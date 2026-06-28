extends RefCounted

class_name AiJobDriver

const AI_TASK_STEP_SCRIPT = preload("res://features/ai/bridge/ai_task_step.gd")

var owner = null
var job = null
var steps: Array = []
var current_step_index := 0
var last_status: int = AI_TASK_STEP_SCRIPT.StepStatus.READY


func setup(target_owner, target_job) -> void:
	owner = target_owner
	job = target_job
	steps = target_job.steps.duplicate() if target_job != null and target_job.get("steps") is Array else []
	current_step_index = 0
	last_status = AI_TASK_STEP_SCRIPT.StepStatus.READY


func tick(delta: float) -> int:
	if job == null or current_step_index >= steps.size():
		last_status = AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED
		return last_status
	var step = steps[current_step_index]
	if step == null or not step.has_method("start") or not step.has_method("tick"):
		last_status = AI_TASK_STEP_SCRIPT.StepStatus.FAILED
		return last_status
	if int(step.get("status")) == AI_TASK_STEP_SCRIPT.StepStatus.READY:
		step.start(owner, job)
	var result: int = step.tick(owner, job, delta)
	if result == AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED:
		current_step_index += 1
		if current_step_index >= steps.size():
			last_status = AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED
			return last_status
		last_status = AI_TASK_STEP_SCRIPT.StepStatus.RUNNING
		return last_status
	last_status = result
	return result


func cancel() -> void:
	var last_started_index := mini(current_step_index, steps.size() - 1)
	for index in range(last_started_index, -1, -1):
		var step = steps[index]
		if step != null and step.has_method("cancel"):
			if int(step.get("status")) != AI_TASK_STEP_SCRIPT.StepStatus.READY:
				step.cancel(owner, job)
	last_status = AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED


func get_current_step():
	if current_step_index >= 0 and current_step_index < steps.size():
		return steps[current_step_index]
	return null


func get_debug_snapshot() -> Dictionary:
	var step = get_current_step()
	return {
		"current_step_index": current_step_index,
		"step_count": steps.size(),
		"status": last_status,
		"current_step": step.get_debug_snapshot() if step != null and step.has_method("get_debug_snapshot") else {},
	}
