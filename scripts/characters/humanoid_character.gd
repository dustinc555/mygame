extends "res://scripts/actors/world_actor.gd"

class_name HumanoidCharacter

const WORLD_TEXT_NOTICE_SCENE = preload("res://scenes/world/effects/world_text_notice.tscn")
const HUMAN_RACE = preload("res://resources/character_races/human.tres")
const HUMAN_MALE_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/human_female.tres")
const MALE_VISUAL_SCENE = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Male_FullBody.gltf")
const FEMALE_VISUAL_SCENE = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Female_FullBody.gltf")
const UAL1_ANIMATION_SOURCE_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_1/UAL1_Standard.glb")
const UAL2_ANIMATION_SOURCE_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_2/UAL2_Standard.glb")
const DEFAULT_GRIP_SOCKET_PROFILE = preload("res://resources/humanoid_grip_socket_profiles/default.tres")
const HUMANOID_GRIP_SOCKET_MARKER_SCRIPT = preload("res://scripts/characters/humanoid_grip_socket_marker.gd")
const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const CHARACTER_ANIMATION_PLAYER_NAME := "CharacterAnimationPlayer"
const CHARACTER_VISUAL_YAW_OFFSET := PI
const CHARACTER_VISUAL_FOOT_CLEARANCE := 0.02
const IDLE_ANIMATION_NAME := "Idle"
const FOLD_ARMS_IDLE_ANIMATION_NAME := "Idle_FoldArms"
const WALK_ANIMATION_NAME := "Walk"
const CROUCH_IDLE_ANIMATION_NAME := "Crouch_Idle"
const CROUCH_WALK_ANIMATION_NAME := "Crouch_Fwd"
const JOG_ANIMATION_NAME := "Jog_Fwd"
const SPRINT_ANIMATION_NAME := "Sprint"
const SITTING_ENTER_ANIMATION_NAME := "Sitting_Enter"
const SITTING_IDLE_ANIMATION_NAME := "Sitting_Idle"
const SITTING_TALKING_ANIMATION_NAME := "Sitting_Talking"
const SITTING_EXIT_ANIMATION_NAME := "Sitting_Exit"
const IDLE_ANIMATION_NAMES := [IDLE_ANIMATION_NAME]
const IDLE_ANIMATION_MIN_SECONDS := 4.0
const IDLE_ANIMATION_MAX_SECONDS := 8.0
const SITTING_IDLE_MIN_SECONDS := 5.0
const SITTING_IDLE_MAX_SECONDS := 11.0
const SITTING_TALKING_CHANCE := 0.28
const MOVE_ANIMATION_BLEND_SECONDS := 0.12
const SPRINT_ANIMATION_SPEED_RATIO := 0.82
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
const BONE_EQUIPMENT_SLOTS := {
	"weapon": "hand_r",
	"offhand": "hand_l",
}

