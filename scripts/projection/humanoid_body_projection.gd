extends "res://scripts/projection/body_projection_adapter.gd"

class_name HumanoidBodyProjection

const HUMAN_RACE := preload("res://resources/character_races/human.tres")
const HUMAN_MALE_BODY := preload("res://resources/character_body_archetypes/human_male.tres")
const HUMANOID_RAGDOLL_PROFILE_SCRIPT := preload("res://scripts/characters/humanoid_ragdoll_profile.gd")
const STABLE_PHYSICAL_BONE_SCRIPT := preload("res://scripts/characters/stable_physical_bone.gd")
const UAL1_ANIMATION_SOURCE_SCENE := preload("res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb")
const UAL2_ANIMATION_SOURCE_SCENE := preload("res://assets/vendor/quaternius/universal_animation_library_2/UAL2.glb")
const DEFAULT_GRIP_SOCKET_PROFILE := preload("res://resources/humanoid_grip_socket_profiles/default.tres")

const WORLD_VISUAL_NODE_NAME := "BodyVisual"
const PORTRAIT_SOURCE_NODE_NAME := "PortraitVisualSource"
const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const CHARACTER_ANIMATION_PLAYER_NAME := "CharacterAnimationPlayer"
const PORTRAIT_CHARACTER_VISUAL_YAW_OFFSET := PI
const IDLE_ANIMATION_NAME := "Idle"
const WALK_ANIMATION_NAME := "Walk"
const CROUCH_IDLE_ANIMATION_NAME := "Crouch_Idle"
const CROUCH_WALK_ANIMATION_NAME := "Crouch_Fwd"
const JOG_ANIMATION_NAME := "Jog_Fwd"
const IDLE_SAMPLE_SECONDS := 0.45
const EQUIPMENT_VISUAL_META := "projection_equipment_visual"
const COMBAT_IDLE_ANIMATION_CANDIDATES := ["Unarmed_Combat_Idle", "Combat_Idle", "Idle"]
const ATTACK_ANIMATION_CANDIDATES := ["Melee_Hook", "Melee_Knee", "Punch", "Punching", "Kick", "Kick_Fwd"]
const REACTION_ANIMATION_CANDIDATES := ["Hit", "Hit_Chest", "Hit_Head", "Hit_Stomach", "Damage", "Dodge"]
const BLOCK_ANIMATION_CANDIDATES := ["Block", "Shield_Block", "Parry"]
const DOWNED_ANIMATION_CANDIDATES := ["Death", "Death_A", "Death_Back", "Death_Fwd"]
const RAGDOLL_COLLIDER_LENGTH_SCALE := 0.82
const RAGDOLL_MAX_LINEAR_SPEED := 10.0
const RAGDOLL_MAX_ANGULAR_SPEED := 18.0
const RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES := 90
const RAGDOLL_ACTIVATIONS_PER_PHYSICS_FRAME := 2
const BONE_EQUIPMENT_SLOTS := {
	"weapon": "hand_r",
	"offhand": "hand_l",
}

var _body_archetype: Resource
var _body_archetype_path := ""
var _body_visual: Node3D
var _skeleton: Skeleton3D
var _equipment_root: Node3D
var _label: Label3D
var _equipment_signature := ""
var _character_animation_player: AnimationPlayer
var _current_world_animation := ""
var _current_combat_event_id := ""
var _default_ragdoll_profile: Resource
var _ragdoll_simulator: PhysicalBoneSimulator3D
var _ragdoll_skeleton: Skeleton3D
var _ragdoll_physical_bones: Dictionary = {}
var _is_ragdoll_active := false
var _ragdoll_requested := false
var _ragdoll_request_event_id := ""
var _ragdoll_seed := 0
var _ragdoll_preroll_active := false
var _ragdoll_preroll_animation_name := ""
var _ragdoll_preroll_remaining := 0.0
var _ragdoll_upward_velocity_suppression_frames := 0

static var _ragdoll_activation_frame := -1
static var _ragdoll_activation_count := 0

var _portrait_source: Node3D
var _portrait_character_visual: Node3D
var _portrait_skeleton: Skeleton3D
var _portrait_animation_player: AnimationPlayer
var _portrait_equipment_signature := ""
var _last_equipment_slots: Dictionary = {}


func apply_projection_snapshot(record: Dictionary, equipment_slots: Dictionary, combat_state: Dictionary = {}) -> void:
	var body_archetype := _body_archetype_from_record(record)
	_ensure_body_visual(body_archetype)
	_last_equipment_slots = equipment_slots.duplicate(true)
	_apply_label(record)
	_apply_life_state(record, combat_state)
	_sync_equipment(equipment_slots)
	if _portrait_source != null and is_instance_valid(_portrait_source):
		_sync_portrait_equipment(equipment_slots)
	_apply_locomotion_state(record)


func get_body_adapter_id() -> String:
	return "humanoid"


func get_portrait_source() -> Node:
	_ensure_portrait_source(_body_archetype if _body_archetype != null else HUMAN_MALE_BODY)
	_sync_portrait_equipment(_last_equipment_slots)
	return _portrait_source if _portrait_source != null and is_instance_valid(_portrait_source) else self


func _process(delta: float) -> void:
	if _ragdoll_preroll_active:
		_process_downed_ragdoll_preroll(delta)
		return
	if _ragdoll_requested and not _is_ragdoll_active and _can_activate_ragdoll_this_frame():
		_finish_downed_ragdoll_preroll()


func _physics_process(delta: float) -> void:
	if _is_ragdoll_active:
		_stabilize_active_ragdoll(delta)


func get_projection_debug_state() -> Dictionary:
	return {
		"body_adapter_id": get_body_adapter_id(),
		"body_archetype": _body_archetype_path,
		"world_visual_ready": _body_visual != null and _body_visual.name == WORLD_VISUAL_NODE_NAME,
		"world_skeleton_ready": _skeleton != null,
		"world_idle_animation_ready": _character_animation_player != null and _character_animation_player.has_animation(IDLE_ANIMATION_NAME),
		"world_animation": _current_world_animation,
		"combat_event_id": _current_combat_event_id,
		"ragdoll_requested": _ragdoll_requested,
		"ragdoll_preroll_active": _ragdoll_preroll_active,
		"ragdoll_active": _is_ragdoll_active,
		"ragdoll_physical_bone_count": _ragdoll_physical_bones.size(),
		"portrait_source_ready": _portrait_source != null,
		"portrait_character_visual_ready": _portrait_character_visual != null and _portrait_character_visual.name == CHARACTER_VISUAL_NODE_NAME,
		"portrait_skeleton_ready": _portrait_skeleton != null,
		"portrait_idle_animation_ready": _portrait_animation_player != null and _portrait_animation_player.has_animation(IDLE_ANIMATION_NAME),
		"attached_item_paths": _attached_item_paths(),
	}


