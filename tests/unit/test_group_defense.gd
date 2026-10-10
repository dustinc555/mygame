extends GutTest

var previous_context: BootstrapContext
var context: BootstrapContext
var gecs: GecsWorldController
var response: GameCombatResponseSystem
var roots: Array[Dictionary] = []

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
	roots.clear()
	response.root_combat_started.connect(func(attacker: String, victim: String, _origin: Vector3, _incident: String): roots.append({"attacker": attacker, "victim": victim}))

func after_each() -> void:
	BootstrapContext.active = previous_context

func actor(id: String, faction_id: String, party_id := "", squad := "", position_x := 0.0) -> WorldActor:
	var result := WorldActor.new()
	result.stable_id = id
	result.faction_name = faction_id
	result.squad_name = squad
	WorldActor.set_profile_metadata(result, &"party_id", party_id)
	add_child_autofree(result)
	result.position.x = position_x
	result.set_process(false)
	result.set_physics_process(false)
	gecs.register_actor(result)
	var faction = gecs.get_actor_entity(result).get_component(CGameActorFaction)
	faction.party_id = party_id
	faction.squad_name = squad
	return result

func attack(attacker: WorldActor, victim: WorldActor) -> void:
	response.emit_attack_started(attacker.stable_id, victim.stable_id, victim.global_position, 0)
	response.process([], [], 0.05)

func authorize(guard: WorldActor, suspect: WorldActor) -> void:
	response.authorize_response(CGameCombatEvent.Audience.EXPLICIT_ACTORS, suspect.stable_id, guard.stable_id, "city:warrant", "city", "city_town", guard.global_position, 20.0, CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT, PackedStringArray([guard.stable_id]))
	response.process([], [], 0.05)

func test_remote_party_member_can_defend_against_attacking_squad() -> void:
	var raider := actor("raider", "thugs", "", "raid")
	var other_raider := actor("other_raider", "thugs", "", "raid", 100.0)
	var friend := actor("friend", "player", "party")
	var companion := actor("companion", "player", "party", "", 100.0)
	attack(raider, friend)
	assert_eq(response.get_response_depth(companion.stable_id, other_raider.stable_id), 1, "Defense follows groups, not proximity or encounter placement")
	attack(companion, other_raider)
	assert_eq(roots.size(), 1, "Defending another party member is not a new aggression")

func test_group_defense_does_not_cover_unrelated_member_of_same_faction() -> void:
	var raider := actor("raider", "thugs", "", "raid")
	var unrelated := actor("unrelated", "thugs", "", "other_camp", 100.0)
	var friend := actor("friend", "player", "party")
	var companion := actor("companion", "player", "party", "", 100.0)
	attack(raider, friend)
	assert_eq(response.get_response_depth(companion.stable_id, unrelated.stable_id), 0)

func test_group_defense_survives_the_attacked_friend_going_down() -> void:
	var raider := actor("raider", "thugs", "", "raid")
	var friend := actor("friend", "player", "party")
	var companion := actor("companion", "player", "party", "", 100.0)
	attack(raider, friend)
	gecs.get_actor_entity(friend).get_component(CGameActorVitals).life_state = NpcRules.LifeState.UNCONSCIOUS
	response.process([], [], 0.05)
	assert_eq(response.get_response_depth(companion.stable_id, raider.stable_id), 1)

func test_arrest_is_not_defense_for_suspect_or_companion() -> void:
	var guard := actor("guard", "city")
	var suspect := actor("suspect", "player", "party")
	var companion := actor("companion", "player", "party", "", 100.0)
	authorize(guard, suspect)
	attack(guard, suspect)
	for defender in [suspect, companion]:
		var reason := response.get_response_context(defender.stable_id, guard.stable_id)
		assert_eq(reason.get("legal_reason", ""), "resisting_arrest")
		assert_eq(int(reason.get("response_depth", 0)), 0)
		assert_eq(reason.get("authority_faction_id", ""), "city")
	assert_false(response.is_law_enforcement_pair(guard.stable_id, companion.stable_id), "Party membership alone does not authorize arrest")
	attack(companion, guard)
	assert_eq(roots.size(), 1, "Only the intervening companion committed new aggression")

