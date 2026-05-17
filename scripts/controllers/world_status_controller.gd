extends Node

class_name WorldStatusController

var root: Node
var hud_layer: CanvasLayer
var world_time: Node
var world_simulation: Node
var time_label: Label
var phase_label: Label
var stats_label: Label
var pause_button: Button
var slow_button: Button
var normal_button: Button
var fast_button: Button
var very_fast_button: Button
var pause_overlay: Control
var conversation_window: Control
var _initialized := false


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root = target_root
	hud_layer = target_hud
	_try_initialize()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_try_initialize()


func _unhandled_input(event: InputEvent) -> void:
	if not _initialized or world_time == null:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_SPACE:
		return
	if _is_conversation_visible():
		return
	world_time.toggle_manual_pause()
	get_viewport().set_input_as_handled()


func _try_initialize() -> void:
	if _initialized or root == null or hud_layer == null or not is_inside_tree():
		return
	world_time = get_parent().get_node_or_null("WorldTimeController")
	if world_time == null:
		return
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	world_simulation = get_parent().get_node_or_null("WorldSimulationController")
	time_label = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/TimeLabel") as Label
	phase_label = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/PhaseLabel") as Label
	stats_label = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/StatsLabel") as Label
	pause_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/SpeedButtonRow/PauseButton") as Button
	slow_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/SpeedButtonRow/SlowButton") as Button
	normal_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/SpeedButtonRow/NormalButton") as Button
	fast_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/SpeedButtonRow/FastButton") as Button
	very_fast_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/SpeedButtonRow/VeryFastButton") as Button
	pause_overlay = hud_layer.get_node_or_null("PauseOverlay") as Control
	conversation_window = hud_layer.get_node_or_null("ConversationWindow") as Control
	if time_label == null or phase_label == null or pause_button == null or slow_button == null or normal_button == null or fast_button == null or very_fast_button == null:
		return
	_setup_speed_buttons()
	world_time.time_changed.connect(_on_time_changed)
	world_time.speed_changed.connect(_on_speed_changed)
	if world_time.has_signal("pause_changed"):
		world_time.pause_changed.connect(_on_pause_changed)
	_initialized = true
	_refresh_labels()


func _setup_speed_buttons() -> void:
	_set_always_process_tree(pause_button.get_parent())
	_set_always_process_tree(pause_overlay)
	_configure_speed_button(pause_button, "Pause", _on_pause_button_pressed)
	_configure_speed_button(slow_button, "Slow", _on_speed_button_pressed.bind(0))
	_configure_speed_button(normal_button, "Normal", _on_speed_button_pressed.bind(1))
	_configure_speed_button(fast_button, "Fast", _on_speed_button_pressed.bind(2))
	_configure_speed_button(very_fast_button, "Very Fast", _on_speed_button_pressed.bind(3))


func _configure_speed_button(button: Button, tooltip: String, callable: Callable) -> void:
	button.toggle_mode = true
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callable)


func _set_always_process_tree(node: Node) -> void:
	if node == null:
		return
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	for child in node.get_children():
		_set_always_process_tree(child)


func _on_pause_button_pressed() -> void:
	if world_time == null or _is_conversation_visible():
		_refresh_buttons()
		return
	world_time.toggle_manual_pause()


func _on_speed_button_pressed(index: int) -> void:
	if world_time == null:
		return
	world_time.set_speed_index(index)
	if world_time.has_method("release_manual_pause"):
		world_time.release_manual_pause()


func _on_time_changed(_day_index: int, _weekday_name: String, _hour: int, _minute: int, _phase_name: String, _speed_label: String) -> void:
	_refresh_labels()


func _on_speed_changed(_speed_index: int, _speed_label: String, _speed_scale: float) -> void:
	_refresh_labels()


func _on_pause_changed(_manual_paused: bool, _world_paused: bool) -> void:
	_refresh_labels()


func _refresh_labels() -> void:
	if world_time == null or time_label == null or phase_label == null:
		return
	time_label.text = world_time.format_time()
	phase_label.text = "%s  %s" % [world_time.get_phase_name(), world_time.get_status_speed_label()]
	if stats_label != null:
		if world_simulation != null and world_simulation.has_method("get_summary_text"):
			stats_label.text = world_simulation.get_summary_text()
		else:
			stats_label.text = "World: Stable"
	_refresh_buttons()


func _refresh_buttons() -> void:
	if world_time == null or pause_button == null:
		return
	var manual_paused := bool(world_time.is_manual_paused())
	pause_button.set_pressed_no_signal(manual_paused)
	_set_speed_button_pressed(slow_button, 0, manual_paused)
	_set_speed_button_pressed(normal_button, 1, manual_paused)
	_set_speed_button_pressed(fast_button, 2, manual_paused)
	_set_speed_button_pressed(very_fast_button, 3, manual_paused)
	if pause_overlay != null:
		pause_overlay.visible = manual_paused


func _set_speed_button_pressed(button: Button, index: int, manual_paused: bool) -> void:
	if button == null:
		return
	button.set_pressed_no_signal(not manual_paused and world_time.get_speed_index() == index)


func _is_conversation_visible() -> bool:
	return conversation_window != null and conversation_window.visible