func apply_combat_presentation(presentation: Dictionary) -> void:
	if _character_animation_player == null:
		return
	var state := str(presentation.get("state", "combat_idle")).strip_edges()
	var event_id := str(presentation.get("event_id", state)).strip_edges()
	var progress := clampf(float(presentation.get("progress", 0.0)), 0.0, 1.0)
	var is_downed_state := state == "downed" or state == "downed_start" or state == "downed_hold"
	if is_downed_state:
		_ragdoll_seed = int(presentation.get("downed_seed", _stable_text_hash(event_id)))
	if not is_downed_state and _is_ragdoll_active:
		_stop_ragdoll_simulation(true)
	if not is_downed_state:
		_cancel_ragdoll_preroll()
		_ragdoll_requested = false
	match state:
		"move":
			_current_combat_event_id = event_id
			_play_world_animation(WALK_ANIMATION_NAME, 0.95)
		"attack_start":
			_play_combat_once_animation(event_id, ATTACK_ANIMATION_CANDIDATES, 1.0)
		"attack_hold":
			_hold_combat_once_animation(event_id, ATTACK_ANIMATION_CANDIDATES)
		"attack":
			_play_combat_progress_animation(event_id, ATTACK_ANIMATION_CANDIDATES, progress, 1.0)
		"reaction_start":
			_play_combat_once_animation(event_id, REACTION_ANIMATION_CANDIDATES, 1.0)
		"reaction_hold":
			_hold_combat_once_animation(event_id, REACTION_ANIMATION_CANDIDATES)
		"reaction":
			_play_combat_progress_animation(event_id, REACTION_ANIMATION_CANDIDATES, progress, 1.0)
		"block":
			_play_combat_progress_animation(event_id, BLOCK_ANIMATION_CANDIDATES, progress, 1.0)
		"downed_start", "downed_hold":
			_request_downed_ragdoll(event_id)
		"downed":
			_request_downed_ragdoll(event_id)
			if not _is_ragdoll_active and not _ragdoll_preroll_active:
				_play_combat_progress_animation(event_id, DOWNED_ANIMATION_CANDIDATES, progress, 1.0)
		_:
			_current_combat_event_id = ""
			_play_first_available_loop(COMBAT_IDLE_ANIMATION_CANDIDATES)


func get_combat_presentation_duration(presentation_state: String, event_id: String, fallback: float) -> float:
	var state := str(presentation_state).strip_edges()
	var animation_name := ""
	match state:
		"attack", "attack_start", "attack_hold":
			animation_name = _deterministic_available_animation(ATTACK_ANIMATION_CANDIDATES, event_id)
		"reaction", "reaction_start", "reaction_hold":
			animation_name = _deterministic_available_animation(REACTION_ANIMATION_CANDIDATES, event_id)
		"block":
			animation_name = _deterministic_available_animation(BLOCK_ANIMATION_CANDIDATES, event_id)
		"downed", "downed_start", "downed_hold":
			animation_name = _choose_downed_preroll_animation(event_id)
	if animation_name.is_empty():
		return fallback
	var length := _get_character_animation_length(animation_name)
	return length if length > 0.0 else fallback


func get_combat_impact_ratio(presentation_state: String, _event_id: String, fallback: float) -> float:
	var state := str(presentation_state).strip_edges()
	if state == "attack" or state == "attack_start" or state == "attack_hold":
		return 0.45
	return fallback


func _body_archetype_from_record(record: Dictionary) -> Resource:
	var appearance: Dictionary = record.get("appearance", {}) if record.get("appearance", {}) is Dictionary else {}
	var body_path := str(appearance.get("body_archetype", "")).strip_edges()
	var body := load(body_path) as Resource if not body_path.is_empty() else null
	if body != null:
		return body
	var race_path := str(appearance.get("character_race", "")).strip_edges()
	var race := load(race_path) as Resource if not race_path.is_empty() else null
	var visual_body_type := int(appearance.get("visual_body_type", 2))
	if race != null:
		var property_name := "default_female_archetype" if visual_body_type == 3 else "default_male_archetype"
		body = race.get(property_name) as Resource
		if body != null:
			return body
	return HUMAN_MALE_BODY


