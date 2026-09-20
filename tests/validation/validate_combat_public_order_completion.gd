extends "res://tests/validation/test_case.gd"

## Small real-scene command-path probe, not a substitute for the 20v20 FPS gate.
const FIXTURE = preload("res://tests/validation/helpers/combat_fixture.gd")
var _world: Node3D
var _gecs: GecsWorldController
var _failures: Array[String] = []
var _impacts: Array[Dictionary] = []
var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_world = Node3D.new()
	_world.name = "PublicCombatOrders"
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80.0, 1.0, 80.0)
	floor_shape.shape = shape
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	_world.add_child(floor_body)
	var party_root := Node3D.new()
	party_root.name = "PartyMembers"
	_world.add_child(party_root)
	var party := PartyManager.new()
	party.name = "PartyManager"
	_world.add_child(party)
	var rig := Node3D.new()
	rig.name = "CameraRig"
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(-4.0, 12.0, 12.0)
	camera.current = true
	pivot.add_child(camera)
	rig.add_child(pivot)
	_world.add_child(rig)
	var bootstrap := preload("res://features/core/game_bootstrap.gd").new()
	bootstrap.name = "GameBootstrap"
	_world.add_child(bootstrap)
	root.add_child(_world)
	camera.look_at(Vector3(-4.0, 0.0, 0.0))
	if not await _wait_for(func() -> bool: return BootstrapContext.service(GecsWorldController.SERVICE_ID) != null, 3.0):
		_expect(false, "The normal GameBootstrap scene must initialize its services")
		await _finish()
		return
	_gecs = BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var attacker := preload("res://features/core/party/party_member.tscn").instantiate() as PartyMember
	var carrier := preload("res://features/core/party/party_member.tscn").instantiate() as PartyMember
	var enemy := FactionHumanoid.new()
	var body := FactionHumanoid.new()
	var decoy := FactionHumanoid.new()
	var actors: Array[WorldActor] = [attacker, carrier, enemy, body, decoy]
	# A script-only humanoid has no standing collider. Reuse the authored
	# actor capsule so approach/carry tests run on the floor, not in free fall.
	var actor_template := preload("res://features/core/party/party_member.tscn").instantiate()
	for actor in [enemy, body, decoy]:
		actor.add_child(actor_template.get_node("CollisionShape3D").duplicate())
	actor_template.free()
	var positions: Array[Vector3] = [Vector3(-8.0, 0.6, 0.0), Vector3(-6.0, 0.6, 5.0), Vector3(0.0, 0.6, 0.0), Vector3(0.0, 0.6, 5.0), Vector3(-7.0, 0.6, 1.0)]
	for index in range(actors.size()):
		var actor := actors[index]
		actor.name = "OrderActor%d" % index
		actor.stable_id = "validation.public_order.%d" % index
		actor.faction_name = "Party" if index < 2 else "ValidationOpponents"
		actor.hostile_factions = PackedStringArray()
		actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE if index == 0 else NpcRules.CombatStance.PASSIVE
		actor.position = positions[index]
		_world.add_child(actor)
	carrier.get_stats().set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, 80)
	if not await _wait_for(func() -> bool: return _gecs.get_actor_entity(body) != null and _gecs.get_actor_entity(attacker) != null and _gecs.get_actor_entity(carrier) != null and _gecs.get_actor_entity(enemy) != null, 3.0):
		_expect(false, "All command participants must be registered real actors")
		await _finish()
		return
	# Arrange a persistent, fully wounded corpse in canonical vitals. This test
	# does not use or claim to validate force_kill, which has separate ownership.
	var body_entity = _gecs.get_actor_entity(body)
	var body_vitals = body_entity.get_component(_gecs.C_VITALS)
	var body_inputs = body_entity.get_component(_gecs.C_VITALS_INPUTS)
	body_vitals.blunt_damage = body_vitals.max_hp * 2.0
	VitalsStateMachine.recalculate(body_vitals, body_inputs.toughness)
	body_vitals.life_state = NpcRules.LifeState.DEAD
	body_vitals.vitals_seeded = true
	_expect(await _wait_for(func() -> bool: return body.life_state == NpcRules.LifeState.DEAD, 2.0), "Canonical dead-body setup must reach the real projection")
	var resolution := _gecs.find_child("GameCombatResolutionSystem", true, false)
	_expect(resolution != null and resolution.has_signal("impact_resolved"), "Command completion needs authoritative impact attribution")
	if resolution != null and resolution.has_signal("impact_resolved"):
		resolution.connect("impact_resolved", func(attacker_id: String, target_id: String, sequence: int, outcome: String, damage: float) -> void:
			_impacts.append({"attacker_id": attacker_id, "target_id": target_id, "sequence": sequence, "outcome": outcome, "damage": damage})
		)
	var move_start := attacker.global_position
	attacker.set_move_target(attacker.get_floor_aligned_origin_position(Vector3(-12.0, 0.0, 0.0)), true)
	_expect(await _wait_for(func() -> bool: return attacker.global_position.x < move_start.x - 0.3, 2.0), "The initial public move must physically start before attack preemption")
	_expect(attacker.has_active_player_order(), "The attack must preempt an actual active movement order")
	var action = _gecs.get_actor_entity(attacker).get_component(_gecs.C_COMBAT_ACTION)
	var before_sequence: int = action.action_sequence
	enemy.get_legal_status().is_prisoner = true
	_expect(not attacker.assign_attack_target(enemy) and attacker.has_move_target() and attacker.has_active_player_order(), "A refused protected-target attack must preserve the prior public move")
	enemy.get_legal_status().is_prisoner = false
	attacker.mark_hostile(decoy)
	_expect(attacker.assign_attack_target(enemy), "The public attack command must be accepted")
	_expect(not attacker.has_move_target(), "The attack must cancel the old movement destination, not resume it after combat")
	print("PUBLIC_ORDER_TRACE attack_issued=%s target=%s" % [_snapshot(attacker), _snapshot(enemy)])
	var enemy_vitals = _gecs.get_actor_entity(enemy).get_component(_gecs.C_VITALS)
	# The impact event precedes the actor-view sync. Require both within the
	# original deadline, rather than reading the view immediately after impact.
	var impacted := await _wait_for(func() -> bool:
		for impact in _impacts:
			if impact.attacker_id == attacker.stable_id and impact.target_id == enemy.stable_id and int(impact.sequence) > before_sequence and float(impact.damage) > 0.0:
				return VitalsMath.total_wound_damage(enemy_vitals.blunt_damage, enemy_vitals.open_cut_damage, enemy_vitals.bandaged_cut_damage) > 0.0 and enemy.get_total_wound_damage() > 0.0
		return false
	, 12.0)
	_expect(impacted, "A new commanded attack must reach canonical damage on the exact target, not just acquisition")
	_expect(not _impacts.any(func(impact: Dictionary) -> bool: return impact.attacker_id == attacker.stable_id and impact.target_id == decoy.stable_id), "A nearer hostile must not steal an explicit attack command")
	print("PUBLIC_ORDER_TRACE attack_final=%s target=%s impacts=%s" % [_snapshot(attacker), _snapshot(enemy), _impacts])
	attacker.set_move_target(_floor_origin(attacker, attacker.global_position + Vector3(-2.0, 0.0, 0.0)), true)
	_expect(str(_gecs.get_actor_entity(attacker).get_component(_gecs.C_COMBAT_STATE).commanded_target_actor_id).is_empty(), "A replacing public move must clear exact attack intent")
	# Independent carrier exercises the carry order without depending on combat.
	carrier.assign_carry_target(body)
	print("PUBLIC_ORDER_TRACE carry_issued=%s target=%s" % [_snapshot(carrier), _snapshot(body)])
	var attached := await _wait_for(func() -> bool: return carrier.get_carry().get_carried_character() == body and body.get_carry().get_carrier() == carrier, 10.0)
	_expect(attached, "The public carry command must establish both actual carry links")
	if attached:
		await physics_frame
		var view := body.get_body_projection() as HumanoidBodyProjection
		var expected := CarryPoseSolver.solve_carried_transform(carrier.get_body_projection(), carrier, carrier.get_carry().carry_pose_profile, view, body)
		_expect(view != null and not view.is_ragdoll_active() and body.global_position.distance_to(expected.origin) <= 0.2 and body.global_basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion()) <= 0.1, "The carried body must occupy its real solved visual pose")
		print("PUBLIC_CARRY_POSE body=%s expected=%s" % [body.global_transform, expected])
		var destination := _floor_origin(carrier, carrier.global_position + Vector3(3.0, 0.0, 0.0))
		carrier.set_move_target(destination, true)
		var arrived := await _wait_for(func() -> bool: return not carrier.has_move_target() and carrier.global_position.distance_to(destination) <= 1.0, 6.0)
		_expect(arrived and carrier.get_carry().get_carried_character() == body, "The carrier must complete movement without losing the body")
		carrier.drop_carried_character()
		await physics_frame
		_expect(carrier.get_carry().get_carried_character() == null and body.get_carry().get_carrier() == null, "Public drop must clear both carry links")
		_expect(body.life_state == NpcRules.LifeState.DEAD, "Carrying and dropping must not revive a corpse")
		_expect(body.global_position.distance_to(_floor_origin(body, body.global_position)) <= 0.2 and body.global_position.distance_to(carrier.global_position) <= carrier.interact_distance, "Completed drop must leave the exact body grounded beside its carrier")
	print("PUBLIC_ORDER_TRACE carry_final=%s target=%s" % [_snapshot(carrier), _snapshot(body)])
	await _finish()

