extends Node

class_name WorldMapPlacementProjector

const PROJECTED_MARKER_META := "world_map_projected_marker"

@export var world_definition: Resource
@export var overlay_path: NodePath = NodePath("../WorldMapOverlay")
@export var nest_root_path: NodePath = NodePath("../NestMarkers")
@export_range(4.0, 32.0, 1.0) var town_marker_size := 12.0
@export_range(4.0, 32.0, 1.0) var nest_marker_size := 9.0
@export var town_marker_color := Color(0.95, 0.76, 0.28, 1.0)
@export var nest_marker_color := Color(0.86, 0.28, 0.18, 1.0)
@export var town_label_color := Color(0.92, 0.84, 0.66, 1.0)
@export var town_label_offset := Vector2(9.0, -17.0)

var _overlay: Node
var _map_area: Control


func _ready() -> void:
	add_to_group("world_map_placement_projector")
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_connect_overlay_and_refresh")


func refresh_markers() -> void:
	var overlay := _get_overlay()
	if overlay == null:
		return
	var towns_layer := _get_towns_layer(overlay)
	var nests_layer := _get_nests_layer(overlay)
	if towns_layer == null or nests_layer == null:
		return
	_clear_projected_markers(towns_layer)
	_clear_projected_markers(nests_layer)
	for data in get_projected_town_marker_data():
		towns_layer.add_child(_create_marker(data, town_marker_size, town_marker_color, true))
	for data in get_projected_nest_marker_data():
		nests_layer.add_child(_create_marker(data, nest_marker_size, nest_marker_color, false))


func get_projected_town_marker_data() -> Array[Dictionary]:
	var overlay := _get_overlay()
	if overlay == null:
		return []
	var marker_data: Array[Dictionary] = []
	for placement in _get_settlement_placements():
		var world_position := _placement_world_position(placement)
		var settlement_definition := placement.get("settlement_definition") as Resource
		marker_data.append({
			"id": _placement_id(placement),
			"kind": "town",
			"display_name": _settlement_display_name(settlement_definition, _placement_id(placement)),
			"world_position": world_position,
			"map_position": overlay.call("world_to_map_position", world_position) as Vector2,
		})
	return marker_data


func get_projected_nest_marker_data() -> Array[Dictionary]:
	var overlay := _get_overlay()
	if overlay == null:
		return []
	var marker_data: Array[Dictionary] = []
	for marker in _get_nest_markers():
		var world_position := marker.global_position
		marker_data.append({
			"id": _nest_marker_id(marker),
			"kind": "nest",
			"display_name": _node_display_name(marker, str(marker.name)),
			"world_position": world_position,
			"map_position": overlay.call("world_to_map_position", world_position) as Vector2,
		})
	return marker_data


func _connect_overlay_and_refresh() -> void:
	var overlay := _get_overlay()
	if overlay != null:
		_map_area = _get_map_area(overlay)
		if _map_area != null and not _map_area.resized.is_connected(_on_map_area_resized):
			_map_area.resized.connect(_on_map_area_resized)
	await get_tree().process_frame
	refresh_markers()


func _on_map_area_resized() -> void:
	refresh_markers()


func _get_overlay() -> Node:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	if overlay_path == NodePath():
		return null
	_overlay = get_node_or_null(overlay_path)
	return _overlay


func _get_map_area(overlay: Node) -> Control:
	if overlay.has_method("get_map_area"):
		return overlay.call("get_map_area") as Control
	return null


func _get_towns_layer(overlay: Node) -> Control:
	if overlay.has_method("get_towns_layer"):
		return overlay.call("get_towns_layer") as Control
	return null


func _get_nests_layer(overlay: Node) -> Control:
	if overlay.has_method("get_nests_layer"):
		return overlay.call("get_nests_layer") as Control
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
	var placement_id := str(placement.get("placement_id")).strip_edges() if placement != null else ""
	return placement_id if not placement_id.is_empty() else "town_marker"


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


func _settlement_display_name(settlement_definition: Resource, fallback: String) -> String:
	var display_name := str(settlement_definition.get("display_name")).strip_edges() if settlement_definition != null else ""
	if not display_name.is_empty():
		return display_name
	return fallback.capitalize()


func _get_nest_markers() -> Array[Node3D]:
	var markers: Array[Node3D] = []
	var nest_root := get_node_or_null(nest_root_path) if nest_root_path != NodePath() else null
	if nest_root != null:
		_collect_nest_markers(nest_root, markers)
		return markers
	for node in get_tree().get_nodes_in_group("nest_placement_marker"):
		if node is Node3D:
			markers.append(node as Node3D)
	return markers


func _collect_nest_markers(node: Node, markers: Array[Node3D]) -> void:
	if node is Node3D and (node.has_method("get_marker_id") or node.is_in_group("nest_placement_marker")):
		markers.append(node as Node3D)
	for child in node.get_children():
		_collect_nest_markers(child, markers)


func _nest_marker_id(marker: Node3D) -> String:
	if marker.has_method("get_marker_id"):
		return str(marker.call("get_marker_id")).strip_edges()
	return str(marker.name).strip_edges().to_snake_case()


func _node_display_name(node: Node, fallback: String) -> String:
	if _has_property(node, "display_name"):
		var display_name := str(node.get("display_name")).strip_edges()
		if not display_name.is_empty():
			return display_name
	return fallback.capitalize()


func _clear_projected_markers(layer: Control) -> void:
	for child in layer.get_children():
		if child.has_meta(PROJECTED_MARKER_META):
			layer.remove_child(child)
			child.queue_free()


func _create_marker(data: Dictionary, marker_size: float, marker_color: Color, show_label: bool) -> Control:
	var marker := Control.new()
	marker.name = _node_name_from_id(str(data.get("id", "map_marker")))
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.position = data.get("map_position", Vector2.ZERO)
	marker.set_meta(PROJECTED_MARKER_META, true)
	marker.set_meta("marker_id", str(data.get("id", "")))
	marker.set_meta("marker_kind", str(data.get("kind", "")))
	marker.set_meta("world_position", data.get("world_position", Vector3.ZERO))
	marker.set_meta("map_position", data.get("map_position", Vector2.ZERO))
	marker.add_child(_create_marker_dot(marker_size, marker_color))
	if show_label:
		marker.add_child(_create_town_label(str(data.get("display_name", ""))))
	return marker


func _create_marker_dot(marker_size: float, marker_color: Color) -> Panel:
	var dot := Panel.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.size = Vector2(marker_size, marker_size)
	dot.position = -dot.size * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = marker_color
	style.border_color = Color(0.04, 0.035, 0.03, 1.0)
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	var radius := int(round(marker_size * 0.5))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	dot.add_theme_stylebox_override("panel", style)
	return dot


func _create_town_label(display_name: String) -> Label:
	var label := Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = town_label_offset
	label.size = Vector2(150.0, 22.0)
	label.text = display_name
	label.add_theme_color_override("font_color", town_label_color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.018, 0.015, 0.95))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 12)
	return label


func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _node_name_from_id(value: String) -> String:
	var clean_value := value.strip_edges()
	if clean_value.is_empty():
		return "MapMarker"
	var result := ""
	for part in clean_value.split("_", false):
		if part.is_empty():
			continue
		result += part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return result if not result.is_empty() else "MapMarker"
