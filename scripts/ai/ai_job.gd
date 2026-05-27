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
}

const PRIORITY_NONE := 0
const PRIORITY_GUARD_POST := 20
const PRIORITY_ASSIGNED_WORK := 35
const PRIORITY_CARRY_PRISONER := 82
const PRIORITY_PLACE_IN_CELL := 86
const PRIORITY_SELF_DEFENSE := 90
const PRIORITY_LAW_ARREST := 96
const PRIORITY_PLAYER_ATTACK := 120
const PRIORITY_PLAYER_MOVE := 130

var job_type: int = JobType.NONE
var priority := PRIORITY_NONE
var target = null
var source = null
var issued_by_player := false
var origin_position := Vector3.ZERO
var objective_id := ""


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


func should_replace(active_job, owner) -> bool:
	if active_job == null or not active_job.is_valid_for(owner):
		return true
	if active_job == self:
		return true
	if is_combat() and active_job.is_combat() and active_job.target == target:
		return priority >= active_job.priority
	return priority > active_job.priority


func _is_valid_combat_target() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.has_method("get_life_state") and target.get("life_state") == null:
		return false
	var target_life_state: int = target.get("life_state")
	if target_life_state != NpcRules.LifeState.ALIVE:
		return false
	return not (target.has_method("is_protected_from_combat") and bool(target.call("is_protected_from_combat")))
