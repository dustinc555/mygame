extends SceneTree

const RAGDOLL_PYRAMID_SCENE := preload("res://scenes/test_levels/ragdoll_pyramid_test.tscn")
const SPEED_SCENARIOS: Array[Dictionary] = [
	{"label": "Run 01 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 3101},
	{"label": "Run 02 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 9137},
	{"label": "Run 03 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 4721},
	{"label": "Run 04 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 6659},
	{"label": "Run 05 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 1289},
	{"label": "Run 06 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 7403},
	{"label": "Run 07 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 2213},
	{"label": "Run 08 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 5831},
	{"label": "Run 09 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 3559},
	{"label": "Run 10 Normal", "speed_index": 1, "scale": 1.0, "settle_frames": 300, "seed": 9973},
	{"label": "Run 11 Fast", "speed_index": 2, "scale": 3.0, "settle_frames": 260, "seed": 3101},
	{"label": "Run 12 Fast", "speed_index": 2, "scale": 3.0, "settle_frames": 260, "seed": 9137},
	{"label": "Run 13 Fast", "speed_index": 2, "scale": 3.0, "settle_frames": 260, "seed": 4721},
	{"label": "Run 14 Very Fast", "speed_index": 3, "scale": 8.0, "settle_frames": 240, "seed": 3101},
	{"label": "Run 15 Very Fast", "speed_index": 3, "scale": 8.0, "settle_frames": 240, "seed": 9137},
	{"label": "Run 16 Very Fast", "speed_index": 3, "scale": 8.0, "settle_frames": 240, "seed": 4721},
]
const MAX_POSITION_ABS := 160.0
const MAX_PELVIS_HEIGHT := 24.0
const MIN_PELVIS_HEIGHT := -3.0
const MAX_HORIZONTAL_DISTANCE := 48.0
const MAX_FRAME_HORIZONTAL_STEP := 2.4
const MAX_FRAME_VERTICAL_STEP := 2.8
const MAX_RAGDOLL_AABB_AXIS := 5.5
const MAX_BONE_LINEAR_SPEED := 16.0
const MAX_BONE_ANGULAR_SPEED := 32.0
const FOLLOW_CAMERA_HEIGHT := 1.35
const FOLLOW_TOLERANCE := 0.12
const MARKER_TOLERANCE := 0.16

var _failures: Array[String] = []
var _scene: Node
var _mira: HumanoidCharacter
var _party_manager: PartyManager
var _world_time: WorldTimeController
var _interaction_controller: WorldInteractionController


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _finalize() -> void:
	Engine.time_scale = 1.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.paused = false


func _run() -> void:
	for scenario_index in range(SPEED_SCENARIOS.size()):
		var scenario: Dictionary = SPEED_SCENARIOS[scenario_index]
		await _run_speed_scenario(scenario)
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("RAGDOLL_PYRAMID_SMOKE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RAGDOLL_PYRAMID_SMOKE_FAILED count=%d" % _failures.size())
	quit(1)


func _run_speed_scenario(scenario: Dictionary) -> void:
	var label := str(scenario.get("label", "Scenario"))
	await _load_scene(label)
	_configure_speed(label, int(scenario.get("speed_index", 1)), float(scenario.get("scale", 1.0)))
	_start_ragdoll_demo(label, int(scenario.get("seed", 3101)))
	await _wait_until_ragdoll_active(label, 360)
	_check_ragdoll_started(label)
	var active_anchor := _mira.get_follow_anchor_position() if _mira != null else Vector3.ZERO
	await _monitor_ragdoll_stability(label, active_anchor, int(scenario.get("settle_frames", 240)))
	_check_ragdoll_stable(label, active_anchor)
	await _check_follow_and_markers(label)
	await _unload_scene()


func _load_scene(label: String) -> void:
	Engine.time_scale = 1.0
	_scene = RAGDOLL_PYRAMID_SCENE.instantiate()
	_scene.set("auto_start_unconscious", false)
	root.add_child(_scene)
	await _wait_physics(8)
	_mira = _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	_party_manager = _scene.get_node_or_null("PartyManager") as PartyManager
	_world_time = _scene.get_node_or_null("GameBootstrap/WorldTimeController") as WorldTimeController
	_interaction_controller = _scene.get_node_or_null("GameBootstrap/WorldInteractionController") as WorldInteractionController
	if _mira == null:
		_fail(label, "Mira was not found")
	if _party_manager == null:
		_fail(label, "PartyManager was not found")
	if _world_time == null:
		_fail(label, "WorldTimeController was not found")
	if _interaction_controller == null:
		_fail(label, "WorldInteractionController was not found")


func _unload_scene() -> void:
	Engine.time_scale = 1.0
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.queue_free()
	_scene = null
	_mira = null
	_party_manager = null
	_world_time = null
	_interaction_controller = null
	await process_frame


func _configure_speed(label: String, speed_index: int, expected_scale: float) -> void:
	if _world_time == null:
		return
	_world_time.set_speed_index(speed_index)
	if absf(Engine.time_scale - expected_scale) > 0.001:
		_fail(label, "Expected Engine.time_scale %.2f, got %.2f" % [expected_scale, Engine.time_scale])
	if absf(_world_time.real_seconds_per_game_minute - 1.0) > 0.001:
		_fail(label, "World base minute should be 1 real second, got %.2f" % _world_time.real_seconds_per_game_minute)


func _start_ragdoll_demo(label: String, seed: int) -> void:
	if _scene == null or _mira == null:
		return
	_mira._rng.seed = seed
	var half_size := float(_scene.get("pyramid_half_size"))
	var height := float(_scene.get("pyramid_height"))
	var face_z := -half_size * 0.45
	var face_y := height + face_z * height / half_size + 0.7
	_mira.global_position = Vector3(0.0, face_y, face_z)
	_mira.rotation = Vector3(0.0, PI, 0.0)
	_mira.velocity = Vector3.ZERO
	_mira.force_unconscious()
	_mira._downed_recover_delay_remaining = 999.0
	if _mira.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail(label, "Mira did not enter unconscious state")


func _wait_until_ragdoll_active(label: String, max_frames: int) -> void:
	for _frame_index in range(max_frames):
		if _mira != null and _mira._is_ragdoll_active:
			return
		await physics_frame
	_fail(label, "Ragdoll did not become active within %d physics frames" % max_frames)


func _check_ragdoll_started(label: String) -> void:
	if _mira == null:
		return
	if _mira.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail(label, "Mira should be unconscious, got %s" % _mira.get_life_state_label())
	if _mira._character_animation_player == null or not _mira._character_animation_player.has_animation("Death01") or not _mira._character_animation_player.has_animation("Death02"):
		_fail(label, "Death01 and Death02 should be available for downed pre-roll")
	if _mira._ragdoll_preroll_active:
		_fail(label, "Ragdoll preroll should have finished")
	if not _mira._is_ragdoll_active:
		_fail(label, "Ragdoll should be active")
	if _mira._ragdoll_simulator == null or not _mira._ragdoll_simulator.is_simulating_physics():
		_fail(label, "PhysicalBoneSimulator3D should be simulating")
	if _mira._ragdoll_physical_bones.size() < 10:
		_fail(label, "Expected runtime physical bones, got %d" % _mira._ragdoll_physical_bones.size())


func _check_ragdoll_stable(label: String, active_anchor: Vector3) -> void:
	if _mira == null:
		return
	var pelvis := _mira._ragdoll_physical_bones.get("pelvis", null) as PhysicalBone3D
	if pelvis == null:
		_fail(label, "Pelvis physical bone was not created")
		return
	var pelvis_position := pelvis.global_position
	if not _is_finite_position(pelvis_position):
		_fail(label, "Pelvis physical bone position is not finite: %s" % pelvis_position)
	if pelvis_position.y < MIN_PELVIS_HEIGHT:
		_fail(label, "Pelvis fell below the floor: %s" % pelvis_position)
	if pelvis_position.y > MAX_PELVIS_HEIGHT:
		_fail(label, "Pelvis launched too high: %s" % pelvis_position)
	var horizontal_distance := Vector2(pelvis_position.x, pelvis_position.z).length()
	if horizontal_distance > MAX_HORIZONTAL_DISTANCE:
		_fail(label, "Pelvis traveled too far from the demo area: %s" % pelvis_position)
	_check_all_bones_stable(label)
	_check_ragdoll_bounds(label)
	var final_anchor := _mira.get_follow_anchor_position()
	if active_anchor.y - final_anchor.y < 0.35 and absf(final_anchor.z - active_anchor.z) < 0.35:
		_fail(label, "Ragdoll did not visibly slide or fall from the pyramid: start=%s final=%s" % [active_anchor, final_anchor])


func _check_all_bones_stable(label: String) -> void:
	for bone_name_value in _mira._ragdoll_physical_bones.keys():
		var bone_name := str(bone_name_value)
		var physical_bone := _mira._ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			_fail(label, "Physical bone %s is invalid" % bone_name)
			continue
		var position := physical_bone.global_position
		if not _is_finite_position(position):
			_fail(label, "Physical bone %s position is not finite: %s" % [bone_name, position])
		var linear_speed := physical_bone.linear_velocity.length()
		if linear_speed > MAX_BONE_LINEAR_SPEED:
			_fail(label, "Physical bone %s linear speed is unstable: %.2f" % [bone_name, linear_speed])
		var angular_speed := physical_bone.angular_velocity.length()
		if angular_speed > MAX_BONE_ANGULAR_SPEED:
			_fail(label, "Physical bone %s angular speed is unstable: %.2f" % [bone_name, angular_speed])


func _monitor_ragdoll_stability(label: String, active_anchor: Vector3, frames: int) -> void:
	var previous_anchor := active_anchor
	for frame_index in range(frames):
		await physics_frame
		if _mira == null or not _mira._is_ragdoll_active:
			_fail(label, "Ragdoll stopped unexpectedly at frame %d" % frame_index)
			return
		var anchor := _mira.get_follow_anchor_position()
		if not _is_finite_position(anchor):
			_fail(label, "Ragdoll anchor became non-finite at frame %d: %s" % [frame_index, anchor])
			return
		var frame_horizontal_step := Vector2(anchor.x - previous_anchor.x, anchor.z - previous_anchor.z).length()
		var frame_vertical_step := absf(anchor.y - previous_anchor.y)
		if frame_horizontal_step > MAX_FRAME_HORIZONTAL_STEP or frame_vertical_step > MAX_FRAME_VERTICAL_STEP:
			_fail(label, "Ragdoll anchor jumped at frame %d: horizontal=%.2f vertical=%.2f previous=%s current=%s" % [frame_index, frame_horizontal_step, frame_vertical_step, previous_anchor, anchor])
			return
		var horizontal_distance := Vector2(anchor.x - active_anchor.x, anchor.z - active_anchor.z).length()
		if horizontal_distance > MAX_HORIZONTAL_DISTANCE:
			_fail(label, "Ragdoll traveled too far at frame %d: distance=%.2f start=%s current=%s" % [frame_index, horizontal_distance, active_anchor, anchor])
			return
		if anchor.y < MIN_PELVIS_HEIGHT or anchor.y > MAX_PELVIS_HEIGHT:
			_fail(label, "Ragdoll anchor left stability height at frame %d: %s" % [frame_index, anchor])
			return
		_check_all_bones_stable(label)
		_check_ragdoll_bounds(label)
		if not _failures.is_empty():
			return
		previous_anchor = anchor
	print("RAGDOLL_PYRAMID_TEST_OK %s frames=%d anchor=%s" % [label, frames, _mira.get_follow_anchor_position()])


func _check_ragdoll_bounds(label: String) -> void:
	var bounds := _get_ragdoll_bounds()
	if bounds.size.x > MAX_RAGDOLL_AABB_AXIS or bounds.size.y > MAX_RAGDOLL_AABB_AXIS or bounds.size.z > MAX_RAGDOLL_AABB_AXIS:
		_fail(label, "Ragdoll bounds exploded: position=%s size=%s" % [bounds.position, bounds.size])


func _get_ragdoll_bounds() -> AABB:
	var has_bounds := false
	var bounds := AABB()
	for physical_bone_value in _mira._ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		var position := physical_bone.global_position
		if not has_bounds:
			bounds = AABB(position, Vector3.ZERO)
			has_bounds = true
		else:
			bounds = bounds.expand(position)
	return bounds


func _check_follow_and_markers(label: String) -> void:
	if _mira == null or _party_manager == null or _interaction_controller == null:
		return
	_party_manager.select_only(_mira)
	_interaction_controller._set_follow_target(_mira)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	var expected_camera_anchor := _mira.get_follow_anchor_position() + Vector3(0.0, FOLLOW_CAMERA_HEIGHT, 0.0)
	var camera_rig := _scene.get_node_or_null("CameraRig") as Node3D
	if camera_rig == null:
		_fail(label, "CameraRig was not found")
	else:
		var camera_error := camera_rig.global_position.distance_to(expected_camera_anchor)
		if camera_error > FOLLOW_TOLERANCE:
			_fail(label, "Camera follow anchor did not track ragdoll: error=%.3f expected=%s got=%s" % [camera_error, expected_camera_anchor, camera_rig.global_position])
	var selection_ring := _mira.get_node_or_null("SelectionRing") as Node3D
	if selection_ring == null:
		_fail(label, "SelectionRing was not found")
	else:
		var expected_marker := _mira.get_ground_marker_position(0.03)
		var marker_error := Vector2(selection_ring.global_position.x - expected_marker.x, selection_ring.global_position.z - expected_marker.z).length()
		if marker_error > MARKER_TOLERANCE:
			_fail(label, "SelectionRing did not track ragdoll ground marker: error=%.3f expected=%s got=%s" % [marker_error, expected_marker, selection_ring.global_position])


func _is_finite_position(position: Vector3) -> bool:
	return position.x == position.x and position.y == position.y and position.z == position.z and absf(position.x) < MAX_POSITION_ABS and absf(position.y) < MAX_POSITION_ABS and absf(position.z) < MAX_POSITION_ABS


func _wait_physics(frames: int) -> void:
	for _index in range(frames):
		await physics_frame


func _fail(label: String, message: String) -> void:
	_failures.append("[%s] %s" % [label, message])
