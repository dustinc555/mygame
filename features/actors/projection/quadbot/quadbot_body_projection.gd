extends BodyProjection

class_name QuadBotBodyProjection

const QUADBOT_DEATH_ANIMATION_NAME := "RobotDeath"
const DEFAULT_BLEND_SECONDS := 0.12
const VISUAL_BODY_TYPE_NONE := 1
const QUADBOT_VISUAL_YAW_OFFSET := PI
const QUADBOT_VISUAL_FLOOR_CLEARANCE := 0.38
const QUADBOT_GET_UP_SECONDS := 0.08
const QUADBOT_RAGDOLL_SIMULATOR_NAME := "QuadBotRagdollSimulator"
const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const STABLE_PHYSICAL_BONE_SCRIPT = preload("res://features/actors/projection/stable_physical_bone.gd")
const RAGDOLL_MAX_LINEAR_SPEED := 10.0
const RAGDOLL_MAX_ANGULAR_SPEED := 18.0
const RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES := 90
const QUADBOT_RAGDOLL_BONES := [
	"Body",
	"Front_Shoulder.L",
	"Front_Leg1.L",
	"Front_Leg2.L",
	"Front_Leg3.L",
	"Back_Shoulder.L",
	"Back_Leg1.L",
	"Back_Leg2.L",
	"Back_Leg3.L",
	"Front_Shoulder.R",
	"Front_Leg1.R",
	"Front_Leg2.R",
	"Front_Leg3.R",
	"Back_Shoulder.R",
	"Back_Leg1.R",
	"Back_Leg2.R",
	"Back_Leg3.R",
]
var _visual_root: Node3D
var _model_root: Node3D
var _animation_player: AnimationPlayer
var _current_clip := ""
var _visual_fit_scale := 1.0
var _ragdoll_active := false
var _stored_local_transform := Transform3D.IDENTITY
var _ragdoll_skeleton: Skeleton3D
var _ragdoll_simulator: PhysicalBoneSimulator3D
var _ragdoll_physical_bones: Dictionary = {}
var _last_ragdoll_impulse := Vector3.ZERO
var _last_ragdoll_impulse_remaining := 0.0
var _ragdoll_upward_velocity_suppression_frames := 0


## Typed handle to the _actor. Base stores it sim-agnostically as Node3D; this concrete quadbot
## projection caches a typed reference (one-way edge, not part of the base BodyProjection cycle).
var _actor: WorldActor


func bind_actor(owner_actor: Node3D) -> void:
	super.bind_actor(owner_actor)
	_actor = owner_actor as WorldActor


func supports_downed_visuals() -> bool:
	return true


func supports_ragdoll_visuals() -> bool:
	return true


func setup_visual() -> void:
	_free_visual_root()
	_animation_player = null
	_current_clip = ""
	_ragdoll_active = false
	_ragdoll_skeleton = null
	_ragdoll_simulator = null
	_ragdoll_physical_bones.clear()
	if actor == null:
		return
	var body_mesh := _actor.get_node_or_null("BodyMesh") as MeshInstance3D
	if body_mesh != null:
		body_mesh.visible = false
	var visual_scene := _get_quadbot_visual_scene()
	if visual_scene == null:
		return
	var model = visual_scene.instantiate()
	if not (model is Node3D):
		if model != null:
			model.queue_free()
		return
	_model_root = model as Node3D
	_model_root.name = "QuadOrbModel"
	_model_root.rotation.y = QUADBOT_VISUAL_YAW_OFFSET
	_visual_root = Node3D.new()
	_visual_root.name = CHARACTER_VISUAL_NODE_NAME
	add_child(_visual_root)
	_visual_root.add_child(_model_root)
	_fit_visual_to_actor_body(body_mesh)
	_configure_quadbot_meshes(_model_root)
	_animation_player = _find_animation_player(_model_root)
	_stored_local_transform = _visual_root.transform
	if _actor.life_state == NpcRules.LifeState.ALIVE:
		play_clip(_quadbot_idle_clip(), 0.0, true, 0.0)


func get_visual_root() -> Node3D:
	return _visual_root if _visual_root != null and is_instance_valid(_visual_root) else null


func get_primary_animation_player() -> AnimationPlayer:
	return _animation_player if _animation_player != null and is_instance_valid(_animation_player) else null


