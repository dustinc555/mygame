extends RefCounted

class_name AiUtilityJobFactory

const AI_JOB_SCRIPT := preload("res://scripts/ai/ai_job.gd")
const AI_ASSIGNED_WORK_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_assigned_work_step.gd")
const AI_START_ACTIVITY_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_start_activity_step.gd")
const AI_WAIT_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_wait_step.gd")
const AI_RELEASE_ACTIVITY_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_release_activity_step.gd")


func create_job(decision: AiUtilityDecisionResult, actor: Node):
	if decision == null or decision.goal == null or actor == null:
		return null
	var goal := decision.goal
	if goal.job_type == AI_JOB_SCRIPT.JobType.NONE:
		return null
	if goal.id == &"assigned_work":
		return _create_assigned_work_job(decision, actor)
	if goal.id == &"ambient_activity" and decision.target != null:
		return _create_activity_job(decision, actor)
	var job = AI_JOB_SCRIPT.new()
	_apply_common_job_fields(job, decision, actor)
	return job


func _create_assigned_work_job(decision: AiUtilityDecisionResult, actor: Node):
	var provider = decision.target
	if provider == null and actor.has_method("get_active_job_provider"):
		provider = actor.call("get_active_job_provider")
	if provider == null or not is_instance_valid(provider):
		return null
	var contract: Dictionary = decision.target_data.get("contract", {})
	if not contract.is_empty() and provider.has_method("start_contract_shift"):
		var contract_job = provider.call("start_contract_shift", actor, contract)
		if contract_job != null:
			return contract_job
	if provider.has_method("create_assigned_work_ai_job"):
		var provider_job = provider.call("create_assigned_work_ai_job", actor, _provider_label(provider))
		if provider_job != null:
			return provider_job
	var job = AI_JOB_SCRIPT.new()
	_apply_common_job_fields(job, decision, actor)
	job.source_id = "job_provider"
	job.source = provider
	job.target = provider
	job.target_id = _node_key(provider)
	job.package_id = "assigned_work"
	job.debug_label = "Working: %s" % _provider_label(provider)
	job.debug_reason = "Utility AI selected assigned work"
	job.steps = [AI_ASSIGNED_WORK_STEP_SCRIPT.new()]
	return job


func _create_activity_job(decision: AiUtilityDecisionResult, actor: Node):
	var point = decision.target
	if point == null or not is_instance_valid(point):
		return null
	var job = AI_JOB_SCRIPT.new()
	_apply_common_job_fields(job, decision, actor)
	var wait_step = AI_WAIT_STEP_SCRIPT.new()
	wait_step.setup(18.0, "Hold Activity")
	job.steps = [
		AI_START_ACTIVITY_STEP_SCRIPT.new(),
		wait_step,
		AI_RELEASE_ACTIVITY_STEP_SCRIPT.new(),
	]
	return job


func _apply_common_job_fields(job, decision: AiUtilityDecisionResult, actor: Node) -> void:
	var goal := decision.goal
	job.job_type = goal.job_type
	job.priority = goal.get_priority()
	job.source_id = goal.source_id
	job.package_id = goal.get_package_id()
	job.target = decision.target
	job.target_id = decision.target_entity_id
	job.origin_position = (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO
	job.debug_label = goal.get_debug_label()
	job.debug_reason = decision.reason_string


func _provider_label(provider) -> String:
	if provider != null and provider.has_method("get_provider_name"):
		return str(provider.call("get_provider_name"))
	if provider is Node:
		return str((provider as Node).name)
	return str(provider)


func _node_key(value) -> String:
	if value is Node:
		var node := value as Node
		var stable_id = node.get("stable_id")
		if stable_id != null and not str(stable_id).strip_edges().is_empty():
			return str(stable_id).strip_edges()
		if node.is_inside_tree():
			return str(node.get_path())
		return str(node.get_instance_id())
	return str(value)
