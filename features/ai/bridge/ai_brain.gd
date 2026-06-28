extends RefCounted

class_name AiBrain

const AI_BLACKBOARD_SCRIPT = preload("res://features/ai/bridge/ai_blackboard.gd")
const AI_JOB_SCRIPT = preload("res://features/ai/bridge/ai_job.gd")
const AI_LIMBO_JOB_DRIVER_SCRIPT = preload("res://features/ai/bridge/limbo/ai_limbo_job_driver.gd")
const AI_TASK_STEP_SCRIPT = preload("res://features/ai/bridge/ai_task_step.gd")

var owner = null
var blackboard = AI_BLACKBOARD_SCRIPT.new()
var active_job = null
var active_driver = null
var last_completed_job_snapshot: Dictionary = {}


func setup(target_owner) -> void:
	owner = target_owner


func request_job(job) -> bool:
	if job == null or not job.is_valid_for(owner):
		return false
	if active_job != null and not active_job.is_valid_for(owner):
		_clear_active_job_without_filters()
	if not job.should_replace(active_job, owner):
		return false
	_cancel_active_driver()
	active_job = job
	active_job.status = AI_JOB_SCRIPT.JobStatus.RUNNING
	if active_job.job_id.is_empty():
		active_job.job_id = _make_job_id(active_job)
	if active_job.steps.size() > 0:
		active_driver = AI_LIMBO_JOB_DRIVER_SCRIPT.new()
		active_driver.setup(owner, active_job)
		if owner is Node:
			owner.add_child(active_driver)
	blackboard.set_fact("active_job_type", job.job_type)
	blackboard.set_fact("active_target", job.target)
	blackboard.set_fact("active_priority", job.priority)
	blackboard.set_fact("active_job_id", job.job_id)
	blackboard.set_fact("active_package_id", job.package_id)
	_sync_active_job_to_gecs()
	return true


func tick(delta: float) -> void:
	if not has_active_job():
		return
	if active_driver == null:
		return
	var result: int = active_driver.tick(delta)
	match result:
		AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED:
			_finish_active_job(AI_JOB_SCRIPT.JobStatus.SUCCEEDED)
		AI_TASK_STEP_SCRIPT.StepStatus.FAILED:
			_finish_active_job(AI_JOB_SCRIPT.JobStatus.FAILED)
		AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED:
			_finish_active_job(AI_JOB_SCRIPT.JobStatus.CANCELLED)


func finish_active_job_from_gecs(step_status: int) -> void:
	match step_status:
		AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED:
			_finish_active_job(AI_JOB_SCRIPT.JobStatus.SUCCEEDED)
		AI_TASK_STEP_SCRIPT.StepStatus.FAILED:
			_finish_active_job(AI_JOB_SCRIPT.JobStatus.FAILED)
		AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED:
			_finish_active_job(AI_JOB_SCRIPT.JobStatus.CANCELLED)


func has_active_job() -> bool:
	return active_job != null and active_job.is_valid_for(owner)


func has_active_combat_job() -> bool:
	return has_active_job() and active_job.is_combat()


func get_active_combat_target():
	if not has_active_combat_job():
		return null
	return active_job.target


func get_active_combat_origin_position() -> Vector3:
	if not has_active_combat_job():
		return Vector3.ZERO
	return active_job.origin_position


func is_active_job_player_issued() -> bool:
	return has_active_job() and active_job.issued_by_player


func get_active_job_type() -> int:
	return active_job.job_type if has_active_job() else AI_JOB_SCRIPT.JobType.NONE


func clear_active_job(job_type: int = AI_JOB_SCRIPT.JobType.NONE, target = null) -> void:
	if active_job == null:
		return
	if job_type != AI_JOB_SCRIPT.JobType.NONE and active_job.job_type != job_type:
		return
	if target != null and active_job.target != target:
		return
	_cancel_active_driver()
	_clear_active_job_without_filters()


func clear_combat_job(target = null) -> void:
	if active_job == null or not active_job.is_combat():
		return
	if target != null and active_job.target != target:
		return
	_cancel_active_driver()
	_clear_active_job_without_filters()


func clear_for_player_override() -> void:
	if active_job != null and not active_job.is_interruptible():
		return
	_cancel_active_driver()
	_clear_active_job_without_filters()


func clear_jobs_from_source(source_id: String) -> void:
	if source_id.is_empty() or active_job == null:
		return
	if str(active_job.source_id) != source_id:
		return
	_cancel_active_driver()
	_clear_active_job_without_filters()


func get_debug_snapshot() -> Dictionary:
	return {
		"has_active_job": has_active_job(),
		"active_job": active_job.get_debug_snapshot() if active_job != null and active_job.has_method("get_debug_snapshot") else {},
		"driver": active_driver.get_debug_snapshot() if active_driver != null and active_driver.has_method("get_debug_snapshot") else {},
		"blackboard": blackboard.snapshot(),
		"last_completed_job": last_completed_job_snapshot,
	}


func _finish_active_job(status: int) -> void:
	var finished_driver = active_driver
	if active_job != null:
		active_job.status = status
		last_completed_job_snapshot = active_job.get_debug_snapshot() if active_job.has_method("get_debug_snapshot") else {}
	active_driver = null
	_dispose_driver(finished_driver)
	_clear_active_job_without_filters()


func _cancel_active_driver() -> void:
	if active_driver != null:
		active_driver.cancel()
	active_driver = null


func _dispose_driver(driver) -> void:
	if driver == null:
		return
	if driver.has_method("dispose"):
		driver.call("dispose")


func _clear_active_job_without_filters() -> void:
	active_job = null
	active_driver = null
	blackboard.clear_fact("active_job_type")
	blackboard.clear_fact("active_target")
	blackboard.clear_fact("active_priority")
	blackboard.clear_fact("active_job_id")
	blackboard.clear_fact("active_package_id")
	_clear_active_job_in_gecs()


func _make_job_id(job) -> String:
	var owner_id := str(owner.get("stable_id")) if owner != null and owner.get("stable_id") != null else str(owner.get_instance_id()) if owner != null else "actor"
	var type_text := str(job.job_type) if job != null else "job"
	var target_text := str(job.target_id) if job != null and not str(job.target_id).is_empty() else str(job.target.get_instance_id()) if job != null and job.target != null else "none"
	return "%s.%s.%s" % [owner_id, type_text, target_text]


func _sync_active_job_to_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("set_actor_ai_job"):
		bridge.call("set_actor_ai_job", owner, active_job, active_driver)


func _clear_active_job_in_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("clear_actor_ai_job"):
		bridge.call("clear_actor_ai_job", owner)


func _get_gecs_world() -> Node:
	if owner == null or not (owner is Node) or not owner.is_inside_tree():
		return null
	var tree: SceneTree = owner.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("gecs_world_controller")
