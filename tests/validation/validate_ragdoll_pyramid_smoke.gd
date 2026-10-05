extends "res://tests/validation/test_case.gd"

const AI_UTILITY_ADAPTER_PATH := "res://features/ai/bridge/ai_utility_adapter.gd"
const COMBAT_COORDINATOR_PATH := "res://features/combat/bridge/combat_coordinator.gd"
const RAGDOLL_PYRAMID_SCENE_PATH := "res://scenes/test_levels/ragdoll_pyramid_test.tscn"
const SKIN_TEXTURE_BUILDER_PATH := "res://features/actors/projection/appearance/skin_texture_builder.gd"
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
const MAX_ROOT_ACTIVATION_LIFT := 0.02
const MAX_INITIAL_UPWARD_BONE_SPEED := 0.05

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
	print("RAGDOLL_SCENARIO %s" % label)
	if not await _load_scene(label):
		await _unload_scene()
		return
	if _mira == null or _world_time == null or _party_manager == null or _interaction_controller == null or _mira.get_body_projection() == null:
		_fail(label, "Missing actor/body/time prerequisites")
		await _unload_scene()
		return
	_configure_speed(label, int(scenario.get("speed_index", 1)), float(scenario.get("scale", 1.0)))
	_start_ragdoll_demo(label, int(scenario.get("seed", 3101)))

	_check_ragdoll_started(label)
	if not _mira.is_ragdoll_active() or _mira.get_body_projection()._ragdoll_physical_bones.size() < 10:
		await _unload_scene()
		return
	var active_anchor := _mira.get_follow_anchor_position() if _mira != null else Vector3.ZERO
	await _monitor_ragdoll_stability(label, active_anchor, int(scenario.get("settle_frames", 240)))
	_check_ragdoll_stable(label, active_anchor)
	await _check_follow_and_markers(label)
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
	_party_manager = _scene.get_node_or_null("PartyManager") as PartyManager
	_world_time = _scene.find_child("WorldTimeController", true, false) as WorldTimeController
	_interaction_controller = _scene.find_child("WorldInteractionController", true, false) as WorldInteractionController
	if _mira == null:
		_fail(label, "Mira was not found")
	if _party_manager == null:
		_fail(label, "PartyManager was not found")
	if _world_time == null:
		_fail(label, "WorldTimeController was not found")
	if _interaction_controller == null:
		_fail(label, "WorldInteractionController was not found")
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
	_party_manager = null
	_world_time = null
	_interaction_controller = null
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
	if not (absf(_world_time.real_seconds_per_game_minute - 1.0) <= 0.001):
		_fail(label, "World base minute should be 1 real second, got %.2f" % _world_time.real_seconds_per_game_minute)


func _start_ragdoll_demo(label: String, seed: int) -> void:
	if _scene == null or _mira == null:
		return
	_mira.get_body_projection()._rng.seed = seed
	var half_size := float(_scene.get("pyramid_half_size"))
	var height := float(_scene.get("pyramid_height"))
	var face_z := -half_size * 0.45
	var face_y := height + face_z * height / half_size + 0.7
	_mira.global_position = Vector3(0.0, face_y, face_z)
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


func _check_ragdoll_started(label: String) -> void:
	if _mira == null:
		return
	if _mira.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail(label, "Mira should be unconscious, got %s" % _mira.get_life_state_label())
	var body := _mira.get_body_projection()
	if not body.get_current_clip().is_empty():
		_fail(label, "Collapse must not play a death clip")
	if not _mira.is_ragdoll_active():
		_fail(label, "Ragdoll should activate immediately")
	if _mira.get_body_projection()._ragdoll_simulator == null or not _mira.get_body_projection()._ragdoll_simulator.is_simulating_physics():
		_fail(label, "PhysicalBoneSimulator3D should be simulating")
	if _mira.get_body_projection()._ragdoll_physical_bones.size() < 10:
		_fail(label, "Expected runtime physical bones, got %d" % _mira.get_body_projection()._ragdoll_physical_bones.size())
	if _mira.global_position.y > _activation_root_y + MAX_ROOT_ACTIVATION_LIFT:
		_fail(label, "Ragdoll activation lifted root upward: start=%.3f active=%.3f" % [_activation_root_y, _mira.global_position.y])
	_check_no_upward_bone_velocity(label, -1)


func _check_ragdoll_stable(label: String, active_anchor: Vector3) -> void:
	if _mira == null:
		return
	var pelvis := _mira.get_body_projection()._ragdoll_physical_bones.get("pelvis", null) as PhysicalBone3D
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
	if final_anchor.distance_to(pelvis_position) > 0.001:
		_fail(label, "Public camera/marker anchor must follow simulated pelvis, not capsule")
	if active_anchor.y - final_anchor.y < 0.35 and absf(final_anchor.z - active_anchor.z) < 0.35:
		_fail(label, "Ragdoll did not visibly slide or fall from the pyramid: start=%s final=%s" % [active_anchor, final_anchor])


