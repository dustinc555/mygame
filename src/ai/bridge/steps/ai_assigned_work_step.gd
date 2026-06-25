extends AiTaskStep

class_name AiAssignedWorkStep


func _init() -> void:
	step_id = "assigned_work"
	debug_label = "Assigned Work"


func start(owner, job) -> void:
	super.start(owner, job)
	if _get_provider(owner, job) == null:
		last_blocker = "Missing job provider"
		status = StepStatus.FAILED


func tick(owner, job, delta: float) -> int:
	if status != StepStatus.RUNNING:
		return status
	var provider = _get_provider(owner, job)
	if provider == null:
		last_blocker = "Job provider was removed"
		status = StepStatus.FAILED
		return status
	if owner == null or not is_instance_valid(owner):
		last_blocker = "Worker was removed"
		status = StepStatus.FAILED
		return status
	if owner.has_method("get_active_job_provider") and owner.call("get_active_job_provider") != provider:
		status = StepStatus.SUCCEEDED
		return status
	if not provider.has_method("tick_worker_job_from_ai"):
		last_blocker = "Provider has no AI work tick"
		status = StepStatus.FAILED
		return status
	var result: Dictionary = provider.call("tick_worker_job_from_ai", owner, delta, job)
	last_blocker = str(result.get("blocker", ""))
	if bool(result.get("failed", false)):
		status = StepStatus.FAILED
	elif bool(result.get("ended", false)):
		status = StepStatus.SUCCEEDED
	return status


func _get_provider(owner, job):
	if job != null:
		if job.source != null and is_instance_valid(job.source):
			return job.source
		if job.target != null and is_instance_valid(job.target):
			return job.target
	if owner != null and is_instance_valid(owner) and owner.has_method("get_active_job_provider"):
		var provider = owner.call("get_active_job_provider")
		if provider != null and is_instance_valid(provider):
			return provider
	return null
