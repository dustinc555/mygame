extends SceneTree

const RAGDOLL_PYRAMID_SCENE := preload("res://scenes/test_levels/ragdoll_pyramid_test.tscn")
const SCENARIOS: Array[Dictionary] = [
	{"label": "Death01 Normal 55", "animation": "Death01", "ratio": 0.55, "speed_index": 1, "scale": 1.0, "frames": 180},
	{"label": "Death01 Normal 100", "animation": "Death01", "ratio": 1.0, "speed_index": 1, "scale": 1.0, "frames": 180},
	{"label": "Death02 Normal 55", "animation": "Death02", "ratio": 0.55, "speed_index": 1, "scale": 1.0, "frames": 180},
	{"label": "Death02 Normal 100", "animation": "Death02", "ratio": 1.0, "speed_index": 1, "scale": 1.0, "frames": 180},
	{"label": "Death01 Fast 75", "animation": "Death01", "ratio": 0.75, "speed_index": 2, "scale": 3.0, "frames": 150},
	{"label": "Death02 Fast 75", "animation": "Death02", "ratio": 0.75, "speed_index": 2, "scale": 3.0, "frames": 150},
	{"label": "Death01 Very Fast 75", "animation": "Death01", "ratio": 0.75, "speed_index": 3, "scale": 8.0, "frames": 120},
	{"label": "Death02 Very Fast 75", "animation": "Death02", "ratio": 0.75, "speed_index": 3, "scale": 8.0, "frames": 120},
]
const FLAT_START := Vector3(26.0, 0.6, 24.0)
const MAX_POSITION_ABS := 160.0
const MIN_BONE_Y := -1.25
const MAX_BONE_Y := 4.5
const MAX_HORIZONTAL_TRAVEL := 7.0
const MAX_FRAME_HORIZONTAL_STEP := 1.1
const MAX_RAGDOLL_AABB_AXIS := 4.25
const MAX_BONE_LINEAR_SPEED := 16.0
const MAX_BONE_ANGULAR_SPEED := 32.0

var _failures: Array[String] = []
var _scene: Node
var _mira: HumanoidCharacter
var _world_time: WorldTimeController


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _finalize() -> void:
	Engine.time_scale = 1.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.paused = false


func _run() -> void:
	for scenario in SCENARIOS:
		await _run_scenario(scenario)
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("RAGDOLL_FLAT_STABILITY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RAGDOLL_FLAT_STABILITY_FAILED count=%d" % _failures.size())
	quit(1)


func _run_scenario(scenario: Dictionary) -> void:
	var label := str(scenario.get("label", "Scenario"))
	await _load_scene(label)
	_configure_speed(label, int(scenario.get("speed_index", 1)), float(scenario.get("scale", 1.0)))
	_start_flat_ragdoll(label, str(scenario.get("animation", "Death01")), float(scenario.get("ratio", 0.75)))
	await _wait_until_ragdoll_active(label, 420)
	if _mira == null or not _mira._is_ragdoll_active:
		await _unload_scene()
		return
	await _monitor_flat_ragdoll(label, int(scenario.get("frames", 160)))
	await _unload_scene()


func _load_scene(label: String) -> void:
	Engine.time_scale = 1.0
	_scene = RAGDOLL_PYRAMID_SCENE.instantiate()
	_scene.set("auto_start_unconscious", false)
	root.add_child(_scene)
	await _wait_physics(8)
	_mira = _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	_world_time = _scene.get_node_or_null("GameBootstrap/WorldTimeController") as WorldTimeController
	if _mira == null:
		_fail(label, "Mira was not found")
	if _world_time == null:
		_fail(label, "WorldTimeController was not found")


func _unload_scene() -> void:
	Engine.time_scale = 1.0
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.queue_free()
	_scene = null
	_mira = null
	_world_time = null
	await process_frame


func _configure_speed(label: String, speed_index: int, expected_scale: float) -> void:
	if _world_time == null:
		return
	_world_time.set_speed_index(speed_index)
	if absf(Engine.time_scale - expected_scale) > 0.001:
		_fail(label, "Expected Engine.time_scale %.2f, got %.2f" % [expected_scale, Engine.time_scale])