func get_visual_local_bounds() -> AABB:
	return _accumulate_mesh_bounds(_visual_root) if _visual_root != null and is_instance_valid(_visual_root) else AABB()


func get_visual_world_bounds() -> AABB:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return AABB()
	var parent_node := _visual_root.get_parent() as Node3D
	var parent_transform := parent_node.global_transform if parent_node != null else Transform3D.IDENTITY
	return _accumulate_mesh_bounds_from(_visual_root, parent_transform)


func get_ragdoll_physical_bone_world_bounds() -> AABB:
	var result := {"has_bounds": false, "bounds": AABB()}
	for physical_bone_value in _ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		_accumulate_physical_bone_shape_bounds(physical_bone, result)
	return result["bounds"] if bool(result["has_bounds"]) else AABB()


func get_visual_skeleton_world_bounds() -> AABB:
	if (_ragdoll_skeleton == null or not is_instance_valid(_ragdoll_skeleton)) and _visual_root != null and is_instance_valid(_visual_root):
		_ragdoll_skeleton = _find_skeleton(_visual_root)
	if _ragdoll_skeleton == null or not is_instance_valid(_ragdoll_skeleton):
		return AABB()
	var result := {"has_bounds": false, "bounds": AABB()}
	for bone_index in range(_ragdoll_skeleton.get_bone_count()):
		var point := _ragdoll_skeleton.global_transform * _ragdoll_skeleton.get_bone_global_pose(bone_index).origin
		_accumulate_point_bounds(point, result)
	return result["bounds"] if bool(result["has_bounds"]) else AABB()


func get_max_skeleton_ancestor_scale_delta() -> float:
	if (_ragdoll_skeleton == null or not is_instance_valid(_ragdoll_skeleton)) and _visual_root != null and is_instance_valid(_visual_root):
		_ragdoll_skeleton = _find_skeleton(_visual_root)
	if _ragdoll_skeleton == null or not is_instance_valid(_ragdoll_skeleton):
		return 0.0
	var max_delta := 0.0
	var node: Node = _ragdoll_skeleton
	while node != null and node != self:
		if node is Node3D:
			max_delta = maxf(max_delta, ((node as Node3D).scale - Vector3.ONE).length())
		node = node.get_parent()
	return max_delta


func get_animation_players() -> Array[AnimationPlayer]:
	var result: Array[AnimationPlayer] = []
	if get_primary_animation_player() != null:
		result.append(_animation_player)
	return result


func get_resolved_visual_body_type() -> int:
	return VISUAL_BODY_TYPE_NONE


func get_resolved_body_archetype() -> Resource:
	if actor != null and _actor.get("body_archetype") != null:
		return _actor.get("body_archetype") as Resource
	return null


func update_idle_animation(_delta: float, _use_tired_idle: bool) -> void:
	play_clip(_quadbot_idle_clip())


func play_random_idle_animation(_force: bool) -> void:
	play_clip(_quadbot_idle_clip(), 0.0, _force)


func play_clip(animation_name: String, speed_ratio: float = 0.0, force_restart: bool = false, blend_seconds: float = DEFAULT_BLEND_SECONDS) -> bool:
	var resolved_animation := _resolve_quadbot_clip(animation_name)
	if resolved_animation == QUADBOT_DEATH_ANIMATION_NAME:
		return start_ragdoll_simulation(true)
	var player := get_primary_animation_player()
	if player == null or not player.has_animation(resolved_animation):
		return false
	var already_current := _current_clip == resolved_animation
	_current_clip = resolved_animation
	player.speed_scale = _clip_speed(resolved_animation, speed_ratio)
	if force_restart or not already_current or not player.is_playing():
		player.play(resolved_animation, blend_seconds)
		player.advance(0.0)
	return true


func stop_clip(keep_state: bool = true) -> void:
	_current_clip = ""
	var player := get_primary_animation_player()
	if player != null:
		player.stop(keep_state)
		player.speed_scale = 1.0


func seek_clip(animation_name: String, time: float, update: bool = true, speed_scale: float = 1.0) -> void:
	var resolved_animation := _resolve_quadbot_clip(animation_name)
	var player := get_primary_animation_player()
	if player == null or not player.has_animation(resolved_animation):
		return
	_current_clip = resolved_animation
	player.speed_scale = speed_scale
	player.play(resolved_animation)
	player.seek(clampf(time, 0.0, clip_length(resolved_animation)), update)