enum OrderType {
	NONE,
	MOVE,
	MINE,
	OPEN_CONTAINER,
	TRADE,
	TALK,
	ATTACK,
	HEAL,
	FINISH_OFF,
	CARRY,
	SLEEP,
	PLACE_IN_BED,
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

@export var member_name := "Character"
@export var stable_id := ""
@export var interact_distance := 1.8
@export var inventory_columns := 10
@export var inventory_rows := 4
@export var max_carry_weight := 60.0
@export var show_inventory_weight := true
@export var overhead_text_height := 2.4
@export var show_nameplate := true
@export var character_race: Resource = HUMAN_RACE
@export var body_archetype: Resource
@export_enum("Auto", "None", "Male", "Female") var visual_body_type: int = VisualBodyType.AUTO
@export var grip_socket_profile: Resource = DEFAULT_GRIP_SOCKET_PROFILE
@export var show_grip_socket_markers := false
@export var starting_items: Array[Resource] = []
@export var starting_equipment: Array[Resource] = []

@export var faction_name := "Player"
@export var squad_name := "Default"
@export var hostile_factions: PackedStringArray = PackedStringArray()
@export var conversation_definition: Resource

@export var hunger_enabled := false
@export_range(0, 2, 1) var hunger_stage := NpcRules.HungerStage.WELL_NOURISHED
@export var hunger := 100.0
@export var hunger_drain_rate := 0.08
@export var fatigue_enabled := true
@export_range(0, 2, 1) var fatigue_stage := NpcRules.FatigueStage.WELL_RESTED
@export var fatigue := 100.0
@export var running := false
@export var sneaking := false
@export_range(0, 2, 1) var combat_stance := NpcRules.CombatStance.DEFENSIVE

@export var max_hp := 100.0
@export var hp := 100.0
@export var max_blood := 100.0
@export var blood := 100.0

@export var trade_interaction_distance := 3.0
@export var aggressive_scan_radius := NpcRules.AGGRO_RANGE
@export var assist_scan_radius := NpcRules.ASSIST_RANGE
@export var attack_range := 1.8
@export var attack_cooldown_seconds := 1.2
@export var base_attack_damage := 18.0
@export_range(0.0, 1.0, 0.01) var attack_cut_ratio := 0.05
@export var base_dodge_chance := 0.08
@export var base_block_chance := 0.06
@export var block_damage_multiplier := 0.4
@export var carry_move_speed_multiplier := 0.6

var inventory: InventoryData
var is_inspected := false
var is_selected := false
var is_focused := false
var player_party_member := false
var life_state := NpcRules.LifeState.ALIVE
var _current_order_type: int = OrderType.NONE
var _order_was_player_issued := false

var _current_mining_node
var _mining_progress_by_node: Dictionary = {}
var _mining_active := false
var _current_container_target
var _current_trade_target
var _current_conversation_target
var _current_attack_target: HumanoidCharacter
var _current_heal_target: HumanoidCharacter
var _current_finish_off_target: HumanoidCharacter
var _current_carry_target: HumanoidCharacter
var _current_sleep_target
var _current_place_bed_target
var _current_seat_target
var _current_pickup_item
var _current_seat_stand_position: Variant = null
var _carried_by: HumanoidCharacter
var _carried_character: HumanoidCharacter
var equipped_items: Dictionary = {}

var _current_blunt_damage := 0.0
var _current_open_cut_damage := 0.0
var _current_bandaged_cut_damage := 0.0
var _bleed_rate := 0.0
var _pending_nourishment := 0.0
var _combat_cooldown_remaining := 0.0
var _ai_tick_remaining := 0.0
var _downed_recover_delay_remaining := 0.0
var _downed_target_rotation_z := 0.0
var _downed_is_settled := false
var _stored_collision_layer := 1
var _stored_collision_mask := 1

var _personal_hostile_ids: Dictionary = {}
var _last_direct_attacker_id := 0
var _assigned_talkers: Dictionary = {}
var _pending_talker_ids: Dictionary = {}

var _nameplate: Label3D
var _inspect_ring: MeshInstance3D
var _inspect_ring_material := StandardMaterial3D.new()
var _character_animation_player: AnimationPlayer
var _character_animation_players: Array[AnimationPlayer] = []
var _current_character_animation := ""
var _idle_animation_change_remaining := 0.0
var _sitting_enter_animation_remaining := 0.0
var _sitting_exit_animation_remaining := 0.0
var _sitting_idle_change_remaining := 0.0
var _rng := RandomNumberGenerator.new()
var _work_inventory_override: InventoryData
var _active_job_provider
var _active_job_label := ""
var _is_sitting := false
var _equipment_update_batch_depth := 0
var _equipment_change_pending := false
var _equipment_changed_slots: Dictionary = {}

signal inventory_changed
signal mining_changed
signal state_changed
signal combat_state_changed
signal container_reached(member, container)
signal trade_target_reached(member, target)
signal conversation_target_reached(member, target)
signal center_notice_requested(message)


func _ready() -> void:
	super._ready()
	_rng.randomize()
	inventory = InventoryData.new(inventory_columns, inventory_rows, max_carry_weight, true)
	inventory.changed.connect(_on_inventory_data_changed)
	_seed_starting_inventory()
	_seed_starting_equipment()
	_setup_nameplate()
	_setup_inspect_ring()
	_setup_character_visual()
	add_to_group("humanoid_character")
	add_to_group("npc_character")
	_sync_party_membership_group()
	hunger = clampf(hunger, 0.0, 100.0)
	fatigue = clampf(fatigue, 0.0, 100.0)
	_recalculate_vitals()


func _process(delta: float) -> void:
	if _carried_by != null:
		_update_carried_transform()
		return
	if _combat_cooldown_remaining > 0.0:
		_combat_cooldown_remaining = maxf(0.0, _combat_cooldown_remaining - delta)
	_process_needs(delta)
	_process_bleeding(delta)
	_process_recovery(delta)
	_process_ai(delta)
	_recalculate_vitals()
	_update_character_animation(delta)


func _physics_process(delta: float) -> void:
	if _carried_by != null:
		velocity = Vector3.ZERO
		return
	if life_state != NpcRules.LifeState.ALIVE and _downed_is_settled and is_on_floor():
		velocity = Vector3.ZERO
		return
	_process_movement(delta)
	if life_state != NpcRules.LifeState.ALIVE:
		return
	match _current_order_type:
		OrderType.MINE:
			_process_mining(delta)
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
		OrderType.SIT:
			_process_seat_interaction()
		OrderType.PICKUP_ITEM:
			_process_pickup_interaction()


func set_move_target(target: Vector3, issued_by_player: bool = true) -> void:
	_set_order(OrderType.MOVE, issued_by_player)
	_set_actor_move_target(target)


func stop_mining_assignment() -> void:
	if _current_mining_node != null:
		_current_mining_node.release_miner(self)
	_current_mining_node = null
	_mining_active = false
	if _current_order_type == OrderType.MINE:
		_current_order_type = OrderType.NONE
	mining_changed.emit()


func stop_container_interaction() -> void:
	if _current_container_target != null and _current_container_target.has_method("release_interactor"):
		_current_container_target.release_interactor(self)
	_current_container_target = null
	if _current_order_type == OrderType.OPEN_CONTAINER:
		_current_order_type = OrderType.NONE


func stop_trade_interaction() -> void:
	if _current_trade_target != null and _current_trade_target.has_method("release_trader"):
		_current_trade_target.release_trader(self)
	_current_trade_target = null
	if _current_order_type == OrderType.TRADE:
		_current_order_type = OrderType.NONE


func stop_conversation_interaction() -> void:
	if _current_conversation_target != null and _current_conversation_target.has_method("release_talker"):
		_current_conversation_target.release_talker(self)
	_current_conversation_target = null
	if _current_order_type == OrderType.TALK:
		_current_order_type = OrderType.NONE


func stop_attack_assignment() -> void:
	_current_attack_target = null
	if _current_order_type == OrderType.ATTACK:
		_current_order_type = OrderType.NONE
	combat_state_changed.emit()


func stop_heal_assignment() -> void:
	_current_heal_target = null
	if _current_order_type == OrderType.HEAL:
		_current_order_type = OrderType.NONE


func stop_finish_off_assignment() -> void:
	_current_finish_off_target = null
	if _current_order_type == OrderType.FINISH_OFF:
		_current_order_type = OrderType.NONE


func stop_carry_assignment() -> void:
	_current_carry_target = null
	if _current_order_type == OrderType.CARRY:
		_current_order_type = OrderType.NONE


func stop_sleep_assignment() -> void:
	if life_state == NpcRules.LifeState.ASLEEP and _current_sleep_target != null and _current_sleep_target.has_method("get_interaction_position"):
		global_position = _current_sleep_target.get_interaction_position(self)
	_release_sleep_target_without_waking()
	if life_state == NpcRules.LifeState.ASLEEP:
		life_state = NpcRules.LifeState.ALIVE
		rotation = Vector3(0.0, rotation.y, 0.0)
		velocity = Vector3.ZERO
		state_changed.emit()
	if _current_order_type == OrderType.SLEEP:
		_current_order_type = OrderType.NONE


func stop_place_in_bed_assignment() -> void:
	_current_place_bed_target = null
	if _current_order_type == OrderType.PLACE_IN_BED:
		_current_order_type = OrderType.NONE


func _release_sleep_target_without_waking() -> void:
	if _current_sleep_target != null and _current_sleep_target.has_method("release_sleeper"):
		_current_sleep_target.release_sleeper(self)
	_current_sleep_target = null
	if _current_order_type == OrderType.SLEEP:
		_current_order_type = OrderType.NONE


func stop_seat_assignment() -> void:
	var did_stop_sitting := _is_sitting
	if _is_sitting and _current_seat_target != null:
		if _current_seat_stand_position != null:
			global_position = _current_seat_stand_position
		elif _current_seat_target.has_method("get_stand_position"):
			global_position = _current_seat_target.get_stand_position()
		elif _current_seat_target.has_method("get_interaction_position"):
			global_position = _current_seat_target.get_interaction_position(self)
	if _current_seat_target != null and _current_seat_target.has_method("release_sitter"):
		_current_seat_target.release_sitter(self)
	_current_seat_target = null
	_current_seat_stand_position = null
	if did_stop_sitting:
		_is_sitting = false
		_start_sitting_exit_animation()
		rotation = Vector3(0.0, rotation.y, 0.0)
		velocity = Vector3.ZERO
		state_changed.emit()
	if _current_order_type == OrderType.SIT:
		_current_order_type = OrderType.NONE


func stop_pickup_assignment() -> void:
	_current_pickup_item = null
	if _current_order_type == OrderType.PICKUP_ITEM:
		_current_order_type = OrderType.NONE


func assign_open_container(container, issued_by_player: bool = true) -> void:
	if container == null:
		return
	_set_order(OrderType.OPEN_CONTAINER, issued_by_player)
	if _current_container_target != null and _current_container_target != container and _current_container_target.has_method("release_interactor"):
		_current_container_target.release_interactor(self)
	_current_container_target = container
	if _current_container_target.has_method("register_interactor"):
		_current_container_target.register_interactor(self)
	_set_actor_move_target(_current_container_target.get_interaction_position(self))


func assign_trade_target(target_character, issued_by_player: bool = true) -> void:
	if target_character == null:
		return
	_set_order(OrderType.TRADE, issued_by_player)
	if _current_trade_target != null and _current_trade_target != target_character and _current_trade_target.has_method("release_trader"):
		_current_trade_target.release_trader(self)
	_current_trade_target = target_character
	if _current_trade_target.has_method("register_trader"):
		_current_trade_target.register_trader(self)
	_set_actor_move_target(_current_trade_target.get_interaction_position(self))


func assign_conversation_target(target_character, issued_by_player: bool = true) -> void:
	if target_character == null or not target_character.has_conversation_definition():
		return
	_set_order(OrderType.TALK, issued_by_player)
	if _current_conversation_target != null and _current_conversation_target != target_character and _current_conversation_target.has_method("release_talker"):
		_current_conversation_target.release_talker(self)
	_current_conversation_target = target_character
	if _current_conversation_target.has_method("register_talker"):
		_current_conversation_target.register_talker(self)
	_set_actor_move_target(_current_conversation_target.get_interaction_position(self))


func assign_mining_resource(resource_node, issued_by_player: bool = true) -> void:
	if resource_node == null:
		return
	_set_order(OrderType.MINE, issued_by_player)
	if _current_mining_node != null and _current_mining_node != resource_node:
		_current_mining_node.release_miner(self)
	_current_mining_node = resource_node
	_current_mining_node.register_miner(self)
	_mining_active = false
	_set_actor_move_target(_current_mining_node.get_mining_position(self))
	mining_changed.emit()


func assign_attack_target(target_character: HumanoidCharacter, issued_by_player: bool = true, notify_target: bool = true, notify_allies: bool = true) -> void:
	if target_character == null or target_character == self or not is_instance_valid(target_character):
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if target_character.life_state != NpcRules.LifeState.ALIVE:
		return
	if _current_attack_target == target_character and _current_order_type == OrderType.ATTACK:
		return
	_set_order(OrderType.ATTACK, issued_by_player)
	_current_attack_target = target_character
	mark_hostile(target_character)
	target_character.mark_hostile(self)
	if notify_target:
		target_character.notify_incoming_attack(self)
	if notify_allies:
		_notify_defensive_allies_of_engagement(target_character)
	combat_state_changed.emit()


func assign_heal_target(target_character: HumanoidCharacter, issued_by_player: bool = true) -> void:
	if target_character == null or target_character == self:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	_set_order(OrderType.HEAL, issued_by_player)
	_current_heal_target = target_character


func assign_finish_off_target(target_character: HumanoidCharacter, issued_by_player: bool = true) -> void:
	if target_character == null or target_character == self:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if target_character.life_state != NpcRules.LifeState.UNCONSCIOUS:
		return
	_set_order(OrderType.FINISH_OFF, issued_by_player)
	_current_finish_off_target = target_character


func assign_carry_target(target_character: HumanoidCharacter, issued_by_player: bool = true) -> void:
	if target_character == null or target_character == self:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if not target_character.can_be_carried_by(self) or _carried_character != null:
		return
	_set_order(OrderType.CARRY, issued_by_player)
	_current_carry_target = target_character


func assign_sleep_target(bed, issued_by_player: bool = true) -> void:
	if bed == null or not bed.has_method("get_interaction_position"):
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if is_carrying_someone():
		if issued_by_player:
			center_notice_requested.emit("Place them in bed first")
			_show_world_notice("Place them in bed first", Color(1.0, 0.78, 0.38, 1.0))
		return
	_set_order(OrderType.SLEEP, issued_by_player)
	_current_sleep_target = bed
	_set_actor_move_target(bed.get_interaction_position(self))


func assign_place_carried_in_bed_target(bed, issued_by_player: bool = true) -> void:
	if bed == null or not bed.has_method("get_interaction_position"):
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if _carried_character == null or not is_instance_valid(_carried_character):
		return
	_set_order(OrderType.PLACE_IN_BED, issued_by_player)
	_current_place_bed_target = bed
	_set_actor_move_target(bed.get_interaction_position(self))


func assign_seat_target(seat, issued_by_player: bool = true) -> void:
	if seat == null or not seat.has_method("get_interaction_position"):
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	_set_order(OrderType.SIT, issued_by_player)
	_current_seat_target = seat
	_current_seat_stand_position = global_position
	if seat.has_method("can_sit_from_position") and seat.can_sit_from_position(global_position):
		_clear_actor_move_target()
	else:
		_set_actor_move_target(seat.get_interaction_position(self))


func assign_pickup_item(world_item, issued_by_player: bool = true) -> void:
	if world_item == null or not is_instance_valid(world_item):
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	_set_order(OrderType.PICKUP_ITEM, issued_by_player)
	_current_pickup_item = world_item
	if world_item.has_method("get_pickup_position"):
		_set_actor_move_target(world_item.get_pickup_position(self))
	else:
		_set_actor_move_target(world_item.global_position)


func wake_up_from_rest(show_notice: bool = true) -> void:
	var did_wake := life_state == NpcRules.LifeState.ASLEEP
	var did_stand := _is_sitting
	var stand_position: Variant = null
	if did_wake and _current_sleep_target != null and _current_sleep_target.has_method("get_interaction_position"):
		stand_position = _current_sleep_target.get_interaction_position(self)
	elif did_stand and _current_seat_target != null:
		if _current_seat_stand_position != null:
			stand_position = _current_seat_stand_position
		elif _current_seat_target.has_method("get_stand_position"):
			stand_position = _current_seat_target.get_stand_position()
		elif _current_seat_target.has_method("get_interaction_position"):
			stand_position = _current_seat_target.get_interaction_position(self)
	stop_sleep_assignment()
	stop_seat_assignment()
	if stand_position != null:
		global_position = stand_position
	if did_wake or did_stand:
		life_state = NpcRules.LifeState.ALIVE
		_clear_actor_move_target()
		_current_order_type = OrderType.NONE
		velocity = Vector3.ZERO
		if show_notice:
			_show_world_notice("Awake" if did_wake else "Standing", Color(0.5, 1.0, 0.65, 1.0))
		state_changed.emit()


func is_sitting() -> bool:
	return _is_sitting


func get_floor_aligned_origin_position(floor_position: Vector3) -> Vector3:
	return Vector3(floor_position.x, floor_position.y - get_collision_bottom_local_y(), floor_position.z)


func get_collision_bottom_local_y() -> float:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		return 0.0
	var shape_bounds := _get_collision_shape_local_bounds(collision_shape)
	return shape_bounds.position.y if shape_bounds.size.y > 0.001 else 0.0


func has_mining_assignment() -> bool:
	return _current_mining_node != null


func get_assigned_mining_node():
	return _current_mining_node


func is_actively_mining() -> bool:
	return _mining_active


func get_mining_progress_ratio() -> float:
	if _current_mining_node == null:
		return 0.0
	return minf(_get_stored_mining_progress(_current_mining_node) / _current_mining_node.mine_duration, 1.0)


func can_eat_item(definition: ItemDefinition) -> bool:
	return definition != null and definition.nutrition_value > 0.0 and hunger_enabled


func eat_item(definition: ItemDefinition) -> bool:
	if not can_eat_item(definition):
		return false
	if not inventory.remove_item_count(definition, 1):
		return false
	_pending_nourishment += definition.nutrition_value
	return true


func begin_job_assignment(provider, job_label: String, work_inventory: InventoryData) -> void:
	if _work_inventory_override != null and _work_inventory_override.changed.is_connected(_on_inventory_data_changed):
		_work_inventory_override.changed.disconnect(_on_inventory_data_changed)
	_active_job_provider = provider
	_active_job_label = job_label
	_work_inventory_override = work_inventory
	if _work_inventory_override != null and not _work_inventory_override.changed.is_connected(_on_inventory_data_changed):
		_work_inventory_override.changed.connect(_on_inventory_data_changed)
	inventory_changed.emit()
	state_changed.emit()


func end_job_assignment() -> void:
	if _work_inventory_override != null and _work_inventory_override.changed.is_connected(_on_inventory_data_changed):
		_work_inventory_override.changed.disconnect(_on_inventory_data_changed)
	_active_job_provider = null
	_active_job_label = ""
	_work_inventory_override = null
	inventory_changed.emit()
	state_changed.emit()


func get_active_job_provider():
	return _active_job_provider


func get_inventory_for_display() -> InventoryData:
	if _work_inventory_override != null:
		return _work_inventory_override
	return inventory


func is_displaying_work_inventory() -> bool:
	return _work_inventory_override != null


func get_inventory_display_title() -> String:
	if is_displaying_work_inventory():
		return "%s Work Inventory" % member_name
	return "%s Inventory" % member_name


func can_transfer_display_inventory_to(_target_owner) -> bool:
	return not is_displaying_work_inventory()


func can_receive_inventory_transfer_from(_source_owner) -> bool:
	return not is_displaying_work_inventory()


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


func get_equipped_item(slot_name: String) -> ItemDefinition:
	return equipped_items.get(slot_name) as ItemDefinition


func can_equip_item_to_slot(definition: ItemDefinition, slot_name: String) -> bool:
	if definition == null or not definition.is_equippable():
		return false
	if not get_equipment_slot_names().has(slot_name):
		return false
	return definition.can_equip_to_slot(slot_name)


func equip_item_to_slot(definition: ItemDefinition, slot_name: String) -> ItemDefinition:
	if not can_equip_item_to_slot(definition, slot_name):
		return null
	var previous := get_equipped_item(slot_name)
	equipped_items[slot_name] = definition
	_mark_equipment_changed(slot_name)
	return previous


func unequip_item_from_slot(slot_name: String) -> ItemDefinition:
	var previous := get_equipped_item(slot_name)
	if previous == null:
		return null
	equipped_items.erase(slot_name)
	_mark_equipment_changed(slot_name)
	return previous


func begin_equipment_update_batch() -> void:
	_equipment_update_batch_depth += 1


func end_equipment_update_batch() -> void:
	if _equipment_update_batch_depth <= 0:
		return
	_equipment_update_batch_depth -= 1
	if _equipment_update_batch_depth > 0 or not _equipment_change_pending:
		return
	_equipment_change_pending = false
	_apply_equipment_changed()


func _mark_equipment_changed(slot_name := "") -> void:
	if not slot_name.is_empty():
		_equipment_changed_slots[slot_name] = true
	if _equipment_update_batch_depth > 0:
		_equipment_change_pending = true
		return
	_apply_equipment_changed()


func _apply_equipment_changed() -> void:
	_equipment_change_pending = false
	var changed_slots := _equipment_changed_slots.keys()
	_equipment_changed_slots.clear()
	if _can_refresh_bone_equipment_only(changed_slots):
		_refresh_bone_equipment_slots(changed_slots)
	else:
		_rebuild_character_visual_for_equipment()
	inventory_changed.emit()
	state_changed.emit()


func has_equipment() -> bool:
	return not equipped_items.is_empty()


func get_equipped_weight() -> float:
	var total := 0.0
	for item in equipped_items.values():
		if item is ItemDefinition:
			total += (item as ItemDefinition).unit_weight
	return total


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


func get_job_status_text() -> String:
	if _active_job_provider == null:
		return ""
	if _active_job_provider.has_method("get_provider_name"):
		return "Working for %s" % _active_job_provider.get_provider_name()
	return "Working"


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


func can_bandage_target(target: HumanoidCharacter) -> bool:
	if target == null or not target.can_receive_bandage():
		return false
	for entry in inventory.entries:
		if can_use_bandage_item(entry.definition):
			return true
	return false


func get_inventory_display_name() -> String:
	return member_name


func get_inventory_world_position() -> Vector3:
	return global_position


func get_inventory_cell_size() -> Vector2:
	return Vector2(30.0, 30.0)


func shows_inventory_weight() -> bool:
	if is_displaying_work_inventory():
		return false
	return show_inventory_weight


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
	return _bleed_rate


func get_stance_label() -> String:
	return NpcRules.get_stance_label(combat_stance)


func get_life_state_label() -> String:
	return NpcRules.get_life_state_label(life_state)


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


func can_continue_running() -> bool:
	if life_state != NpcRules.LifeState.ALIVE:
		return false
	if fatigue_stage < NpcRules.FatigueStage.EXHAUSTED:
		return true
	return fatigue > NpcRules.FATIGUE_RUN_LOCKOUT_THRESHOLD


func can_enable_running() -> bool:
	return can_continue_running()


func is_in_combat() -> bool:
	return _current_order_type == OrderType.ATTACK and _current_attack_target != null


func get_current_combat_target() -> HumanoidCharacter:
	return _current_attack_target


func has_bandageable_wounds() -> bool:
	return _current_open_cut_damage > 0.0 or _bleed_rate > 0.0


func can_receive_bandage() -> bool:
	return life_state != NpcRules.LifeState.DEAD and has_bandageable_wounds()


func can_be_carried() -> bool:
	return can_be_carried_by(null)


func can_be_carried_by(carrier: HumanoidCharacter) -> bool:
	if _carried_by != null:
		return false
	if carrier != null and carrier.faction_name == faction_name:
		return true
	return life_state == NpcRules.LifeState.ASLEEP or life_state == NpcRules.LifeState.UNCONSCIOUS or life_state == NpcRules.LifeState.DEAD


func is_carried() -> bool:
	return _carried_by != null


func is_carrying_someone() -> bool:
	return _carried_character != null


func get_carried_character() -> HumanoidCharacter:
	return _carried_character


func has_hostility_with(other: HumanoidCharacter) -> bool:
	return is_hostile_to(other) or other.is_hostile_to(self)


func is_hostile_to(other: HumanoidCharacter) -> bool:
	if other == null or other == self:
		return false
	if _personal_hostile_ids.has(other.get_instance_id()):
		return true
	return hostile_factions.has(other.faction_name)


func mark_hostile(other: HumanoidCharacter) -> void:
	if other == null or other == self:
		return
	_personal_hostile_ids[other.get_instance_id()] = true


func clear_personal_hostility(other: HumanoidCharacter) -> void:
	if other == null:
		return
	_personal_hostile_ids.erase(other.get_instance_id())


func set_running_enabled(value: bool) -> bool:
	if value:
		sneaking = false
		running = can_enable_running()
	else:
		running = false
	state_changed.emit()
	return running == value


func set_sneaking_enabled(value: bool) -> void:
	if value:
		running = false
	sneaking = value and life_state == NpcRules.LifeState.ALIVE
	state_changed.emit()


func notify_incoming_attack(attacker: HumanoidCharacter) -> void:
	if attacker == null or attacker == self:
		return
	if life_state == NpcRules.LifeState.ASLEEP:
		wake_up_from_rest(false)
	if life_state != NpcRules.LifeState.ALIVE:
		return
	mark_hostile(attacker)
	attacker.mark_hostile(self)
	_last_direct_attacker_id = attacker.get_instance_id()
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


func receive_attack(attacker: HumanoidCharacter, blunt_damage: float, cut_damage: float) -> String:
	if attacker == null or life_state == NpcRules.LifeState.DEAD:
		return "ignored"
	if life_state == NpcRules.LifeState.ASLEEP:
		wake_up_from_rest(false)
	mark_hostile(attacker)
	attacker.mark_hostile(self)
	_last_direct_attacker_id = attacker.get_instance_id()
	if _rng.randf() <= get_stat_value("dodge_chance"):
		_show_world_notice("Dodge", Color(0.74, 0.94, 1.0, 1.0))
		_try_start_self_defense(attacker)
		return "dodged"
	var final_blunt := maxf(blunt_damage, 0.0)
	var final_cut := maxf(cut_damage, 0.0)
	if _rng.randf() <= get_stat_value("block_chance"):
		final_blunt *= block_damage_multiplier
		final_cut *= block_damage_multiplier
		_show_world_notice("Block", Color(0.86, 0.9, 1.0, 1.0))
	_current_blunt_damage += final_blunt
	_current_open_cut_damage += final_cut
	_bleed_rate += final_cut * 0.12
	_show_world_notice("Hit", Color(1.0, 0.42, 0.42, 1.0))
	_recalculate_vitals()
	_try_start_self_defense(attacker)
	return "hit"


func apply_bandage_from(actor: HumanoidCharacter) -> bool:
	if actor == null or not can_receive_bandage() or not actor.can_bandage_target(self):
		return false
	var bandage_definition := actor._get_best_bandage_definition()
	if bandage_definition == null:
		return false
	if not actor.inventory.remove_item_count(bandage_definition, 1):
		return false
	_current_bandaged_cut_damage += _current_open_cut_damage
	_current_open_cut_damage = 0.0
	_bleed_rate = maxf(0.0, _bleed_rate - bandage_definition.bandage_power)
	if _bleed_rate <= 0.01:
		_bleed_rate = 0.0
	_recalculate_vitals()
	return true


func get_interaction_position(member: HumanoidCharacter) -> Vector3:
	var slot_index := _get_talker_slot(member)
	var angle := TAU * float(slot_index) / 6.0
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * interact_distance


func get_combat_approach_position(attacker: HumanoidCharacter) -> Vector3:
	var away := global_position - attacker.global_position
	away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = Vector3.FORWARD
	return global_position - away.normalized() * maxf(attack_range - 0.2, 0.9)


func _process_movement(delta: float) -> void:
	if _is_sitting:
		velocity = Vector3.ZERO
		return
	if life_state == NpcRules.LifeState.ASLEEP:
		velocity = Vector3.ZERO
		return
	if life_state != NpcRules.LifeState.ALIVE:
		_process_downed_movement(delta)
		if _downed_is_settled and is_on_floor():
			return
		move_and_slide()
		return
	process_world_actor_movement(delta)


func _get_actor_move_speed() -> float:
	return _get_current_move_speed()


func _on_actor_move_target_reached() -> void:
	if _current_order_type == OrderType.MOVE:
		_current_order_type = OrderType.NONE


func _on_actor_move_target_unreachable() -> void:
	if _order_was_player_issued:
		show_world_speech("I can't reach that", 4.0)
	match _current_order_type:
		OrderType.MOVE:
			_current_order_type = OrderType.NONE
		OrderType.MINE:
			stop_mining_assignment()
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
		OrderType.SIT:
			stop_seat_assignment()
		OrderType.PICKUP_ITEM:
			stop_pickup_assignment()


func _process_downed_movement(delta: float) -> void:
	if _downed_is_settled and is_on_floor():
		velocity = Vector3.ZERO
		rotation.z = _downed_target_rotation_z
		rotation.x = 0.0
		return
	velocity.y -= gravity * delta
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, 9.0 * delta))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	rotation.z = lerp_angle(rotation.z, _downed_target_rotation_z, minf(1.0, 10.0 * delta))
	rotation.x = lerp_angle(rotation.x, 0.0, minf(1.0, 7.5 * delta))
	if is_on_floor():
		var floor_is_flat := get_floor_normal().dot(Vector3.UP) >= 0.98
		var horizontal_speed := Vector2(velocity.x, velocity.z).length()
		var rotation_delta := absf(wrapf(rotation.z - _downed_target_rotation_z, -PI, PI))
		if floor_is_flat and horizontal_speed <= 0.08 and absf(velocity.y) <= 0.15 and rotation_delta <= 0.04:
			_downed_is_settled = true
			velocity = Vector3.ZERO
			rotation.z = _downed_target_rotation_z


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
		if life_state != NpcRules.LifeState.ALIVE:
			fatigue_delta += get_stat_value("fatigue_recovery_rate") * delta
		elif _is_working():
			fatigue_delta -= NpcRules.FATIGUE_WORK_DRAIN * delta
		elif is_in_combat():
			fatigue_delta -= NpcRules.FATIGUE_COMBAT_DRAIN * delta
		elif is_running_enabled() and _has_move_target:
			fatigue_delta -= NpcRules.FATIGUE_RUN_DRAIN * delta
		else:
			fatigue_delta += get_stat_value("fatigue_recovery_rate") * delta
		_apply_fatigue_delta(fatigue_delta)
		if running and not can_continue_running():
			running = false
		if was_running != running:
			state_changed.emit()