func test_attack_order_records_initiative_before_first_swing() -> void:
	var raider := actor("raider", "thugs", "", "raid")
	var friend := actor("friend", "player", "party")
	assert_true(raider.assign_attack_target(friend, false))
	assert_true(friend.assign_attack_target(raider))
	response.process([], [], 0.05)
	assert_eq(roots.size(), 1)
	if roots.size() == 1:
		assert_eq(roots[0].attacker, "raider")
		assert_eq(roots[0].victim, "friend")
	assert_true(friend.assign_attack_target(raider))
	response.process([], [], 0.05)
	assert_eq(roots.size(), 1, "Repeated Attack does not restart the incident")

func test_guard_targets_only_offenders_authorized_by_its_own_warrants() -> void:
	var targeting := GameCombatTargetingSystem.new()
	var intent := CGameCombatResponseIntent.new()
	intent.responder_actor_id = "guard"
	intent.target_actor_id = "suspect"
	intent.kind = CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT
	var unrelated := CGameCombatResponseIntent.new()
	unrelated.responder_actor_id = "other_guard"
	unrelated.target_actor_id = "unrelated"
	unrelated.kind = CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT
	var candidates := targeting._build_law_candidates_by_actor({"guard": [intent], "other_guard": [unrelated]})
	assert_eq(candidates.get("guard", {}), {"suspect": true}, "Encounter sides cannot issue warrants")
	targeting.free()

func step_targeting(actors: Array) -> void:
	var targeting := gecs.find_child("GameCombatTargetingSystem", true, false)
	var entities: Array = actors.map(func(value: WorldActor): return gecs.get_actor_entity(value))
	var components: Array = []
	for script in [CGameActorNode, CGameActorIdentity, CGameActorSpatial, CGameActorVitals, CGameActorFaction, CGameCombatConfig, CGameCombatState, CGameCombatSlotState]:
		components.append(entities.map(func(entity): return entity.get_component(script)))
	targeting.process(entities, components, 1.0)

func defensive_party_member(id: String, position_x: float) -> WorldActor:
	var member := actor(id, "player", "party", "", position_x)
	member.combat_stance = NpcRules.CombatStance.DEFENSIVE
	member.player_party_member = true
	var entity: Entity = gecs.get_actor_entity(member)
	assert_eq(entity.get_component(CGameActorFaction).party_id, "party")
	assert_eq(entity.get_component(CGameActorFaction).combat_stance, NpcRules.CombatStance.DEFENSIVE)
	entity.get_component(CGameCombatConfig).combat_stance = NpcRules.CombatStance.DEFENSIVE
	return member

func test_nearby_defend_party_member_automatically_targets_friends_attacker() -> void:
	var friend := defensive_party_member("friend", 0.0)
	var companion := defensive_party_member("companion", 2.0)
	var raider := actor("raider", "thugs", "", "raid", 1.0)
	step_targeting([friend, companion, raider])
	var state: CGameCombatState = gecs.get_actor_entity(companion).get_component(CGameCombatState)
	assert_eq(state.system_target_actor_id, "", "Defend must not initiate a fight")
	assert_true(state.personal_hostile_actor_ids.is_empty(), "Companion has not personally been attacked")
	attack(raider, friend)
	step_targeting([friend, companion, raider])
	assert_eq(state.system_target_actor_id, raider.stable_id, "Nearby Defend companion must automatically help their attacked friend")
	assert_eq(companion.get_current_combat_target(), raider, "The real actor must receive the automatically acquired target")
	assert_eq(state.commanded_target_actor_id, "", "Helping must not require a manual Attack command")

func test_defend_party_helps_when_attacker_switches_from_a_third_faction_fight() -> void:
	var friend := defensive_party_member("friend", 0.0)
	var companion := defensive_party_member("companion", 2.0)
	var raider := actor("raider", "thugs", "", "raid", 1.0)
	var third_faction := actor("third_faction", "cinder", "", "cinder_pack", 3.0)
	attack(raider, third_faction)
	step_targeting([friend, companion, raider, third_faction])
	var state: CGameCombatState = gecs.get_actor_entity(companion).get_component(CGameCombatState)
	assert_eq(state.system_target_actor_id, "", "An unrelated fight must not recruit the party")
	attack(raider, friend)
	step_targeting([friend, companion, raider, third_faction])
	assert_eq(state.system_target_actor_id, raider.stable_id, "An existing encounter must not prevent aid to a newly attacked party")
	assert_eq(companion.get_current_combat_target(), raider, "Companion must actually engage without being personally attacked")
	assert_eq(response.get_response_depth(companion.stable_id, raider.stable_id), 1)
	assert_eq(state.commanded_target_actor_id, "")

