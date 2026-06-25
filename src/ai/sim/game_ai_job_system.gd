extends "res://addons/gecs/ecs/system.gd"

class_name GameAiJobSystem

const C_NODE = preload("res://src/actors/bridge/c_game_actor_node.gd")
const C_AI_STATE = preload("res://src/ai/sim/c_game_ai_state.gd")
const AI_TASK_STEP_SCRIPT = preload("res://src/ai/bridge/ai_task_step.gd")


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_AI_STATE]).iterate([C_NODE, C_AI_STATE])


func process(entities: Array, components: Array, delta: float) -> void:
	var nodes: Array = components[0]
	var ai_states: Array = components[1]
	for index in range(entities.size()):
		var actor := _resolve_actor(nodes[index])
		var ai_state = ai_states[index]
		if actor == null or ai_state == null or ai_state.active_job == null or ai_state.active_driver == null:
			continue
		var result: int = ai_state.active_driver.tick(delta)
		ai_state.current_step_index = int(ai_state.active_driver.get("current_step_index")) if ai_state.active_driver != null else 0
		ai_state.last_step_status = result
		match result:
			AI_TASK_STEP_SCRIPT.StepStatus.SUCCEEDED, AI_TASK_STEP_SCRIPT.StepStatus.FAILED, AI_TASK_STEP_SCRIPT.StepStatus.CANCELLED:
				if actor.has_method("finish_active_ai_job_from_gecs"):
					actor.call("finish_active_ai_job_from_gecs", result)


func _resolve_actor(actor_component) -> Node:
	if actor_component == null:
		return null
	var actor = actor_component.get_actor() if actor_component.has_method("get_actor") else actor_component.actor
	if actor != null and is_instance_valid(actor):
		return actor as Node
	if actor_component.actor_path != NodePath():
		actor = get_node_or_null(actor_component.actor_path)
		if actor != null:
			actor_component.actor = actor
			actor_component.instance_id = actor.get_instance_id()
			return actor as Node
	return null
