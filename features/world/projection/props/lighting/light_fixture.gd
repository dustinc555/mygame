extends Node3D

class_name LightFixture

## A placed light source (wall torch, lantern, candle) that follows world
## time: lit through the night window, dark through the day. Wrapper scenes
## pair a vendor mesh with an authored Light3D child; the furnisher places
## them like any other furnishing, so every furnished interior gets night
## lighting for free.
##
## Lights default shadowless with distance fade (authored in the wrapper
## scene) — interiors get several fixtures each, and shadowed omnis are the
## expensive path. Turn shadows on per fixture only where it visibly matters.

## Lit from on_hour through the night until off_hour (window wraps midnight).
@export_range(0, 23, 1) var on_hour := 18
@export_range(0, 23, 1) var off_hour := 7
## Always lit (cellars, jail corridors) — ignores world time.
@export var always_on := false
@export var light_path: NodePath = ^"Light"

var _light: Light3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group("light_fixture")
	_light = get_node_or_null(light_path) as Light3D
	var time_controller := BootstrapContext.service(WorldTimeController.SERVICE_ID)
	if time_controller is WorldTimeController:
		(time_controller as WorldTimeController).hour_changed.connect(_on_hour_changed)
		_apply_hour((time_controller as WorldTimeController).get_hour())
	else:
		# No time authority (test scene): stay lit so interiors are visible.
		_set_lit(true)


func _on_hour_changed(_absolute_hour: int, _day_index: int, hour: int) -> void:
	_apply_hour(hour)


func _apply_hour(hour: int) -> void:
	_set_lit(always_on or _is_lit_hour(hour))


func _is_lit_hour(hour: int) -> bool:
	if on_hour == off_hour:
		return true
	if on_hour < off_hour:
		return hour >= on_hour and hour < off_hour
	return hour >= on_hour or hour < off_hour


func _set_lit(lit: bool) -> void:
	if _light != null:
		_light.visible = lit
