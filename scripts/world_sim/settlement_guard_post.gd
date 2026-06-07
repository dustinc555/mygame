extends Node3D

class_name SettlementGuardPost

@export var display_name := "Guard Post"
@export var point_role := "guard"
@export var debug_color := Color(0.35, 0.78, 1.0, 0.76)


func _ready() -> void:
	add_to_group("settlement_guard_post")


func get_guard_post_record(settlement_id := "") -> Dictionary:
	return {
		"guard_post_id": str(get_path()) if is_inside_tree() else str(name),
		"settlement_id": settlement_id,
		"display_name": display_name,
		"point_role": point_role,
		"world_position": global_position,
	}
