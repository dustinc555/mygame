extends CharacterBody3D

class_name WorldActor

const ACTOR_SKILL_SET_SCRIPT = preload("res://scripts/skills/actor_skill_set.gd")
const COMBAT_COORDINATOR = preload("res://scripts/characters/combat_coordinator.gd")
const AI_BRAIN_SCRIPT = preload("res://scripts/ai/ai_brain.gd")
const AI_JOB_SCRIPT = preload("res://scripts/ai/ai_job.gd")
const AI_UTILITY_ADAPTER_SCRIPT = preload("res://scripts/ai/utility/ai_utility_adapter.gd")
const ACTOR_CAPABILITY_SCRIPT = preload("res://scripts/actors/capabilities/actor_capability.gd")
const INVENTORY_CAPABILITY_SCRIPT = preload("res://scripts/actors/capabilities/inventory_capability.gd")
const EQUIPMENT_CAPABILITY_SCRIPT = preload("res://scripts/actors/capabilities/equipment_capability.gd")
const COMBAT_CAPABILITY_SCRIPT = preload("res://scripts/actors/capabilities/combat_capability.gd")
const AI_TARGETING_CAPABILITY_SCRIPT = preload("res://scripts/actors/capabilities/ai_targeting_capability.gd")
const INTERACTION_CAPABILITY_SCRIPT = preload("res://scripts/actors/capabilities/interaction_capability.gd")
const CUSTODY_CAPABILITY_SCRIPT = preload("res://scripts/actors/capabilities/custody_capability.gd")

# Containment size classes -- how big a cage an actor needs. A standard jail cell
# holds up to CONTAINMENT_SIZE_MEDIUM; larger creatures need special cages.
const CONTAINMENT_SIZE_SMALL := 0
const CONTAINMENT_SIZE_MEDIUM := 1
const CONTAINMENT_SIZE_LARGE := 2
const CONTAINMENT_SIZE_HUGE := 3

const NAVIGATION_MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED := 0.0025
const ACTIVE_COMBAT_ACTOR_GROUP := "active_combat_actor"
const COMBAT_SCORE_CHANCE_DIVISOR := 220.0
const COMBAT_ATTRIBUTE_ASSIST_WEIGHT := 0.25
const COMBAT_DAMAGE_SKILL_WEIGHT := 0.20
const COMBAT_DAMAGE_ATTRIBUTE_WEIGHT := 0.25
const COMBAT_BODY_TOUGHNESS_BASE_WEIGHT := 0.025
const COMBAT_LEGACY_CHANCE_TO_SCORE := 220.0
const COMBAT_CRIT_SKILL_WEIGHT := 0.00303
const COMBAT_CRIT_DEXTERITY_WEIGHT := 0.00190
const TOUGHNESS_GRIT_RESISTANCE_WEIGHT := 0.0045
const TOUGHNESS_GRIT_RESISTANCE_CAP := 0.45
const TOUGHNESS_GRIT_SOAK_WEIGHT := 0.20
const COMA_BASE_FACTOR := 0.10
const COMA_TOUGHNESS_WEIGHT := 0.0075
const COMA_FACTOR_CAP := 0.85
const DYING_BASE_SECONDS := 20.0
const DYING_TOUGHNESS_SECONDS := 0.8

signal state_changed
@warning_ignore("unused_signal")
signal combat_state_changed
@warning_ignore("unused_signal")
signal life_state_changed(previous_state: int, next_state: int)
@warning_ignore("unused_signal")
signal died(actor: WorldActor)
signal center_notice_requested(message)
signal inventory_changed

@export var skill_set: ActorSkillSet
@export var starting_skill_levels: Dictionary = {}

@export var member_name := "Character"
@export var stable_id := ""
@export var faction_name := "Player"
@export var squad_name := "Default"
@export var world_squad_id := ""
@export var hostile_factions: PackedStringArray = PackedStringArray()

@export var hunger_enabled := false
@export var interact_distance := 1.8
@export_range(0, 2, 1) var hunger_stage: int = NpcRules.HungerStage.WELL_NOURISHED
@export var hunger := 100.0
@export var hunger_drain_rate := 0.08
@export var fatigue_enabled := true
@export_range(0, 2, 1) var fatigue_stage: int = NpcRules.FatigueStage.WELL_RESTED
@export var fatigue := 100.0
@export var running := false
@export var sneaking := false
@export var ai_brain_enabled := true
@export var auto_heal_enabled := false
@export var auto_burn_rustdead_enabled := false
@export_range(0, 2, 1) var combat_stance := NpcRules.CombatStance.DEFENSIVE

@export var max_hp := 100.0
@export var hp := 100.0
@export var base_max_blood := 0.0
@export var max_blood := 100.0
@export var blood := 100.0

@export var aggressive_scan_radius := NpcRules.AGGRO_RANGE
@export var assist_scan_radius := NpcRules.ASSIST_RANGE
@export var combat_witness_radius := NpcRules.COMBAT_WITNESS_RANGE
@export var combat_squad_assist_radius := NpcRules.SQUAD_ASSIST_RANGE
@export var combat_support_target_spread_radius := NpcRules.COMBAT_WITNESS_RANGE
@export var attack_range := 1.15
@export var combat_approach_arrival_distance := 0.3
@export var combat_direct_chase_distance := 3.0
@export var combat_chase_leash_distance := 42.0
@export var combat_active_attack_slots := 3
@export var combat_attack_forgiveness_buffer := 0.15
@export var combat_settle_band_extra := 0.65
@export var combat_settle_speed_multiplier := 0.32
@export var combat_personal_space_padding := 0.16
@export var combat_wait_ring_extra := 1.45
@export var combat_direct_translation_enabled := true
@export var combat_close_retarget_interval_seconds := 0.5
@export var combat_close_retarget_jitter_seconds := 0.25
@export var combat_consider_retarget_interval_seconds := 0.5
@export var combat_consider_retarget_jitter_seconds := 0.25
@export var attack_cooldown_seconds := 1.2
@export var base_attack_damage := 18.0
@export var base_dexterity := 10.0
@export_range(0.0, 1.0, 0.01) var attack_cut_ratio := 0.05
@export var base_dodge_chance := 0.08
@export var base_block_chance := 0.06
@export var block_damage_multiplier := 0.4
@export var conversation_definition: Resource

@export var inventory_columns := 10
@export var inventory_rows := 4
@export var max_carry_weight := 60.0
@export var show_inventory_weight := true
@export var starting_items: Array[Resource] = []
@export var starting_equipment: Array[Resource] = []

@export var move_speed := 3.2
@export var acceleration := 10.0
@export var floor_snap_distance := 0.9
@export var max_walkable_slope_degrees := 55.0
@export var move_target_vertical_tolerance := 0.75

@export var use_navigation_pathing := true
@export var navigation_avoidance_enabled := true
@export var navigation_agent_radius := 0.45
@export var navigation_agent_height := 2.0
@export var navigation_path_desired_distance := 0.75
@export var navigation_target_desired_distance := 0.6
@export var navigation_path_height_offset := 0.9
@export var navigation_unreachable_tolerance := 2.0
## Vertical slack for deciding a move target is reachable. Kept separate from
## move_target_vertical_tolerance (which combat reuses for attack reach) so nav
## can be forgiving of bumpy-terrain navmesh height wobble WITHOUT letting actors
## "reach" a cliff/wall top or another floor — anything past this stays unreachable.
@export var navigation_reachable_vertical_tolerance := 2.0
@export var navigation_neighbor_distance := 2.4
@export var navigation_max_neighbors := 8
@export var navigation_time_horizon_agents := 0.7
@export var stuck_check_seconds := 2.0
@export var stuck_min_progress := 0.12
@export var stuck_repath_attempt_limit := 8

var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var player_party_member := false
var life_state := NpcRules.LifeState.ALIVE
var _current_order_type := 0
var _order_was_player_issued := false
var _shared_combat_target: Node
var _move_target := Vector3.ZERO
var _has_move_target := false
var _current_blunt_damage := 0.0
var _current_open_cut_damage := 0.0
var _current_bandaged_cut_damage := 0.0
var _bleed_rate := 0.0
var _bleed_burst_rate := 0.0
var _personal_hostile_ids: Dictionary = {}
var _last_direct_attacker_id := 0
var _system_target_id := 0
var _system_combat_action_active := false
var _system_combat_reaction_remaining := 0.0
var _system_combat_cooldown_remaining := 0.0
var _system_combat_focus_id := 0
var _system_movement_active := false
var _system_movement_settled := false
var _system_movement_target_position := Vector3.ZERO
var _system_movement_desired_velocity := Vector3.ZERO
var _system_movement_look_target := Vector3.ZERO
var _system_movement_collision_focus_id := 0
var _system_movement_collision_exception_focus_id := 0
var _system_movement_collision_exception_peer: CollisionObject3D
var _assigned_talkers: Dictionary = {}
var _pending_talker_ids: Dictionary = {}
var _runtime_controller_cache: Dictionary = {}
var _ai_brain
var _ai_utility_adapter
var _ai_job_tick_remaining := 0.0
var _ai_job_tick_accumulated := 0.0
var _close_combat_retarget_remaining := 0.0
var _consider_retarget_remaining := 0.0
var _active_job_provider
var _active_job_label := ""
var inventory: InventoryData
var _work_inventory_override: InventoryData
var equipped_items: Dictionary = {}
var _actor_capabilities: Array = []
var _actor_capability_by_id: Dictionary = {}
var _actor_process_capabilities: Array = []
var _actor_physics_process_capabilities: Array = []
var _actor_capabilities_ready := false
var _actor_capability_defaults_initialized := false
var _custody_capability
var _legal_status: ActorLegalStatus

var _navigation_agent: NavigationAgent3D
var _navigation_target_synced := false
var _navigation_synced_target := Vector3.ZERO
var _navigation_query_grace_remaining := 0.0
var _avoidance_velocity := Vector3.ZERO
var _has_avoidance_velocity := false
var _stuck_origin := Vector3.ZERO
var _stuck_target_distance := INF
var _stuck_seconds := 0.0
var _stuck_repath_attempts := 0
var _navigation_zero_waypoint_blocked := false
var _starting_skill_levels_applied := false
var _base_max_blood_for_toughness := 0.0
var _last_max_blood_toughness_level := -INF


func _enter_tree() -> void:
	_runtime_controller_cache.clear()
	call_deferred("_register_with_runtime_controllers")


func _ready() -> void:
	_capture_base_max_blood_for_toughness()
	_ensure_skill_set()
	_configure_world_actor_movement()
	if ai_brain_enabled:
		_setup_world_actor_ai()
	_setup_actor_capabilities()
	_ready_actor_capabilities()

