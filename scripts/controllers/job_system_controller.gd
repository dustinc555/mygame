extends Node

class_name JobSystemController

var root_scene: Node
var _sim_time := 0.0
var _initialized := false
var _job_providers: Array = []


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	if is_inside_tree():
		_initialized = true
		_refresh_job_provider_cache()
	refresh_from_gecs_state()


func _ready() -> void:
	add_to_group("job_system_controller")
	if root_scene != null:
		_initialized = true
	_refresh_job_provider_cache()
	refresh_from_gecs_state()


func register_job_provider(provider: Node) -> void:
	if provider == null or not is_instance_valid(provider):
		return
	if _job_providers.has(provider):
		return
	_job_providers.append(provider)


func unregister_job_provider(provider: Node) -> void:
	var index := _job_providers.find(provider)
	if index >= 0:
		_job_providers.remove_at(index)


func _process(delta: float) -> void:
	if not _initialized:
		return
	_sim_time += delta
	_expire_missed_job_contracts()
	_process_job_provider_contracts(delta)
	_sync_job_system_state_to_gecs()


func get_sim_time() -> float:
	return _sim_time


func serialize_state() -> Dictionary:
	_sync_job_system_state_to_gecs()
	return {"state_id": "job_system", "sim_time": _sim_time}


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty():
		refresh_from_gecs_state()
		return
	_sim_time = float(state.get("sim_time", _sim_time))
	_sync_job_system_state_to_gecs()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_job_system_state"):
		return
	var state: Dictionary = bridge.call("get_job_system_state")
	if not state.is_empty():
		_sim_time = float(state.get("sim_time", _sim_time))


func sync_job_system_state() -> void:
	_sync_job_system_state_to_gecs()


func _sync_job_system_state_to_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_job_system_state"):
		bridge.call("upsert_job_system_state", {"state_id": "job_system", "sim_time": _sim_time})


func _expire_missed_job_contracts() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("expire_missed_job_contracts"):
		bridge.call("expire_missed_job_contracts", _sim_time)


func _process_job_provider_contracts(delta: float) -> void:
	for index in range(_job_providers.size() - 1, -1, -1):
		var provider = _job_providers[index]
		if provider == null or not is_instance_valid(provider) or not provider.is_inside_tree():
			_job_providers.remove_at(index)
			continue
		if provider.has_method("process_contracts"):
			provider.call("process_contracts", delta, _sim_time)


func _refresh_job_provider_cache() -> void:
	if not is_inside_tree():
		return
	for provider in get_tree().get_nodes_in_group("job_provider"):
		register_job_provider(provider)


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
	return null
