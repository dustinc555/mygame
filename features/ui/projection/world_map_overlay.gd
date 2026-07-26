extends Control

class_name WorldMapOverlay

## Full-screen fixed 2D world map (top-down X-Z). Toggle M. Hover markers for details.
## Right-click inside the map sends the current selection to that world-space point.

const REFRESH_INTERVAL := 0.3
const HOVER_RADIUS := 12.0
@export var world_bounds: Rect2 = Rect2(Vector2(-560.0, -430.0), Vector2(990.0, 790.0))
const GRID_STEP_METERS := 100.0

var pixels_per_meter := 1.0
var _markers: Array[Dictionary] = []
var _hovered: Dictionary = {}
var _view_center := world_bounds.position + world_bounds.size * 0.5
var _refresh_elapsed := 0.0
var _font: Font
var _interaction_controller: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	_compute_fixed_transform()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_M and not _is_text_focused():
		visible = not visible
		if visible:
			_rebuild_markers()
			queue_redraw()
		get_viewport().set_input_as_handled()
		return


func _gui_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	if not _map_rect().has_point(mouse_event.position):
		return
	_issue_move_order(mouse_event.position)
	accept_event()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed >= REFRESH_INTERVAL:
		_refresh_elapsed = 0.0
		_rebuild_markers()
	var mouse := get_local_mouse_position()
	var best: Dictionary = {}
	var best_distance := HOVER_RADIUS
	for marker in _markers:
		var distance := _world_to_screen(marker["world"]).distance_to(mouse)
		if distance <= best_distance:
			best_distance = distance
			best = marker
	_hovered = best
	queue_redraw()


func _rebuild_markers() -> void:
	_markers.clear()
	_compute_fixed_transform()
	var tree := get_tree()
	if tree == null:
		return
	for town in tree.get_nodes_in_group("settlement_town"):
		if not (town is Node3D):
			continue
		var town_name := _node_display_name(town)
		_markers.append({
			"world": _flatten((town as Node3D).global_position),
			"color": Color(0.45, 0.78, 1.0),
			"label": town_name,
			"detail": "Town: %s" % town_name,
			"kind": "town",
			"radius": 6.0,
		})
	for member in tree.get_nodes_in_group("party_member"):
		if not (member is Node3D):
			continue
		_markers.append({
			"world": _flatten((member as Node3D).global_position),
			"color": Color(0.4, 1.0, 0.45),
			"label": "",
			"detail": "Party: %s" % _node_display_name(member),
			"kind": "party",
			"radius": 4.0,
		})
	var gecs := tree.get_first_node_in_group("gecs_world_controller")
	if gecs != null and gecs.has_method("get_world_sim_squads"):
		for squad in gecs.get_world_sim_squads():
			_markers.append({
				"world": _flatten(squad.get("position", Vector3.ZERO)),
				"color": _squad_color(squad),
				"label": _squad_label(squad),
				"detail": _squad_detail(squad),
				"kind": "squad",
				"radius": 5.0,
			})


func _compute_fixed_transform() -> void:
	var rect := _map_rect()
	_view_center = world_bounds.position + world_bounds.size * 0.5
	pixels_per_meter = minf(rect.size.x / world_bounds.size.x, rect.size.y / world_bounds.size.y)


func _squad_color(squad: Dictionary) -> Color:
	match str(squad.get("phase", "")):
		"demand":
			return Color(1.0, 0.82, 0.3)
		"fight":
			return Color(1.0, 0.3, 0.25)
		"aftermath":
			return Color(0.8, 0.55, 1.0)
		_:
			return Color(1.0, 0.52, 0.32)


func _squad_label(squad: Dictionary) -> String:
	var faction := str(squad.get("faction_id", ""))
	var count := int(squad.get("member_count", 0))
	return "%s (%d)" % [faction, count] if not faction.is_empty() else str(squad.get("squad_id", ""))


func _squad_detail(squad: Dictionary) -> String:
	var phase := str(squad.get("phase", ""))
	var phase_line := "phase %s" % phase if not phase.is_empty() else "objective %s" % str(squad.get("objective", ""))
	return "%s squad — %d strong\n%s\ntarget %s\nfaction %s" % [
		str(squad.get("owner_kind", "")),
		int(squad.get("member_count", 0)),
		phase_line,
		str(squad.get("target_settlement_id", "")),
		str(squad.get("faction_id", "")),
	]


