extends RefCounted

class_name AiJobDriver

const AI_TASK_STEP_SCRIPT = preload("res://scripts/ai/ai_task_step.gd")

var owner = null
var job = null
var steps: Array = []
var current_step_index := 0


func setup(target_owner, target_job) -> void:
	owner = target_owner
	job = target_job
	current_step_index = 0


func tick(delta: float) -> bool:
	if job == null or current_step_index >= steps.size():
		return true
	var step = steps[current_step_index]
	if step.status == AI_TASK_STEP_SCRIPT.StepStatus.READY:
		step.start(owner, job)
	var result: int = step.tick(owner, job, delta)
	if result == AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED:
		current_step_index += 1
		return current_step_index >= steps.size()
	return result == AI_TASK_STEP_SCRIPT.StepStatus.FAILED or result == AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED


func cancel() -> void:
	if current_step_index >= 0 and current_step_index < steps.size():
		steps[current_step_index].cancel(owner, job)