func clip_length(animation_name: String) -> float:
	var resolved_animation := _resolve_quadbot_clip(animation_name)
	if resolved_animation == QUADBOT_DEATH_ANIMATION_NAME:
		return 0.0
	var player := get_primary_animation_player()
	if player == null or not player.has_animation(resolved_animation):
		return 0.0
	var animation := player.get_animation(resolved_animation)
	return animation.length if animation != null else 0.0


func has_clip(animation_name: String) -> bool:
	var resolved_animation := _resolve_quadbot_clip(animation_name)
	if resolved_animation == QUADBOT_DEATH_ANIMATION_NAME:
		return false
	var player := get_primary_animation_player()
	return player != null and player.has_animation(resolved_animation)


func get_current_clip() -> String:
	return _current_clip


func is_current_clip_playing() -> bool:
	var player := get_primary_animation_player()
	return player != null and player.is_playing()


func is_idle_clip(animation_name: String) -> bool:
	return _resolve_quadbot_clip(animation_name) == _quadbot_idle_clip()


func can_play_combat_action(animation_names: Array[String]) -> bool:
	if animation_names.is_empty():
		return false
	for animation_name in animation_names:
		if not has_clip(animation_name):
			return false
	return true


func get_combat_action_timing(animation_names: Array[String], impact_ratio: float, default_seconds: float = 0.45) -> Dictionary:
	var total_seconds := 0.0
	var first_clip_seconds := 0.0
	for index in range(animation_names.size()):
		var clip_seconds := clip_length(animation_names[index])
		if index == 0:
			first_clip_seconds = clip_seconds
		total_seconds += clip_seconds
	if total_seconds <= 0.0:
		total_seconds = default_seconds
	return {
		"total_seconds": total_seconds,
		"first_clip_seconds": first_clip_seconds,
		"impact_seconds": _get_combat_impact_seconds(first_clip_seconds if first_clip_seconds > 0.0 else total_seconds, impact_ratio),
	}


func pick_available_clip(animation_names: Array[String]) -> String:
	for animation_name in animation_names:
		if has_clip(animation_name):
			return _resolve_quadbot_clip(animation_name)
	return ""


func pick_preferred_available_clip(animation_names: Array[String]) -> String:
	return pick_available_clip(animation_names)


func pick_block_reaction_clip(_has_shield: bool, _animation_set, _shield_block_animation_names: Array[String], _fallback_block_animation_name: String) -> String:
	return ""


func pick_hit_reaction_clip(_attack_id: String, _hit_reaction_names: Array[String] = []) -> String:
	return ""


func play_combat_reaction_clip(_animation_name: String, _blend_seconds: float) -> float:
	return 0.0


func enter_downed_visuals(is_dead: bool) -> bool:
	if actor == null:
		return false
	_actor._apply_downed_collision_shape()
	return start_ragdoll_simulation(is_dead)


func restore_from_downed_visuals() -> void:
	stop_ragdoll_simulation(true)
	if actor != null:
		_actor._restore_downed_collision_shape()
	play_clip(_quadbot_idle_clip(), 0.0, true, 0.0)


func process_downed_visuals(delta: float) -> bool:
	if actor != null and bool(_actor.get("_is_getting_up")):
		_actor.set("_get_up_animation_remaining", maxf(0.0, float(_actor.get("_get_up_animation_remaining")) - delta))
		return float(_actor.get("_get_up_animation_remaining")) <= 0.0
	return false


func begin_get_up_visuals() -> void:
	if actor == null:
		return
	_actor.set("_is_getting_up", true)
	_actor.set("_get_up_animation_name", "")
	_actor.set("_get_up_animation_total", 0.0)
	_actor.set("_get_up_animation_remaining", 0.0)
	_actor.call_deferred("_finish_get_up")


func cancel_get_up_visuals() -> void:
	if actor == null or not bool(_actor.get("_is_getting_up")):
		return
	_actor.set("_is_getting_up", false)
	_actor.set("_get_up_animation_name", "")
	_actor.set("_get_up_animation_remaining", 0.0)
	_actor.set("_get_up_animation_total", 0.0)