func _check_all_bones_stable(label: String) -> void:
	for bone_name_value in _mira.get_body_projection()._ragdoll_physical_bones.keys():
		var bone_name := str(bone_name_value)
		var physical_bone := _mira.get_body_projection()._ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			_fail(label, "Physical bone %s is invalid" % bone_name)
			continue
		var position := physical_bone.global_position
		if not _is_finite_position(position):
			_fail(label, "Physical bone %s position is not finite: %s" % [bone_name, position])
		var linear_speed := physical_bone.linear_velocity.length()
		if not is_finite(linear_speed) or linear_speed > MAX_BONE_LINEAR_SPEED:
			_fail(label, "Physical bone %s linear speed is unstable: %.2f" % [bone_name, linear_speed])
		var angular_speed := physical_bone.angular_velocity.length()
		if not is_finite(angular_speed) or angular_speed > MAX_BONE_ANGULAR_SPEED:
			_fail(label, "Physical bone %s angular speed is unstable: %.2f" % [bone_name, angular_speed])


func _check_no_upward_bone_velocity(label: String, frame_index: int) -> void:
	for bone_name_value in _mira.get_body_projection()._ragdoll_physical_bones.keys():
		var bone_name := str(bone_name_value)
		var physical_bone := _mira.get_body_projection()._ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		if physical_bone.linear_velocity.y > MAX_INITIAL_UPWARD_BONE_SPEED:
			_fail(label, "Physical bone %s had upward activation speed at frame %d: %.3f" % [bone_name, frame_index, physical_bone.linear_velocity.y])
			return


func _monitor_ragdoll_stability(label: String, active_anchor: Vector3, frames: int) -> void:
	var previous_anchor := active_anchor
	var prior_failures := _failures.size()
	for frame_index in range(frames):
		await physics_frame
		if _mira == null or not _mira.is_ragdoll_active():
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
		# Uphill contact response is physical, not an activation kick.
		_check_ragdoll_bounds(label)
		if _failures.size() != prior_failures:
			return
		previous_anchor = anchor
	print("RAGDOLL_PYRAMID_TEST_OK %s frames=%d anchor=%s" % [label, frames, _mira.get_follow_anchor_position()])


func _check_ragdoll_bounds(label: String) -> void:
	var bounds := _get_ragdoll_bounds()
	if bounds.size.x > MAX_RAGDOLL_AABB_AXIS or bounds.size.y > MAX_RAGDOLL_AABB_AXIS or bounds.size.z > MAX_RAGDOLL_AABB_AXIS:
		_fail(label, "Ragdoll bounds exploded: position=%s size=%s" % [bounds.position, bounds.size])


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


func _check_follow_and_markers(label: String) -> void:
	if _mira == null or _party_manager == null or _interaction_controller == null:
		return
	_party_manager.select_only(_mira)
	_interaction_controller._set_follow_target(_mira)
	await process_frame
	await physics_frame
	await process_frame
	await process_frame
	# process_frame fires before Node._process: the pelvis has advanced but the
	# per-rendered-frame ring has not. Sample after presentation, not between
	# those updates (an observable stale-frame error at 8x speed).
	await create_timer(0.0, true, false, true).timeout
	var expected_camera_anchor := _mira.get_follow_anchor_position() + Vector3(0.0, FOLLOW_CAMERA_HEIGHT, 0.0)
	var camera_rig := _scene.get_node_or_null("CameraRig") as Node3D
	if camera_rig == null:
		_fail(label, "CameraRig was not found")
	else:
		var camera_error := camera_rig.global_position.distance_to(expected_camera_anchor)
		if not is_finite(camera_error) or camera_error > FOLLOW_TOLERANCE:
			_fail(label, "Camera follow anchor did not track ragdoll: error=%.3f expected=%s got=%s" % [camera_error, expected_camera_anchor, camera_rig.global_position])
	var selection_ring := _mira.get_node_or_null("SelectionRing") as Node3D
	if selection_ring == null:
		_fail(label, "SelectionRing was not found")
	else:
		var expected_marker := _mira.get_ground_marker_position(0.03)
		var marker_error := Vector2(selection_ring.global_position.x - expected_marker.x, selection_ring.global_position.z - expected_marker.z).length()
		if not is_finite(marker_error) or marker_error > MARKER_TOLERANCE:
			_fail(label, "SelectionRing did not track ragdoll ground marker: error=%.3f expected=%s got=%s" % [marker_error, expected_marker, selection_ring.global_position])


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
