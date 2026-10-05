extends Control

## North-up atlas UI. World data, persistent discovery and raster work belong
## to injected services; this view only owns navigation and presentation.
const MASK := preload("res://features/world_map/projection/map_discovery_mask.gd")
const TILE_SHADER := preload("res://features/world_map/projection/map_tile.gdshader")
const PAPER_SHADER := preload("res://features/world_map/projection/map_paper.gdshader")
const DEFAULT_SETTINGS := preload("res://features/world_map/resources/default_world_map_settings.tres")
const INK := Color("473b2c")
const FADED_INK := Color("857356")

class FeatureCanvas extends Control:
	var map_view: Control
	func _draw() -> void:
		map_view.draw_features(self)

var world_bounds := Rect2(-128, -128, 256, 256)
var pixels_per_meter := 1.0
var zoom := 1.0
var pan := Vector2.ZERO
var _view_center := Vector2.ZERO
var _settings: Resource = DEFAULT_SETTINGS
var _atlas: Node
var _exploration: Node
var _interaction: Node
var _terrain: Node
var _gecs: Node
var _canvas: Control
var _tiles: Control
var _features: FeatureCanvas
var _paper: ColorRect
var _footer: Label
var _toolbar: HBoxContainer
var _tile_nodes: Dictionary = {}
var _records: Array = []
var _party: Array = []
var _squads: Array[Dictionary] = []
var _font := SystemFont.new()
var _dragging := false
var _opened_once := false
var _elapsed := 0.0
var _last_size := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font.font_names = PackedStringArray(["Noto Serif", "DejaVu Serif", "serif"])
	_build_controls()
	resized.connect(_layout)
	_layout()
	visible = false

func configure(context: BootstrapContext) -> void:
	_atlas = context.get_optional(&"world_atlas")
	_exploration = context.get_optional(&"map_exploration")
	_interaction = context.get_optional(&"world_interaction")
	_terrain = context.get_optional(&"terrain_camera")
	_gecs = context.get_optional(GecsWorldController.SERVICE_ID)
	if is_instance_valid(_atlas):
		_settings = _atlas.settings
		_atlas.tile_ready.connect(_on_tile_ready)
		_atlas.bounds_changed.connect(_on_bounds_changed)
		_on_bounds_changed()
	if is_instance_valid(_exploration):
		_exploration.discovery_changed.connect(_on_discovery_changed)
		_exploration.knowledge_changed.connect(_rebuild_markers)
		_exploration.state_replaced.connect(_on_state_replaced)
	_paper.material.set_shader_parameter("paper_color", _settings.unknown_color)

func _build_controls() -> void:
	_canvas = Control.new()
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_paper = ColorRect.new()
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var paper_material := ShaderMaterial.new()
	paper_material.shader = PAPER_SHADER
	paper_material.set_shader_parameter("paper_color", _settings.unknown_color)
	_paper.material = paper_material
	_canvas.add_child(_paper)
	_tiles = Control.new()
	_tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_tiles)
	_features = FeatureCanvas.new()
	_features.map_view = self
	_features.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_features)
	_footer = Label.new()
	_footer.add_theme_color_override("font_color", Color("c7b594"))
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer)
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 8)
	add_child(_toolbar)
	_add_button("−", func(): _zoom_at(_canvas.position + _canvas.size * 0.5, 1.0 / 1.25))
	_add_button("+", func(): _zoom_at(_canvas.position + _canvas.size * 0.5, 1.25))
	_add_button("Fit world", fit_world)
	_add_button("Party", focus_party)
	_add_button("Close · M", close_map)

func _add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(42, 34)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color("e5d6b6"))
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("423b30") if state == "normal" else Color("5c4e38")
		style.border_color = Color("786747")
		style.set_border_width_all(1)
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	_toolbar.add_child(button)

