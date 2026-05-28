extends Node

class_name AiSchedulerController

const GECS_WORLD_CONTROLLER_SCRIPT := preload("res://scripts/controllers/gecs_world_controller.gd")

@export var default_tick_interval_seconds := 0.45
@export var default_tick_jitter_seconds := 0.15

var root_scene: Node
var _sim_time := 0.0
var _rng := RandomNumberGenerator.new()
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_initialized = true
	refresh_from_gecs_state()


func _ready() -> void:
	add_to_group("ai_scheduler_controller")
	_rng.randomize()
	_initialized = true
	refresh_from_gecs_state()


func _process(delta: float) -> void:
	if not _initialized:
		return
	_sim_time += delta
	sync_ai_scheduler_state()


func should_tick_actor(actor: Node, interval_seconds := -1.0, jitter_seconds := -1.0) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var interval: float = default_tick_interval_seconds if interval_seconds < 0.0 else interval_seconds
	var jitter: float = default_tick_jitter_seconds if jitter_seconds < 0.0 else jitter_seconds
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("should_tick_actor"):
		return bool(bridge.call("should_tick_actor", actor, _sim_time, interval, jitter, _rng))
	return true


func get_sim_time() -> float:
	return _sim_time


func clear_actor(actor: Node) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("clear_actor_schedule"):
		bridge.call("clear_actor_schedule", actor)


func serialize_state() -> Dictionary:
	sync_ai_scheduler_state()
	var bridge := _get_gecs_world()
	var gecs_state: Dictionary = bridge.call("serialize_state") if bridge != null and bridge.has_method("serialize_state") else {}
	return {
		"scheduled_actor_count": int(gecs_state.get("actor_entity_count", 0)),
		"sim_time": _sim_time,
		"default_tick_interval_seconds": default_tick_interval_seconds,
		"default_tick_jitter_seconds": default_tick_jitter_seconds,
		"gecs": gecs_state,
	}


func apply_serialized_state(state: Dictionary) -> void:
	_sim_time = float(state.get("sim_time", _sim_time))
	default_tick_interval_seconds = float(state.get("default_tick_interval_seconds", default_tick_interval_seconds))
	default_tick_jitter_seconds = float(state.get("default_tick_jitter_seconds", default_tick_jitter_seconds))
	sync_ai_scheduler_state()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_ai_scheduler_state"):
		return
	var state: Dictionary = bridge.call("get_ai_scheduler_state")
	if state.is_empty():
		return
	_sim_time = float(state.get("sim_time", _sim_time))
	default_tick_interval_seconds = float(state.get("default_tick_interval_seconds", default_tick_interval_seconds))
	default_tick_jitter_seconds = float(state.get("default_tick_jitter_seconds", default_tick_jitter_seconds))


func sync_ai_scheduler_state() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_ai_scheduler_state"):
		bridge.call("upsert_ai_scheduler_state", {
			"state_id": "ai_scheduler",
			"sim_time": _sim_time,
			"default_tick_interval_seconds": default_tick_interval_seconds,
			"default_tick_jitter_seconds": default_tick_jitter_seconds,
		})


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	var existing := get_tree().get_first_node_in_group("gecs_world_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	if parent_node == null:
		return null
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	parent_node.add_child(bridge)
	bridge.call("initialize", root_scene if root_scene != null else parent_node)
	return bridge