func _exit_tree() -> void:
	_clear_system_movement_collision_exception()
	if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, false)
	if _ai_brain != null:
		_ai_brain.clear_active_job()
	_teardown_actor_capabilities()
	_unregister_from_runtime_controllers()
	_runtime_controller_cache.clear()


func add_actor_capability(capability) -> bool:
	if not _is_actor_capability(capability):
		return false
	var capability_id: StringName = capability.call("get_capability_id")
	if capability_id == &"" or _actor_capability_by_id.has(capability_id):
		return false
	_actor_capabilities.append(capability)
	_actor_capability_by_id[capability_id] = capability
	if bool(capability.get("process_enabled")):
		_actor_process_capabilities.append(capability)
	if bool(capability.get("physics_process_enabled")):
		_actor_physics_process_capabilities.append(capability)
	capability.call("setup", self)
	if _actor_capabilities_ready:
		capability.call("ready")
	return true


func get_actor_capability(capability_id: StringName):
	return _actor_capability_by_id.get(capability_id, null)


func has_actor_capability(capability_id: StringName) -> bool:
	return _actor_capability_by_id.has(capability_id)


func get_actor_capabilities() -> Array:
	return _actor_capabilities.duplicate()


func _create_actor_capabilities() -> Array:
	return [INVENTORY_CAPABILITY_SCRIPT.new(), EQUIPMENT_CAPABILITY_SCRIPT.new(), COMBAT_CAPABILITY_SCRIPT.new(), AI_TARGETING_CAPABILITY_SCRIPT.new(), INTERACTION_CAPABILITY_SCRIPT.new(), CUSTODY_CAPABILITY_SCRIPT.new()]


func _setup_actor_capabilities() -> void:
	if _actor_capability_defaults_initialized:
		return
	_actor_capability_defaults_initialized = true
	for capability_value in _create_actor_capabilities():
		add_actor_capability(capability_value)


func _ready_actor_capabilities() -> void:
	if _actor_capabilities_ready:
		return
	_actor_capabilities_ready = true
	for capability in _actor_capabilities:
		if _is_actor_capability(capability):
			capability.call("ready")
	_custody_capability = get_actor_capability(&"custody")


func _process_actor_capabilities(delta: float) -> void:
	for capability in _actor_process_capabilities:
		if _is_actor_capability_enabled(capability):
			capability.call("process", delta)


func _physics_process_actor_capabilities(delta: float) -> void:
	for capability in _actor_physics_process_capabilities:
		if _is_actor_capability_enabled(capability):
			capability.call("physics_process", delta)


func _teardown_actor_capabilities() -> void:
	for index in range(_actor_capabilities.size() - 1, -1, -1):
		var capability = _actor_capabilities[index]
		if _is_actor_capability(capability):
			capability.call("teardown")
	_actor_capabilities.clear()
	_actor_capability_by_id.clear()
	_actor_process_capabilities.clear()
	_actor_physics_process_capabilities.clear()
	_actor_capabilities_ready = false
	_actor_capability_defaults_initialized = false
	_custody_capability = null


func _is_actor_capability(value) -> bool:
	return value != null \
		and value.has_method("get_capability_id") \
		and value.has_method("setup") \
		and value.has_method("ready") \
		and value.has_method("process") \
		and value.has_method("physics_process") \
		and value.has_method("teardown")


func _is_actor_capability_enabled(value) -> bool:
	if not _is_actor_capability(value):
		return false
	var enabled_value = value.get("enabled")
	return bool(enabled_value) if enabled_value != null else true


func _setup_inventory_capability() -> void:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("initialize_from_actor"):
		inventory_capability.call("initialize_from_actor")
		return
	if inventory == null:
		inventory = InventoryData.new(inventory_columns, inventory_rows, max_carry_weight, true)
		inventory.changed.connect(_on_inventory_data_changed)
	_seed_starting_inventory()
	_apply_population_inventory_entries_if_present()


func _get_inventory_capability():
	return get_actor_capability(&"inventory")


func _setup_equipment_capability() -> void:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("initialize_from_actor"):
		equipment_capability.call("initialize_from_actor")


func _get_equipment_capability():
	return get_actor_capability(&"equipment")


func _set_work_inventory_override(work_inventory: InventoryData) -> void:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("set_work_inventory"):
		inventory_capability.call("set_work_inventory", work_inventory)
		return
	if _work_inventory_override != null and _work_inventory_override.changed.is_connected(_on_inventory_data_changed):
		_work_inventory_override.changed.disconnect(_on_inventory_data_changed)
	_work_inventory_override = work_inventory
	if _work_inventory_override != null and not _work_inventory_override.changed.is_connected(_on_inventory_data_changed):
		_work_inventory_override.changed.connect(_on_inventory_data_changed)


func _notify_inventory_changed(reset_auto_burn_scan := true) -> void:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("notify_inventory_changed"):
		inventory_capability.call("notify_inventory_changed", reset_auto_burn_scan)
		return
	inventory_changed.emit()
	_sync_inventory_to_gecs()


func _on_inventory_data_changed() -> void:
	_notify_inventory_changed(true)


func _sync_inventory_to_gecs() -> void:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("sync_to_gecs"):
		inventory_capability.call("sync_to_gecs")
		return
	if not is_inside_tree():
		return
	var bridge := _get_runtime_controller("gecs_world_controller")
	if bridge != null and bridge.has_method("sync_actor_inventory"):
		bridge.call("sync_actor_inventory", self)


func _seed_starting_inventory() -> void:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("seed_starting_inventory_from_actor"):
		inventory_capability.call("seed_starting_inventory_from_actor")
		return
	for stock in starting_items:
		if stock != null and stock.item_definition != null and stock.quantity > 0:
			inventory.add_item_count(stock.item_definition, stock.quantity)


func _apply_population_inventory_entries_if_present() -> void:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("apply_population_inventory_entries_if_present"):
		inventory_capability.call("apply_population_inventory_entries_if_present")
		return
	if inventory == null or not has_meta("population_inventory_entries"):
		return
	var snapshots: Array = get_meta("population_inventory_entries")
	if snapshots.is_empty():
		return
	inventory.entries.clear()
	for snapshot_value in snapshots:
		if not (snapshot_value is Dictionary):
			continue
		var snapshot: Dictionary = snapshot_value
		var item_path := str(snapshot.get("item_id", ""))
		if item_path.strip_edges().is_empty() or not ResourceLoader.exists(item_path):
			continue
		var definition := load(item_path) as ItemDefinition
		if definition == null:
			continue
		var grid_position: Vector2i = snapshot.get("grid_position", Vector2i.ZERO)
		inventory.entries.append(InventoryData.InventoryEntry.new(
			definition,
			grid_position,
			maxi(1, int(snapshot.get("count", 1))),
			(snapshot.get("contained_item_counts", {}) as Dictionary).duplicate(true),
			(snapshot.get("metadata", {}) as Dictionary).duplicate(true)
		))
	inventory.changed.emit()


func get_inventory_for_display() -> InventoryData:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("get_inventory_for_display"):
		return inventory_capability.call("get_inventory_for_display") as InventoryData
	if _work_inventory_override != null:
		return _work_inventory_override
	return inventory


func is_displaying_work_inventory() -> bool:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("is_displaying_work_inventory"):
		return bool(inventory_capability.call("is_displaying_work_inventory"))
	return _work_inventory_override != null


func get_inventory_display_title() -> String:
	if is_displaying_work_inventory():
		return "%s Work Inventory" % member_name
	return "%s Inventory" % member_name


func can_transfer_display_inventory_to(_target_owner) -> bool:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("can_transfer_display_inventory_to"):
		return bool(inventory_capability.call("can_transfer_display_inventory_to", _target_owner))
	return not is_displaying_work_inventory()


func can_receive_inventory_transfer_from(_source_owner) -> bool:
	var inventory_capability = _get_inventory_capability()
	if inventory_capability != null and inventory_capability.has_method("can_receive_inventory_transfer_from"):
		return bool(inventory_capability.call("can_receive_inventory_transfer_from", _source_owner))
	return not is_displaying_work_inventory()


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


func shows_inventory_equipment() -> bool:
	return false


func get_equipment_slot_names() -> Array[String]:
	return []


func get_equipment_slot_label(slot_name: String) -> String:
	return slot_name.capitalize()


func get_equipped_items() -> Dictionary:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("get_equipped_items"):
		return equipment_capability.call("get_equipped_items") as Dictionary
	return equipped_items


func get_equipped_item(slot_name: String) -> ItemDefinition:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("get_equipped_item"):
		return equipment_capability.call("get_equipped_item", slot_name) as ItemDefinition
	return equipped_items.get(slot_name) as ItemDefinition


func can_equip_item_to_slot(definition: ItemDefinition, slot_name: String) -> bool:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("can_equip_item_to_slot"):
		return bool(equipment_capability.call("can_equip_item_to_slot", definition, slot_name))
	if definition == null or not definition.is_equippable():
		return false
	var actor_slot_names := get_equipment_slot_names()
	if not actor_slot_names.is_empty() and not actor_slot_names.has(slot_name):
		return false
	return definition.can_equip_to_slot(slot_name)


func equip_item_to_slot(definition: ItemDefinition, slot_name: String) -> ItemDefinition:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("equip_item_to_slot"):
		return equipment_capability.call("equip_item_to_slot", definition, slot_name) as ItemDefinition
	if not can_equip_item_to_slot(definition, slot_name):
		return null
	var previous := get_equipped_item(slot_name)
	equipped_items[slot_name] = definition
	_notify_equipment_changed([slot_name])
	return previous


func unequip_item_from_slot(slot_name: String) -> ItemDefinition:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("unequip_item_from_slot"):
		return equipment_capability.call("unequip_item_from_slot", slot_name) as ItemDefinition
	var previous := get_equipped_item(slot_name)
	if previous == null:
		return null
	equipped_items.erase(slot_name)
	_notify_equipment_changed([slot_name])
	return previous


func begin_equipment_update_batch() -> void:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("begin_equipment_update_batch"):
		equipment_capability.call("begin_equipment_update_batch")


func end_equipment_update_batch() -> void:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("end_equipment_update_batch"):
		equipment_capability.call("end_equipment_update_batch")


func has_equipment() -> bool:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("has_equipment"):
		return bool(equipment_capability.call("has_equipment"))
	return not equipped_items.is_empty()


func get_equipped_weight() -> float:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("get_equipped_weight"):
		return float(equipment_capability.call("get_equipped_weight"))
	var total := 0.0
	for item in equipped_items.values():
		if item is ItemDefinition:
			total += (item as ItemDefinition).unit_weight
	return total


func get_equipment_stat_modifiers() -> Array:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("get_stat_modifiers"):
		return equipment_capability.call("get_stat_modifiers") as Array
	var modifiers: Array = []
	for item in equipped_items.values():
		if not (item is ItemDefinition):
			continue
		for modifier in (item as ItemDefinition).stat_modifiers:
			if modifier == null:
				continue
			modifiers.append(modifier.to_modifier_dictionary())
	return modifiers


