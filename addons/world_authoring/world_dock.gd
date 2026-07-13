@tool
extends PanelContainer

## Bottom-panel World editor for the world_authoring plugin. Session spawn
## options live here — settings the game applies when a fresh session boots
## from this world (a loaded save overrides them). First resident: start
## time, so a night playtest doesn't need an in-game time skip. Every edit
## writes the WorldRoot node's exported properties (undoable; saving the
## world scene persists them).

const TIME_PRESETS := [
	{"label": "Dawn", "hour": 6, "minute": 0},
	{"label": "Noon", "hour": 12, "minute": 0},
	{"label": "Dusk", "hour": 18, "minute": 30},
	{"label": "Midnight", "hour": 0, "minute": 0},
]

var _tools: RefCounted
var _world: Node
var _updating := false
var _placeholder: Label
var _content: VBoxContainer
var _title: Label
var _hour_spin: SpinBox
var _minute_spin: SpinBox


func setup(tools: RefCounted) -> void:
	_tools = tools
	custom_minimum_size = Vector2(0, 170)
	_placeholder = Label.new()
	_placeholder.text = "Select a WorldRoot to edit its session options here."
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_placeholder)
	_content = VBoxContainer.new()
	_content.visible = false
	_content.add_theme_constant_override("separation", 8)
	add_child(_content)
	_title = Label.new()
	_title.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	_content.add_child(_title)
	_content.add_child(_build_spawn_options())


func _build_spawn_options() -> Control:
	var box := VBoxContainer.new()
	var section := Label.new()
	section.text = "Spawn Options (fresh session start — saves override)"
	section.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	box.add_child(section)
	var time_row := HBoxContainer.new()
	var time_label := Label.new()
	time_label.text = "Start Time"
	time_label.custom_minimum_size = Vector2(120, 0)
	time_row.add_child(time_label)
	_hour_spin = SpinBox.new()
	_hour_spin.min_value = 0
	_hour_spin.max_value = 23
	_hour_spin.step = 1
	_hour_spin.suffix = "h"
	_hour_spin.value_changed.connect(func(value: float):
		if not _updating:
			_tools.set_world_property(_world, "start_hour", int(value)))
	time_row.add_child(_hour_spin)
	_minute_spin = SpinBox.new()
	_minute_spin.min_value = 0
	_minute_spin.max_value = 59
	_minute_spin.step = 5
	_minute_spin.suffix = "m"
	_minute_spin.value_changed.connect(func(value: float):
		if not _updating:
			_tools.set_world_property(_world, "start_minute", int(value)))
	time_row.add_child(_minute_spin)
	box.add_child(time_row)
	var preset_row := HBoxContainer.new()
	for preset in TIME_PRESETS:
		var button := Button.new()
		button.text = "%s %02d:%02d" % [preset["label"], preset["hour"], preset["minute"]]
		button.pressed.connect(func():
			_tools.set_world_start_time(_world, int(preset["hour"]), int(preset["minute"]))
			refresh())
		preset_row.add_child(button)
	box.add_child(preset_row)
	return box


func set_world(world: Node) -> void:
	_world = world if world != null and is_instance_valid(world) else null
	_rebuild.call_deferred()


func refresh() -> void:
	_rebuild.call_deferred()


func _rebuild() -> void:
	if _placeholder == null:
		return
	if _world != null and not is_instance_valid(_world):
		_world = null
	_placeholder.visible = _world == null
	_content.visible = _world != null
	if _world == null:
		return
	_updating = true
	_title.text = "World: %s" % str(_world.call("get_world_id"))
	_hour_spin.value = int(_world.get("start_hour"))
	_minute_spin.value = int(_world.get("start_minute"))
	_updating = false
