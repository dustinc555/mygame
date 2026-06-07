extends Node3D

class_name BodyProjectionAdapter


func apply_projection_snapshot(_record: Dictionary, _equipment_slots: Dictionary, _combat_state: Dictionary = {}) -> void:
	pass


func get_body_adapter_id() -> String:
	return "body"


func get_portrait_source() -> Node:
	return self


func get_projection_debug_state() -> Dictionary:
	return {"body_adapter_id": get_body_adapter_id()}