func _process_bleeding(delta: float) -> void:
	if _bleed_rate <= 0.0 or life_state == NpcRules.LifeState.DEAD:
		return
	blood = clampf(blood - _bleed_rate * NpcRules.BLEED_TO_BLOOD_RATE * delta, 0.0, max_blood)
	if blood <= 0.0:
		_enter_dead_state()


func _process_recovery(delta: float) -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	var healing_step := get_stat_value("healing_rate") * delta
	if life_state == NpcRules.LifeState.ASLEEP:
		healing_step *= 6.0
	if healing_step <= 0.0:
		return
	_current_blunt_damage = maxf(0.0, _current_blunt_damage - healing_step)
	_current_bandaged_cut_damage = maxf(0.0, _current_bandaged_cut_damage - healing_step * 0.8)
	_current_open_cut_damage = maxf(0.0, _current_open_cut_damage - healing_step * 0.35)
	if _bleed_rate > 0.0:
		_bleed_rate = maxf(0.0, _bleed_rate - healing_step * 0.02)
	if life_state == NpcRules.LifeState.UNCONSCIOUS:
		_downed_recover_delay_remaining = maxf(0.0, _downed_recover_delay_remaining - delta)
	_recalculate_vitals()


func _process_ai(delta: float) -> void:
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if _current_order_type == OrderType.HEAL and (_current_heal_target == null or not is_instance_valid(_current_heal_target)):
		stop_heal_assignment()
	if _current_order_type == OrderType.FINISH_OFF and (_current_finish_off_target == null or not is_instance_valid(_current_finish_off_target) or _current_finish_off_target.life_state != NpcRules.LifeState.UNCONSCIOUS):
		stop_finish_off_assignment()
	if _current_order_type == OrderType.CARRY and (_current_carry_target == null or not is_instance_valid(_current_carry_target) or not _current_carry_target.can_be_carried_by(self)):
		stop_carry_assignment()
	if _current_order_type == OrderType.PLACE_IN_BED and (_current_place_bed_target == null or not is_instance_valid(_current_place_bed_target) or _carried_character == null or not is_instance_valid(_carried_character)):
		stop_place_in_bed_assignment()
	if _current_order_type == OrderType.PICKUP_ITEM and (_current_pickup_item == null or not is_instance_valid(_current_pickup_item)):
		stop_pickup_assignment()
	if _current_order_type == OrderType.ATTACK and (_current_attack_target == null or not is_instance_valid(_current_attack_target) or _current_attack_target.life_state != NpcRules.LifeState.ALIVE):
		stop_attack_assignment()
	_ai_tick_remaining -= delta
	if _ai_tick_remaining > 0.0:
		return
	_ai_tick_remaining = 0.35 + _rng.randf_range(0.0, 0.15)
	if _should_seek_combat_target():
		var target := _find_ai_target()
		if target != null:
			assign_attack_target(target, false)