func start_ragdoll_simulation(is_dead: bool) -> bool:
	return _start_visual_ragdoll(is_dead)


func stop_ragdoll_simulation(reset_pose: bool) -> void:
	_ragdoll_active = false
	_stop_quadbot_skeleton_ragdoll(reset_pose)
	if reset_pose and _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.top_level = false
		_visual_root.transform = _stored_local_transform


func stabilize_ragdoll(_delta: float) -> void:
	if _ragdoll_active:
		_ragdoll_upward_velocity_suppression_frames = maxi(0, _ragdoll_upward_velocity_suppression_frames - 1)


func process_ragdoll_impulse_memory(delta: float) -> void:
	if _last_ragdoll_impulse_remaining <= 0.0:
		return
	_last_ragdoll_impulse_remaining = maxf(0.0, _last_ragdoll_impulse_remaining - delta)
	if _last_ragdoll_impulse_remaining <= 0.0:
		_last_ragdoll_impulse = Vector3.ZERO


func remember_ragdoll_impulse(impulse: Vector3, seconds: float) -> void:
	_last_ragdoll_impulse = impulse
	_last_ragdoll_impulse_remaining = seconds if impulse.length_squared() > 0.0001 else 0.0


func is_ragdoll_active() -> bool:
	return _ragdoll_active


func is_physics_ragdoll_active() -> bool:
	return _is_quadbot_skeleton_ragdoll_active()


func is_physical_bone_ragdoll_active() -> bool:
	return _is_quadbot_skeleton_ragdoll_active()


func get_ragdoll_anchor_position() -> Variant:
	if _ragdoll_physical_bones.has("Body"):
		var body_bone := _ragdoll_physical_bones.get("Body") as PhysicalBone3D
		if body_bone != null and is_instance_valid(body_bone):
			return body_bone.global_position
	if _visual_root != null and is_instance_valid(_visual_root):
		return _visual_root.global_position
	return _actor.global_position if actor is Node3D else null


func get_visual_foot_anchor_y() -> float:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return INF
	var bounds := _accumulate_mesh_bounds(_visual_root)
	return bounds.position.y if bounds.size.length_squared() > 0.0001 else INF


func get_visual_ground_y() -> float:
	return 0.0


func get_attack_ragdoll_impulse(attacker: Node, damage: float) -> Vector3:
	if attacker == null or not (attacker is Node3D) or not (actor is Node3D):
		return Vector3.ZERO
	var direction := (actor as Node3D).global_position - (attacker as Node3D).global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = Vector3.FORWARD
	return (direction.normalized() + Vector3.UP * 0.18) * clampf(damage * 0.035, 0.35, 3.0)


func get_available_idle_clip_names() -> Array[String]:
	return [_quadbot_idle_clip()] if has_clip(_quadbot_idle_clip()) else []


func _get_quadbot_visual_scene() -> PackedScene:
	if actor == null:
		return null
	var archetype = _actor.get("body_archetype")
	if archetype != null and archetype.get("visual_scene") != null:
		return archetype.get("visual_scene") as PackedScene
	if _actor.has_method("get_quadbot_visual_scene"):
		return _actor.call("get_quadbot_visual_scene") as PackedScene
	return null


func _quadbot_idle_clip() -> String:
	return "Idle"


func _resolve_quadbot_clip(animation_name: String) -> String:
	if animation_name == QUADBOT_DEATH_ANIMATION_NAME:
		return QUADBOT_DEATH_ANIMATION_NAME
	if animation_name == "Idle" or animation_name == "Idle_Tired" or animation_name == "Unarmed_Combat_Idle":
		return "Idle"
	if animation_name == "Walk":
		return "Walk"
	if animation_name == "Jog_Fwd":
		return "Run"
	return animation_name


func _clip_speed(animation_name: String, speed_ratio: float) -> float:
	if animation_name == "Walk":
		return lerpf(0.75, 1.18, clampf(speed_ratio, 0.0, 1.0))
	if animation_name == "Run":
		return lerpf(0.82, 1.28, clampf(speed_ratio, 0.0, 1.0))
	return 1.0


