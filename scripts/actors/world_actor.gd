extends CharacterBody3D

class_name WorldActor

const ACTOR_SKILL_SET_SCRIPT = preload("res://scripts/skills/actor_skill_set.gd")
const COMBAT_COORDINATOR = preload("res://scripts/characters/combat_coordinator.gd")
const AI_BRAIN_SCRIPT = preload("res://scripts/ai/ai_brain.gd")
const AI_JOB_SCRIPT = preload("res://scripts/ai/ai_job.gd")
const AI_UTILITY_ADAPTER_SCRIPT = preload("res://scripts/ai/utility/ai_utility_adapter.gd")
const ACTOR_CAPABILITY_SCRIPT = preload("res://scripts/actors/capabilities/actor_capability.gd")

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
@export var combat_active_attack_slots := 5
@export var combat_attack_forgiveness_buffer := 0.15
@export var combat_settle_band_extra := 0.65
@export var combat_settle_speed_multiplier := 0.32
@export var combat_personal_space_padding := 0.16
@export var combat_wait_ring_extra := 1.45
@export var combat_direct_translation_enabled := true
@export var combat_close_retarget_interval_seconds := 0.5
@export var combat_close_retarget_jitter_seconds := 0.25
@export var attack_cooldown_seconds := 1.2
@export var base_attack_damage := 18.0
@export var base_dexterity := 10.0
@export_range(0.0, 1.0, 0.01) var attack_cut_ratio := 0.05
@export var base_dodge_chance := 0.08
@export var base_block_chance := 0.06
@export var block_damage_multiplier := 0.4
@export var conversation_definition: Resource

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
@export var navigation_unreachable_tolerance := 1.4
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
var _assigned_talkers: Dictionary = {}
var _pending_talker_ids: Dictionary = {}
var _runtime_controller_cache: Dictionary = {}
var _ai_brain
var _ai_utility_adapter
var _ai_job_tick_remaining := 0.0
var _ai_job_tick_accumulated := 0.0
var _close_combat_retarget_remaining := 0.0
var _active_job_provider
var _active_job_label := ""
var _actor_capabilities: Array = []
var _actor_capability_by_id: Dictionary = {}
var _actor_capabilities_ready := false

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
	return []


func _setup_actor_capabilities() -> void:
	if not _actor_capabilities.is_empty():
		return
	for capability_value in _create_actor_capabilities():
		add_actor_capability(capability_value)


func _ready_actor_capabilities() -> void:
	if _actor_capabilities_ready:
		return
	_actor_capabilities_ready = true
	for capability in _actor_capabilities:
		if _is_actor_capability(capability):
			capability.call("ready")


func _process_actor_capabilities(delta: float) -> void:
	for capability in _actor_capabilities:
		if _is_actor_capability_enabled(capability):
			capability.call("process", delta)


func _physics_process_actor_capabilities(delta: float) -> void:
	for capability in _actor_capabilities:
		if _is_actor_capability_enabled(capability):
			capability.call("physics_process", delta)


func _teardown_actor_capabilities() -> void:
	for index in range(_actor_capabilities.size() - 1, -1, -1):
		var capability = _actor_capabilities[index]
		if _is_actor_capability(capability):
			capability.call("teardown")
	_actor_capabilities.clear()
	_actor_capability_by_id.clear()
	_actor_capabilities_ready = false


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
	_set_actor_move_target(target)


func is_alive() -> bool:
	return life_state == NpcRules.LifeState.ALIVE


func get_life_state_label() -> String:
	return NpcRules.get_life_state_label(life_state)


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


func get_attack_range() -> float:
	return get_stat_value("attack_range")


func get_combat_weapon_item() -> ItemDefinition:
	return null


func get_combat_offhand_item() -> ItemDefinition:
	return null


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


func begin_job_assignment(provider, job_label: String, _work_inventory = null, request_runtime_job := true) -> void:
	_active_job_provider = provider
	_active_job_label = job_label
	if request_runtime_job:
		_request_assigned_work_ai_job(provider, job_label)
	state_changed.emit()


func end_job_assignment() -> void:
	_active_job_provider = null
	_active_job_label = ""
	cancel_ai_job("job_provider")
	state_changed.emit()


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
	return false


func process_world_actor_movement(delta: float) -> void:
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
	if item == null:
		return false
	for modifier in item.stat_modifiers:
		if modifier != null and modifier.stat_name == stat_name:
			return true
	return false


func _get_item_stat_value(item: ItemDefinition, stat_name: String, base_value: float) -> float:
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
	return _is_close_to_navigation_point_from(final_position, _move_target, move_target_vertical_tolerance, navigation_unreachable_tolerance)


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