func _notify_equipment_changed(changed_slots: Array) -> void:
	if has_method("_invalidate_stat_value_cache"):
		call("_invalidate_stat_value_cache")
	_on_actor_equipment_changed(changed_slots)
	inventory_changed.emit()
	_sync_inventory_to_gecs()
	if has_signal("appearance_changed"):
		emit_signal("appearance_changed")
	state_changed.emit()


func _on_actor_equipment_changed(_changed_slots: Array) -> void:
	pass


func get_skill_level(skill_id: String) -> int:
	_ensure_skill_set()
	return skill_set.get_skill_level(skill_id)


func set_skill_level(skill_id: String, level: int, clear_xp := true) -> void:
	_ensure_skill_set()
	skill_set.set_skill_level(skill_id, level, clear_xp)
	if skill_id == SkillRules.ATTRIBUTE_TOUGHNESS:
		_refresh_max_blood_from_toughness(true)
	_on_actor_skill_level_changed(skill_id)


func add_skill_xp(skill_id: String, amount: float, reason := "") -> int:
	_ensure_skill_set()
	var level := skill_set.add_skill_xp(skill_id, amount, reason)
	if skill_id == SkillRules.ATTRIBUTE_TOUGHNESS:
		_refresh_max_blood_from_toughness(true)
	_on_actor_skill_level_changed(skill_id)
	return level


func _on_actor_skill_level_changed(_skill_id: String) -> void:
	pass


func get_skill_xp(skill_id: String) -> float:
	_ensure_skill_set()
	return skill_set.get_skill_xp(skill_id)


func get_skill_xp_to_next(skill_id: String) -> float:
	_ensure_skill_set()
	return skill_set.get_skill_xp_to_next(skill_id)


func get_skill_progress_ratio(skill_id: String) -> float:
	_ensure_skill_set()
	return skill_set.get_skill_progress_ratio(skill_id)


func get_skill_entry_snapshot(skill_id: String) -> Dictionary:
	_ensure_skill_set()
	return skill_set.get_entry_snapshot(skill_id)


func _ensure_skill_set() -> void:
	if skill_set != null:
		_apply_starting_skill_levels_if_needed()
		return
	skill_set = ACTOR_SKILL_SET_SCRIPT.new() as ActorSkillSet
	_apply_starting_skill_levels_if_needed()


func _apply_starting_skill_levels_if_needed() -> void:
	if _starting_skill_levels_applied or skill_set == null:
		return
	_starting_skill_levels_applied = true
	for skill_id_value in starting_skill_levels.keys():
		var skill_id := str(skill_id_value)
		if skill_id.is_empty():
			continue
		skill_set.set_skill_level(skill_id, int(starting_skill_levels[skill_id_value]))
	_refresh_max_blood_from_toughness(true)


func get_base_max_blood() -> float:
	_capture_base_max_blood_for_toughness()
	return _base_max_blood_for_toughness


func refresh_max_blood_from_toughness() -> void:
	_refresh_max_blood_from_toughness(true)


func _capture_base_max_blood_for_toughness() -> void:
	if _base_max_blood_for_toughness > 0.0:
		return
	_base_max_blood_for_toughness = maxf(base_max_blood if base_max_blood > 0.0 else max_blood, 1.0)


func _refresh_max_blood_from_toughness(force := false) -> void:
	if skill_set == null:
		return
	_capture_base_max_blood_for_toughness()
	var toughness_level := float(skill_set.get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS))
	if not force and is_equal_approx(toughness_level, _last_max_blood_toughness_level):
		return
	var previous_max_blood := maxf(max_blood, 1.0)
	var was_full := blood >= previous_max_blood - 0.05
	max_blood = SkillRules.get_max_blood_for_toughness(_base_max_blood_for_toughness, toughness_level)
	if was_full:
		blood = max_blood
	else:
		blood = clampf(blood, -maxf(max_blood, 1.0) * NpcRules.BLOOD_LOSS_DEATH_FACTOR, max_blood)
	_last_max_blood_toughness_level = toughness_level


func set_move_target(target: Vector3, _issued_by_player: bool = true) -> void:
	if is_in_cell_custody():
		return
	_set_actor_move_target(target)


func is_alive() -> bool:
	return life_state == NpcRules.LifeState.ALIVE


func get_life_state_label() -> String:
	return NpcRules.get_life_state_label(life_state)


func get_health_vital_label() -> String:
	return "Health"


func get_vital_fluid_label() -> String:
	return "Blood"


func get_vital_fluid_bar_color(fallback_color: Color) -> Color:
	return fallback_color


func get_vital_fluid_glow_color(fallback_color: Color) -> Color:
	return fallback_color


func get_vital_fluid_blink_strength() -> float:
	return 0.0


func get_vital_fluid_blink_speed() -> float:
	return 0.0


func get_vital_fluid_blink_color(fallback_color: Color) -> Color:
	return fallback_color


func shows_hunger_vital() -> bool:
	return hunger_enabled


func shows_fatigue_vital() -> bool:
	return fatigue_enabled


func is_downed_state() -> bool:
	return is_life_state_downed(life_state)


func is_recoverable_downed_state() -> bool:
	return is_life_state_recoverable_downed(life_state)


func is_dead_or_dying_state() -> bool:
	return is_life_state_dead_or_dying(life_state)


static func is_life_state_downed(state: int) -> bool:
	return state == NpcRules.LifeState.UNCONSCIOUS \
		or state == NpcRules.LifeState.RECOVERY_COMA \
		or state == NpcRules.LifeState.DYING


static func is_life_state_recoverable_downed(state: int) -> bool:
	return state == NpcRules.LifeState.UNCONSCIOUS \
		or state == NpcRules.LifeState.RECOVERY_COMA \
		or state == NpcRules.LifeState.DYING


static func is_life_state_dead_or_dying(state: int) -> bool:
	return state == NpcRules.LifeState.DEAD or state == NpcRules.LifeState.DYING


func get_coma_point(part_max_health: float = -1.0) -> float:
	var safe_max_health := maxf(part_max_health if part_max_health > 0.0 else max_hp, 1.0)
	var coma_factor := clampf(COMA_BASE_FACTOR + get_stat_value("toughness") * COMA_TOUGHNESS_WEIGHT, COMA_BASE_FACTOR, COMA_FACTOR_CAP)
	return -safe_max_health * coma_factor


func get_death_point(part_max_health: float = -1.0) -> float:
	return -maxf(part_max_health if part_max_health > 0.0 else max_hp, 1.0)


func get_blood_death_point() -> float:
	return -maxf(max_blood, 1.0)


func get_dying_seconds() -> float:
	return DYING_BASE_SECONDS + get_stat_value("toughness") * DYING_TOUGHNESS_SECONDS


func is_player_party_member() -> bool:
	return player_party_member


func has_active_player_order() -> bool:
	return _order_was_player_issued and _current_order_type != 0


func set_player_party_member(value: bool) -> void:
	player_party_member = value
	_sync_party_membership_group()


func set_selected(_value: bool) -> void:
	pass


func set_focused(_value: bool) -> void:
	pass


func set_running_enabled(value: bool) -> bool:
	running = value and life_state == NpcRules.LifeState.ALIVE
	state_changed.emit()
	return true


func is_running_enabled() -> bool:
	return running


func set_sneaking_enabled(value: bool) -> void:
	sneaking = value and life_state == NpcRules.LifeState.ALIVE
	state_changed.emit()


func is_sneaking() -> bool:
	return sneaking


func can_participate_in_perception() -> bool:
	return life_state == NpcRules.LifeState.ALIVE and is_inside_tree()


func get_perception_eye_position() -> Vector3:
	return global_position + Vector3(0.0, _get_perception_body_height() * 0.82, 0.0)


func get_perception_forward_vector() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func get_stealth_sample_positions() -> Array[Vector3]:
	var height := _get_perception_body_height()
	var side_offset := maxf(0.18, navigation_agent_radius * 0.62)
	return [
		global_position + Vector3(0.0, height * 0.32, 0.0),
		global_position + Vector3(0.0, height * 0.58, 0.0),
		global_position + Vector3(-side_offset, height * 0.58, 0.0),
		global_position + Vector3(side_offset, height * 0.58, 0.0),
		global_position + Vector3(0.0, height * 0.82, 0.0),
	]


func get_stealth_light_sample_position() -> Vector3:
	return global_position + Vector3(0.0, _get_perception_body_height() * 0.55, 0.0)


func get_stealth_indicator_position() -> Vector3:
	return global_position + Vector3(0.0, _get_perception_body_height() + 0.65, 0.0)


func get_stealth_skill_level() -> float:
	return get_stat_value("stealth")


func get_perception_skill_level() -> float:
	return get_stat_value("perception")


func get_actor_display_name() -> String:
	var display_name := member_name.strip_edges()
	return display_name if not display_name.is_empty() else str(name)


func get_character_visual_root() -> Node3D:
	return get_node_or_null("CharacterVisual") as Node3D


func get_follow_anchor_position() -> Vector3:
	return global_position


func is_ragdoll_active() -> bool:
	return false


func can_receive_bandage() -> bool:
	return false


func set_combat_stance(value: int) -> void:
	combat_stance = clampi(value, NpcRules.CombatStance.AGGRESSIVE, NpcRules.CombatStance.PASSIVE) as NpcRules.CombatStance
	state_changed.emit()


func get_actor_squad_id() -> String:
	var actor_squad_id := world_squad_id.strip_edges()
	return actor_squad_id if not actor_squad_id.is_empty() else squad_name.strip_edges()


func assign_attack_target(_target_actor: Node, _issued_by_player: bool = true, _notify_target: bool = true, _notify_allies: bool = true) -> bool:
	return false


func is_in_combat() -> bool:
	return get_current_combat_target() != null


func get_current_combat_target() -> Node:
	return get_shared_combat_target()


func get_shared_combat_target() -> Node:
	return _shared_combat_target if _shared_combat_target != null and is_instance_valid(_shared_combat_target) else null


func set_shared_combat_target(target: Node) -> void:
	_shared_combat_target = target if target != null and is_instance_valid(target) else null


func is_ready_for_combat_exchange(_target: Node) -> bool:
	return false


func set_system_target_bridge(target_id: int, _process_frame: int) -> void:
	_system_target_id = target_id


func set_system_combat_bridge(_process_frame: int, action_active: bool, reaction_remaining: float, cooldown_remaining: float, focus_id: int) -> void:
	_system_combat_action_active = action_active
	_system_combat_reaction_remaining = reaction_remaining
	_system_combat_cooldown_remaining = cooldown_remaining
	_system_combat_focus_id = focus_id


