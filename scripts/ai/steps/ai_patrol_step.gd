extends AiTaskStep

class_name AiPatrolStep

const DEFAULT_ARRIVAL_DISTANCE := 3.0
const DEFAULT_PAUSE_MIN_SECONDS := 4.0
const DEFAULT_PAUSE_MAX_SECONDS := 12.0
const DEFAULT_TRAVEL_TIMEOUT_SECONDS := 90.0
const TRAVEL_TIMEOUT_DISTANCE_SECONDS := 0.35

var _destination := Vector3.ZERO
var _has_destination := false
var _pause_remaining := 0.0
var _travel_remaining := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	step_id = "patrol"
	debug_label = "Patrol"
	_rng.randomize()


func start(owner, job) -> void:
	super.start(owner, job)
	if not _is_valid_owner(owner):
		last_blocker = "Missing patrol actor"
		status = StepStatus.FAILED
		return
	if _get_source(job) == null:
		last_blocker = "Missing patrol source"
		status = StepStatus.FAILED
		return
	_pick_next_destination(owner, job)


func tick(owner, job, delta: float) -> int:
	if status != StepStatus.RUNNING:
		return status
	if not _is_valid_owner(owner):
		last_blocker = "Patrol actor is unavailable"
		status = StepStatus.FAILED
		return status
	if not _is_owner_alive(owner):
		last_blocker = "Patrol actor is not alive"
		status = StepStatus.FAILED
		return status
	if _has_combat_target(owner):
		status = StepStatus.SUCCEEDED
		return status
	if _pause_remaining > 0.0:
		_pause_remaining = maxf(0.0, _pause_remaining - delta)
		if _pause_remaining > 0.0:
			return status
		_has_destination = false
	if not _has_destination:
		_pick_next_destination(owner, job)
		if status != StepStatus.RUNNING:
			return status
	var owner_node := owner as Node3D
	if owner_node.global_position.distance_to(_destination) <= _arrival_distance(job):
		_begin_pause(job)
		_has_destination = false
		return status
	_move_owner(owner, _destination)
	_travel_remaining -= delta
	if _travel_remaining <= 0.0:
		_has_destination = false
	return status


func _pick_next_destination(owner, job) -> void:
	var source = _get_source(job)
	if source == null or not source.has_method("get_patrol_destination"):
		last_blocker = "Patrol source has no destination provider"
		status = StepStatus.FAILED
		return
	var destination = source.call("get_patrol_destination", owner, job)
	if not (destination is Vector3):
		last_blocker = "Patrol source returned no destination"
		status = StepStatus.FAILED
		return
	_destination = destination
	_has_destination = true
	_travel_remaining = _travel_timeout(owner, job, _destination)
	_move_owner(owner, _destination)


func _begin_pause(job) -> void:
	var data := _job_data(job)
	var pause_min := maxf(float(data.get("pause_min_seconds", DEFAULT_PAUSE_MIN_SECONDS)), 0.0)
	var pause_max := maxf(float(data.get("pause_max_seconds", DEFAULT_PAUSE_MAX_SECONDS)), pause_min)
	_pause_remaining = _rng.randf_range(pause_min, pause_max)


func _move_owner(owner, destination: Vector3) -> void:
	if owner != null and owner.has_method("set_move_target"):
		owner.call("set_move_target", destination, false)
		return
	last_blocker = "Patrol actor cannot move"
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
