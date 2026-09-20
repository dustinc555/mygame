extends GutTest

const HELPER_PATH := "res://features/combat/bridge/combat_navigation.gd"

# Only the actor-specific acceptance seam is replaced; production action/impact
# resolution, component damage and physical refusal all run unchanged.
class ResolutionProbe extends GameCombatResolutionSystem:
	var receive_calls := 0
	func _prepare_receive_attack(_target_actor: Node, _attacker_actor: Node, _target_vitals: CGameActorVitals) -> Dictionary:
		receive_calls += 1
		return {"accepted": true, "can_actively_defend": false}


class FloorActor extends WorldActor:
	func _enter_tree() -> void:
		pass # Isolate the real body-origin API from unrelated capabilities.
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

var _viewport: SubViewport
var _root: Node3D
var _actor: CharacterBody3D
var _target: CharacterBody3D


func before_each() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	add_child(_viewport)
	_root = Node3D.new()
	_viewport.add_child(_root)
	_add_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	_add_region(-5.0, 5.0)
	_actor = _add_actor(Vector3(-2, 0.7, 0))
	_target = _add_actor(Vector3(2, 0.7, 0))
	NavigationServer3D.map_set_active(_root.get_world_3d().navigation_map, true)
	await _sync()


func after_each() -> void:
	_viewport.queue_free()
	await get_tree().process_frame


func test_reachable_position_uses_body_origin_not_nav_floor() -> void:
	assert_true(ResourceLoader.exists(HELPER_PATH), "Combat navigation helper is implemented")
	if not ResourceLoader.exists(HELPER_PATH):
		return
	var helper = load(HELPER_PATH)
	var candidate := Vector3(1, 0.7, 0)
	assert_almost_eq(helper.find_reachable_position(_actor, _target, candidate), candidate, Vector3.ONE * 0.001)


func test_world_actor_floor_alignment_contract_is_used() -> void:
	var actor := FloorActor.new()
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8
	capsule.radius = 0.3
	shape.shape = capsule
	shape.position.y = 0.2
	actor.add_child(shape)
	_root.add_child(actor)
	actor.position = actor.get_floor_aligned_origin_position(Vector3(-2, 0, 0))
	await _sync()
	var candidate := actor.get_floor_aligned_origin_position(Vector3(1, 0, 0))
	assert_almost_eq(load(HELPER_PATH).find_reachable_position(actor, _target, candidate), candidate, Vector3.ONE * 0.001)


func test_occupied_candidate_is_refused_without_floor_self_hit() -> void:
	_add_box(Vector3(1, 0.8, 0), Vector3(0.5, 1.6, 0.5))
	await _sync()
	assert_eq(load(HELPER_PATH).find_reachable_position(_actor, _target, Vector3(1, 0.7, 0), false), Vector3.INF)


func test_disconnected_nav_region_is_refused() -> void:
	_add_region(8.0, 12.0)
	await _sync()
	assert_eq(load(HELPER_PATH).find_reachable_position(_actor, _target, Vector3(9, 0.7, 0), false), Vector3.INF)


func test_remote_projection_is_not_a_reachable_candidate() -> void:
	assert_eq(load(HELPER_PATH).find_reachable_position(_actor, _target, Vector3(6, 0.7, 0), false), Vector3.INF)
	assert_eq(load(HELPER_PATH).find_reachable_position(_actor, _target, Vector3(1, 3.7, 0), false), Vector3.INF)


func test_near_edge_actor_can_recover_to_navigation_without_remote_snap() -> void:
	_actor.position.x = -5.15
	await _sync()
	assert_true(load(HELPER_PATH).find_reachable_position(_actor, _target, Vector3(1, 0.7, 0), false).is_finite())
	_actor.position.x = -7.0
	await _sync()
	assert_eq(load(HELPER_PATH).find_reachable_position(_actor, _target, Vector3(1, 0.7, 0), false), Vector3.INF)


func test_solid_wall_crossing_on_stale_nav_is_refused() -> void:
	_add_box(Vector3(0, 1, 0), Vector3(0.2, 2, 8))
	await _sync()
	assert_eq(load(HELPER_PATH).find_reachable_position(_actor, _target, Vector3(1, 0.7, 0), false), Vector3.INF)


