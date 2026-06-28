extends BTAction

class_name AiLimboTaskStepAction

const AI_TASK_STEP_SCRIPT = preload("res://features/ai/bridge/ai_task_step.gd")

@export var step_index := 0


func _generate_name() -> String:
	return "AI Job Step %d" % step_index


func _tick(delta: float) -> Status:
	var driver = blackboard.get_var(&"ai_limbo_driver", null)
	if driver == null or not is_instance_valid(driver) or not driver.has_method("tick_step"):
		return FAILURE
	var result: int = int(driver.call("tick_step", step_index, delta))
	match result:
		AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED:
			return SUCCESS
		AI_TASK_STEP_SCRIPT.StepStatus.RUNNING, AI_TASK_STEP_SCRIPT.StepStatus.READY:
			return RUNNING
		_:
			return FAILURE