func _start_visual_ragdoll(_is_dead: bool) -> bool:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return false
	stop_clip(true)
	_ragdoll_active = true
	_current_clip = ""
	if _start_quadbot_skeleton_ragdoll():
		return true
	return false


func _start_quadbot_skeleton_ragdoll() -> bool:
	if actor == null or not _ensure_quadbot_runtime_ragdoll():
		return false
	if _ragdoll_skeleton != null and is_instance_valid(_ragdoll_skeleton):
		_ragdoll_skeleton.force_update_all_bone_transforms()
	_ragdoll_simulator.active = true
	_ragdoll_simulator.influence = 1.0
	_ragdoll_simulator.physical_bones_add_collision_exception(_actor.get_rid())
	_configure_quadbot_ragdoll_internal_collision_exceptions()
	_sync_quadbot_ragdoll_physical_bones_to_current_pose()
	_reset_quadbot_ragdoll_body_velocities()
	_ragdoll_simulator.physical_bones_start_simulation()
	_reset_quadbot_ragdoll_body_velocities()
	_apply_quadbot_pending_ragdoll_impulse()
	return true


func _ensure_quadbot_runtime_ragdoll() -> bool:
	if actor == null:
		return false
	if _ragdoll_skeleton == null or not is_instance_valid(_ragdoll_skeleton):
		_ragdoll_skeleton = _find_skeleton(_visual_root) if _visual_root != null else null
		_ragdoll_physical_bones.clear()
		_ragdoll_simulator = null
	if _ragdoll_skeleton == null:
		return false
	if _ragdoll_simulator == null or not is_instance_valid(_ragdoll_simulator):
		_ragdoll_simulator = _ragdoll_skeleton.get_node_or_null(QUADBOT_RAGDOLL_SIMULATOR_NAME) as PhysicalBoneSimulator3D
		if _ragdoll_simulator == null:
			_ragdoll_simulator = PhysicalBoneSimulator3D.new()
			_ragdoll_simulator.name = QUADBOT_RAGDOLL_SIMULATOR_NAME
			_ragdoll_skeleton.add_child(_ragdoll_simulator)
		_ragdoll_simulator.active = false
		_ragdoll_simulator.influence = 1.0
	_create_missing_quadbot_physical_bones()
	return not _ragdoll_physical_bones.is_empty()


func _create_missing_quadbot_physical_bones() -> void:
	if _ragdoll_skeleton == null or _ragdoll_simulator == null:
		return
	for bone_name_value in QUADBOT_RAGDOLL_BONES:
		var bone_name := str(bone_name_value)
		if bone_name.is_empty() or _ragdoll_physical_bones.has(bone_name):
			continue
		var bone_index: int = _ragdoll_skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var physical_bone := _build_quadbot_physical_bone(bone_name, bone_index)
		_ragdoll_simulator.add_child(physical_bone)
		_ragdoll_physical_bones[bone_name] = physical_bone


func _build_quadbot_physical_bone(bone_name: String, bone_index: int) -> PhysicalBone3D:
	var physical_bone := STABLE_PHYSICAL_BONE_SCRIPT.new() as PhysicalBone3D
	physical_bone.name = "PhysicalBone_%s" % bone_name
	physical_bone.bone_name = bone_name
	physical_bone.transform = _ragdoll_skeleton.get_bone_global_rest(bone_index)
	physical_bone.set("max_linear_speed", RAGDOLL_MAX_LINEAR_SPEED)
	physical_bone.set("max_angular_speed", RAGDOLL_MAX_ANGULAR_SPEED)
	physical_bone.mass = _quadbot_bone_mass(bone_name)
	physical_bone.gravity_scale = 1.0
	physical_bone.linear_damp = 0.18
	physical_bone.angular_damp = 0.38
	physical_bone.friction = 0.9
	physical_bone.bounce = 0.02
	physical_bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	physical_bone.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	physical_bone.can_sleep = false
	physical_bone.collision_layer = 1
	physical_bone.collision_mask = 1
	physical_bone.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
	physical_bone.joint_offset = Transform3D.IDENTITY
	physical_bone.set("joint_constraints/swing_span", 70.0)
	physical_bone.set("joint_constraints/twist_span", 35.0)
	physical_bone.set("joint_constraints/bias", 0.25)
	physical_bone.set("joint_constraints/softness", 0.65)
	physical_bone.set("joint_constraints/relaxation", 0.8)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var collision_scale := maxf(_visual_fit_scale, 0.001)
	var bone_length := _get_quadbot_bone_length(bone_name, bone_index) * collision_scale
	var radius := _quadbot_bone_radius(bone_name) * collision_scale
	if bone_name == "Body":
		var box := BoxShape3D.new()
		box.size = Vector3(0.72, 0.58, 0.72) * collision_scale
		shape.shape = box
		physical_bone.body_offset = Transform3D.IDENTITY
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = maxf(bone_length * 0.82, radius * 2.2)
		shape.shape = capsule
		var body_basis := _make_y_axis_basis(_get_quadbot_bone_axis(bone_index))
		physical_bone.body_offset = Transform3D(body_basis, body_basis.y * bone_length * 0.5)
	physical_bone.add_child(shape)
	return physical_bone


