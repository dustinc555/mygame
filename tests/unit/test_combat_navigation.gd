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

class GroundingProbe extends GameCombatSlotSystem:
	var grounded_batches := 0
	func _ground_candidates(actor: Node3D, candidates: Array[Vector3], vertical_tolerance: float) -> Array[Vector3]:
		grounded_batches += 1
		return super._ground_candidates(actor, candidates, vertical_tolerance)

var _viewport: SubViewport
var _root: Node3D
var _actor: CharacterBody3D
var _target: CharacterBody3D
var _navigation: WorldNavigationController


func before_each() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	add_child(_viewport)
	_root = Node3D.new()
	_viewport.add_child(_root)
	# Exercise the production local-query route, not just the legacy fallback.
	_navigation = WorldNavigationController.new()
	_navigation.settings = WorldNavigationSettings.new()
	_navigation.settings.tile_size = 32.0
	_navigation._mode = WorldNavigationController.Mode.TILED
	_root.add_child(_navigation)
	_navigation.set_process(false)
	# Tiny fixture geometry must be installed before queries, independent of
	# worker scheduling and preceding tests. Production maps stay asynchronous.
	NavigationServer3D.map_set_use_async_iterations(_root.get_world_3d().navigation_map, false)
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
	NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(min_x, height, -5), Vector3(max_x, height, -5), Vector3(max_x, height, 5), Vector3(min_x, height, 5)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	_root.add_child(region)
	var tile := WorldNavigationController.Tile.new()
	tile.region = region
	tile.state = WorldNavigationController.TileState.BAKED
	_navigation._tiles[Vector2i(int(floorf(min_x / 32.0)), 0)] = tile
	return region


func _sync() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(_root.get_world_3d().navigation_map)
	await get_tree().process_frame


func test_worker_route_rechecks_live_physics_before_acceptance() -> void:
	var helper = load(HELPER_PATH)
	var candidate := Vector3(1, 0.7, 0)
	var path := PackedVector3Array([Vector3(-2, 0, 0), Vector3(1, 0, 0)])
	assert_almost_eq(helper.accept_path(_actor, _target, candidate, path, false), candidate, Vector3.ONE * 0.001)
	_add_box(Vector3(0, 1, 0), Vector3(0.2, 2, 8))
	await _sync()
	assert_eq(helper.accept_path(_actor, _target, candidate, path, false), Vector3.INF, "A wall added while a query runs must still refuse its result")


func test_worker_route_refuses_partial_path_and_obsolete_start() -> void:
	var helper = load(HELPER_PATH)
	var candidate := Vector3(1, 0.7, 0)
	assert_eq(helper.accept_path(_actor, _target, candidate, PackedVector3Array([Vector3(-2, 0, 0), Vector3.ZERO]), false), Vector3.INF)
	assert_eq(helper.accept_path(_actor, _target, candidate, PackedVector3Array([Vector3(-4, 0, 0), Vector3(1, 0, 0)]), false), Vector3.INF)
	assert_eq(helper.accept_path(_actor, _target, candidate, PackedVector3Array(), false), Vector3.INF)


func _positioning_data() -> Array:
	var data := _combat_data()
	var states := [CGameCombatState.new(), CGameCombatState.new()]
	states[0].system_target_actor_id = "b"
	data[6][0].clear()
	return [data[1], data[2], data[3], data[4], states, data[6], data[5], data[0]]


func test_combat_slot_queries_are_deferred_and_cancel_on_target_removal() -> void:
	var system := GameCombatSlotSystem.new()
	_root.add_child(system)
	var columns := _positioning_data()
	system.process([], columns, 0.1)
	assert_false(columns[5][0].position_valid, "Tactical search must queue native navigation, not block this frame")
	assert_not_null(_navigation.query_jobs)
	var deadline := Time.get_ticks_msec() + 2000
	while not columns[5][0].position_valid and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		system.process([], columns, 0.1)
	assert_true(columns[5][0].position_valid, "A completed worker route becomes an ordinary combat reservation")
	assert_almost_eq(columns[5][0].slot_position, Vector3(1, 0.7, 0), Vector3.ONE * 0.001)
	columns[5][0].position_recheck_remaining = 0.0
	system.process([], columns, 0.1)
	_target.queue_free()
	await get_tree().process_frame
	system.process([], columns, 0.1)
	assert_false(columns[5][0].position_valid)
	assert_true(_navigation.query_jobs._tickets.is_empty(), "LOD removal cancels queued/resolved tactical work")


