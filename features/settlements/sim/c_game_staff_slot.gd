extends "res://addons/gecs/ecs/component.gd"

class_name CGameStaffSlot

@export var slot_id := ""
@export var settlement_id := ""
@export var assignment_domain := "employment"
@export var role_id := ""
@export var character_type_id := ""
@export var filled := false
@export var population_cost := 1
@export var owner_id := ""
@export var facility_id := ""
@export var building_id := ""
@export var preferred_actor_id := ""
@export var preferred_character_path := ""
@export var occupant_actor_id := ""
@export var authority_scope := ""
@export var assignment_exclusivity_group := ""
@export var dead_actor_key := ""
@export var replacement_due_minute := 0
@export var vacancy_reason := ""
@export var world_position := Vector3.ZERO

var slot_record: Dictionary = {}


func _set(property: StringName, value: Variant) -> bool:
	if property == &"worker_actor_id":
		occupant_actor_id = str(value)
		return true
	return false


func apply_slot(source: Dictionary) -> void:
	slot_id = str(source.get("slot_id", slot_id))
	settlement_id = str(source.get("settlement_id", settlement_id))
	assignment_domain = str(source.get("assignment_domain", assignment_domain))
	role_id = str(source.get("role_id", role_id))
	character_type_id = str(source.get("character_type_id", character_type_id))
	filled = bool(source.get("filled", filled))
	population_cost = int(source.get("population_cost", population_cost))
	owner_id = str(source.get("owner_id", owner_id))
	facility_id = str(source.get("facility_id", facility_id))
	building_id = str(source.get("building_id", building_id))
	preferred_actor_id = str(source.get("preferred_actor_id", preferred_actor_id))
	preferred_character_path = str(source.get("preferred_character_path", preferred_character_path))
	occupant_actor_id = str(source.get("occupant_actor_id", source.get("actor_id", occupant_actor_id)))
	authority_scope = str(source.get("authority_scope", authority_scope))
	assignment_exclusivity_group = str(source.get("assignment_exclusivity_group", assignment_exclusivity_group))
	dead_actor_key = str(source.get("dead_actor_key", dead_actor_key))
	replacement_due_minute = int(source.get("replacement_due_minute", replacement_due_minute))
	vacancy_reason = str(source.get("vacancy_reason", source.get("reason", vacancy_reason)))
	var position_value = source.get("world_position", world_position)
	if position_value is Vector3:
		world_position = position_value
	slot_record = to_slot()


func to_slot() -> Dictionary:
	return {
		"slot_id": slot_id,
		"settlement_id": settlement_id,
		"assignment_domain": assignment_domain,
		"role_id": role_id,
		"character_type_id": character_type_id,
		"filled": filled,
		"population_cost": population_cost,
		"owner_id": owner_id,
		"facility_id": facility_id,
		"building_id": building_id,
		"preferred_actor_id": preferred_actor_id,
		"preferred_character_path": preferred_character_path,
		"occupant_actor_id": occupant_actor_id,
		"authority_scope": authority_scope,
		"assignment_exclusivity_group": assignment_exclusivity_group,
		"dead_actor_key": dead_actor_key,
		"replacement_due_minute": replacement_due_minute,
		"vacancy_reason": vacancy_reason,
		"world_position": world_position,
	}
