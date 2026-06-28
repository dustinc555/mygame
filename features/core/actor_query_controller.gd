extends Node

class_name ActorQueryController

const SERVICE_ID := &"actor_query"

@export var spatial_cell_size := 6.0
@export var spatial_rebuild_interval_seconds := 0.25

var root_scene: Node
var _context: BootstrapContext
var _initialized := false


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_context = context
	_try_initialize()


func _ready() -> void:
	add_to_group("actor_query_controller")
	_try_initialize()


func register_actor(actor: Node) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("register_actor"):
		bridge.set("spatial_cell_size", spatial_cell_size)
		if _has_property(bridge, "spatial_rebuild_interval_seconds"):
			bridge.set("spatial_rebuild_interval_seconds", spatial_rebuild_interval_seconds)
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
	if _has_property(bridge, "spatial_rebuild_interval_seconds"):
		bridge.set("spatial_rebuild_interval_seconds", spatial_rebuild_interval_seconds)
	return bridge.call("get_nearby_actors", position, radius, include_party)


func get_nearby_actors_limited(position: Vector3, radius: float, max_count: int, include_party := true) -> Array:
	var bridge := _get_gecs_world()
	if bridge == null:
		return []
	bridge.set("spatial_cell_size", spatial_cell_size)
	if _has_property(bridge, "spatial_rebuild_interval_seconds"):
		bridge.set("spatial_rebuild_interval_seconds", spatial_rebuild_interval_seconds)
	if bridge.has_method("get_nearby_actors_limited"):
		return bridge.call("get_nearby_actors_limited", position, radius, max_count, include_party)
	return bridge.call("get_nearby_actors", position, radius, include_party) if bridge.has_method("get_nearby_actors") else []


func get_actor_query_metrics() -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_actor_query_metrics"):
		return bridge.call("get_actor_query_metrics") as Dictionary
	return {}


func reset_actor_query_metrics() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("reset_actor_query_metrics"):
		bridge.call("reset_actor_query_metrics")


func set_actor_query_metrics_enabled(enabled: bool) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("set_actor_query_metrics_enabled"):
		bridge.call("set_actor_query_metrics_enabled", enabled)


func get_all_humanoids() -> Array:
	return get_all_actors()


func get_alive_humanoids(include_party := true) -> Array:
	return get_alive_actors(include_party)


func get_alive_humanoids_for_settlement(settlement_id: String, include_party := true) -> Array:
	return get_alive_actors_for_settlement(settlement_id, include_party)


func get_alive_humanoids_for_role(role_id: String, include_party := true) -> Array:
	return get_alive_actors_for_role(role_id, include_party)


func get_alive_humanoids_for_faction(faction_id: String, include_party := true) -> Array:
	return get_alive_actors_for_faction(faction_id, include_party)


func get_nearby_humanoids(position: Vector3, radius: float, include_party := true) -> Array:
	return get_nearby_actors(position, radius, include_party)


func get_nearby_humanoids_limited(position: Vector3, radius: float, max_count: int, include_party := true) -> Array:
	return get_nearby_actors_limited(position, radius, max_count, include_party)


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
	# Late spawns (created characters, squads, encounter bodies) register centrally:
	# per-scene spawners must NOT need to know about GECS registration.
	var tree := get_tree()
	if tree != null and not tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.connect(_on_tree_node_added)
	_initialized = true


func _on_tree_node_added(node: Node) -> void:
	var actor := node as WorldActor
	if actor == null:
		return
	# Register after the actor's own _ready (groups + capabilities exist by then).
	if actor.is_node_ready():
		register_actor(actor)
	else:
		actor.ready.connect(register_actor.bind(actor), CONNECT_ONE_SHOT)


func _collect_existing_actors() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var registered := {}
	for actor in tree.get_nodes_in_group("combat_actor"):
		register_actor(actor)
		registered[actor.get_instance_id()] = true
	for actor in tree.get_nodes_in_group("humanoid_character"):
		if registered.has(actor.get_instance_id()):
			continue
		register_actor(actor)
		registered[actor.get_instance_id()] = true
	for actor in tree.get_nodes_in_group("npc_character"):
		if registered.has(actor.get_instance_id()):
			continue
		register_actor(actor)
		registered[actor.get_instance_id()] = true
	for actor in tree.get_nodes_in_group("world_actor"):
		if registered.has(actor.get_instance_id()):
			continue
		register_actor(actor)


func _get_gecs_world() -> Node:
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
