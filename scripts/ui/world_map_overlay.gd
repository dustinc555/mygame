extends CanvasLayer

class_name WorldMapOverlay

@export var start_open := false
@export var toggle_keycode := KEY_M

@onready var map_root: Control = $MapRoot


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


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
