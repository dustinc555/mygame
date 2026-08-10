extends BodyProjection
class_name HumanoidBodyProjection

# Humanoid visual adapter. PRESENTATION ONLY -- never owns durable truth.
#
# Holds humanoid animation + foot-IK behavior migrated out of HumanoidCharacter.
# Animation/skeleton STATE still lives on the actor during migration (other systems
# and tests read it directly); this projection owns the LOGIC and reads/writes that
# state via `actor`. Constants are read through the untyped `actor` at runtime so this
# file never statically depends on HumanoidCharacter (which would be a cyclic dep).
#
# Migrated in increment A1: animation library setup/copy, clip playback, idle-clip
# selection, foot-ground IK. Rustdead clip overrides live in RustdeadBodyProjection.

const DEFAULT_MOVE_BLEND_SECONDS := 0.12
const COMBAT_ANIMATION_SET_SCRIPT = preload("res://features/actors/resources/characters/combat_animation_set.gd")
const COMBAT_ATTACK_ANIMATION_SCRIPT = preload("res://features/actors/resources/characters/combat_attack_animation.gd")
const HUMANOID_RAGDOLL_PROFILE_SCRIPT = preload("res://features/actors/resources/characters/humanoid_ragdoll_profile.gd")
const STABLE_PHYSICAL_BONE_SCRIPT = preload("res://features/actors/projection/stable_physical_bone.gd")
const HUMAN_RACE = preload("res://features/actors/resources/character_races/human.tres")
const HUMAN_MALE_BODY_ARCHETYPE = preload("res://features/actors/resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE = preload("res://features/actors/resources/character_body_archetypes/human_female.tres")
const SKIN_TEXTURE_BUILDER = preload("res://features/actors/projection/appearance/skin_texture_builder.gd")
const DEFAULT_MALE_EYEBROW_STYLE = preload("res://features/actors/resources/character_appearance/eyebrows_regular.tres")
const DEFAULT_FEMALE_EYEBROW_STYLE = preload("res://features/actors/resources/character_appearance/eyebrows_female.tres")
const MALE_VISUAL_SCENE = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Male_FullBody.gltf")
const FEMALE_VISUAL_SCENE = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Female_FullBody.gltf")
const UAL1_ANIMATION_SOURCE_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb")
const UAL2_ANIMATION_SOURCE_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_2/UAL2.glb")
const DEFAULT_GRIP_SOCKET_PROFILE = preload("res://features/actors/resources/humanoid_grip_socket_profiles/default.tres")
const HUMANOID_GRIP_SOCKET_MARKER_SCRIPT = preload("res://features/actors/projection/humanoid/humanoid_grip_socket_marker.gd")
const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const CHARACTER_ANIMATION_PLAYER_NAME := "CharacterAnimationPlayer"
const CHARACTER_VISUAL_YAW_OFFSET := PI
const CHARACTER_VISUAL_FOOT_CLEARANCE := 0.02
const CHARACTER_VISUAL_FOOT_GROUND_CORRECTION_MAX_UP := 0.18
const CHARACTER_VISUAL_FOOT_GROUND_CORRECTION_MAX_DOWN := 0.05
const IDLE_ANIMATION_NAME := "Idle"
const TIRED_IDLE_ANIMATION_NAME := "Idle_Tired"
const FOLD_ARMS_IDLE_ANIMATION_NAME := "Idle_FoldArms"
const WALK_ANIMATION_NAME := "Walk"
const MINING_ANIMATION_NAME := "Mining"
const SCAVENGING_ANIMATION_NAME := "Fixing_Kneeling"
const FARM_HARVEST_ANIMATION_NAME := "Farm_Harvest"
const FARM_PLANT_ANIMATION_NAME := "Farm_PlantSeed"
const FARM_WATER_ANIMATION_NAME := "Farm_Watering"
const CROUCH_ENTER_ANIMATION_NAME := "Crouch_Enter"
const CROUCH_IDLE_ANIMATION_NAME := "Crouch_Idle"
const CROUCH_WALK_ANIMATION_NAME := "Crouch_Fwd"
const CROUCH_EXIT_ANIMATION_NAME := "Crouch_Exit"
const RUN_ENTER_ANIMATION_NAME := "Sprint_Enter"
const JOG_ANIMATION_NAME := "Jog_Fwd"
const RUN_EXIT_ANIMATION_NAME := "Sprint_Exit"
const SITTING_ENTER_ANIMATION_NAME := "Sitting_Enter"
const SITTING_IDLE_ANIMATION_NAME := "Sitting_Idle"
const SITTING_TALKING_ANIMATION_NAME := "Sitting_Talking"
const SITTING_EXIT_ANIMATION_NAME := "Sitting_Exit"
const COUNTER_ENTER_ANIMATION_NAME := "Counter_Enter"
const COUNTER_IDLE_ANIMATION_NAME := "Counter_Idle"
const COUNTER_SHOW_ANIMATION_NAME := "Counter_Show"
const COUNTER_GIVE_ANIMATION_NAME := "Counter_Give"
const COUNTER_EXIT_ANIMATION_NAME := "Counter_Exit"
const LAY_ENTER_ANIMATION_NAME := "IdleToLay"
const LAY_EXIT_ANIMATION_NAME := "LayToIdle"
const UNARMED_STANCE_ID := "unarmed"
const UNARMED_COMBAT_IDLE_ANIMATION_NAME := "Unarmed_Combat_Idle"
const UNARMED_STANCE_ENTER_ANIMATION_NAME := "PunchKick_Enter"
const UNARMED_STANCE_EXIT_ANIMATION_NAME := "PunchKick_Exit"
const UNARMED_COMBAT_IDLE_SEGMENT_SECONDS := 0.3
const UNARMED_JAB_ANIMATION_NAME := "Punch_Jab"
const UNARMED_CROSS_ANIMATION_NAME := "Punch_Cross"
const UNARMED_UPPERCUT_ANIMATION_NAME := "Punch_Uppercut"
const UNARMED_KICK_ANIMATION_NAME := "Kick"
const UNARMED_HOOK_ANIMATION_NAMES: Array[String] = ["Melee_Hook", "Melee_Hook_Rec"]
const UNARMED_KNEE_ANIMATION_NAMES: Array[String] = ["Melee_Knee", "Melee_Knee_Rec"]
const CARRY_POSE_ANIMATION_NAMES: Array[String] = ["LiftAir_Fall"]
const CELL_CUSTODY_ANIMATION_NAMES: Array[String] = ["IdleToLay", "LayToIdle"]
const ONE_HAND_MELEE_IDLE_ANIMATION_NAME := "Sword_Idle"
const ONE_HAND_LIGHT_A_ANIMATION_NAMES: Array[String] = ["Sword_Light_A", "Sword_Light_A_Rec"]
const ONE_HAND_LIGHT_B_ANIMATION_NAMES: Array[String] = ["Sword_Light_B", "Sword_Light_B_Rec"]
const BLOCK_ANIMATION_NAME := "Sword_Block"
const SHIELD_COMBAT_IDLE_ANIMATION_NAME := "Idle_Shield_Loop"
const SHIELD_BLOCK_ANIMATION_NAMES: Array[String] = ["Shield_OneShot", "Idle_Shield_Break", "Sword_Block"]
const HIT_CHEST_ANIMATION_NAME := "Hit_Chest"
const HIT_HEAD_ANIMATION_NAME := "Hit_Head"
const HIT_STOMACH_ANIMATION_NAME := "Hit_Stomach"
const HIT_SHOULDER_L_ANIMATION_NAME := "Hit_Shoulder_L"
const HIT_SHOULDER_R_ANIMATION_NAME := "Hit_Shoulder_R"
const IDLE_ANIMATION_NAMES := [IDLE_ANIMATION_NAME]
const IDLE_ANIMATION_MIN_SECONDS := 4.0
const IDLE_ANIMATION_MAX_SECONDS := 8.0
const SITTING_IDLE_MIN_SECONDS := 5.0
const SITTING_IDLE_MAX_SECONDS := 11.0
const SITTING_TALKING_CHANCE := 0.28
const MOVE_ANIMATION_BLEND_SECONDS := 0.12
const RAGDOLL_COLLIDER_LENGTH_SCALE := 0.82
const RAGDOLL_MAX_LINEAR_SPEED := 10.0
const RAGDOLL_MAX_ANGULAR_SPEED := 18.0
const RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES := 90
const CLOTHING_EQUIPMENT_SLOTS := ["undershirt", "hands", "chest", "legs", "feet", "backpack", "head"]
const APPEARANCE_HEAD_ATTACHMENT_PREFIX := "Appearance"
const BONE_EQUIPMENT_SLOTS := {
	"weapon": "hand_r",
	"offhand": "hand_l",
}

enum VisualBodyType {
	AUTO,
	NONE,
	MALE,
	FEMALE,
}

const FEMALE_VISUAL_NAME_KEYS := {
	"anya": true,
	"avery": true,
	"cleo": true,
	"cora": true,
	"esme": true,
	"gwen": true,
	"iris": true,
	"kaia": true,
	"mira": true,
	"nika": true,
	"orla": true,
	"quinn": true,
	"rhea": true,
	"sable": true,
	"talia": true,
	"vera": true,
	"wren": true,
	"yara": true,
}

static var _fallback_visual_material: Material

@export var grip_socket_profile: Resource
@export var ragdoll_profile: Resource
@export var show_grip_socket_markers := false

## Authored appearance. The projection OWNS appearance now (4b.4) instead of
## reading it off the actor. CharacterAppearanceData already carries race,
## body archetype and visual body type, so these collapse into one resource.
@export var appearance_data: CharacterAppearanceData


## Inject authored appearance (called by the actor when it builds the body).
func configure_appearance(data: CharacterAppearanceData) -> void:
	appearance_data = data.make_copy() if data != null else null
	_ensure_appearance_data()


func _ensure_appearance_data() -> void:
	if appearance_data == null:
		appearance_data = CharacterAppearanceData.new()


func _authored_visual_body_type() -> int:
	_ensure_appearance_data()
	return appearance_data.visual_body_type


func _authored_body_archetype() -> Resource:
	_ensure_appearance_data()
	return appearance_data.body_archetype


func _authored_character_race() -> Resource:
	_ensure_appearance_data()
	return appearance_data.character_race

var _visual_root: Node3D = null
var _default_ragdoll_profile: Resource
@warning_ignore("unused_private_class_variable")
var _ragdoll_simulator: PhysicalBoneSimulator3D
@warning_ignore("unused_private_class_variable")
var _ragdoll_skeleton: Skeleton3D
var _ragdoll_physical_bones: Dictionary = {}
var _is_ragdoll_active := false
var _last_ragdoll_impulse := Vector3.ZERO
var _last_ragdoll_impulse_remaining := 0.0
var _ragdoll_upward_velocity_suppression_frames := 0
var _ragdoll_preroll_active := false
var _ragdoll_preroll_is_dead := false
var _ragdoll_preroll_animation_name := ""
var _ragdoll_preroll_remaining := 0.0
var _is_getting_up := false
var _get_up_animation_name := ""
var _get_up_animation_remaining := 0.0
var _get_up_animation_total := 0.0
var _combat_animation_sets: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _character_animation_player: AnimationPlayer
var _character_animation_players: Array[AnimationPlayer] = []
var _character_skeleton: Skeleton3D
var _bone_pose_position_offsets: Dictionary = {}
var _visual_foot_anchor_correction_y := 0.0
var _visual_foot_ground_correction_y := 0.0
var _current_character_animation := ""
var _idle_animation_change_remaining := 0.0
var _crouch_enter_animation_remaining := 0.0
var _crouch_exit_animation_remaining := 0.0
var _run_enter_animation_remaining := 0.0
var _run_exit_animation_remaining := 0.0
var _running_locomotion_active := false
var _sitting_enter_animation_remaining := 0.0
var _sitting_exit_animation_remaining := 0.0
var _sitting_idle_change_remaining := 0.0
var _preview_clothes_visible := true


# --- Visual build ---

## Typed handle to the _actor. The base stores it sim-agnostically as `Node3D`; this concrete
## humanoid projection legitimately calls WorldActor methods, so it caches a typed reference here.
## That is a one-way HumanoidBodyProjection -> WorldActor edge (NOT part of the base
## BodyProjection <-> WorldActor cycle, which is now broken).
var _actor: WorldActor


func bind_actor(owner_actor: Node3D) -> void:
	super.bind_actor(owner_actor)
	_actor = owner_actor as WorldActor
	_default_ragdoll_profile = null
	_rng.randomize()


func setup_visual() -> void:
	var old_visual := get_visual_root()
	if old_visual != null:
		old_visual.free()
	_visual_root = null
	# A2 moves CharacterVisual under BodyProjection; remove any legacy actor-child
	# visual root left from an older live rebuild.
	var legacy_visual := _actor.get_node_or_null(CHARACTER_VISUAL_NODE_NAME)
	if legacy_visual != null:
		legacy_visual.free()

	_character_animation_player = null
	_character_animation_players.clear()
	_character_skeleton = null
	_bone_pose_position_offsets.clear()
	_visual_foot_anchor_correction_y = 0.0
	_visual_foot_ground_correction_y = 0.0
	_current_character_animation = ""

	var body_mesh := _actor.get_node_or_null("BodyMesh") as MeshInstance3D
	if body_mesh == null:
		return
	body_mesh.visible = true
	var resolved_body_archetype := get_resolved_body_archetype()
	var resolved_body_type := get_resolved_visual_body_type()
	if resolved_body_type == VisualBodyType.NONE:
		return
	var race := _get_character_race()
	var race_id := str(race.get("race_id")) if race != null else ""
	var fallback_scene := _get_character_visual_scene(resolved_body_type, resolved_body_archetype)
	var model_root := CharacterVisualAssembler.instantiate_body(resolved_body_archetype, appearance_data, race_id, resolved_body_type, fallback_scene)
	if model_root == null:
		return
	model_root.rotation.y = CHARACTER_VISUAL_YAW_OFFSET

	_visual_root = Node3D.new()
	_visual_root.name = CHARACTER_VISUAL_NODE_NAME
	add_child(_visual_root)
	_visual_root.add_child(model_root)
	var visual_fit_scale := _fit_visual_to_body_mesh(_visual_root, body_mesh)
	setup_animation(model_root)
	var character_skeleton := _find_skeleton(model_root)
	_character_skeleton = character_skeleton
	_bone_pose_position_offsets = _get_bone_pose_position_offsets(resolved_body_archetype)
	_setup_equipped_clothing_visuals(_visual_root, character_skeleton, resolved_body_archetype, body_mesh, visual_fit_scale)
	# No authored eyebrows: apply the automatic per-body-type style with hair-matched
	# color — the same defaulting the character creator applies on save. The base
	# mesh brows are an untinted gray placeholder and read as white in game light.
	if appearance_data != null and appearance_data.eyebrow_style == null:
		apply_automatic_eyebrow_style()
	set_base_eyebrow_visuals_visible(model_root, appearance_data == null or appearance_data.eyebrow_style == null)
	_setup_head_attachment_visuals(_visual_root, character_skeleton)
	_setup_humanoid_grip_sockets(_visual_root)
	_setup_equipped_bone_visuals(_visual_root)
	if _actor.life_state == NpcRules.LifeState.ALIVE:
		play_random_idle_animation(true)
	else:
		stop_clip(true)
	apply_bone_pose_offsets()
	refresh_foot_ground_alignment()
	set_equipped_clothing_visuals_visible(_preview_clothes_visible)
	_ensure_non_null_visual_materials(_visual_root)
	body_mesh.visible = false


func get_visual_root() -> Node3D:
	if _visual_root != null and is_instance_valid(_visual_root):
		return _visual_root
	_visual_root = get_node_or_null(CHARACTER_VISUAL_NODE_NAME) as Node3D
	return _visual_root


func get_visual_local_bounds() -> AABB:
	var visual_root := get_visual_root()
	return _calculate_local_mesh_bounds(visual_root) if visual_root != null else AABB()


func has_custom_skin_material() -> bool:
	var visual_root := get_visual_root()
	return visual_root != null and SKIN_TEXTURE_BUILDER.has_custom_skin_materials(visual_root)


func apply_automatic_eyebrow_style() -> void:
	if appearance_data == null:
		return
	match get_resolved_visual_body_type():
		VisualBodyType.FEMALE:
			appearance_data.eyebrow_style = DEFAULT_FEMALE_EYEBROW_STYLE
		VisualBodyType.MALE:
			appearance_data.eyebrow_style = DEFAULT_MALE_EYEBROW_STYLE
		_:
			appearance_data.eyebrow_style = null
	appearance_data.eyebrow_color = appearance_data.hair_color


func rebuild_visual_for_appearance() -> void:
	setup_visual()


func apply_appearance_materials(root: Node, body_type: int) -> void:
	if appearance_data == null or not bool(appearance_data.skin_color_customized):
		return
	var race := _get_character_race()
	var race_id := str(race.get("race_id")) if race != null else ""
	SKIN_TEXTURE_BUILDER.apply_custom_skin_materials(root, race_id, body_type, appearance_data.skin_color)


func _get_bone_pose_position_offsets(target_body_archetype: Resource) -> Dictionary:
	if target_body_archetype == null:
		return appearance_data.get_body_pose_offsets({}) if appearance_data != null else {}
	var raw_offsets = target_body_archetype.get("bone_pose_position_offsets")
	var result: Dictionary = {}
	if raw_offsets is Dictionary:
		for bone_name_value in raw_offsets.keys():
			var offset_value = raw_offsets[bone_name_value]
			if offset_value is Vector3:
				result[str(bone_name_value)] = offset_value
	return appearance_data.get_body_pose_offsets(result) if appearance_data != null else result


func set_base_eyebrow_visuals_visible(root: Node, visible_flag: bool) -> void:
	if root == null:
		return
	if root is MeshInstance3D and str(root.name).to_lower().contains("eyebrow"):
		(root as MeshInstance3D).visible = visible_flag
	for child in root.get_children():
		set_base_eyebrow_visuals_visible(child, visible_flag)


# --- Ragdoll / downed visuals ---

func supports_downed_visuals() -> bool:
	return true


func supports_ragdoll_visuals() -> bool:
	return true

func get_ragdoll_profile():
	if ragdoll_profile != null:
		return ragdoll_profile
	if _default_ragdoll_profile == null:
		_default_ragdoll_profile = HUMANOID_RAGDOLL_PROFILE_SCRIPT.new()
	return _default_ragdoll_profile


func get_ragdoll_profile_animation_names() -> Array[String]:
	var profile = get_ragdoll_profile()
	if profile != null and profile.has_method("get_all_animation_names"):
		return profile.get_all_animation_names()
	return []


func _get_ragdoll_profile_animation_names() -> Array[String]:
	return get_ragdoll_profile_animation_names()


func process_ragdoll_impulse_memory(delta: float) -> void:
	if _last_ragdoll_impulse_remaining <= 0.0:
		return
	_last_ragdoll_impulse_remaining = maxf(0.0, _last_ragdoll_impulse_remaining - delta)
	if _last_ragdoll_impulse_remaining <= 0.0:
		_last_ragdoll_impulse = Vector3.ZERO


func remember_ragdoll_impulse(impulse: Vector3, seconds: float) -> void:
	_last_ragdoll_impulse = impulse
	_last_ragdoll_impulse_remaining = seconds if impulse.length_squared() > 0.0001 else 0.0


func enter_downed_visuals(is_dead: bool) -> bool:
	_cancel_ragdoll_preroll()
	_clear_get_up_state()
	stop_clip(true)
	if _begin_downed_ragdoll_preroll(is_dead):
		return true
	_actor._apply_downed_collision_shape()
	if not start_ragdoll_simulation(is_dead):
		_actor._restore_downed_collision_shape()
		return false
	return true


func restore_from_downed_visuals() -> void:
	_cancel_ragdoll_preroll()
	_clear_get_up_state()
	stop_ragdoll_simulation(true)
	_actor._restore_downed_collision_shape()


func begin_get_up_visuals() -> void:
	_cancel_ragdoll_preroll()
	_clear_get_up_state()
	prepare_ragdoll_get_up()
	_is_getting_up = true
	_get_up_animation_name = _choose_get_up_animation()
	_get_up_animation_total = clip_length(_get_up_animation_name) if not _get_up_animation_name.is_empty() else 0.0
	if _get_up_animation_total <= 0.0:
		_get_up_animation_total = _get_ragdoll_profile_float("get_up_fallback_seconds", 1.15)
	_get_up_animation_remaining = _get_up_animation_total
	if not _get_up_animation_name.is_empty():
		play_clip(_get_up_animation_name, 0.0, true, MOVE_ANIMATION_BLEND_SECONDS)


func process_downed_visuals(delta: float) -> bool:
	if _ragdoll_preroll_active:
		_process_downed_ragdoll_preroll(delta)
		return false
	if not _is_getting_up:
		return false
	return _process_get_up_animation(delta)


func cancel_get_up_visuals() -> void:
	var had_get_up_state: bool = _is_getting_up \
		or not _get_up_animation_name.is_empty() \
		or _get_up_animation_remaining > 0.0 \
		or _get_up_animation_total > 0.0
	_clear_get_up_state()
	if not had_get_up_state:
		return
	stop_clip(true)
	_actor._apply_downed_collision_shape()
	stop_ragdoll_simulation(false)


func _clear_get_up_state() -> void:
	_is_getting_up = false
	_get_up_animation_name = ""
	_get_up_animation_remaining = 0.0
	_get_up_animation_total = 0.0


func start_ragdoll_simulation(_is_dead: bool) -> bool:
	if not _ensure_runtime_ragdoll():
		return false
	_is_ragdoll_active = true
	if _ragdoll_skeleton != null and is_instance_valid(_ragdoll_skeleton):
		_ragdoll_skeleton.force_update_all_bone_transforms()
	_ragdoll_simulator.active = true
	_ragdoll_simulator.influence = 1.0
	_ragdoll_simulator.physical_bones_add_collision_exception(_actor.get_rid())
	_configure_ragdoll_internal_collision_exceptions()
	_sync_ragdoll_physical_bones_to_current_pose()
	_prepare_ragdoll_activation()
	_reset_ragdoll_body_velocities()
	_ragdoll_simulator.physical_bones_start_simulation()
	_reset_ragdoll_body_velocities()
	_apply_pending_ragdoll_impulse()
	_clamp_ragdoll_upward_velocities()
	return true


## Cancels any pending downed-visual transitions (ragdoll preroll, get-up) —
## cell custody and similar hard pose owners must clear these or the deferred
## transition fires later and stomps the owned pose.
func cancel_downed_visual_transitions() -> void:
	_cancel_ragdoll_preroll()
	_clear_get_up_state()


func stop_ragdoll_simulation(reset_pose: bool) -> void:
	if _ragdoll_simulator != null and is_instance_valid(_ragdoll_simulator):
		if _ragdoll_simulator.is_simulating_physics():
			_ragdoll_simulator.physical_bones_stop_simulation()
		_ragdoll_simulator.physical_bones_remove_collision_exception(_actor.get_rid())
		_ragdoll_simulator.active = false
	if _ragdoll_skeleton != null and is_instance_valid(_ragdoll_skeleton):
		if reset_pose:
			_ragdoll_skeleton.reset_bone_poses()
	_is_ragdoll_active = false
	_ragdoll_upward_velocity_suppression_frames = 0
	_set_ragdoll_bone_upward_velocity_suppression(0)


func prepare_ragdoll_get_up() -> void:
	var anchor_position: Variant = get_ragdoll_anchor_position()
	stop_ragdoll_simulation(true)
	if anchor_position is Vector3:
		_actor.global_position = Vector3(anchor_position.x, _actor.global_position.y, anchor_position.z)
	_actor.rotation = Vector3(0.0, _actor.rotation.y, 0.0)


func stabilize_ragdoll(_delta: float) -> void:
	var upward_velocity_suppression_frames: int = _ragdoll_upward_velocity_suppression_frames
	if upward_velocity_suppression_frames > 0:
		_ragdoll_upward_velocity_suppression_frames = maxi(0, upward_velocity_suppression_frames - 1)


func is_ragdoll_active() -> bool:
	return _is_ragdoll_active


func get_ragdoll_anchor_position() -> Variant:
	var profile = get_ragdoll_profile()
	var root_bone_name := str(profile.get("root_bone_name")) if profile != null else "pelvis"
	var physical_bone := _ragdoll_physical_bones.get(root_bone_name, null) as PhysicalBone3D
	if physical_bone == null or not is_instance_valid(physical_bone):
		return null
	return physical_bone.global_position


func get_attack_ragdoll_impulse(attacker: Node, damage: float) -> Vector3:
	if attacker == null or not is_instance_valid(attacker):
		return Vector3.ZERO
	var attacker_node := attacker as Node3D
	if attacker_node == null:
		return Vector3.ZERO
	var direction: Vector3 = _actor.global_position - attacker_node.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = -_actor.transform.basis.z
		direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = Vector3.DOWN
	else:
		direction = (direction.normalized() + Vector3.DOWN * 0.12).normalized()
	var profile = get_ragdoll_profile()
	var impulse_scale := float(profile.get("impulse_scale")) if profile != null else 2.4
	return _get_non_upward_ragdoll_vector(direction.normalized() * clampf(damage * 0.045 * impulse_scale, 0.45, 4.5))


func _choose_get_up_animation() -> String:
	var profile = get_ragdoll_profile()
	if profile != null and profile.has_method("choose_get_up_animation"):
		return profile.choose_get_up_animation(_character_animation_player, _rng)
	return ""


func _choose_downed_preroll_animation() -> String:
	var profile = get_ragdoll_profile()
	if profile != null and profile.has_method("choose_downed_preroll_animation"):
		return profile.choose_downed_preroll_animation(_character_animation_player, _rng)
	return ""


func _choose_downed_preroll_duration(animation_length: float) -> float:
	var profile = get_ragdoll_profile()
	if profile != null and profile.has_method("choose_downed_preroll_duration"):
		return profile.choose_downed_preroll_duration(animation_length, _rng)
	return animation_length


func _get_ragdoll_profile_float(property_name: String, fallback: float) -> float:
	var profile = get_ragdoll_profile()
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	return float(value) if value != null else fallback


func _begin_downed_ragdoll_preroll(is_dead: bool) -> bool:
	if _character_animation_player == null:
		return false
	var animation_name := _choose_downed_preroll_animation()
	if animation_name.is_empty():
		return false
	var animation_length: float = clip_length(animation_name)
	var preroll_duration := _choose_downed_preroll_duration(animation_length)
	if preroll_duration <= 0.0:
		return false
	_ragdoll_preroll_active = true
	_ragdoll_preroll_is_dead = is_dead
	_ragdoll_preroll_animation_name = animation_name
	_ragdoll_preroll_remaining = preroll_duration
	if not play_clip(animation_name, 0.0, true, 0.0):
		_cancel_ragdoll_preroll()
		return false
	return true


func _process_downed_ragdoll_preroll(delta: float) -> void:
	_ragdoll_preroll_remaining = maxf(0.0, _ragdoll_preroll_remaining - delta)
	if _ragdoll_preroll_remaining > 0.0 and _character_animation_player != null and _character_animation_player.is_playing():
		return
	_finish_downed_ragdoll_preroll()


func _finish_downed_ragdoll_preroll() -> void:
	if not _ragdoll_preroll_active:
		return
	var was_dead: bool = _ragdoll_preroll_is_dead
	_cancel_ragdoll_preroll()
	stop_clip(true)
	_actor._apply_downed_collision_shape()
	if not start_ragdoll_simulation(was_dead):
		_actor._restore_downed_collision_shape()


func _cancel_ragdoll_preroll() -> void:
	_ragdoll_preroll_active = false
	_ragdoll_preroll_is_dead = false
	_ragdoll_preroll_animation_name = ""
	_ragdoll_preroll_remaining = 0.0


func _process_get_up_animation(delta: float) -> bool:
	_get_up_animation_remaining = maxf(0.0, _get_up_animation_remaining - delta)
	if not _get_up_animation_name.is_empty() and _character_animation_player != null and not _character_animation_player.is_playing() and _get_up_animation_remaining > 0.0:
		play_clip(_get_up_animation_name)
	return _get_up_animation_remaining <= 0.0


func _ensure_runtime_ragdoll() -> bool:
	if _ragdoll_skeleton == null or not is_instance_valid(_ragdoll_skeleton):
		var visual_root := get_visual_root()
		_ragdoll_skeleton = _find_skeleton(visual_root) if visual_root != null else null
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
	var profile = get_ragdoll_profile()
	if profile == null:
		return
	for bone_name_value in profile.physical_bone_names:
		var bone_name := String(bone_name_value)
		if bone_name.is_empty() or _ragdoll_physical_bones.has(bone_name):
			continue
		var bone_index: int = _ragdoll_skeleton.find_bone(bone_name)
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


func _configure_ragdoll_internal_collision_exceptions() -> void:
	var profile = get_ragdoll_profile()
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
		var bone_index: int = _ragdoll_skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		physical_bone.transform = _ragdoll_skeleton.get_bone_global_pose(bone_index)


func _prepare_ragdoll_activation() -> void:
	_actor.velocity.y = minf(_actor.velocity.y, 0.0)
	_ragdoll_upward_velocity_suppression_frames = RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES
	_set_ragdoll_bone_upward_velocity_suppression(RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES)
	if _ragdoll_skeleton != null and is_instance_valid(_ragdoll_skeleton):
		_ragdoll_skeleton.force_update_all_bone_transforms()


func _set_ragdoll_bone_upward_velocity_suppression(frame_count: int) -> void:
	for physical_bone_value in _ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone != null and is_instance_valid(physical_bone) and physical_bone.has_method("set_upward_velocity_suppression_frames"):
			physical_bone.call("set_upward_velocity_suppression_frames", frame_count)


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
		var child_name: String = _ragdoll_skeleton.get_bone_name(child_index)
		if not profile.has_physical_bone(child_name):
			continue
		var child_vector: Vector3 = _ragdoll_skeleton.get_bone_rest(child_index).origin
		var child_length_squared: float = child_vector.length_squared()
		if child_length_squared > best_length_squared:
			best_vector = child_vector
			best_length_squared = child_length_squared
	return best_vector


func _get_ragdoll_parent_continuation_axis(bone_index: int) -> Vector3:
	var bone_rest: Transform3D = _ragdoll_skeleton.get_bone_rest(bone_index)
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


func _apply_pending_ragdoll_impulse() -> void:
	if _last_ragdoll_impulse.length_squared() <= 0.0001 or _last_ragdoll_impulse_remaining <= 0.0:
		_last_ragdoll_impulse = Vector3.ZERO
		_last_ragdoll_impulse_remaining = 0.0
		return
	var ragdoll_impulse := _get_non_upward_ragdoll_vector(_last_ragdoll_impulse)
	var profile = get_ragdoll_profile()
	var root_bone_name := str(profile.get("root_bone_name")) if profile != null else "pelvis"
	var root_bone := _ragdoll_physical_bones.get(root_bone_name, null) as PhysicalBone3D
	if root_bone != null and is_instance_valid(root_bone):
		root_bone.apply_central_impulse(ragdoll_impulse)
	for bone_name in ["spine_02", "spine_03"]:
		var physical_bone := _ragdoll_physical_bones.get(bone_name, null) as PhysicalBone3D
		if physical_bone != null and is_instance_valid(physical_bone):
			physical_bone.apply_central_impulse(ragdoll_impulse * 0.35)
	_last_ragdoll_impulse = Vector3.ZERO
	_last_ragdoll_impulse_remaining = 0.0


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


func get_resolved_visual_body_type() -> int:
	var authored_body_type := _authored_visual_body_type()
	if authored_body_type != VisualBodyType.AUTO:
		return authored_body_type
	var authored_archetype := _authored_body_archetype()
	if authored_archetype != null:
		var archetype_body_type := int(authored_archetype.get("visual_body_type"))
		if archetype_body_type != VisualBodyType.NONE:
			return archetype_body_type
	return _infer_visual_body_type()


func get_resolved_body_archetype() -> Resource:
	var authored_archetype := _authored_body_archetype()
	if authored_archetype != null:
		return authored_archetype
	var race := _get_character_race()
	match get_resolved_visual_body_type():
		VisualBodyType.MALE:
			if race != null and race.get("default_male_archetype") != null:
				return race.get("default_male_archetype") as Resource
			return HUMAN_MALE_BODY_ARCHETYPE
		VisualBodyType.FEMALE:
			if race != null and race.get("default_female_archetype") != null:
				return race.get("default_female_archetype") as Resource
			return HUMAN_FEMALE_BODY_ARCHETYPE
	return null


func _get_character_race() -> Resource:
	var authored_race := _authored_character_race()
	if authored_race != null:
		return authored_race
	var authored_archetype := _authored_body_archetype()
	if authored_archetype != null and authored_archetype.get("race") != null:
		return authored_archetype.get("race") as Resource
	return HUMAN_RACE


func _infer_visual_body_type() -> int:
	var name_key: String = _actor.member_name.strip_edges().to_lower()
	if name_key.contains(" "):
		name_key = name_key.get_slice(" ", 0)
	if FEMALE_VISUAL_NAME_KEYS.has(name_key):
		return VisualBodyType.FEMALE
	return VisualBodyType.MALE


func _get_character_visual_scene(body_type: int, resolved_body_archetype: Resource) -> PackedScene:
	if resolved_body_archetype != null:
		var age_years := appearance_data.visual_age_years if appearance_data != null else CharacterVisualRules.DEFAULT_ADULT_AGE
		var toughness_level := appearance_data.visual_toughness_level if appearance_data != null else SkillRules.DEFAULT_LEVEL
		var archetype_visual_scene := CharacterVisualRules.get_body_visual_scene(resolved_body_archetype, age_years, toughness_level)
		if archetype_visual_scene != null:
			return archetype_visual_scene
	match body_type:
		VisualBodyType.MALE:
			return MALE_VISUAL_SCENE
		VisualBodyType.FEMALE:
			return FEMALE_VISUAL_SCENE
	return null


func _fit_visual_to_body_mesh(visual_root: Node3D, body_mesh: MeshInstance3D) -> float:
	var body_bounds := _calculate_local_mesh_bounds(body_mesh)
	var visual_bounds := _calculate_local_mesh_bounds(visual_root)
	if body_bounds.size.y <= 0.001 or visual_bounds.size.y <= 0.001:
		return 1.0

	var fit_scale := body_bounds.size.y / visual_bounds.size.y
	var body_center := body_bounds.position + body_bounds.size * 0.5
	var visual_center := visual_bounds.position + visual_bounds.size * 0.5
	var visual_ground_y: float = _get_visual_ground_y(body_bounds.position.y) + CHARACTER_VISUAL_FOOT_CLEARANCE
	visual_root.scale = Vector3.ONE * fit_scale
	visual_root.position = Vector3(
		body_center.x - visual_center.x * fit_scale,
		visual_ground_y - visual_bounds.position.y * fit_scale,
		body_center.z - visual_center.z * fit_scale
	)
	return fit_scale


func _get_clothing_surface_offset_base(body_mesh: MeshInstance3D, visual_fit_scale: float) -> float:
	var body_bounds := _calculate_local_mesh_bounds(body_mesh)
	if body_bounds.size.y <= 0.001:
		return 0.0
	return body_bounds.size.y / maxf(visual_fit_scale, 0.001)


func _get_visual_ground_y(fallback_y: float) -> float:
	var collision_shape := _actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return fallback_y
	var shape_bounds := _get_collision_shape_local_bounds(collision_shape)
	if shape_bounds.size.y <= 0.001:
		return fallback_y
	return shape_bounds.position.y


func _get_collision_shape_local_bounds(collision_shape: CollisionShape3D) -> AABB:
	var shape := collision_shape.shape
	var shape_bounds := AABB()
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		shape_bounds = AABB(
			Vector3(-capsule.radius, -capsule.height * 0.5, -capsule.radius),
			Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0)
		)
	elif shape is SphereShape3D:
		var sphere := shape as SphereShape3D
		shape_bounds = AABB(
			Vector3(-sphere.radius, -sphere.radius, -sphere.radius),
			Vector3(sphere.radius * 2.0, sphere.radius * 2.0, sphere.radius * 2.0)
		)
	elif shape is BoxShape3D:
		var box := shape as BoxShape3D
		shape_bounds = AABB(-box.size * 0.5, box.size)
	else:
		return AABB()
	return _transform_aabb(shape_bounds, collision_shape.transform)


