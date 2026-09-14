extends "res://features/world/bridge/resource_nodes/resource_deposit_node.gd"

class_name MiningResourceNode

@export var display_name := "Resource Node"
@export var item_definition: Resource
@export var required_mining_level := 0
@export var slow_mine_seconds := 15.0
@export var fast_mine_seconds := 7.0
@export var levels_to_fast_speed := 30
@export var required_tool_tag := "tool.pickaxe"
@export var required_tool_label := "Pickaxe"
@export_range(0.0, 1.0, 0.01) var locked_attempt_xp_multiplier := 0.35
@export_range(0.0, 2.0, 0.01) var vein_quality := 1.0
@export var mining_noise_radius := 12.0
@export var interaction_radius := 1.8
@export var slot_distance := 3.2
@export var slot_count := 6

const STRENGTH_SPEED_BONUS_CAP := 0.12
const STRENGTH_SPEED_BONUS_CURVE := 45.0

var _assigned_slots: Dictionary = {}


func _init() -> void:
	deposit_definition = preload("res://features/world/resources/resource_deposits/copper.tres")


func _ready() -> void:
	super._ready()
	add_to_group("mining_resource")


func get_mining_position(member: Node) -> Vector3:
	var slot_index := _get_slot_index(member)
	var angle := TAU * float(slot_index) / float(max(slot_count, 1))
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * slot_distance


func get_mining_interaction_radius() -> float:
	return maxf(interaction_radius, 0.05)


func get_resource_progress_key() -> String:
	return resource_node_id.strip_edges()


func register_miner(member: Node) -> void:
	_get_slot_index(member)


func release_miner(member: Node) -> void:
	_assigned_slots.erase(member.get_instance_id())


func get_mining_level(actor) -> int:
	if actor != null and actor.has_method("get_skill_level"):
		return actor.get_skill_level(SkillRules.LABOR_MINING)
	return SkillRules.get_default_level(SkillRules.LABOR_MINING)


func can_produce_ore_for(actor) -> bool:
	return get_mining_level(actor) >= required_mining_level


func get_locked_attempt_xp_multiplier_for(actor) -> float:
	return 1.0 if can_produce_ore_for(actor) else locked_attempt_xp_multiplier


func get_effective_mine_duration(actor) -> float:
	var relative_level := maxf(float(get_mining_level(actor) - required_mining_level), 0.0)
	var speed_ratio := 1.0 if levels_to_fast_speed <= 0 else clampf(relative_level / float(levels_to_fast_speed), 0.0, 1.0)
	var skill_seconds := lerpf(slow_mine_seconds, fast_mine_seconds, speed_ratio)
	var strength_bonus := _get_strength_speed_bonus(actor)
	return maxf(skill_seconds / (1.0 + strength_bonus), 0.1)


func complete_mining_attempt(actor: Node, inventory) -> Dictionary:
	return _complete_deposit_attempt(actor, inventory)


func can_complete_deposit_attempt(actor: Node) -> bool:
	if not can_produce_ore_for(actor):
		return false
	if required_tool_tag.is_empty():
		return true
	var tool = actor.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) if actor.has_method("get_equipped_item") else null
	return tool != null and tool.has_tool_tag(required_tool_tag)


func deliver_deposit_attempt(actor: Node, inventory, metadata: Dictionary) -> Dictionary:
	if not _claim_deposit_delivery(actor):
		return {"success": false, "message": "Unavailable"}
	var delivered: bool = inventory != null and item_definition != null and inventory.add_item_count_with_metadata(item_definition, 1, metadata)
	return {"success": delivered, "message": "" if delivered else "Inventory full"}


func _get_strength_speed_bonus(actor) -> float:
	if actor == null or not actor.has_method("get_skill_level"):
		return 0.0
	var strength_level: float = maxf(float(actor.get_skill_level(SkillRules.ATTRIBUTE_STRENGTH) - SkillRules.DEFAULT_LEVEL), 0.0)
	return SkillRules.get_diminishing_bonus(strength_level, STRENGTH_SPEED_BONUS_CAP, STRENGTH_SPEED_BONUS_CURVE)


func _get_slot_index(member: Node) -> int:
	var key: int = member.get_instance_id()
	if _assigned_slots.has(key):
		return _assigned_slots[key]

	var used: Array[int] = []
	for value in _assigned_slots.values():
		used.append(value)

	var best_slot := 0
	var best_distance := INF
	for slot_index in range(slot_count):
		if used.has(slot_index):
			continue
		var slot_position := _slot_position_from_index(slot_index)
		var distance: float = member.global_position.distance_squared_to(slot_position)
		if distance < best_distance:
			best_distance = distance
			best_slot = slot_index

	if best_distance == INF:
		for slot_index in range(slot_count):
			var slot_position := _slot_position_from_index(slot_index)
			var distance: float = member.global_position.distance_squared_to(slot_position)
			if distance < best_distance:
				best_distance = distance
				best_slot = slot_index

	_assigned_slots[key] = best_slot
	return best_slot


func _slot_position_from_index(slot_index: int) -> Vector3:
	var angle := TAU * float(slot_index) / float(max(slot_count, 1))
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * slot_distance
