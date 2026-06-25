extends "res://addons/gecs/ecs/system.gd"

class_name GecsBenchmarkMovementSystem

const C_ACTOR = preload("res://tools/benchmark/gecs/components/c_benchmark_actor.gd")
const C_TRANSFORM = preload("res://tools/benchmark/gecs/components/c_benchmark_transform.gd")
const C_AGENT = preload("res://tools/benchmark/gecs/components/c_benchmark_agent.gd")

var total_distance_moved := 0.0


func query() -> QueryBuilder:
	return q.with_all([C_TRANSFORM, C_AGENT, C_ACTOR]).iterate([C_TRANSFORM, C_AGENT, C_ACTOR])


func process(entities: Array, components: Array, delta: float) -> void:
	var transforms: Array = components[0]
	var agents: Array = components[1]
	var actors: Array = components[2]
	for index in range(entities.size()):
		var transform := transforms[index] as CBenchmarkTransform
		var agent := agents[index] as CBenchmarkAgent
		var actor_component := actors[index] as CBenchmarkActor
		if transform == null or agent == null or actor_component == null:
			continue
		_step_transform(transform, agent, delta)
		_sync_actor(actor_component, transform)


func _step_transform(transform: CBenchmarkTransform, agent: CBenchmarkAgent, delta: float) -> void:
	var to_destination := agent.target_position - transform.position
	to_destination.y = 0.0
	var distance := to_destination.length()
	if distance <= 0.05:
		return
	var direction := to_destination / distance
	var step := minf(distance, maxf(agent.speed, 0.0) * delta)
	transform.position += direction * step
	transform.facing = direction
	transform.distance_moved += step
	total_distance_moved += step


func _sync_actor(actor_component: CBenchmarkActor, transform: CBenchmarkTransform) -> void:
	var actor := _resolve_actor(actor_component)
	if actor == null:
		return
	actor.global_position = transform.position
	if transform.facing.length_squared() <= 0.001:
		return
	actor.look_at(actor.global_position + transform.facing, Vector3.UP)
	actor.rotation.x = 0.0
	actor.rotation.z = 0.0


func _resolve_actor(actor_component: CBenchmarkActor) -> Node3D:
	if actor_component.actor != null and is_instance_valid(actor_component.actor):
		return actor_component.actor
	if actor_component.actor_path == NodePath():
		return null
	var actor := get_node_or_null(actor_component.actor_path) as Node3D
	actor_component.actor = actor
	return actor
