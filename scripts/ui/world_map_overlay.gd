extends CanvasLayer

class_name WorldMapOverlay

const WORLD_MAP_PROJECTION_SCRIPT := preload("res://scripts/ui/world_map_projection.gd")

@export var start_open := false
@export var toggle_keycode := KEY_M
@export var world_bounds := Rect2(Vector2(-500.0, -500.0), Vector2(1000.0, 1000.0))

@onready var map_root: Control = $MapRoot
@onready var map_area: Control = $MapRoot/MapPanel/Margin/MainColumn/MapArea
@onready var towns_layer: Control = $MapRoot/MapPanel/Margin/MainColumn/MapArea/TownsLayer
@onready var nests_layer: Control = $MapRoot/MapPanel/Margin/MainColumn/MapArea/NestsLayer
@onready var squads_layer: Control = $MapRoot/MapPanel/Margin/MainColumn/MapArea/SquadsLayer
@onready var buttons_layer: Control = $MapRoot/MapPanel/Margin/MainColumn/ButtonsLayer
@onready var logs_layer: Control = $MapRoot/MapPanel/Margin/MainColumn/LogsLayer/LogMargin


func _ready() -> void:
	add_to_group("world_map_overlay")
	process_mode = Node.PROCESS_MODE_ALWAYS
	map_root.visible = start_open


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or key_event.keycode != toggle_keycode:
		return
	if _is_text_input_focused():
		return
	toggle_map()
	get_viewport().set_input_as_handled()


func open_map() -> void:
	map_root.visible = true


func close_map() -> void:
	map_root.visible = false


func toggle_map() -> void:
	map_root.visible = not map_root.visible


func is_map_open() -> bool:
	return map_root.visible


func get_map_area() -> Control:
	return map_area


func get_towns_layer() -> Control:
	return towns_layer


func get_nests_layer() -> Control:
	return nests_layer


func get_squads_layer() -> Control:
	return squads_layer


func get_buttons_layer() -> Control:
	return buttons_layer


func get_logs_layer() -> Control:
	return logs_layer


func get_map_rect() -> Rect2:
	return Rect2(Vector2.ZERO, map_area.size)


func get_projection_world_bounds() -> Rect2:
	return world_bounds


func world_to_map_position(world_position: Vector3) -> Vector2:
	return WORLD_MAP_PROJECTION_SCRIPT.world_to_map(world_position, world_bounds, get_map_rect())


func map_to_world_position(map_position: Vector2, y := 0.0) -> Vector3:
	return WORLD_MAP_PROJECTION_SCRIPT.map_to_world(map_position, world_bounds, get_map_rect(), y)


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