func _layout() -> void:
	if _canvas == null:
		return
	var display_size := size
	if display_size.x < 100 or display_size.y < 100:
		display_size = Vector2(1152, 648)
	var narrow := display_size.x < 920
	var top := 130.0 if narrow else 100.0
	_canvas.position = Vector2(26, top)
	_canvas.size = Vector2(maxf(64, display_size.x - 52), maxf(64, display_size.y - top - 54))
	_toolbar.position = Vector2(maxf(28, display_size.x - _toolbar.get_combined_minimum_size().x - 28), 31)
	if narrow:
		_toolbar.position = Vector2(28, 86)
	_footer.position = Vector2(28, display_size.y - 36)
	if _last_size == Vector2.ZERO:
		pixels_per_meter = _fit_scale()
		_view_center = world_bounds.get_center()
	_last_size = display_size
	_refresh_view()

func open_map() -> void:
	visible = true
	if is_instance_valid(_exploration):
		_exploration.observe_party()
	if not _opened_once:
		focus_party()
		_opened_once = true
	else:
		_refresh_view()
	_rebuild_markers()

func close_map() -> void:
	visible = false
	_dragging = false
	if is_instance_valid(_atlas):
		_atlas.request_view(Rect2(), pixels_per_meter)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		if visible:
			close_map()
		else:
			open_map()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		close_map()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed:
		_dragging = false

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			_dragging = event.pressed and _map_rect().has_point(event.position)
		elif event.pressed and _map_rect().has_point(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(event.position, 1.25)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(event.position, 1.0 / 1.25)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_issue_move_order(event.position)
		accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			_view_center -= event.relative / pixels_per_meter
			_refresh_view()
		_update_footer(event.position)
		accept_event()

func _zoom_at(screen: Vector2, factor: float) -> void:
	var anchor := _screen_to_world(screen)
	pixels_per_meter = clampf(pixels_per_meter * factor, _fit_scale() * 0.65, maxf(_settings.max_pixels_per_meter, _fit_scale() * 2.0))
	_view_center += anchor - _screen_to_world(screen)
	_refresh_view()

func _issue_move_order(screen: Vector2) -> bool:
	var point := _screen_to_world(screen)
	if not world_bounds.has_point(point) or not is_instance_valid(_interaction):
		return false
	var target := Vector3(point.x, 0, point.y)
	var height: float = _terrain.get_terrain_height(target) if is_instance_valid(_terrain) else NAN
	if not is_finite(height):
		return false
	target.y = height
	return _interaction.issue_move_command_at_world(target, true)

func fit_world() -> void:
	_view_center = world_bounds.get_center()
	pixels_per_meter = _fit_scale()
	_refresh_view()

func focus_party() -> void:
	if is_instance_valid(_exploration) and not _exploration.party_markers.is_empty():
		_view_center = _exploration.party_markers[0]["world"]
		pixels_per_meter = clampf(_canvas.size.x / _settings.opening_width_meters, _fit_scale(), _settings.max_pixels_per_meter)
	else:
		fit_world()
	_refresh_view()

func _fit_scale() -> float:
	var canvas_size := _canvas.size if _canvas != null else Vector2(1100, 494)
	return maxf(0.000001, minf(canvas_size.x / maxf(1, world_bounds.size.x), canvas_size.y / maxf(1, world_bounds.size.y)) * 0.92)

func _map_rect() -> Rect2:
	return Rect2(_canvas.position, _canvas.size)

func _screen_to_world(screen: Vector2) -> Vector2:
	return _view_center + (screen - _map_rect().get_center()) / pixels_per_meter

func _world_to_screen(world: Vector2) -> Vector2:
	return _map_rect().get_center() + (world - _view_center) * pixels_per_meter

func _visible_world() -> Rect2:
	return Rect2(_screen_to_world(_canvas.position), _canvas.size / pixels_per_meter)

func _refresh_view() -> void:
	if _canvas == null or not is_inside_tree():
		return
	zoom = pixels_per_meter / _fit_scale()
	pan = (_view_center - world_bounds.get_center()) * pixels_per_meter
	if visible and is_instance_valid(_atlas):
		_sync_tiles(_atlas.request_view(_visible_world(), pixels_per_meter))
	_rebuild_markers()
	queue_redraw()
	_update_footer(get_local_mouse_position())

func _sync_tiles(descriptors: Array) -> void:
	var used: Dictionary = {}
	for descriptor in descriptors:
		var key: Vector3i = descriptor["key"]
		used[key] = true
		var tile: TextureRect = _tile_nodes.get(key)
		if tile == null:
			tile = TextureRect.new()
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var material := ShaderMaterial.new()
			material.shader = TILE_SHADER
			tile.material = material
			_tiles.add_child(tile)
			_tile_nodes[key] = tile
			_update_tile_mask(key, tile)
		var area: Rect2 = descriptor["rect"]
		# Adjacent quads share the same rounded endpoint. Fractional rectangle
		# sizes otherwise leave single-pixel parchment cracks at some zooms.
		var start := (_world_to_screen(area.position) - _canvas.position).round()
		var end := (_world_to_screen(area.end) - _canvas.position).round()
		tile.position = start
		tile.size = end - start
		tile.texture = descriptor["texture"]
		tile.visible = tile.texture != null
	for key in _tile_nodes.keys():
		if not used.has(key):
			_tile_nodes[key].queue_free()
			_tile_nodes.erase(key)

func _update_tile_mask(key: Vector3i, tile: TextureRect) -> void:
	var discovery: bool = _settings.discovery_enabled
	tile.material.set_shader_parameter("discovery_enabled", discovery)
	if discovery and is_instance_valid(_exploration):
		var image: Image = MASK.render(_exploration.state, _atlas.tile_rect(key), 128)
		tile.material.set_shader_parameter("discovery_mask", ImageTexture.create_from_image(image))

func _on_tile_ready(_key: Vector3i) -> void:
	if visible:
		_sync_tiles(_atlas.request_view(_visible_world(), pixels_per_meter))

func _on_bounds_changed() -> void:
	if _atlas.bounds.has_area():
		world_bounds = _atlas.bounds
	_refresh_view()

func _on_discovery_changed(_chunks: Array) -> void:
	for key in _tile_nodes:
		_update_tile_mask(key, _tile_nodes[key])
	_rebuild_markers()

func _on_state_replaced() -> void:
	_on_discovery_changed([])

func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		if is_instance_valid(_exploration):
			_party = _exploration.party_markers
		_refresh_observed_squads()
		_features.queue_redraw()

func _refresh_observed_squads() -> void:
	_squads.clear()
	if not is_instance_valid(_gecs) or not is_instance_valid(_exploration):
		return
	for squad: Dictionary in _gecs.get_world_sim_squads():
		var position: Vector3 = squad.get("position", Vector3.ZERO)
		var flat := Vector2(position.x, position.z)
		if _exploration.is_observed(flat):
			_squads.append({"world": flat, "label": "%s · %d" % [str(squad.get("faction_id", "Travelers")).capitalize(), int(squad.get("member_count", 0))]})

func _rebuild_markers() -> void:
	_records.clear()
	if is_instance_valid(_exploration) and _exploration.state != null:
		var candidates: Array = _exploration.state.known_features.values()
		if not _settings.discovery_enabled and is_instance_valid(_atlas):
			candidates = _atlas.source.all_features()
		var area := _visible_world().grow(256)
		for record in candidates:
			if area.has_point(record["world"]):
				_records.append(record)
		_party = _exploration.party_markers
	if _features != null:
		_features.queue_redraw()

func draw_features(canvas: Control) -> void:
	var occupied: Array[Rect2] = []
	for record in _records:
		var kind: String = record.get("kind", "")
		if kind == "road":
			var points := PackedVector2Array()
			for point in record.get("points", []):
				points.append(_world_to_screen(point) - _canvas.position)
			if points.size() > 1:
				canvas.draw_polyline(points, Color("d6bf8a"), 3.5, true)
				canvas.draw_polyline(points, Color("93724d"), 1.2, true)
		elif kind == "building" and pixels_per_meter >= 0.12:
			for polygon in record.get("polygons", []):
				var points := PackedVector2Array()
				for point in polygon:
					points.append(_world_to_screen(point) - _canvas.position)
				if points.size() >= 3:
					if Geometry2D.triangulate_polygon(points).is_empty():
						continue
					canvas.draw_colored_polygon(points, Color("806749"))
					points.append(points[0])
					canvas.draw_polyline(points, Color("554734"), 1.0, true)
	for record in _records:
		if record.get("kind") != "town":
			continue
		var p := _world_to_screen(record["world"]) - _canvas.position
		canvas.draw_circle(p, 6, Color("e1d1a8"))
		canvas.draw_arc(p, 6, 0, TAU, 24, INK, 1.5, true)
		canvas.draw_circle(p, 2.5, INK)
		_draw_label(canvas, p + Vector2(11, -10), record.get("label", ""), occupied)
	for squad in _squads:
		var p := _world_to_screen(squad["world"]) - _canvas.position
		canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0,-6), p + Vector2(6,0), p + Vector2(0,6), p + Vector2(-6,0)]), Color("95533e"))
		_draw_label(canvas, p + Vector2(10, 4), squad["label"], occupied)
	for marker in _party:
		var p := _world_to_screen(marker["world"]) - _canvas.position
		if not Rect2(Vector2.ZERO, _canvas.size).grow(-16).has_point(p):
			continue
		canvas.draw_circle(p, 10, Color("e7dab3"))
		canvas.draw_arc(p, 10, 0, TAU, 32, Color("695033"), 1.5, true)
		canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0,-7), p + Vector2(5,5), p + Vector2(0,2), p + Vector2(-5,5)]), Color("2d6667"))
		_draw_label(canvas, p + Vector2(14, 5), marker.get("label", "Party"), occupied)
	_draw_compass(canvas)
	_draw_scale(canvas)

