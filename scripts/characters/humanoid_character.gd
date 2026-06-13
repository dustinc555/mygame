extends "res://scripts/actors/world_actor.gd"

class_name HumanoidCharacter

const WORLD_TEXT_NOTICE_SCENE = preload("res://scenes/world/effects/world_text_notice.tscn")
const COMBAT_ANIMATION_SET_SCRIPT = preload("res://scripts/characters/combat_animation_set.gd")
const COMBAT_ATTACK_ANIMATION_SCRIPT = preload("res://scripts/characters/combat_attack_animation.gd")
const HUMANOID_RAGDOLL_PROFILE_SCRIPT = preload("res://scripts/characters/humanoid_ragdoll_profile.gd")
const STABLE_PHYSICAL_BONE_SCRIPT = preload("res://scripts/characters/stable_physical_bone.gd")
const NEEDS_CAPABILITY_SCRIPT = preload("res://scripts/actors/capabilities/needs_capability.gd")
const HUMAN_RACE = preload("res://resources/character_races/human.tres")
const HUMAN_MALE_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/human_female.tres")
const CHARACTER_APPEARANCE_DATA_SCRIPT = preload("res://scripts/character_appearance/character_appearance_data.gd")
const SKIN_TEXTURE_BUILDER = preload("res://scripts/character_appearance/skin_texture_builder.gd")
const DEFAULT_MALE_EYEBROW_STYLE = preload("res://resources/character_appearance/eyebrows_regular.tres")
const DEFAULT_FEMALE_EYEBROW_STYLE = preload("res://resources/character_appearance/eyebrows_female.tres")
const APPEARANCE_VISUAL_BODY_TYPE_AUTO := 0
const MALE_VISUAL_SCENE = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Male_FullBody.gltf")
const FEMALE_VISUAL_SCENE = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Female_FullBody.gltf")
const UAL1_ANIMATION_SOURCE_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb")
const UAL2_ANIMATION_SOURCE_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_2/UAL2.glb")
const DEFAULT_GRIP_SOCKET_PROFILE = preload("res://resources/humanoid_grip_socket_profiles/default.tres")
const DEFAULT_CARRY_POSE_PROFILE = preload("res://resources/humanoid_carry_pose_profiles/default.tres")
const HUMANOID_GRIP_SOCKET_MARKER_SCRIPT = preload("res://scripts/characters/humanoid_grip_socket_marker.gd")
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
const CELL_CUSTODY_LAY_ANIMATION_NAME := "IdleToLay"
const CELL_CUSTODY_WAKE_ANIMATION_NAME := "LayToIdle"
const CELL_CUSTODY_ANIMATION_NAMES: Array[String] = ["IdleToLay", "LayToIdle"]
const CELL_CUSTODY_LAY_FREEZE_RATIO := 0.6
const CELL_CUSTODY_WAKE_START_RATIO := 0.25
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
const COMBAT_ACTION_BLEND_SECONDS := 0.05
const DEFAULT_COMBAT_ACTION_SECONDS := 0.45
const DEFAULT_COMBAT_IMPACT_RATIO := 0.45
const COMBAT_RANGE_HYSTERESIS := 0.18
const CELL_PLACEMENT_INTERACT_DISTANCE := 2.4
const ACTUAL_LOCOMOTION_SPEED_THRESHOLD := 0.18
const RAGDOLL_IMPULSE_MEMORY_SECONDS := 4.0
const RAGDOLL_COLLIDER_LENGTH_SCALE := 0.82
const RAGDOLL_MAX_LINEAR_SPEED := 10.0
const RAGDOLL_MAX_ANGULAR_SPEED := 18.0
const RAGDOLL_UPWARD_VELOCITY_SUPPRESSION_FRAMES := 90
const GROUND_MARKER_RAYCAST_UP := 0.35
const GROUND_MARKER_RAYCAST_DOWN := 24.0
const SELECTION_GROUND_MARKER_HEIGHT := 0.02
const UPRIGHT_SELECTION_GROUND_MARKER_HEIGHT := 0.34
const ACTIVE_AI_DECISION_INTERVAL := 0.35
const ACTIVE_AI_DECISION_JITTER := 0.15
const BACKGROUND_AI_DECISION_INTERVAL := 1.25
const BACKGROUND_AI_DECISION_JITTER := 0.45
const FAR_BACKGROUND_AI_DECISION_INTERVAL := 3.0
const FAR_BACKGROUND_AI_DECISION_JITTER := 1.0
const FAR_BACKGROUND_AI_DECISION_DISTANCE := 28.0
const FAR_RUNTIME_CADENCE_DISTANCE := 90.0
const FAR_RUNTIME_PROCESS_INTERVAL := 3.0
const FAR_RUNTIME_PHYSICS_INTERVAL := 3.0
const NEEDS_PROCESS_INTERVAL := 0.25
const NEEDS_PROCESS_JITTER := 0.08
const HUMANOID_PROFILE_SAMPLE_CALLS := 12000
const RUNNING_SKILL_XP_PER_SECOND := 0.35
const RUNNING_ENDURANCE_XP_PER_SECOND := 0.05
const CARRY_STRENGTH_XP_PER_SECOND := 0.1
const SNEAK_MOVE_SPEED_MIN_MULTIPLIER := 0.45
const SNEAK_MOVE_SPEED_MAX_MULTIPLIER := 1.45
const SNEAK_MOVE_SPEED_MASTER_LEVEL := 80.0
const SNEAK_MOVE_SPEED_CURVE := 0.75
const MINING_ORE_WORTH_FOR_FIRST_LEVEL := 4.0
const MINING_STRENGTH_XP_FACTOR := 0.08
const SCAVENGING_ATTEMPTS_FOR_FIRST_LEVEL := 4.0
const COMBAT_ATTACK_SKILL_XP := 0.85
const TOUGHNESS_DAMAGE_XP_MULTIPLIER := 0.18
const MEDICAL_BANDAGE_XP := 3.0
const CINDER_FLASK_TOOL_TAG := "tool.cinder_flask"
const AUTO_BURN_TARGET_RESERVED_BY_META := "auto_burn_reserved_by_instance_id"
const AUTO_BURN_TARGET_RESERVED_UNTIL_META := "auto_burn_reserved_until_msec"
const DOWNED_INTERACTION_DISTANCE := 3.0
const DOWNED_INTERACTION_MOVE_OFFSET := 1.25
const DOWNED_INTERACTION_VERTICAL_TOLERANCE := 1.6
const DOWNED_INTERACTION_UNREACHABLE_EXTRA := 0.65
const PICKUP_GRAB_EXTRA_DISTANCE := 0.1
const PICKUP_UNREACHABLE_EXTRA_DISTANCE := 0.25
const PICKUP_ROUTE_ARRIVAL_DISTANCE := 0.25
const MAX_COMBAT_TARGET_CANDIDATES := 16
const MAX_COMBAT_QUERY_CANDIDATES := 32
const MAX_COMBAT_SUPPORT_TARGETS := 6
const MAX_COMBAT_ASSIST_NOTIFY_RECIPIENTS := 12
const COMBAT_INTERVENTION_STAFF_GROUP := "combat_intervention_staff"
const SETTLEMENT_AUTHORITY_GROUP := "settlement_authority"
const PRIVATE_SECURITY_GROUP := "private_security"
const FACTION_SOLDIER_GROUP := "faction_soldier"
const EQUIPMENT_SLOTS: Array[String] = ["undershirt", "hands", "chest", "legs", "feet", "backpack", "head", "weapon", "offhand"]
const EQUIPMENT_SLOT_LABELS := {
	"undershirt": "Undershirt",
	"hands": "Hands",
	"head": "Head",
	"chest": "Chest",
	"backpack": "Backpack",
	"legs": "Legs",
	"feet": "Feet",
	"weapon": "Weapon",
	"offhand": "Offhand",
}
const CLOTHING_EQUIPMENT_SLOTS := ["undershirt", "hands", "chest", "legs", "feet", "backpack", "head"]
const APPEARANCE_HEAD_ATTACHMENT_PREFIX := "Appearance"
const BONE_EQUIPMENT_SLOTS := {
	"weapon": "hand_r",
	"offhand": "hand_l",
}
# Opt-in section timing for humanoid `_process`. Use with the demo benchmark as
# `--humanoid-profile` when chasing per-frame character regressions.
static var _debug_humanoid_profile_enabled := OS.get_cmdline_args().has("--humanoid-profile")
static var _debug_humanoid_profile_calls := 0
static var _debug_humanoid_profile_totals: Dictionary = {}
static var _debug_humanoid_ai_profile_calls := 0
static var _debug_humanoid_ai_profile_totals: Dictionary = {}
static var _runtime_focus_cache_frame_key := -1
static var _runtime_focus_cache_tree_id := 0
static var _runtime_focus_cache_positions: Array[Vector3] = []

