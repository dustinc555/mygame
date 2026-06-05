extends Node

class_name ActorQueryController

@export var spatial_cell_size := 12.0
@export var spatial_rebuild_interval_seconds := 0.25

var root_scene: Node
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("actor_query_controller")
	_try_initialize()


func register_actor(actor: Node) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("register_actor"):
		bridge.set("spatial_cell_size", spatial_cell_size)
		bridge.call("register_actor", actor)


func unregister_actor(actor: Node) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("unregister_actor"):
		bridge.call("unregister_actor", actor)


func get_actor_by_stable_id(stable_id: String) -> Node:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_actor_by_stable_id"):
		return null
	return bridge.call("get_actor_by_stable_id", stable_id) as Node


func get_actor_by_instance_id(instance_id: int) -> Node:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_actor_by_instance_id"):
		return null
	return bridge.call("get_actor_by_instance_id", instance_id) as Node


func get_all_actors() -> Array:
	var bridge := _get_gecs_world()
	return bridge.call("get_all_actors") if bridge != null and bridge.has_method("get_all_actors") else []


func get_alive_actors(include_party := true) -> Array:
	var bridge := _get_gecs_world()
	return bridge.call("get_alive_actors", include_party) if bridge != null and bridge.has_method("get_alive_actors") else []


func get_alive_actors_for_settlement(settlement_id: String, include_party := true) -> Array:
	var bridge := _get_gecs_world()
	return bridge.call("get_alive_actors_for_settlement", settlement_id, include_party) if bridge != null and bridge.has_method("get_alive_actors_for_settlement") else []


func get_alive_actors_for_role(role_id: String, include_party := true) -> Array:
	var bridge := _get_gecs_world()
	return bridge.call("get_alive_actors_for_role", role_id, include_party) if bridge != null and bridge.has_method("get_alive_actors_for_role") else []


func get_alive_actors_for_faction(faction_id: String, include_party := true) -> Array:
	var bridge := _get_gecs_world()
	return bridge.call("get_alive_actors_for_faction", faction_id, include_party) if bridge != null and bridge.has_method("get_alive_actors_for_faction") else []


func get_nearby_actors(position: Vector3, radius: float, include_party := true) -> Array:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_nearby_actors"):
		return []
	bridge.set("spatial_cell_size", spatial_cell_size)
	return bridge.call("get_nearby_actors", position, radius, include_party)


func serialize_state() -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("serialize_state"):
		var state: Dictionary = bridge.call("serialize_state")
		return {
			"registered_actor_count": int(state.get("actor_entity_count", 0)),
			"settlement_index_count": 0,
			"faction_index_count": 0,
			"role_index_count": 0,
			"spatial_cell_count": int(state.get("spatial_cell_count", 0)),
			"gecs": state,
		}
	return {
		"registered_actor_count": 0,
		"settlement_index_count": 0,
		"faction_index_count": 0,
		"role_index_count": 0,
		"spatial_cell_count": 0,
	}


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	_collect_existing_actors()
	_initialized = true


func _collect_existing_actors() -> void:
	return


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
