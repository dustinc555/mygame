extends "res://addons/gecs/ecs/component.gd"

class_name CGameStaffSlot

@export var slot_id := ""
@export var settlement_id := ""
@export var role_id := ""
@export var filled := false
@export var population_cost := 1
@export var owner_path: NodePath
@export var worker_actor_id := ""
@export var worker_path: NodePath
@export var dead_actor_key := ""
@export var replacement_due_minute := 0
@export var vacancy_reason := ""

var slot_record: Dictionary = {}


func apply_slot(source: Dictionary) -> void:
	slot_id = str(source.get("slot_id", slot_id))
	settlement_id = str(source.get("settlement_id", settlement_id))
	role_id = str(source.get("role_id", role_id))
	filled = bool(source.get("filled", filled))
	population_cost = int(source.get("population_cost", population_cost))
	owner_path = source.get("owner_path", owner_path)
	worker_actor_id = str(source.get("worker_actor_id", source.get("actor_id", worker_actor_id)))
	worker_path = source.get("worker_path", worker_path)
	dead_actor_key = str(source.get("dead_actor_key", dead_actor_key))
	replacement_due_minute = int(source.get("replacement_due_minute", replacement_due_minute))
	vacancy_reason = str(source.get("vacancy_reason", source.get("reason", vacancy_reason)))
	slot_record = to_slot()


func to_slot() -> Dictionary:
	return {
		"slot_id": slot_id,
		"settlement_id": settlement_id,
		"role_id": role_id,
		"filled": filled,
		"population_cost": population_cost,
		"owner_path": owner_path,
		"worker_actor_id": worker_actor_id,
		"worker_path": worker_path,
		"dead_actor_key": dead_actor_key,
		"replacement_due_minute": replacement_due_minute,
		"vacancy_reason": vacancy_reason,
	}