func test_strike_checks_live_torso_ray_and_closed_door_layer() -> void:
	var helper = load(HELPER_PATH)
	assert_true(helper.has_method("can_strike"), "Physical strike query exists")
	if not helper.has_method("can_strike"):
		return
	assert_true(helper.can_strike(_actor, _target))
	var wall := _add_box(Vector3(0, 1, 0), Vector3(0.2, 2, 3), 8)
	await _sync()
	assert_false(helper.can_strike(_actor, _target), "Closed doors refuse strikes")
	wall.collision_layer = 16
	await _sync()
	assert_true(helper.can_strike(_actor, _target), "Click-only panels do not refuse strikes")
	wall.collision_layer = 1
	await _sync()
	assert_false(helper.can_strike(_actor, _target), "World walls refuse strikes")
	assert_true(helper.can_strike(_actor, _target, Vector3(1, 0.7, 0)), "Hypothetical strike uses candidate torso")
	_root.remove_child(_target)
	assert_false(helper.can_strike(_actor, _target), "Detached targets fail closed")
	_target.free()
	assert_false(helper.can_strike(_actor, null))


func test_candidate_requires_strike_but_openable_door_does_not_cut_nav_path() -> void:
	_add_box(Vector3(1.5, 1, 0), Vector3(0.1, 2, 3), 8)
	await _sync()
	var helper = load(HELPER_PATH)
	assert_eq(helper.find_reachable_position(_actor, _target, Vector3(1, 0.7, 0)), Vector3.INF)
	assert_almost_eq(helper.find_reachable_position(_actor, _target, Vector3(1, 0.7, 0), false), Vector3(1, 0.7, 0), Vector3.ONE * 0.001)
	assert_almost_eq(helper.find_reachable_position(_actor, _target, Vector3(3, 0.7, 0)), Vector3(3, 0.7, 0), Vector3.ONE * 0.001)


func test_disabled_downed_target_shape_still_supplies_strike_torso() -> void:
	# WorldActor disables the main collider when downed; component life-state
	# rules, not collision participation, decide whether this victim is attackable.
	_target.get_node("CollisionShape3D").disabled = true
	assert_true(load(HELPER_PATH).can_strike(_actor, _target))
	_add_box(Vector3(0, 1, 0), Vector3(0.1, 2, 3))
	await _sync()
	assert_false(load(HELPER_PATH).can_strike(_actor, _target))


func test_clearance_uses_capsule_radius_not_just_candidate_center() -> void:
	_add_box(Vector3(1.25, 0.8, 0), Vector3(0.1, 1.6, 0.1), 4)
	await _sync()
	assert_eq(load(HELPER_PATH).find_reachable_position(_actor, _target, Vector3(1, 0.7, 0), false), Vector3.INF)


func test_missing_nav_ground_or_body_fails_closed() -> void:
	var helper = load(HELPER_PATH)
	assert_eq(helper.find_reachable_position(_actor, null, Vector3(1, 0.7, 0)), Vector3.INF)
	_actor.get_node("CollisionShape3D").disabled = true
	assert_eq(helper.find_reachable_position(_actor, _target, Vector3(1, 0.7, 0)), Vector3.INF)
	_actor.get_node("CollisionShape3D").disabled = false
	for child in _root.get_children():
		if child is StaticBody3D:
			child.queue_free()
	await _sync()
	assert_eq(helper.find_reachable_position(_actor, _target, Vector3(1, 0.7, 0)), Vector3.INF, "Navmesh alone is not physical ground")
	_add_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	for child in _root.get_children():
		if child is NavigationRegion3D:
			child.queue_free()
	await _sync()
	assert_eq(helper.find_reachable_position(_actor, _target, Vector3(1, 0.7, 0)), Vector3.INF, "Floor alone is not navigation connectivity")