func test_already_clear_stance_does_not_wait_for_a_worker_batch() -> void:
	_actor.position = Vector3(1, 0.7, 0)
	await _sync()
	var system := GameCombatSlotSystem.new()
	_root.add_child(system)
	var columns := _positioning_data()
	system.process([], columns, 0.1)
	assert_true(columns[5][0].position_valid, "A physically clear current stance needs no travel search")
	assert_eq(columns[5][0].slot_state, CGameCombatSlotState.FightState.FIGHTING)
	assert_almost_eq(columns[5][0].slot_position, _actor.position, Vector3.ONE * 0.001)
	assert_true(system._position_requests.is_empty())

func test_moving_target_does_not_cancel_completed_tactical_results() -> void:
	var system := GameCombatSlotSystem.new()
	_root.add_child(system)
	var candidates: Array[Vector3] = [Vector3.INF, Vector3.INF, Vector3(1, 0.7, 0)]
	assert_true(system._candidate_paths(_actor, _target, candidates, true, 0.75).pending)
	var key := "combat:%d" % _actor.get_instance_id()
	var deadline := Time.get_ticks_msec() + 2000
	while not _navigation.query_jobs._ready.has(key) and Time.get_ticks_msec() < deadline:
		_navigation.query_jobs.pump()
		await get_tree().process_frame
	assert_true(_navigation.query_jobs._ready.has(key))
	_target.position.x += 0.6
	var result := system._candidate_paths(_actor, _target, candidates, true, 0.75)
	assert_false(result.get("pending", false), "Consume completed work; live physical acceptance decides whether it is still useful")
	assert_true(result.has("paths"))

func test_open_front_position_is_reserved_on_a_walkable_slope() -> void:
	await _assert_sloped_front(10.0, 22.5)


func test_shallow_slope_uses_open_front_instead_of_contour_flank() -> void:
	await _assert_sloped_front(5.0, 0.0)


func test_synchronous_position_search_grounds_the_same_open_front() -> void:
	_navigation.settings.threaded_queries_enabled = false
	await _assert_sloped_front(-10.0, 22.5)


func _assert_sloped_front(slope_degrees: float, bearing_degrees: float) -> void:
	var slope := deg_to_rad(slope_degrees)
	var bearing := deg_to_rad(bearing_degrees)
	for child in _root.get_children():
		if child is StaticBody3D:
			child.rotation.z = slope
			child.position = Vector3(sin(slope) * 0.1, -cos(slope) * 0.1, 0.0)
		elif child is NavigationRegion3D:
			child.rotation.z = slope
	_target.position = Vector3(0.0, 0.7, 0.0)
	_actor.position = Vector3(-3.0 * cos(bearing), 0.7 - 3.0 * cos(bearing) * tan(slope), -3.0 * sin(bearing))
	await _sync()
	# Independent geometry oracle: the closest front spot is on the plane,
	# not at the defender's body height. Native routing and physics approve it.
	var front := Vector3(-cos(bearing), 0.7 - cos(bearing) * tan(slope), -sin(bearing))
	assert_almost_eq(load(HELPER_PATH).find_reachable_position(_actor, _target, front), front, Vector3.ONE * 0.001)
	var system := GameCombatSlotSystem.new()
	_root.add_child(system)
	var columns := _positioning_data()
	columns[3][1].combat_stance = NpcRules.CombatStance.DEFENSIVE
	var deadline := Time.get_ticks_msec() + 2000
	while not columns[5][0].position_valid and Time.get_ticks_msec() < deadline:
		system.process([], columns, 0.1)
		await get_tree().process_frame
	assert_true(columns[5][0].position_valid, "An enemy must obtain an open fighting position on a walkable slope")
	assert_almost_eq(columns[5][0].slot_position, front, Vector3.ONE * 0.001, "Use the open front, not an unnecessary flank")
	assert_eq(columns[4][1].system_target_actor_id, "", "Defend does not have to chase the attacker to make its approach work")


