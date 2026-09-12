extends Control
## Separate ruler gutter: project body-plane heights without covering the viewport.
const METERS_PER_FOOT := 0.3048
const GUTTER_WIDTH := 76.0
var camera: Camera3D
var ground_y := 0.0
var upper_extent := 2.0
var _center := Vector3.ZERO

func _ready() -> void:
	custom_minimum_size.x = GUTTER_WIDTH
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)

static func meters_to_feet(meters: float) -> float:
	return meters / METERS_PER_FOOT

func configure(unequipped_bounds: AABB) -> void:
	ground_y = unequipped_bounds.position.y
	_center = unequipped_bounds.get_center()
	upper_extent = maxf(ceilf(unequipped_bounds.size.y + 0.25), 1.0)
	queue_redraw()

func project_height(meters: float) -> float:
	if not is_instance_valid(camera) or not camera.is_inside_tree(): return INF
	var point := Vector3(_center.x, ground_y + meters, _center.z)
	if camera.is_position_behind(point): return INF
	var viewport_height := camera.get_viewport().get_visible_rect().size.y
	return camera.unproject_position(point).y * size.y / maxf(viewport_height, 1.0)

func _draw() -> void:
	if not is_instance_valid(camera): return
	var font := ThemeDB.fallback_font
	var ink := Color("a6b3bc")
	var minor := Color("65717a")
	# Unit headers and ticks belong only to this reserved strip.
	draw_string(font, Vector2(10, 18), "m", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	draw_string(font, Vector2(51, 18), "ft", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	var first := clampf(project_height(upper_extent), 28.0, size.y - 8.0)
	var last := clampf(project_height(0), 28.0, size.y - 8.0)
	if is_finite(first) and is_finite(last):
		draw_line(Vector2(37, first), Vector2(37, last), minor)
		draw_line(Vector2(41, first), Vector2(41, last), minor)
	var previous_label := INF
	for tenth in range(int(upper_extent * 10) + 1):
		var y := project_height(tenth * 0.1)
		if not is_finite(y) or y < 30 or y > size.y - 8: continue
		var major := tenth % 5 == 0
		draw_line(Vector2(37, y), Vector2(29 if major else 33, y), ink if major else minor)
		if major and absf(y - previous_label) >= 18:
			draw_string(font, Vector2(0, y + 4), "%.1f" % (tenth * 0.1), HORIZONTAL_ALIGNMENT_RIGHT, 26, 12, ink)
			previous_label = y
	previous_label = INF
	for foot in range(int(floorf(meters_to_feet(upper_extent))) + 1):
		var y := project_height(foot * METERS_PER_FOOT)
		if not is_finite(y) or y < 30 or y > size.y - 8: continue
		draw_line(Vector2(41, y), Vector2(49, y), ink)
		if absf(y - previous_label) >= 18:
			draw_string(font, Vector2(52, y + 4), str(foot), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ink)
			previous_label = y
