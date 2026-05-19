extends SceneTree

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")
const MAX_MOVE_FRAMES := 1500
const SETTLE_FRAMES := 12
const START_CLEARANCE_Y := 0.7
const TARGET_FLOOR_Y := 0.1
const TARGET_TOP_Y := 3.0
const HORIZONTAL_TOLERANCE := 0.9
const VERTICAL_TOLERANCE := 0.9

var _failures: Array[String] = []
var _scene: Node
var _party_manager: PartyManager
var _interaction_controller: WorldInteractionController
var _camera: Camera3D
var _mira: HumanoidCharacter
var _tomas: HumanoidCharacter
var _building: Node3D
var _lower_stairs: Node3D
var _roof_stairs: Node3D
var _guard_post3: Node3D


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _load_two_towns_scene()
	await _run_guardpost3_descent_repro()
	if not _failures.is_empty():
		_finish()
		return
	await _run_direct_stair_tests()
	if not _failures.is_empty():
		_finish()
		return
	await _run_click_stair_tests()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("STAIR_NAV_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("STAIR_NAV_VALIDATION_FAILED count=%d" % _failures.size())
	quit(1)


func _load_two_towns_scene() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_physics(80)
	_party_manager = _scene.get_node("PartyManager") as PartyManager
	_interaction_controller = _scene.get_node("GameBootstrap/WorldInteractionController") as WorldInteractionController
	_camera = _scene.get_node("CameraRig/CameraPivot/Camera3D") as Camera3D
	_mira = _scene.get_node("PartyMembers/Mira") as HumanoidCharacter
	_tomas = _scene.get_node("PartyMembers/Tomas") as HumanoidCharacter
	_building = _scene.get_node("Settlements/FarmerCrossing/Bars/FarmerBar/BuildingSlot/SmallBarScene") as Node3D
	_lower_stairs = _building.get_node("LowerStairs") as Node3D
	_roof_stairs = _building.get_node("BalconyRoofStairs") as Node3D
	_guard_post3 = _scene.get_node("Settlements/FarmerCrossing/Bars/FarmerBar/GuardPosts/GuardPost3") as Node3D
	_camera.current = true


func _run_guardpost3_descent_repro() -> void:
	var actors: Array[HumanoidCharacter] = [_mira, _tomas]
	await _run_click_move_from_current_test(
		"click_group_start_to_guardpost3",
		actors,
		_guard_post3.global_position,
		_guard_post3.global_position,
		Vector3(0.0, 12.0, 12.0)
	)
	if not _failures.is_empty():
		return
	await _wait_physics(40)
	await _run_click_move_from_current_test(
		"click_group_guardpost3_to_outside",
		actors,
		_outside_front_target(),
		_outside_front_target(),
		Vector3(0.0, 12.0, 12.0)
	)


func _run_direct_stair_tests() -> void:
	await _run_single_move_test(
		"direct_lower_to_upper",
		_mira,
		_stair_bottom_start(_lower_stairs),
		_stair_top_target(_lower_stairs)
	)
	await _run_single_move_test(
		"direct_upper_to_lower",
		_mira,
		_stair_top_start(_lower_stairs),
		_stair_bottom_target(_lower_stairs)
	)
	await _run_single_move_test(
		"direct_upper_to_roof",
		_mira,
		_stair_bottom_start(_roof_stairs),
		_stair_top_target(_roof_stairs)
	)
	await _run_single_move_test(
		"direct_roof_to_upper",
		_mira,
		_stair_top_start(_roof_stairs),
		_stair_bottom_target(_roof_stairs)
	)
	await _run_single_move_test(
		"direct_tomas_roof_to_outside",
		_tomas,
		_stair_top_start(_roof_stairs),
		_outside_front_target()
	)
	await _run_single_move_test(
		"direct_tomas_roof_left_corner_to_outside",
		_tomas,
		_stair_top_start(_roof_stairs) + _roof_stair_lateral_offset(-1.35),
		_outside_front_target()
	)
	await _run_single_move_test(
		"direct_tomas_roof_right_corner_to_outside",
		_tomas,
		_stair_top_start(_roof_stairs) + _roof_stair_lateral_offset(1.35),
		_outside_front_target()
	)
	await _run_roof_descent_fan_tests()


func _run_click_stair_tests() -> void:
	await _run_click_move_test(
		"click_roof_to_upper",
		[_mira],
		[_stair_top_start(_roof_stairs)],
		_stair_bottom_target(_roof_stairs),
		_stair_bottom_target(_roof_stairs),
		Vector3(0.0, 8.0, -9.0)
	)
	await _run_click_move_test(
		"click_group_lower_to_upper",
		[_mira, _tomas],
		[_stair_bottom_start(_lower_stairs) + Vector3(-0.55, 0.0, 0.0), _stair_bottom_start(_lower_stairs) + Vector3(0.55, 0.0, 0.0)],
		_stair_top_target(_lower_stairs),
		_stair_top_target(_lower_stairs),
		Vector3(0.0, 10.0, 10.0)
	)
	await _run_click_move_test(
		"click_tomas_roof_to_outside",
		[_tomas],
		[_stair_top_start(_roof_stairs)],
		_outside_front_target(),
		_outside_front_target(),
		Vector3(0.0, 12.0, 12.0)
	)
	await _run_click_move_test(
		"click_tomas_roof_corner_to_outside",
		[_tomas],
		[_stair_top_start(_roof_stairs) + _roof_stair_lateral_offset(1.35)],
		_outside_front_target(),
		_outside_front_target(),
		Vector3(0.0, 12.0, 12.0)
	)
	await _run_click_group_roof_to_outside_test()


func _run_roof_descent_fan_tests() -> void:
	var local_starts := [
		Vector3(-1.45, TARGET_TOP_Y + START_CLEARANCE_Y, 3.4),
		Vector3(-0.75, TARGET_TOP_Y + START_CLEARANCE_Y, 3.4),
		Vector3(0.0, TARGET_TOP_Y + START_CLEARANCE_Y, 3.4),
		Vector3(0.75, TARGET_TOP_Y + START_CLEARANCE_Y, 3.4),
		Vector3(1.45, TARGET_TOP_Y + START_CLEARANCE_Y, 3.4),
		Vector3(-1.45, TARGET_TOP_Y + START_CLEARANCE_Y, 4.7),
		Vector3(1.45, TARGET_TOP_Y + START_CLEARANCE_Y, 4.7),
	]
	for index in range(local_starts.size()):
		await _run_single_move_test(
			"direct_tomas_roof_descent_fan_%d" % index,
			_tomas,
			_roof_stairs.to_global(local_starts[index]),
			_outside_front_target()
		)
		if not _failures.is_empty():
			return


func _run_click_group_roof_to_outside_test() -> void:
	var actors: Array[HumanoidCharacter] = [_mira, _tomas]
	await _run_click_move_test(
		"click_group_roof_to_outside",
		actors,
		[_roof_stairs.to_global(Vector3(-0.75, TARGET_TOP_Y + START_CLEARANCE_Y, 4.7)), _roof_stairs.to_global(Vector3(0.75, TARGET_TOP_Y + START_CLEARANCE_Y, 4.7))],
		_outside_front_target(),
		_outside_front_target(),
		Vector3(0.0, 12.0, 12.0)
	)


func _run_single_move_test(test_name: String, actor: HumanoidCharacter, start_position: Vector3, target_position: Vector3) -> void:
	await _place_actor(actor, start_position)
	actor.set_move_target(target_position)
	await _wait_for_actor(actor)
	if not _actor_reached(actor, target_position):
		_record_actor_failure(test_name, actor, target_position)
		return
	print("STAIR_NAV_TEST_OK %s actor=%s position=%s" % [test_name, actor.name, actor.global_position])


func _run_click_move_test(test_name: String, actors: Array[HumanoidCharacter], start_positions: Array[Vector3], click_target: Vector3, expected_target: Vector3, camera_offset: Vector3) -> void:
	for index in range(actors.size()):
		await _place_actor(actors[index], start_positions[index])
	await _run_click_move_from_current_test(test_name, actors, click_target, expected_target, camera_offset)


func _run_click_move_from_current_test(test_name: String, actors: Array[HumanoidCharacter], click_target: Vector3, expected_target: Vector3, camera_offset: Vector3) -> void:
	_party_manager.set_selection(actors)
	await _wait_physics(20)
	_set_camera_for_click(click_target, camera_offset)
	await _wait_physics(3)
	var screen_position := _camera.unproject_position(click_target)
	var click_hit := _interaction_controller._pick_ground_hit(screen_position)
	var command_issued := bool(_interaction_controller._handle_right_click(screen_position))
	if not command_issued:
		_failures.append("%s did not issue a move command at screen=%s world=%s hit=%s" % [test_name, screen_position, click_target, click_hit])
		return
	var issued_targets: Array[Vector3] = []
	for actor in actors:
		issued_targets.append(actor._move_target)
		print("STAIR_NAV_COMMAND %s actor=%s click=%s hit=%s issued=%s" % [test_name, actor.name, click_target, click_hit, actor._move_target])
		if absf(actor._move_target.y - expected_target.y) > VERTICAL_TOLERANCE:
			_failures.append("%s actor=%s issued target on wrong level: target=%s expected_level_y=%.3f" % [test_name, actor.name, actor._move_target, expected_target.y])
			return
		if _horizontal_distance(actor._move_target, expected_target) > _interaction_controller.move_command_spacing * 1.25:
			_failures.append("%s actor=%s issued target too far from intended click: target=%s intended=%s" % [test_name, actor.name, actor._move_target, expected_target])
			return
	for actor in actors:
		await _wait_for_actor(actor)
	for index in range(actors.size()):
		if not _actor_reached(actors[index], issued_targets[index]):
			_record_actor_failure(test_name, actors[index], issued_targets[index])
			for actor in actors:
				_record_actor_state("%s_group_state" % test_name, actor)
			return
	if actors.size() > 1 and actors[0].global_position.distance_to(actors[1].global_position) < 0.55:
		_failures.append("%s group actors bunched at %s and %s" % [test_name, actors[0].global_position, actors[1].global_position])
		return
	print("STAIR_NAV_TEST_OK %s actors=%d" % [test_name, actors.size()])


func _place_actor(actor: HumanoidCharacter, start_position: Vector3) -> void:
	actor.set_move_target(actor.global_position)
	actor.global_position = start_position
	actor.velocity = Vector3.ZERO
	if actor.has_method("stop_mining_assignment"):
		actor.stop_mining_assignment()
	if actor.has_method("stop_container_interaction"):
		actor.stop_container_interaction()
	await _wait_physics(SETTLE_FRAMES)
	actor.velocity = Vector3.ZERO


func _wait_for_actor(actor: HumanoidCharacter) -> void:
	for _frame in range(MAX_MOVE_FRAMES):
		await physics_frame
		if not actor._has_move_target:
			return


func _actor_reached(actor: HumanoidCharacter, target_position: Vector3) -> bool:
	return _horizontal_distance(actor.global_position, target_position) <= HORIZONTAL_TOLERANCE and absf(actor.global_position.y - target_position.y) <= VERTICAL_TOLERANCE


func _record_actor_failure(test_name: String, actor: HumanoidCharacter, target_position: Vector3) -> void:
	var agent := actor.get_node("NavigationAgent3D") as NavigationAgent3D
	_failures.append("%s actor=%s position=%s target=%s horizontal_error=%.3f vertical_error=%.3f has_target=%s final=%s reachable=%s path=%s" % [
		test_name,
		actor.name,
		actor.global_position,
		target_position,
		_horizontal_distance(actor.global_position, target_position),
		absf(actor.global_position.y - target_position.y),
		actor._has_move_target,
		agent.get_final_position(),
		agent.is_target_reachable(),
		agent.get_current_navigation_path(),
	])


func _record_actor_state(test_name: String, actor: HumanoidCharacter) -> void:
	var agent := actor.get_node("NavigationAgent3D") as NavigationAgent3D
	_failures.append("%s actor=%s position=%s velocity=%s has_target=%s move_target=%s path_index=%d nearby=%s path=%s" % [
		test_name,
		actor.name,
		actor.global_position,
		actor.velocity,
		actor._has_move_target,
		actor._move_target,
		agent.get_current_navigation_path_index(),
		_nearby_actor_summary(actor, 4.0),
		agent.get_current_navigation_path(),
	])


func _nearby_actor_summary(actor: HumanoidCharacter, radius: float) -> Array[String]:
	var summaries: Array[String] = []
	for node in get_nodes_in_group("world_actor"):
		if node == actor or not (node is Node3D):
			continue
		var node3d := node as Node3D
		var distance := actor.global_position.distance_to(node3d.global_position)
		if distance <= radius:
			summaries.append("%s@%s d=%.2f" % [node.name, node3d.global_position, distance])
	return summaries


func _set_camera_for_click(target_position: Vector3, offset: Vector3) -> void:
	_camera.global_position = target_position + offset
	_camera.look_at(target_position, Vector3.UP)


func _stair_bottom_start(stairs: Node3D) -> Vector3:
	return stairs.to_global(Vector3(0.0, START_CLEARANCE_Y, -4.1))


func _stair_top_start(stairs: Node3D) -> Vector3:
	return stairs.to_global(Vector3(0.0, TARGET_TOP_Y + START_CLEARANCE_Y, 4.1))


func _stair_bottom_target(stairs: Node3D) -> Vector3:
	return stairs.to_global(Vector3(0.0, TARGET_FLOOR_Y, -4.1))


func _stair_top_target(stairs: Node3D) -> Vector3:
	return stairs.to_global(Vector3(0.0, TARGET_TOP_Y, 4.1))


func _outside_front_target() -> Vector3:
	return _building.to_global(Vector3(0.0, TARGET_FLOOR_Y, 8.5))


func _roof_stair_lateral_offset(local_x: float) -> Vector3:
	return _roof_stairs.global_transform.basis.x.normalized() * local_x


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _wait_physics(frames: int) -> void:
	for _index in range(frames):
		await physics_frame
