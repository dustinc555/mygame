extends Node

class_name WorldMapProjectionDebug

const DEBUG_MARKER_META := "world_map_projection_debug_marker"

@export var world_definition: Resource
@export var overlay_path: NodePath = NodePath("../WorldMapOverlay")
@export_range(2.0, 32.0, 1.0) var marker_size := 9.0
@export var marker_color := Color(0.95, 0.72, 0.22, 1.0)
@export var projection_test_anchor_color := Color(0.35, 0.64, 1.0, 0.9)
@export var show_projection_test_anchors := false

var _overlay: Node
var _map_area: Control


func _ready() -> void:
	add_to_group("world_map_projection_debug")
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_connect_overlay_and_refresh")


func refresh_debug_markers() -> void:
	var overlay := _get_overlay()
	if overlay == null:
		return
	var towns_layer := _get_towns_layer(overlay)
	if towns_layer == null:
		return
	_clear_debug_markers(towns_layer)
	var marker_data := get_projected_marker_data()
	for data in marker_data:
		var marker := _create_marker(data)
		towns_layer.add_child(marker)


func get_projected_marker_data() -> Array[Dictionary]:
	var overlay := _get_overlay()
	if overlay == null:
		return []
	var marker_data: Array[Dictionary] = []
	for placement in _get_settlement_placements():
		var marker_id := _placement_id(placement)
		var world_position := _placement_world_position(placement)
		var map_position := overlay.call("world_to_map_position", world_position) as Vector2
		marker_data.append({
			"id": marker_id,
			"kind": "settlement_placement",
			"world_position": world_position,
			"map_position": map_position,
		})
	if show_projection_test_anchors:
		marker_data.append_array(_projection_test_anchor_data(overlay))
	return marker_data


func _connect_overlay_and_refresh() -> void:
	var overlay := _get_overlay()
	if overlay != null:
		_map_area = _get_map_area(overlay)
		if _map_area != null and not _map_area.resized.is_connected(_on_map_area_resized):
			_map_area.resized.connect(_on_map_area_resized)
	await get_tree().process_frame
	refresh_debug_markers()


func _on_map_area_resized() -> void:
	refresh_debug_markers()


func _get_overlay() -> Node:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	if overlay_path == NodePath():
		return null
	_overlay = get_node_or_null(overlay_path)
	return _overlay


func _get_map_area(overlay: Node) -> Control:
	if overlay != null and overlay.has_method("get_map_area"):
		return overlay.call("get_map_area") as Control
	return null


func _get_towns_layer(overlay: Node) -> Control:
	if overlay != null and overlay.has_method("get_towns_layer"):
		return overlay.call("get_towns_layer") as Control
	return null


func _get_settlement_placements() -> Array[Resource]:
	var placements: Array[Resource] = []
	if world_definition == null:
		return placements
	var raw_placements = world_definition.get("settlement_placements")
	if not (raw_placements is Array):
		return placements
	for placement in raw_placements:
		if placement is Resource:
			placements.append(placement)
	return placements


func _placement_id(placement: Resource) -> String:
	if placement != null and placement.has_method("get_id"):
		return str(placement.call("get_id")).strip_edges()
	var placement_id := ""
	if placement != null:
		var raw_id = placement.get("placement_id")
		if raw_id != null:
			placement_id = str(raw_id).strip_edges()
	return placement_id if not placement_id.is_empty() else "projection_marker"


func _placement_world_position(placement: Resource) -> Vector3:
	if placement == null:
		return Vector3.ZERO
	var transform_value = placement.get("world_transform")
	if transform_value is Transform3D:
		var world_transform: Transform3D = transform_value
		return world_transform.origin
	var settlement_definition := placement.get("settlement_definition") as Resource
	if settlement_definition != null:
		var position_value = settlement_definition.get("world_position")
		if position_value is Vector3:
			return position_value
	return Vector3.ZERO


func _projection_test_anchor_data(overlay: Node) -> Array[Dictionary]:
	var anchor_data: Array[Dictionary] = []
	var world_bounds := overlay.call("get_projection_world_bounds") as Rect2
	var world_positions := {
		"projection_test_min": Vector3(world_bounds.position.x, 0.0, world_bounds.position.y),
		"projection_test_max": Vector3(world_bounds.end.x, 0.0, world_bounds.end.y),
	}
	for anchor_id in world_positions.keys():
		var world_position: Vector3 = world_positions[anchor_id]
		anchor_data.append({
			"id": str(anchor_id),
			"kind": "projection_test_anchor",
			"world_position": world_position,
			"map_position": overlay.call("world_to_map_position", world_position) as Vector2,
		})
	return anchor_data


func _clear_debug_markers(layer: Control) -> void:
	for child in layer.get_children():
		if child.has_meta(DEBUG_MARKER_META):
			layer.remove_child(child)
			child.queue_free()


func _create_marker(data: Dictionary) -> ColorRect:
	var marker := ColorRect.new()
	marker.name = _node_name_from_id(str(data.get("id", "projection_marker")))
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.color = projection_test_anchor_color if str(data.get("kind", "")) == "projection_test_anchor" else marker_color
	marker.custom_minimum_size = Vector2(marker_size, marker_size)
	marker.size = marker.custom_minimum_size
	var map_position: Vector2 = data.get("map_position", Vector2.ZERO)
	marker.position = map_position - marker.size * 0.5
	marker.set_meta(DEBUG_MARKER_META, true)
	marker.set_meta("marker_id", str(data.get("id", "")))
	marker.set_meta("marker_kind", str(data.get("kind", "")))
	marker.set_meta("world_position", data.get("world_position", Vector3.ZERO))
	marker.set_meta("map_position", map_position)
	return marker


func _node_name_from_id(value: String) -> String:
	var clean_value := value.strip_edges()
	if clean_value.is_empty():
		return "ProjectionMarker"
	var result := ""
	for part in clean_value.split("_", false):
		if part.is_empty():
			continue
		result += part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return result if not result.is_empty() else "ProjectionMarker"
