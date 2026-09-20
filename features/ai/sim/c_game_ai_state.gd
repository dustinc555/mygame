extends "res://addons/gecs/ecs/component.gd"

class_name CGameAiState

@export var active_job_type := 0
@export var active_job_id := ""
@export var active_job_status := 0
@export var active_source_id := ""
@export var active_package_id := ""
@export var active_objective_id := ""
@export var active_target_id := ""
@export var active_priority := 0
@export var issued_by_player := false
@export var interrupt_policy := 0
@export var current_step_index := 0
@export var last_step_status := 0
@export var active_origin_position := Vector3.ZERO
@export var last_completed_job: Dictionary = {}
@export var blackboard_facts: Dictionary = {}

var active_job
var active_driver


func apply_job(job) -> void:
	active_job = job
	if job == null:
		clear_job()
		return
	active_job_type = int(job.job_type)
	active_job_id = str(job.job_id)
	active_job_status = int(job.status)
	active_source_id = str(job.source_id)
	active_package_id = str(job.package_id)
	active_objective_id = str(job.objective_id)
	active_target_id = str(job.target_id)
	active_priority = int(job.priority)
	issued_by_player = bool(job.issued_by_player)
	interrupt_policy = int(job.interrupt_policy)
	active_origin_position = job.origin_position
	blackboard_facts = {
		"active_job_type": active_job_type,
		"active_job_id": active_job_id,
		"active_source_id": active_source_id,
		"active_target_id": active_target_id,
		"active_priority": active_priority,
		"active_package_id": active_package_id,
	}


## Finalize the command held by this component, not an optional actor brain.
## Detach first so cancellation callbacks cannot erase a newly submitted job.
func finish_job(step_status: int) -> void:
	var finished_job = active_job
	var finished_driver = active_driver
	clear_job()
	if finished_job == null:
		return
	match step_status:
		AiTaskStep.StepStatus.SUCCEEDED:
			finished_job.status = AiJob.JobStatus.SUCCEEDED
		AiTaskStep.StepStatus.FAILED:
			finished_job.status = AiJob.JobStatus.FAILED
		_:
			finished_job.status = AiJob.JobStatus.CANCELLED
	last_completed_job = finished_job.get_debug_snapshot()
	if is_instance_valid(finished_driver):
		# A projection may be gone before its next system tick. Cancellation
		# still releases step-owned resources, but must not dereference it.
		if finished_driver is AiJobDriver and not is_instance_valid(finished_driver.owner):
			finished_driver.owner = null
		if step_status != AiTaskStep.StepStatus.SUCCEEDED:
			finished_driver.cancel()
		if finished_driver.has_method("dispose"):
			finished_driver.dispose()


func clear_job() -> void:
	active_job = null
	active_driver = null
	active_job_type = 0
	active_job_id = ""
	active_job_status = 0
	active_source_id = ""
	active_package_id = ""
	active_objective_id = ""
	active_target_id = ""
	active_priority = 0
	issued_by_player = false
	interrupt_policy = 0
	current_step_index = 0
	last_step_status = 0
	active_origin_position = Vector3.ZERO
	blackboard_facts.clear()