func set_system_movement_bridge(_process_frame: int, active: bool, target_position := Vector3.ZERO, desired_velocity := Vector3.ZERO, look_target := Vector3.ZERO, settled := false, collision_focus_id := 0) -> void:
	_system_movement_active = active
	_system_movement_settled = settled
	_system_movement_target_position = target_position
	_system_movement_desired_velocity = desired_velocity
	_system_movement_look_target = look_target
	_system_movement_collision_focus_id = collision_focus_id
	if not active:
		_clear_system_movement_collision_exception()


func _get_system_combat_target() -> Node3D:
	if _system_target_id == 0:
		return null
	var target := instance_from_id(_system_target_id) as Node3D
	if target == null or target == self or not is_instance_valid(target):
		return null
	if has_method("_is_valid_active_combat_target"):
		return target if bool(call("_is_valid_active_combat_target", target)) else null
	return target if has_hostility_with(target) else null


func _try_reconfigure_system_combat_target() -> bool:
	if life_state != NpcRules.LifeState.ALIVE or _system_has_active_player_order():
		return false
	if has_method("_is_combat_resolution_busy") and bool(call("_is_combat_resolution_busy")):
		return false
	var active_target := _system_active_combat_target()
	if active_target != null and absf(active_target.global_position.y - global_position.y) <= move_target_vertical_tolerance and _horizontal_distance_to_system(active_target.global_position) <= get_attack_range() + maxf(0.18, combat_attack_forgiveness_buffer):
		return false
	if active_target == null and has_method("_should_seek_combat_target") and not bool(call("_should_seek_combat_target")):
		return false
	var system_target := _get_system_combat_target()
	if system_target == null or system_target == active_target:
		return false
	if active_target != null and _should_keep_current_target_over_close_hostile(active_target, system_target):
		return false
	return assign_attack_target(system_target, false, false, false)


func _system_has_active_player_order() -> bool:
	if has_method("_has_active_player_order"):
		return bool(call("_has_active_player_order"))
	if has_method("has_active_player_order"):
		return bool(call("has_active_player_order"))
	return _order_was_player_issued and _current_order_type != 0


func _system_active_combat_target() -> Node3D:
	if has_method("_get_active_combat_target"):
		return call("_get_active_combat_target") as Node3D
	return get_current_combat_target() as Node3D


func _should_keep_current_target_over_close_hostile(active_target: Node, close_target: Node) -> bool:
	if active_target == null or close_target == null or not (active_target is Node3D) or not (close_target is Node3D):
		return false
	if has_method("_is_valid_active_combat_target") and not bool(call("_is_valid_active_combat_target", active_target)):
		return false
	if absf((active_target as Node3D).global_position.y - global_position.y) > move_target_vertical_tolerance:
		return false
	var active_distance := _horizontal_distance_to_system((active_target as Node3D).global_position)
	var close_distance := _horizontal_distance_to_system((close_target as Node3D).global_position)
	return active_distance <= close_distance + get_attack_range()


func get_system_combat_attack_spec() -> Dictionary:
	var default_seconds := _get_system_default_combat_action_seconds()
	var default_impact_ratio := _get_system_default_combat_impact_ratio()
	var animation_set = call("_get_current_combat_animation_set") if has_method("_get_current_combat_animation_set") else null
	var attack = call("_choose_combat_attack", animation_set) if has_method("_choose_combat_attack") else null
	if attack == null:
		var default_timing := _get_system_combat_action_timing(PackedStringArray(), default_impact_ratio)
		return {
			"animation_names": PackedStringArray(),
			"attack_id": "",
			"hit_reaction_names": PackedStringArray(),
			"total_seconds": float(default_timing.get("total_seconds", default_seconds)),
			"first_clip_seconds": 0.0,
			"impact_seconds": float(default_timing.get("impact_seconds", default_seconds * default_impact_ratio)),
		}
	var action_names := PackedStringArray(attack.get_animation_names()) if attack.has_method("get_animation_names") else PackedStringArray()
	var impact_ratio := float(attack.get("impact_ratio")) if attack.get("impact_ratio") != null else default_impact_ratio
	var timing := _get_system_combat_action_timing(action_names, impact_ratio)
	return {
		"animation_names": action_names,
		"attack_id": str(attack.get("attack_id")),
		"hit_reaction_names": PackedStringArray(attack.get_hit_reaction_names()) if attack.has_method("get_hit_reaction_names") else PackedStringArray(),
		"total_seconds": float(timing.get("total_seconds", default_seconds)),
		"first_clip_seconds": float(timing.get("first_clip_seconds", 0.0)),
		"impact_seconds": float(timing.get("impact_seconds", default_seconds * impact_ratio)),
	}


func on_system_combat_attack_started(target_actor: Node, animation_names: PackedStringArray) -> float:
	if target_actor != null and is_instance_valid(target_actor) and has_method("_face_character"):
		call("_face_character", target_actor)
	if has_method("get_body_projection"):
		var body = call("get_body_projection")
		if body != null and body.has_method("stop_clip"):
			body.call("stop_clip", true)
	if has_method("_spend_fatigue"):
		call("_spend_fatigue", NpcRules.FATIGUE_ATTACK_COST)
	if has_method("_award_combat_attack_xp"):
		call("_award_combat_attack_xp")
	if animation_names.is_empty():
		return 0.0
	return play_system_combat_action_clip(str(animation_names[0]))


func play_system_combat_action_clip(animation_name: String) -> float:
	if animation_name.is_empty() or not has_method("_play_combat_action_clip"):
		return 0.0
	return float(call("_play_combat_action_clip", animation_name))


func prepare_system_combat_receive_attack(attacker: Node, blunt_damage: float, cut_damage: float) -> Dictionary:
	if attacker == null or not is_instance_valid(attacker) or life_state == NpcRules.LifeState.DEAD or is_protected_from_combat():
		return {"accepted": false, "can_actively_defend": false}
	if life_state == NpcRules.LifeState.ASLEEP and has_method("wake_up_from_rest"):
		call("wake_up_from_rest", false)
	if life_state == NpcRules.LifeState.ALIVE and has_method("_break_stealth_for_combat"):
		call("_break_stealth_for_combat")
	mark_hostile(attacker)
	_last_direct_attacker_id = attacker.get_instance_id()
	if attacker.has_method("mark_hostile"):
		attacker.call("mark_hostile", self)
	var incoming_law_arrest := has_method("_is_incoming_law_arrest") and bool(call("_is_incoming_law_arrest", attacker))
	if not incoming_law_arrest and has_method("_notify_defensive_allies_of_attack"):
		call("_notify_defensive_allies_of_attack", attacker)
	if has_method("_face_character"):
		call("_face_character", attacker)
	if has_method("_remember_combat_attack_impulse"):
		call("_remember_combat_attack_impulse", attacker, maxf(blunt_damage, 0.0) + maxf(cut_damage, 0.0))
	var getting_up = get("_is_getting_up")
	var is_getting_up := bool(getting_up) if getting_up != null else false
	return {"accepted": true, "can_actively_defend": life_state == NpcRules.LifeState.ALIVE and not is_getting_up}


func handle_system_combat_resolution(attacker: Node, outcome: String, attack_id: String, hit_reaction_names: PackedStringArray, is_critical: bool, has_shield_block: bool, final_blunt: float, final_cut: float, can_actively_defend := true) -> float:
	if attacker != null and is_instance_valid(attacker):
		if has_method("_face_character"):
			call("_face_character", attacker)
	_apply_system_combat_defense_costs(outcome, has_shield_block)
	var reaction_seconds := play_system_combat_reaction(outcome, attack_id, hit_reaction_names, has_shield_block) if can_actively_defend else 0.0
	if reaction_seconds > 0.0:
		COMBAT_COORDINATOR.extend_character_lock(self, reaction_seconds + 0.05)
	if outcome == "hit" or outcome == "blocked":
		apply_system_combat_damage(attacker, final_blunt, final_cut, outcome, is_critical)
	_show_system_combat_notice(outcome, is_critical, has_shield_block)
	if has_method("_try_start_self_defense"):
		call("_try_start_self_defense", attacker)
	return reaction_seconds


func transform_system_incoming_damage(_attacker: Node, blunt_damage: float, cut_damage: float) -> Dictionary:
	return {"blunt_damage": maxf(blunt_damage, 0.0), "cut_damage": maxf(cut_damage, 0.0)}


func clamp_system_final_combat_damage(attacker: Node, final_blunt: float, final_cut: float) -> Dictionary:
	if has_method("_is_nonlethal_authority_arrest_attack") and bool(call("_is_nonlethal_authority_arrest_attack", attacker)) and has_method("_clamp_nonlethal_arrest_damage"):
		var arrest_damage: Dictionary = call("_clamp_nonlethal_arrest_damage", final_blunt, final_cut) as Dictionary
		return {"blunt_damage": float(arrest_damage.get("blunt", 0.0)), "cut_damage": 0.0}
	return {"blunt_damage": maxf(final_blunt, 0.0), "cut_damage": maxf(final_cut, 0.0)}


func play_system_combat_reaction(outcome: String, attack_id: String, hit_reaction_names: PackedStringArray, has_shield_block: bool) -> float:
	var animation_name := ""
	if outcome == "blocked" and has_method("_pick_combat_block_reaction_clip"):
		animation_name = str(call("_pick_combat_block_reaction_clip", has_shield_block))
	elif outcome == "hit" and has_method("_pick_combat_hit_reaction_clip"):
		var names: Array[String] = []
		for value in hit_reaction_names:
			names.append(str(value))
		animation_name = str(call("_pick_combat_hit_reaction_clip", attack_id, names))
	if animation_name.is_empty() or not has_method("_play_combat_reaction_clip"):
		return 0.0
	return float(call("_play_combat_reaction_clip", animation_name))


func _apply_system_combat_defense_costs(outcome: String, has_shield_block: bool) -> void:
	match outcome:
		"dodged":
			if has_method("_spend_fatigue"):
				call("_spend_fatigue", NpcRules.FATIGUE_DODGE_COST)
			add_skill_xp(SkillRules.ATTRIBUTE_DEXTERITY, 0.35, "combat_dodge")
		"blocked":
			if has_method("_spend_fatigue"):
				call("_spend_fatigue", NpcRules.FATIGUE_BLOCK_COST)
			if has_shield_block:
				add_skill_xp(SkillRules.COMBAT_SHIELDS, 0.25, "combat_block")
			else:
				add_skill_xp(get_combat_weapon_skill_id(), 0.15, "combat_parry")
			add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, 0.12, "combat_block")