func _start_flat_ragdoll(label: String, animation_name: String, ratio: float) -> void:
	if _mira == null:
		return
	var profile := HumanoidRagdollProfile.new()
	profile.downed_preroll_animation_names = PackedStringArray([animation_name])
	profile.downed_preroll_min_ratio = ratio
	profile.downed_preroll_max_ratio = ratio
	_mira.ragdoll_profile = profile
	_mira.global_position = FLAT_START
	_mira.rotation = Vector3(0.0, PI, 0.0)
	_mira.velocity = Vector3.ZERO
	_mira.force_unconscious()
	_mira._downed_recover_delay_remaining = 999.0
	if _mira.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail(label, "Mira did not enter unconscious state")
	if _mira._character_animation_player == null or not _mira._character_animation_player.has_animation(animation_name):
		_fail(label, "Missing forced downed pre-roll animation %s" % animation_name)


func _wait_until_ragdoll_active(label: String, max_frames: int) -> void:
	for _frame_index in range(max_frames):
		if _mira != null and _mira._is_ragdoll_active:
			return
		await physics_frame
	_fail(label, "Ragdoll did not become active within %d physics frames" % max_frames)


func _monitor_flat_ragdoll(label: String, frames: int) -> void:
	var start_anchor := _mira.get_follow_anchor_position()
	var previous_anchor := start_anchor
	for frame_index in range(frames):
		await physics_frame
		if _mira == null:
			return
		var anchor := _mira.get_follow_anchor_position()
		if not _is_finite_position(anchor):
			_fail(label, "Anchor became non-finite at frame %d: %s" % [frame_index, anchor])
			return
		var travel := _horizontal_distance(anchor, start_anchor)
		if travel > MAX_HORIZONTAL_TRAVEL:
			_fail(label, "Flat ragdoll traveled too far at frame %d: %.2f anchor=%s start=%s" % [frame_index, travel, anchor, start_anchor])
			return
		var frame_step := _horizontal_distance(anchor, previous_anchor)
		if frame_step > MAX_FRAME_HORIZONTAL_STEP:
			_fail(label, "Flat ragdoll teleported at frame %d: step=%.2f anchor=%s previous=%s" % [frame_index, frame_step, anchor, previous_anchor])
			return
		previous_anchor = anchor
		if anchor.y > MAX_BONE_Y:
			_fail(label, "Flat ragdoll launched upward at frame %d: %s" % [frame_index, anchor])
			return
		_check_all_bones(label, frame_index)
		_check_ragdoll_bounds(label, frame_index)
		if not _failures.is_empty():
			return
	print("RAGDOLL_FLAT_TEST_OK %s frames=%d anchor=%s" % [label, frames, _mira.get_follow_anchor_position()])


func _check_all_bones(label: String, frame_index: int) -> void:
	for bone_name_value in _mira._ragdoll_physical_bones.keys():
		var bone_name := str(bone_name_value)
		var physical_bone := _mira._ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			_fail(label, "Physical bone %s is invalid at frame %d" % [bone_name, frame_index])
			return
		var position := physical_bone.global_position
		if not _is_finite_position(position):
			_fail(label, "Physical bone %s became non-finite at frame %d: %s" % [bone_name, frame_index, position])
			return
		if position.y < MIN_BONE_Y or position.y > MAX_BONE_Y:
			_fail(label, "Physical bone %s left flat stability height at frame %d: %s" % [bone_name, frame_index, position])
			return
		var linear_speed := physical_bone.linear_velocity.length()
		if linear_speed > MAX_BONE_LINEAR_SPEED:
			_fail(label, "Physical bone %s linear speed unstable at frame %d: %.2f" % [bone_name, frame_index, linear_speed])
			return
		var angular_speed := physical_bone.angular_velocity.length()
		if angular_speed > MAX_BONE_ANGULAR_SPEED:
			_fail(label, "Physical bone %s angular speed unstable at frame %d: %.2f" % [bone_name, frame_index, angular_speed])
			return


func _check_ragdoll_bounds(label: String, frame_index: int) -> void:
	var bounds := _get_ragdoll_bounds()
	if bounds.size.x > MAX_RAGDOLL_AABB_AXIS or bounds.size.y > MAX_RAGDOLL_AABB_AXIS or bounds.size.z > MAX_RAGDOLL_AABB_AXIS:
		_fail(label, "Flat ragdoll bounds exploded at frame %d: position=%s size=%s" % [frame_index, bounds.position, bounds.size])


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


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _is_finite_position(position: Vector3) -> bool:
	return position.x == position.x and position.y == position.y and position.z == position.z and absf(position.x) < MAX_POSITION_ABS and absf(position.y) < MAX_POSITION_ABS and absf(position.z) < MAX_POSITION_ABS


func _wait_physics(frames: int) -> void:
	for _index in range(frames):
		await physics_frame


func _fail(label: String, message: String) -> void:
	_failures.append("[%s] %s" % [label, message])