func test_defend_companion_helps_against_an_authorized_officer() -> void:
	var guard := actor("guard", "city")
	var suspect := defensive_party_member("suspect", 0.0)
	var companion := defensive_party_member("companion", 2.0)
	authorize(guard, suspect)
	step_targeting([guard, suspect, companion])
	assert_eq(gecs.get_actor_entity(guard).get_component(CGameCombatState).system_target_actor_id, "suspect")
	assert_null(companion.get_current_combat_target(), "A warrant alone is not an attack on the friend")
	attack(guard, suspect)
	step_targeting([guard, suspect, companion])
	assert_eq(gecs.get_actor_entity(guard).get_component(CGameCombatState).system_target_actor_id, "suspect")
	assert_eq(gecs.get_actor_entity(companion).get_component(CGameCombatState).system_target_actor_id, "guard", "Defend helps even when the intervention is illegal")
	assert_eq(companion.get_current_combat_target(), guard, "Officer authority must not suppress automatic assistance")
	assert_eq(response.get_response_context(companion.stable_id, guard.stable_id).get("legal_reason", ""), "resisting_arrest", "Helping and legal justification are independent")
	assert_false(response.is_law_enforcement_pair(guard.stable_id, companion.stable_id), "Acquiring a target alone must not issue a warrant")

func test_passive_companion_stays_out_when_an_officer_attacks_their_friend() -> void:
	var guard := actor("guard", "city")
	var suspect := defensive_party_member("suspect", 0.0)
	var companion := defensive_party_member("companion", 2.0)
	companion.combat_stance = NpcRules.CombatStance.PASSIVE
	gecs.get_actor_entity(companion).get_component(CGameCombatConfig).combat_stance = NpcRules.CombatStance.PASSIVE
	authorize(guard, suspect)
	attack(guard, suspect)
	step_targeting([guard, suspect, companion])
	assert_null(companion.get_current_combat_target(), "Passive stays out regardless of the attacker's authority")
	assert_eq(gecs.get_actor_entity(companion).get_component(CGameCombatState).system_target_actor_id, "")
	assert_false(response.is_law_enforcement_pair(guard.stable_id, companion.stable_id))

func test_defend_companion_joins_after_an_earlier_attack_by_their_friend() -> void:
	var friend := defensive_party_member("friend", 0.0)
	var companion := defensive_party_member("companion", 2.0)
	var raider := actor("raider", "thugs", "", "raid", 1.0)
	attack(friend, raider)
	step_targeting([friend, companion, raider])
	assert_null(companion.get_current_combat_target(), "Defend does not join the initial offensive order")
	attack(raider, friend)
	step_targeting([friend, companion, raider])
	assert_eq(companion.get_current_combat_target(), raider, "A real counterattack must wake nearby defenders")

func test_defend_companion_outside_alert_range_does_not_join() -> void:
	var friend := defensive_party_member("friend", 0.0)
	var companion := defensive_party_member("companion", NpcRules.NPC_ALERT_PROXIMITY_RADIUS + 1.0)
	var raider := actor("raider", "thugs", "", "raid", 1.0)
	var third_faction := actor("third_faction", "cinder", "", "pack", 3.0)
	attack(raider, third_faction)
	attack(raider, friend)
	step_targeting([friend, companion, raider, third_faction])
	assert_null(companion.get_current_combat_target(), "Legal group defense is not a remote combat order")

func test_passive_companion_does_not_join_third_party_attack() -> void:
	var friend := defensive_party_member("friend", 0.0)
	var companion := defensive_party_member("companion", 2.0)
	companion.combat_stance = NpcRules.CombatStance.PASSIVE
	gecs.get_actor_entity(companion).get_component(CGameCombatConfig).combat_stance = NpcRules.CombatStance.PASSIVE
	var raider := actor("raider", "thugs", "", "raid", 1.0)
	var third_faction := actor("third_faction", "cinder", "", "pack", 3.0)
	attack(raider, third_faction)
	attack(raider, friend)
	step_targeting([friend, companion, raider, third_faction])
	assert_null(companion.get_current_combat_target())

func test_defend_assistance_preserves_explicit_movement_orders() -> void:
	var friend := defensive_party_member("friend", 0.0)
	var companion := defensive_party_member("companion", 2.0)
	companion.set_active_player_order(true)
	gecs.get_actor_entity(companion).get_component(CGameActorFaction).player_order_active = true
	var raider := actor("raider", "thugs", "", "raid", 1.0)
	var third_faction := actor("third_faction", "cinder", "", "pack", 3.0)
	attack(raider, third_faction)
	attack(raider, friend)
	step_targeting([friend, companion, raider, third_faction])
	assert_null(companion.get_current_combat_target())
	assert_true(companion.has_active_player_order())