func apply_system_combat_damage(_attacker: Node, final_blunt: float, final_cut: float, _outcome := "hit", _is_critical := false) -> void:
	var safe_blunt := maxf(final_blunt, 0.0)
	var safe_cut := maxf(final_cut, 0.0)
	_current_blunt_damage += safe_blunt
	_current_open_cut_damage += safe_cut
	if has_method("_add_bleeding_from_cut"):
		call("_add_bleeding_from_cut", safe_blunt, safe_cut)
	if has_method("_on_resolved_damage"):
		call("_on_resolved_damage", safe_blunt, safe_cut)
	if has_method("_award_toughness_xp"):
		call("_award_toughness_xp", safe_blunt + safe_cut)
	if has_method("_recalculate_vitals"):
		call("_recalculate_vitals")
	else:
		hp = maxf(0.0, max_hp - get_total_wound_damage())


func _get_system_default_combat_action_seconds() -> float:
	return float(call("_get_default_combat_action_seconds")) if has_method("_get_default_combat_action_seconds") else 0.45


func _get_system_default_combat_impact_ratio() -> float:
	return float(call("_get_default_combat_impact_ratio")) if has_method("_get_default_combat_impact_ratio") else 0.45


func _get_system_combat_action_timing(animation_names: PackedStringArray, impact_ratio: float) -> Dictionary:
	if has_method("_get_combat_action_timing"):
		var names: Array[String] = []
		for value in animation_names:
			names.append(str(value))
		return call("_get_combat_action_timing", names, impact_ratio) as Dictionary
	var action_seconds := _get_system_default_combat_action_seconds()
	return {
		"total_seconds": action_seconds,
		"first_clip_seconds": 0.0,
		"impact_seconds": clampf(action_seconds * impact_ratio, 0.05, maxf(0.05, action_seconds - 0.03)),
	}


func _show_system_combat_notice(outcome: String, is_critical: bool, has_shield_block: bool) -> void:
	var message := ""
	var color := Color(1.0, 0.42, 0.42, 1.0)
	match outcome:
		"dodged":
			message = "Dodge"
			color = Color(0.74, 0.94, 1.0, 1.0)
		"blocked":
			message = "Shield Block" if has_shield_block else "Parry"
			color = Color(0.86, 0.9, 1.0, 1.0)
		"hit":
			message = "Critical Hit" if is_critical else "Hit"
	if message.is_empty():
		return
	if has_method("_show_world_notice"):
		call("_show_world_notice", message, color)
	elif has_method("show_world_notice"):
		call("show_world_notice", message, color)


func _actor_id_for_system_bridge(actor: Node) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""
	var stable = actor.get("stable_id")
	if stable != null and not str(stable).strip_edges().is_empty():
		return str(stable).strip_edges()
	if actor.has_meta("actor_record_id"):
		return str(actor.get_meta("actor_record_id")).strip_edges()
	return ""


func _horizontal_distance_to_system(world_position: Vector3) -> float:
	var offset := world_position - global_position
	offset.y = 0.0
	return offset.length()


func get_attack_range() -> float:
	return get_stat_value("attack_range")


func get_combat_weapon_item() -> ItemDefinition:
	return get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON)


func get_combat_offhand_item() -> ItemDefinition:
	return get_equipped_item(ItemDefinition.EQUIP_SLOT_OFFHAND)


func has_combat_shield() -> bool:
	return false


func get_combat_weapon_skill_id() -> String:
	return SkillRules.COMBAT_UNARMED


func get_combat_weapon_skill_level() -> float:
	return float(get_skill_level(get_combat_weapon_skill_id()))


func get_combat_hit_score() -> float:
	return get_combat_weapon_skill_level() + get_stat_value("dexterity") * COMBAT_ATTRIBUTE_ASSIST_WEIGHT


func get_combat_dodge_score() -> float:
	return get_stat_value("dexterity")


func get_combat_hit_chance(defender: WorldActor) -> float:
	var dodge_score := defender.get_combat_dodge_score() if defender != null else 0.0
	return clampf(0.50 + (get_combat_hit_score() - dodge_score) / COMBAT_SCORE_CHANCE_DIVISOR, 0.05, 0.95)


func get_combat_crit_chance() -> float:
	var weapon_skill := get_combat_weapon_skill_level()
	var dexterity := get_stat_value("dexterity")
	return clampf(0.05 + maxf(0.0, weapon_skill - 1.0) * COMBAT_CRIT_SKILL_WEIGHT + maxf(0.0, dexterity - 1.0) * COMBAT_CRIT_DEXTERITY_WEIGHT, 0.0, 1.0)


func get_combat_parry_score() -> float:
	return get_combat_weapon_skill_level() + get_stat_value("dexterity") * COMBAT_ATTRIBUTE_ASSIST_WEIGHT + get_combat_weapon_parry_bonus()


func get_combat_shield_block_score() -> float:
	return float(get_skill_level(SkillRules.COMBAT_SHIELDS)) + get_stat_value("strength") * COMBAT_ATTRIBUTE_ASSIST_WEIGHT + get_combat_shield_block_bonus()


func get_combat_block_score() -> float:
	return get_combat_shield_block_score() if has_combat_shield() else get_combat_parry_score()


func get_combat_block_chance(incoming_hit_score: float) -> float:
	return clampf(0.15 + (get_combat_block_score() - incoming_hit_score) / COMBAT_SCORE_CHANCE_DIVISOR, 0.02, 0.75)


func get_combat_weapon_parry_bonus() -> float:
	var explicit_bonus := get_stat_value("weapon_parry_bonus")
	if explicit_bonus > 0.0:
		return explicit_bonus
	return maxf(0.0, _get_item_stat_value(get_combat_weapon_item(), "block_chance", 0.0) * COMBAT_LEGACY_CHANCE_TO_SCORE)


func get_combat_shield_block_bonus() -> float:
	var explicit_bonus := get_stat_value("shield_block_bonus")
	if explicit_bonus > 0.0:
		return explicit_bonus
	return maxf(0.0, _get_item_stat_value(get_combat_offhand_item(), "block_chance", 0.0) * COMBAT_LEGACY_CHANCE_TO_SCORE)


func get_combat_block_damage_multiplier() -> float:
	return clampf(get_stat_value("block_damage_multiplier"), 0.0, 1.0)


func get_body_weapon_damage_profile() -> Dictionary:
	return {"blunt_base": 2.5, "cut_base": 0.0}


func get_combat_damage_bases() -> Dictionary:
	var weapon_item := get_combat_weapon_item()
	if weapon_item != null:
		if _item_has_stat_modifier(weapon_item, "blunt_base") or _item_has_stat_modifier(weapon_item, "cut_base"):
			var explicit_blunt := maxf(0.0, _get_item_stat_value(weapon_item, "blunt_base", 0.0))
			var explicit_cut := maxf(0.0, _get_item_stat_value(weapon_item, "cut_base", 0.0))
			var damage_multiplier := _get_combat_damage_stat_multiplier()
			return {"blunt_base": explicit_blunt * damage_multiplier, "cut_base": explicit_cut * damage_multiplier}
		var weapon_total_base := maxf(0.0, get_stat_value("attack_damage"))
		var weapon_cut_ratio := clampf(get_stat_value("cut_ratio"), 0.0, 1.0)
		return {"blunt_base": weapon_total_base * (1.0 - weapon_cut_ratio), "cut_base": weapon_total_base * weapon_cut_ratio}
	var body_profile := get_body_weapon_damage_profile()
	var body_multiplier := 1.0 + get_stat_value("toughness") * COMBAT_BODY_TOUGHNESS_BASE_WEIGHT
	body_multiplier *= _get_combat_damage_stat_multiplier()
	return {
		"blunt_base": maxf(0.0, float(body_profile.get("blunt_base", 0.0))) * body_multiplier,
		"cut_base": maxf(0.0, float(body_profile.get("cut_base", 0.0))) * body_multiplier,
	}


func get_combat_damage() -> Dictionary:
	var bases := get_combat_damage_bases()
	return calculate_combat_damage(
		float(bases.get("blunt_base", 0.0)),
		float(bases.get("cut_base", 0.0)),
		get_combat_weapon_skill_level(),
		get_stat_value("strength"),
		get_stat_value("dexterity")
	)


func roll_combat_attack_damage(rng: RandomNumberGenerator = null) -> Dictionary:
	var damage := get_combat_damage()
	var blunt_damage := float(damage.get("blunt_damage", 0.0))
	var cut_damage := float(damage.get("cut_damage", 0.0))
	var critical := false
	var crit_multiplier := 1.0
	var roll := rng.randf() if rng != null else randf()
	if roll <= get_combat_crit_chance():
		critical = true
		crit_multiplier = rng.randf_range(2.0, 3.0) if rng != null else randf_range(2.0, 3.0)
		blunt_damage *= crit_multiplier
		cut_damage *= crit_multiplier
	return {
		"blunt_damage": blunt_damage,
		"cut_damage": cut_damage,
		"critical": critical,
		"crit_multiplier": crit_multiplier,
	}


static func calculate_combat_damage(blunt_base: float, cut_base: float, weapon_skill: float, strength: float, dexterity: float) -> Dictionary:
	var safe_blunt_base := maxf(0.0, blunt_base)
	var safe_cut_base := maxf(0.0, cut_base)
	var total_base := safe_blunt_base + safe_cut_base
	if total_base <= 0.0:
		return {"blunt_damage": 0.0, "cut_damage": 0.0}
	var blunt_share := safe_blunt_base / total_base
	var cut_share := safe_cut_base / total_base
	var skill_bonus := maxf(0.0, weapon_skill) * COMBAT_DAMAGE_SKILL_WEIGHT
	return {
		"blunt_damage": safe_blunt_base + blunt_share * skill_bonus + blunt_share * maxf(0.0, strength) * COMBAT_DAMAGE_ATTRIBUTE_WEIGHT,
		"cut_damage": safe_cut_base + cut_share * skill_bonus + cut_share * maxf(0.0, dexterity) * COMBAT_DAMAGE_ATTRIBUTE_WEIGHT,
	}


func apply_toughness_grit(blunt_damage: float, cut_damage: float) -> Dictionary:
	var safe_blunt := maxf(0.0, blunt_damage)
	var safe_cut := maxf(0.0, cut_damage)
	var post_armor_total := safe_blunt + safe_cut
	if post_armor_total <= 0.0:
		return {"blunt_damage": 0.0, "cut_damage": 0.0, "prevented_total": 0.0}
	var toughness := get_stat_value("toughness")
	var damage_resistance := clampf(toughness * TOUGHNESS_GRIT_RESISTANCE_WEIGHT, 0.0, TOUGHNESS_GRIT_RESISTANCE_CAP)
	var grit_soak := toughness * TOUGHNESS_GRIT_SOAK_WEIGHT
	var prevented_total := minf(post_armor_total * damage_resistance, grit_soak)
	if prevented_total <= 0.0:
		return {"blunt_damage": safe_blunt, "cut_damage": safe_cut, "prevented_total": 0.0}
	var blunt_share := safe_blunt / post_armor_total
	var cut_share := safe_cut / post_armor_total
	return {
		"blunt_damage": maxf(0.0, safe_blunt - prevented_total * blunt_share),
		"cut_damage": maxf(0.0, safe_cut - prevented_total * cut_share),
		"prevented_total": prevented_total,
	}