func _process_mining(delta: float) -> void:
	if _current_mining_node == null:
		return
	var mining_position: Vector3 = _current_mining_node.get_mining_position(self)
	if global_position.distance_to(mining_position) > interact_distance:
		_set_actor_move_target(mining_position)
		_mining_active = false
		mining_changed.emit()
		return
	if _has_move_target:
		return
	_mining_active = true
	var progress := _get_stored_mining_progress(_current_mining_node) + delta
	var duration := maxf(_current_mining_node.mine_duration, 0.01)
	var mining_inventory := _work_inventory_override if _work_inventory_override != null else inventory
	if progress >= duration:
		if mining_inventory.add_item(_current_mining_node.item_definition):
			progress = 0.0
		else:
			progress = duration
			_mining_active = false
	_store_mining_progress(_current_mining_node, progress)
	mining_changed.emit()


func _process_container_interaction() -> void:
	if _current_container_target == null:
		return
	var interaction_position: Vector3 = _current_container_target.get_interaction_position(self)
	if global_position.distance_to(interaction_position) > interact_distance:
		_set_actor_move_target(interaction_position)
		return
	if _has_move_target:
		return
	var container = _current_container_target
	_current_container_target = null
	_current_order_type = OrderType.NONE
	container_reached.emit(self, container)


func _process_trade_interaction() -> void:
	if _current_trade_target == null:
		return
	var interaction_position: Vector3 = _current_trade_target.get_interaction_position(self)
	var target_position: Vector3 = _current_trade_target.global_position
	if global_position.distance_to(target_position) > trade_interaction_distance:
		_set_actor_move_target(interaction_position)
		return
	_clear_actor_move_target()
	var target = _current_trade_target
	_current_trade_target = null
	_current_order_type = OrderType.NONE
	trade_target_reached.emit(self, target)


func _process_conversation_interaction() -> void:
	if _current_conversation_target == null:
		return
	var interaction_position: Vector3 = _current_conversation_target.get_interaction_position(self)
	var target_position: Vector3 = _current_conversation_target.global_position
	if global_position.distance_to(target_position) > interact_distance:
		_set_actor_move_target(interaction_position)
		return
	_clear_actor_move_target()
	var target = _current_conversation_target
	_current_conversation_target = null
	_current_order_type = OrderType.NONE
	conversation_target_reached.emit(self, target)


func _process_sleep_interaction() -> void:
	if _current_sleep_target == null or not is_instance_valid(_current_sleep_target):
		stop_sleep_assignment()
		return
	var interaction_position: Vector3 = _current_sleep_target.get_interaction_position(self)
	if global_position.distance_to(interaction_position) > interact_distance:
		_set_actor_move_target(interaction_position)
		return
	if _has_move_target:
		return
	var sleep_result: Dictionary = _current_sleep_target.request_sleep(self) if _current_sleep_target.has_method("request_sleep") else {"allowed": true, "message": ""}
	if not sleep_result.get("allowed", false):
		var failure_message := str(sleep_result.get("message", "Cannot sleep here"))
		if not failure_message.is_empty():
			center_notice_requested.emit(failure_message)
			_show_world_notice(failure_message, Color(1.0, 0.78, 0.38, 1.0))
		stop_sleep_assignment()
		return
	if not _current_sleep_target.claim_sleeper(self):
		center_notice_requested.emit("Bed occupied")
		_show_world_notice("Bed occupied", Color(1.0, 0.78, 0.38, 1.0))
		stop_sleep_assignment()
		return
	var success_message := str(sleep_result.get("message", ""))
	if not success_message.is_empty():
		center_notice_requested.emit(success_message)
	global_position = _current_sleep_target.get_sleep_position()
	rotation = _current_sleep_target.get_sleep_rotation()
	velocity = Vector3.ZERO
	running = false
	sneaking = false
	_clear_actor_move_target()
	life_state = NpcRules.LifeState.ASLEEP
	_show_world_notice("Sleeping", Color(0.55, 0.72, 1.0, 1.0))
	state_changed.emit()