func _stop_quadbot_skeleton_ragdoll(reset_pose: bool) -> void:
	if _ragdoll_simulator != null and is_instance_valid(_ragdoll_simulator):
		if _ragdoll_simulator.is_simulating_physics():
			_ragdoll_simulator.physical_bones_stop_simulation()
		if actor != null:
			_ragdoll_simulator.physical_bones_remove_collision_exception(_actor.get_rid())
		_ragdoll_simulator.active = false
	if reset_pose and _ragdoll_skeleton != null and is_instance_valid(_ragdoll_skeleton):
		_ragdoll_skeleton.reset_bone_poses()


func _is_quadbot_skeleton_ragdoll_active() -> bool:
	return _ragdoll_simulator != null and is_instance_valid(_ragdoll_simulator) and _ragdoll_simulator.is_simulating_physics()


func _configure_quadbot_ragdoll_internal_collision_exceptions() -> void:
	if actor == null:
		return
	var bones: Array[PhysicalBone3D] = []
	for physical_bone_value in _ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone != null and is_instance_valid(physical_bone):
			bones.append(physical_bone)
	for first_index in range(bones.size()):
		for second_index in range(first_index + 1, bones.size()):
			PhysicsServer3D.body_add_collision_exception(bones[first_index].get_rid(), bones[second_index].get_rid())
			PhysicsServer3D.body_add_collision_exception(bones[second_index].get_rid(), bones[first_index].get_rid())


func _sync_quadbot_ragdoll_physical_bones_to_current_pose() -> void:
	if _ragdoll_skeleton == null or not is_instance_valid(_ragdoll_skeleton):
		return
	_ragdoll_skeleton.force_update_all_bone_transforms()
	for bone_name_value in _ragdoll_physical_bones.keys():
		var bone_name := str(bone_name_value)
		var physical_bone := _ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		var bone_index: int = _ragdoll_skeleton.find_bone(bone_name)
		if bone_index >= 0:
			physical_bone.transform = _ragdoll_skeleton.get_bone_global_pose(bone_index)


func _reset_quadbot_ragdoll_body_velocities() -> void:
	for physical_bone_value in _ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		physical_bone.linear_velocity = Vector3.ZERO
		physical_bone.angular_velocity = Vector3.ZERO
		if physical_bone.has_method("set_upward_velocity_suppression_frames"):
			physical_bone.call("set_upward_velocity_suppression_frames", RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES)
	_ragdoll_upward_velocity_suppression_frames = RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES


func _apply_quadbot_pending_ragdoll_impulse() -> void:
	if _last_ragdoll_impulse.length_squared() <= 0.0001 or _last_ragdoll_impulse_remaining <= 0.0:
		return
	var impulse: Vector3 = _last_ragdoll_impulse
	if impulse.y > 0.0:
		impulse.y = 0.0
	var body_bone := _ragdoll_physical_bones.get("Body", null) as PhysicalBone3D
	if body_bone != null and is_instance_valid(body_bone):
		body_bone.apply_central_impulse(impulse)
	for bone_name in ["Front_Shoulder.L", "Front_Shoulder.R", "Back_Shoulder.L", "Back_Shoulder.R"]:
		var physical_bone := _ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
		if physical_bone != null and is_instance_valid(physical_bone):
			physical_bone.apply_central_impulse(impulse * 0.25)
	_last_ragdoll_impulse = Vector3.ZERO
	_last_ragdoll_impulse_remaining = 0.0