func get_stat_value(stat_name: String, include_secondary_modifiers: bool = true) -> float:
	var value := _get_base_stat_value(stat_name)
	if not include_secondary_modifiers:
		return value
	var additive := 0.0
	var multiplier := 1.0
	for modifier in _collect_stat_modifiers():
		if modifier.get("stat", "") != stat_name:
			continue
		additive += modifier.get("add", 0.0)
		multiplier *= modifier.get("mul", 1.0)
	value = (value + additive) * multiplier
	match stat_name:
		"dodge_chance", "block_chance", "cut_ratio":
			return clampf(value, 0.0, 0.95)
		"block_damage_multiplier":
			return clampf(value, 0.0, 1.0)
		"attack_cooldown":
			return maxf(0.2, value)
		"move_speed_multiplier", "run_speed_multiplier", "attack_damage", "attack_range", "strength", "dexterity", "toughness", "perception", "stealth", "hunger_drain_rate", "fatigue_recovery_rate", "healing_rate", "weapon_parry_bonus", "shield_block_bonus":
			return maxf(0.0, value)
	return value


func _collect_stat_modifiers() -> Array:
	return get_equipment_stat_modifiers()


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


func get_hunger_stage() -> int:
	return hunger_stage


func get_fatigue_stage() -> int:
	return fatigue_stage


func get_hunger_stage_label() -> String:
	return NpcRules.get_hunger_stage_label(get_hunger_stage())


func get_fatigue_stage_label() -> String:
	return NpcRules.get_fatigue_stage_label(get_fatigue_stage())


func has_conversation_definition() -> bool:
	return conversation_definition != null


func get_conversation_definition():
	return conversation_definition


func register_talker(member: Node) -> void:
	if member == null:
		return
	_get_talker_slot(member)
	_pending_talker_ids[member.get_instance_id()] = true


func release_talker(member: Node) -> void:
	if member == null:
		return
	_pending_talker_ids.erase(member.get_instance_id())
	_assigned_talkers.erase(member.get_instance_id())


func resolve_talk(member: Node) -> bool:
	if member == null:
		return false
	var actor_id := member.get_instance_id()
	if not _pending_talker_ids.has(actor_id):
		return false
	_pending_talker_ids.clear()
	return true


func get_interaction_position(member: Node) -> Vector3:
	var slot_index := _get_talker_slot(member)
	var angle := TAU * float(slot_index) / 6.0
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * interact_distance


func get_combat_approach_position(attacker: Node) -> Vector3:
	var attacker_actor := attacker as WorldActor
	var preferred_range: float = attacker_actor.get_attack_range() if attacker_actor != null else get_attack_range()
	var wait_extra: float = attacker_actor.combat_wait_ring_extra if attacker_actor != null else combat_wait_ring_extra
	return COMBAT_COORDINATOR.get_combat_slot_position(self, attacker, preferred_range, wait_extra)


func get_combat_move_position(attacker: Node) -> Vector3:
	var attacker_actor := attacker as WorldActor
	if attacker_actor != null and absf(global_position.y - attacker_actor.global_position.y) > attacker_actor.move_target_vertical_tolerance:
		return global_position
	return get_combat_approach_position(attacker)


func is_ranged_combatant() -> bool:
	return false


func should_run_close_combat_retarget(delta: float) -> bool:
	if combat_close_retarget_interval_seconds <= 0.0:
		return true
	_close_combat_retarget_remaining -= delta
	if _close_combat_retarget_remaining > 0.0:
		return false
	_close_combat_retarget_remaining = maxf(combat_close_retarget_interval_seconds, 0.01) + randf_range(0.0, maxf(combat_close_retarget_jitter_seconds, 0.0))
	return true


func should_run_consider_retarget(delta: float) -> bool:
	if combat_consider_retarget_interval_seconds <= 0.0:
		return true
	_consider_retarget_remaining -= delta
	if _consider_retarget_remaining > 0.0:
		return false
	_consider_retarget_remaining = maxf(combat_consider_retarget_interval_seconds, 0.01) + randf_range(0.0, maxf(combat_consider_retarget_jitter_seconds, 0.0))
	return true


func request_ai_job(job) -> bool:
	if _ai_brain == null or job == null:
		return false
	return _ai_brain.request_job(job)


func cancel_ai_job(source_id := "") -> void:
	if _ai_brain == null:
		return
	if source_id.is_empty():
		_ai_brain.clear_active_job()
	else:
		_ai_brain.clear_jobs_from_source(source_id)
	_sync_active_combat_actor_group()


func has_active_ai_job_from_source(source_id: String) -> bool:
	return _ai_brain != null and _ai_brain.active_job != null and str(_ai_brain.active_job.source_id) == source_id and _ai_brain.has_active_job()


func finish_active_ai_job_from_gecs(step_status: int) -> void:
	if _ai_brain != null and _ai_brain.has_method("finish_active_job_from_gecs"):
		_ai_brain.call("finish_active_job_from_gecs", step_status)


func get_ai_debug_snapshot() -> Dictionary:
	return _ai_brain.get_debug_snapshot() if _ai_brain != null and _ai_brain.has_method("get_debug_snapshot") else {}


func begin_job_assignment(provider, job_label: String, work_inventory = null, request_runtime_job := true) -> void:
	_set_work_inventory_override(work_inventory as InventoryData)
	_active_job_provider = provider
	_active_job_label = job_label
	if request_runtime_job:
		_request_assigned_work_ai_job(provider, job_label)
	state_changed.emit()
	_notify_inventory_changed(false)


func end_job_assignment() -> void:
	_set_work_inventory_override(null)
	_active_job_provider = null
	_active_job_label = ""
	cancel_ai_job("job_provider")
	state_changed.emit()
	_notify_inventory_changed(false)


func get_active_job_provider():
	return _active_job_provider


func get_job_status_text() -> String:
	if _active_job_provider != null and _active_job_provider.has_method("get_provider_name"):
		return "Working for %s" % _active_job_provider.get_provider_name()
	if _active_job_provider != null:
		return "Working"
	var bridge := get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null
	if bridge != null and bridge.has_method("get_actor_job_contracts"):
		var contracts: Array = bridge.call("get_actor_job_contracts", self)
		if contracts.size() == 1:
			return "Job: %s" % str(contracts[0].get("display_name", "Job"))
		if contracts.size() > 1:
			return "%d jobs" % contracts.size()
	return ""


func show_world_notice(message: String, _color: Color = Color(1.0, 0.28, 0.28, 1.0), _lifetime: float = 1.0) -> void:
	center_notice_requested.emit(message)


func show_world_speech(message: String, lifetime: float = 5.0) -> void:
	show_world_notice(message, Color(0.94, 0.92, 0.86, 1.0), lifetime)


func has_hostility_with(other: Node) -> bool:
	var other_actor := other as WorldActor
	if other_actor != null:
		if is_protected_from_combat() or other_actor.is_protected_from_combat():
			return false
		return is_hostile_to(other_actor) or other_actor.is_hostile_to(self)
	if other == null or is_protected_from_combat() or _is_actor_protected_from_combat(other):
		return false
	return is_hostile_to(other) or (other.has_method("is_hostile_to") and bool(other.call("is_hostile_to", self)))


func is_hostile_to(other: Node) -> bool:
	var other_actor := other as WorldActor
	if other_actor != null:
		if other_actor == self:
			return false
		if is_protected_from_combat() or other_actor.is_protected_from_combat():
			return false
		if _personal_hostile_ids.has(other_actor.get_instance_id()):
			return true
		if hostile_factions.has(other_actor.faction_name):
			return true
		return _factions_are_hostile(faction_name, other_actor.faction_name)
	if other == null or other == self:
		return false
	if is_protected_from_combat() or _is_actor_protected_from_combat(other):
		return false
	if _personal_hostile_ids.has(other.get_instance_id()):
		return true
	var other_faction := _get_actor_string_property(other, "faction_name")
	if hostile_factions.has(other_faction):
		return true
	return _factions_are_hostile(faction_name, other_faction)


func mark_hostile(other: Node) -> void:
	if other == null or other == self:
		return
	_personal_hostile_ids[other.get_instance_id()] = true


func clear_personal_hostility(other: Node) -> void:
	if other == null:
		return
	_personal_hostile_ids.erase(other.get_instance_id())


func clear_all_personal_hostility() -> void:
	_personal_hostile_ids.clear()
	_last_direct_attacker_id = 0


func can_see_actor_for_combat(target: Node) -> bool:
	if target == null or target == self or not is_instance_valid(target):
		return false
	if not _actor_is_sneaking(target):
		return true
	var perception_controller := _get_perception_controller()
	if perception_controller == null:
		return false
	var latest_result := _get_perception_result(perception_controller, target, true)
	if not latest_result.is_empty() and latest_result.has("clearly_seen"):
		return bool(latest_result.get("clearly_seen", false))
	var result := _get_perception_result(perception_controller, target, false)
	return bool(result.get("clearly_seen", false))


func is_protected_from_combat() -> bool:
	return is_in_cell_custody() or is_law_prisoner()


# --- Physical containment (cells / cages) -------------------------------------
# Generic state lives on CustodyCapability; subclasses add their own visuals via
# the _on_enter_custody() / _on_exit_custody() hooks.

func is_in_cell_custody() -> bool:
	return _custody_capability != null and _custody_capability.is_contained()


func get_cell_custody_target() -> Node:
	return _custody_capability.get_container() if _custody_capability != null else null


func _set_cell_custody_container(container) -> void:
	if _custody_capability != null:
		_custody_capability.set_container(container)


func enter_cell_custody(cell, cell_position: Vector3, cell_rotation: Vector3) -> void:
	_set_cell_custody_container(cell)
	global_position = cell_position
	global_rotation = cell_rotation
	velocity = Vector3.ZERO
	_on_enter_custody()


func exit_cell_custody(exit_position: Vector3, exit_rotation: Vector3) -> void:
	_on_exit_custody()
	_set_cell_custody_container(null)
	global_position = exit_position
	global_rotation = exit_rotation
	velocity = Vector3.ZERO


func _on_enter_custody() -> void:
	pass


func _on_exit_custody() -> void:
	pass


# Whether this actor can be held in a cage at all, and how big a cage it needs.
# Giant creatures override is_imprisonable()/get_containment_size_class().
func is_imprisonable() -> bool:
	return true


func get_containment_size_class() -> int:
	return CONTAINMENT_SIZE_MEDIUM


