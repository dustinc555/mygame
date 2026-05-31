extends RefCounted

class_name AiJob

enum JobType {
	NONE,
	PLAYER_MOVE,
	PLAYER_ATTACK,
	SELF_DEFENSE,
	LAW_ARREST,
	CARRY_PRISONER,
	PLACE_IN_CELL,
	ASSIGNED_WORK,
	GUARD_POST,
	AMBIENT_ACTIVITY,
	PATROL,
	NEST_ASSAULT,
}

enum JobStatus {
	READY,
	RUNNING,
	SUCCEEDED,
	FAILED,
	CANCELLED,
}

enum InterruptPolicy {
	INTERRUPTIBLE,
	PROTECTED,
}

const PRIORITY_NONE := 0
const PRIORITY_GUARD_POST := 20
const PRIORITY_AMBIENT_ACTIVITY := 18
const PRIORITY_PATROL := 22
const PRIORITY_ASSIGNED_WORK := 35
const PRIORITY_NEST_ASSAULT := 72
const PRIORITY_CARRY_PRISONER := 82
const PRIORITY_PLACE_IN_CELL := 86
const PRIORITY_SELF_DEFENSE := 90
const PRIORITY_LAW_ARREST := 96
const PRIORITY_PLAYER_ATTACK := 120
const PRIORITY_PLAYER_MOVE := 130

var job_type: int = JobType.NONE
var job_id := ""
var package_id := ""
var source_id := ""
var target_id := ""
var debug_label := ""
var debug_reason := ""
var interrupt_policy: int = InterruptPolicy.INTERRUPTIBLE
var status: int = JobStatus.READY
var priority := PRIORITY_NONE
var target = null
var source = null
var issued_by_player := false
var origin_position := Vector3.ZERO
var objective_id := ""
var data: Dictionary = {}
var steps: Array = []


static func priority_for_type(candidate_type: int) -> int:
	match candidate_type:
		JobType.PLAYER_MOVE:
			return PRIORITY_PLAYER_MOVE
		JobType.PLAYER_ATTACK:
			return PRIORITY_PLAYER_ATTACK
		JobType.LAW_ARREST:
			return PRIORITY_LAW_ARREST
		JobType.SELF_DEFENSE:
			return PRIORITY_SELF_DEFENSE
		JobType.PLACE_IN_CELL:
			return PRIORITY_PLACE_IN_CELL
		JobType.CARRY_PRISONER:
			return PRIORITY_CARRY_PRISONER
		JobType.ASSIGNED_WORK:
			return PRIORITY_ASSIGNED_WORK
		JobType.GUARD_POST:
			return PRIORITY_GUARD_POST
		JobType.AMBIENT_ACTIVITY:
			return PRIORITY_AMBIENT_ACTIVITY
		JobType.PATROL:
			return PRIORITY_PATROL
		JobType.NEST_ASSAULT:
			return PRIORITY_NEST_ASSAULT
		_:
			return PRIORITY_NONE


func is_combat() -> bool:
	return job_type == JobType.PLAYER_ATTACK or job_type == JobType.SELF_DEFENSE or job_type == JobType.LAW_ARREST


func is_valid_for(owner) -> bool:
	if job_type == JobType.NONE:
		return false
	if owner == null or not is_instance_valid(owner):
		return false
	if is_combat():
		return _is_valid_combat_target()
	return true


func is_interruptible() -> bool:
	return interrupt_policy == InterruptPolicy.INTERRUPTIBLE


func should_replace(active_job, owner) -> bool:
	if active_job == null or not active_job.is_valid_for(owner):
		return true
	if active_job == self:
		return true
	if active_job.has_method("is_interruptible") and not active_job.is_interruptible():
		return false
	if is_combat() and active_job.is_combat() and active_job.target == target:
		return priority >= active_job.priority
	return priority > active_job.priority


func get_debug_label() -> String:
	if not debug_label.is_empty():
		return debug_label
	if not package_id.is_empty():
		return package_id
	return _job_type_label(job_type)


func get_debug_snapshot() -> Dictionary:
	return {
		"job_id": job_id,
		"job_type": job_type,
		"job_type_label": _job_type_label(job_type),
		"package_id": package_id,
		"source_id": source_id,
		"target_id": target_id,
		"debug_label": get_debug_label(),
		"debug_reason": debug_reason,
		"priority": priority,
		"status": status,
		"issued_by_player": issued_by_player,
		"interruptible": is_interruptible(),
		"data": data.duplicate(true),
		"step_count": steps.size(),
	}


func _job_type_label(value: int) -> String:
	match value:
		JobType.PLAYER_MOVE:
			return "player_move"
		JobType.PLAYER_ATTACK:
			return "player_attack"
		JobType.SELF_DEFENSE:
			return "self_defense"
		JobType.LAW_ARREST:
			return "law_arrest"
		JobType.CARRY_PRISONER:
			return "carry_prisoner"
		JobType.PLACE_IN_CELL:
			return "place_in_cell"
		JobType.ASSIGNED_WORK:
			return "assigned_work"
		JobType.GUARD_POST:
			return "guard_post"
		JobType.AMBIENT_ACTIVITY:
			return "ambient_activity"
		JobType.PATROL:
			return "patrol"
		JobType.NEST_ASSAULT:
			return "nest_assault"
		_:
			return "none"


func _is_valid_combat_target() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.has_method("get_life_state") and target.get("life_state") == null:
		return false
	var target_life_state: int = target.get("life_state")
	if target_life_state != NpcRules.LifeState.ALIVE:
		return false
	return not (target.has_method("is_protected_from_combat") and bool(target.call("is_protected_from_combat")))
