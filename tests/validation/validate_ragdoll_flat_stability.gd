extends "res://tests/validation/test_case.gd"

const AI_UTILITY_ADAPTER_PATH := "res://features/ai/bridge/ai_utility_adapter.gd"
const COMBAT_COORDINATOR_PATH := "res://features/combat/bridge/combat_coordinator.gd"
const RAGDOLL_PYRAMID_SCENE_PATH := "res://scenes/test_levels/ragdoll_pyramid_test.tscn"
const SKIN_TEXTURE_BUILDER_PATH := "res://features/actors/projection/appearance/skin_texture_builder.gd"
const SCENARIOS: Array[Dictionary] = [
	{"label": "Death01 Normal Full", "animation": "Death01", "speed_index": 1, "scale": 1.0, "frames": 180},
	{"label": "Death02 Normal Full", "animation": "Death02", "speed_index": 1, "scale": 1.0, "frames": 180},
	{"label": "Death01 Fast Full", "animation": "Death01", "speed_index": 2, "scale": 3.0, "frames": 150},
	{"label": "Death02 Fast Full", "animation": "Death02", "speed_index": 2, "scale": 3.0, "frames": 150},
	{"label": "Death01 Very Fast Full", "animation": "Death01", "speed_index": 3, "scale": 8.0, "frames": 120},
	{"label": "Death02 Very Fast Full", "animation": "Death02", "speed_index": 3, "scale": 8.0, "frames": 120},
]
const FLAT_START := Vector3(26.0, 0.6, 24.0)
const MAX_POSITION_ABS := 160.0
const MAX_ROOT_ACTIVATION_LIFT := 0.02
const MAX_INITIAL_UPWARD_BONE_SPEED := 0.05
const INITIAL_NO_UPWARD_FRAMES := 30
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
var _activation_root_y := 0.0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _finalize() -> void:
	Engine.time_scale = 1.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.paused = false
	_cleanup_runtime_state()


func _run() -> void:
	# Optional single-scenario diagnosis; the default remains the complete matrix.
	var selected_label := OS.get_environment("MYGAME_RAGDOLL_SCENARIO")
	var executed := 0
	for scenario in SCENARIOS:
		if not selected_label.is_empty() and str(scenario.label) != selected_label:
			continue
		await _run_scenario(scenario)
		executed += 1
	var expected := SCENARIOS.size() if selected_label.is_empty() else 1
	if executed != expected:
		_fail("scenario selection", "Expected %d scenarios, executed %d" % [expected, executed])
	print("RAGDOLL_FLAT_SCENARIOS executed=%d expected=%d" % [executed, expected])
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
	print("RAGDOLL_SCENARIO %s" % label)
	if not await _load_scene(label):
		await _unload_scene()
		return
	if _mira == null or _world_time == null or _mira.get_body_projection() == null:
		_fail(label, "Missing actor/body/time prerequisites")
		await _unload_scene()
		return
	_configure_speed(label, int(scenario.get("speed_index", 1)), float(scenario.get("scale", 1.0)))
	_start_flat_ragdoll(label, str(scenario.get("animation", "Death01")))
	await _wait_until_ragdoll_active(label, 420)
	if _mira == null or not _mira.is_ragdoll_active():
		await _unload_scene()
		return
	if _mira.get_body_projection()._ragdoll_physical_bones.size() < 10:
		_fail(label, "Expected nonempty runtime physical skeleton")
		await _unload_scene()
		return
	_check_flat_activation(label)
	await _monitor_flat_ragdoll(label, int(scenario.get("frames", 160)))
	await _unload_scene()


