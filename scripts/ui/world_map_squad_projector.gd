extends Node

class_name WorldMapSquadProjector

const PROJECTED_SQUAD_MARKER_META := "world_map_projected_squad_marker"

@export var world_definition: Resource
@export var overlay_path: NodePath = NodePath("../WorldMapOverlay")
@export var squad_state_source_path: NodePath = NodePath("../DemoSimBootstrap")
@export_range(0.0, 1.0, 0.01) var refresh_interval_seconds := 0.1
@export_range(4.0, 32.0, 1.0) var squad_marker_size := 10.0
@export var fallback_squad_color := Color(0.7, 0.7, 0.72, 1.0)

var _overlay: Node
var _squad_state_source: Node
var _map_area: Control
var _squad_markers := {}
var _faction_colors := {}
var _faction_colors_built := false
var _refresh_elapsed := 0.0


func _ready() -> void:
	add_to_group("world_map_squad_projector")
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_connect_overlay_and_refresh")


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if refresh_interval_seconds > 0.0 and _refresh_elapsed < refresh_interval_seconds:
		return
	_refresh_elapsed = 0.0
	refresh_squad_markers()


func refresh_squad_markers() -> void:
	var overlay := _get_overlay()
	if overlay == null:
		return
	var squads_layer := _get_squads_layer(overlay)
	if squads_layer == null:
		return
	var seen_squad_ids := {}
	for data in get_projected_squad_marker_data():
		var squad_id := str(data.get("id", ""))
		if squad_id.is_empty():
			continue
		seen_squad_ids[squad_id] = true
		var marker := _get_or_create_marker(squad_id, squads_layer)
		_update_marker(marker, data)
	_remove_stale_markers(seen_squad_ids)


func get_projected_squad_marker_data() -> Array[Dictionary]:
	var overlay := _get_overlay()
	if overlay == null:
		return []
	var active_squads := _get_active_squad_records()
	var marker_data: Array[Dictionary] = []
	for squad_key in active_squads.keys():
		var record = active_squads[squad_key]
		if not (record is Dictionary):
			continue
		var squad_id := str(record.get("squad_id", squad_key)).strip_edges()
		if squad_id.is_empty():
			continue
		var world_position := _record_location(record)
		var faction_id := str(record.get("faction_id", "")).strip_edges()
		var squad_state := str(record.get("state", "unknown")).strip_edges()
		marker_data.append({
			"id": squad_id,
			"kind": "squad",
			"faction_id": faction_id,
			"state": squad_state,
			"member_count": int(record.get("member_count", 0)),
			"strength": float(record.get("strength", 0.0)),
			"world_position": world_position,
			"map_position": overlay.call("world_to_map_position", world_position) as Vector2,
			"color": _faction_color(faction_id),
		})
	return marker_data


func _connect_overlay_and_refresh() -> void:
	var overlay := _get_overlay()
	if overlay != null:
		_map_area = _get_map_area(overlay)
		if _map_area != null and not _map_area.resized.is_connected(_on_map_area_resized):
			_map_area.resized.connect(_on_map_area_resized)
	await get_tree().process_frame
	refresh_squad_markers()


func _on_map_area_resized() -> void:
	refresh_squad_markers()


func _get_overlay() -> Node:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	if overlay_path == NodePath():
		return null
	_overlay = get_node_or_null(overlay_path)
	return _overlay


func _get_squad_state_source() -> Node:
	if _squad_state_source != null and is_instance_valid(_squad_state_source):
		return _squad_state_source
	if squad_state_source_path == NodePath():
		return null
	_squad_state_source = get_node_or_null(squad_state_source_path)
	return _squad_state_source


func _get_map_area(overlay: Node) -> Control:
	if overlay.has_method("get_map_area"):
		return overlay.call("get_map_area") as Control
	return null


func _get_squads_layer(overlay: Node) -> Control:
	if overlay.has_method("get_squads_layer"):
		return overlay.call("get_squads_layer") as Control
	return null


func _get_active_squad_records() -> Dictionary:
	var source := _get_squad_state_source()
	if source == null or not source.has_method("get_world_squad_state"):
		return {}
	var squad_state = source.call("get_world_squad_state")
	if not (squad_state is Dictionary):
		return {}
	var active_squads = squad_state.get("active_squads", {})
	if active_squads is Dictionary:
		return active_squads
	return {}


func _record_location(record: Dictionary) -> Vector3:
	var location = record.get("location", Vector3.ZERO)
	if location is Vector3:
		return location
	if location is Vector2:
		return Vector3(location.x, 0.0, location.y)
	return Vector3.ZERO