func _find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null


func _quadbot_bone_mass(bone_name: String) -> float:
	if bone_name == "Body":
		return 3.2
	if bone_name.contains("Shoulder"):
		return 0.55
	return 0.28


func _quadbot_bone_radius(bone_name: String) -> float:
	if bone_name.contains("Shoulder"):
		return 0.08
	if bone_name.contains("Leg1"):
		return 0.075
	return 0.055


func _get_quadbot_bone_axis(bone_index: int) -> Vector3:
	var child_vector := _get_quadbot_child_vector(bone_index)
	if child_vector.length_squared() > 0.0001:
		return child_vector.normalized()
	var rest: Transform3D = _ragdoll_skeleton.get_bone_rest(bone_index)
	if rest.origin.length_squared() > 0.0001:
		return (rest.basis.inverse() * rest.origin).normalized()
	return Vector3.UP


func _get_quadbot_child_vector(bone_index: int) -> Vector3:
	var best_vector := Vector3.ZERO
	var best_length_squared := 0.0
	for child_index in _ragdoll_skeleton.get_bone_children(bone_index):
		var child_vector: Vector3 = _ragdoll_skeleton.get_bone_rest(child_index).origin
		var child_length_squared := child_vector.length_squared()
		if child_length_squared > best_length_squared:
			best_vector = child_vector
			best_length_squared = child_length_squared
	return best_vector


func _get_quadbot_bone_length(bone_name: String, bone_index: int) -> float:
	var child_vector := _get_quadbot_child_vector(bone_index)
	if child_vector.length() > 0.02:
		return child_vector.length()
	if bone_name.contains("Shoulder"):
		return 0.28
	return 0.24


func _make_y_axis_basis(axis: Vector3) -> Basis:
	var y_axis := axis.normalized()
	if y_axis.length_squared() <= 0.0001:
		return Basis.IDENTITY
	var reference_axis := Vector3.UP
	if absf(y_axis.dot(reference_axis)) > 0.92:
		reference_axis = Vector3.FORWARD
	var x_axis := reference_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


func _fit_visual_to_actor_body(body_mesh: MeshInstance3D) -> void:
	if _visual_root == null:
		return
	var bounds := _accumulate_mesh_bounds(_model_root)
	if bounds.size.length_squared() <= 0.0001:
		_visual_root.position = Vector3(0.0, 0.85, 0.0)
		return
	var target_height := 1.35
	if body_mesh != null and body_mesh.mesh != null:
		var body_bounds := body_mesh.mesh.get_aabb()
		target_height = maxf(1.0, body_bounds.size.y * body_mesh.scale.y * 1.15)
	var scale_ratio := clampf(target_height / maxf(bounds.size.y, 0.001), 0.45, 2.2)
	_visual_fit_scale = scale_ratio
	_bake_visual_scale(_model_root, scale_ratio)
	var scaled_bounds := AABB(bounds.position * scale_ratio, bounds.size * scale_ratio)
	_model_root.position = Vector3(-scaled_bounds.get_center().x, -scaled_bounds.position.y, -scaled_bounds.get_center().z)
	_visual_root.position = Vector3(0.0, QUADBOT_VISUAL_FLOOR_CLEARANCE, 0.0)


func _bake_visual_scale(root_node: Node, scale_ratio: float) -> void:
	if root_node == null or is_equal_approx(scale_ratio, 1.0):
		return
	for node in _collect_descendants(root_node):
		if node is MeshInstance3D:
			_bake_mesh_instance_scale(node as MeshInstance3D, scale_ratio)
		if node is Skeleton3D:
			_bake_skeleton_scale(node as Skeleton3D, scale_ratio)


func _collect_descendants(root_node: Node) -> Array[Node]:
	var result: Array[Node] = [root_node]
	for child in root_node.get_children():
		result.append_array(_collect_descendants(child))
	return result


func _bake_mesh_instance_scale(mesh_instance: MeshInstance3D, scale_ratio: float) -> void:
	if mesh_instance.mesh is ArrayMesh:
		mesh_instance.mesh = _scaled_array_mesh(mesh_instance.mesh as ArrayMesh, scale_ratio)
	if mesh_instance.skin != null:
		mesh_instance.skin = _scaled_skin(mesh_instance.skin, scale_ratio)


