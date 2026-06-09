extends StaticBody3D

class_name MiningResourceNode

const SKILL_LABOR_MINING := "labor.mining"
const STRENGTH_SPEED_BONUS_CAP := 0.12
const STRENGTH_SPEED_BONUS_CURVE := 45.0

@export var resource_id := ""
@export var display_name := "Resource Node"
@export var item_definition: ItemDefinition
@export var required_mining_level := 0
@export var slow_mine_seconds := 15.0
@export var fast_mine_seconds := 7.0
@export var levels_to_fast_speed := 30
@export var required_tool_tag := "tool.pickaxe"
@export var required_tool_label := "Pickaxe"
@export_range(0.0, 1.0, 0.01) var locked_attempt_xp_multiplier := 0.35
@export_range(0.0, 2.0, 0.01) var vein_quality := 1.0
@export var depletion_enabled := false
@export var max_ore_yield := 0
@export var mining_noise_radius := 12.0
@export var interaction_radius := 1.8
@export var slot_distance := 3.2
@export var slot_count := 6
@export var owner_character_path: NodePath
@export var owner_faction_name := ""

var _assigned_slots_by_actor_id: Dictionary = {}


func _ready() -> void:
	add_to_group("mining_resource")


func get_resource_id() -> String:
	var normalized_id := resource_id.strip_edges()
	if not normalized_id.is_empty():
		return normalized_id
	return "mining_resource:%s" % str(name).to_snake_case()


func get_mining_position_for_actor(actor_id: String, actor_position: Vector3) -> Vector3:
	var slot_index := _get_slot_index(actor_id, actor_position)
	var angle := TAU * float(slot_index) / float(maxi(slot_count, 1))
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * maxf(slot_distance, interaction_radius)


func get_mining_action_for_actor(_actor_id: String, actor_record: Dictionary) -> Dictionary:
	if item_definition == null:
		return {}
	var actor_position = actor_record.get("last_world_position", actor_record.get("world_position", Vector3.ZERO))
	var mining_position := get_mining_position_for_actor(_actor_id, actor_position if actor_position is Vector3 else Vector3.ZERO)
	return {
		"type": "mine_resource",
		"resource_id": get_resource_id(),
		"display_name": display_name,
		"item_definition_path": str(item_definition.resource_path),
		"duration_seconds": get_effective_mine_duration_for_record(actor_record),
		"slow_mine_seconds": slow_mine_seconds,
		"fast_mine_seconds": fast_mine_seconds,
		"levels_to_fast_speed": levels_to_fast_speed,
		"required_mining_level": required_mining_level,
		"required_tool_tag": required_tool_tag,
		"required_tool_label": required_tool_label,
		"locked_attempt_xp_multiplier": get_locked_attempt_xp_multiplier_for_record(actor_record),
		"can_produce_ore": can_produce_ore_for_record(actor_record),
		"interaction_radius": get_mining_interaction_radius(),
		"resource_position": global_position,
		"mining_position": mining_position,
	}


func get_mining_interaction_radius() -> float:
	return maxf(interaction_radius, 0.05)


func get_owner_faction_name() -> String:
	if not owner_faction_name.strip_edges().is_empty():
		return owner_faction_name.strip_edges()
	var owner := get_node_or_null(owner_character_path)
	if owner != null:
		var faction = owner.get("faction_name")
		if faction != null:
			return str(faction)
	return ""


func get_mining_level_for_record(record: Dictionary) -> int:
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	return int(skill_levels.get(SKILL_LABOR_MINING, SkillRules.get_default_level(SKILL_LABOR_MINING)))


func can_produce_ore_for_record(record: Dictionary) -> bool:
	return get_mining_level_for_record(record) >= required_mining_level


func get_locked_attempt_xp_multiplier_for_record(record: Dictionary) -> float:
	return 1.0 if can_produce_ore_for_record(record) else locked_attempt_xp_multiplier


func get_effective_mine_duration_for_record(record: Dictionary) -> float:
	var mining_level := get_mining_level_for_record(record)
	var relative_level := maxf(float(mining_level - required_mining_level), 0.0)
	var speed_ratio := 1.0 if levels_to_fast_speed <= 0 else clampf(relative_level / float(levels_to_fast_speed), 0.0, 1.0)
	var skill_seconds := lerpf(slow_mine_seconds, fast_mine_seconds, speed_ratio)
	return maxf(skill_seconds / (1.0 + _get_strength_speed_bonus_for_record(record)), 0.1)


func release_miner_for_actor(actor_id: String) -> void:
	_assigned_slots_by_actor_id.erase(actor_id.strip_edges())


func _get_strength_speed_bonus_for_record(record: Dictionary) -> float:
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	var strength_level := maxf(float(skill_levels.get(SkillRules.ATTRIBUTE_STRENGTH, SkillRules.DEFAULT_LEVEL)) - float(SkillRules.DEFAULT_LEVEL), 0.0)
	return SkillRules.get_diminishing_bonus(strength_level, STRENGTH_SPEED_BONUS_CAP, STRENGTH_SPEED_BONUS_CURVE)


func _get_slot_index(actor_id: String, actor_position: Vector3) -> int:
	var count := maxi(slot_count, 1)
	var normalized_actor_id := actor_id.strip_edges()
	if not normalized_actor_id.is_empty() and _assigned_slots_by_actor_id.has(normalized_actor_id):
		return int(_assigned_slots_by_actor_id[normalized_actor_id])
	var used: Array[int] = []
	for value in _assigned_slots_by_actor_id.values():
		used.append(int(value))
	var best_slot := 0
	var best_distance := INF
	for slot_index in range(count):
		if used.has(slot_index):
			continue
		var angle := TAU * float(slot_index) / float(count)
		var slot_position := global_position + Vector3(cos(angle), 0.0, sin(angle)) * maxf(slot_distance, interaction_radius)
		var distance := actor_position.distance_squared_to(slot_position)
		if distance < best_distance:
			best_distance = distance
			best_slot = slot_index
	if best_distance == INF:
		for fallback_slot_index in range(count):
			var fallback_angle := TAU * float(fallback_slot_index) / float(count)
			var fallback_slot_position := global_position + Vector3(cos(fallback_angle), 0.0, sin(fallback_angle)) * maxf(slot_distance, interaction_radius)
			var fallback_distance := actor_position.distance_squared_to(fallback_slot_position)
			if fallback_distance < best_distance:
				best_distance = fallback_distance
				best_slot = fallback_slot_index
	if not normalized_actor_id.is_empty():
		_assigned_slots_by_actor_id[normalized_actor_id] = best_slot
	return best_slot