func _calculate_local_mesh_bounds(root: Node) -> AABB:
	var result := {
		"has_bounds": false,
		"bounds": AABB(),
	}
	_accumulate_local_mesh_bounds(root, Transform3D.IDENTITY, result)
	return result["bounds"]


func _accumulate_local_mesh_bounds(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * node.transform

	if node is MeshInstance3D and node.mesh != null:
		var mesh_bounds := _transform_aabb(node.mesh.get_aabb(), local_transform)
		if result["has_bounds"]:
			result["bounds"] = (result["bounds"] as AABB).merge(mesh_bounds)
		else:
			result["bounds"] = mesh_bounds
			result["has_bounds"] = true

	for child in node.get_children():
		_accumulate_local_mesh_bounds(child, local_transform, result)


func _transform_aabb(bounds: AABB, bounds_transform: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := bounds_transform * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds


func _ensure_non_null_visual_materials(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				if mesh_instance.mesh.surface_get_material(surface_index) != null:
					continue
				if surface_index < mesh_instance.get_surface_override_material_count() and mesh_instance.get_surface_override_material(surface_index) != null:
					continue
				mesh_instance.set_surface_override_material(surface_index, _get_fallback_visual_material())
	for child in root.get_children():
		_ensure_non_null_visual_materials(child)


static func _get_fallback_visual_material() -> Material:
	if _fallback_visual_material != null:
		return _fallback_visual_material
	var material := StandardMaterial3D.new()
	material.resource_name = "Fallback Character Surface"
	material.albedo_color = Color(0.62, 0.58, 0.52, 1.0)
	material.roughness = 0.86
	_fallback_visual_material = material
	return _fallback_visual_material


# --- Animation library setup / copy ---

func setup_animation(model_root: Node3D) -> void:
	var animation_player := AnimationPlayer.new()
	animation_player.name = CHARACTER_ANIMATION_PLAYER_NAME
	animation_player.root_node = NodePath("..")
	model_root.add_child(animation_player)
	var animation_library := AnimationLibrary.new()
	_copy_character_animations(animation_library, _find_skeleton(model_root))
	if animation_library.get_animation_list().is_empty():
		animation_player.queue_free()
		return
	animation_player.add_animation_library("", animation_library)
	_character_animation_players.append(animation_player)
	if _character_animation_player == null:
		_character_animation_player = animation_player


func _copy_character_animations(animation_library: AnimationLibrary, target_skeleton: Skeleton3D) -> void:
	var ual1_source: Node = UAL1_ANIMATION_SOURCE_SCENE.instantiate()
	var ual1_player := _find_animation_player(ual1_source)
	if ual1_player != null:
		_copy_animation(ual1_player, animation_library, IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, TIRED_IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, WALK_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, CROUCH_ENTER_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, CROUCH_IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, CROUCH_WALK_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, CROUCH_EXIT_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, RUN_ENTER_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, JOG_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, RUN_EXIT_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, SITTING_ENTER_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, SITTING_IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, SITTING_TALKING_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, SITTING_EXIT_ANIMATION_NAME)
		_copy_default_combat_set_animations(ual1_player, animation_library)
		_copy_contextual_combat_reaction_animations(ual1_player, animation_library)
		_copy_ragdoll_profile_animations(ual1_player, animation_library)
		_copy_unarmed_combat_idle_animation(ual1_player, animation_library)
		_copy_animation(ual1_player, animation_library, SCAVENGING_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, COUNTER_ENTER_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, COUNTER_IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, COUNTER_SHOW_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, COUNTER_GIVE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, COUNTER_EXIT_ANIMATION_NAME)
	# Rig-proportion compensation per pack (each pack has its own source rig):
	# scale the pelvis/root position tracks so feet land on the floor instead
	# of the vendor mannequin's heights. See AnimationPositionScale.
	var ual1_names := animation_library.get_animation_list()
	AnimationPositionScale.scale_animation_names(animation_library, ual1_names, AnimationPositionScale.ratio_between(_find_skeleton(ual1_source), target_skeleton))
	ual1_source.queue_free()

	var ual2_source: Node = UAL2_ANIMATION_SOURCE_SCENE.instantiate()
	var ual2_player := _find_animation_player(ual2_source)
	if ual2_player != null:
		_copy_animation(ual2_player, animation_library, FOLD_ARMS_IDLE_ANIMATION_NAME)
		_copy_animation(ual2_player, animation_library, MINING_ANIMATION_NAME)
		_copy_animation(ual2_player, animation_library, FARM_HARVEST_ANIMATION_NAME)
		_copy_animation(ual2_player, animation_library, FARM_PLANT_ANIMATION_NAME)
		_copy_animation(ual2_player, animation_library, FARM_WATER_ANIMATION_NAME)
		_copy_animation(ual2_player, animation_library, LAY_ENTER_ANIMATION_NAME)
		_copy_animation(ual2_player, animation_library, LAY_EXIT_ANIMATION_NAME)
		_copy_default_combat_set_animations(ual2_player, animation_library)
		_copy_contextual_combat_reaction_animations(ual2_player, animation_library)
		_copy_ragdoll_profile_animations(ual2_player, animation_library)
		_copy_named_animations(ual2_player, animation_library, CARRY_POSE_ANIMATION_NAMES)
		_copy_named_animations(ual2_player, animation_library, CELL_CUSTODY_ANIMATION_NAMES)
	var ual2_names := []
	for animation_name in animation_library.get_animation_list():
		if not (animation_name in ual1_names):
			ual2_names.append(animation_name)
	AnimationPositionScale.scale_animation_names(animation_library, ual2_names, AnimationPositionScale.ratio_between(_find_skeleton(ual2_source), target_skeleton))
	ual2_source.queue_free()


func _copy_animation(source_player: AnimationPlayer, animation_library: AnimationLibrary, animation_name: String) -> void:
	if not source_player.has_animation(animation_name) or animation_library.has_animation(animation_name):
		return
	var source_animation := source_player.get_animation(animation_name)
	if source_animation == null:
		return
	var copied_animation := source_animation.duplicate(true) as Animation
	animation_library.add_animation(animation_name, copied_animation)


func _copy_named_animations(source_player: AnimationPlayer, animation_library: AnimationLibrary, animation_names: Array) -> void:
	for animation_name in animation_names:
		_copy_animation(source_player, animation_library, String(animation_name))


## Public lookup for the actor's attack-choice hooks (see HumanoidCharacter
## get_system_combat_attack_spec). Returns null for unknown stances.
func get_combat_animation_set(stance_id: String):
	_ensure_default_combat_animation_sets()
	return _combat_animation_sets.get(stance_id, null)


func _ensure_default_combat_animation_sets() -> void:
	if not _combat_animation_sets.is_empty():
		return
	_combat_animation_sets[UNARMED_STANCE_ID] = _build_unarmed_combat_animation_set()
	_combat_animation_sets[EquipmentGripProfile.GRIP_CLASS_ONE_HAND_MELEE] = _build_one_hand_melee_combat_animation_set()


func _build_unarmed_combat_animation_set():
	var animation_set = COMBAT_ANIMATION_SET_SCRIPT.new()
	animation_set.stance_id = UNARMED_STANCE_ID
	animation_set.idle_animation_name = UNARMED_COMBAT_IDLE_ANIMATION_NAME
	animation_set.block_animation_name = BLOCK_ANIMATION_NAME
	animation_set.fallback_hit_reaction_names = PackedStringArray([HIT_CHEST_ANIMATION_NAME, HIT_HEAD_ANIMATION_NAME, HIT_STOMACH_ANIMATION_NAME])
	# Light in-place attacks only: the heavier clips (uppercut/hook/knee/kick) carry
	# root motion the character body does not apply, so the mesh steps away from the
	# body and snaps back when the clip ends. Reintroduce them only with root-motion
	# handling in the actuator.
	animation_set.attacks = [
		_make_combat_attack("jab", [UNARMED_JAB_ANIMATION_NAME], 30.0, 0.42, [HIT_HEAD_ANIMATION_NAME, HIT_CHEST_ANIMATION_NAME]),
		_make_combat_attack("cross", [UNARMED_CROSS_ANIMATION_NAME], 24.0, 0.44, [HIT_HEAD_ANIMATION_NAME, HIT_CHEST_ANIMATION_NAME, HIT_SHOULDER_L_ANIMATION_NAME]),
	]
	return animation_set


func _build_one_hand_melee_combat_animation_set():
	var animation_set = COMBAT_ANIMATION_SET_SCRIPT.new()
	animation_set.stance_id = EquipmentGripProfile.GRIP_CLASS_ONE_HAND_MELEE
	animation_set.idle_animation_name = ONE_HAND_MELEE_IDLE_ANIMATION_NAME
	animation_set.block_animation_name = BLOCK_ANIMATION_NAME
	animation_set.fallback_hit_reaction_names = PackedStringArray([HIT_CHEST_ANIMATION_NAME, HIT_HEAD_ANIMATION_NAME, HIT_STOMACH_ANIMATION_NAME])
	animation_set.attacks = [
		_make_combat_attack("one_hand_light_a", ONE_HAND_LIGHT_A_ANIMATION_NAMES, 18.0, 0.42, [HIT_HEAD_ANIMATION_NAME, HIT_CHEST_ANIMATION_NAME]),
		_make_combat_attack("one_hand_light_b", ONE_HAND_LIGHT_B_ANIMATION_NAMES, 18.0, 0.42, [HIT_CHEST_ANIMATION_NAME, HIT_SHOULDER_L_ANIMATION_NAME]),
	]
	return animation_set


func _make_combat_attack(attack_id: String, animation_names: Array[String], weight: float, impact_ratio: float, hit_reaction_names: Array[String]):
	var attack = COMBAT_ATTACK_ANIMATION_SCRIPT.new()
	attack.attack_id = attack_id
	attack.animation_names = PackedStringArray(animation_names)
	attack.weight = weight
	attack.impact_ratio = impact_ratio
	attack.hit_reaction_names = PackedStringArray(hit_reaction_names)
	return attack


func _copy_default_combat_set_animations(source_player: AnimationPlayer, animation_library: AnimationLibrary) -> void:
	_ensure_default_combat_animation_sets()
	for animation_set_value in _combat_animation_sets.values():
		var animation_set = animation_set_value
		if animation_set == null:
			continue
		for animation_name in animation_set.get_all_animation_names():
			_copy_animation(source_player, animation_library, animation_name)


func _copy_contextual_combat_reaction_animations(source_player: AnimationPlayer, animation_library: AnimationLibrary) -> void:
	_copy_animation(source_player, animation_library, SHIELD_COMBAT_IDLE_ANIMATION_NAME)
	for animation_name in SHIELD_BLOCK_ANIMATION_NAMES:
		_copy_animation(source_player, animation_library, String(animation_name))


func _copy_ragdoll_profile_animations(source_player: AnimationPlayer, animation_library: AnimationLibrary) -> void:
	for animation_name in _get_ragdoll_profile_animation_names():
		_copy_animation(source_player, animation_library, String(animation_name))


func _copy_unarmed_combat_idle_animation(source_player: AnimationPlayer, animation_library: AnimationLibrary) -> void:
	if animation_library.has_animation(UNARMED_COMBAT_IDLE_ANIMATION_NAME):
		return
	if not source_player.has_animation(UNARMED_STANCE_ENTER_ANIMATION_NAME) or not source_player.has_animation(UNARMED_STANCE_EXIT_ANIMATION_NAME):
		return
	var enter_animation := source_player.get_animation(UNARMED_STANCE_ENTER_ANIMATION_NAME)
	var exit_animation := source_player.get_animation(UNARMED_STANCE_EXIT_ANIMATION_NAME)
	if enter_animation == null or exit_animation == null:
		return
	var enter_duration := minf(UNARMED_COMBAT_IDLE_SEGMENT_SECONDS, enter_animation.length)
	var exit_duration := minf(UNARMED_COMBAT_IDLE_SEGMENT_SECONDS, exit_animation.length)
	if enter_duration <= 0.0 or exit_duration <= 0.0:
		return
	var generated_animation := Animation.new()
	generated_animation.length = enter_duration + exit_duration
	generated_animation.loop_mode = Animation.LOOP_LINEAR
	var track_map: Dictionary = {}
	_copy_animation_time_window(enter_animation, generated_animation, maxf(0.0, enter_animation.length - enter_duration), enter_animation.length, 0.0, track_map)
	_copy_animation_time_window(exit_animation, generated_animation, 0.0, exit_duration, enter_duration, track_map)
	if generated_animation.get_track_count() == 0:
		return
	animation_library.add_animation(UNARMED_COMBAT_IDLE_ANIMATION_NAME, generated_animation)


func _copy_animation_time_window(source_animation: Animation, target_animation: Animation, source_start: float, source_end: float, target_offset: float, track_map: Dictionary) -> void:
	for source_track_index in range(source_animation.get_track_count()):
		var target_track_index := _get_or_create_copied_animation_track(source_animation, target_animation, source_track_index, track_map)
		var did_insert_key := false
		for key_index in range(source_animation.track_get_key_count(source_track_index)):
			var key_time := source_animation.track_get_key_time(source_track_index, key_index)
			if key_time < source_start or key_time > source_end:
				continue
			_target_insert_animation_key(source_animation, target_animation, source_track_index, target_track_index, key_index, target_offset + key_time - source_start)
			did_insert_key = true
		if not did_insert_key:
			var sample_key_index := _get_animation_sample_key_index(source_animation, source_track_index, source_start)
			if sample_key_index >= 0:
				_target_insert_animation_key(source_animation, target_animation, source_track_index, target_track_index, sample_key_index, target_offset)


func _get_or_create_copied_animation_track(source_animation: Animation, target_animation: Animation, source_track_index: int, track_map: Dictionary) -> int:
	var track_key := "%s|%s" % [str(source_animation.track_get_path(source_track_index)), str(source_animation.track_get_type(source_track_index))]
	if track_map.has(track_key):
		return int(track_map[track_key])
	var target_track_index := target_animation.add_track(source_animation.track_get_type(source_track_index))
	target_animation.track_set_path(target_track_index, source_animation.track_get_path(source_track_index))
	target_animation.track_set_interpolation_type(target_track_index, source_animation.track_get_interpolation_type(source_track_index))
	track_map[track_key] = target_track_index
	return target_track_index


func _get_animation_sample_key_index(source_animation: Animation, source_track_index: int, sample_time: float) -> int:
	var key_count := source_animation.track_get_key_count(source_track_index)
	if key_count <= 0:
		return -1
	var sample_key_index := 0
	for key_index in range(key_count):
		if source_animation.track_get_key_time(source_track_index, key_index) <= sample_time:
			sample_key_index = key_index
		else:
			break
	return sample_key_index


func _target_insert_animation_key(source_animation: Animation, target_animation: Animation, source_track_index: int, target_track_index: int, source_key_index: int, target_time: float) -> void:
	target_animation.track_insert_key(
		target_track_index,
		clampf(target_time, 0.0, target_animation.length),
		source_animation.track_get_key_value(source_track_index, source_key_index),
		source_animation.track_get_key_transition(source_track_index, source_key_index)
	)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


# --- Clip playback ---

func play_clip(animation_name: String, speed_ratio: float = 0.0, force_restart: bool = false, blend_seconds: float = DEFAULT_MOVE_BLEND_SECONDS) -> bool:
	if _character_animation_player == null or not _character_animation_player.has_animation(animation_name):
		return false
	var custom_speed := _get_clip_speed(animation_name, speed_ratio)
	var already_current: bool = _current_character_animation == animation_name
	_current_character_animation = animation_name
	var started_animation := false
	for animation_player in _character_animation_players:
		if animation_player == null or not animation_player.has_animation(animation_name):
			continue
		animation_player.speed_scale = custom_speed
		if not force_restart and already_current and animation_player.is_playing():
			continue
		animation_player.play(animation_name, blend_seconds)
		animation_player.advance(0.0)
		started_animation = true
	if started_animation:
		apply_bone_pose_offsets()
		refresh_foot_ground_alignment()
	return true


func stop_clip(keep_state: bool = true) -> void:
	_current_character_animation = ""
	for animation_player in _character_animation_players:
		if animation_player == null:
			continue
		animation_player.stop(keep_state)
		animation_player.speed_scale = 1.0


func clip_length(animation_name: String) -> float:
	var player: AnimationPlayer = _character_animation_player
	if player == null or not player.has_animation(animation_name):
		return 0.0
	var animation := player.get_animation(animation_name)
	return animation.length if animation != null else 0.0


func get_clip_length(animation_name: String) -> float:
	if _character_animation_player == null or not _character_animation_player.has_animation(animation_name):
		return 0.0
	return _character_animation_player.get_animation(animation_name).length


func has_clip(animation_name: String) -> bool:
	var player: AnimationPlayer = _character_animation_player
	return player != null and player.has_animation(animation_name)


func get_current_clip() -> String:
	return _current_character_animation


func is_current_clip_playing() -> bool:
	return _character_animation_player != null and _character_animation_player.is_playing()


func get_primary_animation_player() -> AnimationPlayer:
	return _character_animation_player


func get_animation_players() -> Array[AnimationPlayer]:
	return _character_animation_players.duplicate()


func get_skeleton() -> Skeleton3D:
	return _character_skeleton


func seek_clip(animation_name: String, time: float, update: bool = true, speed_scale: float = 1.0) -> void:
	var animation_length := clip_length(animation_name)
	var seek_time := clampf(time, 0.0, maxf(0.0, animation_length - 0.001))
	for animation_player in _character_animation_players:
		if animation_player != null and animation_player.has_animation(animation_name):
			animation_player.seek(seek_time, update)
			animation_player.speed_scale = speed_scale


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
		return super.get_combat_action_timing(animation_names, impact_ratio, default_seconds)
	return {
		"total_seconds": total_seconds,
		"first_clip_seconds": first_clip_seconds,
		"impact_seconds": _get_combat_impact_seconds(first_clip_seconds if first_clip_seconds > 0.0 else total_seconds, impact_ratio),
	}


func pick_block_reaction_clip(has_shield: bool, animation_set, shield_block_animation_names: Array[String], fallback_block_animation_name: String) -> String:
	if has_shield:
		var shield_block_animation := pick_available_clip(shield_block_animation_names)
		if not shield_block_animation.is_empty():
			return shield_block_animation
	if animation_set != null and not str(animation_set.block_animation_name).is_empty():
		return str(animation_set.block_animation_name)
	return fallback_block_animation_name


func pick_hit_reaction_clip(attack_id: String, hit_reaction_names: Array[String] = []) -> String:
	if not hit_reaction_names.is_empty():
		return pick_available_clip(hit_reaction_names)
	match attack_id:
		"knee":
			return pick_available_clip([HIT_STOMACH_ANIMATION_NAME])
		"kick":
			return pick_available_clip([HIT_HEAD_ANIMATION_NAME])
		"uppercut":
			return pick_available_clip([HIT_HEAD_ANIMATION_NAME])
		"hook":
			return pick_available_clip([HIT_HEAD_ANIMATION_NAME, HIT_SHOULDER_L_ANIMATION_NAME, HIT_SHOULDER_R_ANIMATION_NAME])
		"cross":
			return pick_available_clip([HIT_HEAD_ANIMATION_NAME, HIT_CHEST_ANIMATION_NAME, HIT_SHOULDER_L_ANIMATION_NAME])
		"jab":
			return pick_available_clip([HIT_HEAD_ANIMATION_NAME, HIT_CHEST_ANIMATION_NAME])
	return pick_available_clip([HIT_CHEST_ANIMATION_NAME, HIT_HEAD_ANIMATION_NAME, HIT_STOMACH_ANIMATION_NAME])


func pick_available_clip(animation_names: Array[String]) -> String:
	var available: Array[String] = []
	for animation_name in animation_names:
		if has_clip(animation_name):
			available.append(animation_name)
	if available.is_empty():
		return ""
	return available[_rng.randi_range(0, available.size() - 1)]


func pick_preferred_available_clip(animation_names: Array[String]) -> String:
	for animation_name in animation_names:
		if has_clip(animation_name):
			return animation_name
	return ""


func play_combat_reaction_clip(animation_name: String, blend_seconds: float) -> float:
	if animation_name.is_empty() or not has_clip(animation_name):
		return 0.0
	if not play_clip(animation_name, 0.0, true, blend_seconds):
		return 0.0
	return maxf(0.1, clip_length(animation_name))


func _get_clip_speed(animation_name: String, speed_ratio: float) -> float:
	if animation_name == WALK_ANIMATION_NAME:
		return lerpf(0.85, 1.25, speed_ratio)
	elif animation_name == CROUCH_WALK_ANIMATION_NAME:
		return lerpf(0.85, 1.15, speed_ratio)
	elif animation_name == JOG_ANIMATION_NAME:
		return lerpf(0.9, 1.35, speed_ratio)
	return 1.0


# --- Idle clip selection (clip-name knowledge) ---

func get_available_idle_clip_names() -> Array[String]:
	var idle_names: Array[String] = []
	if _character_animation_player == null:
		return idle_names
	for animation_name_value in IDLE_ANIMATION_NAMES:
		var animation_name := String(animation_name_value)
		if _character_animation_player.has_animation(animation_name):
			idle_names.append(animation_name)
	return idle_names


func is_idle_clip(animation_name: String) -> bool:
	return IDLE_ANIMATION_NAMES.has(animation_name)


# --- Locomotion / idle visuals ---

## Locomotion animation driver. Picks idle/walk/jog (or crouch variants) from the
## actor's movement state and plays the matching clip. Combat/mining/sitting/carry
## animation states are separate concerns rebuilt in later phases.
func update_locomotion(delta: float, horizontal_speed: float, reference_move_speed: float, is_moving: bool, wants_run: bool, is_sneaking: bool, use_tired_idle := false) -> void:
	if get_primary_animation_player() == null:
		return
	if update_crouch_enter_animation(delta):
		return
	if update_crouch_exit_animation(delta):
		return
	if update_run_transition(delta, wants_run):
		return
	if is_sneaking:
		if is_moving:
			play_clip(CROUCH_WALK_ANIMATION_NAME, _locomotion_speed_ratio(horizontal_speed, reference_move_speed))
		else:
			play_clip(CROUCH_IDLE_ANIMATION_NAME)
		return
	if not is_moving:
		update_idle_animation(delta, use_tired_idle)
		return
	if wants_run:
		play_clip(JOG_ANIMATION_NAME, _locomotion_speed_ratio(horizontal_speed, reference_move_speed * NpcRules.RUN_SPEED_MULTIPLIER))
	else:
		play_clip(WALK_ANIMATION_NAME, _locomotion_speed_ratio(horizontal_speed, reference_move_speed))


func _locomotion_speed_ratio(horizontal_speed: float, reference_speed: float) -> float:
	return clampf(horizontal_speed / maxf(reference_speed, 0.001), 0.0, 1.0)


func update_idle_animation(delta: float, use_tired_idle: bool) -> void:
	if use_tired_idle:
		if _current_character_animation != TIRED_IDLE_ANIMATION_NAME or not is_current_clip_playing():
			play_clip(TIRED_IDLE_ANIMATION_NAME)
		return
	if not is_idle_clip(_current_character_animation) or not is_current_clip_playing():
		play_random_idle_animation(true)
		return
	_idle_animation_change_remaining -= delta
	if _idle_animation_change_remaining <= 0.0:
		play_random_idle_animation(false)


func play_random_idle_animation(force: bool) -> void:
	var idle_names := get_available_idle_clip_names()
	if idle_names.is_empty():
		return
	var animation_index: int = _rng.randi_range(0, idle_names.size() - 1)
	var animation_name := idle_names[animation_index]
	if not force and idle_names.size() > 1 and animation_name == _current_character_animation:
		animation_name = idle_names[(animation_index + 1) % idle_names.size()]
	play_clip(animation_name)
	_reset_idle_animation_timer()


func _reset_idle_animation_timer() -> void:
	_idle_animation_change_remaining = _rng.randf_range(IDLE_ANIMATION_MIN_SECONDS, IDLE_ANIMATION_MAX_SECONDS)


func start_crouch_enter_animation() -> void:
	_crouch_exit_animation_remaining = 0.0
	if play_clip(CROUCH_ENTER_ANIMATION_NAME):
		_crouch_enter_animation_remaining = clip_length(CROUCH_ENTER_ANIMATION_NAME)
	else:
		_crouch_enter_animation_remaining = 0.0


func start_crouch_exit_animation() -> void:
	_crouch_enter_animation_remaining = 0.0
	if play_clip(CROUCH_EXIT_ANIMATION_NAME):
		_crouch_exit_animation_remaining = clip_length(CROUCH_EXIT_ANIMATION_NAME)
	else:
		_crouch_exit_animation_remaining = 0.0


func cancel_crouch_transition() -> void:
	_crouch_enter_animation_remaining = 0.0
	_crouch_exit_animation_remaining = 0.0


func update_crouch_enter_animation(delta: float) -> bool:
	if _crouch_enter_animation_remaining <= 0.0:
		return false
	_crouch_enter_animation_remaining = maxf(0.0, _crouch_enter_animation_remaining - delta)
	if _crouch_enter_animation_remaining > 0.0:
		play_clip(CROUCH_ENTER_ANIMATION_NAME)
	return true


func update_crouch_exit_animation(delta: float) -> bool:
	if _crouch_exit_animation_remaining <= 0.0:
		return false
	_crouch_exit_animation_remaining = maxf(0.0, _crouch_exit_animation_remaining - delta)
	if _crouch_exit_animation_remaining > 0.0:
		play_clip(CROUCH_EXIT_ANIMATION_NAME)
	return true


func update_run_transition(delta: float, wants_run_animation: bool) -> bool:
	if wants_run_animation:
		_run_exit_animation_remaining = 0.0
		if not _running_locomotion_active and _run_enter_animation_remaining <= 0.0:
			_start_run_enter_animation()
		_running_locomotion_active = true
		if _run_enter_animation_remaining > 0.0:
			_update_run_enter_animation(delta)
			return true
		return false

	_run_enter_animation_remaining = 0.0
	if _running_locomotion_active and _run_exit_animation_remaining <= 0.0:
		_start_run_exit_animation()
	_running_locomotion_active = false
	if _run_exit_animation_remaining > 0.0:
		_update_run_exit_animation(delta)
		return true
	return false


func _start_run_enter_animation() -> void:
	_run_exit_animation_remaining = 0.0
	if play_clip(RUN_ENTER_ANIMATION_NAME):
		_run_enter_animation_remaining = clip_length(RUN_ENTER_ANIMATION_NAME)
	else:
		_run_enter_animation_remaining = 0.0


func _start_run_exit_animation() -> void:
	_run_enter_animation_remaining = 0.0
	if play_clip(RUN_EXIT_ANIMATION_NAME):
		_run_exit_animation_remaining = clip_length(RUN_EXIT_ANIMATION_NAME)
	else:
		_run_exit_animation_remaining = 0.0


func cancel_run_transition() -> void:
	_run_enter_animation_remaining = 0.0
	_run_exit_animation_remaining = 0.0
	_running_locomotion_active = false


func _update_run_enter_animation(delta: float) -> void:
	_run_enter_animation_remaining = maxf(0.0, _run_enter_animation_remaining - delta)
	if _run_enter_animation_remaining > 0.0:
		play_clip(RUN_ENTER_ANIMATION_NAME)


func _update_run_exit_animation(delta: float) -> void:
	_run_exit_animation_remaining = maxf(0.0, _run_exit_animation_remaining - delta)
	if _run_exit_animation_remaining > 0.0:
		play_clip(RUN_EXIT_ANIMATION_NAME)


func start_sitting_enter_animation(allow_talking_idle: bool = false) -> void:
	_sitting_exit_animation_remaining = 0.0
	_sitting_idle_change_remaining = 0.0
	if play_clip(SITTING_ENTER_ANIMATION_NAME):
		_sitting_enter_animation_remaining = clip_length(SITTING_ENTER_ANIMATION_NAME)
	else:
		_sitting_enter_animation_remaining = 0.0
		_play_sitting_idle_animation(true, allow_talking_idle)


func start_sitting_exit_animation() -> void:
	_sitting_enter_animation_remaining = 0.0
	_sitting_idle_change_remaining = 0.0
	if play_clip(SITTING_EXIT_ANIMATION_NAME):
		_sitting_exit_animation_remaining = clip_length(SITTING_EXIT_ANIMATION_NAME)
	else:
		_sitting_exit_animation_remaining = 0.0


func update_sitting_animation(delta: float, allow_talking_idle: bool) -> void:
	if _sitting_enter_animation_remaining > 0.0:
		_sitting_enter_animation_remaining -= delta
		if _sitting_enter_animation_remaining > 0.0:
			play_clip(SITTING_ENTER_ANIMATION_NAME)
			return
		_sitting_enter_animation_remaining = 0.0
		_play_sitting_idle_animation(true, allow_talking_idle)
		return
	if not _is_sitting_idle_animation(_current_character_animation) or not is_current_clip_playing():
		_play_sitting_idle_animation(true, allow_talking_idle)
		return
	_sitting_idle_change_remaining -= delta
	if _sitting_idle_change_remaining <= 0.0:
		_play_sitting_idle_animation(false, allow_talking_idle)


func update_sitting_exit_animation(delta: float) -> bool:
	if _sitting_exit_animation_remaining <= 0.0:
		return false
	_sitting_exit_animation_remaining = maxf(0.0, _sitting_exit_animation_remaining - delta)
	if _sitting_exit_animation_remaining > 0.0:
		play_clip(SITTING_EXIT_ANIMATION_NAME)
	return true


func cancel_sitting_exit_animation() -> void:
	_sitting_exit_animation_remaining = 0.0


func _play_sitting_idle_animation(force: bool, allow_talking_idle: bool) -> void:
	if _character_animation_player == null:
		return
	var animation_name: String = SITTING_IDLE_ANIMATION_NAME
	if allow_talking_idle and _rng.randf() <= SITTING_TALKING_CHANCE:
		animation_name = SITTING_TALKING_ANIMATION_NAME
	if not has_clip(animation_name):
		animation_name = SITTING_IDLE_ANIMATION_NAME
	if not has_clip(animation_name):
		return
	if not force and animation_name == _current_character_animation and animation_name == SITTING_TALKING_ANIMATION_NAME:
		animation_name = SITTING_IDLE_ANIMATION_NAME
	play_clip(animation_name)
	_reset_sitting_idle_animation_timer()


func _is_sitting_idle_animation(animation_name: String) -> bool:
	return animation_name == SITTING_IDLE_ANIMATION_NAME or animation_name == SITTING_TALKING_ANIMATION_NAME


func _reset_sitting_idle_animation_timer() -> void:
	_sitting_idle_change_remaining = _rng.randf_range(SITTING_IDLE_MIN_SECONDS, SITTING_IDLE_MAX_SECONDS)


# --- Equipment / attachment visuals ---

func set_preview_clothes_visible(visible_flag: bool) -> void:
	_preview_clothes_visible = visible_flag
	set_equipped_clothing_visuals_visible(visible_flag)


func set_equipped_clothing_visuals_visible(visible_flag: bool) -> void:
	var visual_root := get_visual_root()
	if visual_root == null:
		return
	for child in visual_root.get_children():
		if str(child.name).begins_with("Equipped_"):
			(child as Node3D).visible = visible_flag


func refresh_grip_sockets_for_body() -> void:
	var visual_root := get_visual_root()
	if visual_root == null:
		return
	_setup_humanoid_grip_sockets(visual_root)
	refresh_bone_equipment_slots(BONE_EQUIPMENT_SLOTS.keys())


func rebuild_visual_for_equipment() -> void:
	if not _actor.is_inside_tree():
		return
	setup_visual()


func can_refresh_bone_equipment_only(changed_slots: Array) -> bool:
	if not _actor.is_inside_tree() or changed_slots.is_empty():
		return false
	for slot_name in changed_slots:
		if not BONE_EQUIPMENT_SLOTS.has(str(slot_name)):
			return false
	var visual_root := get_visual_root()
	if visual_root == null:
		return false
	return _find_skeleton(visual_root) != null


func refresh_bone_equipment_slots(changed_slots: Array) -> void:
	var visual_root := get_visual_root()
	if visual_root == null:
		rebuild_visual_for_equipment()
		return
	var skeleton := _find_skeleton(visual_root)
	if skeleton == null:
		rebuild_visual_for_equipment()
		return
	for slot_name in changed_slots:
		_refresh_bone_equipment_slot(skeleton, str(slot_name))


func _refresh_bone_equipment_slot(skeleton: Skeleton3D, slot_name: String) -> void:
	_remove_bone_equipment_slot(skeleton, slot_name)
	var item: ItemDefinition = _actor.get_equipped_item(slot_name)
	_add_bone_equipment_slot(skeleton, slot_name, item)


func _remove_bone_equipment_slot(skeleton: Skeleton3D, slot_name: String) -> void:
	var existing_visual := _find_node3d_by_name(skeleton, _get_bone_equipment_visual_name(slot_name))
	if existing_visual != null:
		existing_visual.free()
	var legacy_attachment := skeleton.get_node_or_null(_get_bone_attachment_name(slot_name))
	if legacy_attachment != null:
		legacy_attachment.free()


func _setup_equipped_clothing_visuals(visual_root: Node3D, character_skeleton: Skeleton3D, visual_body_archetype: Resource, body_mesh: MeshInstance3D, visual_fit_scale: float) -> void:
	var surface_offset_base := _get_clothing_surface_offset_base(body_mesh, visual_fit_scale)
	for slot_name in CLOTHING_EQUIPMENT_SLOTS:
		var item: ItemDefinition = _actor.get_equipped_item(slot_name)
		if item == null:
			continue
		var equipment_visual := item.get_equipment_visual_for_body_archetype(visual_body_archetype)
		var equipped_scene := item.get_equipped_scene_for_body_archetype(visual_body_archetype)
		if equipped_scene == null:
			continue
		var instance := equipped_scene.instantiate()
		if not (instance is Node3D):
			instance.queue_free()
			continue
		var model_root := instance as Node3D
		model_root.name = "Equipped_%s" % slot_name.capitalize()
		var visual_transform := item.equipped_transform
		var surface_offset_ratio := 0.0
		if equipment_visual != null:
			visual_transform = equipment_visual.get("equipped_transform")
			surface_offset_ratio = float(equipment_visual.get("surface_offset_ratio"))
		var surface_offset := surface_offset_base * surface_offset_ratio
		if character_skeleton != null and _setup_shared_skeleton_clothing_visual(visual_root, character_skeleton, model_root, visual_transform, surface_offset):
			model_root.free()
			continue
		_setup_legacy_clothing_visual(visual_root, model_root, visual_transform, surface_offset)


func _setup_head_attachment_visuals(visual_root: Node3D, character_skeleton: Skeleton3D) -> void:
	if appearance_data == null:
		return
	_setup_head_attachment_visual(visual_root, character_skeleton, appearance_data.hair_style, appearance_data.hair_color, "Hair")
	_setup_head_attachment_visual(visual_root, character_skeleton, appearance_data.beard_style, appearance_data.beard_color, "Beard")
	_setup_head_attachment_visual(visual_root, character_skeleton, appearance_data.eyebrow_style, appearance_data.eyebrow_color, "Eyebrows")


func _setup_head_attachment_visual(visual_root: Node3D, character_skeleton: Skeleton3D, style_resource: Resource, color: Color, slot_label: String) -> void:
	if visual_root == null or style_resource == null:
		return
	var age_years := appearance_data.visual_age_years if appearance_data != null else CharacterVisualRules.DEFAULT_ADULT_AGE
	var source_root := CharacterVisualAssembler.instantiate_head_attachment(style_resource, age_years, color)
	if source_root == null:
		return
	source_root.name = "%s%s" % [APPEARANCE_HEAD_ATTACHMENT_PREFIX, slot_label]
	if character_skeleton != null and _setup_shared_skeleton_head_attachment_visual(visual_root, character_skeleton, source_root, color, false):
		source_root.free()
		return
	_setup_legacy_head_attachment_visual(visual_root, source_root, color, false)


func _setup_shared_skeleton_head_attachment_visual(visual_root: Node3D, character_skeleton: Skeleton3D, source_root: Node3D, color: Color, colorize: bool) -> bool:
	var source_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(source_root, source_meshes)
	if source_meshes.is_empty():
		return false
	var slot_root := Node3D.new()
	slot_root.name = source_root.name
	slot_root.transform = Transform3D(Basis(Vector3.UP, CHARACTER_VISUAL_YAW_OFFSET), Vector3.ZERO)
	visual_root.add_child(slot_root)
	var copied_mesh_count := 0
	for source_mesh in source_meshes:
		if source_mesh == null or source_mesh.mesh == null:
			continue
		var attachment_mesh := _copy_clothing_mesh_instance(source_root, source_mesh)
		if colorize:
			_apply_head_attachment_material(attachment_mesh, color)
		slot_root.add_child(attachment_mesh)
		attachment_mesh.skeleton = attachment_mesh.get_path_to(character_skeleton)
		copied_mesh_count += 1
	if copied_mesh_count <= 0:
		slot_root.free()
		return false
	return true


func _setup_legacy_head_attachment_visual(visual_root: Node3D, source_root: Node3D, color: Color, colorize: bool) -> void:
	source_root.transform = Transform3D(Basis(Vector3.UP, CHARACTER_VISUAL_YAW_OFFSET), Vector3.ZERO)
	if colorize:
		_apply_head_attachment_material(source_root, color)
	visual_root.add_child(source_root)


func _apply_head_attachment_material(root: Node, color: Color) -> void:
	if root is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.82
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_head_attachment_material(child, color)


func _setup_shared_skeleton_clothing_visual(visual_root: Node3D, character_skeleton: Skeleton3D, source_root: Node3D, visual_transform: Transform3D, surface_offset: float) -> bool:
	var source_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(source_root, source_meshes)
	if source_meshes.is_empty():
		return false

	var slot_root := Node3D.new()
	slot_root.name = source_root.name
	slot_root.transform = Transform3D(Basis(Vector3.UP, CHARACTER_VISUAL_YAW_OFFSET), Vector3.ZERO) * visual_transform
	visual_root.add_child(slot_root)
	var copied_mesh_count := 0
	for source_mesh in source_meshes:
		if source_mesh == null or source_mesh.mesh == null:
			continue
		var clothing_mesh := _copy_clothing_mesh_instance(source_root, source_mesh)
		slot_root.add_child(clothing_mesh)
		clothing_mesh.skeleton = clothing_mesh.get_path_to(character_skeleton)
		_inflate_clothing_visual(clothing_mesh, surface_offset)
		copied_mesh_count += 1

	if copied_mesh_count <= 0:
		slot_root.free()
		return false
	return true


func _setup_legacy_clothing_visual(visual_root: Node3D, model_root: Node3D, visual_transform: Transform3D, surface_offset: float) -> void:
	model_root.transform = Transform3D(Basis(Vector3.UP, CHARACTER_VISUAL_YAW_OFFSET), Vector3.ZERO) * visual_transform
	_inflate_clothing_visual(model_root, surface_offset)
	visual_root.add_child(model_root)
	setup_animation(model_root)


func _collect_mesh_instances(root: Node, meshes: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_mesh_instances(child, meshes)


func _copy_clothing_mesh_instance(source_root: Node3D, source_mesh: MeshInstance3D) -> MeshInstance3D:
	var clothing_mesh := MeshInstance3D.new()
	clothing_mesh.name = source_mesh.name
	clothing_mesh.transform = _get_node3d_transform_relative_to_root(source_root, source_mesh)
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


func _setup_equipped_bone_visuals(visual_root: Node3D) -> void:
	var skeleton := _find_skeleton(visual_root)
	if skeleton == null:
		return
	for slot_name in BONE_EQUIPMENT_SLOTS.keys():
		var item: ItemDefinition = _actor.get_equipped_item(slot_name)
		_add_bone_equipment_slot(skeleton, slot_name, item)


func _add_bone_equipment_slot(skeleton: Skeleton3D, slot_name: String, item: ItemDefinition) -> void:
	if item == null:
		return
	var equipped_scene := item.get_equipped_scene_for_body_archetype(get_resolved_body_archetype())
	if equipped_scene == null:
		return
	var instance := equipped_scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return
	var socket_id := _get_equipment_socket_id(item, slot_name)
	var fallback_bone_name := _get_equipment_attachment_bone(item, slot_name)
	var socket := _get_or_create_humanoid_grip_socket(skeleton, socket_id, fallback_bone_name)
	if socket == null:
		instance.queue_free()
		return
	var slot_visual := Node3D.new()
	slot_visual.name = _get_bone_equipment_visual_name(slot_name)
	socket.add_child(slot_visual)
	var model_root := instance as Node3D
	model_root.transform = item.equipped_transform * _get_item_grip_transform(model_root, item, slot_name).affine_inverse()
	slot_visual.add_child(model_root)


func _get_bone_attachment_name(slot_name: String) -> String:
	return "Equipped%sAttachment" % slot_name.capitalize()


func _get_bone_equipment_visual_name(slot_name: String) -> String:
	return "Equipped%sVisual" % slot_name.capitalize()


func _setup_humanoid_grip_sockets(visual_root: Node3D) -> void:
	var skeleton := _find_skeleton(visual_root)
	if skeleton == null:
		return
	var socket_profile := _get_grip_socket_profile()
	if socket_profile == null or not socket_profile.has_method("get_socket_ids"):
		return
	for socket_id in socket_profile.get_socket_ids():
		_get_or_create_humanoid_grip_socket(skeleton, str(socket_id))


func _get_or_create_humanoid_grip_socket(skeleton: Skeleton3D, socket_id: String, fallback_bone_name := "") -> Node3D:
	if socket_id.is_empty():
		return null
	var socket_name := _get_equipment_socket_node_name(socket_id)
	var attachment_name := _get_humanoid_grip_socket_attachment_name(socket_id)
	var bone_name := _get_equipment_socket_bone_name(socket_id)
	if bone_name.is_empty():
		bone_name = fallback_bone_name
	var attachment := skeleton.get_node_or_null(attachment_name) as BoneAttachment3D
	if attachment == null:
		if bone_name.is_empty() or skeleton.find_bone(bone_name) < 0:
			return null
		attachment = BoneAttachment3D.new()
		attachment.name = attachment_name
		attachment.bone_name = bone_name
		skeleton.add_child(attachment)
	elif not bone_name.is_empty() and skeleton.find_bone(bone_name) >= 0 and attachment.bone_name != bone_name:
		attachment.bone_name = bone_name
	var socket := attachment.get_node_or_null(socket_name) as Node3D
	if socket == null:
		socket = HUMANOID_GRIP_SOCKET_MARKER_SCRIPT.new() as Node3D
		socket.name = socket_name
		attachment.add_child(socket)
	if socket.get_script() == HUMANOID_GRIP_SOCKET_MARKER_SCRIPT:
		socket.set("socket_id", socket_id)
		socket.set("show_runtime_visual", show_grip_socket_markers)
	socket.transform = _get_equipment_socket_transform(socket_id)
	return socket


func _get_humanoid_grip_socket_attachment_name(socket_id: String) -> String:
	return "%sAttachment" % _get_equipment_socket_node_name(socket_id)


func _get_equipment_socket_transform(socket_id: String) -> Transform3D:
	var socket_profile := _get_grip_socket_profile()
	if socket_profile != null and socket_profile.has_method("get_socket_transform"):
		return socket_profile.get_socket_transform(socket_id)
	return Transform3D.IDENTITY


func _get_equipment_socket_node_name(socket_id: String) -> String:
	var socket_profile := _get_grip_socket_profile()
	if socket_profile != null and socket_profile.has_method("get_socket_node_name"):
		return socket_profile.get_socket_node_name(socket_id)
	return "GripSocket"


func _get_equipment_socket_bone_name(socket_id: String) -> String:
	var socket_profile := _get_grip_socket_profile()
	if socket_profile != null and socket_profile.has_method("get_socket_bone_name"):
		return socket_profile.get_socket_bone_name(socket_id)
	return ""


func _get_grip_socket_profile() -> Resource:
	if grip_socket_profile != null:
		return grip_socket_profile
	var resolved_body_archetype := get_resolved_body_archetype()
	if resolved_body_archetype != null:
		var body_profile := resolved_body_archetype.get("grip_socket_profile") as Resource
		if body_profile != null:
			return body_profile
	return DEFAULT_GRIP_SOCKET_PROFILE


func _get_equipment_socket_id(item: ItemDefinition, slot_name: String) -> String:
	if item != null and item.grip_profile != null:
		var socket_id := str(item.grip_profile.get("primary_socket_id"))
		if not socket_id.is_empty():
			return socket_id
	match slot_name:
		"weapon":
			return "right_hand_one_hand"
		"offhand":
			return "left_hand_shield"
	return ""


func _get_item_grip_transform(model_root: Node3D, item: ItemDefinition, slot_name: String) -> Transform3D:
	var marker_name := _get_item_grip_marker_name(item, slot_name)
	if marker_name.is_empty():
		return Transform3D.IDENTITY
	var marker := _find_node3d_by_name(model_root, marker_name)
	if marker == null:
		push_warning("Missing %s marker in %s; using wrapper root as grip point." % [marker_name, item.display_name])
		return Transform3D.IDENTITY
	return _get_node3d_transform_relative_to_root(model_root, marker)


func _get_item_grip_marker_name(item: ItemDefinition, _slot_name: String) -> String:
	if item != null and item.grip_profile != null:
		var marker_name := str(item.grip_profile.get("primary_grip_marker"))
		if not marker_name.is_empty():
			return marker_name
	return "GripPoint_Primary"


func _find_node3d_by_name(root: Node, node_name: String) -> Node3D:
	if root is Node3D and root.name == node_name:
		return root as Node3D
	for child in root.get_children():
		var found := _find_node3d_by_name(child, node_name)
		if found != null:
			return found
	return null


func _get_node3d_transform_relative_to_root(root: Node3D, target: Node3D) -> Transform3D:
	if target == root:
		return Transform3D.IDENTITY
	var current: Node = target
	var result := Transform3D.IDENTITY
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _get_equipment_attachment_bone(item: ItemDefinition, slot_name: String) -> String:
	if item != null and item.grip_profile != null:
		var primary_bone := str(item.grip_profile.get("primary_bone"))
		if not primary_bone.is_empty():
			return primary_bone
	return str(BONE_EQUIPMENT_SLOTS.get(slot_name, ""))


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null


func _inflate_clothing_visual(root: Node, surface_offset: float) -> void:
	if surface_offset <= 0.0:
		return
	if root is MeshInstance3D:
		_inflate_mesh_instance(root as MeshInstance3D, surface_offset)
	for child in root.get_children():
		_inflate_clothing_visual(child, surface_offset)


func _inflate_mesh_instance(mesh_instance: MeshInstance3D, surface_offset: float) -> void:
	if mesh_instance.mesh == null or not (mesh_instance.mesh is ArrayMesh):
		return
	var source_mesh := mesh_instance.mesh as ArrayMesh
	var inflated_mesh := ArrayMesh.new()
	inflated_mesh.set_blend_shape_mode(source_mesh.get_blend_shape_mode())
	var blend_shape_values: Array[float] = []
	for blend_shape_index in range(source_mesh.get_blend_shape_count()):
		inflated_mesh.add_blend_shape(source_mesh.get_blend_shape_name(blend_shape_index))
		blend_shape_values.append(mesh_instance.get_blend_shape_value(blend_shape_index))
	for surface_index in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if not vertices.is_empty() and normals.size() == vertices.size():
			for vertex_index in range(vertices.size()):
				var normal := normals[vertex_index]
				if normal.length_squared() > 0.0001:
					vertices[vertex_index] += normal.normalized() * surface_offset
			arrays[Mesh.ARRAY_VERTEX] = vertices
		inflated_mesh.add_surface_from_arrays(
			source_mesh.surface_get_primitive_type(surface_index),
			arrays,
			source_mesh.surface_get_blend_shape_arrays(surface_index),
			{},
			source_mesh.surface_get_format(surface_index)
		)
		var source_material := source_mesh.surface_get_material(surface_index)
		if source_material != null:
			inflated_mesh.surface_set_material(surface_index, source_material)
		inflated_mesh.surface_set_name(surface_index, source_mesh.surface_get_name(surface_index))
	if inflated_mesh.get_surface_count() == source_mesh.get_surface_count():
		mesh_instance.mesh = inflated_mesh
		for blend_shape_index in range(mini(mesh_instance.get_blend_shape_count(), blend_shape_values.size())):
			mesh_instance.set_blend_shape_value(blend_shape_index, blend_shape_values[blend_shape_index])


# --- Foot IK / grounding ---

func apply_bone_pose_offsets() -> void:
	var skeleton: Skeleton3D = _character_skeleton
	if skeleton == null or not is_instance_valid(skeleton):
		return
	if _bone_pose_position_offsets.is_empty() or _is_ragdoll_active:
		if not is_zero_approx(_visual_foot_anchor_correction_y):
			var reset_visual_root := get_visual_root()
			_apply_visual_foot_anchor_correction(reset_visual_root, 0.0)
		return
	var visual_root := get_visual_root()
	for bone_name in _bone_pose_position_offsets.keys():
		var bone_index := skeleton.find_bone(str(bone_name))
		if bone_index < 0:
			continue
		var offset: Vector3 = _bone_pose_position_offsets[bone_name]
		var rest_position := skeleton.get_bone_rest(bone_index).origin
		skeleton.set_bone_pose_position(bone_index, rest_position + offset)
	skeleton.force_update_all_bone_transforms()
	var desired_correction := 0.0
	if appearance_data != null and appearance_data.has_method("get_foot_anchor_correction_y") and visual_root != null:
		desired_correction = float(appearance_data.get_foot_anchor_correction_y()) * visual_root.scale.y
	_apply_visual_foot_anchor_correction(visual_root, desired_correction)


func _apply_visual_foot_anchor_correction(visual_root: Node3D, desired_correction: float) -> void:
	if visual_root == null or not is_instance_valid(visual_root):
		return
	visual_root.position.y += desired_correction - _visual_foot_anchor_correction_y
	_visual_foot_anchor_correction_y = desired_correction


func refresh_foot_ground_alignment() -> void:
	if actor == null or not is_instance_valid(actor) or not _actor.is_inside_tree():
		return
	if _is_ragdoll_active or _character_skeleton == null or not is_instance_valid(_character_skeleton):
		return
	var skeleton: Skeleton3D = _character_skeleton
	var visual_root := get_visual_root()
	if visual_root == null or not visual_root.is_inside_tree() or not skeleton.is_inside_tree():
		return
	skeleton.force_update_all_bone_transforms()
	var foot_y := _get_skeleton_foot_anchor_global_y(skeleton)
	if foot_y == INF:
		return
	var ground_y := get_visual_ground_y()
	var desired_correction := clampf(ground_y - foot_y, -CHARACTER_VISUAL_FOOT_GROUND_CORRECTION_MAX_DOWN, CHARACTER_VISUAL_FOOT_GROUND_CORRECTION_MAX_UP)
	var correction_delta: float = desired_correction - _visual_foot_ground_correction_y
	if absf(correction_delta) <= 0.001:
		return
	visual_root.position.y += correction_delta
	_visual_foot_ground_correction_y = desired_correction
	skeleton.force_update_all_bone_transforms()


func _get_skeleton_foot_anchor_global_y(skeleton: Skeleton3D) -> float:
	if skeleton == null or not is_instance_valid(skeleton) or not skeleton.is_inside_tree():
		return INF
	var result := INF
	for bone_name in ["foot_l", "foot_r", "ball_l", "ball_r"]:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var bone_global_position := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
		result = minf(result, bone_global_position.y)
	return result


func get_visual_foot_anchor_y() -> float:
	var skeleton: Skeleton3D = _character_skeleton
	if skeleton == null or not is_instance_valid(skeleton) or not skeleton.is_inside_tree():
		return INF
	skeleton.force_update_all_bone_transforms()
	return _get_skeleton_foot_anchor_global_y(skeleton)


func get_visual_ground_y() -> float:
	if actor == null or not is_instance_valid(actor) or not _actor.is_inside_tree():
		return 0.0
	var fallback_y := 0.0
	var body_mesh := _actor.get_node_or_null("BodyMesh") as MeshInstance3D
	if body_mesh != null:
		var body_bounds: AABB = _calculate_local_mesh_bounds(body_mesh)
		fallback_y = body_bounds.position.y
	var local_ground_y: float = _get_visual_ground_y(fallback_y) + CHARACTER_VISUAL_FOOT_CLEARANCE
	return (_actor.global_transform * Vector3(0.0, local_ground_y, 0.0)).y