func test_grounding_uses_attacker_body_offset_without_changing_horizontal_hint() -> void:
	_actor.get_node("CollisionShape3D").position.y = 0.5
	_actor.position.y = 0.4
	await _sync()
	var grounded: Vector3 = load(HELPER_PATH).ground_position_hint(_actor, Vector3(1, 0.7, 0), 0.75)
	assert_almost_eq(grounded, Vector3(1, 0.4, 0), Vector3.ONE * 0.001)
	assert_almost_eq(load(HELPER_PATH).find_reachable_position(_actor, _target, grounded), grounded, Vector3.ONE * 0.001)


func test_grounding_does_not_relax_exact_destination_contact() -> void:
	var helper = load(HELPER_PATH)
	var hint := Vector3(1, 0.85, 0)
	var grounded: Vector3 = helper.ground_position_hint(_actor, hint, 0.75)
	assert_almost_eq(grounded, Vector3(1, 0.7, 0), Vector3.ONE * 0.001)
	assert_eq(helper.find_reachable_position(_actor, _target, hint), Vector3.INF, "An ungrounded exact destination still fails closed")
	assert_almost_eq(helper.find_reachable_position(_actor, _target, grounded), grounded, Vector3.ONE * 0.001)


func test_grounding_refuses_remote_height_and_unwalkable_support() -> void:
	var helper = load(HELPER_PATH)
	assert_eq(helper.ground_position_hint(_actor, Vector3(1, 1.6, 0), 0.75), Vector3.INF, "No remote vertical snap")
	assert_eq(helper.ground_position_hint(_actor, Vector3(1, 0.85, 0), 0.1), Vector3.INF, "The actor's configured vertical limit applies")
	for child in _root.get_children():
		if child is StaticBody3D:
			child.rotation.z = deg_to_rad(60.0)
			child.position = Vector3(sin(child.rotation.z), -cos(child.rotation.z), 0) * 0.1
	await _sync()
	assert_eq(helper.ground_position_hint(_actor, Vector3(0, 0.7, 0), 0.75), Vector3.INF, "A steep surface cannot become a standing position")


func test_grounding_does_not_make_disconnected_or_stacked_floors_reachable() -> void:
	var helper = load(HELPER_PATH)
	_add_region(8.0, 12.0)
	_add_box(Vector3(0, 2.9, 0), Vector3(5, 0.2, 5))
	_add_region(-2.5, 2.5, 3.0)
	await _sync()
	var island: Vector3 = helper.ground_position_hint(_actor, Vector3(9, 0.85, 0), 0.75)
	var upstairs: Vector3 = helper.ground_position_hint(_actor, Vector3(1, 3.85, 0), 0.75)
	assert_almost_eq(island, Vector3(9, 0.7, 0), Vector3.ONE * 0.001)
	assert_almost_eq(upstairs, Vector3(1, 3.7, 0), Vector3.ONE * 0.001)
	assert_eq(helper.find_reachable_position(_actor, _target, island, false), Vector3.INF)
	assert_eq(helper.find_reachable_position(_actor, _target, upstairs, false), Vector3.INF)


func test_pending_batch_does_not_repeat_grounding_or_move_exact_preferences() -> void:
	var system := GroundingProbe.new()
	_root.add_child(system)
	var candidates: Array[Vector3] = [_actor.position, Vector3(1, 0.9, 0), Vector3(1, 0.85, 0)]
	assert_true(system._candidate_paths(_actor, _target, candidates, true, 0.75).pending)
	for poll in range(10):
		assert_true(system._candidate_paths(_actor, _target, candidates.duplicate(), true, 0.75).pending)
	assert_eq(system.grounded_batches, 1, "Waiting for workers must not repeat physical ground searches")
	assert_eq(candidates[0], _actor.position, "Current stance stays exact")
	assert_eq(candidates[1], Vector3(1, 0.9, 0), "Retained position stays exact for live acceptance")
	assert_almost_eq(candidates[2], Vector3(1, 0.7, 0), Vector3.ONE * 0.001)


func test_grounded_route_rechecks_support_after_worker_completion() -> void:
	var helper = load(HELPER_PATH)
	var grounded: Vector3 = helper.ground_position_hint(_actor, Vector3(1, 0.85, 0), 0.75)
	var path := PackedVector3Array([Vector3(-2, 0, 0), Vector3(1, 0, 0)])
	for child in _root.get_children():
		if child is StaticBody3D:
			child.queue_free()
	await _sync()
	assert_eq(helper.accept_path(_actor, _target, grounded, path, false), Vector3.INF, "A saved grounded hint is not proof that support still exists")