# --- Legal status -------------------------------------------------------------

func get_legal_status() -> ActorLegalStatus:
	if _legal_status == null:
		_legal_status = ActorLegalStatus.new()
	return _legal_status


func has_legal_status() -> bool:
	return _legal_status != null and not _legal_status.is_empty()


func is_law_prisoner() -> bool:
	return _legal_status != null and _legal_status.is_prisoner


func process_world_actor_movement(delta: float) -> void:
	if is_in_cell_custody():
		velocity = Vector3.ZERO
		return
	_ensure_navigation_agent()
	_apply_floor_motion(delta)
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var desired_direction := Vector3.ZERO
	if _has_move_target:
		desired_direction = _get_move_direction(delta)
		if desired_direction.length_squared() > 0.0001:
			var target_speed := _get_actor_move_speed()
			horizontal_velocity = horizontal_velocity.lerp(desired_direction * target_speed, minf(1.0, acceleration * delta))
			look_at(global_position + desired_direction, Vector3.UP)
		else:
			horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, acceleration * delta))
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, acceleration * delta))
	if _should_apply_avoidance(desired_direction):
		_navigation_agent.max_speed = maxf(_get_actor_move_speed(), 0.0)
		_navigation_agent.velocity = horizontal_velocity
		if _has_avoidance_velocity:
			horizontal_velocity.x = _avoidance_velocity.x
			horizontal_velocity.z = _avoidance_velocity.z
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()
	rotation.x = lerp_angle(rotation.x, 0.0, minf(1.0, 10.0 * delta))
	rotation.z = lerp_angle(rotation.z, 0.0, minf(1.0, 10.0 * delta))
	_update_stuck_state(delta, desired_direction)


func process_system_combat_movement(delta: float) -> void:
	_apply_floor_motion(delta)
	_update_system_movement_collision_exception(_system_movement_active, _system_movement_collision_focus_id)
	if _system_movement_active:
		velocity.x = 0.0 if _system_movement_settled else _system_movement_desired_velocity.x
		velocity.z = 0.0 if _system_movement_settled else _system_movement_desired_velocity.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	_face_system_movement_target()
	move_and_slide()
	rotation.x = lerp_angle(rotation.x, 0.0, minf(1.0, 10.0 * delta))
	rotation.z = lerp_angle(rotation.z, 0.0, minf(1.0, 10.0 * delta))


func _face_system_movement_target() -> void:
	var look_position: Vector3 = _system_movement_look_target
	if look_position == Vector3.ZERO:
		var focus = call("_get_combat_focus_actor") if has_method("_get_combat_focus_actor") else null
		if focus is Node3D:
			look_position = (focus as Node3D).global_position
		else:
			var target := get_current_combat_target() as Node3D
			if target != null:
				look_position = target.global_position
	look_position.y = global_position.y
	if global_position.distance_squared_to(look_position) > 0.0001:
		look_at(look_position, Vector3.UP)


func _update_system_movement_collision_exception(active: bool, focus_id: int) -> void:
	if active and focus_id != 0 and focus_id == _system_movement_collision_exception_focus_id and _system_movement_collision_exception_peer != null and is_instance_valid(_system_movement_collision_exception_peer):
		return
	var next_peer: CollisionObject3D = null
	if active and focus_id != 0:
		var focus := instance_from_id(focus_id) as CollisionObject3D
		if focus != null and focus != self and is_instance_valid(focus):
			next_peer = focus
	if next_peer == _system_movement_collision_exception_peer:
		return
	_clear_system_movement_collision_exception()
	if next_peer != null:
		add_collision_exception_with(next_peer)
		_system_movement_collision_exception_focus_id = focus_id
		_system_movement_collision_exception_peer = next_peer


func _clear_system_movement_collision_exception() -> void:
	if _system_movement_collision_exception_peer != null:
		if is_instance_valid(_system_movement_collision_exception_peer):
			remove_collision_exception_with(_system_movement_collision_exception_peer)
		_system_movement_collision_exception_peer = null
	_system_movement_collision_exception_focus_id = 0


func _configure_world_actor_movement() -> void:
	floor_snap_length = floor_snap_distance
	floor_max_angle = deg_to_rad(max_walkable_slope_degrees)
	add_to_group("world_actor")
	add_to_group(COMBAT_COORDINATOR.COMBAT_ACTOR_GROUP)
	_ensure_navigation_agent()
	_sync_party_membership_group()


func _setup_world_actor_ai() -> void:
	if _ai_brain == null:
		_ai_brain = AI_BRAIN_SCRIPT.new()
		_ai_brain.setup(self)
	if _ai_utility_adapter == null:
		_ai_utility_adapter = AI_UTILITY_ADAPTER_SCRIPT.new()
		_ai_utility_adapter.setup()


func _register_with_runtime_controllers() -> void:
	var population_controller := _get_runtime_controller("population_controller")
	if population_controller != null and population_controller.has_method("register_actor"):
		population_controller.call("register_actor", self)
	var query_controller := _get_runtime_controller("actor_query_controller")
	if query_controller != null and query_controller.has_method("register_actor"):
		query_controller.call("register_actor", self)


func _unregister_from_runtime_controllers() -> void:
	var query_controller := _get_runtime_controller("actor_query_controller")
	if query_controller != null and query_controller.has_method("unregister_actor"):
		query_controller.call("unregister_actor", self)
	var population_controller := _get_runtime_controller("population_controller")
	if population_controller != null and population_controller.has_method("unregister_actor"):
		population_controller.call("unregister_actor", self)
	var scheduler := _get_runtime_controller("ai_scheduler_controller")
	if scheduler != null and scheduler.has_method("clear_actor"):
		scheduler.call("clear_actor", self)


func _get_runtime_controller(group_name: String) -> Node:
	if not is_inside_tree():
		return null
	var cached = _runtime_controller_cache.get(group_name)
	if cached != null and is_instance_valid(cached):
		return cached as Node
	var controller := get_tree().get_first_node_in_group(group_name)
	if controller != null:
		_runtime_controller_cache[group_name] = controller
	return controller as Node


func _request_assigned_work_ai_job(provider, job_label: String) -> void:
	if provider == null or _ai_brain == null:
		return
	if has_active_ai_job_from_source("job_provider"):
		return
	if provider.has_method("create_assigned_work_ai_job"):
		var provider_job = provider.call("create_assigned_work_ai_job", self, job_label)
		if provider_job != null:
			request_ai_job(provider_job)
			return
	var job = AI_JOB_SCRIPT.new()
	job.job_type = AI_JOB_SCRIPT.JobType.ASSIGNED_WORK
	job.priority = AI_JOB_SCRIPT.priority_for_type(job.job_type)
	job.source_id = "job_provider"
	job.source = provider
	job.target = provider
	job.target_id = str(provider.get_path()) if provider is Node else str(provider.get_instance_id())
	job.package_id = "assigned_work"
	job.debug_label = "Working: %s" % job_label if not job_label.is_empty() else "Working"
	job.debug_reason = "Assigned paid work from %s" % (provider.get_provider_name() if provider.has_method("get_provider_name") else str(job.target_id))
	request_ai_job(job)


func _ensure_assigned_work_ai_job() -> void:
	if _active_job_provider == null:
		return
	if get_current_combat_target() != null:
		return
	_request_assigned_work_ai_job(_active_job_provider, _active_job_label)


func _tick_active_ai_job(delta: float) -> void:
	if _ai_brain == null or not _ai_brain.has_active_job():
		_ai_job_tick_accumulated = 0.0
		_ai_job_tick_remaining = 0.0
		return
	var bridge := get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null
	if bridge != null and bridge.has_method("can_tick_actor_ai_job") and bool(bridge.call("can_tick_actor_ai_job", self)):
		return
	_ai_job_tick_accumulated += delta
	_ai_job_tick_remaining -= delta
	if _ai_job_tick_remaining > 0.0:
		return
	var tick_delta := _ai_job_tick_accumulated
	_ai_job_tick_accumulated = 0.0
	_ai_job_tick_remaining = 0.18 + randf_range(0.0, 0.08)
	_ai_brain.tick(tick_delta)


func _sync_active_combat_actor_group() -> void:
	if is_in_combat():
		add_to_group(ACTIVE_COMBAT_ACTOR_GROUP)
	else:
		remove_from_group(ACTIVE_COMBAT_ACTOR_GROUP)


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
	return 0.0


func _get_combat_damage_stat_multiplier() -> float:
	var base_value := maxf(_get_base_stat_value("attack_damage"), 0.001)
	return maxf(0.0, get_stat_value("attack_damage") / base_value)


func _item_has_stat_modifier(item: ItemDefinition, stat_name: String) -> bool:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("has_item_stat_modifier"):
		return bool(equipment_capability.call("has_item_stat_modifier", item, stat_name))
	if item == null:
		return false
	for modifier in item.stat_modifiers:
		if modifier != null and modifier.stat_name == stat_name:
			return true
	return false


func _get_item_stat_value(item: ItemDefinition, stat_name: String, base_value: float) -> float:
	var equipment_capability = _get_equipment_capability()
	if equipment_capability != null and equipment_capability.has_method("get_item_stat_value"):
		return float(equipment_capability.call("get_item_stat_value", item, stat_name, base_value))
	if item == null:
		return base_value
	var value := base_value
	for modifier in item.stat_modifiers:
		if modifier == null or modifier.stat_name != stat_name:
			continue
		value = (value + modifier.add) * modifier.mul
	return value


func _actor_is_sneaking(actor: Node) -> bool:
	if actor == null:
		return false
	var value = actor.get("sneaking")
	return bool(value) if value != null else false


func _get_perception_controller() -> Node:
	if not is_inside_tree():
		return null
	var cached = _runtime_controller_cache.get("perception_controller")
	if cached != null and is_instance_valid(cached):
		return cached as Node
	var controller := get_tree().get_first_node_in_group("perception_controller")
	if controller != null:
		_runtime_controller_cache["perception_controller"] = controller
	return controller as Node


func _get_perception_result(perception_controller: Node, target: Node, prefer_latest: bool) -> Dictionary:
	if perception_controller == null or target == null:
		return {}
	if not (target is WorldActor):
		return {}
	if prefer_latest and perception_controller.has_method("get_latest_result"):
		return perception_controller.call("get_latest_result", self, target) as Dictionary
	if not prefer_latest and perception_controller.has_method("evaluate_observer"):
		return perception_controller.call("evaluate_observer", self, target) as Dictionary
	return {}


func _get_perception_body_height() -> float:
	return maxf(navigation_agent_height, 0.6)


func _get_talker_slot(member: Node) -> int:
	if member == null:
		return 0
	var key := member.get_instance_id()
	if _assigned_talkers.has(key):
		return int(_assigned_talkers[key])
	for slot_index in range(6):
		if not _assigned_talkers.values().has(slot_index):
			_assigned_talkers[key] = slot_index
			return slot_index
	_assigned_talkers[key] = 0
	return 0


