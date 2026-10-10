extends GutTest

class Actor extends HumanoidCharacter:
	var speeches: Array[String] = []
	func _ready() -> void:
		for cap in _capabilities.values(): (cap as ActorCapability).ready()
		set_process(false)
		set_physics_process(false)
	func show_world_speech(message: String, _duration := 3.0) -> void: speeches.append(message)

class Town extends Node3D:
	var settlement_definition := SettlementDefinition.new()
	func get_settlement_id() -> String: return "test_city"
	func contains_town_border_position(point: Vector3) -> bool: return point.length() < 30.0

class Sight extends Node:
	func evaluate_observer(_observer: WorldActor, _subject: WorldActor) -> Dictionary: return {"clearly_seen": true}

var previous_context: BootstrapContext
var context: BootstrapContext
var gecs: GecsWorldController
var response: GameCombatResponseSystem
var law: LawOrderController
var factions: FactionController
var city: FactionDefinition
var town: Town
var player: Actor
var guard: Actor

func before_each() -> void:
	previous_context = BootstrapContext.active
	context = BootstrapContext.new(self)
	BootstrapContext.active = context
	gecs = GecsWorldController.new()
	add_child_autofree(gecs)
	context.register(GecsWorldController.SERVICE_ID, gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	response = context.require(GameCombatResponseSystem.SERVICE_ID)
	var query := ActorQueryController.new()
	add_child_autofree(query)
	context.register(ActorQueryController.SERVICE_ID, query)
	query.initialize(context)
	factions = FactionController.new()
	add_child_autofree(factions)
	context.register(FactionController.SERVICE_ID, factions)
	city = load("res://features/factions/resources/factions/canyonites.tres").duplicate(true)
	city.law_profile = city.law_profile.duplicate(true)
	var thugs: FactionDefinition = load("res://features/factions/resources/factions/roaming_desert_thugs.tres")
	factions.faction_definitions = {city.get_id(): city, thugs.get_id(): thugs}
	var alerts := CrimeAlertController.new()
	add_child_autofree(alerts)
	alerts.initialize(context)
	context.register(CrimeAlertController.SERVICE_ID, alerts)
	var sight := Sight.new()
	add_child_autofree(sight)
	context.register(&"perception", sight)
	town = Town.new()
	town.settlement_definition.faction_definition = city
	add_child_autofree(town)
	town.add_to_group("settlement_town")
	law = LawOrderController.new()
	add_child_autofree(law)
	law.set_process(false)
	law._context = context
	law.root_scene = self
	law._actor_query = query
	law._crime_alerts = alerts
	law._combat_responses = response
	response.root_combat_started.connect(law._on_root_combat_started)
	context.register(LawOrderController.SERVICE_ID, law)
	player = actor("player", "Player", true)
	guard = actor("guard", city.get_id())
	guard.add_to_group("faction_soldier")

func after_each() -> void:
	BootstrapContext.active = previous_context

func actor(id: String, faction_id: String, party := false) -> Actor:
	var result := Actor.new()
	result.stable_id = id
	result.faction_name = faction_id
	result.player_party_member = party
	if party:
		WorldActor.set_profile_metadata(result, &"party_id", "party")
	add_child_autofree(result)
	result.add_to_group("world_actor")
	result.add_to_group("npc")
	gecs.register_actor(result, "", {"party_id": "party" if party else ""})
	return result

func test_hostile_raider_is_not_protected_by_city_assault_law() -> void:
	var raider := actor("raider", "roaming_desert_thugs")
	assert_true(law.report_player_assault(player, raider).is_empty())
	assert_true(law.warrants.is_empty())
	assert_true(raider.speeches.is_empty())

func test_city_can_charge_raider_attacking_a_party_member() -> void:
	var raider := actor("raider", "roaming_desert_thugs")
	assert_true(bool(law.assess_attack(raider, player).get("illegal", false)))

func test_repeated_attack_and_maintenance_add_one_charge_and_no_guard_alarm() -> void:
	assert_true(player.assign_attack_target(guard))
	response.process([], [], 0.05)
	assert_true(player.assign_attack_target(guard))
	response.process([], [], 0.05)
	law._process_active_combat_aggressions()
	var record := law.get_warrant_record(player, city.get_id())
	assert_eq((record.get("crimes", []) as Array).size(), 1)
	assert_false(guard.speeches.has("Guards! Assault!"), "An officer does not call for guards like a civilian")

func test_civilian_in_city_can_call_for_guards() -> void:
	var civilian := actor("civilian", city.get_id())
	guard.position = Vector3(100, 0, 0)
	gecs.register_actor(guard)
	law.report_player_assault(player, civilian)
	assert_true(civilian.speeches.has("Guards! Assault!"))

func test_warrior_role_does_not_call_for_guards() -> void:
	var warrior := actor("warrior", city.get_id())
	warrior.set_meta("population_character_type_id", "warrior")
	guard.position = Vector3(100, 0, 0)
	gecs.register_actor(guard)
	law.report_player_assault(player, warrior)
	assert_false(warrior.speeches.has("Guards! Assault!"))

func test_victim_only_law_does_not_authorize_public_arrest() -> void:
	city.law_profile.assault_response = "victim_only"
	var record := law.report_player_assault(player, guard)
	assert_false(record.is_empty())
	assert_false(record.has("latest_response_event_id"), "A private response cannot send the city after the attacker")

func test_arrest_intervention_charges_only_intervening_member() -> void:
	var companion := actor("companion", "Player", true)
	var bystander := actor("bystander", "Player", true)
	response.authorize_response(CGameCombatEvent.Audience.EXPLICIT_ACTORS, player.stable_id, guard.stable_id, "city:warrant", city.get_id(), "test_city", Vector3.ZERO, 20.0, CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT, PackedStringArray([guard.stable_id]))
	response.process([], [], 0.05)
	assert_eq(response.get_response_context(companion.stable_id, guard.stable_id).get("legal_reason", ""), "resisting_arrest", "Authorization must cover the suspect's actual party")
	assert_true(companion.assign_attack_target(guard))
	assert_eq(str(gecs.get_actor_entity(companion).get_component(CGameActorFaction).party_id), "party", "An attack must not discard party identity")
	response.process([], [], 0.05)
	var record := law.get_warrant_record(companion, city.get_id())
	var crimes: Array = record.get("crimes", [])
	assert_eq(crimes.size(), 1)
	if not crimes.is_empty(): assert_eq(crimes[0].crime_type, "resisting_arrest")
	assert_true(law.get_warrant_record(bystander, city.get_id()).is_empty())

func prepare_combat_actor(participant: Actor, position_x: float, stance: int, officer := false) -> void:
	participant.position.x = position_x
	participant.combat_stance = stance
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = CapsuleShape3D.new()
	participant.add_child(shape)
	if officer:
		participant.add_to_group("settlement_authority")
	gecs.register_actor(participant, "test_city" if officer else "")
	gecs.get_actor_entity(participant).get_component(CGameCombatConfig).combat_stance = stance

func combat_components(actors: Array, scripts: Array) -> Array:
	var components: Array = []
	for script in scripts:
		components.append(actors.map(func(participant: Actor): return gecs.get_actor_entity(participant).get_component(script)))
	return components

func step_targeting(actors: Array) -> void:
	var targeting := gecs.find_child("GameCombatTargetingSystem", true, false)
	var entities: Array = actors.map(func(participant: Actor): return gecs.get_actor_entity(participant))
	var components := combat_components(actors, [CGameActorNode, CGameActorIdentity, CGameActorSpatial, CGameActorVitals, CGameActorFaction, CGameCombatConfig, CGameCombatState, CGameCombatSlotState])
	targeting.process(entities, components, 1.0)

func start_acquired_swing(attacker: Actor, target: Actor) -> void:
	assert_eq(attacker.get_current_combat_target(), target, "Production targeting must acquire the opponent without a manual Attack order")
	var components := combat_components([attacker, target], [CGameActorNode, CGameActorIdentity, CGameActorSpatial, CGameActorVitals, CGameCombatConfig, CGameCombatAction, CGameCombatSlotState])
	# Supply a ready, in-reach slot; resolution still checks physical obstruction,
	# starts the real action and publishes its ordinary attack event.
	var slot: CGameCombatSlotState = components[6][0]
	slot.slot_state = CGameCombatSlotState.FightState.FIGHTING
	slot.slot_target_actor_id = target.stable_id
	for pair_slot in components[6]:
		pair_slot.tempo_actor_id = attacker.stable_id
		pair_slot.tempo_wait_remaining = 0.0
	var resolution := gecs.find_child("GameCombatResolutionSystem", true, false)
	resolution._try_start_slot_action(0, components[0], components[1], components[2], components[3], components[4], components[5], components[6], {attacker.stable_id: 0, target.stable_id: 1}, {})
	assert_true(components[5][0].action_active, "The automatic target must produce a real swing")
	response.process([], [], 0.05)
	# End this controlled turn without advancing unrelated actor behavior.
	components[5][0].clear()
	components[5][0].cooldown_remaining = 0.0

func test_automatic_defend_intervention_creates_only_the_helpers_warrant() -> void:
	var companion := actor("companion", "Player", true)
	var passive := actor("passive", "Player", true)
	prepare_combat_actor(guard, 0.0, NpcRules.CombatStance.DEFENSIVE, true)
	prepare_combat_actor(player, 1.0, NpcRules.CombatStance.DEFENSIVE)
	prepare_combat_actor(companion, -1.0, NpcRules.CombatStance.DEFENSIVE)
	prepare_combat_actor(passive, 2.0, NpcRules.CombatStance.PASSIVE)
	var actors := [guard, player, companion, passive]
	assert_false(law.report_crime(player, city.get_id(), "test_city", LawOrderController.CRIME_THEFT, 10, guard, guard).is_empty())
	response.process([], [], 0.05)
	step_targeting(actors)
	assert_eq(guard.get_current_combat_target(), player, "The warrant targets only the suspect")
	assert_null(companion.get_current_combat_target(), "A warrant alone does not recruit the companion")
	start_acquired_swing(guard, player)
	step_targeting(actors)
	assert_eq(companion.get_current_combat_target(), guard, "Defend helps against an officer without asking law for permission")
	assert_null(passive.get_current_combat_target())
	assert_true(law.get_warrant_record(companion, city.get_id()).is_empty(), "Target acquisition is not yet an actual intervention")
	assert_false(response.is_law_enforcement_pair(guard.stable_id, companion.stable_id))
	start_acquired_swing(companion, guard)
	response.process([], [], 0.05) # Consume the warrant's ordinary guard dispatch.
	var crimes: Array = law.get_warrant_record(companion, city.get_id()).get("crimes", [])
	assert_eq(crimes.size(), 1)
	if not crimes.is_empty(): assert_eq(crimes[0].crime_type, LawOrderController.CRIME_RESISTING_ARREST)
	assert_true(response.is_law_enforcement_pair(guard.stable_id, companion.stable_id), "Only actual intervention expands the officer's authority")
	assert_false(response.is_law_enforcement_pair(guard.stable_id, passive.stable_id))
	assert_true(law.get_warrant_record(passive, city.get_id()).is_empty())
	start_acquired_swing(companion, guard)
	assert_eq((law.get_warrant_record(companion, city.get_id()).get("crimes", []) as Array).size(), 1, "Further swings do not duplicate the same resistance incident")
	law._clear_warrant_for_actor(player, city.get_id())
	response.process([], [], 0.05)
	step_targeting(actors)
	assert_false(response.is_law_enforcement_pair(guard.stable_id, player.stable_id))
	assert_true(response.is_law_enforcement_pair(guard.stable_id, companion.stable_id), "Settling the suspect's offense does not erase the helper's separate warrant")
	assert_eq(guard.get_current_combat_target(), companion)
	assert_null(passive.get_current_combat_target())

func test_automatic_defend_swing_against_raider_does_not_charge_party() -> void:
	var companion := actor("companion", "Player", true)
	var raider := actor("raider", "roaming_desert_thugs")
	prepare_combat_actor(player, 1.0, NpcRules.CombatStance.DEFENSIVE)
	prepare_combat_actor(companion, -1.0, NpcRules.CombatStance.DEFENSIVE)
	prepare_combat_actor(raider, 0.0, NpcRules.CombatStance.AGGRESSIVE)
	assert_true(raider.assign_attack_target(player, false))
	response.process([], [], 0.05)
	step_targeting([player, companion, raider])
	start_acquired_swing(companion, raider)
	assert_true(law.get_warrant_record(companion, city.get_id()).is_empty())
	assert_true(law.get_warrant_record(player, city.get_id()).is_empty())
	assert_false(response.is_law_enforcement_pair(guard.stable_id, companion.stable_id))

func test_existing_personal_hostility_is_not_blanket_assault_immunity() -> void:
	guard.mark_hostile(player)
	assert_false(law.report_player_assault(player, guard).is_empty())

func test_body_warning_uses_owner_laws_not_the_city_laws() -> void:
	var ownership := OwnershipController.new()
	add_child_autofree(ownership)
	ownership.initialize(context)
	guard.life_state = NpcRules.LifeState.UNCONSCIOUS
	assert_eq(ownership.get_take_item_color(player, guard), OwnershipController.STEAL_ACTION_COLOR)
	var raider := actor("raider", "roaming_desert_thugs")
	raider.life_state = NpcRules.LifeState.UNCONSCIOUS
	assert_eq(ownership.get_take_item_color(player, raider), Color.TRANSPARENT)

func test_cleared_warrant_ends_response_without_recharging_old_incident() -> void:
	assert_true(player.assign_attack_target(guard))
	response.process([], [], 0.05)
	var warrant := law.get_warrant_record(player, city.get_id())
	var authority_id := str(warrant.get("response_authority_id", ""))
	assert_false(authority_id.is_empty())
	response.authorize_response(CGameCombatEvent.Audience.EXPLICIT_ACTORS, player.stable_id, guard.stable_id, authority_id, city.get_id(), "test_city", Vector3.ZERO, 20.0, CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT, PackedStringArray([guard.stable_id]))
	response.process([], [], 0.05)
	assert_true(response.is_law_enforcement_pair(guard.stable_id, player.stable_id))
	law._clear_warrant_for_actor(player, city.get_id())
	response.process([], [], 0.05)
	law._process_active_combat_aggressions()
	assert_false(response.is_law_enforcement_pair(guard.stable_id, player.stable_id))
	assert_true(law.get_warrant_record(player, city.get_id()).is_empty(), "A resolved incident must not reissue the same charge during maintenance")
	assert_true(player.assign_attack_target(guard))
	response.process([], [], 0.05)
	var new_crimes: Array = law.get_warrant_record(player, city.get_id()).get("crimes", [])
	assert_eq(new_crimes.size(), 1, "Clearing a warrant is not immunity for a new attack")
