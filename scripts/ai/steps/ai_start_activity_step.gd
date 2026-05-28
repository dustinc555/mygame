extends AiTaskStep

class_name AiStartActivityStep


func _init() -> void:
	step_id = "start_activity"
	debug_label = "Start Activity"


func start(owner, job) -> void:
	super.start(owner, job)
	var target = job.target if job != null else null
	if target == null or not is_instance_valid(target):
		last_blocker = "Missing activity target"
		status = StepStatus.FAILED
		return
	if target.has_method("begin_ai_activity"):
		if bool(target.call("begin_ai_activity", owner, job)):
			status = StepStatus.SUCCEEDED
		else:
			last_blocker = "Activity target rejected actor"
			status = StepStatus.FAILED
		return
	if target.has_method("assign_actor"):
		if bool(target.call("assign_actor", owner)):
			status = StepStatus.SUCCEEDED
		else:
			last_blocker = "Legacy activity target rejected actor"
			status = StepStatus.FAILED
		return
	last_blocker = "Target has no activity contract"
	status = StepStatus.FAILED


func cancel(owner, job) -> void:
	_release_activity(owner, job)
	super.cancel(owner, job)


func _release_activity(owner, job) -> void:
	var target = job.target if job != null else null
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("end_ai_activity"):
		target.call("end_ai_activity", owner, job)
	elif target.has_method("release_actor"):
		target.call("release_actor", owner)