func _process_place_in_bed_interaction() -> void:
	if _current_place_bed_target == null or not is_instance_valid(_current_place_bed_target):
		stop_place_in_bed_assignment()
		return
	if _carried_character == null or not is_instance_valid(_carried_character):
		stop_place_in_bed_assignment()
		return
	var interaction_position: Vector3 = _current_place_bed_target.get_interaction_position(self)
	if global_position.distance_to(interaction_position) > interact_distance:
		_set_actor_move_target(interaction_position)
		return
	if _has_move_target:
		return
	var carried := _carried_character
	var sleep_result: Dictionary = _current_place_bed_target.request_sleep(self) if _current_place_bed_target.has_method("request_sleep") else {"allowed": true, "message": ""}
	if not sleep_result.get("allowed", false):
		var failure_message := str(sleep_result.get("message", "Cannot use this bed"))
		if not failure_message.is_empty():
			center_notice_requested.emit(failure_message)
			_show_world_notice(failure_message, Color(1.0, 0.78, 0.38, 1.0))
		stop_place_in_bed_assignment()
		return
	carried.stop_sleep_assignment()
	if not _current_place_bed_target.claim_sleeper(carried):
		center_notice_requested.emit("Bed occupied")
		_show_world_notice("Bed occupied", Color(1.0, 0.78, 0.38, 1.0))
		stop_place_in_bed_assignment()
		return
	var bed = _current_place_bed_target
	_detach_carried_character()
	carried.global_position = bed.get_sleep_position()
	carried.rotation = bed.get_sleep_rotation()
	carried.velocity = Vector3.ZERO
	carried.running = false
	carried.sneaking = false
	carried._clear_actor_move_target()
	carried._current_order_type = OrderType.SLEEP
	carried._current_sleep_target = bed
	if carried.life_state != NpcRules.LifeState.DEAD:
		carried.life_state = NpcRules.LifeState.ASLEEP
	var success_message := str(sleep_result.get("message", ""))
	if not success_message.is_empty():
		center_notice_requested.emit(success_message)
	_clear_actor_move_target()
	_current_place_bed_target = null
	_current_order_type = OrderType.NONE
	_show_world_notice("Placed in bed", Color(0.55, 0.72, 1.0, 1.0))
	state_changed.emit()
	carried.state_changed.emit()


func _process_seat_interaction() -> void:
	if _current_seat_target == null or not is_instance_valid(_current_seat_target):
		stop_seat_assignment()
		return
	if _is_sitting:
		velocity = Vector3.ZERO
		return
	var interaction_position: Vector3 = _current_seat_target.get_interaction_position(self)
	var arrival_distance := interact_distance
	if _current_seat_target.has_method("get_arrival_distance"):
		arrival_distance = maxf(arrival_distance, float(_current_seat_target.get_arrival_distance()))
	var can_snap_to_seat := false
	if _current_seat_target.has_method("can_sit_from_position"):
		can_snap_to_seat = _current_seat_target.can_sit_from_position(global_position)
	else:
		can_snap_to_seat = global_position.distance_to(interaction_position) <= arrival_distance
	if not can_snap_to_seat:
		_set_actor_move_target(interaction_position)
		return
	_clear_actor_move_target()
	if not _current_seat_target.claim_sitter(self):
		_show_world_notice("Seat occupied", Color(1.0, 0.78, 0.38, 1.0))
		stop_seat_assignment()
		return
	global_position = _current_seat_target.get_seat_position(self)
	rotation = _current_seat_target.get_seat_rotation(self)
	velocity = Vector3.ZERO
	running = false
	sneaking = false
	_clear_actor_move_target()
	_is_sitting = true
	_start_sitting_enter_animation()
	_current_order_type = OrderType.NONE
	_show_world_notice("Sitting", Color(0.55, 0.72, 1.0, 1.0))
	state_changed.emit()


func _process_attack_interaction() -> void:
	if _current_attack_target == null or not is_instance_valid(_current_attack_target):
		stop_attack_assignment()
		return
	if _current_attack_target.life_state != NpcRules.LifeState.ALIVE:
		stop_attack_assignment()
		return
	var target_position := _current_attack_target.get_combat_approach_position(self)
	var target_distance := global_position.distance_to(_current_attack_target.global_position)
	if target_distance > attack_range:
		_set_actor_move_target(target_position)
		return
	_clear_actor_move_target()
	look_at(_current_attack_target.global_position, Vector3.UP)
	if _combat_cooldown_remaining > 0.0:
		return
	var total_damage := get_stat_value("attack_damage")
	var cut_damage := total_damage * get_stat_value("cut_ratio")
	var blunt_damage := total_damage - cut_damage
	_current_attack_target.receive_attack(self, blunt_damage, cut_damage)
	_combat_cooldown_remaining = maxf(0.2, get_stat_value("attack_cooldown"))


func _process_heal_interaction() -> void:
	if _current_heal_target == null or not is_instance_valid(_current_heal_target):
		stop_heal_assignment()
		return
	if not _current_heal_target.can_receive_bandage():
		show_world_speech("They don't need bandaging", 5.0)
		stop_heal_assignment()
		return
	if _get_best_bandage_definition() == null:
		show_world_speech("I don't have anything to heal with", 5.0)
		stop_heal_assignment()
		return
	var target_position := _current_heal_target.get_combat_approach_position(self)
	if global_position.distance_to(_current_heal_target.global_position) > interact_distance:
		_set_actor_move_target(target_position)
		return
	_clear_actor_move_target()
	if _current_heal_target.apply_bandage_from(self):
		stop_heal_assignment()


func _process_finish_off_interaction() -> void:
	if _current_finish_off_target == null or not is_instance_valid(_current_finish_off_target):
		stop_finish_off_assignment()
		return
	if _current_finish_off_target.life_state != NpcRules.LifeState.UNCONSCIOUS:
		stop_finish_off_assignment()
		return
	var target_position := _current_finish_off_target.get_combat_approach_position(self)
	if global_position.distance_to(_current_finish_off_target.global_position) > interact_distance:
		_set_actor_move_target(target_position)
		return
	_clear_actor_move_target()
	_current_finish_off_target.force_kill(self)
	_show_world_notice("Finished", Color(0.95, 0.2, 0.2, 1.0))
	stop_finish_off_assignment()


func _process_carry_interaction() -> void:
	if _current_carry_target == null or not is_instance_valid(_current_carry_target):
		stop_carry_assignment()
		return
	if not _current_carry_target.can_be_carried_by(self) or _carried_character != null:
		stop_carry_assignment()
		return
	var target_position := _current_carry_target.global_position
	if global_position.distance_to(target_position) > interact_distance:
		_set_actor_move_target(target_position)
		return
	_clear_actor_move_target()
	_attach_carried_character(_current_carry_target)
	_show_world_notice("Carrying %s" % _current_carry_target.member_name, Color(0.86, 0.92, 1.0, 1.0))
	stop_carry_assignment()


func _process_pickup_interaction() -> void:
	if _current_pickup_item == null or not is_instance_valid(_current_pickup_item):
		stop_pickup_assignment()
		return
	var pickup_position: Vector3 = _current_pickup_item.global_position
	if _current_pickup_item.has_method("get_pickup_position"):
		pickup_position = _current_pickup_item.get_pickup_position(self)
	if global_position.distance_to(pickup_position) > interact_distance:
		_set_actor_move_target(pickup_position)
		return
	_clear_actor_move_target()
	if _current_pickup_item.has_method("try_pickup"):
		_current_pickup_item.try_pickup(self)
	stop_pickup_assignment()


func _get_stored_mining_progress(resource_node) -> float:
	return _mining_progress_by_node.get(resource_node.get_instance_id(), 0.0)


func _store_mining_progress(resource_node, progress: float) -> void:
	_mining_progress_by_node[resource_node.get_instance_id()] = progress


func _on_inventory_data_changed() -> void:
	inventory_changed.emit()


func has_conversation_definition() -> bool:
	return conversation_definition != null


func get_conversation_definition():
	return conversation_definition


func register_talker(member: HumanoidCharacter) -> void:
	_get_talker_slot(member)
	_pending_talker_ids[member.get_instance_id()] = true


func release_talker(member: HumanoidCharacter) -> void:
	_pending_talker_ids.erase(member.get_instance_id())
	_assigned_talkers.erase(member.get_instance_id())


func resolve_talk(member: HumanoidCharacter) -> bool:
	if member == null:
		return false
	var actor_id := member.get_instance_id()
	if not _pending_talker_ids.has(actor_id):
		return false
	_pending_talker_ids.clear()
	return true


func _get_talker_slot(member: HumanoidCharacter) -> int:
	var key := member.get_instance_id()
	if _assigned_talkers.has(key):
		return _assigned_talkers[key]
	for slot_index in range(6):
		if not _assigned_talkers.values().has(slot_index):
			_assigned_talkers[key] = slot_index
			return slot_index
	_assigned_talkers[key] = 0
	return 0


func is_player_party_member() -> bool:
	return player_party_member


func set_player_party_member(value: bool) -> void:
	player_party_member = value
	_sync_party_membership_group()


func set_selected(value: bool) -> void:
	is_selected = value
	_update_selection_state()


func set_focused(value: bool) -> void:
	is_focused = value
	_update_selection_state()


func _update_selection_state() -> void:
	_update_inspect_visual()


func _sync_party_membership_group() -> void:
	if player_party_member:
		add_to_group("party_member")
	else:
		remove_from_group("party_member")


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