func _scaled_array_mesh(source: ArrayMesh, scale_ratio: float) -> ArrayMesh:
	var copy := ArrayMesh.new()
	for surface_index in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for vertex_index in range(vertices.size()):
			vertices[vertex_index] *= scale_ratio
		arrays[Mesh.ARRAY_VERTEX] = vertices
		copy.add_surface_from_arrays(source.surface_get_primitive_type(surface_index), arrays)
		copy.surface_set_material(surface_index, source.surface_get_material(surface_index))
	return copy


func _scaled_skin(source: Skin, scale_ratio: float) -> Skin:
	var copy := source.duplicate(true) as Skin
	for bind_index in range(copy.get_bind_count()):
		var pose := copy.get_bind_pose(bind_index)
		pose.origin *= scale_ratio
		copy.set_bind_pose(bind_index, pose)
	return copy


func _bake_skeleton_scale(skeleton: Skeleton3D, scale_ratio: float) -> void:
	skeleton.motion_scale = scale_ratio
	for bone_index in range(skeleton.get_bone_count()):
		var rest := skeleton.get_bone_rest(bone_index)
		rest.origin *= scale_ratio
		skeleton.set_bone_rest(bone_index, rest)
		var pose := skeleton.get_bone_pose(bone_index)
		pose.origin *= scale_ratio
		skeleton.set_bone_pose(bone_index, pose)
	skeleton.force_update_all_bone_transforms()


func _configure_quadbot_meshes(root: Node) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in root.get_children():
		_configure_quadbot_meshes(child)


func _accumulate_mesh_bounds(root: Node) -> AABB:
	return _accumulate_mesh_bounds_from(root, Transform3D.IDENTITY)


func _accumulate_mesh_bounds_from(root: Node, parent_transform: Transform3D) -> AABB:
	var result := {"has_bounds": false, "bounds": AABB()}
	_accumulate_mesh_bounds_recursive(root, parent_transform, result)
	return result["bounds"] if bool(result["has_bounds"]) else AABB()


func _accumulate_mesh_bounds_recursive(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	if node == null:
		return
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_bounds := _transform_aabb((node as MeshInstance3D).mesh.get_aabb(), local_transform)
		if bool(result["has_bounds"]):
			result["bounds"] = (result["bounds"] as AABB).merge(mesh_bounds)
		else:
			result["bounds"] = mesh_bounds
			result["has_bounds"] = true
	for child in node.get_children():
		_accumulate_mesh_bounds_recursive(child, local_transform, result)


func _transform_aabb(bounds: AABB, transform_value: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := transform_value * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds


func _accumulate_physical_bone_shape_bounds(physical_bone: PhysicalBone3D, result: Dictionary) -> void:
	for child in physical_bone.get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape == null or collision_shape.shape == null:
			continue
		var local_bounds := _collision_shape_local_bounds(collision_shape.shape)
		if local_bounds.size.length_squared() <= 0.0001:
			continue
		var shape_transform := physical_bone.global_transform * physical_bone.body_offset * collision_shape.transform
		var world_bounds := _transform_aabb(local_bounds, shape_transform)
		if bool(result["has_bounds"]):
			result["bounds"] = (result["bounds"] as AABB).merge(world_bounds)
		else:
			result["bounds"] = world_bounds
			result["has_bounds"] = true


func _accumulate_point_bounds(point: Vector3, result: Dictionary) -> void:
	if bool(result["has_bounds"]):
		result["bounds"] = (result["bounds"] as AABB).expand(point)
	else:
		result["bounds"] = AABB(point, Vector3.ZERO)
		result["has_bounds"] = true


func _collision_shape_local_bounds(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var radius := maxf(capsule.radius, 0.0)
		var height := maxf(capsule.height, radius * 2.0)
		return AABB(Vector3(-radius, -height * 0.5, -radius), Vector3(radius * 2.0, height, radius * 2.0))
	if shape is SphereShape3D:
		var radius := maxf((shape as SphereShape3D).radius, 0.0)
		return AABB(Vector3.ONE * -radius, Vector3.ONE * radius * 2.0)
	return AABB()


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


func _free_visual_root() -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.free()
	_visual_root = null
	_model_root = null