func _factions_are_hostile(faction_a: String, faction_b: String) -> bool:
	if faction_a.is_empty() or faction_b.is_empty() or faction_a == faction_b:
		return false
	if not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group("faction_controller"):
		if node.has_method("are_hostile"):
			return bool(node.call("are_hostile", faction_a, faction_b))
	return false


func _is_actor_hostile_to_faction(actor: Node, target_faction: String) -> bool:
	var world_actor := actor as WorldActor
	if world_actor != null:
		if target_faction.is_empty() or world_actor.faction_name == target_faction:
			return false
		if world_actor.hostile_factions.has(target_faction):
			return true
		return _factions_are_hostile(world_actor.faction_name, target_faction)
	if actor == null or target_faction.is_empty() or _get_actor_string_property(actor, "faction_name") == target_faction:
		return false
	var actor_hostile_factions = actor.get("hostile_factions")
	if actor_hostile_factions != null and actor_hostile_factions.has(target_faction):
		return true
	return _factions_are_hostile(_get_actor_string_property(actor, "faction_name"), target_faction)


func _is_friendly_to_faction(target_faction: String) -> bool:
	return not _is_actor_hostile_to_faction(self, target_faction)


func _is_actor_protected_from_combat(actor: Node) -> bool:
	if actor is WorldActor:
		return (actor as WorldActor).is_protected_from_combat()
	return actor != null and actor.has_method("is_protected_from_combat") and bool(actor.call("is_protected_from_combat"))


func _get_actor_string_property(actor: Node, property_name: String) -> String:
	var world_actor := actor as WorldActor
	if world_actor != null:
		match property_name:
			"faction_name":
				return world_actor.faction_name.strip_edges()
			"squad_name":
				return world_actor.squad_name.strip_edges()
			"world_squad_id":
				return world_actor.world_squad_id.strip_edges()
	if actor == null:
		return ""
	var value = actor.get(property_name)
	return str(value).strip_edges() if value != null else ""


func _ensure_navigation_agent() -> void:
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		return
	_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "NavigationAgent3D"
		add_child(_navigation_agent)
	_configure_navigation_agent()


func _configure_navigation_agent() -> void:
	_navigation_agent.radius = navigation_agent_radius
	_navigation_agent.height = navigation_agent_height
	_navigation_agent.path_desired_distance = navigation_path_desired_distance
	_navigation_agent.target_desired_distance = _get_move_target_arrival_distance()
	_navigation_agent.path_height_offset = navigation_path_height_offset
	_navigation_agent.avoidance_enabled = navigation_avoidance_enabled
	_navigation_agent.neighbor_distance = navigation_neighbor_distance
	_navigation_agent.max_neighbors = navigation_max_neighbors
	_navigation_agent.max_speed = move_speed
	_navigation_agent.time_horizon_agents = navigation_time_horizon_agents
	_navigation_agent.keep_y_velocity = false
	_navigation_agent.simplify_path = false
	_navigation_agent.simplify_epsilon = 0.0
	if not _navigation_agent.velocity_computed.is_connected(_on_navigation_velocity_computed):
		_navigation_agent.velocity_computed.connect(_on_navigation_velocity_computed)


func _set_actor_move_target(target: Vector3) -> void:
	var target_changed := not _has_move_target or _move_target.distance_squared_to(target) > 0.0025
	_move_target = target
	_has_move_target = true
	if not target_changed:
		return
	_navigation_target_synced = false
	_navigation_query_grace_remaining = 0.25
	_navigation_zero_waypoint_blocked = false
	_has_avoidance_velocity = false
	_stuck_repath_attempts = 0
	_reset_stuck_tracking()


func _clear_actor_move_target() -> void:
	_has_move_target = false
	_navigation_target_synced = false
	_navigation_query_grace_remaining = 0.0
	_navigation_zero_waypoint_blocked = false
	_has_avoidance_velocity = false
	_reset_stuck_tracking()
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		_navigation_agent.velocity = Vector3.ZERO


func _apply_floor_motion(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		apply_floor_snap()


func _get_move_direction(delta: float) -> Vector3:
	if _is_close_to_move_target():
		_finish_actor_move_target()
		return Vector3.ZERO
	if use_navigation_pathing and _navigation_agent != null and _has_navigation_data():
		return _get_navigation_move_direction(delta)
	_navigation_query_grace_remaining = maxf(0.0, _navigation_query_grace_remaining - delta)
	if _navigation_query_grace_remaining <= 0.0:
		_fail_actor_move_target()
	return Vector3.ZERO


func _get_navigation_move_direction(delta: float) -> Vector3:
	_navigation_zero_waypoint_blocked = false
	_sync_navigation_target_if_needed()
	if _navigation_agent.is_navigation_finished():
		if _is_close_to_move_target():
			_finish_actor_move_target()
		elif _is_navigation_final_position_close_enough():
			return _get_navigation_point_move_direction(_navigation_agent.get_final_position())
		else:
			_fail_actor_move_target()
		return Vector3.ZERO
	var next_path_position := _navigation_agent.get_next_path_position()
	if not _is_navigation_final_position_close_enough():
		_navigation_query_grace_remaining = maxf(0.0, _navigation_query_grace_remaining - delta)
		if _navigation_query_grace_remaining <= 0.0:
			_fail_actor_move_target()
		return Vector3.ZERO
	return _get_navigation_path_move_direction(next_path_position)


func _get_navigation_path_move_direction(next_path_position: Vector3) -> Vector3:
	var direct_direction := _get_navigation_point_move_direction(next_path_position)
	if direct_direction.length_squared() > 0.0001:
		return direct_direction
	var path := _navigation_agent.get_current_navigation_path()
	var path_index := maxi(0, _navigation_agent.get_current_navigation_path_index())
	for index in range(path_index, path.size()):
		var to_point := path[index] - global_position
		to_point.y = 0.0
		if to_point.length_squared() > NAVIGATION_MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED:
			return to_point.normalized()
	_navigation_zero_waypoint_blocked = true
	return Vector3.ZERO


func _get_navigation_point_move_direction(point: Vector3) -> Vector3:
	var to_point := point - global_position
	to_point.y = 0.0
	if to_point.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_point.normalized()


func _sync_navigation_target_if_needed() -> void:
	_navigation_agent.target_desired_distance = _get_move_target_arrival_distance()
	if _navigation_target_synced and _navigation_synced_target.distance_squared_to(_move_target) <= 0.0025:
		return
	_navigation_agent.target_position = _move_target
	_navigation_synced_target = _move_target
	_navigation_target_synced = true
	_navigation_query_grace_remaining = 0.25
	_reset_stuck_tracking()


func _reset_stuck_tracking() -> void:
	_stuck_origin = global_position
	_stuck_target_distance = _get_stuck_target_distance()
	_stuck_seconds = 0.0


func _get_stuck_target_distance() -> float:
	if not _has_move_target:
		return INF
	return _horizontal_distance(global_position, _move_target)


func _has_made_stuck_progress() -> bool:
	if _horizontal_distance(global_position, _stuck_origin) >= stuck_min_progress:
		return true
	var target_distance := _get_stuck_target_distance()
	if _stuck_target_distance < INF and target_distance <= _stuck_target_distance - stuck_min_progress:
		return true
	return false


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _is_close_to_navigation_point(point: Vector3, vertical_tolerance: float, horizontal_tolerance: float) -> bool:
	return _is_close_to_navigation_point_from(global_position, point, vertical_tolerance, horizontal_tolerance)


func _is_close_to_navigation_point_from(from: Vector3, point: Vector3, vertical_tolerance: float, horizontal_tolerance: float = -1.0) -> bool:
	var effective_horizontal_tolerance := _get_move_target_arrival_distance() if horizontal_tolerance < 0.0 else horizontal_tolerance
	return _horizontal_distance(from, point) <= effective_horizontal_tolerance and absf(from.y - point.y) <= vertical_tolerance


func _get_move_target_arrival_distance() -> float:
	return navigation_target_desired_distance


func _get_navigation_stuck_arrival_distance() -> float:
	return _get_move_target_arrival_distance()


func _has_navigation_data() -> bool:
	return NavigationServer3D.map_get_iteration_id(_navigation_agent.get_navigation_map()) > 0


func _is_close_to_move_target() -> bool:
	var to_target := _move_target - global_position
	return _horizontal_distance(global_position, _move_target) <= _get_move_target_arrival_distance() and absf(to_target.y) <= move_target_vertical_tolerance


func _is_navigation_final_position_close_enough() -> bool:
	if _navigation_agent == null:
		return false
	var final_position := _navigation_agent.get_final_position()
	return _is_close_to_navigation_point_from(final_position, _move_target, navigation_reachable_vertical_tolerance, navigation_unreachable_tolerance)


func _finish_actor_move_target() -> void:
	_clear_actor_move_target()
	_on_actor_move_target_reached()


func _fail_actor_move_target() -> void:
	_clear_actor_move_target()
	_on_actor_move_target_unreachable()


func _should_apply_avoidance(desired_direction: Vector3) -> bool:
	return _navigation_agent != null and _navigation_agent.avoidance_enabled and _has_move_target and desired_direction.length_squared() > 0.0001


func _update_stuck_state(delta: float, desired_direction: Vector3) -> void:
	if not _has_move_target or desired_direction.length_squared() <= 0.0001:
		if _navigation_zero_waypoint_blocked:
			_stuck_seconds += delta
			if _stuck_seconds >= stuck_check_seconds:
				_handle_navigation_stuck()
			return
		_reset_stuck_tracking()
		return
	if _has_made_stuck_progress():
		_reset_stuck_tracking()
		_stuck_repath_attempts = 0
		return
	_stuck_seconds += delta
	if _stuck_seconds < stuck_check_seconds:
		return
	_handle_navigation_stuck()


func _handle_navigation_stuck() -> void:
	if _is_close_to_navigation_point(_move_target, move_target_vertical_tolerance, _get_navigation_stuck_arrival_distance()):
		_finish_actor_move_target()
		return
	if _is_navigation_final_position_close_enough() and _stuck_repath_attempts < stuck_repath_attempt_limit:
		_navigation_target_synced = false
		_stuck_repath_attempts += 1
		_reset_stuck_tracking()
		return
	_fail_actor_move_target()


func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	_avoidance_velocity = safe_velocity
	_has_avoidance_velocity = true


func _get_actor_move_speed() -> float:
	return move_speed


func _sync_party_membership_group() -> void:
	if player_party_member:
		add_to_group("party_member")
	else:
		remove_from_group("party_member")


func _on_actor_move_target_reached() -> void:
	pass


func _on_actor_move_target_unreachable() -> void:
	pass
