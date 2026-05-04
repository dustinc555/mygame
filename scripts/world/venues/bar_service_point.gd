extends Node3D

class_name BarServicePoint

@export var work_radius := 1.1


func _ready() -> void:
	add_to_group("bar_service_point")


func get_work_position() -> Vector3:
	return global_position


func is_worker_at_point(worker: HumanoidCharacter) -> bool:
	return worker != null and worker.global_position.distance_to(global_position) <= work_radius
