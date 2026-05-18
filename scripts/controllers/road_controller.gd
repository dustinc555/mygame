extends Node

class_name RoadController

var root_scene: Node
var roads: Dictionary = {}
var roads_visible := false
var _initialized := false
var _road_graph := AStar3D.new()
var _waypoint_nodes_by_id: Dictionary = {}
var _astar_id_by_waypoint_path: Dictionary = {}
var _settlement_waypoint_ids: Dictionary = {}


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("road_controller")
	_try_initialize()


func refresh() -> void:
	_collect_roads()
	_rebuild_road_graph()
	_apply_debug_visibility()


func toggle_roads_visible() -> String:
	set_roads_visible(not roads_visible)
	return "Roads visible" if roads_visible else "Roads hidden"


func set_roads_visible(value: bool) -> void:
	roads_visible = value
	for node in get_tree().get_nodes_in_group("road_network"):
		if node.has_method("set_debug_visible"):
			node.call("set_debug_visible", value)


func get_route_waypoints(source_settlement_id: String, target_settlement_id: String) -> Array[Vector3]:
	if not _settlement_waypoint_ids.has(source_settlement_id) or not _settlement_waypoint_ids.has(target_settlement_id):
		return []
	var best_path := PackedInt64Array()
	var best_distance := INF
	for source_id in _settlement_waypoint_ids[source_settlement_id]:
		for target_id in _settlement_waypoint_ids[target_settlement_id]:
			var point_path := _road_graph.get_id_path(int(source_id), int(target_id))
			if point_path.is_empty():
				continue
			var distance := _path_distance(point_path)
			if distance < best_distance:
				best_distance = distance
				best_path = point_path
	return _path_positions(best_path)


func serialize_state() -> Dictionary:
	return {
		"roads": roads.duplicate(true),
		"roads_visible": roads_visible,
	}


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	_collect_roads()
	_rebuild_road_graph()
	_apply_debug_visibility()
	_initialized = true


func _collect_roads() -> void:
	roads.clear()
	for node in get_tree().get_nodes_in_group("road_network"):
		if node.has_method("get_network_record"):
			var record: Dictionary = node.call("get_network_record")
			var id := str(record.get("network_id", node.name))
			roads[id] = record


func _apply_debug_visibility() -> void:
	set_roads_visible(roads_visible)


func _rebuild_road_graph() -> void:
	_road_graph.clear()
	_waypoint_nodes_by_id.clear()
	_astar_id_by_waypoint_path.clear()
	_settlement_waypoint_ids.clear()
	var next_point_id := 1
	for network in get_tree().get_nodes_in_group("road_network"):
		if network == null or not network.has_method("get_waypoints"):
			continue
		for waypoint in network.call("get_waypoints"):
			if waypoint == null or not waypoint.has_method("get_waypoint_id"):
				continue
			var point_id := next_point_id
			next_point_id += 1
			_road_graph.add_point(point_id, waypoint.global_position)
			_waypoint_nodes_by_id[point_id] = waypoint
			_astar_id_by_waypoint_path[str(waypoint.get_path())] = point_id
			var settlement_id := str(waypoint.get("settlement_id"))
			if not settlement_id.is_empty():
				_add_settlement_waypoint(settlement_id, point_id)
	_connect_waypoint_edges()


func _connect_waypoint_edges() -> void:
	for point_id in _waypoint_nodes_by_id.keys():
		var waypoint: Node = _waypoint_nodes_by_id[point_id]
		if waypoint == null or not is_instance_valid(waypoint) or not waypoint.has_method("get_connected_waypoints"):
			continue
		for connected in waypoint.call("get_connected_waypoints"):
			if connected == null or not is_instance_valid(connected):
				continue
			var connected_path := str(connected.get_path())
			if not _astar_id_by_waypoint_path.has(connected_path):
				continue
			var connected_id := int(_astar_id_by_waypoint_path[connected_path])
			if point_id == connected_id or _road_graph.are_points_connected(point_id, connected_id):
				continue
			_road_graph.connect_points(point_id, connected_id, true)


func _add_settlement_waypoint(settlement_id: String, point_id: int) -> void:
	var ids: Array = _settlement_waypoint_ids.get(settlement_id, [])
	ids.append(point_id)
	_settlement_waypoint_ids[settlement_id] = ids


func _path_positions(point_path: PackedInt64Array) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for point_id in point_path:
		positions.append(_road_graph.get_point_position(int(point_id)))
	return positions


func _path_distance(point_path: PackedInt64Array) -> float:
	var distance := 0.0
	for index in range(point_path.size() - 1):
		var from_position := _road_graph.get_point_position(int(point_path[index]))
		var to_position := _road_graph.get_point_position(int(point_path[index + 1]))
		distance += from_position.distance_to(to_position)
	return distance