func test_defend_assistance_releases_a_removed_attacker() -> void:
	var friend := defensive_party_member("friend", 0.0)
	var companion := defensive_party_member("companion", 2.0)
	var raider := actor("raider", "thugs", "", "raid", 1.0)
	var third_faction := actor("third_faction", "cinder", "", "pack", 3.0)
	attack(raider, third_faction)
	attack(raider, friend)
	step_targeting([friend, companion, raider, third_faction])
	assert_eq(companion.get_current_combat_target(), raider)
	raider.free()
	response.process([], [], 0.05)
	step_targeting([friend, companion, third_faction])
	assert_null(companion.get_current_combat_target(), "Do not retain a vanished attacker or redirect at the unrelated third faction")
	var returned_raider := actor("raider", "thugs", "", "raid", 1.0)
	attack(returned_raider, friend)
	step_targeting([friend, companion, returned_raider, third_faction])
	assert_eq(companion.get_current_combat_target(), returned_raider, "Fresh aggression after projection replacement must recruit help again")

func test_defend_companion_rejoins_after_projection_replacement() -> void:
	var friend := defensive_party_member("friend", 0.0)
	var companion := defensive_party_member("companion", 2.0)
	var raider := actor("raider", "thugs", "", "raid", 1.0)
	var third_faction := actor("third_faction", "cinder", "", "pack", 3.0)
	attack(raider, third_faction)
	attack(raider, friend)
	step_targeting([friend, companion, raider, third_faction])
	assert_eq(companion.get_current_combat_target(), raider)
	companion.free()
	response.process([], [], 0.05)
	var returned_companion := defensive_party_member("companion", 2.0)
	attack(raider, friend)
	step_targeting([friend, returned_companion, raider, third_faction])
	assert_eq(returned_companion.get_current_combat_target(), raider, "An ongoing attack must wake the replacement companion without a manual command")

func test_revocation_ends_arrest_targeting_without_erasing_unrelated_defense() -> void:
	var guard := actor("guard", "city")
	var suspect := actor("suspect", "player", "party")
	var raider := actor("raider", "thugs", "", "raid", 100.0)
	var friend := actor("friend", "player", "party", "", 100.0)
	attack(raider, friend)
	attack(suspect, guard)
	authorize(guard, suspect)
	attack(guard, suspect)
	step_targeting([guard, suspect, raider, friend])
	assert_eq(gecs.get_actor_entity(guard).get_component(CGameCombatState).system_target_actor_id, "suspect")
	var action: CGameCombatAction = gecs.get_actor_entity(guard).get_component(CGameCombatAction)
	action.action_active = true
	action.action_target_actor_id = suspect.stable_id
	response.revoke_response("city:warrant", "suspect")
	response.process([], [], 0.05)
	step_targeting([guard, suspect, raider, friend])
	assert_eq(gecs.get_actor_entity(guard).get_component(CGameCombatState).system_target_actor_id, "", "Revoked arrest must not persist as ordinary combat")
	assert_ne(gecs.get_actor_entity(suspect).get_component(CGameCombatState).system_target_actor_id, "guard", "The old assault encounter must not restart settled combat")
	assert_false(action.action_active, "Revocation cancels an in-flight arrest swing")
	assert_eq(response.get_response_depth(suspect.stable_id, raider.stable_id), 1, "Revoking one warrant cannot erase an unrelated raid")

func test_revocation_is_visible_to_later_attack_in_same_event_batch() -> void:
	var guard := actor("guard", "city")
	var suspect := actor("suspect", "player", "party")
	authorize(guard, suspect)
	response.revoke_response("city:warrant", "suspect")
	attack(guard, suspect)
	assert_eq(roots.size(), 1, "A former officer cannot attack under already revoked authority")

func test_uncommitted_companion_does_not_join_an_assault_on_guard() -> void:
	var guard := actor("guard", "city")
	var suspect := actor("suspect", "player", "party")
	var companion := actor("companion", "player", "party")
	attack(suspect, guard)
	authorize(guard, suspect)
	step_targeting([guard, suspect, companion])
	assert_eq(gecs.get_actor_entity(companion).get_component(CGameCombatState).system_target_actor_id, "", "Shared party membership is not an order to assist an aggressor")