func test_wall_refuses_attack_start_without_spending_action_or_cooldown() -> void:
	_actor.position.x = -0.7
	_target.position.x = 0.7
	_add_box(Vector3(0, 1, 0), Vector3(0.1, 2, 3))
	await _sync()
	var system := ResolutionProbe.new()
	var data := _combat_data()
	system._try_start_slot_action(0, data[0], data[1], data[2], data[3], data[4], data[5], data[6], {"a": 0, "b": 1}, {})
	assert_false(data[5][0].action_active)
	assert_eq(data[5][0].action_sequence, 0)
	assert_eq(data[5][0].cooldown_remaining, 0.0)
	system.free()


func test_target_moving_behind_wall_during_windup_refuses_impact_consequences() -> void:
	_actor.position.x = -0.7
	_target.position.x = 0.7
	await _sync()
	var system := ResolutionProbe.new()
	var data := _combat_data()
	system._try_start_slot_action(0, data[0], data[1], data[2], data[3], data[4], data[5], data[6], {"a": 0, "b": 1}, {})
	assert_true(data[5][0].action_active, "Clear physical strike starts normally")
	# Move behind a wall while still within the slot leash. The stale component
	# position alone cannot detect this live-world obstruction.
	_add_box(Vector3(0, 1, 0.5), Vector3(0.1, 2, 0.3))
	_target.position.z = 1.0
	await _sync()
	watch_signals(system)
	system._resolve_action_impact(0, data[0], data[1], data[2], data[3], data[4], data[5], data[6], {"a": 0, "b": 1})
	assert_true(data[5][0].action_has_impacted, "Impact attempt remains consumed")
	assert_eq(system.receive_calls, 0, "No wakeup or receive consequences")
	assert_eq(data[3][1].blunt_damage, 0.0)
	assert_signal_not_emitted(system, "impact_resolved")
	system.free()


func test_clear_impact_still_applies_component_damage() -> void:
	_actor.position.x = -0.7
	_target.position.x = 0.7
	await _sync()
	var system := ResolutionProbe.new()
	var data := _combat_data()
	system._try_start_slot_action(0, data[0], data[1], data[2], data[3], data[4], data[5], data[6], {"a": 0, "b": 1}, {})
	watch_signals(system)
	system._resolve_action_impact(0, data[0], data[1], data[2], data[3], data[4], data[5], data[6], {"a": 0, "b": 1})
	assert_eq(system.receive_calls, 1)
	assert_gt(data[3][1].blunt_damage, 0.0)
	assert_signal_emitted(system, "impact_resolved")
	system.free()


func _combat_data() -> Array:
	var nodes := [CGameActorNode.new(), CGameActorNode.new()]
	nodes[0].actor = _actor
	nodes[1].actor = _target
	var identities := [CGameActorIdentity.new(), CGameActorIdentity.new()]
	identities[0].actor_id = "a"
	identities[1].actor_id = "b"
	var spatials := [CGameActorSpatial.new(), CGameActorSpatial.new()]
	spatials[0].world_position = _actor.global_position
	spatials[1].world_position = _target.global_position
	var configs := [CGameCombatConfig.new(), CGameCombatConfig.new()]
	configs[0].blunt_damage = 10.0
	var slots := [CGameCombatSlotState.new(), CGameCombatSlotState.new()]
	slots[0].slot_state = CGameCombatSlotState.FightState.FIGHTING
	slots[0].slot_target_actor_id = "b"
	slots[0].tempo_actor_id = "a"
	return [nodes, identities, spatials, [CGameActorVitals.new(), CGameActorVitals.new()], configs, [CGameCombatAction.new(), CGameCombatAction.new()], slots]


func _add_actor(origin: Vector3) -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 9
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.2
	actor.add_child(collision)
	_root.add_child(actor)
	actor.position = origin
	return actor


func _add_box(origin: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	_root.add_child(body)
	body.position = origin
	return body


func _add_region(min_x: float, max_x: float, height: float = 0.0) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(min_x, height, -5), Vector3(max_x, height, -5), Vector3(max_x, height, 5), Vector3(min_x, height, 5)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	_root.add_child(region)
	return region


func _sync() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(_root.get_world_3d().navigation_map)
	await get_tree().process_frame
