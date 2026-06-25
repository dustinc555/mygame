extends AiTaskStep

class_name AiWaitStep

var duration_seconds := 0.0
var elapsed_seconds := 0.0


func setup(wait_seconds: float, wait_label := "Wait") -> void:
	duration_seconds = maxf(wait_seconds, 0.0)
	debug_label = wait_label
	step_id = "wait"


func start(owner, job) -> void:
	super.start(owner, job)
	elapsed_seconds = 0.0
	if duration_seconds <= 0.0:
		status = StepStatus.SUCCEEDED


func tick(_owner, _job, delta: float) -> int:
	if status != StepStatus.RUNNING:
		return status
	elapsed_seconds += delta
	if elapsed_seconds >= duration_seconds:
		status = StepStatus.SUCCEEDED
	return status


func get_debug_snapshot() -> Dictionary:
	var snapshot := super.get_debug_snapshot()
	snapshot["elapsed_seconds"] = elapsed_seconds
	snapshot["duration_seconds"] = duration_seconds
	return snapshot
