extends RefCounted

class_name AiBrain

const AI_BLACKBOARD_SCRIPT = preload("res://scripts/ai/ai_blackboard.gd")
const AI_JOB_SCRIPT = preload("res://scripts/ai/ai_job.gd")

var owner = null
var blackboard = AI_BLACKBOARD_SCRIPT.new()
var active_job = null


func setup(target_owner) -> void:
	owner = target_owner


func request_job(job) -> bool:
	if job == null or not job.is_valid_for(owner):
		return false
	if active_job != null and not active_job.is_valid_for(owner):
		_clear_active_job_without_filters()
	if not job.should_replace(active_job, owner):
		return false
	active_job = job
	blackboard.set_fact("active_job_type", job.job_type)
	blackboard.set_fact("active_target", job.target)
	blackboard.set_fact("active_priority", job.priority)
	return true


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
	_clear_active_job_without_filters()


func clear_combat_job(target = null) -> void:
	if active_job == null or not active_job.is_combat():
		return
	if target != null and active_job.target != target:
		return
	_clear_active_job_without_filters()


func clear_for_player_override() -> void:
	_clear_active_job_without_filters()


func _clear_active_job_without_filters() -> void:
	active_job = null
	blackboard.clear_fact("active_job_type")
	blackboard.clear_fact("active_target")
	blackboard.clear_fact("active_priority")