func _load_scene(label: String) -> bool:
	Engine.time_scale = 1.0
	var packed_scene := load(RAGDOLL_PYRAMID_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail(label, "Could not load ragdoll pyramid scene")
		return false
	_scene = packed_scene.instantiate()
	_scene.set("auto_start_unconscious", false)
	root.add_child(_scene)
	await _wait_physics(8)
	_mira = _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	_world_time = _scene.find_child("WorldTimeController", true, false) as WorldTimeController
	if _mira == null:
		_fail(label, "Mira was not found")
	if _world_time == null:
		_fail(label, "WorldTimeController was not found")
	if _world_time == null or _mira == null:
		return false
	# The bootstrap releases its real loading pause asynchronously. Eight physics
	# frames can precede that release and silently test frozen bodies at speed 1.
	var ready_deadline := Time.get_ticks_msec() + 40000
	while _world_time.is_world_paused() and Time.get_ticks_msec() < ready_deadline:
		await process_frame
	if _world_time.is_world_paused() or get_tree().paused:
		_fail(label, "Real world loading/pause did not release before physics readiness deadline")
		return false
	return true


func _unload_scene() -> void:
	Engine.time_scale = 1.0
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
	_scene = null
	_mira = null
	_world_time = null
	await process_frame
	await physics_frame
	_cleanup_runtime_state()
	await process_frame


func _configure_speed(label: String, speed_index: int, expected_scale: float) -> void:
	if _world_time == null:
		return
	print("RAGDOLL_CLOCK_BEFORE path=%s speed=%d reasons=%s tree_paused=%s" % [_world_time.get_path(), _world_time.get_speed_index(), str(_world_time.get("_pause_reasons")), get_tree().paused])
	_world_time.set_speed_index(speed_index)
	print("RAGDOLL_CLOCK_AFTER scale=%s paused=%s" % [Engine.time_scale, _world_time.is_world_paused()])
	if not (absf(Engine.time_scale - expected_scale) <= 0.001):
		_fail(label, "Expected Engine.time_scale %.2f, got %.2f" % [expected_scale, Engine.time_scale])


func _start_flat_ragdoll(label: String, animation_name: String) -> void:
	if _mira == null:
		return
	var profile := HumanoidRagdollProfile.new()
	profile.downed_preroll_animation_names = PackedStringArray([animation_name])
	_mira.get_body_projection().ragdoll_profile = profile
	_mira.global_position = FLAT_START
	_mira.rotation = Vector3(0.0, PI, 0.0)
	_mira.velocity = Vector3.ZERO
	_activation_root_y = _mira.global_position.y
	var gecs := _scene.find_child("GecsWorldController", true, false) as GecsWorldController
	assert(gecs != null, "ragdoll fixture requires the real GECS world")
	var entity = gecs.get_actor_entity(_mira)
	assert(entity != null, "ragdoll fixture requires a registered actor")
	var vitals = entity.get_component(gecs.C_VITALS)
	vitals.blunt_damage = _mira.max_hp + 5.0
	vitals.recovery_multiplier = 0.0
	_mira.get_vitals().recovery_multiplier = 0.0
	VitalsStateMachine.recalculate(vitals, _mira.get_stat_value("toughness"))
	var sync := GameActorSyncSystem.new()
	sync._sync_vitals(vitals, _mira)
	sync.free()
	print("RAGDOLL_START %s state=%d" % [label, _mira.life_state])
	if _mira.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail(label, "Mira did not enter unconscious state")
	var body := _mira.get_body_projection()
	var animation_player: AnimationPlayer = body.get_primary_animation_player() if body != null else null
	if animation_player == null or not animation_player.has_animation(animation_name):
		_fail(label, "Missing forced downed pre-roll animation %s" % animation_name)


func _wait_until_ragdoll_active(label: String, max_frames: int) -> void:
	for _frame_index in range(max_frames):
		if _mira != null and _mira.is_ragdoll_active():
			return
		await physics_frame
	_fail(label, "Ragdoll did not become active within %d physics frames" % max_frames)


func _check_flat_activation(label: String) -> void:
	if _mira == null:
		return
	if _mira.global_position.y > _activation_root_y + MAX_ROOT_ACTIVATION_LIFT:
		_fail(label, "Ragdoll activation lifted root upward: start=%.3f active=%.3f" % [_activation_root_y, _mira.global_position.y])
	_check_no_upward_bone_velocity(label, -1)


func _monitor_flat_ragdoll(label: String, frames: int) -> void:
	var prior_failures := _failures.size()
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
		if frame_index < INITIAL_NO_UPWARD_FRAMES:
			_check_no_upward_bone_velocity(label, frame_index)
		_check_ragdoll_bounds(label, frame_index)
		if _failures.size() != prior_failures:
			return
	print("RAGDOLL_FLAT_TEST_OK %s frames=%d anchor=%s" % [label, frames, _mira.get_follow_anchor_position()])


func _check_all_bones(label: String, frame_index: int) -> void:
	for bone_name_value in _mira.get_body_projection()._ragdoll_physical_bones.keys():
		var bone_name := str(bone_name_value)
		var physical_bone := _mira.get_body_projection()._ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
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
		if not is_finite(linear_speed) or linear_speed > MAX_BONE_LINEAR_SPEED:
			_fail(label, "Physical bone %s linear speed unstable at frame %d: %.2f" % [bone_name, frame_index, linear_speed])
			return
		var angular_speed := physical_bone.angular_velocity.length()
		if not is_finite(angular_speed) or angular_speed > MAX_BONE_ANGULAR_SPEED:
			_fail(label, "Physical bone %s angular speed unstable at frame %d: %.2f" % [bone_name, frame_index, angular_speed])
			return


func _check_no_upward_bone_velocity(label: String, frame_index: int) -> void:
	for bone_name_value in _mira.get_body_projection()._ragdoll_physical_bones.keys():
		var bone_name := str(bone_name_value)
		var physical_bone := _mira.get_body_projection()._ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		if physical_bone.linear_velocity.y > MAX_INITIAL_UPWARD_BONE_SPEED:
			_fail(label, "Physical bone %s had upward activation speed at frame %d: %.3f" % [bone_name, frame_index, physical_bone.linear_velocity.y])
			return


func _check_ragdoll_bounds(label: String, frame_index: int) -> void:
	var bounds := _get_ragdoll_bounds()
	if bounds.size.x > MAX_RAGDOLL_AABB_AXIS or bounds.size.y > MAX_RAGDOLL_AABB_AXIS or bounds.size.z > MAX_RAGDOLL_AABB_AXIS:
		_fail(label, "Flat ragdoll bounds exploded at frame %d: position=%s size=%s" % [frame_index, bounds.position, bounds.size])


func _get_ragdoll_bounds() -> AABB:
	assert(not _mira.get_body_projection()._ragdoll_physical_bones.is_empty(), "ragdoll bounds require physical bones")
	var has_bounds := false
	var bounds := AABB()
	for physical_bone_value in _mira.get_body_projection()._ragdoll_physical_bones.values():
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


func _cleanup_runtime_state() -> void:
	var combat_coordinator = load(COMBAT_COORDINATOR_PATH)
	if combat_coordinator != null and combat_coordinator.has_method("reset_all_state"):
		combat_coordinator.reset_all_state()
	var ai_utility_adapter = load(AI_UTILITY_ADAPTER_PATH)
	if ai_utility_adapter != null and ai_utility_adapter.has_method("clear_runtime_caches"):
		ai_utility_adapter.clear_runtime_caches()
	var skin_texture_builder = load(SKIN_TEXTURE_BUILDER_PATH)
	if skin_texture_builder != null and skin_texture_builder.has_method("clear_runtime_caches"):
		skin_texture_builder.clear_runtime_caches()


func _fail(label: String, message: String) -> void:
	_failures.append("[%s] %s" % [label, message])