func _setup_inspect_ring() -> void:
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.74
	ring_mesh.bottom_radius = 0.74
	ring_mesh.height = 0.04
	ring_mesh.radial_segments = 24
	ring_mesh.rings = 2
	_inspect_ring = MeshInstance3D.new()
	_inspect_ring.name = "InspectRing"
	_inspect_ring.mesh = ring_mesh
	_inspect_ring.position = Vector3(0.0, 0.025, 0.0)
	_inspect_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_inspect_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_inspect_ring_material.albedo_color = Color(0.72, 0.72, 0.76, 0.95)
	_inspect_ring.material_override = _inspect_ring_material
	_inspect_ring.visible = false
	add_child(_inspect_ring)


func _update_inspect_visual() -> void:
	if _inspect_ring != null:
		_inspect_ring.visible = is_inspected


func _setup_character_visual() -> void:
	var old_visual := get_node_or_null(CHARACTER_VISUAL_NODE_NAME)
	if old_visual != null:
		old_visual.free()
	_character_animation_player = null
	_character_animation_players.clear()
	_current_character_animation = ""

	var body_mesh := get_node_or_null("BodyMesh") as MeshInstance3D
	if body_mesh == null:
		return
	body_mesh.visible = true
	var resolved_body_archetype := _resolve_body_archetype()
	var resolved_body_type := _resolve_visual_body_type()
	if resolved_body_type == VisualBodyType.NONE:
		return
	var visual_scene := _get_character_visual_scene(resolved_body_type, resolved_body_archetype)
	if visual_scene == null:
		return

	var model := visual_scene.instantiate()
	if not (model is Node3D):
		model.queue_free()
		return
	var model_root := model as Node3D
	model_root.rotation.y = CHARACTER_VISUAL_YAW_OFFSET

	var visual_root := Node3D.new()
	visual_root.name = CHARACTER_VISUAL_NODE_NAME
	add_child(visual_root)
	visual_root.add_child(model_root)
	var visual_fit_scale := _fit_visual_to_body_mesh(visual_root, body_mesh)
	_setup_character_animation(model_root)
	var character_skeleton := _find_skeleton(model_root)
	_setup_equipped_clothing_visuals(visual_root, character_skeleton, resolved_body_archetype, body_mesh, visual_fit_scale)
	_setup_humanoid_grip_sockets(visual_root)
	_setup_equipped_bone_visuals(visual_root)
	_play_random_idle_animation(true)
	body_mesh.visible = false


func refresh_grip_sockets_for_body() -> void:
	var visual_root := get_node_or_null(CHARACTER_VISUAL_NODE_NAME) as Node3D
	if visual_root == null:
		return
	_setup_humanoid_grip_sockets(visual_root)
	_refresh_bone_equipment_slots(BONE_EQUIPMENT_SLOTS.keys())


func _rebuild_character_visual_for_equipment() -> void:
	if not is_inside_tree():
		return
	_setup_character_visual()


func _can_refresh_bone_equipment_only(changed_slots: Array) -> bool:
	if not is_inside_tree() or changed_slots.is_empty():
		return false
	for slot_name in changed_slots:
		if not BONE_EQUIPMENT_SLOTS.has(str(slot_name)):
			return false
	var visual_root := get_node_or_null(CHARACTER_VISUAL_NODE_NAME) as Node3D
	if visual_root == null:
		return false
	return _find_skeleton(visual_root) != null


func _refresh_bone_equipment_slots(changed_slots: Array) -> void:
	var visual_root := get_node_or_null(CHARACTER_VISUAL_NODE_NAME) as Node3D
	if visual_root == null:
		_rebuild_character_visual_for_equipment()
		return
	var skeleton := _find_skeleton(visual_root)
	if skeleton == null:
		_rebuild_character_visual_for_equipment()
		return
	for slot_name in changed_slots:
		_refresh_bone_equipment_slot(skeleton, str(slot_name))


func _refresh_bone_equipment_slot(skeleton: Skeleton3D, slot_name: String) -> void:
	_remove_bone_equipment_slot(skeleton, slot_name)
	var item := get_equipped_item(slot_name)
	_add_bone_equipment_slot(skeleton, slot_name, item)


func _remove_bone_equipment_slot(skeleton: Skeleton3D, slot_name: String) -> void:
	var existing_visual := _find_node3d_by_name(skeleton, _get_bone_equipment_visual_name(slot_name))
	if existing_visual != null:
		existing_visual.free()
	var legacy_attachment := skeleton.get_node_or_null(_get_bone_attachment_name(slot_name))
	if legacy_attachment != null:
		legacy_attachment.free()


func _has_equipped_clothing_visuals() -> bool:
	var resolved_body_archetype := _resolve_body_archetype()
	for slot_name in CLOTHING_EQUIPMENT_SLOTS:
		var item := get_equipped_item(slot_name)
		if item != null and item.get_equipped_scene_for_body_archetype(resolved_body_archetype) != null:
			return true
	return false


func _setup_equipped_clothing_visuals(visual_root: Node3D, character_skeleton: Skeleton3D, body_archetype: Resource, body_mesh: MeshInstance3D, visual_fit_scale: float) -> void:
	var surface_offset_base := _get_clothing_surface_offset_base(body_mesh, visual_fit_scale)
	for slot_name in CLOTHING_EQUIPMENT_SLOTS:
		var item := get_equipped_item(slot_name)
		if item == null:
			continue
		var equipment_visual := item.get_equipment_visual_for_body_archetype(body_archetype)
		var equipped_scene := item.get_equipped_scene_for_body_archetype(body_archetype)
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
	_setup_character_animation(model_root)


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
	clothing_mesh.material_override = source_mesh.material_override
	for surface_index in range(source_mesh.get_surface_override_material_count()):
		clothing_mesh.set_surface_override_material(surface_index, source_mesh.get_surface_override_material(surface_index))
	for blend_shape_index in range(source_mesh.get_blend_shape_count()):
		clothing_mesh.set_blend_shape_value(blend_shape_index, source_mesh.get_blend_shape_value(blend_shape_index))
	return clothing_mesh


func _setup_equipped_bone_visuals(visual_root: Node3D) -> void:
	var skeleton := _find_skeleton(visual_root)
	if skeleton == null:
		return
	for slot_name in BONE_EQUIPMENT_SLOTS.keys():
		var item := get_equipped_item(slot_name)
		_add_bone_equipment_slot(skeleton, slot_name, item)


func _add_bone_equipment_slot(skeleton: Skeleton3D, slot_name: String, item: ItemDefinition) -> void:
	if item == null:
		return
	var equipped_scene := item.get_equipped_scene_for_body_archetype(_resolve_body_archetype())
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
	var attachment := skeleton.get_node_or_null(attachment_name) as BoneAttachment3D
	if attachment == null:
		var bone_name := _get_equipment_socket_bone_name(socket_id)
		if bone_name.is_empty():
			bone_name = fallback_bone_name
		if bone_name.is_empty() or skeleton.find_bone(bone_name) < 0:
			return null
		attachment = BoneAttachment3D.new()
		attachment.name = attachment_name
		attachment.bone_name = bone_name
		skeleton.add_child(attachment)
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


func _get_character_visual_scene(body_type: int, resolved_body_archetype: Resource) -> PackedScene:
	if resolved_body_archetype != null:
		var archetype_visual_scene := resolved_body_archetype.get("visual_scene") as PackedScene
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
	var visual_ground_y := _get_visual_ground_y(body_bounds.position.y) + CHARACTER_VISUAL_FOOT_CLEARANCE
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
		inflated_mesh.add_surface_from_arrays(source_mesh.surface_get_primitive_type(surface_index), arrays)
		inflated_mesh.surface_set_material(surface_index, source_mesh.surface_get_material(surface_index))
	mesh_instance.mesh = inflated_mesh


func _get_visual_ground_y(fallback_y: float) -> float:
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
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


func _setup_character_animation(model_root: Node3D) -> void:
	var animation_player := AnimationPlayer.new()
	animation_player.name = CHARACTER_ANIMATION_PLAYER_NAME
	animation_player.root_node = NodePath("..")
	model_root.add_child(animation_player)
	var animation_library := AnimationLibrary.new()
	_copy_character_animations(animation_library)
	if animation_library.get_animation_list().is_empty():
		animation_player.queue_free()
		return
	animation_player.add_animation_library("", animation_library)
	_character_animation_players.append(animation_player)
	if _character_animation_player == null:
		_character_animation_player = animation_player


func _copy_character_animations(animation_library: AnimationLibrary) -> void:
	var ual1_source := UAL1_ANIMATION_SOURCE_SCENE.instantiate()
	var ual1_player := _find_animation_player(ual1_source)
	if ual1_player != null:
		_copy_animation(ual1_player, animation_library, IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, WALK_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, CROUCH_IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, CROUCH_WALK_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, JOG_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, SPRINT_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, SITTING_ENTER_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, SITTING_IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, SITTING_TALKING_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, SITTING_EXIT_ANIMATION_NAME)
	ual1_source.queue_free()

	var ual2_source := UAL2_ANIMATION_SOURCE_SCENE.instantiate()
	var ual2_player := _find_animation_player(ual2_source)
	if ual2_player != null:
		_copy_animation(ual2_player, animation_library, FOLD_ARMS_IDLE_ANIMATION_NAME)
	ual2_source.queue_free()


func _copy_animation(source_player: AnimationPlayer, animation_library: AnimationLibrary, animation_name: String) -> void:
	if not source_player.has_animation(animation_name) or animation_library.has_animation(animation_name):
		return
	var source_animation := source_player.get_animation(animation_name)
	if source_animation == null:
		return
	var copied_animation := source_animation.duplicate(true) as Animation
	animation_library.add_animation(animation_name, copied_animation)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