func _draw() -> void:
	if not visible:
		return
	_compute_fixed_transform()
	var rect := _map_rect()
	draw_rect(Rect2(Vector2.ZERO, _viewport_size()), Color(0.04, 0.05, 0.08, 0.86))
	draw_rect(rect, Color(0.08, 0.1, 0.14, 1.0))
	_draw_grid(rect)
	draw_rect(rect, Color(0.3, 0.5, 0.7, 0.6), false, 2.0)
	_draw_lod_ring()
	for marker in _markers:
		var screen := _world_to_screen(marker["world"])
		var clamped := Vector2(clampf(screen.x, rect.position.x + 4.0, rect.end.x - 4.0), clampf(screen.y, rect.position.y + 4.0, rect.end.y - 4.0))
		var off_edge := clamped.distance_to(screen) > 1.0
		draw_circle(clamped, float(marker.get("radius", 5.0)), marker["color"])
		if str(marker.get("kind", "")) == "party":
			draw_arc(clamped, float(marker.get("radius", 5.0)) + 5.0, 0.0, TAU, 24, Color(0.4, 1.0, 0.45, 0.8), 1.5)
		if off_edge:
			draw_arc(clamped, float(marker.get("radius", 5.0)) + 2.0, 0.0, TAU, 12, Color(1, 1, 1, 0.5), 1.0)
		elif _font != null and str(marker.get("label", "")) != "":
			draw_string(_font, clamped + Vector2(9.0, 4.0), str(marker.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, marker["color"])
	_draw_chrome(rect)
	if not _hovered.is_empty():
		_draw_hover()


func _draw_grid(rect: Rect2) -> void:
	var grid_color := Color(0.16, 0.2, 0.26, 1.0)
	var min_x: float = floorf(world_bounds.position.x / GRID_STEP_METERS) * GRID_STEP_METERS
	var max_x: float = world_bounds.end.x
	var x: float = min_x
	while x <= max_x:
		var a := _world_to_screen(Vector2(x, world_bounds.position.y))
		var b := _world_to_screen(Vector2(x, world_bounds.end.y))
		draw_line(Vector2(a.x, rect.position.y), Vector2(b.x, rect.end.y), grid_color, 1.0)
		x += GRID_STEP_METERS
	var min_z: float = floorf(world_bounds.position.y / GRID_STEP_METERS) * GRID_STEP_METERS
	var max_z: float = world_bounds.end.y
	var z: float = min_z
	while z <= max_z:
		var a := _world_to_screen(Vector2(world_bounds.position.x, z))
		var b := _world_to_screen(Vector2(world_bounds.end.x, z))
		draw_line(Vector2(rect.position.x, a.y), Vector2(rect.end.x, b.y), grid_color, 1.0)
		z += GRID_STEP_METERS


func _draw_chrome(rect: Rect2) -> void:
	if _font == null:
		return
	draw_string(_font, Vector2(rect.position.x, rect.position.y - 10.0), "World Map   (M close · right-click move)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.82, 0.9, 1.0))
	# Scale bar sized to the current fit.
	var bar_meters := _scale_bar_meters()
	var bar_px := bar_meters * pixels_per_meter
	var bar_y := rect.end.y - 16.0
	var bar_x := rect.position.x + 12.0
	draw_line(Vector2(bar_x, bar_y), Vector2(bar_x + bar_px, bar_y), Color(0.9, 0.9, 0.9), 2.0)
	draw_string(_font, Vector2(bar_x, bar_y - 5.0), "%dm" % int(bar_meters), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.9, 0.9))
	# Legend.
	var legend := [["you", Color(0.4, 1.0, 0.45)], ["town", Color(0.45, 0.78, 1.0)], ["squad", Color(1.0, 0.52, 0.32)], ["fight", Color(1.0, 0.3, 0.25)]]
	if _debug_lod_visible():
		legend.append(["LOD ring", Color(1.0, 0.85, 0.2)])
	var lx := rect.end.x - 96.0
	var ly := rect.position.y + 14.0
	for entry in legend:
		draw_circle(Vector2(lx, ly - 4.0), 5.0, entry[1])
		draw_string(_font, Vector2(lx + 10.0, ly), str(entry[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85))
		ly += 18.0


## A round-ish scale bar length that stays a sensible pixel width at the current zoom.
func _scale_bar_meters() -> float:
	var target_px := 120.0
	var raw := target_px / maxf(pixels_per_meter, 0.0001)
	for step in [25.0, 50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0]:
		if raw <= step:
			return step
	return 5000.0


func _draw_hover() -> void:
	if _font == null:
		return
	var mouse := get_local_mouse_position()
	var lines := str(_hovered.get("detail", "")).split("\n")
	var text_width := 0.0
	for line in lines:
		text_width = maxf(text_width, _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	var box := Rect2(mouse + Vector2(12.0, 12.0), Vector2(text_width + 16.0, lines.size() * 16.0 + 12.0))
	draw_rect(box, Color(0.0, 0.0, 0.0, 0.88))
	draw_rect(box, Color(0.4, 0.7, 1.0, 0.6), false, 1.0)
	var y := box.position.y + 17.0
	for line in lines:
		draw_string(_font, Vector2(box.position.x + 8.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 1.0, 1.0))
		y += 16.0


## Draw every active realization anchor, matching the 3D terrain rings.
func _draw_lod_ring() -> void:
	if not _debug_lod_visible():
		return
	var radius_px := _lod_radius() * pixels_per_meter
	if radius_px <= 1.0:
		return
	var tree := get_tree()
	var controller := tree.get_first_node_in_group("population_realization_controller") if tree != null else null
	if controller == null or not controller.has_method("get_realization_anchor_positions"):
		return
	for value in controller.call("get_realization_anchor_positions"):
		if not (value is Vector3):
			continue
		var center := _world_to_screen(Vector2(value.x, value.z))
		draw_circle(center, radius_px, Color(0.18, 1.0, 0.32, 0.06))
		draw_arc(center, radius_px, 0.0, TAU, 64, Color(0.32, 1.0, 0.42, 0.9), 1.5)


func _lod_radius() -> float:
	var tree := get_tree()
	if tree == null:
		return 0.0
	var controller := tree.get_first_node_in_group("population_realization_controller")
	if controller != null and controller.get("near_player_radius") != null:
		return float(controller.get("near_player_radius"))
	return 55.0


func _viewport_size() -> Vector2:
	return get_viewport_rect().size


func _map_rect() -> Rect2:
	var size_vec := _viewport_size()
	return Rect2(40.0, 56.0, maxf(1.0, size_vec.x - 80.0), maxf(1.0, size_vec.y - 104.0))


func _world_to_screen(world: Vector2) -> Vector2:
	var rect := _map_rect()
	var center := rect.position + rect.size * 0.5
	return center + (world - _view_center) * pixels_per_meter


func _screen_to_world(screen_position: Vector2) -> Vector2:
	_compute_fixed_transform()
	var rect := _map_rect()
	var center := rect.position + rect.size * 0.5
	return (screen_position - center) / maxf(pixels_per_meter, 0.0001) + _view_center


func _issue_move_order(screen_position: Vector2) -> void:
	var controller := _get_interaction_controller()
	if controller == null or not controller.has_method("issue_move_command_at_world"):
		return
	var world := _screen_to_world(screen_position)
	world.x = clampf(world.x, world_bounds.position.x, world_bounds.end.x)
	world.y = clampf(world.y, world_bounds.position.y, world_bounds.end.y)
	controller.call("issue_move_command_at_world", Vector3(world.x, _move_order_reference_y(controller), world.y), true)


func _move_order_reference_y(controller: Node) -> float:
	var party_manager = controller.get("party_manager") if controller != null else null
	if party_manager != null:
		var selected = party_manager.get("selected_members")
		if selected is Array and not selected.is_empty() and selected[0] is Node3D:
			return (selected[0] as Node3D).global_position.y
	if get_tree() != null:
		for member in get_tree().get_nodes_in_group("party_member"):
			if member is Node3D:
				return (member as Node3D).global_position.y
	var camera := get_viewport().get_camera_3d()
	return camera.global_position.y if camera != null else 0.0


func _get_interaction_controller() -> Node:
	if _interaction_controller == null or not is_instance_valid(_interaction_controller):
		_interaction_controller = get_tree().get_first_node_in_group("world_interaction_controller") if get_tree() != null else null
	return _interaction_controller


func _debug_lod_visible() -> bool:
	var lod := get_tree().get_first_node_in_group("lod_radius_overlay") if get_tree() != null else null
	return lod != null and bool(lod.get("visible"))


func _flatten(world_position: Vector3) -> Vector2:
	return Vector2(world_position.x, world_position.z)


func _node_display_name(node: Node) -> String:
	var value = node.get("display_name")
	if value != null and not str(value).strip_edges().is_empty():
		return str(value)
	return node.name


func _is_text_focused() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var focus_owner := viewport.gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