func _draw_label(canvas: Control, baseline: Vector2, text: String, occupied: Array[Rect2]) -> void:
	var extent := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var box := Rect2(baseline - Vector2(0, extent.y), extent + Vector2(4, 5))
	for existing in occupied:
		if existing.intersects(box):
			return
	occupied.append(box)
	canvas.draw_string_outline(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color("dccba4"))
	canvas.draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)

func _draw_compass(canvas: Control) -> void:
	var p := Vector2(_canvas.size.x - 48, 62)
	canvas.draw_string(_font, p + Vector2(-6,-25), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0,-17), p + Vector2(5,12), p, p + Vector2(-5,12)]), FADED_INK)
	canvas.draw_line(p + Vector2(-14,0), p + Vector2(14,0), FADED_INK, 1, true)

func _draw_scale(canvas: Control) -> void:
	var desired := 120.0 / pixels_per_meter
	var magnitude := pow(10.0, floor(log(maxf(0.001, desired)) / log(10.0)))
	var distance: float = floor(desired / magnitude) * magnitude
	var width := distance * pixels_per_meter
	var p := Vector2(25, _canvas.size.y - 25)
	canvas.draw_line(p, p + Vector2(width, 0), INK, 2, true)
	canvas.draw_line(p + Vector2(0,-4), p + Vector2(0,4), INK, 1)
	canvas.draw_line(p + Vector2(width,-4), p + Vector2(width,4), INK, 1)
	var text := "%s km" % str(distance / 1000.0) if distance >= 1000 else "%s m" % str(distance)
	canvas.draw_string(ThemeDB.fallback_font, p + Vector2(0,-10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)

func _update_footer(cursor: Vector2) -> void:
	if _footer == null:
		return
	var location := ""
	if _map_rect().has_point(cursor) and is_instance_valid(_exploration) and _exploration.state != null:
		location = "   ·   Unexplored" if _settings.discovery_enabled and not _exploration.state.is_discovered(_screen_to_world(cursor)) else "   ·   Surveyed land"
	_footer.text = "Scroll to zoom   ·   Drag to pan   ·   Right-click to travel" + location

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("29271f"))
	if _canvas != null:
		draw_rect(_map_rect().grow(2), Color("8e7952"), false, 1)
		draw_line(Vector2(28, 80), Vector2(size.x - 28, 80), Color("64563f"), 1)