func _update_character_animation(delta: float) -> void:
	if _character_animation_player == null:
		return
	if _is_sitting:
		_update_sitting_character_animation(delta)
		return
	if _sitting_exit_animation_remaining > 0.0 and not _has_move_target:
		_update_sitting_exit_animation(delta)
		return
	_sitting_exit_animation_remaining = 0.0
	if life_state != NpcRules.LifeState.ALIVE or _carried_by != null:
		_update_idle_character_animation(delta)
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := horizontal_speed > 0.18 and _has_move_target
	if sneaking:
		if is_moving:
			_play_character_animation(CROUCH_WALK_ANIMATION_NAME, _get_animation_speed_ratio(horizontal_speed, move_speed * 0.65))
		else:
			_play_character_animation(CROUCH_IDLE_ANIMATION_NAME)
		return
	if not is_moving:
		_update_idle_character_animation(delta)
		return
	if is_running_enabled():
		var sprint_speed_ratio := _get_animation_speed_ratio(horizontal_speed, move_speed * NpcRules.RUN_SPEED_MULTIPLIER)
		if _should_use_sprint_animation(sprint_speed_ratio):
			_play_character_animation(SPRINT_ANIMATION_NAME, sprint_speed_ratio)
		else:
			_play_character_animation(JOG_ANIMATION_NAME, _get_animation_speed_ratio(horizontal_speed, move_speed))
	else:
		_play_character_animation(WALK_ANIMATION_NAME, _get_animation_speed_ratio(horizontal_speed, move_speed))


func _should_use_sprint_animation(speed_ratio: float) -> bool:
	if not is_running_enabled():
		return false
	if hunger_stage != NpcRules.HungerStage.WELL_NOURISHED:
		return false
	if fatigue_stage != NpcRules.FatigueStage.WELL_RESTED:
		return false
	return speed_ratio >= SPRINT_ANIMATION_SPEED_RATIO


func _get_animation_speed_ratio(horizontal_speed: float, reference_speed: float) -> float:
	return clampf(horizontal_speed / maxf(reference_speed, 0.001), 0.0, 1.0)


func _update_idle_character_animation(delta: float) -> void:
	if not _is_idle_animation(_current_character_animation) or not _character_animation_player.is_playing():
		_play_random_idle_animation(true)
		return
	_idle_animation_change_remaining -= delta
	if _idle_animation_change_remaining <= 0.0:
		_play_random_idle_animation(false)


func _play_random_idle_animation(force: bool) -> void:
	var idle_names := _get_available_idle_animation_names()
	if idle_names.is_empty():
		return
	var animation_index := _rng.randi_range(0, idle_names.size() - 1)
	var animation_name := idle_names[animation_index]
	if not force and idle_names.size() > 1 and animation_name == _current_character_animation:
		animation_name = idle_names[(animation_index + 1) % idle_names.size()]
	_play_character_animation(animation_name)
	_reset_idle_animation_timer()


func _get_available_idle_animation_names() -> Array[String]:
	var idle_names: Array[String] = []
	if _character_animation_player == null:
		return idle_names
	for animation_name_value in IDLE_ANIMATION_NAMES:
		var animation_name := String(animation_name_value)
		if _character_animation_player.has_animation(animation_name):
			idle_names.append(animation_name)
	return idle_names


func _is_idle_animation(animation_name: String) -> bool:
	return IDLE_ANIMATION_NAMES.has(animation_name)


func _reset_idle_animation_timer() -> void:
	_idle_animation_change_remaining = _rng.randf_range(IDLE_ANIMATION_MIN_SECONDS, IDLE_ANIMATION_MAX_SECONDS)


func _start_sitting_enter_animation() -> void:
	_sitting_exit_animation_remaining = 0.0
	_sitting_idle_change_remaining = 0.0
	if _play_character_animation(SITTING_ENTER_ANIMATION_NAME):
		_sitting_enter_animation_remaining = _get_character_animation_length(SITTING_ENTER_ANIMATION_NAME)
	else:
		_sitting_enter_animation_remaining = 0.0
		_play_sitting_idle_animation(true)


func _start_sitting_exit_animation() -> void:
	_sitting_enter_animation_remaining = 0.0
	_sitting_idle_change_remaining = 0.0
	if _play_character_animation(SITTING_EXIT_ANIMATION_NAME):
		_sitting_exit_animation_remaining = _get_character_animation_length(SITTING_EXIT_ANIMATION_NAME)
	else:
		_sitting_exit_animation_remaining = 0.0


func _update_sitting_character_animation(delta: float) -> void:
	velocity = Vector3.ZERO
	if _sitting_enter_animation_remaining > 0.0:
		_sitting_enter_animation_remaining -= delta
		if _sitting_enter_animation_remaining > 0.0:
			_play_character_animation(SITTING_ENTER_ANIMATION_NAME)
			return
		_sitting_enter_animation_remaining = 0.0
		_play_sitting_idle_animation(true)
		return
	if not _is_sitting_idle_animation(_current_character_animation) or not _character_animation_player.is_playing():
		_play_sitting_idle_animation(true)
		return
	_sitting_idle_change_remaining -= delta
	if _sitting_idle_change_remaining <= 0.0:
		_play_sitting_idle_animation(false)


func _update_sitting_exit_animation(delta: float) -> void:
	_sitting_exit_animation_remaining = maxf(0.0, _sitting_exit_animation_remaining - delta)
	if _sitting_exit_animation_remaining > 0.0:
		_play_character_animation(SITTING_EXIT_ANIMATION_NAME)


func _play_sitting_idle_animation(force: bool) -> void:
	if _character_animation_player == null:
		return
	var animation_name := SITTING_IDLE_ANIMATION_NAME
	if _should_use_sitting_talking_idle() and _rng.randf() <= SITTING_TALKING_CHANCE:
		animation_name = SITTING_TALKING_ANIMATION_NAME
	if not _character_animation_player.has_animation(animation_name):
		animation_name = SITTING_IDLE_ANIMATION_NAME
	if not _character_animation_player.has_animation(animation_name):
		return
	if not force and animation_name == _current_character_animation and animation_name == SITTING_TALKING_ANIMATION_NAME:
		animation_name = SITTING_IDLE_ANIMATION_NAME
	_play_character_animation(animation_name)
	_reset_sitting_idle_animation_timer()


func _should_use_sitting_talking_idle() -> bool:
	if _current_seat_target == null or not is_instance_valid(_current_seat_target):
		return false
	if player_party_member:
		return false
	if not _current_seat_target.has_method("should_use_sitting_talking_idle"):
		return false
	return bool(_current_seat_target.should_use_sitting_talking_idle(self))


func _is_sitting_idle_animation(animation_name: String) -> bool:
	return animation_name == SITTING_IDLE_ANIMATION_NAME or animation_name == SITTING_TALKING_ANIMATION_NAME


func _reset_sitting_idle_animation_timer() -> void:
	_sitting_idle_change_remaining = _rng.randf_range(SITTING_IDLE_MIN_SECONDS, SITTING_IDLE_MAX_SECONDS)


func _get_character_animation_length(animation_name: String) -> float:
	if _character_animation_player == null or not _character_animation_player.has_animation(animation_name):
		return 0.0
	var animation := _character_animation_player.get_animation(animation_name)
	return animation.length if animation != null else 0.0


func _play_character_animation(animation_name: String, speed_ratio: float = 0.0) -> bool:
	if _character_animation_player == null or not _character_animation_player.has_animation(animation_name):
		return false
	var custom_speed := _get_character_animation_speed(animation_name, speed_ratio)
	var already_current := _current_character_animation == animation_name
	_current_character_animation = animation_name
	for animation_player in _character_animation_players:
		if animation_player == null or not animation_player.has_animation(animation_name):
			continue
		animation_player.speed_scale = custom_speed
		if already_current and animation_player.is_playing():
			continue
		animation_player.play(animation_name, MOVE_ANIMATION_BLEND_SECONDS)
	return true


func _get_character_animation_speed(animation_name: String, speed_ratio: float) -> float:
	match animation_name:
		WALK_ANIMATION_NAME:
			return lerpf(0.85, 1.25, speed_ratio)
		CROUCH_WALK_ANIMATION_NAME:
			return lerpf(0.85, 1.15, speed_ratio)
		JOG_ANIMATION_NAME:
			return lerpf(0.9, 1.35, speed_ratio)
		SPRINT_ANIMATION_NAME:
			return lerpf(0.9, 1.25, speed_ratio)
	return 1.0


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


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := transform * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds


func _set_order(order_type: int, issued_by_player: bool) -> void:
	if issued_by_player and _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, true)
	_cancel_non_matching_assignments(order_type)
	_current_order_type = int(order_type)
	_order_was_player_issued = issued_by_player
	if order_type != OrderType.MINE:
		_mining_active = false
		mining_changed.emit()


func _cancel_non_matching_assignments(next_order_type: int) -> void:
	if next_order_type != OrderType.MINE:
		stop_mining_assignment()
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
	if next_order_type != OrderType.SIT:
		stop_seat_assignment()
	if next_order_type != OrderType.PICKUP_ITEM:
		stop_pickup_assignment()


func _seed_starting_inventory() -> void:
	for stock in starting_items:
		if stock != null and stock.item_definition != null and stock.quantity > 0:
			inventory.add_item_count(stock.item_definition, stock.quantity)


func _seed_starting_equipment() -> void:
	for stock in starting_equipment:
		if stock == null:
			continue
		var item_definition: ItemDefinition = null
		if stock is ItemDefinition:
			item_definition = stock
		elif stock.get("item_definition") is ItemDefinition:
			item_definition = stock.item_definition
		if item_definition == null or not item_definition.is_equippable():
			continue
		if get_equipped_item(item_definition.equip_slot) == null:
			equipped_items[item_definition.equip_slot] = item_definition


func _recalculate_vitals() -> void:
	hp = max_hp - get_total_wound_damage()
	if life_state == NpcRules.LifeState.DEAD:
		return
	if blood <= 0.0:
		if life_state != NpcRules.LifeState.DEAD:
			_enter_dead_state()
		return
	if hp <= -max_hp * NpcRules.DEATH_HP_FACTOR:
		if life_state != NpcRules.LifeState.DEAD:
			_enter_dead_state()
		return
	if hp <= 0.0:
		if life_state == NpcRules.LifeState.ALIVE:
			_enter_unconscious_state()
		return
	if life_state != NpcRules.LifeState.ALIVE and life_state != NpcRules.LifeState.ASLEEP and _downed_recover_delay_remaining <= 0.0 and _carried_by == null:
		life_state = NpcRules.LifeState.ALIVE
		_restore_from_downed_state()
		state_changed.emit()


