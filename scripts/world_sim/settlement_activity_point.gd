extends Node3D

class_name SettlementActivityPoint

@export var activity_id := ""
@export var display_name := "Activity Point"
@export_enum("idle", "social", "farm", "guard", "work", "mine", "sit") var activity_type := "idle"
@export var enabled := true
@export var exclusive := false
@export_range(0.1, 100.0, 0.1) var weight := 1.0
@export_range(0, 23, 1) var active_start_hour := 0
@export_range(0, 23, 1) var active_end_hour := 23
@export var target_path: NodePath

var _assigned_actor: Node


func _ready() -> void:
	add_to_group("settlement_activity_point")


func get_activity_id() -> String:
	return activity_id if not activity_id.is_empty() else name


func get_activity_record(settlement_id := "", facility_id := "") -> Dictionary:
	return {
		"activity_id": get_activity_id(),
		"settlement_id": settlement_id,
		"facility_id": facility_id,
		"display_name": display_name if not display_name.is_empty() else get_activity_id().capitalize(),
		"activity_type": activity_type,
		"enabled": enabled,
		"exclusive": exclusive,
		"weight": weight,
		"active_start_hour": active_start_hour,
		"active_end_hour": active_end_hour,
		"world_position": global_position,
	}


func is_active_for_hour(hour: int) -> bool:
	if not enabled:
		return false
	if active_start_hour <= active_end_hour:
		return hour >= active_start_hour and hour <= active_end_hour
	return hour >= active_start_hour or hour <= active_end_hour


func is_available_for(actor: Node) -> bool:
	if not enabled:
		return false
	if not exclusive:
		return true
	return _assigned_actor == null or not is_instance_valid(_assigned_actor) or _assigned_actor == actor


func claim_actor(actor: Node) -> bool:
	if actor == null or not is_available_for(actor):
		return false
	_assigned_actor = actor
	return true


func release_actor(actor: Node) -> void:
	if _assigned_actor == actor:
		_assigned_actor = null


func assign_actor(actor: Node) -> bool:
	if actor == null or not claim_actor(actor):
		return false
	var target := get_activity_target()
	match activity_type:
		"mine":
			if target != null and target.has_method("get_mining_position") and actor.has_method("assign_mining_resource"):
				actor.call("assign_mining_resource", target, false)
				return true
		"sit":
			if target != null and target.has_method("get_interaction_position") and actor.has_method("assign_seat_target"):
				actor.call("assign_seat_target", target, false)
				return true
	var target_position := get_activity_position(actor)
	if actor.has_method("set_move_target"):
		actor.call("set_move_target", target_position, false)
		return true
	release_actor(actor)
	return false


func get_activity_target() -> Node:
	return get_node_or_null(target_path)


func get_activity_position(actor: Node = null) -> Vector3:
	var target := get_activity_target()
	if target != null:
		if target.has_method("get_work_position"):
			return target.call("get_work_position")
		if actor != null and target.has_method("get_interaction_position"):
			return target.call("get_interaction_position", actor)
		if target is Node3D:
			return (target as Node3D).global_position
	return global_position
