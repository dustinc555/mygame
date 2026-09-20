extends "res://tests/validation/test_case.gd"

## Resolution owns damage/pacing; the actor hook only presents the result.
class ReactionActor:
	extends WorldActor
	var reaction_count := 0
	func play_system_combat_hit_reaction(_attacker: Node, _outcome: String, _attack_id: String, _names: PackedStringArray, _critical: bool, _shield: bool, _defend: bool, _damage: float) -> float:
		reaction_count += 1
		return 2.0

const CONTROLLED_ROLL_SEED := 3

var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var context := BootstrapContext.new(scene)
	BootstrapContext.active = context
	var gecs := GecsWorldController.new()
	context.register(GecsWorldController.SERVICE_ID, gecs)
	scene.add_child(gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	var attacker := _actor(scene, "attacker", Vector3.ZERO)
	var defender := _actor(scene, "defender", Vector3(0.9, 0, 0))
	var ally := _actor(scene, "ally", Vector3(3, 0, 0))
	attacker.faction_name = "Aggressors"
	defender.faction_name = "Defenders"
	ally.faction_name = "Defenders"
	for actor in [attacker, defender, ally]:
		gecs.register_actor(actor)
	var entities: Array = [gecs.get_actor_entity(attacker), gecs.get_actor_entity(defender)]
	var components: Array = []
	for script in [gecs.C_NODE, gecs.C_IDENTITY, gecs.C_SPATIAL, gecs.C_VITALS, gecs.C_COMBAT_CONFIG, gecs.C_COMBAT_ACTION, gecs.C_COMBAT_SLOT_STATE]:
		components.append([entities[0].get_component(script), entities[1].get_component(script)])
	var resolution := gecs.find_child("GameCombatResolutionSystem", true, false)
	_expect(resolution.has_signal("impact_resolved"), "Canonical resolution must publish immutable completed-impact attribution for command observers")
	var impacts: Array[Dictionary] = []
	if resolution.has_signal("impact_resolved"):
		resolution.connect("impact_resolved", func(attacker_id: String, target_id: String, sequence: int, outcome: String, damage: float) -> void:
			impacts.append({"attacker_id": attacker_id, "target_id": target_id, "sequence": sequence, "outcome": outcome, "damage": damage})
		)
	var response := context.require(GameCombatResponseSystem.SERVICE_ID) as GameCombatResponseSystem
	var config = components[4][0]
	config.hit_score = 100.0
	config.blunt_damage = 3.0
	config.cut_damage = 0.0
	config.crit_chance = 0.0
	components[4][1].dodge_score = 0.0
	components[4][1].block_score = 0.0
	components[4][1].toughness = 0.0
	seed(CONTROLLED_ROLL_SEED)
	var hit_roll := randf()
	var block_roll := randf()
	_expect(hit_roll > config.crit_chance and hit_roll <= CombatMath.hit_chance(config.hit_score, components[4][1].dodge_score) and block_roll > CombatMath.defense_chance(components[4][1].block_score, config.hit_score), "The native fixture draws must select the intended noncritical, unblocked hit")
	print("CONTROLLED_COMBAT_ROLLS hit=%s block=%s" % [hit_roll, block_roll])
	var slot = components[6][0]
	slot.slot_state = 3
	slot.slot_target_actor_id = defender.stable_id
	slot.slot_index = 0
	slot.engage_distance = 1.03
	slot.leash_distance = 1.88
	slot.tempo_actor_id = attacker.stable_id
	_step_resolution(resolution, entities, components)
	_expect(components[5][0].action_active, "A real slotted attack must start")
	response.process([], [], 0.05)
	var encounters := response.get_active_encounters()
	_expect(encounters.size() == 1, "Attack start must create one GECS encounter")
	if not encounters.is_empty():
		_expect(PackedStringArray(encounters[0].get("defender_side_actor_ids", [])).has(ally.stable_id), "Defender's nearby ally must join through GECS response, not a legacy callback")
	# Falling asleep during windup exercises receive-time wake, not a fabricated API.
	defender.set_sneaking_enabled(true)
	defender.life_state = NpcRules.LifeState.ASLEEP
	components[3][1].life_state = NpcRules.LifeState.ASLEEP
	components[3][1].vitals_seeded = true
	for _tick in range(8):
		_step_resolution(resolution, entities, components)
		if defender.reaction_count > 0:
			break
	_expect(components[3][1].blunt_damage > 0.0, "Impact must damage authoritative GECS vitals")
	_expect(components[3][1].life_state == NpcRules.LifeState.ALIVE, "Receiving an impact must wake canonical sleeping vitals")
	var sync := gecs.find_child("GameActorSyncSystem", true, false)
	var sync_components: Array = []
	for script in [gecs.C_NODE, gecs.C_IDENTITY, gecs.C_FACTION, gecs.C_SETTLEMENT, gecs.C_SPATIAL, gecs.C_VITALS, gecs.C_VITALS_INPUTS]:
		sync_components.append([entities[0].get_component(script), entities[1].get_component(script)])
	sync.process(entities, sync_components, 0.05)
	_expect(defender.life_state == NpcRules.LifeState.ALIVE, "Normal actor sync must present the wake transition")
	_expect(not defender.sneaking, "Receiving an impact must break stealth")
	_expect(attacker.has_hostility_with(defender) and defender.has_hostility_with(attacker), "Impact must establish mutual hostility")
	_expect(defender.reaction_count == 1, "One impact must invoke the presentation hook exactly once")
	_expect(impacts.size() == 1 and impacts[0].attacker_id == attacker.stable_id and impacts[0].target_id == defender.stable_id and float(impacts[0].damage) > 0.0, "Immutable impact attribution must identify the exact resolved positive-damage attack once")
	var reaction = components[5][1]
	_expect(reaction.reaction_remaining > 0.0 and reaction.reaction_remaining <= GameCombatResolutionSystem.MAX_REACTION_HOLD_SECONDS, "GECS must cap the long presentation clip to its stagger budget")
	_expect(reaction.reaction_source_actor_id == attacker.stable_id, "Stagger must retain its attacker identity")
	for _tick in range(12):
		_step_resolution(resolution, entities, components)
	_expect(is_zero_approx(reaction.reaction_remaining) and reaction.reaction_source_actor_id.is_empty(), "Fixed ticks must release reaction hold and source")

	# Protection acquired during a windup must refuse impact and conserve wounds.
	for _tick in range(30):
		if not components[5][0].action_active and not components[5][1].action_active:
			break
		_step_resolution(resolution, entities, components)
	components[5][1].cooldown_remaining = 10.0
	components[5][0].cooldown_remaining = 0.0
	slot.tempo_actor_id = attacker.stable_id
	slot.tempo_wait_remaining = 0.0
	_step_resolution(resolution, entities, components)
	_expect(components[5][0].action_active, "Protected-at-impact case must begin an actual swing")
	var wounds_before: float = components[3][1].blunt_damage
	var impacts_before_protection := impacts.size()
	defender.get_legal_status().is_prisoner = true
	for _tick in range(10):
		_step_resolution(resolution, entities, components)
	_expect(is_equal_approx(components[3][1].blunt_damage, wounds_before), "Protection acquired during windup must prevent damage")
	_expect(impacts.size() == impacts_before_protection, "A protected refused swing must not publish completed-impact attribution")

	# The registered authorization, not an actor callback, defines arrest damage.
	defender.get_legal_status().is_prisoner = false
	response.authorize_response(CGameCombatEvent.Audience.EXPLICIT_ACTORS, defender.stable_id, ally.stable_id, "validation.warrant", attacker.faction_name, "", Vector3.ZERO, 40.0, CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT, PackedStringArray([attacker.stable_id]))
	response.process([], [], 0.05)
	_expect(response.has_active_authority_response("validation.warrant", defender.stable_id), "Nonlethal case must have a live typed law authorization")
	slot.slot_state = 0
	for _tick in range(30):
		_step_resolution(resolution, entities, components)
	slot.slot_state = 3
	config.blunt_damage = 2000.0
	config.cut_damage = 2000.0
	components[5][0].cooldown_remaining = 0.0
	slot.tempo_actor_id = attacker.stable_id
	slot.tempo_wait_remaining = 0.0
	var blood_before: float = components[3][1].blood
	var reactions_before := defender.reaction_count
	for _tick in range(12):
		_step_resolution(resolution, entities, components)
		if defender.reaction_count > reactions_before:
			break
	_expect(defender.reaction_count > reactions_before, "Arrest case must land a real slotted impact")
	var arrested = components[3][1]
	print("LAW_DAMAGE_CANONICAL hp=%.3f blunt=%.3f cut=%.3f blood=%.3f state=%d" % [arrested.hp, arrested.blunt_damage, arrested.open_cut_damage, arrested.blood, arrested.life_state])
	_expect(arrested.life_state == NpcRules.LifeState.UNCONSCIOUS, "An overwhelming law hit must knock out, never kill or enter dying")
	_expect(arrested.hp > -arrested.max_hp and arrested.hp <= 0.0, "Canonical arrest damage must stop above the death threshold")
	_expect(is_zero_approx(arrested.open_cut_damage) and is_equal_approx(arrested.blood, blood_before), "Law damage must convert cutting force to blunt without bleeding")

	var uninvolved := _actor(scene, "uninvolved", Vector3(2.0, 0.0, 0.0))
	uninvolved.faction_name = "Neutral"
	gecs.register_actor(uninvolved)
	_expect(str(response.get_response_context(uninvolved.stable_id, attacker.stable_id).get("encounter_id", "")).is_empty(), "Cross-encounter retaliation fixture must start outside the officer's encounter")
	response.authorize_response(CGameCombatEvent.Audience.EXPLICIT_ACTORS, uninvolved.stable_id, attacker.stable_id, "validation.reply", attacker.faction_name, "", Vector3.ZERO, 40.0, CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT, PackedStringArray([attacker.stable_id]))
	response.process([], [], 0.05)
	_expect(bool(response.get_response_context(attacker.stable_id, uninvolved.stable_id).get("authorized_response", false)), "An explicit law responder must remain authorized outside a shared encounter")
	_expect(int(response.get_response_context(uninvolved.stable_id, attacker.stable_id).get("response_depth", 0)) == 1, "Retaliation against the active law responder must be lawful without a shared encounter")
	_assert_physical_law_retaliation(scene, gecs, resolution, response)
	scene.queue_free()
	await process_frame
	BootstrapContext.active = null
	for failure in _failures:
		push_error(failure)
	print("SYSTEM_COMBAT_CORRECTNESS_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)

func _assert_physical_law_retaliation(scene: Node, gecs: GecsWorldController, resolution: Node, response: GameCombatResponseSystem) -> void:
	var officer := _actor(scene, "physical.officer", Vector3(10.0, 0.0, 0.0))
	var suspect := _actor(scene, "physical.suspect", Vector3(10.9, 0.0, 0.0))
	officer.faction_name = "Officers"
	suspect.faction_name = "Suspects"
	gecs.register_actor(officer)
	gecs.register_actor(suspect)
	var entities: Array = [gecs.get_actor_entity(officer), gecs.get_actor_entity(suspect)]
	var components: Array = []
	for script in [gecs.C_NODE, gecs.C_IDENTITY, gecs.C_SPATIAL, gecs.C_VITALS, gecs.C_COMBAT_CONFIG, gecs.C_COMBAT_ACTION, gecs.C_COMBAT_SLOT_STATE]:
		components.append([entities[0].get_component(script), entities[1].get_component(script)])
	for config in components[4]:
		config.hit_score = 100.0
		config.blunt_damage = 1.0
		config.cut_damage = 0.0
		config.crit_chance = 0.0
		config.dodge_score = 0.0
		config.block_score = 0.0
		config.toughness = 0.0
	var crimes: Array[String] = []
	response.root_combat_started.connect(func(actor_id: String, _target_id: String, _origin: Vector3, _encounter_id: String) -> void: crimes.append(actor_id))
	response.authorize_response(CGameCombatEvent.Audience.EXPLICIT_ACTORS, suspect.stable_id, officer.stable_id, "physical.warrant", officer.faction_name, "", officer.global_position, 40.0, CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT, PackedStringArray([officer.stable_id]))
	response.process([], [], 0.05)
	var officer_slot = components[6][0]
	officer_slot.slot_state = 3
	officer_slot.slot_target_actor_id = suspect.stable_id
	officer_slot.tempo_actor_id = officer.stable_id
	officer_slot.engage_distance = 1.03
	officer_slot.leash_distance = 1.88
	for _tick in range(30):
		_step_resolution(resolution, entities, components)
		response.process([], [], 0.05)
		if suspect.reaction_count > 0:
			break
	_expect(components[3][1].blunt_damage > 0.0, "An actual authorized officer impact must precede the retaliation test")
	_expect(not crimes.has(officer.stable_id), "The physical authorized officer attack must not emit unlawful root aggression")
	officer_slot.slot_state = 0
	var reply_slot = components[6][1]
	reply_slot.slot_state = 3
	reply_slot.slot_target_actor_id = officer.stable_id
	reply_slot.tempo_actor_id = suspect.stable_id
	reply_slot.engage_distance = 1.03
	reply_slot.leash_distance = 1.88
	for _tick in range(50):
		_step_resolution(resolution, entities, components)
		response.process([], [], 0.05)
		if officer.reaction_count > 0:
			break
	_expect(components[3][0].blunt_damage > 0.0, "The suspect must complete an actual physical retaliatory impact")
	_expect(not crimes.has(suspect.stable_id), "Legal response depth must survive physical impact event processing without a new root crime")
	_expect(response.get_response_depth(suspect.stable_id, officer.stable_id) == 1 and response.is_law_enforcement_pair(officer.stable_id, suspect.stable_id), "Physical retaliation must retain both response depth and the original exact law authorization")
	print("LAWFUL_RETALIATION_TRACE officer=%s suspect=%s officer_wounds=%.3f suspect_wounds=%.3f response_depth=%d roots=%s" % [officer.stable_id, suspect.stable_id, components[3][0].blunt_damage, components[3][1].blunt_damage, response.get_response_depth(suspect.stable_id, officer.stable_id), crimes])


func _step_resolution(resolution: Node, entities: Array, components: Array) -> void:
	# This synchronous fixture tests damage/law, not hit probability. Each tick
	# starts with the verified native draws; never retry an attack until it hits.
	seed(CONTROLLED_ROLL_SEED)
	resolution.process(entities, components, 0.05)


func _actor(scene: Node, actor_id: String, position: Vector3) -> ReactionActor:
	var actor := ReactionActor.new()
	actor.name = actor_id
	actor.stable_id = actor_id
	actor.position = position
	scene.add_child(actor)
	actor.set_physics_process(false)
	return actor

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