func _floor_origin(actor: WorldActor, position: Vector3) -> Vector3:
	# This fixture's floor surface is y=0. The actor helper converts a floor
	# point to a capsule origin; it does not raycast an already-aligned origin.
	return actor.get_floor_aligned_origin_position(Vector3(position.x, 0.0, position.z))

func _wait_for(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await physics_frame
	return bool(predicate.call())

func _snapshot(actor: WorldActor) -> Dictionary:
	if not is_instance_valid(actor):
		return {"valid": false}
	var result := {"id": actor.stable_id, "life": actor.life_state, "position": actor.global_position, "order": actor.get_current_order_type(), "player_order": actor.has_active_player_order(), "moving": actor.has_move_target(), "carrying": actor.is_carrying_someone()}
	var entity = _gecs.get_actor_entity(actor)
	if entity != null:
		var state = entity.get_component(_gecs.C_COMBAT_STATE)
		var action = entity.get_component(_gecs.C_COMBAT_ACTION)
		result["target"] = state.system_target_actor_id
		result["action"] = {"active": action.action_active, "sequence": action.action_sequence, "target": action.action_target_actor_id, "impacted": action.action_has_impacted}
	return result

func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		print("PUBLIC_ORDER_ASSERTION_FAILED: %s" % message)

func _finish() -> void:
	await FIXTURE.release_world(_world, get_tree())
	for failure in _failures:
		push_error(failure)
	print("PUBLIC_COMBAT_ORDERS_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)