func _enter_unconscious_state() -> void:
	if life_state == NpcRules.LifeState.DEAD or life_state == NpcRules.LifeState.UNCONSCIOUS:
		return
	life_state = NpcRules.LifeState.UNCONSCIOUS
	running = false
	_clear_actor_move_target()
	_downed_is_settled = false
	_clear_all_active_orders()
	if _carried_character != null:
		drop_carried_character()
	if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, false)
	_downed_recover_delay_remaining = 15.0
	_enter_downed_state(false)
	_show_world_notice("Unconscious", Color(1.0, 0.85, 0.45, 1.0))
	state_changed.emit()


func _enter_dead_state() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	life_state = NpcRules.LifeState.DEAD
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
	state_changed.emit()


func _get_base_stat_value(stat_name: String) -> float:
	match stat_name:
		"attack_damage":
			return base_attack_damage
		"attack_cooldown":
			return attack_cooldown_seconds
		"cut_ratio":
			return attack_cut_ratio
		"dodge_chance":
			return base_dodge_chance
		"block_chance":
			return base_block_chance
		"move_speed_multiplier":
			return 1.0
		"run_speed_multiplier":
			return NpcRules.RUN_SPEED_MULTIPLIER
		"hunger_drain_rate":
			return hunger_drain_rate
		"fatigue_recovery_rate":
			return NpcRules.FATIGUE_IDLE_RECOVERY
		"healing_rate":
			return NpcRules.BASE_HEAL_RATE
	return 0.0


func _collect_stat_modifiers() -> Array:
	var modifiers: Array = []
	NpcRules.append_stage_modifiers(modifiers, get_hunger_stage(), get_fatigue_stage(), _current_open_cut_damage, max_hp)
	if life_state == NpcRules.LifeState.UNCONSCIOUS:
		modifiers.append({"stat": "healing_rate", "mul": NpcRules.UNCONSCIOUS_HEAL_MULTIPLIER})
	if running and _has_move_target:
		modifiers.append({"stat": "move_speed_multiplier", "mul": _get_base_stat_value("run_speed_multiplier")})
	if sneaking:
		modifiers.append({"stat": "move_speed_multiplier", "mul": 0.65})
	if is_carrying_someone():
		modifiers.append({"stat": "move_speed_multiplier", "mul": carry_move_speed_multiplier})
	for item in equipped_items.values():
		if not (item is ItemDefinition):
			continue
		for modifier in (item as ItemDefinition).stat_modifiers:
			if modifier == null:
				continue
			modifiers.append(modifier.to_modifier_dictionary())
	return modifiers


func get_stat_value(stat_name: String, include_secondary_modifiers: bool = true) -> float:
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
			"attack_cooldown":
				value = maxf(0.2, value)
			"move_speed_multiplier", "run_speed_multiplier", "attack_damage", "hunger_drain_rate", "fatigue_recovery_rate", "healing_rate":
				value = maxf(0.0, value)
	return value


func _get_current_move_speed() -> float:
	return move_speed * get_stat_value("move_speed_multiplier")


func _should_seek_combat_target() -> bool:
	if _current_order_type == OrderType.HEAL:
		return false
	if _carried_by != null or is_carrying_someone():
		return false
	if _current_order_type == OrderType.ATTACK and _current_attack_target != null:
		return false
	if _order_was_player_issued and _current_order_type in [OrderType.MOVE, OrderType.MINE, OrderType.OPEN_CONTAINER, OrderType.TRADE]:
		return false
	if combat_stance == NpcRules.CombatStance.PASSIVE and _last_direct_attacker_id == 0:
		return false
	return true


func _find_ai_target() -> HumanoidCharacter:
	if combat_stance == NpcRules.CombatStance.PASSIVE:
		return _get_last_direct_attacker_target()
	if combat_stance == NpcRules.CombatStance.DEFENSIVE:
		var self_defense_target := _get_last_direct_attacker_target()
		if self_defense_target != null:
			return self_defense_target
		return _find_defensive_assist_target()
	return _find_nearest_hostile(aggressive_scan_radius)


func _get_last_direct_attacker_target() -> HumanoidCharacter:
	if _last_direct_attacker_id == 0:
		return null
	for node in get_tree().get_nodes_in_group("npc_character"):
		if node is HumanoidCharacter and node.get_instance_id() == _last_direct_attacker_id and node.life_state == NpcRules.LifeState.ALIVE:
			return node
	return null


func _find_defensive_assist_target() -> HumanoidCharacter:
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var ally: HumanoidCharacter = node
		if ally == self or ally.life_state == NpcRules.LifeState.DEAD:
			continue
		if not _should_defend_ally(ally):
			continue
		if global_position.distance_to(ally.global_position) > assist_scan_radius:
			continue
		var ally_target := ally.get_current_combat_target()
		if ally_target != null and is_instance_valid(ally_target) and ally_target.life_state == NpcRules.LifeState.ALIVE and has_hostility_with(ally_target):
			return ally_target
	return null


func _should_defend_ally(ally: HumanoidCharacter) -> bool:
	if ally == null:
		return false
	if ally.faction_name != faction_name:
		return false
	if ally.squad_name != squad_name:
		return false
	# Allied faction assistance can expand here once deeper faction relations are added.
	return true


func _find_nearest_hostile(scan_radius: float) -> HumanoidCharacter:
	var best_target: HumanoidCharacter
	var best_distance := scan_radius
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var candidate: HumanoidCharacter = node
		if candidate == self or candidate.life_state != NpcRules.LifeState.ALIVE:
			continue
		if not has_hostility_with(candidate):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best_target = candidate
	return best_target


func _try_start_self_defense(attacker: HumanoidCharacter) -> void:
	if attacker == null or attacker.life_state != NpcRules.LifeState.ALIVE:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	assign_attack_target(attacker, false, false, false)
	_set_actor_move_target(attacker.get_combat_approach_position(self))


func _notify_defensive_allies_of_attack(attacker: HumanoidCharacter) -> void:
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var ally: HumanoidCharacter = node
		if ally == self:
			continue
		ally._respond_to_ally_under_attack(self, attacker)


func _notify_defensive_allies_of_engagement(target: HumanoidCharacter) -> void:
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var ally: HumanoidCharacter = node
		if ally == self:
			continue
		ally._respond_to_ally_engagement(self, target)


func _respond_to_ally_under_attack(ally: HumanoidCharacter, attacker: HumanoidCharacter) -> void:
	if ally == null or attacker == null:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if combat_stance == NpcRules.CombatStance.PASSIVE:
		return
	if not _should_defend_ally(ally):
		return
	if global_position.distance_to(ally.global_position) > assist_scan_radius:
		return
	mark_hostile(attacker)
	attacker.mark_hostile(self)
	assign_attack_target(attacker, false, false, false)


func _respond_to_ally_engagement(ally: HumanoidCharacter, target: HumanoidCharacter) -> void:
	if ally == null or target == null:
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if combat_stance == NpcRules.CombatStance.PASSIVE:
		return
	if not _should_defend_ally(ally):
		return
	if global_position.distance_to(ally.global_position) > assist_scan_radius:
		return
	if target.life_state != NpcRules.LifeState.ALIVE:
		return
	mark_hostile(target)
	target.mark_hostile(self)
	assign_attack_target(target, false, false, false)


func _clear_all_active_orders() -> void:
	stop_mining_assignment()
	stop_container_interaction()
	stop_trade_interaction()
	stop_conversation_interaction()
	stop_attack_assignment()
	stop_heal_assignment()
	stop_finish_off_assignment()
	stop_carry_assignment()
	stop_sleep_assignment()
	stop_place_in_bed_assignment()
	stop_seat_assignment()
	stop_pickup_assignment()
	_current_order_type = OrderType.NONE
	_clear_actor_move_target()


func force_kill(_attacker: HumanoidCharacter = null) -> void:
	blood = 0.0
	hp = -max_hp * NpcRules.DEATH_HP_FACTOR
	_enter_dead_state()


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
	carried.collision_layer = carried._stored_collision_layer
	carried.collision_mask = carried._stored_collision_mask
	return carried


func _attach_carried_character(target_character: HumanoidCharacter) -> void:
	_carried_character = target_character
	target_character._carried_by = self
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
	target_character._update_carried_transform()
	state_changed.emit()


func _update_carried_transform() -> void:
	if _carried_by == null:
		return
	var offset := Vector3(0.0, 1.8, 0.4)
	global_position = _carried_by.global_position + _carried_by.transform.basis * offset
	rotation = Vector3(0.0, _carried_by.rotation.y, deg_to_rad(88.0))


func _enter_downed_state(is_dead: bool) -> void:
	if _carried_by != null:
		return
	_clear_actor_move_target()
	_downed_is_settled = false
	velocity = transform.basis.z * -0.8
	velocity.y = 0.0
	_downed_target_rotation_z = deg_to_rad(90.0 if _rng.randf() > 0.5 else -90.0)
	if is_dead:
		_downed_target_rotation_z *= 1.0


func _restore_from_downed_state() -> void:
	if _carried_by != null:
		return
	_downed_is_settled = false
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	collision_layer = _stored_collision_layer
	collision_mask = _stored_collision_mask
	_show_world_notice("Recovered", Color(0.5, 1.0, 0.65, 1.0))


func _show_world_notice(message: String, color: Color = Color(1.0, 0.28, 0.28, 1.0), lifetime: float = 1.0, rise_height: float = 0.4) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var notice = WORLD_TEXT_NOTICE_SCENE.instantiate()
	tree.current_scene.add_child(notice)
	if notice.has_method("setup"):
		notice.setup(global_position + Vector3(0.0, overhead_text_height, 0.0), message, color, lifetime, rise_height)


func _is_working() -> bool:
	return _current_order_type == OrderType.MINE and _mining_active


func _get_best_bandage_definition() -> ItemDefinition:
	var best_definition: ItemDefinition
	var best_power := -1.0
	for entry in inventory.entries:
		if not can_use_bandage_item(entry.definition):
			continue
		if entry.definition.bandage_power > best_power:
			best_definition = entry.definition
			best_power = entry.definition.bandage_power
	return best_definition
