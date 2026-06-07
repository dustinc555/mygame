extends Node

class_name DemoSimBootstrap

const DEMO_SIM_ENTITY_ID := "demo_sim:state"
const GECS_WORLD_SCRIPT := preload("res://addons/gecs/ecs/world.gd")
const GECS_ENTITY_SCRIPT := preload("res://addons/gecs/ecs/entity.gd")
const DEMO_SIM_STATE_SCRIPT := preload("res://scripts/ecs/components/c_game_demo_sim_state.gd")

@export var world_definition: Resource

var _ecs_world
var _sim_state_entity
var _sim_state_component
var _sim_runner: Node


func _ready() -> void:
	add_to_group("demo_sim_bootstrap")
	_ensure_world()
	_ensure_state_entity()
	_sim_runner = _find_sim_runner()


func _exit_tree() -> void:
	var ecs_singleton := get_node_or_null("/root/ECS")
	if ecs_singleton != null and ecs_singleton.get("world") == _ecs_world:
		ecs_singleton.set("world", null)


func get_sim_state() -> Dictionary:
	_ensure_state_entity()
	if _sim_state_component != null and _sim_state_component.has_method("to_state"):
		return _sim_state_component.call("to_state")
	return {}


func update_sim(fixed_delta: float) -> void:
	_ensure_state_entity()
	if _ecs_world != null and _ecs_world.has_method("process"):
		_ecs_world.call("process", fixed_delta)


func get_sim_metrics() -> Dictionary:
	var metrics := {}
	var runner := _get_sim_runner()
	if runner != null and runner.has_method("get_metrics"):
		metrics = runner.call("get_metrics")
	metrics["state"] = get_sim_state()
	return metrics


func _ensure_world() -> void:
	if _ecs_world != null and is_instance_valid(_ecs_world):
		_set_active_ecs_world()
		return
	_ecs_world = get_node_or_null("DemoSimECSWorld")
	if _ecs_world == null:
		_ecs_world = GECS_WORLD_SCRIPT.new()
		_ecs_world.name = "DemoSimECSWorld"
		add_child(_ecs_world)
	if _ecs_world.has_method("initialize"):
		_ecs_world.call("initialize")
	_set_active_ecs_world()


func _ensure_state_entity() -> void:
	_ensure_world()
	if _ecs_world == null:
		return
	if _sim_state_entity == null or not is_instance_valid(_sim_state_entity):
		_sim_state_entity = _find_state_entity()
	if _sim_state_entity == null:
		_sim_state_entity = GECS_ENTITY_SCRIPT.new()
		_sim_state_entity.name = "DemoSimState"
		_sim_state_entity.id = DEMO_SIM_ENTITY_ID
		_ecs_world.call("add_entity", _sim_state_entity, [DEMO_SIM_STATE_SCRIPT.new()])
		_sim_state_component = _sim_state_entity.call("get_component", DEMO_SIM_STATE_SCRIPT)
		if _sim_state_component != null and _sim_state_component.has_method("apply_state"):
			_sim_state_component.call("apply_state", _initial_state())
		return
	_sim_state_component = _sim_state_entity.call("get_component", DEMO_SIM_STATE_SCRIPT)


func _find_state_entity():
	var registry = _ecs_world.get("entity_id_registry")
	if registry is Dictionary:
		var entity = registry.get(DEMO_SIM_ENTITY_ID)
		if entity != null and is_instance_valid(entity):
			return entity
	return null


func _initial_state() -> Dictionary:
	return {
		"state_id": "demo_sim",
		"world_id": _world_definition_id(),
		"world_definition_path": _world_definition_path(),
	}


func _world_definition_id() -> String:
	if world_definition != null and world_definition.has_method("get_id"):
		return str(world_definition.call("get_id")).strip_edges()
	return ""


func _world_definition_path() -> String:
	return str(world_definition.resource_path) if world_definition != null else ""


func _set_active_ecs_world() -> void:
	var ecs_singleton := get_node_or_null("/root/ECS")
	if ecs_singleton != null:
		ecs_singleton.set("world", _ecs_world)


func _get_sim_runner() -> Node:
	if _sim_runner != null and is_instance_valid(_sim_runner):
		return _sim_runner
	_sim_runner = _find_sim_runner()
	return _sim_runner


func _find_sim_runner() -> Node:
	var direct := get_node_or_null("FixedTickSimRunner")
	if direct != null:
		return direct
	for child in get_children():
		if child.is_in_group("fixed_tick_sim_runner"):
			return child
	return null
