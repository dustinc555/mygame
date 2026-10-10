extends Control
## Presentation only: the lock controller owns earned progress. This ornament
## shares the ordinary work timer's placement/lifetime; it has no work clock.
const METAL := Color(0.64, 0.58, 0.43)
const LIT_PIN := Color(0.96, 0.78, 0.36)
const DARK_PIN := Color(0.30, 0.29, 0.25)
const SHADOW := Color(0.055, 0.05, 0.04, 0.94)

var completed_pins := 0
var pin_count := 3
var pulse := 0.0:
	set(value):
		pulse = value
		queue_redraw()
var _pulse_tween: Tween

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func update_progress(active: bool, ratio: float, required_passes: int) -> void:
	var count := maxi(1, required_passes)
	var earned := clampi(int(floor(clampf(ratio, 0.0, 1.0) * count + 0.00001)), 0, count)
	var changed := count != pin_count or earned != completed_pins
	var passed := active and visible and count == pin_count and earned > completed_pins
	if changed or not active:
		if _pulse_tween != null and _pulse_tween.is_valid():
			_pulse_tween.kill()
		pulse = 0.0
		pin_count = count
		completed_pins = earned
		if passed:
			pulse = 1.0
			_pulse_tween = create_tween()
			_pulse_tween.tween_property(self, "pulse", 0.0, 0.26)
		queue_redraw()
	visible = active
	# Extra authored passes add pin rows, never another progress bar.
	size = Vector2(maxf(36.0, mini(pin_count, 5) * 7.0 + 12.0), 34.0 + (ceili(pin_count / 5.0) - 1) * 9.0)

func _draw() -> void:
	var center := size.x * 0.5
	# Open-backed bow and cut-corner brass lock body, outlined against the world.
	draw_arc(Vector2(center, 12), 8, PI, TAU, 16, SHADOW, 6, true)
	draw_arc(Vector2(center, 12), 8, PI, TAU, 16, METAL, 2, true)
	for x in [center - 8, center + 8]:
		draw_line(Vector2(x, 11), Vector2(x, 17), SHADOW, 6, true)
		draw_line(Vector2(x, 11), Vector2(x, 17), METAL, 2, true)
	var outline := PackedVector2Array([Vector2(5, 14), Vector2(size.x - 5, 14),
		Vector2(size.x - 2, 17), Vector2(size.x - 2, size.y - 5),
		Vector2(size.x - 5, size.y - 2), Vector2(5, size.y - 2),
		Vector2(2, size.y - 5), Vector2(2, 17), Vector2(5, 14)])
	draw_colored_polygon(outline, SHADOW)
	draw_polyline(outline, METAL, 1.5, true)
	for index in range(pin_count):
		var column := index % 5
		var row := floori(index / 5.0)
		var columns := mini(5, pin_count - row * 5)
		var x := center + (column - (columns - 1) * 0.5) * 7.0
		var set_pin := index < completed_pins
		var y := 23.0 + row * 9.0 - (2.0 if set_pin else 0.0)
		var color := LIT_PIN if set_pin else DARK_PIN
		if set_pin and index == completed_pins - 1:
			color = color.lerp(Color.WHITE, pulse * 0.85)
			y += pulse * 2.0
		draw_line(Vector2(x, y - 3), Vector2(x, y + 3), color, 3, true)
		draw_line(Vector2(x - 2, y - 3), Vector2(x + 2, y - 3), color, 2, true)
