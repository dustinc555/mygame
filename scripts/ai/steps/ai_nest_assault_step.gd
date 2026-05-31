extends AiTaskStep

class_name AiNestAssaultStep

const DEFAULT_ARRIVAL_DISTANCE := 8.0
const DEFAULT_TRAVEL_TIMEOUT_SECONDS := 180.0
const TRAVEL_TIMEOUT_DISTANCE_SECONDS := 0.45
const RETARGET_SECONDS := 3.0

var _target_position := Vector3.ZERO
var _has_target_position := false
var _travel_remaining := 0.0
var _retarget_remaining := 0.0


func _init() -> void:
	step_id = "nest_assault"
	debug_label = "Nest Assault"


func start(owner, job) -> void:
	super.start(owner, job)
	if not _is_valid_owner(owner):
		last_blocker = "Missing assault actor"
		status = StepStatus.FAILED
		return
	if _get_source(job) == null:
		last_blocker = "Missing assault source"
		status = StepStatus.FAILED
		return
	_resolve_target_position(owner, job)
	if status == StepStatus.RUNNING:
		_move_owner(owner, _target_position)


func tick(owner, job, delta: float) -> int:
	if status != StepStatus.RUNNING:
		return status
	if not _is_valid_owner(owner):
		last_blocker = "Assault actor is unavailable"
		status = StepStatus.FAILED
		return status
	if not _is_owner_alive(owner):
		last_blocker = "Assault actor is not alive"
		status = StepStatus.FAILED
		return status
	if _has_combat_target(owner):
		status = StepStatus.SUCCEEDED
		return status
	if not _has_target_position:
		_resolve_target_position(owner, job)
		if status != StepStatus.RUNNING:
			return status
	var owner_node := owner as Node3D
	if owner_node.global_position.distance_to(_target_position) <= _arrival_distance(job):
		if _try_assign_assault_target(owner, job):
			status = StepStatus.SUCCEEDED
			return status
		_retarget_remaining = maxf(0.0, _retarget_remaining - delta)
		if _retarget_remaining <= 0.0:
			_retarget_remaining = RETARGET_SECONDS
			_resolve_target_position(owner, job)
		return status
	_move_owner(owner, _target_position)
	_travel_remaining -= delta
	if _travel_remaining <= 0.0:
		if _try_assign_assault_target(owner, job):
			status = StepStatus.SUCCEEDED
			return status
		_resolve_target_position(owner, job)
	return status


func _resolve_target_position(owner, job) -> void:
	var source = _get_source(job)
	var target_position = null
	if source != null and source.has_method("get_assault_target_position"):
		target_position = source.call("get_assault_target_position", job)
	if not (target_position is Vector3):
		var data := _job_data(job)
		target_position = data.get("target_position", Vector3.ZERO)
	if not (target_position is Vector3):
		last_blocker = "Assault job has no target position"
		status = StepStatus.FAILED
		return
	_target_position = target_position
	_has_target_position = true
	_travel_remaining = _travel_timeout(owner, job, _target_position)


func _try_assign_assault_target(owner, job) -> bool:
	var source = _get_source(job)
	if source == null or not source.has_method("assign_assault_target"):
		last_blocker = "Assault source has no target assignment"
		return false
	if bool(source.call("assign_assault_target", owner, job)):
		return true
	last_blocker = "No assault target available"
	return false


func _move_owner(owner, destination: Vector3) -> void:
	if owner != null and owner.has_method("set_move_target"):
		owner.call("set_move_target", destination, false)
		return
	last_blocker = "Assault actor cannot move"
	status = StepStatus.FAILED


func _travel_timeout(owner, job, destination: Vector3) -> float:
	var data := _job_data(job)
	if data.has("travel_timeout_seconds"):
		return maxf(float(data.get("travel_timeout_seconds", DEFAULT_TRAVEL_TIMEOUT_SECONDS)), 1.0)
	var owner_node := owner as Node3D
	var distance := owner_node.global_position.distance_to(destination) if owner_node != null else 0.0
	return maxf(DEFAULT_TRAVEL_TIMEOUT_SECONDS, distance * TRAVEL_TIMEOUT_DISTANCE_SECONDS)


func _arrival_distance(job) -> float:
	return maxf(float(_job_data(job).get("arrival_distance", DEFAULT_ARRIVAL_DISTANCE)), 0.1)


func _get_source(job):
	if job == null:
		return null
	var source = job.source
	return source if source != null and is_instance_valid(source) else null


func _job_data(job) -> Dictionary:
	if job != null and job.get("data") is Dictionary:
		return job.data
	return {}


func _is_valid_owner(owner) -> bool:
	return owner != null and is_instance_valid(owner) and owner is Node3D


func _is_owner_alive(owner) -> bool:
	var life_state = owner.get("life_state") if owner != null else null
	return life_state == null or int(life_state) == NpcRules.LifeState.ALIVE


func _has_combat_target(owner) -> bool:
	return owner != null and owner.has_method("get_current_combat_target") and owner.call("get_current_combat_target") != null
