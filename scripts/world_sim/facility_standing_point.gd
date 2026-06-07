extends Node3D

class_name FacilityStandingPoint

@export var enabled := true
@export var point_role := "standing"
@export var display_name := "Standing Point"
@export var debug_color := Color(0.36, 1.0, 0.48, 0.76)

var _visitor: Node


func _ready() -> void:
	add_to_group("facility_standing_point")


func is_available_for(actor: Node) -> bool:
	return enabled and (_visitor == null or not is_instance_valid(_visitor) or _visitor == actor)


func claim_visitor(actor: Node) -> bool:
	if actor == null or not is_available_for(actor):
		return false
	_visitor = actor
	return true


func release_visitor(actor: Node) -> void:
	if _visitor == actor:
		_visitor = null


func get_visitor() -> Node:
	return _visitor if _visitor != null and is_instance_valid(_visitor) else null


func get_visit_position(_actor: Node = null) -> Vector3:
	return global_position


func get_standing_point_record(settlement_id := "", facility_id := "") -> Dictionary:
	return {
		"standing_point_id": str(get_path()) if is_inside_tree() else str(name),
		"settlement_id": settlement_id,
		"facility_id": facility_id,
		"display_name": display_name,
		"point_role": point_role,
		"world_position": global_position,
	}
