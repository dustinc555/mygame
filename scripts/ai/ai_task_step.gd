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


func start(_owner, _job) -> void:
	status = StepStatus.RUNNING


func tick(_owner, _job, _delta: float) -> int:
	return status


func cancel(_owner, _job) -> void:
	status = StepStatus.CANCELLED