func _ensure_body_visual(body_archetype: Resource) -> void:
	var target_path := _resource_path(body_archetype)
	if _body_visual != null and target_path == _body_archetype_path:
		return
	_clear_children()
	_body_archetype = body_archetype
	_body_archetype_path = target_path
	_body_visual = Node3D.new()
	_body_visual.name = WORLD_VISUAL_NODE_NAME
	add_child(_body_visual)
	var model_root := _instantiate_body_model(body_archetype)
	if model_root != null:
		_body_visual.add_child(model_root)
		_character_animation_player = _setup_character_animation(model_root, true)
		_play_idle_pose(_character_animation_player)
		_skeleton = _find_skeleton(model_root)
	_equipment_root = Node3D.new()
	_equipment_root.name = "EquipmentProjection"
	add_child(_equipment_root)
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.position = Vector3(0.0, 2.05, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 22
	add_child(_label)
	_equipment_signature = ""
	_portrait_equipment_signature = ""
	_current_world_animation = ""
	_current_combat_event_id = ""


func _ensure_portrait_source(body_archetype: Resource) -> void:
	if _portrait_source != null and is_instance_valid(_portrait_source):
		return
	_portrait_source = Node3D.new()
	_portrait_source.name = PORTRAIT_SOURCE_NODE_NAME
	_portrait_source.visible = false
	add_child(_portrait_source)
	_portrait_character_visual = Node3D.new()
	_portrait_character_visual.name = CHARACTER_VISUAL_NODE_NAME
	_portrait_source.add_child(_portrait_character_visual)
	var model_root := _instantiate_body_model(body_archetype)
	if model_root == null:
		return
	model_root.rotation.y = PORTRAIT_CHARACTER_VISUAL_YAW_OFFSET
	_portrait_character_visual.add_child(model_root)
	_portrait_animation_player = _setup_character_animation(model_root, false)
	_play_idle_pose(_portrait_animation_player)
	_portrait_skeleton = _find_skeleton(model_root)


func _instantiate_body_model(body_archetype: Resource) -> Node3D:
	var visual_scene: PackedScene
	if body_archetype != null:
		visual_scene = body_archetype.get("visual_scene") as PackedScene
	if visual_scene == null:
		return null
	var instance := visual_scene.instantiate()
	if instance is Node3D:
		return instance as Node3D
	if instance != null:
		instance.queue_free()
	return null


func _clear_children() -> void:
	_stop_ragdoll_simulation(true)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_body_visual = null
	_equipment_root = null
	_skeleton = null
	_label = null
	_character_animation_player = null
	_portrait_source = null
	_portrait_character_visual = null
	_portrait_skeleton = null
	_portrait_animation_player = null
	_ragdoll_simulator = null
	_ragdoll_skeleton = null
	_ragdoll_physical_bones.clear()
	_ragdoll_requested = false
	_cancel_ragdoll_preroll()


func _apply_label(record: Dictionary) -> void:
	if _label != null:
		_label.text = str(record.get("member_name", record.get("actor_id", "Actor")))


func _apply_life_state(record: Dictionary, _combat_state: Dictionary) -> void:
	if _label != null:
		_label.modulate = Color(0.65, 0.65, 0.65, 1.0) if int(record.get("life_state", 0)) != 0 else Color.WHITE


func _apply_locomotion_state(record: Dictionary) -> void:
	if _character_animation_player == null:
		return
	if int(record.get("life_state", 0)) != 0:
		var downed_event_id := _record_downed_event_id(record)
		apply_combat_presentation({"state": "downed_hold", "event_id": downed_event_id, "downed_seed": int(record.get("downed_presentation_seed", _stable_text_hash(downed_event_id)))})
		return
	var locomotion_state: Dictionary = record.get("locomotion_state", {}) if record.get("locomotion_state", {}) is Dictionary else {}
	var animation_state := str(locomotion_state.get("animation_state", ""))
	if animation_state.is_empty():
		var movement_mode := int(record.get("movement_mode", 0))
		animation_state = "sneak_idle" if movement_mode == 2 else "idle"
	match animation_state:
		"run":
			_play_world_animation(JOG_ANIMATION_NAME, _animation_speed_scale(float(locomotion_state.get("horizontal_speed", 0.0)), float(locomotion_state.get("speed", 0.0)), 0.9, 1.35))
		"sneak":
			_play_world_animation(CROUCH_WALK_ANIMATION_NAME, _animation_speed_scale(float(locomotion_state.get("horizontal_speed", 0.0)), float(locomotion_state.get("speed", 0.0)), 0.85, 1.15))
		"sneak_idle":
			_play_world_animation(CROUCH_IDLE_ANIMATION_NAME)
		"walk":
			_play_world_animation(WALK_ANIMATION_NAME, _animation_speed_scale(float(locomotion_state.get("horizontal_speed", 0.0)), float(locomotion_state.get("speed", 0.0)), 0.85, 1.25))
		_:
			_play_world_animation(IDLE_ANIMATION_NAME)


func _play_world_animation(animation_name: String, speed_scale := 1.0) -> void:
	if _character_animation_player == null or not _character_animation_player.has_animation(animation_name):
		return
	_character_animation_player.speed_scale = maxf(speed_scale, 0.01)
	if _current_world_animation == animation_name and _character_animation_player.is_playing():
		return
	_current_world_animation = animation_name
	_character_animation_player.play(animation_name, 0.12)
	_character_animation_player.advance(0.0)


func _animation_speed_scale(horizontal_speed: float, reference_speed: float, min_scale: float, max_scale: float) -> float:
	var ratio := clampf(horizontal_speed / maxf(reference_speed, 0.001), 0.0, 1.0)
	return lerpf(min_scale, max_scale, ratio)


func _get_ragdoll_profile():
	if _default_ragdoll_profile == null:
		_default_ragdoll_profile = HUMANOID_RAGDOLL_PROFILE_SCRIPT.new()
	return _default_ragdoll_profile


func _request_downed_ragdoll(event_id: String) -> void:
	if _is_ragdoll_active:
		return
	if _ragdoll_requested and _ragdoll_request_event_id == event_id:
		return
	_ragdoll_requested = true
	_ragdoll_request_event_id = event_id
	if not _begin_downed_ragdoll_preroll():
		if _can_activate_ragdoll_this_frame():
			_finish_downed_ragdoll_preroll()


func _begin_downed_ragdoll_preroll() -> bool:
	if _character_animation_player == null:
		return false
	var animation_name := _choose_downed_preroll_animation(_ragdoll_request_event_id)
	if animation_name.is_empty():
		return false
	var animation_length := _get_character_animation_length(animation_name)
	var preroll_duration := _choose_downed_preroll_duration(animation_length, _ragdoll_request_event_id)
	if preroll_duration <= 0.0:
		return false
	_ragdoll_preroll_active = true
	_ragdoll_preroll_animation_name = animation_name
	_ragdoll_preroll_remaining = preroll_duration
	_play_world_animation(animation_name, 1.0)
	return true


func _process_downed_ragdoll_preroll(delta: float) -> void:
	_ragdoll_preroll_remaining = maxf(0.0, _ragdoll_preroll_remaining - delta)
	if _ragdoll_preroll_remaining > 0.0 and _character_animation_player != null and _character_animation_player.is_playing():
		return
	if _can_activate_ragdoll_this_frame():
		_finish_downed_ragdoll_preroll()


func _finish_downed_ragdoll_preroll() -> void:
	if _is_ragdoll_active:
		_cancel_ragdoll_preroll()
		return
	_cancel_ragdoll_preroll()
	_stop_character_animation(true)
	_start_ragdoll_simulation()


func _cancel_ragdoll_preroll() -> void:
	_ragdoll_preroll_active = false
	_ragdoll_preroll_animation_name = ""
	_ragdoll_preroll_remaining = 0.0


func _choose_downed_preroll_animation(event_id := "") -> String:
	var profile = _get_ragdoll_profile()
	if profile != null and profile.has_method("choose_downed_preroll_animation"):
		return profile.choose_downed_preroll_animation(_character_animation_player, _rng_for_downed_event(event_id))
	return ""


func _choose_downed_preroll_duration(animation_length: float, event_id := "") -> float:
	var profile = _get_ragdoll_profile()
	if profile != null and profile.has_method("choose_downed_preroll_duration"):
		return profile.choose_downed_preroll_duration(animation_length, _rng_for_downed_event(event_id))
	return animation_length


func _get_character_animation_length(animation_name: String) -> float:
	if _character_animation_player == null or animation_name.is_empty() or not _character_animation_player.has_animation(animation_name):
		return 0.0
	var animation := _character_animation_player.get_animation(animation_name)
	return animation.length if animation != null else 0.0


func _stop_character_animation(reset_pose: bool) -> void:
	if _character_animation_player != null:
		_character_animation_player.stop(reset_pose)
	_current_world_animation = ""
	_current_combat_event_id = ""


func _rng_for_ragdoll() -> RandomNumberGenerator:
	return _rng_for_downed_event(_ragdoll_request_event_id)


func _rng_for_downed_event(event_id: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var seed := _ragdoll_seed if _ragdoll_seed != 0 else _stable_text_hash(event_id)
	rng.seed = maxi(abs(seed), 1)
	return rng


func _record_downed_event_id(record: Dictionary) -> String:
	var event_id := str(record.get("downed_event_id", "")).strip_edges()
	if not event_id.is_empty():
		return event_id
	return "%s:downed" % str(record.get("actor_id", record.get("stable_id", "unknown"))).strip_edges()


func _stable_text_hash(value: String) -> int:
	var result := 0
	for index in range(value.length()):
		result = (result * 31 + value.unicode_at(index)) % 2147483647
	return result


func _can_activate_ragdoll_this_frame() -> bool:
	var frame := Engine.get_physics_frames()
	if _ragdoll_activation_frame != frame:
		_ragdoll_activation_frame = frame
		_ragdoll_activation_count = 0
	if _ragdoll_activation_count >= RAGDOLL_ACTIVATIONS_PER_PHYSICS_FRAME:
		return false
	_ragdoll_activation_count += 1
	return true


func _start_ragdoll_simulation() -> bool:
	if not _ensure_runtime_ragdoll():
		return false
	_is_ragdoll_active = true
	_ragdoll_requested = false
	if _ragdoll_skeleton != null and is_instance_valid(_ragdoll_skeleton):
		_ragdoll_skeleton.force_update_all_bone_transforms()
	_ragdoll_simulator.active = true
	_ragdoll_simulator.influence = 1.0
	_configure_ragdoll_internal_collision_exceptions()
	_sync_ragdoll_physical_bones_to_current_pose()
	_prepare_ragdoll_activation()
	_reset_ragdoll_body_velocities()
	_ragdoll_simulator.physical_bones_start_simulation()
	_reset_ragdoll_body_velocities()
	_clamp_ragdoll_upward_velocities()
	return true


func _stop_ragdoll_simulation(reset_pose: bool) -> void:
	if _ragdoll_simulator != null and is_instance_valid(_ragdoll_simulator):
		if _ragdoll_simulator.is_simulating_physics():
			_ragdoll_simulator.physical_bones_stop_simulation()
		_ragdoll_simulator.active = false
	if _ragdoll_skeleton != null and is_instance_valid(_ragdoll_skeleton) and reset_pose:
		_ragdoll_skeleton.reset_bone_poses()
	_is_ragdoll_active = false
	_ragdoll_upward_velocity_suppression_frames = 0
	_set_ragdoll_bone_upward_velocity_suppression(0)


func _ensure_runtime_ragdoll() -> bool:
	if _ragdoll_skeleton == null or not is_instance_valid(_ragdoll_skeleton):
		_ragdoll_skeleton = _skeleton
		_ragdoll_physical_bones.clear()
		_ragdoll_simulator = null
	if _ragdoll_skeleton == null:
		return false
	if _ragdoll_simulator == null or not is_instance_valid(_ragdoll_simulator):
		_ragdoll_simulator = _ragdoll_skeleton.get_node_or_null("HumanoidRagdollSimulator") as PhysicalBoneSimulator3D
		if _ragdoll_simulator == null:
			_ragdoll_simulator = PhysicalBoneSimulator3D.new()
			_ragdoll_simulator.name = "HumanoidRagdollSimulator"
			_ragdoll_skeleton.add_child(_ragdoll_simulator)
		_ragdoll_simulator.active = false
		_ragdoll_simulator.influence = 1.0
	_create_missing_ragdoll_physical_bones()
	return not _ragdoll_physical_bones.is_empty()


func _create_missing_ragdoll_physical_bones() -> void:
	var profile = _get_ragdoll_profile()
	if profile == null:
		return
	for bone_name_value in profile.physical_bone_names:
		var bone_name := String(bone_name_value)
		if bone_name.is_empty() or _ragdoll_physical_bones.has(bone_name):
			continue
		var bone_index := _ragdoll_skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var physical_bone := _build_ragdoll_physical_bone(profile, bone_name, bone_index)
		_ragdoll_simulator.add_child(physical_bone)
		_ragdoll_physical_bones[bone_name] = physical_bone


func _build_ragdoll_physical_bone(profile, bone_name: String, bone_index: int) -> PhysicalBone3D:
	var physical_bone := STABLE_PHYSICAL_BONE_SCRIPT.new() as PhysicalBone3D
	physical_bone.name = "PhysicalBone_%s" % bone_name
	physical_bone.bone_name = bone_name
	physical_bone.transform = _ragdoll_skeleton.get_bone_global_rest(bone_index)
	physical_bone.set("max_linear_speed", RAGDOLL_MAX_LINEAR_SPEED)
	physical_bone.set("max_angular_speed", RAGDOLL_MAX_ANGULAR_SPEED)
	physical_bone.mass = maxf(0.05, float(profile.get_bone_mass(bone_name)))
	physical_bone.gravity_scale = float(profile.get("gravity_scale"))
	physical_bone.linear_damp = float(profile.get("linear_damp"))
	physical_bone.angular_damp = float(profile.get("angular_damp"))
	physical_bone.friction = float(profile.get("friction"))
	physical_bone.bounce = float(profile.get("bounce"))
	physical_bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	physical_bone.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	physical_bone.can_sleep = false
	physical_bone.collision_layer = int(profile.get("collision_layer"))
	physical_bone.collision_mask = int(profile.get("collision_mask"))
	physical_bone.joint_type = int(profile.get_bone_joint_type(bone_name)) as PhysicalBone3D.JointType
	physical_bone.joint_offset = Transform3D.IDENTITY
	_apply_ragdoll_joint_constraints(profile, physical_bone, bone_name)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var bone_length := _get_ragdoll_bone_length(profile, bone_name, bone_index)
	var radius := float(profile.get_bone_radius(bone_name))
	var body_basis := _get_ragdoll_body_basis(profile, bone_name, bone_index)
	var center_distance := 0.0 if bone_name == str(profile.get("root_bone_name")) else bone_length * 0.5
	if bool(profile.should_use_box_shape(bone_name)):
		var box := BoxShape3D.new()
		box.size = _get_ragdoll_box_size(bone_name, bone_length, radius)
		shape.shape = box
		physical_bone.body_offset = Transform3D(body_basis, body_basis.y * center_distance)
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = maxf(bone_length * RAGDOLL_COLLIDER_LENGTH_SCALE, radius * 2.2)
		shape.shape = capsule
		physical_bone.body_offset = Transform3D(body_basis, body_basis.y * center_distance)
	physical_bone.add_child(shape)
	return physical_bone


func _apply_ragdoll_joint_constraints(profile, physical_bone: PhysicalBone3D, bone_name: String) -> void:
	match int(profile.get_bone_joint_type(bone_name)):
		PhysicalBone3D.JOINT_TYPE_CONE:
			var swing_span := float(profile.get_bone_cone_swing_span_degrees(bone_name)) if profile.has_method("get_bone_cone_swing_span_degrees") else 45.0
			var twist_span := float(profile.get_bone_cone_twist_span_degrees(bone_name)) if profile.has_method("get_bone_cone_twist_span_degrees") else 25.0
			physical_bone.set("joint_constraints/swing_span", swing_span)
			physical_bone.set("joint_constraints/twist_span", twist_span)
			physical_bone.set("joint_constraints/bias", _get_ragdoll_profile_float("cone_bias", 0.25))
			physical_bone.set("joint_constraints/softness", _get_ragdoll_profile_float("cone_softness", 0.65))
			physical_bone.set("joint_constraints/relaxation", _get_ragdoll_profile_float("cone_relaxation", 0.8))
		PhysicalBone3D.JOINT_TYPE_HINGE:
			physical_bone.set("joint_constraints/angular_limit_enabled", true)
			physical_bone.set("joint_constraints/angular_limit_lower", _get_ragdoll_profile_float("hinge_limit_lower_degrees", -12.0))
			physical_bone.set("joint_constraints/angular_limit_upper", _get_ragdoll_profile_float("hinge_limit_upper_degrees", 95.0))
			physical_bone.set("joint_constraints/angular_limit_bias", _get_ragdoll_profile_float("hinge_bias", 0.25))
			physical_bone.set("joint_constraints/angular_limit_softness", _get_ragdoll_profile_float("hinge_softness", 0.75))
			physical_bone.set("joint_constraints/angular_limit_relaxation", _get_ragdoll_profile_float("hinge_relaxation", 0.8))


func _get_ragdoll_profile_float(property_name: String, fallback: float) -> float:
	var profile = _get_ragdoll_profile()
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	return float(value) if value != null else fallback


func _configure_ragdoll_internal_collision_exceptions() -> void:
	var profile = _get_ragdoll_profile()
	if profile == null or not bool(profile.get("disable_internal_collisions")):
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


func _reset_ragdoll_body_velocities() -> void:
	for physical_bone_value in _ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		physical_bone.linear_velocity = Vector3.ZERO
		physical_bone.angular_velocity = Vector3.ZERO


func _sync_ragdoll_physical_bones_to_current_pose() -> void:
	if _ragdoll_skeleton == null or not is_instance_valid(_ragdoll_skeleton):
		return
	_ragdoll_skeleton.force_update_all_bone_transforms()
	for bone_name_value in _ragdoll_physical_bones.keys():
		var bone_name := str(bone_name_value)
		var physical_bone := _ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		var bone_index := _ragdoll_skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		physical_bone.transform = _ragdoll_skeleton.get_bone_global_pose(bone_index)


func _prepare_ragdoll_activation() -> void:
	_ragdoll_upward_velocity_suppression_frames = RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES
	_set_ragdoll_bone_upward_velocity_suppression(RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES)
	if _ragdoll_skeleton != null and is_instance_valid(_ragdoll_skeleton):
		_ragdoll_skeleton.force_update_all_bone_transforms()


func _set_ragdoll_bone_upward_velocity_suppression(frame_count: int) -> void:
	for physical_bone_value in _ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone != null and is_instance_valid(physical_bone) and physical_bone.has_method("set_upward_velocity_suppression_frames"):
			physical_bone.call("set_upward_velocity_suppression_frames", frame_count)


func _stabilize_active_ragdoll(_delta: float) -> void:
	var suppress_upward_velocity := _ragdoll_upward_velocity_suppression_frames > 0
	if suppress_upward_velocity:
		_ragdoll_upward_velocity_suppression_frames = maxi(0, _ragdoll_upward_velocity_suppression_frames - 1)
	for physical_bone_value in _ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		var linear_velocity := physical_bone.linear_velocity
		if suppress_upward_velocity and linear_velocity.y > 0.0:
			linear_velocity.y = 0.0
		if linear_velocity.length() > RAGDOLL_MAX_LINEAR_SPEED:
			linear_velocity = linear_velocity.normalized() * RAGDOLL_MAX_LINEAR_SPEED
		physical_bone.linear_velocity = linear_velocity
		var angular_velocity := physical_bone.angular_velocity
		if angular_velocity.length() > RAGDOLL_MAX_ANGULAR_SPEED:
			physical_bone.angular_velocity = angular_velocity.normalized() * RAGDOLL_MAX_ANGULAR_SPEED


func _get_ragdoll_body_basis(profile, bone_name: String, bone_index: int) -> Basis:
	if profile != null and bone_name == str(profile.get("root_bone_name")):
		return Basis.IDENTITY
	return _make_y_axis_basis(_get_ragdoll_bone_axis(profile, bone_name, bone_index))


func _get_ragdoll_bone_axis(profile, bone_name: String, bone_index: int) -> Vector3:
	var child_vector := _get_ragdoll_child_vector(profile, bone_index)
	if child_vector.length_squared() > 0.0001:
		return child_vector.normalized()
	var parent_axis := _get_ragdoll_parent_continuation_axis(bone_index)
	if parent_axis.length_squared() > 0.0001:
		return parent_axis.normalized()
	return _get_fallback_ragdoll_bone_axis(bone_name)


func _get_ragdoll_child_vector(profile, bone_index: int) -> Vector3:
	if profile == null:
		return Vector3.ZERO
	var best_vector := Vector3.ZERO
	var best_length_squared := 0.0
	for child_index in _ragdoll_skeleton.get_bone_children(bone_index):
		var child_name := _ragdoll_skeleton.get_bone_name(child_index)
		if not profile.has_physical_bone(child_name):
			continue
		var child_vector := _ragdoll_skeleton.get_bone_rest(child_index).origin
		var child_length_squared := child_vector.length_squared()
		if child_length_squared > best_length_squared:
			best_vector = child_vector
			best_length_squared = child_length_squared
	return best_vector


func _get_ragdoll_parent_continuation_axis(bone_index: int) -> Vector3:
	var bone_rest := _ragdoll_skeleton.get_bone_rest(bone_index)
	if bone_rest.origin.length_squared() <= 0.0001:
		return Vector3.ZERO
	return bone_rest.basis.inverse() * bone_rest.origin


func _get_fallback_ragdoll_bone_axis(bone_name: String) -> Vector3:
	if bone_name.ends_with("_l"):
		return Vector3.LEFT
	if bone_name.ends_with("_r"):
		return Vector3.RIGHT
	if bone_name.begins_with("foot"):
		return Vector3.FORWARD
	return Vector3.UP


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


func _get_ragdoll_bone_length(profile, bone_name: String, bone_index: int) -> float:
	var best_length := _get_ragdoll_child_vector(profile, bone_index).length()
	if best_length <= 0.0:
		best_length = _get_fallback_ragdoll_bone_length(bone_name)
	return best_length


func _get_fallback_ragdoll_bone_length(bone_name: String) -> float:
	if bone_name == "Head":
		return 0.22
	if bone_name.begins_with("hand") or bone_name.begins_with("foot"):
		return 0.16
	if bone_name.begins_with("spine"):
		return 0.16
	if bone_name == "pelvis":
		return 0.22
	return 0.25


func _get_ragdoll_box_size(bone_name: String, bone_length: float, radius: float) -> Vector3:
	if bone_name == "pelvis":
		return Vector3(radius * 2.5, maxf(0.14, bone_length * 0.55), radius * 1.8)
	if bone_name == "Head":
		return Vector3(radius * 1.6, radius * 1.8, radius * 1.5)
	return Vector3(radius * 2.0, maxf(0.12, bone_length * RAGDOLL_COLLIDER_LENGTH_SCALE), radius * 1.6)


func _clamp_ragdoll_upward_velocities() -> void:
	for physical_bone_value in _ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone == null or not is_instance_valid(physical_bone):
			continue
		physical_bone.linear_velocity = _get_non_upward_ragdoll_vector(physical_bone.linear_velocity)


func _get_non_upward_ragdoll_vector(vector: Vector3) -> Vector3:
	if vector.y <= 0.0:
		return vector
	return Vector3(vector.x, 0.0, vector.z)


func _sync_equipment(equipment_slots: Dictionary) -> void:
	if _equipment_root == null:
		return
	var signature := _equipment_signature_for(equipment_slots)
	if signature == _equipment_signature:
		return
	_equipment_signature = signature
	_clear_equipment_children(_equipment_root)
	_clear_tagged_equipment_visuals(_body_visual)
	var slot_names := equipment_slots.keys()
	slot_names.sort()
	for slot_name_value in slot_names:
		var slot_name := str(slot_name_value)
		var item := load(str(equipment_slots[slot_name_value])) as Resource
		if item == null:
			continue
		if BONE_EQUIPMENT_SLOTS.has(slot_name):
			_attach_bone_item(_skeleton, slot_name, item)
		else:
			_attach_wearable(_equipment_root, _skeleton, slot_name, item, 0.0)


func _sync_portrait_equipment(equipment_slots: Dictionary) -> void:
	if _portrait_character_visual == null:
		return
	var signature := _equipment_signature_for(equipment_slots)
	if signature == _portrait_equipment_signature:
		return
	_portrait_equipment_signature = signature
	_clear_tagged_equipment_visuals(_portrait_character_visual)
	var slot_names := equipment_slots.keys()
	slot_names.sort()
	for slot_name_value in slot_names:
		var slot_name := str(slot_name_value)
		var item := load(str(equipment_slots[slot_name_value])) as Resource
		if item == null:
			continue
		if BONE_EQUIPMENT_SLOTS.has(slot_name):
			_attach_bone_item(_portrait_skeleton, slot_name, item)
		else:
			_attach_wearable(_portrait_character_visual, _portrait_skeleton, slot_name, item, PORTRAIT_CHARACTER_VISUAL_YAW_OFFSET)


func _setup_character_animation(model_root: Node3D, include_combat := false) -> AnimationPlayer:
	var animation_player := AnimationPlayer.new()
	animation_player.name = CHARACTER_ANIMATION_PLAYER_NAME
	animation_player.root_node = NodePath("..")
	model_root.add_child(animation_player)
	var animation_library := AnimationLibrary.new()
	_copy_animation_names_from_scene(UAL1_ANIMATION_SOURCE_SCENE, animation_library, _base_animation_names() + (_combat_animation_names() if include_combat else []))
	if include_combat:
		_copy_animation_names_from_scene(UAL2_ANIMATION_SOURCE_SCENE, animation_library, _combat_animation_names())
	if animation_library.get_animation_list().is_empty():
		animation_player.queue_free()
		return null
	animation_player.add_animation_library("", animation_library)
	return animation_player


func _copy_animation_names_from_scene(source_scene: PackedScene, animation_library: AnimationLibrary, animation_names: Array) -> void:
	if source_scene == null:
		return
	var source := source_scene.instantiate()
	var source_player := _find_animation_player(source)
	if source_player != null:
		for animation_name in animation_names:
			_copy_animation(source_player, animation_library, str(animation_name))
	source.queue_free()


func _base_animation_names() -> Array:
	return [IDLE_ANIMATION_NAME, WALK_ANIMATION_NAME, CROUCH_IDLE_ANIMATION_NAME, CROUCH_WALK_ANIMATION_NAME, JOG_ANIMATION_NAME]


func _combat_animation_names() -> Array:
	var result: Array = []
	for group in [COMBAT_IDLE_ANIMATION_CANDIDATES, ATTACK_ANIMATION_CANDIDATES, REACTION_ANIMATION_CANDIDATES, BLOCK_ANIMATION_CANDIDATES, DOWNED_ANIMATION_CANDIDATES]:
		for animation_name in group:
			if not result.has(animation_name):
				result.append(animation_name)
	for animation_name in _get_ragdoll_profile_animation_names():
		if not result.has(animation_name):
			result.append(animation_name)
	return result


func _get_ragdoll_profile_animation_names() -> Array[String]:
	var profile = _get_ragdoll_profile()
	if profile != null and profile.has_method("get_all_animation_names"):
		return profile.get_all_animation_names()
	return []


func _copy_animation(source_player: AnimationPlayer, animation_library: AnimationLibrary, animation_name: String) -> void:
	if not source_player.has_animation(animation_name) or animation_library.has_animation(animation_name):
		return
	var source_animation := source_player.get_animation(animation_name)
	if source_animation == null:
		return
	animation_library.add_animation(animation_name, source_animation.duplicate(true) as Animation)


func _play_first_available_loop(candidates: Array) -> void:
	var animation_name := _first_available_animation(candidates)
	if animation_name.is_empty():
		_play_world_animation(IDLE_ANIMATION_NAME)
		return
	_play_world_animation(animation_name)


func _play_combat_progress_animation(event_id: String, candidates: Array, progress: float, speed_scale := 1.0) -> void:
	var animation_name := _deterministic_available_animation(candidates, event_id)
	if animation_name.is_empty():
		_play_first_available_loop(COMBAT_IDLE_ANIMATION_CANDIDATES)
		return
	_current_combat_event_id = event_id
	_current_world_animation = animation_name
	_character_animation_player.speed_scale = maxf(speed_scale, 0.01)
	_character_animation_player.play(animation_name, 0.05)
	var animation := _character_animation_player.get_animation(animation_name)
	if animation != null:
		_character_animation_player.seek(clampf(progress, 0.0, 1.0) * maxf(animation.length, 0.001), true)
	_character_animation_player.advance(0.0)


func _play_combat_once_animation(event_id: String, candidates: Array, speed_scale := 1.0) -> void:
	var animation_name := _deterministic_available_animation(candidates, event_id)
	if animation_name.is_empty():
		_play_first_available_loop(COMBAT_IDLE_ANIMATION_CANDIDATES)
		return
	if _current_combat_event_id == event_id and _current_world_animation == animation_name and _character_animation_player.is_playing():
		return
	_current_combat_event_id = event_id
	_current_world_animation = animation_name
	_character_animation_player.speed_scale = maxf(speed_scale, 0.01)
	_character_animation_player.play(animation_name, 0.08)
	_character_animation_player.advance(0.0)


func _hold_combat_once_animation(event_id: String, candidates: Array) -> void:
	var animation_name := _deterministic_available_animation(candidates, event_id)
	if animation_name.is_empty():
		_play_first_available_loop(COMBAT_IDLE_ANIMATION_CANDIDATES)
		return
	if _current_combat_event_id != event_id or _current_world_animation != animation_name:
		_play_combat_once_animation(event_id, candidates, 1.0)


func _first_available_animation(candidates: Array) -> String:
	if _character_animation_player == null:
		return ""
	for candidate in candidates:
		var animation_name := str(candidate)
		if _character_animation_player.has_animation(animation_name):
			return animation_name
	return ""


func _deterministic_available_animation(candidates: Array, event_id: String) -> String:
	if _character_animation_player == null:
		return ""
	var available: Array[String] = []
	for candidate in candidates:
		var animation_name := str(candidate)
		if _character_animation_player.has_animation(animation_name):
			available.append(animation_name)
	if available.is_empty():
		return ""
	return available[_stable_string_index(event_id, available.size())]


func _stable_string_index(value: String, count: int) -> int:
	if count <= 0:
		return 0
	var hash := 0
	for index in range(value.length()):
		hash = (hash * 31 + value.unicode_at(index)) % 2147483647
	return hash % count


func _play_idle_pose(animation_player: AnimationPlayer) -> void:
	if animation_player == null or not animation_player.has_animation(IDLE_ANIMATION_NAME):
		return
	animation_player.play(IDLE_ANIMATION_NAME)
	animation_player.seek(IDLE_SAMPLE_SECONDS, true)
	animation_player.advance(0.0)


func _attach_wearable(target_root: Node3D, target_skeleton: Skeleton3D, slot_name: String, item: Resource, visual_yaw_offset: float) -> void:
	if target_root == null or item == null:
		return
	var equipment_visual := _equipment_visual_for_item(item)
	var visual_scene := _equipped_scene_for_item(item)
	if visual_scene == null:
		return
	var instance := visual_scene.instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.queue_free()
		return
	var source_root := instance as Node3D
	source_root.name = "Equipped_%s" % slot_name.capitalize()
	source_root.set_meta("item_definition_path", _resource_path(item))
	var visual_transform := _equipment_visual_transform(item, equipment_visual)
	if target_skeleton != null and _setup_shared_skeleton_clothing_visual(target_root, target_skeleton, source_root, visual_transform, visual_yaw_offset):
		source_root.free()
		return
	_setup_legacy_clothing_visual(target_root, source_root, visual_transform, visual_yaw_offset)


func _setup_shared_skeleton_clothing_visual(target_root: Node3D, target_skeleton: Skeleton3D, source_root: Node3D, visual_transform: Transform3D, visual_yaw_offset: float) -> bool:
	var source_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(source_root, source_meshes)
	if source_meshes.is_empty():
		return false
	var slot_root := Node3D.new()
	slot_root.name = source_root.name
	slot_root.set_meta(EQUIPMENT_VISUAL_META, true)
	if source_root.has_meta("item_definition_path"):
		slot_root.set_meta("item_definition_path", source_root.get_meta("item_definition_path"))
	slot_root.transform = Transform3D(Basis(Vector3.UP, visual_yaw_offset), Vector3.ZERO) * visual_transform
	target_root.add_child(slot_root)
	var copied_mesh_count := 0
	for source_mesh in source_meshes:
		if source_mesh == null or source_mesh.mesh == null:
			continue
		var clothing_mesh := _copy_clothing_mesh_instance(source_root, source_mesh)
		slot_root.add_child(clothing_mesh)
		clothing_mesh.skeleton = clothing_mesh.get_path_to(target_skeleton)
		copied_mesh_count += 1
	if copied_mesh_count <= 0:
		slot_root.free()
		return false
	return true


func _setup_legacy_clothing_visual(target_root: Node3D, model_root: Node3D, visual_transform: Transform3D, visual_yaw_offset: float) -> void:
	model_root.set_meta(EQUIPMENT_VISUAL_META, true)
	model_root.transform = Transform3D(Basis(Vector3.UP, visual_yaw_offset), Vector3.ZERO) * visual_transform
	target_root.add_child(model_root)
	var animation_player := _setup_character_animation(model_root, false)
	_play_idle_pose(animation_player)


func _collect_mesh_instances(root: Node, meshes: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_mesh_instances(child, meshes)


func _copy_clothing_mesh_instance(source_root: Node3D, source_mesh: MeshInstance3D) -> MeshInstance3D:
	var clothing_mesh := MeshInstance3D.new()
	clothing_mesh.name = source_mesh.name
	clothing_mesh.transform = _node3d_transform_relative_to_root(source_root, source_mesh)
	clothing_mesh.mesh = source_mesh.mesh
	clothing_mesh.skin = source_mesh.skin
	clothing_mesh.visible = source_mesh.visible
	clothing_mesh.layers = source_mesh.layers
	clothing_mesh.cast_shadow = source_mesh.cast_shadow
	if source_mesh.material_override != null:
		clothing_mesh.material_override = source_mesh.material_override
	for surface_index in range(source_mesh.get_surface_override_material_count()):
		var surface_material := source_mesh.get_surface_override_material(surface_index)
		if surface_material != null:
			clothing_mesh.set_surface_override_material(surface_index, surface_material)
	for blend_shape_index in range(source_mesh.get_blend_shape_count()):
		clothing_mesh.set_blend_shape_value(blend_shape_index, source_mesh.get_blend_shape_value(blend_shape_index))
	return clothing_mesh


func _attach_bone_item(target_skeleton: Skeleton3D, slot_name: String, item: Resource) -> void:
	if target_skeleton == null or item == null:
		return
	var equipped_scene := _equipped_scene_for_item(item)
	if equipped_scene == null:
		return
	var instance := equipped_scene.instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.queue_free()
		return
	var socket_id := _equipment_socket_id(item, slot_name)
	var bone_name := _equipment_socket_bone_name(socket_id)
	if bone_name.is_empty():
		bone_name = _equipment_attachment_bone(item, slot_name)
	if bone_name.is_empty() or target_skeleton.find_bone(bone_name) < 0:
		instance.queue_free()
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = _bone_attachment_name(slot_name)
	attachment.bone_name = bone_name
	attachment.set_meta(EQUIPMENT_VISUAL_META, true)
	target_skeleton.add_child(attachment)
	var socket := Node3D.new()
	socket.name = _equipment_socket_node_name(socket_id)
	socket.transform = _equipment_socket_transform(socket_id)
	attachment.add_child(socket)
	var slot_visual := Node3D.new()
	slot_visual.name = _bone_equipment_visual_name(slot_name)
	slot_visual.set_meta("item_definition_path", _resource_path(item))
	socket.add_child(slot_visual)
	var model_root := instance as Node3D
	model_root.transform = _item_equipped_transform(item) * _item_grip_transform(model_root, item).affine_inverse()
	slot_visual.add_child(model_root)


func _equipment_visual_for_item(item: Resource) -> Resource:
	if item != null and item.has_method("get_equipment_visual_for_body_archetype"):
		var visual = item.call("get_equipment_visual_for_body_archetype", _body_archetype)
		if visual is Resource:
			return visual as Resource
	return null


func _equipped_scene_for_item(item: Resource) -> PackedScene:
	if item == null:
		return null
	if item.has_method("get_equipped_scene_for_body_archetype"):
		var scene = item.call("get_equipped_scene_for_body_archetype", _body_archetype)
		if scene is PackedScene:
			return scene as PackedScene
	return item.get("equipped_scene") as PackedScene


func _equipment_visual_transform(item: Resource, equipment_visual: Resource) -> Transform3D:
	if equipment_visual != null:
		var visual_transform = equipment_visual.get("equipped_transform")
		if visual_transform is Transform3D:
			return visual_transform
	var item_transform = item.get("equipped_transform") if item != null else null
	return item_transform if item_transform is Transform3D else Transform3D.IDENTITY


func _equipment_socket_id(item: Resource, slot_name: String) -> String:
	var grip_profile := item.get("grip_profile") as Resource if item != null else null
	if grip_profile != null:
		var socket_id := str(grip_profile.get("primary_socket_id"))
		if not socket_id.is_empty():
			return socket_id
	match slot_name:
		"weapon":
			return "right_hand_one_hand"
		"offhand":
			return "left_hand_shield"
	return ""


func _equipment_attachment_bone(item: Resource, slot_name: String) -> String:
	var grip_profile := item.get("grip_profile") as Resource if item != null else null
	if grip_profile != null:
		var primary_bone := str(grip_profile.get("primary_bone"))
		if not primary_bone.is_empty():
			return primary_bone
	return str(BONE_EQUIPMENT_SLOTS.get(slot_name, ""))


func _equipment_socket_bone_name(socket_id: String) -> String:
	var profile := _socket_profile()
	if profile != null and profile.has_method("get_socket_bone_name"):
		return str(profile.call("get_socket_bone_name", socket_id))
	return ""


func _equipment_socket_transform(socket_id: String) -> Transform3D:
	var profile := _socket_profile()
	if profile != null and profile.has_method("get_socket_transform"):
		var socket_transform = profile.call("get_socket_transform", socket_id)
		if socket_transform is Transform3D:
			return socket_transform
	return Transform3D.IDENTITY


func _equipment_socket_node_name(socket_id: String) -> String:
	var profile := _socket_profile()
	if profile != null and profile.has_method("get_socket_node_name"):
		return str(profile.call("get_socket_node_name", socket_id))
	return "GripSocket"


func _socket_profile() -> Resource:
	if _body_archetype != null:
		var profile := _body_archetype.get("grip_socket_profile") as Resource
		if profile != null:
			return profile
	return DEFAULT_GRIP_SOCKET_PROFILE


func _item_equipped_transform(item: Resource) -> Transform3D:
	var value = item.get("equipped_transform") if item != null else null
	return value if value is Transform3D else Transform3D.IDENTITY


func _item_grip_transform(model_root: Node3D, item: Resource) -> Transform3D:
	var marker_name := "GripPoint_Primary"
	var grip_profile := item.get("grip_profile") as Resource if item != null else null
	if grip_profile != null and not str(grip_profile.get("primary_grip_marker")).is_empty():
		marker_name = str(grip_profile.get("primary_grip_marker"))
	var marker := _find_node3d_by_name(model_root, marker_name)
	return _node3d_transform_relative_to_root(model_root, marker) if marker != null else Transform3D.IDENTITY


func _bone_attachment_name(slot_name: String) -> String:
	return "Equipped%sAttachment" % slot_name.capitalize()


func _bone_equipment_visual_name(slot_name: String) -> String:
	return "Equipped%sVisual" % slot_name.capitalize()


func _clear_equipment_children(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()


func _clear_tagged_equipment_visuals(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child.has_meta(EQUIPMENT_VISUAL_META):
			root.remove_child(child)
			child.queue_free()
		else:
			_clear_tagged_equipment_visuals(child)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


func _find_node3d_by_name(root: Node, node_name: String) -> Node3D:
	if root is Node3D and root.name == node_name:
		return root as Node3D
	for child in root.get_children():
		var found := _find_node3d_by_name(child, node_name)
		if found != null:
			return found
	return null


func _node3d_transform_relative_to_root(root: Node3D, target: Node3D) -> Transform3D:
	if target == root:
		return Transform3D.IDENTITY
	var current: Node = target
	var result := Transform3D.IDENTITY
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _equipment_signature_for(equipment_slots: Dictionary) -> String:
	var parts: Array[String] = []
	var slot_names := equipment_slots.keys()
	slot_names.sort()
	for slot_name in slot_names:
		parts.append("%s=%s" % [str(slot_name), str(equipment_slots[slot_name])])
	return "|".join(parts)


func _attached_item_paths() -> Array[String]:
	var paths: Array[String] = []
	_collect_attached_item_paths(self, paths)
	paths.sort()
	var unique_paths: Array[String] = []
	for path in paths:
		if not unique_paths.has(path):
			unique_paths.append(path)
	return unique_paths


func _collect_attached_item_paths(root: Node, paths: Array[String]) -> void:
	if root.has_meta("item_definition_path"):
		paths.append(str(root.get_meta("item_definition_path")))
	for child in root.get_children():
		_collect_attached_item_paths(child, paths)


func _resource_path(value) -> String:
	if value is Resource:
		return (value as Resource).resource_path
	return ""
