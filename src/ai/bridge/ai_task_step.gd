extends RefCounted

class_name AiTaskStep

enum StepStatus {
	READY,
	RUNNING,
	SUCCEEDED,
	FAILED,
	CANCELLED,
}

var step_id := ""
var status: int = StepStatus.READY
var debug_label := ""
var last_blocker := ""


func start(_owner, _job) -> void:
	status = StepStatus.RUNNING
	last_blocker = ""


func tick(_owner, _job, _delta: float) -> int:
	return status


func cancel(_owner, _job) -> void:
	status = StepStatus.CANCELLED


func get_debug_label() -> String:
	if not debug_label.is_empty():
		return debug_label
	if not step_id.is_empty():
		return step_id
	return get_script().resource_path.get_file().get_basename()


func get_debug_snapshot() -> Dictionary:
	return {
		"step_id": step_id,
		"label": get_debug_label(),
		"status": status,
		"blocker": last_blocker,
	}
