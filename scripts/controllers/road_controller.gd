extends Node

class_name RoadController

var root_scene: Node
var roads: Dictionary = {}
var roads_visible := false
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("road_controller")
	_try_initialize()


func refresh() -> void:
	roads.clear()
	_collect_roads()
	_apply_debug_visibility()


func toggle_roads_visible() -> String:
	set_roads_visible(not roads_visible)
	return "Roads visible" if roads_visible else "Roads hidden"


func set_roads_visible(value: bool) -> void:
	roads_visible = value
	for node in get_tree().get_nodes_in_group("road_path"):
		if node.has_method("set_debug_visible"):
			node.call("set_debug_visible", value)


func get_route_waypoints(source_settlement_id: String, target_settlement_id: String) -> Array[Vector3]:
	for node in get_tree().get_nodes_in_group("road_path"):
		if node == null or not node.has_method("connects_settlements"):
			continue
		if not bool(node.call("connects_settlements", source_settlement_id, target_settlement_id)):
			continue
		var points := _road_points(node)
		if points.size() < 2:
			continue
		if str(node.get("source_settlement_id")) == target_settlement_id and str(node.get("target_settlement_id")) == source_settlement_id:
			points.reverse()
		return points
	return []


func serialize_state() -> Dictionary:
	return {
		"roads": roads.duplicate(true),
		"roads_visible": roads_visible,
	}


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	_collect_roads()
	_apply_debug_visibility()
	_initialized = true


func _collect_roads() -> void:
	for node in get_tree().get_nodes_in_group("road_path"):
		if node.has_method("get_road_record"):
			var record: Dictionary = node.call("get_road_record")
			var id := str(record.get("road_id", node.name))
			roads[id] = record


func _apply_debug_visibility() -> void:
	set_roads_visible(roads_visible)


func _road_points(road: Node) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if road == null or not road.has_method("get_world_points"):
		return result
	for point in road.call("get_world_points"):
		if point is Vector3:
			result.append(point)
	return result