func _get_or_create_marker(squad_id: String, squads_layer: Control) -> Control:
	var marker = _squad_markers.get(squad_id)
	if marker is Control and is_instance_valid(marker):
		return marker
	var new_marker := Control.new()
	new_marker.name = _node_name_from_id(squad_id)
	new_marker.mouse_filter = Control.MOUSE_FILTER_PASS
	new_marker.size = Vector2(squad_marker_size, squad_marker_size)
	new_marker.set_meta(PROJECTED_SQUAD_MARKER_META, true)
	new_marker.set_meta("marker_kind", "squad")
	new_marker.set_meta("squad_id", squad_id)
	var dot := Panel.new()
	dot.name = "Dot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.size = new_marker.size
	new_marker.add_child(dot)
	squads_layer.add_child(new_marker)
	_squad_markers[squad_id] = new_marker
	return new_marker


func _update_marker(marker: Control, data: Dictionary) -> void:
	var map_position: Vector2 = data.get("map_position", Vector2.ZERO)
	marker.size = Vector2(squad_marker_size, squad_marker_size)
	marker.position = map_position - marker.size * 0.5
	marker.tooltip_text = _tooltip_text(data)
	marker.set_meta("squad_id", str(data.get("id", "")))
	marker.set_meta("faction_id", str(data.get("faction_id", "")))
	marker.set_meta("squad_state", str(data.get("state", "")))
	marker.set_meta("world_position", data.get("world_position", Vector3.ZERO))
	marker.set_meta("map_position", map_position)
	var dot := marker.get_node_or_null("Dot") as Panel
	if dot != null:
		dot.size = marker.size
		_apply_dot_style(dot, data.get("color", fallback_squad_color), str(data.get("state", "unknown")))


func _remove_stale_markers(seen_squad_ids: Dictionary) -> void:
	for squad_id in _squad_markers.keys():
		if seen_squad_ids.has(squad_id):
			continue
		var marker = _squad_markers[squad_id]
		if marker is Control and is_instance_valid(marker):
			var parent: Node = marker.get_parent()
			if parent != null:
				parent.remove_child(marker)
			marker.queue_free()
		_squad_markers.erase(squad_id)


func _apply_dot_style(dot: Panel, color_value, squad_state: String) -> void:
	var color := fallback_squad_color
	if color_value is Color:
		color = color_value
	color.a = _state_alpha(squad_state)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = _state_border_color(squad_state)
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	var radius := int(round(squad_marker_size * 0.5))
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	dot.add_theme_stylebox_override("panel", style)


func _faction_color(faction_id: String) -> Color:
	_build_faction_colors()
	var color = _faction_colors.get(faction_id, fallback_squad_color)
	if color is Color:
		return color
	return fallback_squad_color


func _build_faction_colors() -> void:
	if _faction_colors_built:
		return
	_faction_colors_built = true
	_faction_colors.clear()
	if world_definition == null:
		return
	var faction_definitions = world_definition.get("faction_definitions")
	if not (faction_definitions is Array):
		return
	for faction_definition in faction_definitions:
		if not (faction_definition is Resource):
			continue
		var faction_id := _resource_id(faction_definition)
		if faction_id.is_empty():
			continue
		var color_value = faction_definition.get("primary_color")
		if color_value is Color:
			_faction_colors[faction_id] = color_value


func _state_alpha(squad_state: String) -> float:
	match squad_state:
		"resolved":
			return 0.45
		"battle":
			return 1.0
		"travel":
			return 0.9
		_:
			return 0.82


func _state_border_color(squad_state: String) -> Color:
	match squad_state:
		"battle":
			return Color(1.0, 0.18, 0.12, 1.0)
		"travel":
			return Color(0.85, 0.92, 1.0, 1.0)
		"resolved":
			return Color(0.35, 0.35, 0.35, 1.0)
		_:
			return Color(0.04, 0.035, 0.03, 1.0)


func _tooltip_text(data: Dictionary) -> String:
	return "%s\nFaction: %s\nState: %s\nMembers: %d\nStrength: %.1f" % [
		str(data.get("id", "squad")),
		str(data.get("faction_id", "")),
		str(data.get("state", "unknown")),
		int(data.get("member_count", 0)),
		float(data.get("strength", 0.0)),
	]


func _resource_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_id"):
		return str(resource.call("get_id")).strip_edges()
	return ""


func _node_name_from_id(value: String) -> String:
	var clean_value := value.strip_edges().replace(":", "_")
	if clean_value.is_empty():
		return "SquadMarker"
	var result := ""
	for part in clean_value.split("_", false):
		if part.is_empty():
			continue
		result += part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return result if not result.is_empty() else "SquadMarker"