enum OrderType {
	NONE,
	MOVE,
	MINE,
	SCAVENGE,
	OPEN_CONTAINER,
	TRADE,
	TALK,
	ATTACK,
	HEAL,
	FINISH_OFF,
	CARRY,
	SLEEP,
	PLACE_IN_BED,
	PLACE_IN_CELL,
	PLACE_IN_FURNACE,
	SIT,
	PICKUP_ITEM,
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

@export var seated_player_talk_distance_multiplier := 2.0
@export var overhead_text_height := 2.4
@export var show_nameplate := true
@export var character_race: Resource = HUMAN_RACE
@export var body_archetype: Resource
@export_enum("Auto", "None", "Male", "Female") var visual_body_type: int = VisualBodyType.AUTO
@export var appearance_data: Resource
@export var grip_socket_profile: Resource
@export var carry_pose_profile: Resource = DEFAULT_CARRY_POSE_PROFILE
@export var ragdoll_profile: Resource
@export var show_grip_socket_markers := false

@export var trade_interaction_distance := 3.0
@export var carry_move_speed_multiplier := 0.6
@export var auto_burn_target_scan_radius := 18.0
@export var auto_burn_furnace_access_radius := 42.0
@export var auto_burn_no_resource_backoff_seconds := 14.0
@export var auto_burn_no_target_backoff_seconds := 2.5
@export var auto_burn_failed_backoff_seconds := 5.0

var is_inspected := false
var is_selected := false
var is_focused := false
var _current_mining_node
var _mining_progress_by_node: Dictionary = {}
var _mining_active := false
var _current_scavenging_node
var _scavenging_progress_by_node: Dictionary = {}
var _scavenging_active := false
var _current_container_target
var _current_trade_target
var _current_conversation_target
var _current_attack_target: Node3D
var _attack_origin_position := Vector3.ZERO
var _current_heal_target: HumanoidCharacter
var _current_finish_off_target: HumanoidCharacter
var _current_carry_target: HumanoidCharacter
var _current_sleep_target
var _current_place_bed_target
var _current_place_cell_target
var _current_place_cell_waypoints: Array[Vector3] = []
var _current_place_furnace_target
var _current_seat_target
var _current_pickup_item
var _current_seat_stand_position: Variant = null
var _carried_by: HumanoidCharacter
var _carried_character: HumanoidCharacter
var _cell_custody_target
var _carried_pose_animation := ""
var _cell_custody_unconscious_pose_animation := ""
var _cell_custody_lay_freeze_remaining := 0.0
var _cell_custody_lay_pose_frozen := false
var _cell_custody_wake_animation := ""
var _cell_custody_wake_remaining := 0.0

var _bleed_drip_progress := 0.0
var _bleed_pool_progress := 0.0
var _pending_nourishment := 0.0
var _combat_slot_role_cache_frame := -1
var _combat_slot_role_cache_target_id := 0
var _combat_slot_role_cache := COMBAT_COORDINATOR.SLOT_ROLE_NONE
var _dying_timer_remaining := 0.0
var _ai_tick_remaining := 0.0
var _downed_recover_delay_remaining := 0.0
var _downed_is_settled := false
var _is_getting_up := false
var _get_up_animation_name := ""
var _get_up_animation_remaining := 0.0
var _get_up_animation_total := 0.0
var _ragdoll_preroll_active := false
var _ragdoll_preroll_is_dead := false
var _ragdoll_preroll_animation_name := ""
var _ragdoll_preroll_remaining := 0.0
var _default_ragdoll_profile: Resource
var _ragdoll_simulator: PhysicalBoneSimulator3D
var _ragdoll_skeleton: Skeleton3D
var _ragdoll_physical_bones: Dictionary = {}
var _is_ragdoll_active := false
var _last_ragdoll_impulse := Vector3.ZERO
var _last_ragdoll_impulse_remaining := 0.0
var _ragdoll_upward_velocity_suppression_frames := 0
var _stored_collision_shape: Shape3D
var _stored_collision_transform := Transform3D.IDENTITY
var _stored_collision_disabled := false
var _downed_collision_applied := false
var _stored_navigation_avoidance_enabled := true
var _stored_collision_layer := 1
var _stored_collision_mask := 1

var _combat_reputation_recorded: Dictionary = {}
var _combat_animation_sets: Dictionary = {}

var _nameplate: Label3D
var _inspect_ring: MeshInstance3D
var _far_runtime_process_accumulated := 0.0
var _far_runtime_physics_accumulated := 0.0
var _rng := RandomNumberGenerator.new()
var _is_sitting := false
var _preview_clothes_visible := true
var _selection_ring: Node3D
var _body: BodyProjection = null
var _combat_capability: CombatCapability
var _ai_targeting_capability
var _interaction_capability
var _stat_value_cache_frame := -1
var _stat_value_cache: Dictionary = {}
var _bleed_splotch_controller: Node
var _auto_burn_next_scan_msec := 0
var _auto_burn_cached_furnace
var _auto_burn_cached_furnace_until_msec := 0
var _auto_burn_reserved_target: HumanoidCharacter
var _auto_burn_reserved_furnace
var _spawn_grounding_refresh_frames := 0

signal mining_changed
signal scavenging_changed
signal appearance_changed
signal container_reached(member, container)
signal trade_target_reached(member, target)
signal conversation_target_reached(member, target)


func _enter_tree() -> void:
	super._enter_tree()


func _ready() -> void:
	super._ready()
	_combat_capability = get_actor_capability(&"combat") as CombatCapability
	_ai_targeting_capability = get_actor_capability(&"ai_targeting")
	_interaction_capability = get_actor_capability(&"interaction")
	_rng.randomize()
	_far_runtime_process_accumulated = _rng.randf_range(0.0, FAR_RUNTIME_PROCESS_INTERVAL)
	_far_runtime_physics_accumulated = _rng.randf_range(0.0, FAR_RUNTIME_PHYSICS_INTERVAL)
	_seed_needs_capability_tick()
	_setup_body_projection()
	_ensure_appearance_data()
	_setup_nameplate()
	_setup_inspect_ring()
	_selection_ring = get_node_or_null("SelectionRing") as Node3D
	_setup_character_visual()
	add_to_group("humanoid_character")
	add_to_group("npc_character")
	add_to_group(COMBAT_COORDINATOR.COMBAT_ACTOR_GROUP)
	_sync_party_membership_group()
	hunger = clampf(hunger, 0.0, 100.0)
	fatigue = clampf(fatigue, 0.0, 100.0)
	_recalculate_vitals()


func _exit_tree() -> void:
	COMBAT_COORDINATOR.release_character(self)
	remove_from_group(ACTIVE_COMBAT_ACTOR_GROUP)
	super._exit_tree()
	_combat_capability = null
	_ai_targeting_capability = null
	_interaction_capability = null


# Creates the actor's visual body adapter (BodyProjection). Visual code is migrated
# behind this seam in increments; see scripts/projection/. Subclasses override
# _create_body_projection() to pick their species body.
func _setup_body_projection() -> void:
	if _body != null and is_instance_valid(_body):
		return
	_body = _create_body_projection()
	if _body == null:
		return
	_body.name = "BodyProjection"
	add_child(_body)
	_body.bind_actor(self)


func _create_body_projection() -> BodyProjection:
	return HumanoidBodyProjection.new()


func get_body_projection() -> BodyProjection:
	return _body if _body != null and is_instance_valid(_body) else null


func _create_actor_capabilities() -> Array:
	var capabilities := super._create_actor_capabilities()
	var needs_capability = NEEDS_CAPABILITY_SCRIPT.new()
	needs_capability.configure(NEEDS_PROCESS_INTERVAL, NEEDS_PROCESS_JITTER)
	capabilities.append(needs_capability)
	return capabilities


func _process(delta: float) -> void:
	if _should_use_far_runtime_cadence():
		_far_runtime_process_accumulated += delta
		if _far_runtime_process_accumulated < FAR_RUNTIME_PROCESS_INTERVAL:
			return
		delta = _far_runtime_process_accumulated
		_far_runtime_process_accumulated = 0.0
	else:
		_far_runtime_process_accumulated = 0.0
	_process_actor_capabilities(delta)
	if _debug_humanoid_profile_enabled:
		_process_profiled(delta)
		return
	if _carried_by != null:
		_update_carried_pose_animation()
		if _body != null:
			_body.apply_bone_pose_offsets()
		_update_carried_transform()
		_update_ground_markers()
		return
	if is_in_cell_custody():
		_process_combat_cooldown(delta)
		_process_needs_capability(delta)
		_recalculate_vitals()
		_update_cell_custody_animation(delta)
		if _body != null:
			_body.apply_bone_pose_offsets()
		_update_ground_markers()
		return
	_process_combat_cooldown(delta)
	_process_ragdoll_impulse_memory(delta)
	_process_needs_capability(delta)
	_process_ai(delta)
	_recalculate_vitals()
	_process_downed_animation_state(delta)
	_process_combat_animation_state(delta)
	_update_character_animation(delta)
	if _body != null:
		_body.apply_bone_pose_offsets()
	_update_ground_markers()


func _process_profiled(delta: float) -> void:
	var profile_last_usec := Time.get_ticks_usec()
	if _carried_by != null:
		_update_carried_pose_animation()
		profile_last_usec = _debug_humanoid_profile_checkpoint("carried_animation", profile_last_usec)
		if _body != null:
			_body.apply_bone_pose_offsets()
		profile_last_usec = _debug_humanoid_profile_checkpoint("bone_offsets", profile_last_usec)
		_update_carried_transform()
		profile_last_usec = _debug_humanoid_profile_checkpoint("carried_transform", profile_last_usec)
		_update_ground_markers()
		_debug_humanoid_profile_checkpoint("ground_markers", profile_last_usec)
		_debug_humanoid_profile_finish()
		return
	if is_in_cell_custody():
		_process_combat_cooldown(delta)
		profile_last_usec = _debug_humanoid_profile_checkpoint("timers", profile_last_usec)
		_process_needs_capability(delta)
		profile_last_usec = _debug_humanoid_profile_checkpoint("needs_capability", profile_last_usec)
		_recalculate_vitals()
		profile_last_usec = _debug_humanoid_profile_checkpoint("vitals", profile_last_usec)
		_update_cell_custody_animation(delta)
		profile_last_usec = _debug_humanoid_profile_checkpoint("cell_animation", profile_last_usec)
		if _body != null:
			_body.apply_bone_pose_offsets()
		profile_last_usec = _debug_humanoid_profile_checkpoint("bone_offsets", profile_last_usec)
		_update_ground_markers()
		_debug_humanoid_profile_checkpoint("ground_markers", profile_last_usec)
		_debug_humanoid_profile_finish()
		return
	_process_combat_cooldown(delta)
	_process_ragdoll_impulse_memory(delta)
	profile_last_usec = _debug_humanoid_profile_checkpoint("timers", profile_last_usec)
	_process_needs_capability(delta)
	profile_last_usec = _debug_humanoid_profile_checkpoint("needs_capability", profile_last_usec)
	_process_ai_profiled(delta)
	profile_last_usec = _debug_humanoid_profile_checkpoint("ai", profile_last_usec)
	_recalculate_vitals()
	profile_last_usec = _debug_humanoid_profile_checkpoint("vitals", profile_last_usec)
	_process_downed_animation_state(delta)
	profile_last_usec = _debug_humanoid_profile_checkpoint("downed_animation", profile_last_usec)
	_process_combat_animation_state(delta)
	profile_last_usec = _debug_humanoid_profile_checkpoint("combat_animation", profile_last_usec)
	_update_character_animation(delta)
	profile_last_usec = _debug_humanoid_profile_checkpoint("character_animation", profile_last_usec)
	if _body != null:
		_body.apply_bone_pose_offsets()
	profile_last_usec = _debug_humanoid_profile_checkpoint("bone_offsets", profile_last_usec)
	_update_ground_markers()
	_debug_humanoid_profile_checkpoint("ground_markers", profile_last_usec)
	_debug_humanoid_profile_finish()


static func _debug_humanoid_profile_checkpoint(section_name: String, previous_usec: int) -> int:
	var now_usec := Time.get_ticks_usec()
	_debug_humanoid_profile_totals[section_name] = int(_debug_humanoid_profile_totals.get(section_name, 0)) + now_usec - previous_usec
	return now_usec


static func _debug_humanoid_profile_finish() -> void:
	_debug_humanoid_profile_calls += 1
	if _debug_humanoid_profile_calls < HUMANOID_PROFILE_SAMPLE_CALLS:
		return
	var rows: Array = []
	for section_name in _debug_humanoid_profile_totals.keys():
		rows.append([section_name, int(_debug_humanoid_profile_totals[section_name])])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for row in rows:
		print("HUMANOID_PROFILE %s usec=%d avg_per_process=%.3f" % [str(row[0]), int(row[1]), float(row[1]) / float(_debug_humanoid_profile_calls)])
	_debug_humanoid_profile_enabled = false


static func _debug_humanoid_ai_profile_checkpoint(section_name: String, previous_usec: int) -> int:
	var now_usec := Time.get_ticks_usec()
	_debug_humanoid_ai_profile_totals[section_name] = int(_debug_humanoid_ai_profile_totals.get(section_name, 0)) + now_usec - previous_usec
	return now_usec


static func _debug_humanoid_ai_profile_finish() -> void:
	_debug_humanoid_ai_profile_calls += 1
	if _debug_humanoid_ai_profile_calls < HUMANOID_PROFILE_SAMPLE_CALLS:
		return
	var rows: Array = []
	for section_name in _debug_humanoid_ai_profile_totals.keys():
		rows.append([section_name, int(_debug_humanoid_ai_profile_totals[section_name])])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for row in rows:
		print("HUMANOID_AI_PROFILE %s usec=%d avg_per_ai_process=%.3f" % [str(row[0]), int(row[1]), float(row[1]) / float(_debug_humanoid_ai_profile_calls)])


func _physics_process(delta: float) -> void:
	if _spawn_grounding_refresh_frames > 0:
		_process_spawn_grounding_refresh(delta)
		return
	if _should_use_far_runtime_cadence():
		_far_runtime_physics_accumulated += delta
		if _far_runtime_physics_accumulated < FAR_RUNTIME_PHYSICS_INTERVAL:
			return
		delta = _far_runtime_physics_accumulated
		_far_runtime_physics_accumulated = 0.0
	else:
		_far_runtime_physics_accumulated = 0.0
	_physics_process_actor_capabilities(delta)
	if _carried_by != null:
		velocity = Vector3.ZERO
		return
	if is_in_cell_custody():
		velocity = Vector3.ZERO
		return
	if _is_ragdoll_active:
		_stabilize_active_ragdoll(delta)
		_update_ground_markers()
	if life_state != NpcRules.LifeState.ALIVE and _downed_is_settled and is_on_floor():
		velocity = Vector3.ZERO
		return
	_process_movement(delta)
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if _has_active_combat_target():
		_process_attack_interaction()
		return
	match _current_order_type:
		OrderType.MINE:
			_process_mining(delta)
		OrderType.SCAVENGE:
			_process_scavenging(delta)
		OrderType.OPEN_CONTAINER:
			_process_container_interaction()
		OrderType.TRADE:
			_process_trade_interaction()
		OrderType.TALK:
			_process_conversation_interaction()
		OrderType.ATTACK:
			_process_attack_interaction()
		OrderType.HEAL:
			_process_heal_interaction()
		OrderType.FINISH_OFF:
			_process_finish_off_interaction()
		OrderType.CARRY:
			_process_carry_interaction()
		OrderType.SLEEP:
			_process_sleep_interaction()
		OrderType.PLACE_IN_BED:
			_process_place_in_bed_interaction()
		OrderType.PLACE_IN_CELL:
			_process_place_in_cell_interaction()
		OrderType.PLACE_IN_FURNACE:
			_process_place_in_furnace_interaction()
		OrderType.SIT:
			_process_seat_interaction()
		OrderType.PICKUP_ITEM:
			_process_pickup_interaction()
	if _should_face_combat_focus_after_movement():
		_face_combat_focus()


func set_move_target(target: Vector3, issued_by_player: bool = true) -> void:
	if is_in_cell_custody():
		if issued_by_player:
			center_notice_requested.emit("Locked in cell")
			_show_world_notice("Locked in cell", Color(1.0, 0.78, 0.38, 1.0))
		return
	if not _set_order(OrderType.MOVE, issued_by_player):
		return
	_set_actor_move_target(target)


func request_spawn_grounding_refresh(frame_count: int = 8) -> void:
	_spawn_grounding_refresh_frames = maxi(_spawn_grounding_refresh_frames, frame_count)
	call_deferred("_apply_deferred_spawn_visual_grounding")


func _process_spawn_grounding_refresh(delta: float) -> void:
	_spawn_grounding_refresh_frames -= 1
	if life_state == NpcRules.LifeState.ALIVE and _carried_by == null and not _is_sitting and not is_in_cell_custody() and not _is_ragdoll_active:
		_apply_floor_motion(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		apply_floor_snap()
	velocity = Vector3.ZERO
	_apply_deferred_spawn_visual_grounding()


func _apply_deferred_spawn_visual_grounding() -> void:
	if not is_inside_tree():
		return
	if _body != null:
		_body.apply_bone_pose_offsets()
		_body.refresh_foot_ground_alignment()
	_update_ground_markers()


func stop_mining_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_mining_assignment()


func stop_scavenging_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_scavenging_assignment()


func stop_container_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_container_interaction()


func stop_trade_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_trade_interaction()


func stop_conversation_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_conversation_interaction()


func stop_attack_assignment() -> void:
	_current_attack_target = null
	_attack_origin_position = global_position
	_clear_combat_movement_state()
	if _ai_brain != null:
		_ai_brain.clear_combat_job()
	COMBAT_COORDINATOR.release_character(self)
	if _current_order_type == OrderType.ATTACK:
		_current_order_type = OrderType.NONE
	_sync_active_combat_actor_group()
	combat_state_changed.emit()


func stop_heal_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_heal_assignment()


func stop_finish_off_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_finish_off_assignment()


func stop_carry_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_carry_assignment()


func stop_sleep_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_sleep_assignment()


func stop_place_in_bed_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_place_in_bed_assignment()


func stop_place_in_cell_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_place_in_cell_assignment()


func stop_place_in_furnace_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_place_in_furnace_assignment()


func _release_sleep_target_without_waking() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.release_sleep_target_without_waking()


func stop_seat_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_seat_assignment()


func stop_pickup_assignment() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.stop_pickup_assignment()


func assign_open_container(container, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_open_container(container, issued_by_player)


func assign_trade_target(target_character, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_trade_target(target_character, issued_by_player)


func assign_conversation_target(target_character, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_conversation_target(target_character, issued_by_player)


func assign_mining_resource(resource_node, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_mining_resource(resource_node, issued_by_player)


func assign_scavenging_resource(resource_node, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_scavenging_resource(resource_node, issued_by_player)


func assign_attack_target(target_actor: Node, issued_by_player: bool = true, notify_target: bool = true, notify_allies: bool = true) -> bool:
	var target_character := target_actor as Node3D
	if target_character == null:
		return false
	var combat_job_type := AI_JOB_SCRIPT.JobType.PLAYER_ATTACK if issued_by_player else AI_JOB_SCRIPT.JobType.SELF_DEFENSE
	return _assign_combat_target(target_character, combat_job_type, issued_by_player, notify_target, notify_allies)


func assign_law_arrest_target(target_character: HumanoidCharacter, notify_target: bool = true, notify_allies: bool = false) -> bool:
	return _assign_combat_target(target_character, AI_JOB_SCRIPT.JobType.LAW_ARREST, false, notify_target, notify_allies)


# TODO(actor-decoupling): generic combat assignment still lives in HumanoidCharacter; move this routing to CombatCapability/WorldActor.
func _assign_combat_target(target_character: Node3D, combat_job_type: int, issued_by_player: bool, notify_target: bool, notify_allies: bool) -> bool:
	if is_in_cell_custody():
		return false
	if target_character == null or target_character == self or not is_instance_valid(target_character):
		return false
	if life_state != NpcRules.LifeState.ALIVE:
		return false
	if not _is_valid_combat_target(target_character):
		return false
	if not can_see_actor_for_combat(target_character):
		return false
	if issued_by_player and target_character is HumanoidCharacter:
		_report_assault_crime_if_needed(target_character as HumanoidCharacter)
	_break_stealth_for_combat()
	if _get_active_combat_target() == target_character and _get_active_ai_job_type() == combat_job_type:
		return true
	var combat_job = AI_JOB_SCRIPT.new()
	combat_job.job_type = combat_job_type
	combat_job.priority = AI_JOB_SCRIPT.priority_for_type(combat_job_type)
	combat_job.target = target_character
	combat_job.issued_by_player = issued_by_player
	combat_job.origin_position = global_position
	if _ai_brain != null:
		_ai_brain.request_job(combat_job)
	if issued_by_player:
		if not _set_order(OrderType.ATTACK, issued_by_player):
			if _ai_brain != null:
				_ai_brain.clear_combat_job(target_character)
			return false
	else:
		_cancel_non_matching_assignments(OrderType.ATTACK, false)
		if _current_order_type == OrderType.MOVE:
			_current_order_type = OrderType.NONE
			_clear_actor_move_target()
		_current_order_type = OrderType.ATTACK
		_order_was_player_issued = false
	_current_attack_target = target_character
	_attack_origin_position = global_position
	_clear_combat_movement_state()
	_clear_non_combat_ai_job_for_combat()
	COMBAT_COORDINATOR.register_combat_target(self, target_character)
	_sync_active_combat_actor_group()
	mark_hostile(target_character)
	if target_character.has_method("mark_hostile"):
		target_character.call("mark_hostile", self)
	if notify_target and target_character.has_method("notify_incoming_attack"):
		target_character.call("notify_incoming_attack", self)
	if notify_allies:
		_notify_defensive_allies_of_engagement(target_character)
	combat_state_changed.emit()
	return true


func _clear_non_combat_ai_job_for_combat() -> void:
	if _ai_brain == null or _ai_brain.active_job == null:
		return
	if _ai_brain.active_job.is_combat():
		return
	_ai_brain.clear_active_job()


func assign_heal_target(target_character: HumanoidCharacter, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_heal_target(target_character, issued_by_player)


func assign_finish_off_target(target_character: HumanoidCharacter, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_finish_off_target(target_character, issued_by_player)


func assign_carry_target(target_character: HumanoidCharacter, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_carry_target(target_character, issued_by_player)


func assign_sleep_target(bed, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_sleep_target(bed, issued_by_player)


func assign_place_carried_in_bed_target(bed, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_place_carried_in_bed_target(bed, issued_by_player)


func assign_place_carried_in_cell_target(cell, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_place_carried_in_cell_target(cell, issued_by_player)


func assign_place_carried_in_furnace_target(furnace, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_place_carried_in_furnace_target(furnace, issued_by_player)


func assign_seat_target(seat, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_seat_target(seat, issued_by_player)


func sit_at_seat_immediately(seat) -> bool:
	var interaction = _get_interaction_capability()
	return interaction.sit_at_seat_immediately(seat) if interaction != null else false


func assign_pickup_item(world_item, issued_by_player: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_pickup_item(world_item, issued_by_player)


func wake_up_from_rest(show_notice: bool = true) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.wake_up_from_rest(show_notice)


func is_sitting() -> bool:
	return _is_sitting


func get_current_seat_target():
	return _current_seat_target if _current_seat_target != null and is_instance_valid(_current_seat_target) else null


func get_floor_aligned_origin_position(floor_position: Vector3) -> Vector3:
	return Vector3(floor_position.x, floor_position.y - get_collision_bottom_local_y(), floor_position.z)


func get_collision_bottom_local_y() -> float:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return 0.0
	var shape_bounds := _get_collision_shape_local_bounds(collision_shape)
	return shape_bounds.position.y if shape_bounds.size.y > 0.001 else 0.0


func has_mining_assignment() -> bool:
	var interaction = _get_interaction_capability()
	return interaction.has_mining_assignment() if interaction != null else _current_mining_node != null


func get_assigned_mining_node():
	var interaction = _get_interaction_capability()
	return interaction.get_assigned_mining_node() if interaction != null else _current_mining_node


func is_actively_mining() -> bool:
	var interaction = _get_interaction_capability()
	return interaction.is_actively_mining() if interaction != null else _mining_active


func get_mining_progress_ratio() -> float:
	var interaction = _get_interaction_capability()
	return interaction.get_mining_progress_ratio() if interaction != null else 0.0


func has_scavenging_assignment() -> bool:
	var interaction = _get_interaction_capability()
	return interaction.has_scavenging_assignment() if interaction != null else _current_scavenging_node != null


func get_assigned_scavenging_node():
	var interaction = _get_interaction_capability()
	return interaction.get_assigned_scavenging_node() if interaction != null else _current_scavenging_node


func is_actively_scavenging() -> bool:
	var interaction = _get_interaction_capability()
	return interaction.is_actively_scavenging() if interaction != null else _scavenging_active


func get_scavenging_progress_ratio() -> float:
	var interaction = _get_interaction_capability()
	return interaction.get_scavenging_progress_ratio() if interaction != null else 0.0


func can_eat_item(definition: ItemDefinition) -> bool:
	return definition != null and definition.nutrition_value > 0.0 and hunger_enabled


func eat_item(definition: ItemDefinition) -> bool:
	if not can_eat_item(definition):
		return false
	if not inventory.remove_item_count(definition, 1):
		return false
	_pending_nourishment += definition.nutrition_value
	return true


func get_equipment_slot_names() -> Array[String]:
	var race := _get_character_race()
	if race != null and race.has_method("get_equipment_slots"):
		var race_slots: Array[String] = race.get_equipment_slots()
		if not race_slots.is_empty():
			return race_slots
	return EQUIPMENT_SLOTS.duplicate()


func get_equipment_slot_label(slot_name: String) -> String:
	var race := _get_character_race()
	if race != null and race.has_method("get_slot_label"):
		return race.get_slot_label(slot_name)
	return str(EQUIPMENT_SLOT_LABELS.get(slot_name, slot_name.capitalize()))


func _on_actor_equipment_changed(changed_slots: Array) -> void:
	if _can_refresh_bone_equipment_only(changed_slots):
		_refresh_bone_equipment_slots(changed_slots)
	else:
		_rebuild_character_visual_for_equipment()


func can_eat_inventory_entry(entry) -> bool:
	if entry == null:
		return false
	var display_inventory := get_inventory_for_display()
	return can_eat_item(entry.definition) and display_inventory != null and display_inventory.entries.has(entry)


func consume_inventory_entry(entry) -> bool:
	if not can_eat_inventory_entry(entry):
		return false
	var display_inventory := get_inventory_for_display()
	if not display_inventory.remove_item_count(entry.definition, 1):
		return false
	_pending_nourishment += entry.definition.nutrition_value
	if display_inventory != inventory:
		inventory_changed.emit()
	return true


func is_authorized_for_owner(owner_character: HumanoidCharacter, owner_faction: String = "") -> bool:
	if owner_character != null and owner_character == self:
		return true
	if _active_job_provider == null:
		return owner_character == null and not owner_faction.is_empty() and faction_name == owner_faction
	if not _active_job_provider.has_method("get_provider_character"):
		return false
	var provider_owner: HumanoidCharacter = _active_job_provider.get_provider_character()
	if owner_character != null:
		return provider_owner == owner_character
	return owner_faction == provider_owner.faction_name


func show_world_notice(message: String, color: Color = Color(1.0, 0.28, 0.28, 1.0), lifetime: float = 1.0) -> void:
	_show_world_notice(message, color, lifetime)


func show_world_speech(message: String, lifetime: float = 5.0) -> void:
	_show_world_notice(message, Color(0.94, 0.92, 0.86, 1.0), lifetime, 0.22)


func can_use_bandage_item(definition: ItemDefinition) -> bool:
	return definition != null and definition.bandage_power > 0.0


func requires_fire_to_die() -> bool:
	return false


func can_be_destroyed_by_cinder() -> bool:
	return false


func is_fire_destruction_in_progress() -> bool:
	return false


func begin_cinder_burn(_attacker: HumanoidCharacter = null) -> bool:
	return false


func is_cinder_burned() -> bool:
	return false


func has_cinder_burned_visuals() -> bool:
	return false


func can_use_cinder_flask() -> bool:
	return _find_inventory_tool(CINDER_FLASK_TOOL_TAG) != null


func burn_target_with_cinder_flask(target_character: HumanoidCharacter, show_notices: bool = true) -> bool:
	if target_character == null or not is_instance_valid(target_character):
		return false
	if not target_character.can_be_destroyed_by_cinder():
		if show_notices:
			_show_world_notice("Cannot burn", Color(1.0, 0.66, 0.28, 1.0))
		return false
	var flask_definition := _consume_cinder_flask_definition()
	if flask_definition == null:
		if show_notices:
			show_world_speech("Need a Cinder Flask", 4.0)
		return false
	if not target_character.begin_cinder_burn(self):
		inventory.add_item_count(flask_definition, 1)
		if show_notices:
			_show_world_notice("Cannot burn", Color(1.0, 0.66, 0.28, 1.0))
		return false
	if show_notices:
		_show_world_notice("Burning", Color(1.0, 0.45, 0.12, 1.0))
	return true


func can_bandage_target(target: HumanoidCharacter) -> bool:
	if target == null or not target.can_receive_bandage():
		return false
	for entry in inventory.entries:
		if can_use_bandage_item(entry.definition) and _bandage_entry_has_uses(entry):
			return true
	return false


func shows_inventory_equipment() -> bool:
	return not is_displaying_work_inventory()


func set_inspected(value: bool) -> void:
	is_inspected = value
	_update_inspect_visual()


func get_hunger_stage() -> int:
	return hunger_stage


func get_fatigue_stage() -> int:
	return fatigue_stage


func get_total_wound_damage() -> float:
	return _current_blunt_damage + _current_open_cut_damage + _current_bandaged_cut_damage


func get_open_cut_damage() -> float:
	return _current_open_cut_damage


func get_bandaged_cut_damage() -> float:
	return _current_bandaged_cut_damage


func get_blunt_damage() -> float:
	return _current_blunt_damage


func get_bleed_rate() -> float:
	return _bleed_rate + _bleed_burst_rate


func get_bleed_fluid() -> Resource:
	var race := _get_character_race()
	if race != null and race.get("bleed_fluid") != null:
		return race.get("bleed_fluid") as Resource
	return null


func get_vital_fluid_label() -> String:
	var fluid := get_bleed_fluid()
	if fluid != null:
		var display_name := str(fluid.get("display_name")).strip_edges()
		if not display_name.is_empty():
			return display_name
	return super.get_vital_fluid_label()


func get_vital_fluid_bar_color(fallback_color: Color) -> Color:
	var fluid := get_bleed_fluid()
	if fluid != null and bool(fluid.get("uses_custom_ui_color")):
		var color_value = fluid.get("ui_bar_color")
		if color_value is Color:
			return color_value
	return fallback_color


func get_vital_fluid_glow_color(fallback_color: Color) -> Color:
	var fluid := get_bleed_fluid()
	if fluid != null and bool(fluid.get("uses_custom_ui_color")):
		var color_value = fluid.get("ui_glow_color")
		if color_value is Color:
			return color_value
	return fallback_color


func get_appearance_copy():
	_ensure_appearance_data()
	return appearance_data.make_copy() if appearance_data != null and appearance_data.has_method("make_copy") else CHARACTER_APPEARANCE_DATA_SCRIPT.new()


func get_resolved_visual_body_type() -> int:
	# A2 transitional shim -> BodyProjection.get_resolved_visual_body_type.
	if _body != null:
		return _body.get_resolved_visual_body_type()
	return _resolve_visual_body_type()


func get_resolved_body_archetype() -> Resource:
	# A2 transitional shim -> BodyProjection.get_resolved_body_archetype.
	if _body != null:
		return _body.get_resolved_body_archetype()
	return _resolve_body_archetype()


func apply_appearance_data(next_appearance) -> void:
	if next_appearance == null:
		return
	appearance_data = next_appearance.make_copy()
	if appearance_data.character_race != null:
		character_race = appearance_data.character_race
	if appearance_data.body_archetype != null:
		body_archetype = appearance_data.body_archetype
	visual_body_type = appearance_data.visual_body_type
	_apply_automatic_eyebrow_style()
	_rebuild_character_visual_for_appearance()
	appearance_changed.emit()


func set_preview_clothes_visible(visible_flag: bool) -> void:
	_preview_clothes_visible = visible_flag
	_set_equipped_clothing_visuals_visible(visible_flag)


func get_stance_label() -> String:
	return NpcRules.get_stance_label(combat_stance)


func get_life_state_label() -> String:
	return NpcRules.get_life_state_label(life_state)


func set_settlement_authority(value: bool) -> void:
	if value:
		add_to_group(SETTLEMENT_AUTHORITY_GROUP)
	else:
		remove_from_group(SETTLEMENT_AUTHORITY_GROUP)


func is_settlement_authority() -> bool:
	return is_in_group(SETTLEMENT_AUTHORITY_GROUP)


func set_private_security(value: bool) -> void:
	if value:
		add_to_group(PRIVATE_SECURITY_GROUP)
	else:
		remove_from_group(PRIVATE_SECURITY_GROUP)


func is_private_security() -> bool:
	return is_in_group(PRIVATE_SECURITY_GROUP)


func set_faction_soldier(value: bool) -> void:
	if value:
		add_to_group(FACTION_SOLDIER_GROUP)
	else:
		remove_from_group(FACTION_SOLDIER_GROUP)


func is_faction_soldier() -> bool:
	return is_in_group(FACTION_SOLDIER_GROUP)


func get_hunger_stage_label() -> String:
	return NpcRules.get_hunger_stage_label(get_hunger_stage())


func get_fatigue_stage_label() -> String:
	return NpcRules.get_fatigue_stage_label(get_fatigue_stage())


func _apply_hunger_delta(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var remaining := amount
	while not is_zero_approx(remaining):
		if remaining > 0.0:
			var recoverable := 100.0 - hunger
			var recovery_step := minf(remaining, recoverable)
			hunger += recovery_step
			remaining -= recovery_step
			if hunger >= 100.0 and hunger_stage > NpcRules.HungerStage.WELL_NOURISHED and remaining > 0.0:
				hunger_stage -= 1
				hunger = 0.0
				continue
			break
		var drainable := hunger
		var drain_step := minf(-remaining, drainable)
		hunger -= drain_step
		remaining += drain_step
		if hunger <= 0.0:
			if hunger_stage < NpcRules.HungerStage.STARVING:
				hunger_stage += 1
				hunger = 100.0
				continue
			if life_state != NpcRules.LifeState.DEAD:
				hunger = 0.0
				_enter_dead_state()
			break
		break
	hunger = clampf(hunger, 0.0, 100.0)


func _apply_fatigue_delta(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var remaining := amount
	while not is_zero_approx(remaining):
		if remaining > 0.0:
			var recoverable := 100.0 - fatigue
			var recovery_step := minf(remaining, recoverable)
			fatigue += recovery_step
			remaining -= recovery_step
			if fatigue >= 100.0 and fatigue_stage > NpcRules.FatigueStage.WELL_RESTED and remaining > 0.0:
				fatigue_stage -= 1
				fatigue = 0.0
				continue
			break
		var drainable := fatigue
		var drain_step := minf(-remaining, drainable)
		fatigue -= drain_step
		remaining += drain_step
		if fatigue <= 0.0:
			if fatigue_stage < NpcRules.FatigueStage.EXHAUSTED:
				fatigue_stage += 1
				fatigue = 100.0
				continue
			fatigue = 0.0
			if life_state == NpcRules.LifeState.ALIVE:
				_enter_unconscious_state()
			break
		break
	fatigue = clampf(fatigue, 0.0, 100.0)


func is_running_enabled() -> bool:
	return running and can_continue_running()


func is_auto_heal_enabled() -> bool:
	return auto_heal_enabled and life_state == NpcRules.LifeState.ALIVE


func set_auto_heal_enabled(value: bool) -> void:
	auto_heal_enabled = value
	state_changed.emit()


func is_auto_burn_rustdead_enabled() -> bool:
	return auto_burn_rustdead_enabled and life_state == NpcRules.LifeState.ALIVE


func set_auto_burn_rustdead_enabled(value: bool) -> void:
	auto_burn_rustdead_enabled = value
	_auto_burn_next_scan_msec = 0
	state_changed.emit()


func can_continue_running() -> bool:
	if life_state != NpcRules.LifeState.ALIVE:
		return false
	if fatigue_stage < NpcRules.FatigueStage.EXHAUSTED:
		return true
	return fatigue > NpcRules.FATIGUE_RUN_LOCKOUT_THRESHOLD


func can_enable_running() -> bool:
	return can_continue_running()


func is_in_combat() -> bool:
	return _has_active_combat_target()


func is_law_arresting(target: Node = null) -> bool:
	if _get_active_ai_job_type() != AI_JOB_SCRIPT.JobType.LAW_ARREST:
		return false
	return target == null or _get_active_combat_target() == target


func is_law_custody_returning() -> bool:
	var interaction = _get_interaction_capability()
	return interaction.is_law_custody_returning() if interaction != null else false


func is_law_sentence_moving() -> bool:
	var interaction = _get_interaction_capability()
	return interaction.is_law_sentence_moving() if interaction != null else false


func assign_law_custody_return_target(target_position: Vector3) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_law_custody_return_target(target_position)


func clear_law_custody_return() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.clear_law_custody_return()


func assign_law_sentence_move_target(target_position: Vector3) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.assign_law_sentence_move_target(target_position)


func clear_law_sentence_move() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.clear_law_sentence_move()


func get_current_combat_target() -> Node:
	return _get_active_combat_target()


func is_ready_for_combat_exchange(target: Node) -> bool:
	var target_character := target as Node3D
	if not _is_valid_combat_target(target_character):
		return false
	if _get_active_combat_target() != target_character:
		return false
	if not _is_combat_resolution_ready():
		return false
	if COMBAT_COORDINATOR.is_character_locked(self):
		return false
	return _horizontal_distance_to(target_character.global_position) <= _get_effective_combat_attack_range()


func get_attack_range() -> float:
	return get_stat_value("attack_range")


func _get_current_combat_animation_stance_id() -> String:
	var weapon := get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON)
	if weapon == null:
		return UNARMED_STANCE_ID
	if weapon.grip_profile != null:
		var stance_id := str(weapon.grip_profile.get("animation_stance_id"))
		if not stance_id.is_empty():
			return stance_id
	return EquipmentGripProfile.GRIP_CLASS_ONE_HAND_MELEE


func _is_unarmed_combat_stance() -> bool:
	return _get_current_combat_animation_stance_id() == UNARMED_STANCE_ID


func _get_current_combat_animation_set():
	_ensure_default_combat_animation_sets()
	return _combat_animation_sets.get(_get_current_combat_animation_stance_id(), null)


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
	animation_set.attacks = [
		_make_combat_attack("jab", [UNARMED_JAB_ANIMATION_NAME], 30.0, 0.42, [HIT_HEAD_ANIMATION_NAME, HIT_CHEST_ANIMATION_NAME]),
		_make_combat_attack("cross", [UNARMED_CROSS_ANIMATION_NAME], 24.0, 0.44, [HIT_HEAD_ANIMATION_NAME, HIT_CHEST_ANIMATION_NAME, HIT_SHOULDER_L_ANIMATION_NAME]),
		_make_combat_attack("uppercut", [UNARMED_UPPERCUT_ANIMATION_NAME], 12.0, 0.5, [HIT_HEAD_ANIMATION_NAME]),
		_make_combat_attack("hook", UNARMED_HOOK_ANIMATION_NAMES, 20.0, 0.55, [HIT_HEAD_ANIMATION_NAME, HIT_SHOULDER_L_ANIMATION_NAME, HIT_SHOULDER_R_ANIMATION_NAME]),
		_make_combat_attack("knee", UNARMED_KNEE_ANIMATION_NAMES, 14.0, 0.55, [HIT_STOMACH_ANIMATION_NAME]),
		_make_combat_attack("kick", [UNARMED_KICK_ANIMATION_NAME], 12.0, 0.5, [HIT_HEAD_ANIMATION_NAME]),
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


func _get_ragdoll_profile():
	# A4 transitional shim -> HumanoidBodyProjection.get_ragdoll_profile.
	if _body != null and _body.has_method("get_ragdoll_profile"):
		return _body.call("get_ragdoll_profile")
	if _default_ragdoll_profile == null:
		_default_ragdoll_profile = HUMANOID_RAGDOLL_PROFILE_SCRIPT.new()
	return ragdoll_profile if ragdoll_profile != null else _default_ragdoll_profile


func _get_ragdoll_profile_animation_names() -> Array[String]:
	# A4 transitional shim -> HumanoidBodyProjection.get_ragdoll_profile_animation_names.
	if _body != null and _body.has_method("get_ragdoll_profile_animation_names"):
		return _body.call("get_ragdoll_profile_animation_names")
	return []


func _choose_get_up_animation() -> String:
	# A4 transitional shim -> HumanoidBodyProjection._choose_get_up_animation.
	if _body != null and _body.has_method("_choose_get_up_animation"):
		return str(_body.call("_choose_get_up_animation"))
	return ""


func _choose_downed_preroll_animation() -> String:
	# A4 transitional shim -> HumanoidBodyProjection._choose_downed_preroll_animation.
	if _body != null and _body.has_method("_choose_downed_preroll_animation"):
		return str(_body.call("_choose_downed_preroll_animation"))
	return ""


func _choose_downed_preroll_duration(animation_length: float) -> float:
	# A4 transitional shim -> HumanoidBodyProjection._choose_downed_preroll_duration.
	if _body != null and _body.has_method("_choose_downed_preroll_duration"):
		return float(_body.call("_choose_downed_preroll_duration", animation_length))
	return animation_length


func _get_ragdoll_profile_float(property_name: String, fallback: float) -> float:
	# A4 transitional shim -> HumanoidBodyProjection._get_ragdoll_profile_float.
	if _body != null and _body.has_method("_get_ragdoll_profile_float"):
		return float(_body.call("_get_ragdoll_profile_float", property_name, fallback))
	return fallback


func _process_ragdoll_impulse_memory(delta: float) -> void:
	if _body != null:
		_body.process_ragdoll_impulse_memory(delta)
		return
	if _last_ragdoll_impulse_remaining <= 0.0:
		return
	_last_ragdoll_impulse_remaining = maxf(0.0, _last_ragdoll_impulse_remaining - delta)
	if _last_ragdoll_impulse_remaining <= 0.0:
		_last_ragdoll_impulse = Vector3.ZERO


func _remember_ragdoll_impulse(impulse: Vector3, seconds: float) -> void:
	if _body != null:
		_body.remember_ragdoll_impulse(impulse, seconds)
		return
	_last_ragdoll_impulse = impulse
	_last_ragdoll_impulse_remaining = seconds if impulse.length_squared() > 0.0001 else 0.0


func has_bandageable_wounds() -> bool:
	return _current_open_cut_damage > 0.0 or _bleed_rate > 0.0 or _bleed_burst_rate > 0.0


func can_receive_bandage() -> bool:
	return life_state != NpcRules.LifeState.DEAD and has_bandageable_wounds()


func can_be_carried() -> bool:
	return can_be_carried_by(null)


func can_be_carried_by(carrier: HumanoidCharacter) -> bool:
	if _carried_by != null:
		return false
	if _is_downed_recovery_locked():
		return false
	if carrier != null and carrier.faction_name == faction_name:
		return true
	return life_state == NpcRules.LifeState.ASLEEP or is_downed_state() or life_state == NpcRules.LifeState.DEAD


func is_carried() -> bool:
	return _carried_by != null


func is_carrying_someone() -> bool:
	return _carried_character != null


func is_handling_carried_character() -> bool:
	return _carried_character != null or _current_order_type == OrderType.CARRY or _current_order_type == OrderType.PLACE_IN_BED or _current_order_type == OrderType.PLACE_IN_CELL or _current_order_type == OrderType.PLACE_IN_FURNACE


func is_in_cell_custody() -> bool:
	return _cell_custody_target != null and is_instance_valid(_cell_custody_target)


func get_cell_custody_target() -> Node:
	return _cell_custody_target if _cell_custody_target != null and is_instance_valid(_cell_custody_target) else null


func is_protected_from_combat() -> bool:
	return is_in_cell_custody() or has_meta("law_prisoner")


func is_ragdoll_active() -> bool:
	return _is_ragdoll_active


func get_follow_anchor_position() -> Vector3:
	if _is_ragdoll_active:
		var ragdoll_anchor: Variant = _get_ragdoll_anchor_position()
		if ragdoll_anchor is Vector3:
			return ragdoll_anchor
	return global_position


func get_ground_marker_position(marker_height: float = 0.03) -> Vector3:
	var anchor_position := get_follow_anchor_position()
	var marker_xz := Vector3(anchor_position.x, anchor_position.y, anchor_position.z)
	var fallback := Vector3(marker_xz.x, anchor_position.y + marker_height, marker_xz.z)
	var world := get_world_3d()
	if world == null:
		return fallback
	var start_y := anchor_position.y + GROUND_MARKER_RAYCAST_UP
	var end_y := anchor_position.y - GROUND_MARKER_RAYCAST_DOWN
	var query := PhysicsRayQueryParameters3D.create(Vector3(marker_xz.x, start_y, marker_xz.z), Vector3(marker_xz.x, end_y, marker_xz.z))
	query.exclude = _get_ground_marker_raycast_exclusions()
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.has("position"):
		var hit_position: Vector3 = hit["position"]
		return hit_position + Vector3(0.0, marker_height, 0.0)
	return fallback


func get_carried_character() -> HumanoidCharacter:
	return _carried_character


func get_carrier() -> HumanoidCharacter:
	return _carried_by if _carried_by != null and is_instance_valid(_carried_by) else null


func disengage_combat_with(other: HumanoidCharacter = null) -> void:
	if other != null:
		clear_personal_hostility(other)
	if other == null or _last_direct_attacker_id == other.get_instance_id():
		_last_direct_attacker_id = 0
	if other == null or _current_attack_target == other or _get_active_combat_target() == other:
		stop_attack_assignment()
	_clear_combat_resolution_state(other)
	COMBAT_COORDINATOR.release_character(self)


func set_running_enabled(value: bool) -> bool:
	if value:
		_set_sneaking_state(false, true)
		running = can_enable_running()
	else:
		running = false
	_invalidate_stat_value_cache()
	state_changed.emit()
	return running == value


func set_sneaking_enabled(value: bool) -> void:
	if value:
		running = false
	_set_sneaking_state(value, true)
	state_changed.emit()


func _set_sneaking_state(value: bool, play_transition: bool) -> bool:
	var next_sneaking := value and life_state == NpcRules.LifeState.ALIVE
	if sneaking == next_sneaking:
		return false
	sneaking = next_sneaking
	_invalidate_stat_value_cache()
	if play_transition:
		if sneaking:
			_cancel_run_transition()
			_start_crouch_enter_animation()
		else:
			_start_crouch_exit_animation()
	else:
		_cancel_crouch_transition()
		_cancel_run_transition()
	return true


func _on_actor_skill_level_changed(_skill_id: String) -> void:
	_invalidate_stat_value_cache()


func get_perception_eye_position() -> Vector3:
	return global_position + Vector3(0.0, 1.65, 0.0)


func get_stealth_sample_positions() -> Array[Vector3]:
	return [
		global_position + Vector3(0.0, 0.65, 0.0),
		global_position + Vector3(0.0, 1.15, 0.0),
		global_position + Vector3(-0.28, 1.15, 0.0),
		global_position + Vector3(0.28, 1.15, 0.0),
		global_position + Vector3(0.0, 1.65, 0.0),
	]


func get_stealth_light_sample_position() -> Vector3:
	return global_position + Vector3(0.0, 1.1, 0.0)


func get_stealth_indicator_position() -> Vector3:
	return global_position + Vector3(0.0, 2.65, 0.0)


func _break_stealth_for_combat() -> void:
	var changed := false
	if _set_sneaking_state(false, true):
		changed = true
	if changed:
		state_changed.emit()


func notify_incoming_attack(attacker: Node) -> void:
	if attacker == null or attacker == self:
		return
	if life_state == NpcRules.LifeState.ASLEEP:
		wake_up_from_rest(false)
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if is_protected_from_combat():
		return
	_break_stealth_for_combat()
	mark_hostile(attacker)
	if attacker.has_method("mark_hostile"):
		attacker.call("mark_hostile", self)
	_last_direct_attacker_id = attacker.get_instance_id()
	if not _is_incoming_law_arrest(attacker):
		_notify_defensive_allies_of_attack(attacker)
	if combat_stance == NpcRules.CombatStance.PASSIVE:
		return
	_try_start_self_defense(attacker)


func set_combat_stance(value: int) -> void:
	if value <= NpcRules.CombatStance.AGGRESSIVE:
		combat_stance = NpcRules.CombatStance.AGGRESSIVE
	elif value >= NpcRules.CombatStance.PASSIVE:
		combat_stance = NpcRules.CombatStance.PASSIVE
	else:
		combat_stance = NpcRules.CombatStance.DEFENSIVE
	state_changed.emit()


func receive_attack(attacker: Node, blunt_damage: float, cut_damage: float, attack_id: String = "", hit_reaction_names: Array[String] = [], is_critical := false) -> String:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		return combat_capability.receive_attack(attacker, blunt_damage, cut_damage, attack_id, hit_reaction_names, is_critical)
	return "ignored"


func _is_incoming_law_arrest(attacker: Node) -> bool:
	return attacker != null and attacker.has_method("is_law_arresting") and bool(attacker.call("is_law_arresting", self))


func _is_nonlethal_authority_arrest_attack(attacker: Node) -> bool:
	if attacker == null or not attacker.has_method("is_faction_soldier") or not bool(attacker.call("is_faction_soldier")):
		return false
	var law_controller := _get_law_order_controller()
	if law_controller == null or not law_controller.has_method("actor_has_active_warrant"):
		return false
	return bool(law_controller.call("actor_has_active_warrant", self, str(attacker.get("faction_name"))))


func _clamp_nonlethal_arrest_damage(final_blunt: float, final_cut: float) -> Dictionary:
	var incoming := maxf(0.0, final_blunt) + maxf(0.0, final_cut)
	var max_nonlethal_wounds := maxf(0.0, max_hp + 1.0)
	var available := maxf(0.0, max_nonlethal_wounds - get_total_wound_damage())
	return {"blunt": minf(incoming, available), "cut": 0.0}


func _add_bleeding_from_cut(final_blunt: float, final_cut: float) -> void:
	if final_cut <= 0.0:
		return
	var total_damage := maxf(final_blunt + final_cut, 0.001)
	var cut_ratio := clampf(final_cut / total_damage, 0.0, 1.0)
	var sharp_excess := maxf(0.0, cut_ratio - NpcRules.BLEED_SHARP_CUT_RATIO_THRESHOLD)
	var immediate_loss := final_cut * (NpcRules.BLEED_IMMEDIATE_BLOOD_LOSS_PER_CUT + sharp_excess * NpcRules.BLEED_IMMEDIATE_SHARPNESS_SCALE)
	_apply_blood_loss(immediate_loss)
	_bleed_burst_rate += final_cut * (NpcRules.BLEED_BURST_FROM_CUT_BASE + sharp_excess * NpcRules.BLEED_BURST_SHARPNESS_SCALE)
	_bleed_rate += final_cut * (NpcRules.BLEED_SUSTAINED_FROM_CUT_BASE + sharp_excess * NpcRules.BLEED_SUSTAINED_SHARPNESS_SCALE)
	_spawn_bleed_hit_splotches(final_cut)


func _apply_blood_loss(amount: float) -> void:
	if amount <= 0.0:
		return
	blood = maxf(blood - amount, -maxf(max_blood, 1.0) * NpcRules.BLOOD_LOSS_DEATH_FACTOR)


func apply_bandage_from(actor: HumanoidCharacter) -> bool:
	if actor == null or not can_receive_bandage() or not actor.can_bandage_target(self):
		return false
	var bandage_entry = actor._get_best_bandage_entry()
	if bandage_entry == null:
		return false
	if not actor.inventory.consume_bandage_entry_use(bandage_entry):
		return false
	_current_bandaged_cut_damage += _current_open_cut_damage
	_current_open_cut_damage = 0.0
	_bleed_rate = 0.0
	_bleed_burst_rate = 0.0
	_bleed_drip_progress = 0.0
	_bleed_pool_progress = 0.0
	_recalculate_vitals()
	actor.add_skill_xp(SkillRules.KNOWLEDGE_MEDICINE, MEDICAL_BANDAGE_XP, "bandage")
	return true


func _face_character(character: Node3D) -> void:
	if character == null or not is_instance_valid(character):
		return
	_face_world_position(character.global_position)


func _face_world_position(world_position: Vector3) -> void:
	var look_position := world_position
	look_position.y = global_position.y
	if global_position.distance_squared_to(look_position) <= 0.0001:
		return
	look_at(look_position, Vector3.UP)


func _face_combat_focus() -> void:
	var focus_actor := _get_combat_focus_actor()
	if focus_actor is Node3D:
		_face_character(focus_actor as Node3D)
		return
	var active_target := _get_active_combat_target()
	if active_target != null:
		_face_character(active_target)


func _should_face_combat_focus_after_movement() -> bool:
	if not _has_active_combat_target():
		return false
	if _is_combat_resolution_busy():
		return true
	if _has_move_target:
		return false
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	return horizontal_speed <= 0.15


func _process_movement(delta: float) -> void:
	if _is_sitting:
		velocity = Vector3.ZERO
		return
	if life_state == NpcRules.LifeState.ASLEEP:
		velocity = Vector3.ZERO
		return
	if life_state != NpcRules.LifeState.ALIVE:
		_process_downed_movement(delta)
		if _is_ragdoll_active or _is_getting_up or _downed_is_settled:
			return
		move_and_slide()
		return
	if _is_combat_resolution_busy():
		_face_combat_focus()
		_apply_floor_motion(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	if _should_direct_law_move():
		_process_direct_custody_chase(delta)
		return
	if _should_hold_combat_position():
		var hold_target := _get_active_combat_target()
		_hold_combat_movement(delta, hold_target)
		return
	if _should_direct_combat_chase():
		_process_direct_combat_chase(delta)
		return
	if _should_direct_custody_chase():
		_process_direct_custody_chase(delta)
		return
	if _can_skip_idle_movement_physics():
		velocity = Vector3.ZERO
		return
	process_world_actor_movement(delta)


func _can_skip_idle_movement_physics() -> bool:
	if _has_move_target or not is_on_floor():
		return false
	if absf(velocity.y) > 0.001 or Vector2(velocity.x, velocity.z).length_squared() > 0.0001:
		return false
	return absf(rotation.x) <= 0.001 and absf(rotation.z) <= 0.001


func _get_actor_move_speed() -> float:
	return _get_current_move_speed()


func _should_direct_combat_chase() -> bool:
	var target := _get_active_combat_target()
	if target == null:
		return false
	if absf(target.global_position.y - global_position.y) > move_target_vertical_tolerance:
		return false
	var target_distance := _horizontal_distance_to(target.global_position)
	if target_distance <= _get_effective_combat_attack_range() and _has_active_combat_attack_slot(target):
		return false
	return target_distance <= maxf(maxf(combat_chase_leash_distance, combat_direct_chase_distance), get_attack_range() + 1.0)


func _should_hold_combat_position() -> bool:
	var target := _get_active_combat_target()
	if target == null:
		return false
	if absf(target.global_position.y - global_position.y) > move_target_vertical_tolerance:
		return false
	return _horizontal_distance_to(target.global_position) <= _get_effective_combat_attack_range()


func _get_effective_combat_attack_range() -> float:
	return get_attack_range() + maxf(COMBAT_RANGE_HYSTERESIS, combat_attack_forgiveness_buffer)


func _get_combat_settle_band_distance(target: Node3D) -> float:
	var personal_space := COMBAT_COORDINATOR.get_personal_space_distance(self, target, combat_personal_space_padding)
	var wait_extra := combat_wait_ring_extra if not _has_active_combat_attack_slot(target) else 0.0
	return maxf(_get_effective_combat_attack_range() + combat_settle_band_extra + wait_extra, personal_space + combat_settle_band_extra + wait_extra)


func _get_combat_settle_position(target: Node3D) -> Vector3:
	var desired_range := maxf(COMBAT_COORDINATOR.get_personal_space_distance(self, target, combat_personal_space_padding), _get_effective_combat_attack_range() - combat_approach_arrival_distance * 0.5)
	return COMBAT_COORDINATOR.get_combat_slot_position(target, self, desired_range, combat_wait_ring_extra)


func _clear_combat_movement_state() -> void:
	_combat_slot_role_cache_frame = -1
	_combat_slot_role_cache_target_id = 0
	_combat_slot_role_cache = COMBAT_COORDINATOR.SLOT_ROLE_NONE


func _has_active_combat_attack_slot(target: Node3D) -> bool:
	return _get_combat_slot_role_for_target(target) == COMBAT_COORDINATOR.SLOT_ROLE_ACTIVE


func _get_combat_slot_role_for_target(target: Node3D) -> int:
	if target == null or not is_instance_valid(target):
		return COMBAT_COORDINATOR.SLOT_ROLE_NONE
	var physics_frame := Engine.get_physics_frames()
	var target_id := target.get_instance_id()
	if _combat_slot_role_cache_frame == physics_frame and _combat_slot_role_cache_target_id == target_id:
		return _combat_slot_role_cache
	_combat_slot_role_cache_frame = physics_frame
	_combat_slot_role_cache_target_id = target_id
	_combat_slot_role_cache = COMBAT_COORDINATOR.get_combat_slot_role(self, target)
	return _combat_slot_role_cache


func _process_direct_combat_chase(delta: float) -> void:
	var target := _get_active_combat_target()
	if target == null:
		return
	var target_distance := _horizontal_distance_to(target.global_position)
	if target_distance <= _get_combat_settle_band_distance(target):
		_process_close_combat_movement(delta, target, target_distance)
		return
	_apply_floor_motion(delta)
	var target_position := _get_combat_approach_target_position(target)
	var to_target := target_position - global_position
	to_target.y = 0.0
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var desired_direction := Vector3.ZERO
	if to_target.length() > combat_approach_arrival_distance:
		desired_direction = to_target.normalized()
		horizontal_velocity = horizontal_velocity.lerp(desired_direction * _get_actor_move_speed(), minf(1.0, acceleration * delta))
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, acceleration * delta))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	if not _try_apply_direct_combat_translation(horizontal_velocity, delta):
		move_and_slide()
	if desired_direction.length_squared() > 0.0001:
		look_at(global_position + desired_direction, Vector3.UP)
	else:
		_face_character(target)


func _process_close_combat_movement(delta: float, target: Node3D, target_distance: float) -> void:
	_clear_combat_move_target_if_needed()
	if target_distance <= _get_effective_combat_attack_range():
		_hold_combat_movement(delta, target)
		return
	_apply_floor_motion(delta)
	var settle_position := _get_combat_approach_target_position(target)
	var to_target := settle_position - global_position
	to_target.y = 0.0
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if to_target.length() > combat_approach_arrival_distance * 0.35:
		var desired_direction := to_target.normalized()
		var speed_multiplier := 1.0 if _is_player_attack_order_for(target) else combat_settle_speed_multiplier
		horizontal_velocity = horizontal_velocity.lerp(desired_direction * _get_actor_move_speed() * speed_multiplier, minf(1.0, acceleration * delta))
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, acceleration * delta))
	if _can_skip_low_speed_combat_slide(horizontal_velocity):
		velocity.x = 0.0
		velocity.z = 0.0
		_face_character(target)
		return
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	if not _try_apply_direct_combat_translation(horizontal_velocity, delta):
		move_and_slide()
	_face_character(target)


func _hold_combat_movement(delta: float, target: Node3D) -> void:
	_clear_combat_move_target_if_needed()
	_face_character(target)
	if _can_skip_stationary_combat_physics():
		velocity = Vector3.ZERO
		return
	_apply_floor_motion(delta)
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()


func _get_combat_approach_target_position(target: Node3D) -> Vector3:
	if target == null:
		return global_position
	if _is_player_attack_order_for(target):
		return target.global_position
	if target.has_method("get_combat_move_position"):
		var move_position = target.call("get_combat_move_position", self)
		if move_position is Vector3:
			return move_position
	return COMBAT_COORDINATOR.get_combat_slot_position(target, self, _get_effective_combat_attack_range(), combat_wait_ring_extra)


func _can_skip_stationary_combat_physics() -> bool:
	if not is_on_floor():
		return false
	if absf(velocity.y) > 0.001:
		return false
	return Vector2(velocity.x, velocity.z).length_squared() <= 0.0001


func _can_skip_low_speed_combat_slide(horizontal_velocity: Vector3) -> bool:
	if not is_on_floor() or absf(velocity.y) > 0.001:
		return false
	return Vector2(horizontal_velocity.x, horizontal_velocity.z).length_squared() <= ACTUAL_LOCOMOTION_SPEED_THRESHOLD * ACTUAL_LOCOMOTION_SPEED_THRESHOLD


func _try_apply_direct_combat_translation(horizontal_velocity: Vector3, delta: float) -> bool:
	if not combat_direct_translation_enabled:
		return false
	if use_navigation_pathing or navigation_avoidance_enabled:
		return false
	if not is_on_floor() or absf(velocity.y) > 0.001:
		return false
	global_position += Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z) * delta
	return true


func _clear_combat_move_target_if_needed() -> void:
	if _has_move_target:
		_clear_actor_move_target()


func _should_direct_custody_chase() -> bool:
	if _current_order_type != OrderType.CARRY and _current_order_type != OrderType.PLACE_IN_CELL:
		return false
	return _has_move_target


func _should_direct_law_move() -> bool:
	var interaction = _get_interaction_capability()
	return interaction.has_direct_law_move() if interaction != null else false


func _process_direct_custody_chase(delta: float) -> void:
	_apply_floor_motion(delta)
	var to_target := _move_target - global_position
	to_target.y = 0.0
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var desired_direction := Vector3.ZERO
	if to_target.length() <= _get_move_target_arrival_distance():
		_clear_actor_move_target()
	else:
		desired_direction = _get_direct_custody_move_direction(to_target.normalized())
		horizontal_velocity = horizontal_velocity.lerp(desired_direction * _get_actor_move_speed(), minf(1.0, acceleration * delta))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()
	if desired_direction.length_squared() > 0.0001:
		look_at(global_position + desired_direction, Vector3.UP)


func _get_direct_custody_move_direction(target_direction: Vector3) -> Vector3:
	var desired := target_direction
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if collision == null:
			continue
		var normal := collision.get_normal()
		normal.y = 0.0
		if normal.length_squared() <= 0.0001 or desired.dot(normal.normalized()) >= -0.35:
			continue
		normal = normal.normalized()
		var tangent := Vector3(-normal.z, 0.0, normal.x)
		if tangent.dot(target_direction) < 0.0:
			tangent = -tangent
		desired = (target_direction * 0.35 + tangent.normalized() * 0.9).normalized()
		break
	return desired


func _get_move_target_arrival_distance() -> float:
	if _has_active_combat_target():
		return combat_approach_arrival_distance
	if _current_order_type == OrderType.PICKUP_ITEM:
		return minf(super._get_move_target_arrival_distance(), PICKUP_ROUTE_ARRIVAL_DISTANCE)
	return super._get_move_target_arrival_distance()


func _horizontal_distance_to(target_position: Vector3) -> float:
	return Vector2(global_position.x - target_position.x, global_position.z - target_position.z).length()


func _get_downed_target_anchor_position(target_character: HumanoidCharacter) -> Vector3:
	if target_character == null or not is_instance_valid(target_character):
		return Vector3.INF
	return target_character.get_follow_anchor_position()


func _get_downed_interaction_distance(_target_character: HumanoidCharacter, extra_distance: float = 0.0) -> float:
	return maxf(interact_distance, DOWNED_INTERACTION_DISTANCE) + maxf(extra_distance, 0.0)


func _get_downed_target_interaction_position(target_character: HumanoidCharacter) -> Vector3:
	var anchor_position := _get_downed_target_anchor_position(target_character)
	if anchor_position == Vector3.INF:
		return Vector3.INF
	var approach_direction := global_position - anchor_position
	approach_direction.y = 0.0
	if approach_direction.length_squared() <= 0.0001 and target_character != null:
		approach_direction = -target_character.global_transform.basis.z
		approach_direction.y = 0.0
	if approach_direction.length_squared() <= 0.0001:
		approach_direction = Vector3.FORWARD
	var max_offset := maxf(0.25, _get_downed_interaction_distance(target_character) - 0.65)
	return anchor_position + approach_direction.normalized() * minf(DOWNED_INTERACTION_MOVE_OFFSET, max_offset)


func _is_close_enough_to_downed_interaction_target(target_character: HumanoidCharacter, extra_distance: float = 0.0) -> bool:
	var anchor_position := _get_downed_target_anchor_position(target_character)
	if anchor_position == Vector3.INF:
		return false
	var horizontal_distance := _horizontal_distance_to(anchor_position)
	var vertical_tolerance := maxf(move_target_vertical_tolerance + 0.9, DOWNED_INTERACTION_VERTICAL_TOLERANCE)
	return horizontal_distance <= _get_downed_interaction_distance(target_character, extra_distance) and absf(global_position.y - anchor_position.y) <= vertical_tolerance


func _get_navigation_stuck_arrival_distance() -> float:
	if _current_order_type == OrderType.MOVE:
		return maxf(super._get_navigation_stuck_arrival_distance(), minf(navigation_unreachable_tolerance, 1.2))
	return super._get_navigation_stuck_arrival_distance()


func _is_navigation_final_position_close_enough() -> bool:
	if super._is_navigation_final_position_close_enough():
		return true
	if _current_order_type != OrderType.PICKUP_ITEM or _navigation_agent == null:
		return false
	if _current_pickup_item == null or not is_instance_valid(_current_pickup_item):
		return false
	return _can_pickup_item_from_position(_current_pickup_item, _navigation_agent.get_final_position(), PICKUP_UNREACHABLE_EXTRA_DISTANCE)

func _on_actor_move_target_reached() -> void:
	if _current_order_type == OrderType.MOVE:
		_current_order_type = OrderType.NONE


func _on_actor_move_target_unreachable() -> void:
	if _has_active_combat_target():
		_handle_unreachable_combat_target()
		return
	if _current_order_type == OrderType.FINISH_OFF and _try_complete_finish_off_interaction(DOWNED_INTERACTION_UNREACHABLE_EXTRA):
		return
	if _current_order_type == OrderType.PICKUP_ITEM and _try_complete_pickup_interaction(PICKUP_UNREACHABLE_EXTRA_DISTANCE):
		return
	if _order_was_player_issued:
		show_world_speech("I can't reach that", 4.0)
	match _current_order_type:
		OrderType.MOVE:
			_current_order_type = OrderType.NONE
		OrderType.MINE:
			stop_mining_assignment()
		OrderType.SCAVENGE:
			stop_scavenging_assignment()
		OrderType.OPEN_CONTAINER:
			stop_container_interaction()
		OrderType.TRADE:
			stop_trade_interaction()
		OrderType.TALK:
			stop_conversation_interaction()
		OrderType.ATTACK:
			stop_attack_assignment()
		OrderType.HEAL:
			stop_heal_assignment()
		OrderType.FINISH_OFF:
			stop_finish_off_assignment()
		OrderType.CARRY:
			stop_carry_assignment()
		OrderType.SLEEP:
			stop_sleep_assignment()
		OrderType.PLACE_IN_BED:
			stop_place_in_bed_assignment()
		OrderType.PLACE_IN_CELL:
			stop_place_in_cell_assignment()
		OrderType.PLACE_IN_FURNACE:
			stop_place_in_furnace_assignment()
			_set_auto_burn_backoff(auto_burn_failed_backoff_seconds)
		OrderType.SIT:
			stop_seat_assignment()
		OrderType.PICKUP_ITEM:
			stop_pickup_assignment()


func _handle_unreachable_combat_target() -> void:
	var active_target := _get_active_combat_target()
	var close_target := _find_closest_hostile(_get_close_hostile_retarget_radius())
	if close_target != null and close_target != active_target and not _has_active_player_order():
		assign_attack_target(close_target, false, false, false)
		return
	stop_attack_assignment()


func _process_downed_movement(_delta: float) -> void:
	velocity = Vector3.ZERO
	_downed_is_settled = true


func _process_needs(delta: float) -> void:
	if hunger_enabled:
		if _pending_nourishment > 0.0:
			var nourishment_step := minf(_pending_nourishment, NpcRules.NOURISHMENT_APPLY_RATE * delta * 100.0)
			_pending_nourishment -= nourishment_step
			_apply_hunger_delta(nourishment_step)
		else:
			_apply_hunger_delta(-get_stat_value("hunger_drain_rate") * NpcRules.WORLD_HUNGER_DRAIN_MULTIPLIER * delta)

	if fatigue_enabled:
		var was_running := running
		var fatigue_delta := 0.0
		if life_state == NpcRules.LifeState.ASLEEP:
			fatigue_delta += get_stat_value("fatigue_recovery_rate") * NpcRules.FATIGUE_SLEEP_RECOVERY_MULTIPLIER * delta
		elif life_state != NpcRules.LifeState.ALIVE:
			fatigue_delta += get_stat_value("fatigue_recovery_rate") * delta
		elif _is_working():
			fatigue_delta -= NpcRules.FATIGUE_WORK_DRAIN * delta
		elif is_running_enabled() and _is_actual_locomotion_active():
			fatigue_delta -= NpcRules.FATIGUE_RUN_DRAIN * delta
			add_skill_xp(SkillRules.MOVEMENT_RUNNING, RUNNING_SKILL_XP_PER_SECOND * delta, "running")
			add_skill_xp(SkillRules.ATTRIBUTE_ENDURANCE, RUNNING_ENDURANCE_XP_PER_SECOND * delta, "running")
		elif _is_sitting:
			fatigue_delta += get_stat_value("fatigue_recovery_rate") * NpcRules.FATIGUE_SIT_RECOVERY_MULTIPLIER * delta
		elif _is_actual_locomotion_active():
			fatigue_delta += get_stat_value("fatigue_recovery_rate") * NpcRules.FATIGUE_WALK_RECOVERY_MULTIPLIER * delta
		else:
			fatigue_delta += get_stat_value("fatigue_recovery_rate") * delta
		_apply_fatigue_delta(fatigue_delta)
		if life_state == NpcRules.LifeState.ALIVE and is_carrying_someone() and _is_actual_locomotion_active():
			add_skill_xp(SkillRules.ATTRIBUTE_STRENGTH, CARRY_STRENGTH_XP_PER_SECOND * delta, "carrying")
		if running and not can_continue_running():
			running = false
		if was_running != running:
			state_changed.emit()


func _process_needs_capability(delta: float) -> void:
	var needs_capability = _get_needs_capability()
	if needs_capability != null and needs_capability.has_method("process_actor_needs"):
		var enabled_value = needs_capability.get("enabled")
		if enabled_value == null or bool(enabled_value):
			needs_capability.call("process_actor_needs", delta)
		return
	_process_needs(delta)
	_process_bleeding(delta)
	_process_dying(delta)
	_process_recovery(delta)


func _process_scheduled_needs(delta: float) -> void:
	var needs_capability = _get_needs_capability()
	if needs_capability != null and needs_capability.has_method("process_scheduled_needs"):
		needs_capability.call("process_scheduled_needs", delta)


func _get_needs_capability():
	return get_actor_capability(&"needs")


func _get_combat_capability() -> CombatCapability:
	if _combat_capability == null:
		_combat_capability = get_actor_capability(&"combat") as CombatCapability
	return _combat_capability


func _get_ai_targeting_capability():
	if _ai_targeting_capability == null:
		_ai_targeting_capability = get_actor_capability(&"ai_targeting")
	return _ai_targeting_capability


func _get_interaction_capability():
	if _interaction_capability == null:
		_setup_actor_capabilities()
		_interaction_capability = get_actor_capability(&"interaction")
	return _interaction_capability


func _validate_heal_finish_interaction_orders() -> void:
	if _current_order_type != OrderType.HEAL and _current_order_type != OrderType.FINISH_OFF:
		return
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.validate_heal_finish_order_targets()


func _validate_carried_interaction_orders() -> void:
	if _current_order_type != OrderType.CARRY and _current_order_type != OrderType.PLACE_IN_BED and _current_order_type != OrderType.PLACE_IN_CELL and _current_order_type != OrderType.PLACE_IN_FURNACE:
		return
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.validate_carried_order_targets()


func _process_combat_cooldown(delta: float) -> void:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		combat_capability.process_cooldown(delta)


func _is_combat_resolution_busy() -> bool:
	var combat_capability := _get_combat_capability()
	return combat_capability.is_busy() if combat_capability != null else false


func _is_combat_resolution_ready() -> bool:
	var combat_capability := _get_combat_capability()
	return combat_capability.is_ready() if combat_capability != null else true


func _get_combat_reaction_remaining() -> float:
	var combat_capability := _get_combat_capability()
	return combat_capability.reaction_remaining if combat_capability != null else 0.0


func _get_combat_focus_actor() -> Node:
	var combat_capability := _get_combat_capability()
	return combat_capability.get_focus_actor() if combat_capability != null else null


func _clear_combat_resolution_state(other: Node = null) -> void:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		combat_capability.clear_for_actor(other)


func _invalidate_combat_slot_role_cache() -> void:
	_combat_slot_role_cache_frame = -1


func _roll_combat_action_damage() -> Dictionary:
	return roll_combat_attack_damage(_rng)


func _roll_combat_resolution_chance() -> float:
	return _rng.randf()


func _remember_combat_attack_impulse(attacker: Node, damage: float) -> void:
	_remember_ragdoll_impulse(_get_attack_ragdoll_impulse(attacker, damage), RAGDOLL_IMPULSE_MEMORY_SECONDS)


func _get_default_combat_action_seconds() -> float:
	return DEFAULT_COMBAT_ACTION_SECONDS


func _get_default_combat_impact_ratio() -> float:
	return DEFAULT_COMBAT_IMPACT_RATIO


func _seed_needs_capability_tick() -> void:
	var needs_capability = _get_needs_capability()
	if needs_capability != null and needs_capability.has_method("set_tick_remaining"):
		needs_capability.call("set_tick_remaining", _rng.randf_range(0.0, NEEDS_PROCESS_INTERVAL))


func _has_scheduled_needs_work() -> bool:
	return hunger_enabled or fatigue_enabled or _pending_nourishment > 0.0


func _get_needs_process_jitter() -> float:
	return _rng.randf_range(0.0, NEEDS_PROCESS_JITTER)


func _process_bleeding(delta: float) -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	var total_bleed_rate := get_bleed_rate()
	if total_bleed_rate <= 0.0:
		return
	var blood_loss_amount := total_bleed_rate * NpcRules.BLEED_TO_BLOOD_RATE * delta
	_apply_blood_loss(blood_loss_amount)
	_recalculate_vitals()
	_process_bleed_splotches(total_bleed_rate, blood_loss_amount, delta)


func _process_dying(delta: float) -> void:
	if life_state != NpcRules.LifeState.DYING:
		return
	if not _has_lethal_dying_vitals() or not _should_enter_dead_state_from_vitals():
		_enter_recovery_coma_state()
		return
	_dying_timer_remaining = maxf(0.0, _dying_timer_remaining - delta)
	if _dying_timer_remaining <= 0.0:
		_enter_dead_state()


func _has_lethal_dying_vitals() -> bool:
	return blood <= get_blood_death_point() or hp <= get_death_point(max_hp)


func _process_recovery(delta: float) -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	if _current_blunt_damage <= 0.0 and _current_bandaged_cut_damage <= 0.0 and _current_open_cut_damage <= 0.0 and _bleed_burst_rate <= 0.0 and _bleed_rate <= 0.0 and blood >= max_blood and not is_recoverable_downed_state():
		return
	var healing_step := get_stat_value("healing_rate") * delta
	var recovery_multiplier := _get_recovery_multiplier()
	healing_step *= recovery_multiplier
	if healing_step <= 0.0:
		return
	_current_blunt_damage = maxf(0.0, _current_blunt_damage - healing_step)
	_current_bandaged_cut_damage = maxf(0.0, _current_bandaged_cut_damage - healing_step * 0.8)
	_current_open_cut_damage = maxf(0.0, _current_open_cut_damage - healing_step * 0.35)
	if _bleed_burst_rate > 0.0:
		var burst_clot_step := maxf(NpcRules.BLEED_BURST_MIN_CLOT_RATE, _bleed_burst_rate * NpcRules.BLEED_BURST_CLOT_FRACTION_PER_SECOND) * delta + healing_step * NpcRules.BLEED_HEALING_BURST_CLOT_MULTIPLIER
		_bleed_burst_rate = maxf(0.0, _bleed_burst_rate - burst_clot_step)
	if _bleed_rate > 0.0:
		var clot_step := NpcRules.BLEED_CLOT_RATE * delta + healing_step * NpcRules.BLEED_HEALING_CLOT_MULTIPLIER
		_bleed_rate = maxf(0.0, _bleed_rate - clot_step)
	if get_bleed_rate() <= 0.0 and blood < max_blood:
		var blood_recovery_step := get_stat_value("blood_recovery_rate") * delta
		blood_recovery_step *= recovery_multiplier
		blood = minf(max_blood, blood + blood_recovery_step)
	if is_recoverable_downed_state() and not _is_downed_recovery_locked():
		_downed_recover_delay_remaining = maxf(0.0, _downed_recover_delay_remaining - delta)
	_recalculate_vitals()


func _get_recovery_multiplier() -> float:
	if _current_sleep_target != null and is_instance_valid(_current_sleep_target):
		if _current_sleep_target.has_method("get_recovery_multiplier"):
			return maxf(1.0, float(_current_sleep_target.call("get_recovery_multiplier")))
		return 8.0
	return 8.0 if life_state == NpcRules.LifeState.ASLEEP else 1.0


func _process_bleed_splotches(total_bleed_rate: float, blood_loss_amount: float, delta: float) -> void:
	if life_state == NpcRules.LifeState.DEAD or total_bleed_rate <= 0.0 or blood_loss_amount <= 0.0:
		return
	var blood_loss_per_second := total_bleed_rate * NpcRules.BLEED_TO_BLOOD_RATE
	var severity := clampf(blood_loss_per_second / 8.0, 0.0, 1.0)
	_bleed_drip_progress += delta * clampf(blood_loss_per_second / 2.5, 0.08, 2.2)
	var drip_count := 0
	while _bleed_drip_progress >= 1.0 and drip_count < 3:
		_spawn_bleed_drip_splotch(severity)
		_bleed_drip_progress -= 1.0
		drip_count += 1
	if life_state != NpcRules.LifeState.ALIVE:
		_bleed_pool_progress += delta * clampf(blood_loss_per_second / 4.0, 0.04, 1.25)
		var pool_count := 0
		while _bleed_pool_progress >= 1.0 and pool_count < 2:
			_spawn_bleed_pool_splotch(severity)
			_bleed_pool_progress -= 1.0
			pool_count += 1


func _spawn_bleed_hit_splotches(cut_damage: float) -> void:
	var controller := _get_bleed_splotch_controller()
	if controller != null and controller.has_method("spawn_hit_splash"):
		controller.call("spawn_hit_splash", self, get_bleed_fluid(), cut_damage)


func _spawn_bleed_drip_splotch(severity: float) -> void:
	var controller := _get_bleed_splotch_controller()
	if controller != null and controller.has_method("spawn_bleed_drip"):
		controller.call("spawn_bleed_drip", self, get_bleed_fluid(), severity)


func _spawn_bleed_pool_splotch(severity: float) -> void:
	var controller := _get_bleed_splotch_controller()
	if controller != null and controller.has_method("spawn_bleed_pool"):
		controller.call("spawn_bleed_pool", self, get_bleed_fluid(), severity)


func _get_bleed_splotch_controller() -> Node:
	if _bleed_splotch_controller != null and is_instance_valid(_bleed_splotch_controller):
		return _bleed_splotch_controller
	var tree := get_tree()
	if tree == null:
		return null
	var controllers := tree.get_nodes_in_group("bleed_splotch_controller")
	if not controllers.is_empty():
		_bleed_splotch_controller = controllers[0] as Node
		return _bleed_splotch_controller
	if tree.current_scene == null:
		return null
	_bleed_splotch_controller = tree.current_scene.get_node_or_null("GameBootstrap/BleedSplotchController")
	return _bleed_splotch_controller


func _process_ai(delta: float) -> void:
	if life_state != NpcRules.LifeState.ALIVE:
		if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
			_active_job_provider.pause_worker_job(self, false)
		if _ai_brain != null and _ai_brain.has_active_job():
			_ai_brain.clear_active_job()
		_sync_active_combat_actor_group()
		return
	_clear_invalid_ai_job()
	if _ai_brain != null:
		_tick_active_ai_job(delta)
	if _ai_utility_adapter == null:
		_ensure_assigned_work_ai_job()
	_process_law_movement()
	_validate_heal_finish_interaction_orders()
	_validate_carried_interaction_orders()
	if _current_order_type == OrderType.PICKUP_ITEM and (_current_pickup_item == null or not is_instance_valid(_current_pickup_item)):
		stop_pickup_assignment()
	if _current_attack_target != null and not _is_valid_active_combat_target(_current_attack_target):
		stop_attack_assignment()
	if should_run_close_combat_retarget(delta) and _try_reconfigure_close_combat_target():
		return
	if _get_active_combat_target() != null:
		return
	if not _should_run_ai_decision_tick(delta):
		return
	if _ai_utility_adapter != null and bool(_ai_utility_adapter.run_actor_decision(self)):
		return
	if _should_consider_combat_retarget():
		var replacement_target := _find_ai_target()
		var active_target := _get_active_combat_target()
		if replacement_target != null and replacement_target != active_target and COMBAT_COORDINATOR.should_switch_target(self, active_target, replacement_target, maxf(aggressive_scan_radius, assist_scan_radius)):
			assign_attack_target(replacement_target, false, true, false)
			return
	if _should_seek_auto_heal_target():
		var heal_target := _find_auto_heal_target()
		if heal_target != null:
			assign_heal_target(heal_target, false)
			return
	if _try_assign_auto_burn_action():
		return
	if _should_seek_combat_target():
		var target := _find_ai_target()
		if target != null:
			assign_attack_target(target, false)


func _process_ai_profiled(delta: float) -> void:
	var profile_last_usec := Time.get_ticks_usec()
	if life_state != NpcRules.LifeState.ALIVE:
		if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
			_active_job_provider.pause_worker_job(self, false)
		if _ai_brain != null and _ai_brain.has_active_job():
			_ai_brain.clear_active_job()
		_sync_active_combat_actor_group()
		_debug_humanoid_ai_profile_checkpoint("life_state_cleanup", profile_last_usec)
		_debug_humanoid_ai_profile_finish()
		return
	_clear_invalid_ai_job()
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("clear_invalid_job", profile_last_usec)
	if _ai_brain != null:
		_tick_active_ai_job(delta)
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("tick_active_job", profile_last_usec)
	if _ai_utility_adapter == null:
		_ensure_assigned_work_ai_job()
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("assigned_work_fallback", profile_last_usec)
	_process_law_movement()
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("law_movement", profile_last_usec)
	_validate_heal_finish_interaction_orders()
	_validate_carried_interaction_orders()
	if _current_order_type == OrderType.PICKUP_ITEM and (_current_pickup_item == null or not is_instance_valid(_current_pickup_item)):
		stop_pickup_assignment()
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("order_validation", profile_last_usec)
	if _current_attack_target != null and not _is_valid_active_combat_target(_current_attack_target):
		stop_attack_assignment()
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("attack_validation", profile_last_usec)
	if should_run_close_combat_retarget(delta) and _try_reconfigure_close_combat_target():
		_debug_humanoid_ai_profile_checkpoint("close_combat_retarget", profile_last_usec)
		_debug_humanoid_ai_profile_finish()
		return
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("close_combat_retarget", profile_last_usec)
	if _get_active_combat_target() != null:
		_debug_humanoid_ai_profile_checkpoint("active_combat_hold", profile_last_usec)
		_debug_humanoid_ai_profile_finish()
		return
	if not _should_run_ai_decision_tick(delta):
		_debug_humanoid_ai_profile_checkpoint("decision_gate", profile_last_usec)
		_debug_humanoid_ai_profile_finish()
		return
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("decision_gate", profile_last_usec)
	if _ai_utility_adapter != null and bool(_ai_utility_adapter.run_actor_decision(self)):
		_debug_humanoid_ai_profile_checkpoint("utility_decision", profile_last_usec)
		_debug_humanoid_ai_profile_finish()
		return
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("utility_decision", profile_last_usec)
	if _should_consider_combat_retarget():
		var replacement_target := _find_ai_target()
		var active_target := _get_active_combat_target()
		if replacement_target != null and replacement_target != active_target and COMBAT_COORDINATOR.should_switch_target(self, active_target, replacement_target, maxf(aggressive_scan_radius, assist_scan_radius)):
			assign_attack_target(replacement_target, false, true, false)
			_debug_humanoid_ai_profile_checkpoint("retarget", profile_last_usec)
			_debug_humanoid_ai_profile_finish()
			return
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("retarget", profile_last_usec)
	if _should_seek_auto_heal_target():
		var heal_target := _find_auto_heal_target()
		if heal_target != null:
			assign_heal_target(heal_target, false)
			_debug_humanoid_ai_profile_checkpoint("auto_heal", profile_last_usec)
			_debug_humanoid_ai_profile_finish()
			return
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("auto_heal", profile_last_usec)
	if _try_assign_auto_burn_action():
		_debug_humanoid_ai_profile_checkpoint("auto_burn", profile_last_usec)
		_debug_humanoid_ai_profile_finish()
		return
	profile_last_usec = _debug_humanoid_ai_profile_checkpoint("auto_burn", profile_last_usec)
	if _should_seek_combat_target():
		var target := _find_ai_target()
		if target != null:
			assign_attack_target(target, false)
	_debug_humanoid_ai_profile_checkpoint("seek_combat", profile_last_usec)
	_debug_humanoid_ai_profile_finish()


func _should_run_ai_decision_tick(delta: float) -> bool:
	_ai_tick_remaining -= delta
	if _ai_tick_remaining > 0.0:
		return false
	# Utility decisions build context, touch GECS/job state, and may scan targets/contracts.
	# Keep combat/orders/party responsive, but tick idle background NPC decisions less often.
	var decision_interval := BACKGROUND_AI_DECISION_INTERVAL
	var decision_jitter := BACKGROUND_AI_DECISION_JITTER
	if _current_order_type != OrderType.NONE or _has_active_combat_target() or player_party_member:
		decision_interval = ACTIVE_AI_DECISION_INTERVAL
		decision_jitter = ACTIVE_AI_DECISION_JITTER
	elif _should_use_far_background_ai_cadence():
		decision_interval = FAR_BACKGROUND_AI_DECISION_INTERVAL
		decision_jitter = FAR_BACKGROUND_AI_DECISION_JITTER
	var scheduler := _get_runtime_controller("ai_scheduler_controller")
	if scheduler != null and scheduler.has_method("should_tick_actor"):
		if bool(scheduler.call("should_tick_actor", self, decision_interval, decision_jitter)):
			_ai_tick_remaining = decision_interval + _rng.randf_range(0.0, decision_jitter)
			return true
		_ai_tick_remaining = 0.05
		return false
	_ai_tick_remaining = decision_interval + _rng.randf_range(0.0, decision_jitter)
	return true


func _should_use_far_background_ai_cadence() -> bool:
	if _current_order_type != OrderType.NONE or player_party_member or _has_active_combat_target():
		return false
	if _ai_brain != null and _ai_brain.has_active_job():
		return false
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var party_members := tree.get_nodes_in_group("party_member")
	if party_members.is_empty():
		return false
	var distance_squared := FAR_BACKGROUND_AI_DECISION_DISTANCE * FAR_BACKGROUND_AI_DECISION_DISTANCE
	for node in party_members:
		if not (node is Node3D):
			continue
		var party_member := node as Node3D
		if global_position.distance_squared_to(party_member.global_position) <= distance_squared:
			return false
	return true


func _should_use_far_runtime_cadence() -> bool:
	if player_party_member or life_state != NpcRules.LifeState.ALIVE:
		return false
	if _carried_by != null or _carried_character != null or _is_ragdoll_active:
		return false
	if _has_active_combat_target() or _is_combat_resolution_busy():
		return false
	if _has_active_player_order() or _is_active_ai_combat_player_issued():
		return false
	if not is_inside_tree():
		return false
	return _is_far_from_runtime_focus(FAR_RUNTIME_CADENCE_DISTANCE)


func _is_far_from_runtime_focus(distance: float) -> bool:
	var distance_squared := distance * distance
	var focus_positions := _get_runtime_focus_positions()
	if focus_positions.is_empty() and get_tree() == null:
		return false
	for focus_position in focus_positions:
		if global_position.distance_squared_to(focus_position) <= distance_squared:
			return false
	return true


func _get_runtime_focus_positions() -> Array[Vector3]:
	var tree := get_tree()
	if tree == null:
		_runtime_focus_cache_frame_key = -1
		_runtime_focus_cache_tree_id = 0
		_runtime_focus_cache_positions = []
		return _runtime_focus_cache_positions
	var tree_id := tree.get_instance_id()
	var frame_key := Engine.get_process_frames() * 1000000 + Engine.get_physics_frames()
	if _runtime_focus_cache_frame_key == frame_key and _runtime_focus_cache_tree_id == tree_id:
		return _runtime_focus_cache_positions
	var positions: Array[Vector3] = []
	for node in tree.get_nodes_in_group("party_member"):
		if node is Node3D:
			positions.append((node as Node3D).global_position)
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera is Camera3D:
		positions.append((camera as Camera3D).global_position)
	_runtime_focus_cache_frame_key = frame_key
	_runtime_focus_cache_tree_id = tree_id
	_runtime_focus_cache_positions = positions
	return _runtime_focus_cache_positions


func _process_law_movement() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_law_movement()


func _process_law_custody_return() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_law_custody_return()


func _process_law_sentence_move() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_law_sentence_move()


func _process_mining(delta: float) -> void:
	if _current_mining_node == null:
		return
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_mining(delta)


func _award_mining_progress_xp(progress_delta: float, xp_multiplier: float = 1.0) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.award_mining_progress_xp(progress_delta, xp_multiplier)


func _show_mining_requirement_notice(mining_node: MiningResourceNode) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.show_mining_requirement_notice(mining_node)


func _ensure_mining_tool_equipped(mining_node: MiningResourceNode, issued_by_player: bool) -> bool:
	var interaction = _get_interaction_capability()
	return interaction.ensure_mining_tool_equipped(mining_node, issued_by_player) if interaction != null else false


func _find_inventory_tool(required_tag: String) -> ItemDefinition:
	if required_tag.is_empty() or inventory == null:
		return null
	for entry in inventory.entries:
		if _item_has_tool_tag(entry.definition, required_tag):
			return entry.definition
	return null


func _item_has_tool_tag(item: ItemDefinition, required_tag: String) -> bool:
	return item != null and item.has_method("has_tool_tag") and item.has_tool_tag(required_tag)


func _get_mining_tool_label(mining_node: MiningResourceNode) -> String:
	var interaction = _get_interaction_capability()
	return interaction.get_mining_tool_label(mining_node) if interaction != null else "Tool"


func _show_mining_notice(message: String, color: Color, center_notice: bool) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.show_mining_notice(message, color, center_notice)


func _process_scavenging(delta: float) -> void:
	if _current_scavenging_node == null:
		return
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_scavenging(delta)


func _award_scavenging_progress_xp(progress_delta: float) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.award_scavenging_progress_xp(progress_delta)


func _show_scavenging_notice(message: String, color: Color, center_notice: bool) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.show_scavenging_notice(message, color, center_notice)


func _get_scavenging_notice_color(result: Dictionary) -> Color:
	var interaction = _get_interaction_capability()
	return interaction.get_scavenging_notice_color(result) if interaction != null else Color(0.74, 0.68, 0.55, 1.0)


func _process_container_interaction() -> void:
	if _current_container_target == null:
		return
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_container_interaction()


func _process_trade_interaction() -> void:
	if _current_trade_target == null:
		return
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_trade_interaction()


func _process_conversation_interaction() -> void:
	if _current_conversation_target == null:
		return
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_conversation_interaction()


func _get_conversation_interaction_distance() -> float:
	var interaction = _get_interaction_capability()
	return interaction.get_conversation_interaction_distance() if interaction != null else interact_distance


func _process_sleep_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_sleep_interaction()


func _process_place_in_bed_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_place_in_bed_interaction()


func _process_place_in_cell_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_place_in_cell_interaction()


func _process_place_in_furnace_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_place_in_furnace_interaction()


func _get_place_cell_route(cell) -> Array[Vector3]:
	var interaction = _get_interaction_capability()
	return interaction.get_place_cell_route(cell) if interaction != null else []


func _set_next_place_cell_move_target(final_position: Vector3) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.set_next_place_cell_move_target(final_position)


func _process_seat_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_seat_interaction()


func _process_attack_interaction() -> void:
	if _is_combat_resolution_busy():
		_face_combat_focus()
		return
	var target := _get_active_combat_target()
	if target == null:
		stop_attack_assignment()
		return
	if _should_abandon_attack_chase():
		stop_attack_assignment()
		return
	if not _is_combat_resolution_ready():
		return
	var target_distance := _horizontal_distance_to(target.global_position)
	var chase_distance := _get_effective_combat_attack_range()
	var target_position := _get_combat_approach_target_position(target)
	if COMBAT_COORDINATOR.is_character_locked(self):
		if target_distance > chase_distance:
			_set_actor_move_target(target_position)
		else:
			_clear_combat_move_target_if_needed()
			_face_character(target)
		return
	if target_distance > chase_distance:
		_set_actor_move_target(target_position)
		return
	_clear_combat_move_target_if_needed()
	_face_character(target)
	_start_combat_attack(target)


func _process_combat_animation_state(delta: float) -> void:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		combat_capability.process_action_state(delta)


func _start_combat_attack(target: Node3D) -> void:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		combat_capability.start_attack(target)

func _start_default_timed_combat_attack(target: Node3D) -> void:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		combat_capability.start_default_timed_attack(target)


func _choose_combat_attack(animation_set):
	if animation_set == null:
		return null
	var available_attacks: Array = []
	var total_weight := 0.0
	for attack in animation_set.attacks:
		if attack == null:
			continue
		var action_names: Array[String] = attack.get_animation_names()
		if _body == null or not _body.can_play_combat_action(action_names):
			continue
		available_attacks.append(attack)
		total_weight += maxf(float(attack.weight), 0.0)
	if available_attacks.is_empty() or total_weight <= 0.0:
		return null
	var roll := _rng.randf_range(0.0, total_weight)
	for attack in available_attacks:
		roll -= maxf(float(attack.weight), 0.0)
		if roll <= 0.0:
			return attack
	return available_attacks[available_attacks.size() - 1]


func _get_combat_action_timing(animation_names: Array[String], impact_ratio: float) -> Dictionary:
	if _body != null:
		return _body.get_combat_action_timing(animation_names, impact_ratio, DEFAULT_COMBAT_ACTION_SECONDS)
	var action_seconds := DEFAULT_COMBAT_ACTION_SECONDS
	return {
		"total_seconds": action_seconds,
		"first_clip_seconds": 0.0,
		"impact_seconds": clampf(action_seconds * impact_ratio, 0.05, maxf(0.05, action_seconds - 0.03)),
	}


func _play_combat_action_clip(animation_name: String) -> float:
	var clip_seconds := _body.clip_length(animation_name) if _body != null else 0.0
	if _body != null:
		_body.play_clip(animation_name, 0.0, true, COMBAT_ACTION_BLEND_SECONDS)
	return clip_seconds


func _resolve_combat_action_impact() -> void:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		combat_capability.resolve_action_impact()


func _finish_combat_action() -> void:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		combat_capability.finish_action()


func _clear_combat_action() -> void:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		combat_capability.clear_action()


func _prepare_combat_reaction(attacker: Node) -> void:
	var combat_capability := _get_combat_capability()
	if combat_capability != null:
		combat_capability.prepare_reaction(attacker)


func _play_combat_reaction(animation_name: String) -> bool:
	var combat_capability := _get_combat_capability()
	return combat_capability.play_reaction(animation_name) if combat_capability != null else false


func _pick_combat_block_reaction_clip(has_shield_block: bool) -> String:
	return _body.pick_block_reaction_clip(has_shield_block, _get_current_combat_animation_set(), SHIELD_BLOCK_ANIMATION_NAMES, BLOCK_ANIMATION_NAME) if _body != null else ""


func _pick_combat_hit_reaction_clip(attack_id: String, hit_reaction_names: Array[String]) -> String:
	return _body.pick_hit_reaction_clip(attack_id, hit_reaction_names) if _body != null else ""


func _play_combat_reaction_clip(animation_name: String) -> float:
	return _body.play_combat_reaction_clip(animation_name, COMBAT_ACTION_BLEND_SECONDS) if _body != null else 0.0


func _has_equipped_shield() -> bool:
	var offhand_item := get_equipped_item(ItemDefinition.EQUIP_SLOT_OFFHAND)
	if offhand_item == null or offhand_item.grip_profile == null:
		return false
	return str(offhand_item.grip_profile.get("grip_class_id")) == EquipmentGripProfile.GRIP_CLASS_OFFHAND_SHIELD


func _process_heal_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_heal_interaction()


func _process_finish_off_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_finish_off_interaction()


func _try_complete_finish_off_interaction(extra_distance: float = 0.0) -> bool:
	var interaction = _get_interaction_capability()
	return interaction.try_complete_finish_off_interaction(extra_distance) if interaction != null else false


func _process_carry_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_carry_interaction()


func _process_pickup_interaction() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.process_pickup_interaction()


func _try_complete_pickup_interaction(extra_distance: float = 0.0) -> bool:
	var interaction = _get_interaction_capability()
	return interaction.try_complete_pickup_interaction(extra_distance) if interaction != null else false


func _can_pickup_item_from_position(item, actor_position: Vector3, extra_distance: float = 0.0) -> bool:
	var interaction = _get_interaction_capability()
	return interaction.can_pickup_item_from_position(item, actor_position, extra_distance) if interaction != null else false


func _get_pickup_route_position(item) -> Vector3:
	var interaction = _get_interaction_capability()
	return interaction.get_pickup_route_position(item) if interaction != null else global_position


func _get_stored_mining_progress(resource_node) -> float:
	var interaction = _get_interaction_capability()
	return interaction.get_stored_mining_progress(resource_node) if interaction != null else 0.0


func _store_mining_progress(resource_node, progress: float) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.store_mining_progress(resource_node, progress)


func _get_stored_scavenging_progress(resource_node) -> float:
	var interaction = _get_interaction_capability()
	return interaction.get_stored_scavenging_progress(resource_node) if interaction != null else 0.0


func _store_scavenging_progress(resource_node, progress: float) -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.store_scavenging_progress(resource_node, progress)


func set_selected(value: bool) -> void:
	is_selected = value
	_update_selection_state()


func set_focused(value: bool) -> void:
	is_focused = value
	_update_selection_state()


func _update_selection_state() -> void:
	_update_inspect_visual()
	_update_ground_markers()


func _setup_nameplate() -> void:
	if not show_nameplate:
		return
	_nameplate = get_node_or_null("Nameplate")
	if _nameplate == null:
		_nameplate = Label3D.new()
		_nameplate.name = "Nameplate"
		add_child(_nameplate)
	_nameplate.text = member_name
	_nameplate.position = Vector3(0.0, overhead_text_height, 0.0)
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.no_depth_test = false
	_nameplate.font_size = 50
	_nameplate.modulate = Color(0.56, 0.56, 0.6, 0.96)
	_nameplate.outline_size = 0
	_nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func refresh_nameplate() -> void:
	if not show_nameplate:
		return
	if _nameplate == null or not is_instance_valid(_nameplate):
		_setup_nameplate()
		return
	_nameplate.text = member_name
	_nameplate.position = Vector3(0.0, overhead_text_height, 0.0)


func _setup_inspect_ring() -> void:
	_inspect_ring = null


func _update_inspect_visual() -> void:
	if _inspect_ring != null:
		_inspect_ring.visible = false


func _update_ground_markers() -> void:
	if _selection_ring == null or not is_instance_valid(_selection_ring):
		_selection_ring = get_node_or_null("SelectionRing") as Node3D
	if _selection_ring != null and _selection_ring.visible:
		var selection_height := UPRIGHT_SELECTION_GROUND_MARKER_HEIGHT if life_state == NpcRules.LifeState.ALIVE and not _is_ragdoll_active else SELECTION_GROUND_MARKER_HEIGHT
		_update_ground_marker_transform(_selection_ring, selection_height)


func _update_ground_marker_transform(marker: Node3D, marker_height: float) -> void:
	if marker == null or not is_instance_valid(marker):
		return
	marker.top_level = true
	marker.global_position = get_ground_marker_position(marker_height)
	marker.global_rotation = Vector3.ZERO


func _get_ground_marker_raycast_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = [get_rid()]
	var carrier := get_carrier()
	if carrier != null:
		exclusions.append(carrier.get_rid())
	for physical_bone_value in _ragdoll_physical_bones.values():
		var physical_bone := physical_bone_value as PhysicalBone3D
		if physical_bone != null and is_instance_valid(physical_bone):
			exclusions.append(physical_bone.get_rid())
	return exclusions


func _setup_character_visual() -> void:
	# A2 transitional shim -> BodyProjection.setup_visual. CharacterVisual now lives
	# under BodyProjection; actor remains the truth owner during this split.
	if _body != null:
		_body.setup_visual()


func _ensure_appearance_data() -> void:
	if appearance_data == null:
		appearance_data = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	else:
		appearance_data = appearance_data.make_copy()
	if appearance_data.character_race == null:
		appearance_data.character_race = character_race
	else:
		character_race = appearance_data.character_race
	if appearance_data.body_archetype == null:
		appearance_data.body_archetype = body_archetype
	else:
		body_archetype = appearance_data.body_archetype
	if appearance_data.visual_body_type == APPEARANCE_VISUAL_BODY_TYPE_AUTO:
		appearance_data.visual_body_type = visual_body_type
	else:
		visual_body_type = appearance_data.visual_body_type
	_apply_automatic_eyebrow_style()


func _apply_automatic_eyebrow_style() -> void:
	# A3 transitional shim -> BodyProjection.apply_automatic_eyebrow_style.
	if _body == null:
		_setup_body_projection()
	if _body != null:
		_body.apply_automatic_eyebrow_style()


func has_custom_skin_material() -> bool:
	return _body.has_custom_skin_material() if _body != null else false


func get_character_visual_root() -> Node3D:
	if _body != null:
		var body_visual_root := _body.get_visual_root()
		if body_visual_root != null:
			return body_visual_root
	return get_node_or_null(CHARACTER_VISUAL_NODE_NAME) as Node3D


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


func _reset_bone_pose_positions(skeleton: Skeleton3D, offsets: Dictionary) -> void:
	for bone_name in offsets.keys():
		var bone_index := skeleton.find_bone(str(bone_name))
		if bone_index < 0:
			continue
		skeleton.set_bone_pose_position(bone_index, skeleton.get_bone_rest(bone_index).origin)


func refresh_grip_sockets_for_body() -> void:
	# A2 transitional shim -> BodyProjection.refresh_grip_sockets_for_body.
	# Kept for existing callers until A5 removes actor-side visual shims.
	if _body != null:
		_body.refresh_grip_sockets_for_body()


func _rebuild_character_visual_for_equipment() -> void:
	# A2 transitional shim -> BodyProjection.rebuild_visual_for_equipment.
	if _body != null:
		_body.rebuild_visual_for_equipment()


func _rebuild_character_visual_for_appearance() -> void:
	# A3 transitional shim -> BodyProjection.rebuild_visual_for_appearance.
	if _body != null:
		_body.rebuild_visual_for_appearance()


func _can_refresh_bone_equipment_only(changed_slots: Array) -> bool:
	# A2 transitional shim -> BodyProjection.can_refresh_bone_equipment_only.
	return _body.can_refresh_bone_equipment_only(changed_slots) if _body != null else false


func _refresh_bone_equipment_slots(changed_slots: Array) -> void:
	# A2 transitional shim -> BodyProjection.refresh_bone_equipment_slots.
	if _body != null:
		_body.refresh_bone_equipment_slots(changed_slots)


func _apply_skin_materials(root: Node, body_type: int) -> void:
	# A3 transitional shim -> BodyProjection.apply_appearance_materials.
	if _body != null:
		_body.apply_appearance_materials(root, body_type)


func _set_base_eyebrow_visuals_visible(root: Node, visible_flag: bool) -> void:
	# A3 transitional shim -> BodyProjection.set_base_eyebrow_visuals_visible.
	if _body != null:
		_body.set_base_eyebrow_visuals_visible(root, visible_flag)


func _set_equipped_clothing_visuals_visible(visible_flag: bool) -> void:
	# A2 transitional shim -> BodyProjection.set_equipped_clothing_visuals_visible.
	if _body != null:
		_body.set_equipped_clothing_visuals_visible(visible_flag)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null


func _resolve_visual_body_type() -> int:
	if visual_body_type != VisualBodyType.AUTO:
		return visual_body_type
	if body_archetype != null:
		var archetype_body_type := int(body_archetype.get("visual_body_type"))
		if archetype_body_type != VisualBodyType.NONE:
			return archetype_body_type
	return _infer_visual_body_type()


func _resolve_body_archetype() -> Resource:
	if body_archetype != null:
		return body_archetype
	var race := _get_character_race()
	match _resolve_visual_body_type():
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
	if character_race != null:
		return character_race
	if body_archetype != null and body_archetype.get("race") != null:
		return body_archetype.get("race") as Resource
	return HUMAN_RACE


func _infer_visual_body_type() -> int:
	var name_key := member_name.strip_edges().to_lower()
	if name_key.contains(" "):
		name_key = name_key.get_slice(" ", 0)
	if FEMALE_VISUAL_NAME_KEYS.has(name_key):
		return VisualBodyType.FEMALE
	return VisualBodyType.MALE


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


# Animation library setup/copy migrated to HumanoidBodyProjection in increment A1.


func _update_character_animation(delta: float) -> void:
	if _body == null or _body.get_primary_animation_player() == null:
		return
	if _is_combat_resolution_busy():
		return
	if _is_sitting:
		velocity = Vector3.ZERO
		_cancel_crouch_transition()
		_cancel_run_transition()
		_body.update_sitting_animation(delta, _should_use_sitting_talking_idle())
		return
	if not _has_move_target and _body.update_sitting_exit_animation(delta):
		return
	_body.cancel_sitting_exit_animation()
	if life_state != NpcRules.LifeState.ALIVE:
		_cancel_crouch_transition()
		_cancel_run_transition()
		return
	if _carried_by != null:
		_cancel_crouch_transition()
		_cancel_run_transition()
		_update_carried_pose_animation()
		return
	if _mining_active and _current_mining_node != null:
		_cancel_crouch_transition()
		_cancel_run_transition()
		_face_world_position(_current_mining_node.global_position)
		if _body.play_clip(MINING_ANIMATION_NAME):
			return
	var horizontal_speed := _get_horizontal_speed()
	var should_hold_combat_idle := _should_hold_combat_idle_animation()
	var is_moving := horizontal_speed > ACTUAL_LOCOMOTION_SPEED_THRESHOLD and (_has_move_target or _has_active_combat_target()) and not should_hold_combat_idle
	var wants_run_animation := is_running_enabled() and is_moving and not sneaking
	if _body.update_crouch_enter_animation(delta):
		return
	if _body.update_crouch_exit_animation(delta):
		return
	if _body.update_run_transition(delta, wants_run_animation):
		return
	if sneaking:
		if is_moving:
			_body.play_clip(CROUCH_WALK_ANIMATION_NAME, _get_animation_speed_ratio(horizontal_speed, move_speed * _get_sneak_move_speed_multiplier()))
		else:
			_body.play_clip(CROUCH_IDLE_ANIMATION_NAME)
		return
	if should_hold_combat_idle:
		_cancel_crouch_transition()
		_cancel_run_transition()
		if _play_combat_idle_animation_if_available():
			return
	if not is_moving:
		if _play_combat_idle_animation_if_available():
			return
		_body.update_idle_animation(delta, _should_use_tired_idle_animation())
		return
	if wants_run_animation:
		_body.play_clip(JOG_ANIMATION_NAME, _get_animation_speed_ratio(horizontal_speed, move_speed * NpcRules.RUN_SPEED_MULTIPLIER))
	else:
		_body.play_clip(WALK_ANIMATION_NAME, _get_animation_speed_ratio(horizontal_speed, move_speed))


func _get_animation_speed_ratio(horizontal_speed: float, reference_speed: float) -> float:
	return clampf(horizontal_speed / maxf(reference_speed, 0.001), 0.0, 1.0)


func _should_hold_combat_idle_animation() -> bool:
	var target := _get_active_combat_target()
	if target == null:
		return false
	if absf(target.global_position.y - global_position.y) > move_target_vertical_tolerance:
		return false
	return _horizontal_distance_to(target.global_position) <= get_attack_range() + COMBAT_RANGE_HYSTERESIS


func _play_combat_idle_animation_if_available() -> bool:
	if _body == null or _get_active_combat_target() == null:
		return false
	var animation_set = _get_current_combat_animation_set()
	var idle_animation_name := _get_current_combat_idle_animation_name(animation_set)
	if idle_animation_name.is_empty() or not _body.has_clip(idle_animation_name):
		return false
	return _body.play_clip(idle_animation_name)


func _get_current_combat_idle_animation_name(animation_set) -> String:
	if animation_set != null and str(animation_set.stance_id) == EquipmentGripProfile.GRIP_CLASS_ONE_HAND_MELEE:
		return str(animation_set.idle_animation_name)
	if _has_equipped_shield() and _body != null and _body.has_clip(SHIELD_COMBAT_IDLE_ANIMATION_NAME):
		return SHIELD_COMBAT_IDLE_ANIMATION_NAME
	if animation_set != null:
		return str(animation_set.idle_animation_name)
	return ""


func _should_use_tired_idle_animation() -> bool:
	return life_state == NpcRules.LifeState.ALIVE \
		and fatigue_stage == NpcRules.FatigueStage.EXHAUSTED \
		and _body != null \
		and _body.has_clip(TIRED_IDLE_ANIMATION_NAME)


func _play_random_idle_animation(force: bool) -> void:
	if _body != null:
		_body.play_random_idle_animation(force)


func _start_crouch_enter_animation() -> void:
	if _body != null:
		_body.start_crouch_enter_animation()


func _start_crouch_exit_animation() -> void:
	if _body != null:
		_body.start_crouch_exit_animation()


func _cancel_crouch_transition() -> void:
	if _body != null:
		_body.cancel_crouch_transition()


func _cancel_run_transition() -> void:
	if _body != null:
		_body.cancel_run_transition()


func _start_sitting_enter_animation() -> void:
	if _body != null:
		_body.start_sitting_enter_animation(_should_use_sitting_talking_idle())


func _start_sitting_exit_animation() -> void:
	if _body != null:
		_body.start_sitting_exit_animation()


func _should_use_sitting_talking_idle() -> bool:
	if _current_seat_target == null or not is_instance_valid(_current_seat_target):
		return false
	if player_party_member:
		return false
	if not _current_seat_target.has_method("should_use_sitting_talking_idle"):
		return false
	return bool(_current_seat_target.should_use_sitting_talking_idle(self))


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


func _set_order(order_type: int, issued_by_player: bool, preserve_seat: bool = false) -> bool:
	if _should_keep_active_combat_order(order_type, issued_by_player):
		return false
	var interaction = _interaction_capability
	if interaction == null:
		interaction = get_actor_capability(&"interaction")
	if interaction != null:
		interaction.clear_law_moves_for_order(order_type, issued_by_player)
	if issued_by_player and order_type != OrderType.ATTACK and _ai_brain != null:
		_ai_brain.clear_for_player_override()
	if issued_by_player and _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, true)
	_cancel_non_matching_assignments(order_type, preserve_seat)
	_current_order_type = int(order_type)
	_order_was_player_issued = issued_by_player
	if order_type != OrderType.MINE:
		_mining_active = false
		mining_changed.emit()
	if order_type != OrderType.SCAVENGE:
		_scavenging_active = false
		scavenging_changed.emit()
	return true


func _should_keep_active_combat_order(next_order_type: int, issued_by_player: bool) -> bool:
	if issued_by_player or next_order_type == OrderType.ATTACK:
		return false
	return _has_active_combat_target()


func _has_active_combat_target() -> bool:
	return life_state == NpcRules.LifeState.ALIVE and _get_active_combat_target() != null


func _get_active_combat_target() -> Node3D:
	if _current_order_type == OrderType.ATTACK and _is_valid_active_combat_target(_current_attack_target):
		return _current_attack_target
	if _ai_brain != null:
		var ai_target := _ai_brain.get_active_combat_target() as Node3D
		if _is_valid_active_combat_target(ai_target):
			return ai_target
	return null


func _is_valid_combat_target(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var target_life_state = target.get("life_state")
	if target_life_state == null or int(target_life_state) != NpcRules.LifeState.ALIVE:
		return false
	return not (target.has_method("is_protected_from_combat") and bool(target.call("is_protected_from_combat")))


func _is_valid_active_combat_target(target: Node3D) -> bool:
	return _is_valid_combat_target(target) and has_hostility_with(target) and can_see_actor_for_combat(target)


func _get_active_ai_job_type() -> int:
	return _ai_brain.get_active_job_type() if _ai_brain != null else AI_JOB_SCRIPT.JobType.NONE


func _is_active_ai_combat_player_issued() -> bool:
	return _ai_brain != null and _ai_brain.has_active_combat_job() and _ai_brain.is_active_job_player_issued()


func _clear_invalid_ai_job() -> void:
	if _ai_brain != null and _ai_brain.active_job != null and (not _ai_brain.active_job.is_valid_for(self) or (_ai_brain.active_job.is_combat() and not _is_valid_active_combat_target(_ai_brain.active_job.target))):
		_ai_brain.clear_active_job()
		if not _has_active_combat_target():
			COMBAT_COORDINATOR.clear_combat_target(self)
		_sync_active_combat_actor_group()


func _sync_active_combat_actor_group() -> void:
	var active_target := _get_active_combat_target()
	set_shared_combat_target(active_target)
	if active_target != null:
		add_to_group(ACTIVE_COMBAT_ACTOR_GROUP)
	else:
		remove_from_group(ACTIVE_COMBAT_ACTOR_GROUP)


func _cancel_non_matching_assignments(next_order_type: int, preserve_seat: bool = false) -> void:
	if next_order_type != OrderType.MINE:
		stop_mining_assignment()
	if next_order_type != OrderType.SCAVENGE:
		stop_scavenging_assignment()
	if next_order_type != OrderType.OPEN_CONTAINER:
		stop_container_interaction()
	if next_order_type != OrderType.TRADE:
		stop_trade_interaction()
	if next_order_type != OrderType.TALK:
		stop_conversation_interaction()
	if next_order_type != OrderType.ATTACK:
		stop_attack_assignment()
	if next_order_type != OrderType.HEAL:
		stop_heal_assignment()
	if next_order_type != OrderType.FINISH_OFF:
		stop_finish_off_assignment()
	if next_order_type != OrderType.CARRY:
		stop_carry_assignment()
	if next_order_type != OrderType.SLEEP:
		stop_sleep_assignment()
	if next_order_type != OrderType.PLACE_IN_BED:
		stop_place_in_bed_assignment()
	if next_order_type != OrderType.PLACE_IN_CELL:
		stop_place_in_cell_assignment()
	if next_order_type != OrderType.PLACE_IN_FURNACE:
		stop_place_in_furnace_assignment()
	if next_order_type != OrderType.SIT and not preserve_seat:
		stop_seat_assignment()
	if next_order_type != OrderType.PICKUP_ITEM:
		stop_pickup_assignment()


func _recalculate_vitals() -> void:
	hp = max_hp - get_total_wound_damage()
	if life_state == NpcRules.LifeState.DEAD:
		return
	var blood_death_threshold := get_blood_death_point()
	if blood <= blood_death_threshold:
		if _should_enter_dying_state_from_vitals():
			_enter_dying_state()
		else:
			_enter_recovery_coma_from_lethal_vitals()
		return
	if hp <= get_death_point(max_hp):
		if _should_enter_dying_state_from_vitals():
			_enter_dying_state()
		else:
			_enter_recovery_coma_from_lethal_vitals()
		return
	if hp <= get_coma_point(max_hp):
		_enter_recovery_coma_state()
		return
	if blood <= 0.0:
		if _is_getting_up:
			_cancel_get_up()
			_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, 5.0)
			_enter_downed_state(false)
		if life_state == NpcRules.LifeState.RECOVERY_COMA:
			return
		if life_state != NpcRules.LifeState.UNCONSCIOUS:
			_enter_unconscious_state()
		return
	if hp <= 0.0:
		if _is_getting_up:
			_cancel_get_up()
			_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, 5.0)
			_enter_downed_state(false)
		if life_state == NpcRules.LifeState.RECOVERY_COMA:
			return
		if life_state != NpcRules.LifeState.UNCONSCIOUS:
			_enter_unconscious_state()
		return
	_dying_timer_remaining = 0.0
	if _is_downed_recovery_locked():
		if is_recoverable_downed_state():
			_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, 0.5)
		return
	if is_in_cell_custody() and is_recoverable_downed_state() and _downed_recover_delay_remaining <= 0.0:
		_wake_in_cell()
		return
	if is_recoverable_downed_state() and _downed_recover_delay_remaining <= 0.0 and _carried_by == null:
		_begin_get_up()


func _should_enter_dead_state_from_vitals() -> bool:
	return true


func _should_enter_dying_state_from_vitals() -> bool:
	return _should_enter_dead_state_from_vitals()


func _is_downed_recovery_locked() -> bool:
	return false


func _enter_unconscious_from_lethal_vitals() -> void:
	_enter_recovery_coma_from_lethal_vitals()


func _enter_recovery_coma_from_lethal_vitals() -> void:
	if _is_getting_up:
		_cancel_get_up()
		_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, 5.0)
		_enter_downed_state(false)
	_enter_recovery_coma_state()


func _has_started_downed_state() -> bool:
	return _downed_is_settled \
		or _ragdoll_preroll_active \
		or _is_ragdoll_active \
		or _downed_collision_applied \
		or _carried_by != null \
		or is_in_cell_custody()


func _wake_in_cell() -> void:
	if not is_in_cell_custody() or not is_recoverable_downed_state():
		return
	var previous_state := life_state
	life_state = NpcRules.LifeState.ALIVE
	_dying_timer_remaining = 0.0
	_cancel_get_up()
	_cancel_ragdoll_preroll()
	_stop_ragdoll_simulation(true)
	_restore_downed_collision_shape()
	_clear_combat_resolution_state()
	COMBAT_COORDINATOR.release_character(self)
	var stand_position := _get_cell_custody_stand_position(get_cell_custody_target())
	if stand_position != Vector3.INF:
		global_position = stand_position
	velocity = Vector3.ZERO
	running = false
	_start_cell_wake_animation()
	life_state_changed.emit(previous_state, life_state)
	state_changed.emit()


func _get_cell_custody_stand_position(cell) -> Vector3:
	if cell != null and is_instance_valid(cell) and cell.has_method("get_prisoner_stand_position"):
		var stand_position: Variant = cell.call("get_prisoner_stand_position", self)
		if stand_position is Vector3:
			return stand_position
	return Vector3.INF


func _enter_unconscious_state() -> void:
	_enter_downed_life_state(NpcRules.LifeState.UNCONSCIOUS, 15.0, "Unconscious", Color(1.0, 0.85, 0.45, 1.0))


func _enter_recovery_coma_state() -> void:
	_enter_downed_life_state(NpcRules.LifeState.RECOVERY_COMA, 15.0, "Recovery Coma", Color(1.0, 0.58, 0.28, 1.0))


func _enter_dying_state() -> void:
	if life_state != NpcRules.LifeState.DYING:
		_dying_timer_remaining = maxf(_dying_timer_remaining, get_dying_seconds())
	_enter_downed_life_state(NpcRules.LifeState.DYING, 15.0, "Dying", Color(1.0, 0.24, 0.18, 1.0))


func _enter_downed_life_state(next_life_state: int, recover_delay: float, notice: String, notice_color: Color) -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	var previous_state := life_state
	var was_downed := is_downed_state()
	if previous_state == next_life_state:
		_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, recover_delay)
		if not _has_started_downed_state():
			_enter_downed_state(false)
		return
	life_state = next_life_state
	_cancel_get_up()
	COMBAT_COORDINATOR.release_character(self)
	running = false
	_clear_actor_move_target()
	if not was_downed:
		_downed_is_settled = false
		if previous_state != NpcRules.LifeState.ASLEEP:
			_clear_all_active_orders()
		if _carried_character != null:
			drop_carried_character()
		if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
			_active_job_provider.pause_worker_job(self, false)
	_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, recover_delay)
	if not _has_started_downed_state():
		_enter_downed_state(false)
	_show_world_notice(notice, notice_color)
	life_state_changed.emit(previous_state, life_state)
	state_changed.emit()


func _enter_dead_state() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	_report_murder_crime_if_needed()
	var previous_state := life_state
	life_state = NpcRules.LifeState.DEAD
	_dying_timer_remaining = 0.0
	_notify_law_order_actor_death()
	_cancel_get_up()
	COMBAT_COORDINATOR.release_character(self)
	running = false
	_clear_actor_move_target()
	_downed_is_settled = false
	_clear_all_active_orders()
	if _carried_character != null:
		drop_carried_character()
	if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, false)
	_enter_downed_state(true)
	_show_world_notice("Dead", Color(1.0, 0.2, 0.2, 1.0))
	velocity = Vector3.ZERO
	life_state_changed.emit(previous_state, life_state)
	died.emit(self)
	state_changed.emit()


func _award_combat_attack_xp() -> void:
	var skill_id := _get_current_weapon_skill_id()
	add_skill_xp(skill_id, COMBAT_ATTACK_SKILL_XP, "combat_attack")
	add_skill_xp(SkillRules.ATTRIBUTE_DEXTERITY, COMBAT_ATTACK_SKILL_XP * 0.01, "weapon_attack")
	match skill_id:
		SkillRules.COMBAT_DAGGERS:
			add_skill_xp(SkillRules.ATTRIBUTE_DEXTERITY, COMBAT_ATTACK_SKILL_XP * 0.12, "finesse_attack")
		SkillRules.COMBAT_AXES_ONE_HANDED:
			add_skill_xp(SkillRules.ATTRIBUTE_STRENGTH, COMBAT_ATTACK_SKILL_XP * 0.08, "axe_attack")
		SkillRules.COMBAT_UNARMED:
			add_skill_xp(SkillRules.ATTRIBUTE_STRENGTH, COMBAT_ATTACK_SKILL_XP * 0.04, "unarmed_attack")
		_:
			add_skill_xp(SkillRules.ATTRIBUTE_DEXTERITY, COMBAT_ATTACK_SKILL_XP * 0.025, "weapon_attack")


func get_combat_weapon_item() -> ItemDefinition:
	return get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON)


func get_combat_offhand_item() -> ItemDefinition:
	return get_equipped_item(ItemDefinition.EQUIP_SLOT_OFFHAND)


func has_combat_shield() -> bool:
	return _has_equipped_shield()


func get_combat_weapon_skill_id() -> String:
	return _get_current_weapon_skill_id()


func get_body_weapon_damage_profile() -> Dictionary:
	var race := _get_character_race()
	var race_id := str(race.get("race_id")).strip_edges().to_lower() if race != null else ""
	if race_id == "rustdead":
		return {"blunt_base": 2.5, "cut_base": 2.5}
	return super.get_body_weapon_damage_profile()


func _get_current_weapon_skill_id() -> String:
	var weapon_item = get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON)
	if not (weapon_item is ItemDefinition):
		return SkillRules.COMBAT_UNARMED
	var item := weapon_item as ItemDefinition
	var descriptor := "%s %s" % [item.display_name.to_lower(), item.resource_path.to_lower()]
	if descriptor.contains("dagger"):
		return SkillRules.COMBAT_DAGGERS
	if descriptor.contains("axe"):
		return SkillRules.COMBAT_AXES_ONE_HANDED
	if descriptor.contains("sword"):
		return SkillRules.COMBAT_SWORDS_ONE_HANDED
	return SkillRules.COMBAT_SWORDS_ONE_HANDED


func _award_toughness_xp(real_damage: float) -> void:
	if real_damage <= 0.0:
		return
	add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, real_damage * TOUGHNESS_DAMAGE_XP_MULTIPLIER, "damage_taken")


func _get_base_stat_value(stat_name: String) -> float:
	match stat_name:
		"attack_damage":
			return base_attack_damage
		"attack_range":
			return attack_range
		"strength":
			return float(get_skill_level(SkillRules.ATTRIBUTE_STRENGTH))
		"dexterity":
			return float(get_skill_level(SkillRules.ATTRIBUTE_DEXTERITY))
		"toughness":
			return float(get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS))
		"perception":
			return float(get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION))
		"stealth":
			return float(get_skill_level(SkillRules.SUBTERFUGE_SNEAKING))
		"attack_cooldown":
			return attack_cooldown_seconds
		"cut_ratio":
			return attack_cut_ratio
		"dodge_chance":
			return base_dodge_chance + SkillRules.get_diminishing_bonus(float(get_skill_level(SkillRules.ATTRIBUTE_DEXTERITY)), 0.18, 45.0)
		"block_chance":
			return base_block_chance
		"block_damage_multiplier":
			return block_damage_multiplier
		"weapon_parry_bonus", "shield_block_bonus":
			return 0.0
		"move_speed_multiplier":
			return 1.0
		"run_speed_multiplier":
			return NpcRules.RUN_SPEED_MULTIPLIER + SkillRules.get_diminishing_bonus(float(get_skill_level(SkillRules.MOVEMENT_RUNNING)), 0.42, 55.0)
		"hunger_drain_rate":
			var endurance_hunger_reduction := SkillRules.get_diminishing_bonus(float(get_skill_level(SkillRules.ATTRIBUTE_ENDURANCE)), 0.16, 65.0)
			return hunger_drain_rate * (1.0 - endurance_hunger_reduction)
		"fatigue_recovery_rate":
			return NpcRules.FATIGUE_IDLE_RECOVERY + SkillRules.get_diminishing_bonus(float(get_skill_level(SkillRules.ATTRIBUTE_ENDURANCE)), 0.9, 60.0)
		"healing_rate":
			return NpcRules.BASE_HEAL_RATE
		"blood_recovery_rate":
			return NpcRules.BLOOD_RECOVERY_RATE
	return 0.0


func _collect_stat_modifiers() -> Array:
	var modifiers: Array = []
	NpcRules.append_stage_modifiers(modifiers, get_hunger_stage(), get_fatigue_stage(), _current_open_cut_damage, max_hp)
	if running and (_has_move_target or _has_active_combat_target()):
		modifiers.append({"stat": "move_speed_multiplier", "mul": _get_base_stat_value("run_speed_multiplier")})
	if sneaking:
		modifiers.append({"stat": "move_speed_multiplier", "mul": _get_sneak_move_speed_multiplier()})
	if is_carrying_someone():
		modifiers.append({"stat": "move_speed_multiplier", "mul": carry_move_speed_multiplier})
	modifiers.append_array(get_equipment_stat_modifiers())
	return modifiers


func _get_sneak_move_speed_multiplier() -> float:
	var sneak_level := float(get_skill_level(SkillRules.SUBTERFUGE_SNEAKING))
	var ratio := clampf((sneak_level - float(SkillRules.DEFAULT_LEVEL)) / maxf(SNEAK_MOVE_SPEED_MASTER_LEVEL - float(SkillRules.DEFAULT_LEVEL), 0.001), 0.0, 1.0)
	var mastery := pow(ratio, SNEAK_MOVE_SPEED_CURVE)
	return lerpf(SNEAK_MOVE_SPEED_MIN_MULTIPLIER, SNEAK_MOVE_SPEED_MAX_MULTIPLIER, mastery)


func get_stat_value(stat_name: String, include_secondary_modifiers: bool = true) -> float:
	var cache_frame := Engine.get_physics_frames()
	if _stat_value_cache_frame != cache_frame:
		_stat_value_cache_frame = cache_frame
		_stat_value_cache.clear()
	var cache_key := stat_name if include_secondary_modifiers else stat_name + "|base"
	if _stat_value_cache.has(cache_key):
		return float(_stat_value_cache[cache_key])
	var value := _get_base_stat_value(stat_name)
	var additive := 0.0
	var multiplier := 1.0
	for modifier in _collect_stat_modifiers():
		if modifier.get("stat", "") != stat_name:
			continue
		additive += modifier.get("add", 0.0)
		multiplier *= modifier.get("mul", 1.0)
	value = (value + additive) * multiplier
	if include_secondary_modifiers:
		match stat_name:
			"dodge_chance", "block_chance", "cut_ratio":
				value = clampf(value, 0.0, 0.95)
			"block_damage_multiplier":
				value = clampf(value, 0.0, 1.0)
			"attack_cooldown":
				value = maxf(0.2, value)
			"move_speed_multiplier", "run_speed_multiplier", "attack_damage", "attack_range", "strength", "dexterity", "toughness", "perception", "stealth", "hunger_drain_rate", "fatigue_recovery_rate", "healing_rate", "blood_recovery_rate", "weapon_parry_bonus", "shield_block_bonus":
				value = maxf(0.0, value)
	_stat_value_cache[cache_key] = value
	return value


func _invalidate_stat_value_cache() -> void:
	_stat_value_cache_frame = -1
	_stat_value_cache.clear()


func _get_current_move_speed() -> float:
	return move_speed * get_stat_value("move_speed_multiplier")


func _get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _is_actual_locomotion_active() -> bool:
	if life_state != NpcRules.LifeState.ALIVE or _is_sitting or _carried_by != null:
		return false
	return _get_horizontal_speed() > ACTUAL_LOCOMOTION_SPEED_THRESHOLD


func _spend_fatigue(amount: float) -> void:
	if not fatigue_enabled or amount <= 0.0:
		return
	_apply_fatigue_delta(-amount)


func _should_consider_combat_retarget() -> bool:
	var targeting = _get_ai_targeting_capability()
	return targeting.should_consider_combat_retarget() if targeting != null else false


func _try_reconfigure_close_combat_target() -> bool:
	var targeting = _get_ai_targeting_capability()
	return targeting.try_reconfigure_close_combat_target() if targeting != null else false


func _should_keep_current_target_over_close_hostile(active_target: Node, close_target: Node) -> bool:
	var targeting = _get_ai_targeting_capability()
	return targeting.should_keep_current_target_over_close_hostile(active_target, close_target) if targeting != null else false


func _get_close_hostile_retarget_radius() -> float:
	return _get_effective_combat_attack_range() + 0.65


func _should_seek_auto_heal_target() -> bool:
	if not auto_heal_enabled or life_state != NpcRules.LifeState.ALIVE:
		return false
	if _current_order_type == OrderType.HEAL:
		return false
	if _order_was_player_issued and _current_order_type != OrderType.NONE:
		return false
	if _carried_by != null or is_carrying_someone() or _is_sitting:
		return false
	return _get_best_bandage_definition() != null


func _find_auto_heal_target() -> HumanoidCharacter:
	var scan_radius := maxf(assist_scan_radius, interact_distance)
	var best_target: HumanoidCharacter
	var best_score := -INF
	if can_bandage_target(self):
		best_target = self
		best_score = _get_auto_heal_priority(self, 0.0)
	if faction_name.is_empty():
		return best_target
	for node in _get_query_humanoids(global_position, scan_radius, true):
		if not (node is HumanoidCharacter):
			continue
		var candidate: HumanoidCharacter = node
		if candidate == self or not is_instance_valid(candidate):
			continue
		if candidate.faction_name != faction_name:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance > scan_radius:
			continue
		if not can_bandage_target(candidate):
			continue
		var score := _get_auto_heal_priority(candidate, distance)
		if score > best_score:
			best_score = score
			best_target = candidate
	return best_target


func _get_auto_heal_priority(target: HumanoidCharacter, distance: float) -> float:
	var priority := target.get_total_wound_damage()
	priority += target.get_open_cut_damage() * 2.0
	priority += target.get_bleed_rate() * 75.0
	if target.is_downed_state():
		priority += 50.0
	return priority - distance * 0.1


func _try_assign_auto_burn_action() -> bool:
	if not _can_consider_auto_burn():
		return false
	var carried := get_carried_character()
	if carried != null and is_instance_valid(carried):
		return _try_assign_carried_body_to_furnace(carried)
	var furnace = _get_accessible_auto_burn_furnace()
	var has_flask := can_use_cinder_flask()
	if furnace == null and not has_flask:
		_set_auto_burn_backoff(auto_burn_no_resource_backoff_seconds)
		return false
	var target := _find_auto_burn_rustdead_target(furnace != null)
	if target == null:
		_set_auto_burn_backoff(auto_burn_no_target_backoff_seconds)
		return false
	if furnace != null:
		if not _reserve_auto_burn_target(target):
			return false
		if furnace.has_method("reserve_for") and not bool(furnace.call("reserve_for", self, target)):
			_release_auto_burn_target_reservation()
			_set_auto_burn_backoff(auto_burn_failed_backoff_seconds)
			return false
		_auto_burn_reserved_furnace = furnace
		assign_carry_target(target, false)
		if _current_carry_target == target:
			return true
		_release_auto_burn_reservations()
		_set_auto_burn_backoff(auto_burn_failed_backoff_seconds)
		return false
	if not _reserve_auto_burn_target(target):
		return false
	assign_finish_off_target(target, false)
	if _current_finish_off_target == target:
		return true
	_release_auto_burn_target_reservation()
	_set_auto_burn_backoff(auto_burn_failed_backoff_seconds)
	return false


func _can_consider_auto_burn() -> bool:
	if not auto_burn_rustdead_enabled or life_state != NpcRules.LifeState.ALIVE:
		return false
	if _carried_by != null or _is_sitting:
		return false
	if _get_active_combat_target() != null:
		return false
	if _current_order_type != OrderType.NONE:
		return false
	return Time.get_ticks_msec() >= _auto_burn_next_scan_msec


func _try_assign_carried_body_to_furnace(carried: HumanoidCharacter) -> bool:
	if not (carried.has_method("requires_fire_to_die") and bool(carried.call("requires_fire_to_die"))):
		_set_auto_burn_backoff(auto_burn_failed_backoff_seconds)
		return false
	var furnace = _get_accessible_auto_burn_furnace(carried)
	if furnace == null:
		_set_auto_burn_backoff(auto_burn_no_resource_backoff_seconds)
		return false
	assign_place_carried_in_furnace_target(furnace, false)
	if _current_place_furnace_target == furnace:
		return true
	_set_auto_burn_backoff(auto_burn_failed_backoff_seconds)
	return false


func _find_auto_burn_rustdead_target(has_furnace: bool) -> HumanoidCharacter:
	if not is_inside_tree():
		return null
	var scan_radius := maxf(maxf(auto_burn_target_scan_radius, assist_scan_radius), interact_distance)
	var scan_radius_squared := scan_radius * scan_radius
	var best_target: HumanoidCharacter
	var best_score := INF
	for node in get_tree().get_nodes_in_group("npc_character"):
		var candidate := node as HumanoidCharacter
		if candidate == null or candidate == self or not is_instance_valid(candidate):
			continue
		if not candidate.has_method("requires_fire_to_die") or not bool(candidate.call("requires_fire_to_die")):
			continue
		if candidate.has_method("is_fire_destruction_in_progress") and bool(candidate.call("is_fire_destruction_in_progress")):
			continue
		if candidate.is_carried() or _is_auto_burn_target_reserved_by_other(candidate):
			continue
		if has_furnace:
			if not candidate.is_downed_state() and candidate.life_state != NpcRules.LifeState.DEAD:
				continue
		else:
			if not candidate.can_be_destroyed_by_cinder():
				continue
		var distance_squared := global_position.distance_squared_to(candidate.global_position)
		if distance_squared > scan_radius_squared:
			continue
		if distance_squared < best_score:
			best_score = distance_squared
			best_target = candidate
	return best_target


func _get_accessible_auto_burn_furnace(body: HumanoidCharacter = null):
	var now := Time.get_ticks_msec()
	if _is_furnace_accessible(_auto_burn_reserved_furnace, body):
		return _auto_burn_reserved_furnace
	if now < _auto_burn_cached_furnace_until_msec:
		if _auto_burn_cached_furnace == null:
			return null
		if _is_furnace_accessible(_auto_burn_cached_furnace, body):
			return _auto_burn_cached_furnace
	_auto_burn_cached_furnace = null
	if not is_inside_tree():
		return null
	var best_furnace
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("body_furnace"):
		if not _is_furnace_accessible(node, body):
			continue
		var furnace_position := (node as Node3D).global_position if node is Node3D else global_position
		var distance_squared := global_position.distance_squared_to(furnace_position)
		if distance_squared < best_distance:
			best_distance = distance_squared
			best_furnace = node
	_auto_burn_cached_furnace = best_furnace
	_auto_burn_cached_furnace_until_msec = now + (3000 if best_furnace != null else 1500)
	return best_furnace


func _is_furnace_accessible(furnace, body: HumanoidCharacter = null) -> bool:
	if furnace == null or not is_instance_valid(furnace):
		return false
	if not (furnace is Node3D):
		return false
	var access_radius := maxf(auto_burn_furnace_access_radius, interact_distance)
	if global_position.distance_squared_to((furnace as Node3D).global_position) > access_radius * access_radius:
		return false
	if furnace.has_method("is_available_for") and not bool(furnace.call("is_available_for", self, body)):
		return false
	if body != null and furnace.has_method("can_accept_body") and not bool(furnace.call("can_accept_body", body)):
		return false
	return true


func _reserve_auto_burn_target(target: HumanoidCharacter) -> bool:
	if target == null or not is_instance_valid(target) or _is_auto_burn_target_reserved_by_other(target):
		return false
	target.set_meta(AUTO_BURN_TARGET_RESERVED_BY_META, get_instance_id())
	target.set_meta(AUTO_BURN_TARGET_RESERVED_UNTIL_META, Time.get_ticks_msec() + 15000)
	_auto_burn_reserved_target = target
	return true


func _is_auto_burn_target_reserved_by_other(target: HumanoidCharacter) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var reserved_until := int(target.get_meta(AUTO_BURN_TARGET_RESERVED_UNTIL_META, 0))
	if reserved_until <= Time.get_ticks_msec():
		if target.has_meta(AUTO_BURN_TARGET_RESERVED_BY_META):
			target.remove_meta(AUTO_BURN_TARGET_RESERVED_BY_META)
		if target.has_meta(AUTO_BURN_TARGET_RESERVED_UNTIL_META):
			target.remove_meta(AUTO_BURN_TARGET_RESERVED_UNTIL_META)
		return false
	return int(target.get_meta(AUTO_BURN_TARGET_RESERVED_BY_META, 0)) != get_instance_id()


func _release_auto_burn_target_reservation() -> void:
	if _auto_burn_reserved_target != null and is_instance_valid(_auto_burn_reserved_target):
		if int(_auto_burn_reserved_target.get_meta(AUTO_BURN_TARGET_RESERVED_BY_META, 0)) == get_instance_id():
			if _auto_burn_reserved_target.has_meta(AUTO_BURN_TARGET_RESERVED_BY_META):
				_auto_burn_reserved_target.remove_meta(AUTO_BURN_TARGET_RESERVED_BY_META)
			if _auto_burn_reserved_target.has_meta(AUTO_BURN_TARGET_RESERVED_UNTIL_META):
				_auto_burn_reserved_target.remove_meta(AUTO_BURN_TARGET_RESERVED_UNTIL_META)
	_auto_burn_reserved_target = null


func _release_auto_burn_furnace_reservation() -> void:
	if _auto_burn_reserved_furnace != null and is_instance_valid(_auto_burn_reserved_furnace) and _auto_burn_reserved_furnace.has_method("release_reservation"):
		_auto_burn_reserved_furnace.call("release_reservation", self, null)
	_auto_burn_reserved_furnace = null


func _release_auto_burn_reservations() -> void:
	_release_auto_burn_target_reservation()
	_release_auto_burn_furnace_reservation()


func _release_place_furnace_reservation() -> void:
	var interaction = _get_interaction_capability()
	if interaction != null:
		interaction.release_place_furnace_reservation()


func _set_auto_burn_backoff(seconds: float) -> void:
	_auto_burn_next_scan_msec = Time.get_ticks_msec() + int(maxf(seconds, 0.0) * 1000.0)


func _append_bounded_nearest_candidate(entries: Array, candidate: HumanoidCharacter, distance_squared: float, max_count: int) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.append_bounded_nearest_candidate(entries, candidate, distance_squared, max_count)


func _candidate_entries_to_humanoids(entries: Array) -> Array[HumanoidCharacter]:
	var result: Array[HumanoidCharacter] = []
	var targeting = _get_ai_targeting_capability()
	var targets: Array = targeting.candidate_entries_to_actors(entries) if targeting != null else []
	for target_value in targets:
		var target := target_value as HumanoidCharacter
		if target != null and is_instance_valid(target):
			result.append(target)
	return result


func _get_query_humanoids(query_position: Vector3 = Vector3.ZERO, radius := -1.0, include_party := true) -> Array:
	# TODO(actor-decoupling): this now returns actors, not just humanoids; rename callers after the robot combat path is stable.
	var targeting = _get_ai_targeting_capability()
	return targeting.get_query_actors(query_position, radius, include_party) if targeting != null else []


func _get_query_humanoids_limited(query_position: Vector3, radius: float, max_count: int, include_party := true) -> Array:
	var targeting = _get_ai_targeting_capability()
	return targeting.get_query_actors_limited(query_position, radius, max_count, include_party) if targeting != null else []


func _should_seek_combat_target() -> bool:
	var targeting = _get_ai_targeting_capability()
	return targeting.should_seek_combat_target() if targeting != null else false


func _find_ai_target() -> Node3D:
	var targeting = _get_ai_targeting_capability()
	if targeting == null:
		return null
	return targeting.find_ai_target() as Node3D


func _get_last_direct_attacker_target() -> Node3D:
	var targeting = _get_ai_targeting_capability()
	if targeting == null:
		return null
	return targeting.get_last_direct_attacker_target() as Node3D


func _find_defensive_assist_target() -> Node3D:
	var targeting = _get_ai_targeting_capability()
	if targeting == null:
		return null
	return targeting.find_defensive_assist_target() as Node3D


func _should_defend_ally(ally: Node) -> bool:
	var ally_target: Node3D = null
	if ally != null and ally.has_method("get_current_combat_target"):
		ally_target = ally.call("get_current_combat_target") as Node3D
	return _should_help_against(ally, ally_target, true)


func _should_help_against(protected_actor, threat, allow_public_intervention: bool) -> bool:
	if protected_actor == null or threat == null or threat == self:
		return false
	if not _is_alive_combat_actor(protected_actor) or not _is_alive_combat_actor(threat):
		return false
	if _is_actor_protected_from_combat(protected_actor):
		return false
	if _is_law_arrest_against(protected_actor, threat):
		return false
	if _actors_have_hostility(self, protected_actor):
		return false
	var can_witness := _can_witness_combat(protected_actor, threat)
	if _can_squad_assist_actor(protected_actor):
		return true
	if not can_witness:
		return false
	if _are_party_allies(protected_actor):
		return true
	if _actors_have_hostility(self, threat):
		return true
	return allow_public_intervention and _is_public_order_defender()


func _is_law_arrest_against(protected_actor, threat) -> bool:
	return protected_actor is HumanoidCharacter and threat != null and threat.has_method("is_law_arresting") and bool(threat.call("is_law_arresting", protected_actor))


func _are_party_allies(other) -> bool:
	return other != null and player_party_member and _get_actor_bool_property(other, "player_party_member")


func _can_squad_assist_actor(protected_actor) -> bool:
	if not _are_squad_allies(protected_actor):
		return false
	var assist_radius := _get_combat_squad_assist_radius()
	if assist_radius <= 0.0:
		return false
	var protected_position = _get_combat_actor_position(protected_actor)
	return protected_position is Vector3 and global_position.distance_to(protected_position) <= assist_radius


func _are_squad_allies(other) -> bool:
	var own_squad := _get_actor_squad_key(self)
	return not own_squad.is_empty() and own_squad == _get_actor_squad_key(other)


func _get_actor_squad_key(actor) -> String:
	var world_squad := _get_actor_string_property(actor, "world_squad_id")
	if _is_meaningful_squad_key(world_squad):
		return world_squad
	var squad := _get_actor_string_property(actor, "squad_name")
	return squad if _is_meaningful_squad_key(squad) else ""


func _is_meaningful_squad_key(value: String) -> bool:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return false
	var lower := normalized.to_lower()
	return lower != "default" and lower != "none"


func _get_actor_bool_property(actor, property_name: String) -> bool:
	if actor == null:
		return false
	var value = actor.get(property_name)
	return bool(value) if value != null else false


func _is_alive_combat_actor(actor) -> bool:
	if actor == null or not is_instance_valid(actor) or not (actor is Node3D):
		return false
	var life_state_value = actor.get("life_state")
	return life_state_value != null and int(life_state_value) == NpcRules.LifeState.ALIVE


func _is_actor_protected_from_combat(actor) -> bool:
	return actor != null and actor.has_method("is_protected_from_combat") and bool(actor.call("is_protected_from_combat"))


func _actors_have_hostility(actor_a, actor_b) -> bool:
	if actor_a == null or actor_b == null:
		return false
	if actor_a.has_method("has_hostility_with"):
		return bool(actor_a.call("has_hostility_with", actor_b))
	return false


func _is_public_order_defender() -> bool:
	if is_faction_soldier():
		return true
	if is_in_group(COMBAT_INTERVENTION_STAFF_GROUP):
		return true
	return false


func _is_authority_guard_role() -> bool:
	return is_faction_soldier()


func _get_combat_witness_radius() -> float:
	return maxf(assist_scan_radius, combat_witness_radius)


func _get_combat_squad_assist_radius() -> float:
	return maxf(combat_squad_assist_radius, 0.0)


func _get_defensive_assist_notify_radius() -> float:
	return maxf(_get_combat_witness_radius(), _get_combat_squad_assist_radius())


func _get_combat_switch_radius() -> float:
	return maxf(maxf(assist_scan_radius, aggressive_scan_radius), combat_witness_radius)


func _can_witness_combat(protected_actor, threat) -> bool:
	var witness_radius := _get_combat_witness_radius()
	var protected_position = _get_combat_actor_position(protected_actor)
	if protected_position is Vector3 and global_position.distance_to(protected_position) <= witness_radius:
		return true
	var threat_position = _get_combat_actor_position(threat)
	return threat_position is Vector3 and global_position.distance_to(threat_position) <= witness_radius


func _get_combat_actor_position(actor):
	if actor is Node3D:
		return (actor as Node3D).global_position
	return null


func _find_nearest_hostile(scan_radius: float) -> Node3D:
	var targeting = _get_ai_targeting_capability()
	if targeting == null:
		return null
	return targeting.find_nearest_hostile(scan_radius) as Node3D


func _find_closest_hostile(scan_radius: float, same_level_only: bool = true) -> Node3D:
	var targeting = _get_ai_targeting_capability()
	if targeting == null:
		return null
	return targeting.find_closest_hostile(scan_radius, same_level_only) as Node3D


func _try_start_self_defense(attacker: Node) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.try_start_self_defense(attacker)


func _should_keep_active_target_against_self_defense(attacker: Node) -> bool:
	var targeting = _get_ai_targeting_capability()
	return targeting.should_keep_active_target_against_self_defense(attacker) if targeting != null else false


func _clear_combat_target_for_direct_self_defense() -> void:
	if _ai_brain != null and _ai_brain.has_active_combat_job():
		_ai_brain.clear_combat_job()
	_current_attack_target = null
	_clear_combat_movement_state()
	COMBAT_COORDINATOR.clear_combat_target(self)
	if _current_order_type == OrderType.ATTACK:
		_current_order_type = OrderType.NONE
	_sync_active_combat_actor_group()


func _notify_defensive_allies_of_attack(attacker: Node) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.notify_defensive_allies_of_attack(attacker)


func _notify_defensive_allies_of_engagement(target: Node) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.notify_defensive_allies_of_engagement(target)


func _respond_to_ally_under_attack(ally, attacker, support_targets: Array = []) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.respond_to_ally_under_attack(ally, attacker, support_targets)


func _respond_to_ally_engagement(ally, target, support_targets: Array = []) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.respond_to_ally_engagement(ally, target, support_targets)


func _get_support_target_candidates(primary_target: Node, radius: float) -> Array:
	var candidates: Array = []
	var targeting = _get_ai_targeting_capability()
	var target_candidates: Array = targeting.get_support_target_candidates(primary_target, radius) if targeting != null else []
	for target_value in target_candidates:
		var target := target_value as Node3D
		if target != null:
			candidates.append(target)
	return candidates


func _choose_support_target(primary_target, candidates: Array, scan_radius: float) -> Node3D:
	var targeting = _get_ai_targeting_capability()
	if targeting == null:
		return null
	return targeting.choose_support_target(primary_target, candidates, scan_radius) as Node3D


func _join_defense_against(threat: Node) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.join_defense_against(threat)


func _should_abandon_attack_chase() -> bool:
	if _is_active_ai_combat_player_issued() or _ai_brain != null and _ai_brain.has_active_combat_job():
		return false
	if _current_attack_target == null or not is_instance_valid(_current_attack_target):
		return false
	var leash := maxf(combat_chase_leash_distance, get_attack_range() + 1.0)
	if global_position.distance_to(_attack_origin_position) > leash:
		return true
	return _current_attack_target.global_position.distance_to(_attack_origin_position) > leash


func _is_player_order_to_avoid_combat() -> bool:
	return _has_active_player_order()


func _has_active_player_order() -> bool:
	return _order_was_player_issued and _current_order_type != OrderType.NONE


func _is_player_attack_order_for(target: Node) -> bool:
	return target != null and _order_was_player_issued and _current_order_type == OrderType.ATTACK and _current_attack_target == target


func respond_to_settlement_alarm(attacker: Node, alarm_town: Node, victim: Node = null) -> void:
	_respond_to_settlement_alarm(victim, attacker, alarm_town)


func _notify_settlement_alarm_of_attack(attacker: Node) -> void:
	var alarm_town := _find_alarm_town_for_attack(attacker)
	if alarm_town == null or not _should_attack_raise_settlement_alarm(attacker, alarm_town):
		return
	for node in _get_query_humanoids(global_position, _get_combat_witness_radius() + NpcRules.RAID_ALARM_APPROACH_RANGE, true):
		# TODO(actor-decoupling): settlement alarm responders are still humanoid-only; move this to a responder capability.
		if not (node is HumanoidCharacter):
			continue
		var responder: HumanoidCharacter = node
		if responder == self or responder == attacker:
			continue
		responder._respond_to_settlement_alarm(self, attacker, alarm_town)


func _respond_to_settlement_alarm(victim: Node, attacker: Node, alarm_town: Node) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker == self:
		return
	var attacker_life_state = attacker.get("life_state")
	if attacker_life_state == null or int(attacker_life_state) != NpcRules.LifeState.ALIVE or life_state != NpcRules.LifeState.ALIVE:
		return
	if combat_stance == NpcRules.CombatStance.PASSIVE:
		return
	if not _should_answer_settlement_alarm(victim, attacker, alarm_town):
		return
	_join_defense_against(attacker)


func _find_alarm_town_for_attack(attacker: Node) -> Node:
	var town := _get_owning_settlement_town(self)
	if town != null:
		return town
	town = _get_containing_settlement_town(global_position)
	if town != null:
		return town
	var attacker_node := attacker as Node3D
	return _get_containing_settlement_town(attacker_node.global_position) if attacker_node != null else null


func _should_attack_raise_settlement_alarm(attacker: Node, alarm_town: Node) -> bool:
	if attacker == null or alarm_town == null:
		return false
	var town_faction := _get_settlement_faction_id(alarm_town)
	if town_faction.is_empty() or not _is_actor_hostile_to_faction(attacker, town_faction):
		return false
	return _is_actor_in_or_attached_to_town(self, alarm_town) or _is_actor_in_or_attached_to_town(attacker, alarm_town)


func _should_answer_settlement_alarm(victim: Node, attacker: Node, alarm_town: Node) -> bool:
	if alarm_town == null or not _is_actor_in_or_attached_to_town(self, alarm_town):
		return false
	var town_faction := _get_settlement_faction_id(alarm_town)
	if town_faction.is_empty() or not _is_actor_hostile_to_faction(attacker, town_faction):
		return false
	if victim != null and has_hostility_with(victim):
		return false
	if is_faction_soldier():
		return true
	if player_party_member or faction_name == "Player":
		return _should_player_help_settlement_faction(town_faction)
	if has_hostility_with(attacker):
		return true
	return _is_public_order_defender()


func _should_player_help_settlement_faction(town_faction: String) -> bool:
	if town_faction.is_empty() or not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group("faction_controller"):
		if node.has_method("should_player_help_faction"):
			return bool(node.call("should_player_help_faction", town_faction))
	return false


func _record_player_combat_reputation(threat: Node) -> void:
	if threat == null or not is_inside_tree():
		return
	var threat_faction := _get_actor_string_property(threat, "faction_name")
	var threat_is_party := _get_actor_bool_property(threat, "player_party_member")
	var opposed_faction := ""
	if player_party_member and threat_faction != faction_name:
		opposed_faction = threat_faction
	elif threat_is_party and not faction_name.is_empty() and faction_name != threat_faction:
		opposed_faction = faction_name
	if opposed_faction.is_empty():
		return
	var record_key := opposed_faction
	if _combat_reputation_recorded.has(record_key):
		return
	_combat_reputation_recorded[record_key] = true
	for node in get_tree().get_nodes_in_group("faction_controller"):
		if node.has_method("record_player_combat_against"):
			node.call("record_player_combat_against", opposed_faction, -1)
			return


func _get_owning_settlement_town(node: Node) -> Node:
	var current := node
	while current != null:
		if current.is_in_group("settlement_town"):
			return current
		current = current.get_parent()
	return null


func _get_containing_settlement_town(world_position: Vector3) -> Node:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("settlement_town"):
		if node.has_method("contains_town_border_position") and bool(node.call("contains_town_border_position", world_position)):
			return node
	return null


func _get_settlement_faction_id(alarm_town: Node) -> String:
	if alarm_town == null:
		return ""
	var definition = alarm_town.get("settlement_definition")
	if definition != null and definition.has_method("get_faction_id"):
		return str(definition.call("get_faction_id"))
	return ""


func _is_actor_in_or_attached_to_town(actor: Node, alarm_town: Node) -> bool:
	if actor == null or alarm_town == null:
		return false
	if _is_node_descendant_of(actor, alarm_town):
		return true
	var actor_node := actor as Node3D
	return actor_node != null and alarm_town.has_method("contains_town_border_position") and bool(alarm_town.call("contains_town_border_position", actor_node.global_position))


func _is_node_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _clear_all_active_orders() -> void:
	stop_mining_assignment()
	stop_scavenging_assignment()
	stop_container_interaction()
	stop_trade_interaction()
	stop_conversation_interaction()
	stop_attack_assignment()
	stop_heal_assignment()
	stop_finish_off_assignment()
	stop_carry_assignment()
	stop_sleep_assignment()
	stop_place_in_bed_assignment()
	stop_place_in_cell_assignment()
	stop_place_in_furnace_assignment()
	stop_seat_assignment()
	stop_pickup_assignment()
	_current_order_type = OrderType.NONE
	_clear_actor_move_target()


func force_kill(_attacker: HumanoidCharacter = null) -> void:
	blood = get_blood_death_point()
	hp = get_death_point(max_hp)
	_enter_dead_state()


func force_unconscious() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	_enter_unconscious_state()


func drop_carried_character() -> void:
	var carried := _detach_carried_character()
	if carried == null:
		return
	carried.global_position = global_position - transform.basis.z * 0.9
	carried.velocity = Vector3(transform.basis.z.x, 0.0, transform.basis.z.z) * 0.5
	carried._enter_downed_state(carried.life_state == NpcRules.LifeState.DEAD)
	state_changed.emit()


func _detach_carried_character() -> HumanoidCharacter:
	if _carried_character == null:
		return null
	var carried := _carried_character
	_carried_character = null
	carried._carried_by = null
	carried._carried_pose_animation = ""
	carried.collision_layer = carried._stored_collision_layer
	carried.collision_mask = carried._stored_collision_mask
	return carried


func _attach_carried_character(target_character: HumanoidCharacter) -> void:
	_carried_character = target_character
	target_character._clear_cell_custody_state(false)
	target_character._carried_by = self
	target_character._cancel_ragdoll_preroll()
	target_character._cancel_get_up()
	target_character._stop_ragdoll_simulation(true)
	target_character._restore_downed_collision_shape()
	target_character._stored_collision_layer = target_character.collision_layer
	target_character._stored_collision_mask = target_character.collision_mask
	target_character.collision_layer = 0
	target_character.collision_mask = 0
	target_character.velocity = Vector3.ZERO
	target_character.stop_attack_assignment()
	target_character.stop_heal_assignment()
	target_character.stop_finish_off_assignment()
	target_character.stop_carry_assignment()
	target_character._release_sleep_target_without_waking()
	target_character._play_carried_pose_animation()
	var target_body := target_character.get_body_projection()
	if target_body != null:
		target_body.apply_bone_pose_offsets()
	target_character._update_carried_transform()
	state_changed.emit()


func _update_carried_transform() -> void:
	if _carried_by == null:
		return
	var profile := _carried_by._get_carry_pose_profile()
	var shoulder_origin := _carried_by._get_carry_shoulder_origin_transform(profile)
	var carried_local_position := _get_carry_profile_vector(profile, "carried_local_position", _get_carry_profile_vector(profile, "carrier_anchor_local_offset", Vector3.ZERO))
	global_transform = shoulder_origin * Transform3D(_get_carry_pose_local_basis(profile), carried_local_position)


func _get_carry_pose_profile() -> Resource:
	return carry_pose_profile if carry_pose_profile != null else DEFAULT_CARRY_POSE_PROFILE


func _get_carry_pose_local_basis(profile: Resource) -> Basis:
	var carry_rotation_degrees := _get_carry_profile_vector(profile, "rotation_degrees", Vector3.ZERO)
	return Basis.from_euler(Vector3(
		deg_to_rad(carry_rotation_degrees.x),
		deg_to_rad(carry_rotation_degrees.y),
		deg_to_rad(carry_rotation_degrees.z)
	))


func _get_carry_shoulder_origin_transform(profile: Resource) -> Transform3D:
	var origin_position = _get_carry_bone_global_position(
		_get_carry_profile_bone_names(profile, "carrier_anchor_bones", PackedStringArray(["upperarm_r", "clavicle_r", "spine_03"])),
		Vector3.ZERO,
		"carrier"
	)
	var origin: Vector3 = origin_position if origin_position is Vector3 else global_transform * _get_carry_fallback_local_anchor(true)
	return Transform3D(global_transform.basis.orthonormalized(), origin)


func _get_carry_carrier_anchor_global_position(profile: Resource) -> Vector3:
	var anchor_position = _get_carry_bone_global_position(
		_get_carry_profile_bone_names(profile, "carrier_anchor_bones", PackedStringArray(["upperarm_r", "clavicle_r", "spine_03"])),
		_get_carry_profile_vector(profile, "carrier_anchor_local_offset", Vector3.ZERO),
		"carrier"
	)
	if anchor_position is Vector3:
		return anchor_position
	return global_transform * _get_carry_fallback_local_anchor(true)


func _get_carry_carried_anchor_local_position(profile: Resource) -> Vector3:
	var anchor_position = _get_carry_bone_global_position(
		_get_carry_profile_bone_names(profile, "carried_anchor_bones", PackedStringArray(["spine_02", "spine_03", "pelvis"])),
		_get_carry_profile_vector(profile, "carried_anchor_local_offset", Vector3.ZERO),
		"carried"
	)
	if anchor_position is Vector3:
		return global_transform.affine_inverse() * anchor_position
	return _get_carry_fallback_local_anchor(false)


func _get_carry_bone_global_position(bone_names: PackedStringArray, bone_local_offset: Vector3, anchor_role: String):
	var character_skeleton := _body.get_skeleton() if _body != null else null
	if character_skeleton == null or not is_instance_valid(character_skeleton):
		return null
	character_skeleton.force_update_all_bone_transforms()
	var bone_index := _find_carry_anchor_bone_index(character_skeleton, bone_names, anchor_role)
	if bone_index < 0:
		return null
	var bone_pose := character_skeleton.get_bone_global_pose(bone_index)
	return character_skeleton.global_transform * (bone_pose * bone_local_offset)


func _find_carry_anchor_bone_index(skeleton: Skeleton3D, bone_names: PackedStringArray, anchor_role: String) -> int:
	for bone_name in bone_names:
		var exact_index := skeleton.find_bone(str(bone_name))
		if exact_index >= 0:
			return exact_index
	var semantic_index := _find_semantic_carry_anchor_bone_index(skeleton, anchor_role)
	if semantic_index >= 0:
		return semantic_index
	for bone_index in range(skeleton.get_bone_count()):
		return bone_index
	return -1


func _find_semantic_carry_anchor_bone_index(skeleton: Skeleton3D, anchor_role: String) -> int:
	if anchor_role == "carrier":
		var shoulder_index := _find_bone_index_by_keyword_groups(skeleton, [
			["upperarm", "r"],
			["right", "upperarm"],
			["clavicle", "r"],
			["right", "clavicle"],
			["shoulder", "r"],
			["right", "shoulder"],
		])
		if shoulder_index >= 0:
			return shoulder_index
		return _find_highest_spine_bone_index(skeleton)
	return _find_bone_index_by_keyword_groups(skeleton, [
		["spine02"],
		["spine2"],
		["spine", "02"],
		["spine", "2"],
		["stomach"],
		["abdomen"],
		["torso"],
		["chest"],
		["spine03"],
		["spine3"],
		["pelvis"],
		["hips"],
	])


func _find_bone_index_by_keyword_groups(skeleton: Skeleton3D, keyword_groups: Array) -> int:
	for keyword_group in keyword_groups:
		for bone_index in range(skeleton.get_bone_count()):
			var normalized_name := _normalize_bone_name(skeleton.get_bone_name(bone_index))
			var matches := true
			for keyword in keyword_group:
				if not normalized_name.contains(_normalize_bone_name(str(keyword))):
					matches = false
					break
			if matches:
				return bone_index
	return -1


func _find_highest_spine_bone_index(skeleton: Skeleton3D) -> int:
	var best_index := -1
	var best_score := -1
	for bone_index in range(skeleton.get_bone_count()):
		var normalized_name := _normalize_bone_name(skeleton.get_bone_name(bone_index))
		if not normalized_name.contains("spine") and not normalized_name.contains("chest"):
			continue
		var score := 0
		for character in normalized_name:
			if character.is_valid_int():
				score = score * 10 + int(character)
		if score >= best_score:
			best_score = score
			best_index = bone_index
	return best_index


func _normalize_bone_name(bone_name: String) -> String:
	return bone_name.to_lower().replace("_", "").replace("-", "").replace(" ", "").replace(".", "").replace(":", "")


func _get_carry_profile_bone_names(profile: Resource, property_name: String, fallback: PackedStringArray) -> PackedStringArray:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	var result := PackedStringArray()
	if value is PackedStringArray:
		result = value
	elif value is Array:
		for item in value:
			result.append(str(item))
	elif value is String and not str(value).is_empty():
		result.append(str(value))
	return result if not result.is_empty() else fallback


func _get_carry_profile_vector(profile: Resource, property_name: String, fallback: Vector3) -> Vector3:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	return value if value is Vector3 else fallback


func _get_carry_profile_float(profile: Resource, property_name: String, fallback: float) -> float:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	return float(value) if value is float or value is int else fallback


func _get_carry_fallback_local_anchor(is_carrier_anchor: bool) -> Vector3:
	var body_mesh := get_node_or_null("BodyMesh") as MeshInstance3D
	if body_mesh != null and body_mesh.mesh != null:
		var bounds := _calculate_local_mesh_bounds(body_mesh)
		if bounds.size.y > 0.001:
			var height_ratio := 0.78 if is_carrier_anchor else 0.56
			var side_offset := bounds.size.x * 0.25 if is_carrier_anchor else 0.0
			return Vector3(bounds.position.x + bounds.size.x * 0.5 + side_offset, bounds.position.y + bounds.size.y * height_ratio, bounds.position.z + bounds.size.z * 0.5)
	return Vector3(0.24, 1.55, 0.08) if is_carrier_anchor else Vector3.ZERO


func enter_cell_custody(cell, cell_position: Vector3, cell_rotation: Vector3) -> void:
	_cell_custody_target = cell
	_cancel_ragdoll_preroll()
	_cancel_get_up()
	_clear_all_active_orders()
	_clear_combat_resolution_state()
	COMBAT_COORDINATOR.release_character(self)
	_stop_ragdoll_simulation(true)
	_restore_downed_collision_shape()
	var stand_position := _get_cell_custody_stand_position(cell)
	global_position = stand_position if life_state == NpcRules.LifeState.ALIVE and stand_position != Vector3.INF else cell_position
	global_rotation = cell_rotation
	velocity = Vector3.ZERO
	running = false
	_set_sneaking_state(false, false)
	if is_recoverable_downed_state():
		_apply_downed_collision_shape()
		_play_cell_unconscious_pose()
	elif life_state == NpcRules.LifeState.ALIVE:
		if _body != null:
			_body.stop_clip(true)
		_play_random_idle_animation(true)
	state_changed.emit()


func exit_cell_custody(exit_position: Vector3, exit_rotation: Vector3) -> void:
	_clear_cell_custody_state(true)
	global_position = exit_position
	global_rotation = exit_rotation
	velocity = Vector3.ZERO
	state_changed.emit()


func _clear_cell_custody_state(restore_collision := true) -> void:
	_cell_custody_target = null
	_cell_custody_unconscious_pose_animation = ""
	_cell_custody_lay_freeze_remaining = 0.0
	_cell_custody_lay_pose_frozen = false
	_cell_custody_wake_animation = ""
	_cell_custody_wake_remaining = 0.0
	if restore_collision:
		_restore_downed_collision_shape()
	if _body != null:
		_body.stop_clip(true)


func _play_carried_pose_animation() -> void:
	var animation_name := _body.pick_preferred_available_clip(CARRY_POSE_ANIMATION_NAMES) if _body != null else ""
	if animation_name.is_empty():
		return
	_carried_pose_animation = animation_name
	if _body == null or not _body.play_clip(animation_name, 0.0, true, MOVE_ANIMATION_BLEND_SECONDS):
		return
	var profile := _carried_by._get_carry_pose_profile() if _carried_by != null else _get_carry_pose_profile()
	var animation_length := _body.clip_length(animation_name)
	var sample_time := animation_length * clampf(_get_carry_profile_float(profile, "carried_pose_time_ratio", 0.0), 0.0, 1.0)
	_body.seek_clip(animation_name, sample_time, true, 0.0)


func _update_carried_pose_animation() -> void:
	var animation_player := _body.get_primary_animation_player() if _body != null else null
	if animation_player == null:
		return
	if _carried_pose_animation.is_empty() or _body.get_current_clip() != _carried_pose_animation or not _body.is_current_clip_playing():
		_play_carried_pose_animation()
	elif animation_player.speed_scale != 0.0:
		_play_carried_pose_animation()


func _play_cell_unconscious_pose() -> void:
	var animation_name := CELL_CUSTODY_LAY_ANIMATION_NAME
	if _body == null or not _body.has_clip(animation_name):
		animation_name = _body.pick_preferred_available_clip(["LiftAir_Fall"]) if _body != null else ""
	if animation_name.is_empty() or _body == null or _body.get_primary_animation_player() == null:
		return
	_cell_custody_unconscious_pose_animation = animation_name
	_cell_custody_lay_pose_frozen = false
	_cell_custody_wake_animation = ""
	_cell_custody_wake_remaining = 0.0
	_body.play_clip(animation_name, 0.0, true, 0.0)
	var animation_length := _body.clip_length(animation_name)
	_cell_custody_lay_freeze_remaining = maxf(0.0, animation_length * CELL_CUSTODY_LAY_FREEZE_RATIO)
	_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, _cell_custody_lay_freeze_remaining + 0.5)
	if _cell_custody_lay_freeze_remaining <= 0.0:
		_freeze_cell_lay_pose()


func _freeze_cell_lay_pose() -> void:
	if _cell_custody_unconscious_pose_animation.is_empty() or _body == null or _body.get_primary_animation_player() == null:
		return
	var animation_name := _cell_custody_unconscious_pose_animation
	var animation_length := _body.clip_length(animation_name)
	var freeze_time := animation_length * CELL_CUSTODY_LAY_FREEZE_RATIO
	_body.seek_clip(animation_name, freeze_time, true, 0.0)
	_cell_custody_lay_freeze_remaining = 0.0
	_cell_custody_lay_pose_frozen = true


func _start_cell_wake_animation() -> void:
	_cell_custody_unconscious_pose_animation = ""
	_cell_custody_lay_freeze_remaining = 0.0
	_cell_custody_lay_pose_frozen = false
	var animation_name := CELL_CUSTODY_WAKE_ANIMATION_NAME
	if _body == null or not _body.has_clip(animation_name):
		_cell_custody_wake_animation = ""
		_cell_custody_wake_remaining = 0.0
		if _body != null:
			_body.stop_clip(true)
		_play_random_idle_animation(true)
		return
	var animation_length := _body.clip_length(animation_name)
	var start_time := animation_length * CELL_CUSTODY_WAKE_START_RATIO
	_cell_custody_wake_animation = animation_name
	_cell_custody_wake_remaining = maxf(0.0, animation_length - start_time)
	_body.play_clip(animation_name, 0.0, true, 0.0)
	_body.seek_clip(animation_name, start_time, true, 1.0)
	if _cell_custody_wake_remaining <= 0.0:
		_finish_cell_wake_animation()


func _finish_cell_wake_animation() -> void:
	_cell_custody_wake_animation = ""
	_cell_custody_wake_remaining = 0.0
	if _body != null:
		_body.stop_clip(true)
	_play_random_idle_animation(true)


func _update_cell_custody_animation(delta: float) -> void:
	velocity = Vector3.ZERO
	if is_recoverable_downed_state():
		var animation_player := _body.get_primary_animation_player() if _body != null else null
		if _cell_custody_unconscious_pose_animation.is_empty() or animation_player == null:
			_play_cell_unconscious_pose()
		elif not _cell_custody_lay_pose_frozen:
			_cell_custody_lay_freeze_remaining = maxf(0.0, _cell_custody_lay_freeze_remaining - delta)
			if _cell_custody_lay_freeze_remaining <= 0.0:
				_freeze_cell_lay_pose()
		return
	if life_state == NpcRules.LifeState.ALIVE:
		_restore_downed_collision_shape()
		_cell_custody_unconscious_pose_animation = ""
		_cell_custody_lay_freeze_remaining = 0.0
		_cell_custody_lay_pose_frozen = false
		if not _cell_custody_wake_animation.is_empty():
			_cell_custody_wake_remaining = maxf(0.0, _cell_custody_wake_remaining - delta)
			if _cell_custody_wake_remaining <= 0.0:
				_finish_cell_wake_animation()
			return
		_update_character_animation(delta)


func _enter_downed_state(is_dead: bool) -> void:
	if _carried_by != null:
		return
	_cancel_ragdoll_preroll()
	_cancel_get_up()
	_clear_actor_move_target()
	_clear_combat_resolution_state()
	_downed_is_settled = true
	rotation = Vector3(0.0, rotation.y, 0.0)
	velocity = Vector3.ZERO
	if _body != null:
		_body.enter_downed_visuals(is_dead)


func _restore_from_downed_state() -> void:
	if _carried_by != null:
		return
	_cancel_ragdoll_preroll()
	_downed_is_settled = false
	rotation = Vector3(0.0, rotation.y, 0.0)
	velocity = Vector3.ZERO
	if _body != null:
		_body.restore_from_downed_visuals()
	else:
		_restore_downed_collision_shape()
	_show_world_notice("Recovered", Color(0.5, 1.0, 0.65, 1.0))


func _begin_get_up() -> void:
	if _is_getting_up or life_state == NpcRules.LifeState.DEAD or _carried_by != null:
		return
	_clear_all_active_orders()
	_clear_actor_move_target()
	velocity = Vector3.ZERO
	_downed_is_settled = true
	if _body != null:
		_body.begin_get_up_visuals()
	else:
		_is_getting_up = true
	_show_world_notice("Getting up", Color(0.5, 1.0, 0.65, 1.0))
	state_changed.emit()


func _process_downed_animation_state(delta: float) -> void:
	if _body != null and _body.process_downed_visuals(delta):
		_finish_get_up()


func _begin_downed_ragdoll_preroll(is_dead: bool) -> bool:
	# A4 transitional shim -> HumanoidBodyProjection._begin_downed_ragdoll_preroll.
	return bool(_body.call("_begin_downed_ragdoll_preroll", is_dead)) if _body != null and _body.has_method("_begin_downed_ragdoll_preroll") else false


func _process_downed_ragdoll_preroll(delta: float) -> void:
	# A4 transitional shim -> HumanoidBodyProjection._process_downed_ragdoll_preroll.
	if _body != null and _body.has_method("_process_downed_ragdoll_preroll"):
		_body.call("_process_downed_ragdoll_preroll", delta)


func _finish_downed_ragdoll_preroll() -> void:
	# A4 transitional shim -> HumanoidBodyProjection._finish_downed_ragdoll_preroll.
	if _body != null and _body.has_method("_finish_downed_ragdoll_preroll"):
		_body.call("_finish_downed_ragdoll_preroll")


func _cancel_ragdoll_preroll() -> void:
	# A4 transitional shim -> HumanoidBodyProjection._cancel_ragdoll_preroll.
	if _body != null and _body.has_method("_cancel_ragdoll_preroll"):
		_body.call("_cancel_ragdoll_preroll")
		return
	_ragdoll_preroll_active = false
	_ragdoll_preroll_is_dead = false
	_ragdoll_preroll_animation_name = ""
	_ragdoll_preroll_remaining = 0.0


func _process_get_up_animation(delta: float) -> void:
	# A4 transitional shim -> HumanoidBodyProjection._process_get_up_animation.
	if _body != null and _body.has_method("_process_get_up_animation") and bool(_body.call("_process_get_up_animation", delta)):
		_finish_get_up()


func _finish_get_up() -> void:
	if not _is_getting_up:
		return
	_is_getting_up = false
	_get_up_animation_name = ""
	_get_up_animation_remaining = 0.0
	_get_up_animation_total = 0.0
	var previous_state := life_state
	life_state = NpcRules.LifeState.ALIVE
	_restore_from_downed_state()
	life_state_changed.emit(previous_state, life_state)
	state_changed.emit()


func _cancel_get_up() -> void:
	if _body != null:
		_body.cancel_get_up_visuals()
		return
	if not _is_getting_up:
		return
	_is_getting_up = false
	_get_up_animation_name = ""
	_get_up_animation_remaining = 0.0
	_get_up_animation_total = 0.0


func _apply_downed_collision_shape() -> void:
	var collision_shape := _get_main_collision_shape()
	if collision_shape == null:
		return
	if not _downed_collision_applied:
		_stored_collision_shape = collision_shape.shape
		_stored_collision_transform = collision_shape.transform
		_stored_collision_disabled = collision_shape.disabled
		_stored_collision_layer = collision_layer
		_stored_collision_mask = collision_mask
		_stored_navigation_avoidance_enabled = _get_navigation_avoidance_enabled()
	collision_shape.disabled = true
	collision_layer = 0
	collision_mask = 0
	_downed_collision_applied = true
	_set_navigation_avoidance_enabled(false)


func _restore_downed_collision_shape() -> void:
	var collision_shape := _get_main_collision_shape()
	if _downed_collision_applied and collision_shape != null:
		collision_shape.shape = _stored_collision_shape
		collision_shape.transform = _stored_collision_transform
		collision_shape.disabled = _stored_collision_disabled
		collision_layer = _stored_collision_layer
		collision_mask = _stored_collision_mask
	_downed_collision_applied = false
	_set_navigation_avoidance_enabled(_stored_navigation_avoidance_enabled)


func _get_main_collision_shape() -> CollisionShape3D:
	return get_node_or_null("CollisionShape3D") as CollisionShape3D


func _get_navigation_avoidance_enabled() -> bool:
	_ensure_navigation_agent()
	return _navigation_agent.avoidance_enabled if _navigation_agent != null else navigation_avoidance_enabled


func _set_navigation_avoidance_enabled(enabled: bool) -> void:
	navigation_avoidance_enabled = enabled
	_ensure_navigation_agent()
	if _navigation_agent != null:
		_navigation_agent.avoidance_enabled = enabled


func _start_ragdoll_simulation(_is_dead: bool) -> bool:
	return _body.start_ragdoll_simulation(_is_dead) if _body != null else false


func _stop_ragdoll_simulation(reset_pose: bool) -> void:
	if _body != null:
		_body.stop_ragdoll_simulation(reset_pose)
		return
	_is_ragdoll_active = false
	_ragdoll_upward_velocity_suppression_frames = 0


func _prepare_ragdoll_get_up() -> void:
	if _body != null:
		_body.prepare_ragdoll_get_up()
		return
	rotation = Vector3(0.0, rotation.y, 0.0)


func _stabilize_active_ragdoll(_delta: float) -> void:
	if _body != null:
		_body.stabilize_ragdoll(_delta)


func _get_ragdoll_anchor_position() -> Variant:
	return _body.get_ragdoll_anchor_position() if _body != null else null


func _get_attack_ragdoll_impulse(attacker: Node, damage: float) -> Vector3:
	return _body.get_attack_ragdoll_impulse(attacker, damage) if _body != null else Vector3.ZERO


func _show_world_notice(message: String, color: Color = Color(1.0, 0.28, 0.28, 1.0), lifetime: float = 1.0, rise_height: float = 0.4) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var notice = WORLD_TEXT_NOTICE_SCENE.instantiate()
	tree.current_scene.add_child(notice)
	if notice.has_method("setup"):
		notice.setup(global_position + Vector3(0.0, overhead_text_height, 0.0), message, color, lifetime, rise_height)


func _is_working() -> bool:
	return (_current_order_type == OrderType.MINE and _mining_active) or (_current_order_type == OrderType.SCAVENGE and _scavenging_active)


func _get_best_bandage_definition() -> ItemDefinition:
	var entry = _get_best_bandage_entry()
	return entry.definition if entry != null else null


func _get_best_bandage_entry():
	var best_entry = null
	var best_power := -1.0
	for entry in inventory.entries:
		if not can_use_bandage_item(entry.definition):
			continue
		if not _bandage_entry_has_uses(entry):
			continue
		if entry.definition.bandage_power > best_power:
			best_entry = entry
			best_power = entry.definition.bandage_power
	return best_entry


func _consume_cinder_flask_definition() -> ItemDefinition:
	var flask_definition := _find_inventory_tool(CINDER_FLASK_TOOL_TAG)
	if flask_definition == null:
		return null
	if inventory == null or not inventory.remove_item_count(flask_definition, 1):
		return null
	return flask_definition


func _bandage_entry_has_uses(entry) -> bool:
	if entry == null or inventory == null:
		return false
	if inventory.has_method("get_entry_bandage_uses"):
		return int(inventory.call("get_entry_bandage_uses", entry)) > 0
	return entry.definition != null and int(entry.definition.bandage_max_uses) > 0


func _report_assault_crime_if_needed(target_character: HumanoidCharacter) -> void:
	if target_character == null or not is_player_party_member() or target_character.is_player_party_member():
		return
	if has_hostility_with(target_character):
		return
	var law_controller := _get_law_order_controller()
	if law_controller != null and law_controller.has_method("report_player_assault"):
		law_controller.call("report_player_assault", self, target_character)
	elif law_controller != null and law_controller.has_method("report_assault_if_witnessed"):
		law_controller.call("report_assault_if_witnessed", self, target_character)


func _report_murder_crime_if_needed() -> void:
	if _last_direct_attacker_id == 0:
		return
	var attacker := _find_humanoid_by_instance_id(_last_direct_attacker_id)
	if attacker == null or not attacker.is_player_party_member() or is_player_party_member():
		return
	var law_controller := _get_law_order_controller()
	if law_controller != null and law_controller.has_method("report_murder_if_witnessed"):
		law_controller.call("report_murder_if_witnessed", attacker, self)


func _notify_law_order_actor_death() -> void:
	var law_controller := _get_law_order_controller()
	if law_controller != null and law_controller.has_method("handle_actor_death"):
		law_controller.call("handle_actor_death", self)


func _find_humanoid_by_instance_id(instance_id: int) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var query_controller := _get_runtime_controller("actor_query_controller")
	if query_controller != null and query_controller.has_method("get_actor_by_instance_id"):
		var indexed_actor := query_controller.call("get_actor_by_instance_id", instance_id) as Node
		if indexed_actor != null:
			return indexed_actor
	# TODO(actor-decoupling): fallback is still humanoid-only; rely on ActorQueryController for non-humanoid actors instead of scanning world_actor here.
	for node in tree.get_nodes_in_group("humanoid_character"):
		var actor := node as HumanoidCharacter
		if actor != null and actor.get_instance_id() == instance_id:
			return actor
	return null


func _get_law_order_controller() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("law_order_controller"):
		return node
	return null
