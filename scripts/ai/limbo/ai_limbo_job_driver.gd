extends Node

class_name AiLimboJobDriver

const AI_TASK_STEP_SCRIPT = preload("res://scripts/ai/ai_task_step.gd")
const AI_LIMBO_TASK_STEP_ACTION_SCRIPT = preload("res://scripts/ai/limbo/ai_limbo_task_step_action.gd")

const BT_UPDATE_MANUAL := 2

var owner_actor = null
var job = null
var steps: Array = []
var current_step_index := 0
var last_status: int = AI_TASK_STEP_SCRIPT.StepStatus.READY

var _bt_player: BTPlayer
var _behavior_tree: BehaviorTree
var _blackboard: Blackboard
var _disposed := false


func setup(target_owner, target_job) -> void:
	owner_actor = target_owner
	job = target_job
	steps = target_job.steps.duplicate() if target_job != null and target_job.get("steps") is Array else []
	current_step_index = 0
	last_status = AI_TASK_STEP_SCRIPT.StepStatus.READY
	name = "AiLimboJobDriver"
	_build_behavior_player()


func tick(delta: float) -> int:
	if _disposed:
		return AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED
	if steps.is_empty():
		last_status = AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED
		return last_status
	if _bt_player == null or not is_instance_valid(_bt_player):
		last_status = AI_TASK_STEP_SCRIPT.StepStatus.FAILED
		return last_status
	_bt_player.update(delta)
	return last_status


func tick_step(step_index: int, delta: float) -> int:
	if _disposed:
		last_status = AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED
		return last_status
	if step_index < current_step_index:
		return AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED
	if step_index < 0 or step_index >= steps.size():
		last_status = AI_TASK_STEP_SCRIPT.StepStatus.FAILED
		return last_status
	var step = steps[step_index]
	if step == null or not step.has_method("start") or not step.has_method("tick"):
		last_status = AI_TASK_STEP_SCRIPT.StepStatus.FAILED
		return last_status
	current_step_index = step_index
	if int(step.get("status")) == AI_TASK_STEP_SCRIPT.StepStatus.READY:
		step.start(owner_actor, job)
	var result: int = int(step.tick(owner_actor, job, delta))
	match result:
		AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED:
			current_step_index = step_index + 1
			last_status = AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED if current_step_index >= steps.size() else AI_TASK_STEP_SCRIPT.StepStatus.RUNNING
		AI_TASK_STEP_SCRIPT.StepStatus.RUNNING, AI_TASK_STEP_SCRIPT.StepStatus.READY:
			last_status = AI_TASK_STEP_SCRIPT.StepStatus.RUNNING
		AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED:
			last_status = AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED
		_:
			last_status = AI_TASK_STEP_SCRIPT.StepStatus.FAILED
	return result


func cancel() -> void:
	if _disposed:
		return
	var last_started_index := mini(current_step_index, steps.size() - 1)
	for index in range(last_started_index, -1, -1):
		var step = steps[index]
		if step != null and step.has_method("cancel"):
			if int(step.get("status")) != AI_TASK_STEP_SCRIPT.StepStatus.READY:
				step.cancel(owner_actor, job)
	last_status = AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED
	dispose()


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	if _bt_player != null and is_instance_valid(_bt_player):
		_bt_player.active = false
	if is_inside_tree():
		queue_free()
	else:
		call_deferred("free")


func get_current_step():
	if current_step_index >= 0 and current_step_index < steps.size():
		return steps[current_step_index]
	return null


func get_debug_snapshot() -> Dictionary:
	var step = get_current_step()
	return {
		"runtime": "limboai",
		"current_step_index": current_step_index,
		"step_count": steps.size(),
		"status": last_status,
		"current_step": step.get_debug_snapshot() if step != null and step.has_method("get_debug_snapshot") else {},
	}


func _build_behavior_player() -> void:
	_behavior_tree = BehaviorTree.new()
	var root := BTSequence.new()
	root.custom_name = "AI Job"
	for index in range(steps.size()):
		var action = AI_LIMBO_TASK_STEP_ACTION_SCRIPT.new()
		action.step_index = index
		root.add_child(action)
	_behavior_tree.root_task = root

	_blackboard = Blackboard.new()
	_blackboard.set_var(&"ai_limbo_driver", self)
	_blackboard.set_var(&"ai_job", job)

	_bt_player = BTPlayer.new()
	_bt_player.name = "BTPlayer"
	_bt_player.active = false
	_bt_player.agent_node = NodePath("../..")
	_bt_player.update_mode = BT_UPDATE_MANUAL
	_bt_player.blackboard = _blackboard
	_bt_player.behavior_tree = _behavior_tree
	if owner_actor is Node:
		_bt_player.set_scene_root_hint(owner_actor)
	add_child(_bt_player)
	_bt_player.active = true
