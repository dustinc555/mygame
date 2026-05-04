extends Node3D

class_name BarGuardPost

@export var stand_radius := 0.85

var _assigned_worker: HumanoidCharacter


func _ready() -> void:
	add_to_group("bar_guard_post")


func get_work_position() -> Vector3:
	return global_position


func claim_worker(worker: HumanoidCharacter) -> bool:
	if worker == null:
		return false
	if _assigned_worker != null and is_instance_valid(_assigned_worker) and _assigned_worker != worker:
		return false
	_assigned_worker = worker
	return true


func release_worker(worker: HumanoidCharacter) -> void:
	if _assigned_worker == worker:
		_assigned_worker = null


func is_available_for(worker: HumanoidCharacter) -> bool:
	return _assigned_worker == null or not is_instance_valid(_assigned_worker) or _assigned_worker == worker


func is_worker_at_post(worker: HumanoidCharacter) -> bool:
	return worker != null and worker.global_position.distance_to(global_position) <= stand_radius
