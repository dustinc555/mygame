extends Node

class_name WorldStatusController

const FPS_REFRESH_INTERVAL := 0.25
# #76 Humanoid Projection can register visible projected actors into these groups.
const PROJECTED_ACTOR_GROUPS := [
	"projected_humanoid_actor",
	"humanoid_projection_actor",
	"realized_humanoid_actor",
	"character_authoring_actor",
]

@export var fixed_tick_runner_path := NodePath("../WorldMapCombatFixedTickRunner")

var root: Node
var hud_layer: CanvasLayer
var world_time: Node
var fixed_tick_runner: Node
var time_label: Label
var phase_label: Label
var fps_label: Label
var pause_button: Button
var slow_button: Button
var normal_button: Button
var fast_button: Button
var very_fast_button: Button
var pause_overlay: Control
var conversation_window: Control
var _initialized := false
var _fps_refresh_elapsed := 0.0


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root = target_root
	hud_layer = target_hud
	_try_initialize()


func _ready() -> void:
	add_to_group("world_status_controller")
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
	if _is_text_input_focused():
		return
	if _is_conversation_visible():
		return
	world_time.toggle_manual_pause()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _initialized or fps_label == null:
		return
	_fps_refresh_elapsed += delta
	if _fps_refresh_elapsed < FPS_REFRESH_INTERVAL:
		return
	_fps_refresh_elapsed = 0.0
	_refresh_fps_label()


func _try_initialize() -> void:
	if _initialized or root == null or hud_layer == null or not is_inside_tree():
		return
	world_time = get_parent().get_node_or_null("WorldTimeController")
	if world_time == null:
		return
	fixed_tick_runner = _resolve_fixed_tick_runner()
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	time_label = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/TimeLabel") as Label
	phase_label = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/PhaseLabel") as Label
	fps_label = hud_layer.get_node_or_null("FPSLabel") as Label
	pause_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/PauseButton") as Button
	slow_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/SlowButton") as Button
	normal_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/NormalButton") as Button
	fast_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/FastButton") as Button
	very_fast_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/VeryFastButton") as Button
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
	_refresh_fps_label()


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


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


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
	_refresh_buttons()


func _refresh_fps_label() -> void:
	if fps_label == null:
		return
	var gecs_label := "--"
	var average_tick_time_ms := _get_average_tick_time_ms()
	if average_tick_time_ms >= 0.0:
		gecs_label = "%.1f ms" % average_tick_time_ms
	var actor_label := "--"
	var actor_count := _get_visible_projected_actor_count()
	if actor_count >= 0:
		actor_label = str(actor_count)
	fps_label.text = "FPS: %d\nGECS: %s\nActors: %s" % [
		int(round(Engine.get_frames_per_second())),
		gecs_label,
		actor_label,
	]


func _get_average_tick_time_ms() -> float:
	var runner := _get_fixed_tick_runner()
	if runner != null and runner.has_method("get_metrics"):
		var runner_metrics = runner.call("get_metrics")
		if runner_metrics is Dictionary and runner_metrics.has("average_tick_time_ms"):
			return float(runner_metrics.get("average_tick_time_ms", 0.0))
	return -1.0


func _get_fixed_tick_runner() -> Node:
	if fixed_tick_runner != null and is_instance_valid(fixed_tick_runner):
		return fixed_tick_runner
	fixed_tick_runner = _resolve_fixed_tick_runner()
	return fixed_tick_runner


func _resolve_fixed_tick_runner() -> Node:
	if fixed_tick_runner_path == NodePath(""):
		return null
	return get_node_or_null(fixed_tick_runner_path)


func _get_visible_projected_actor_count() -> int:
	var tree := get_tree()
	if tree == null:
		return -1
	var seen := {}
	var found_group_node := false
	var count := 0
	for group_name in PROJECTED_ACTOR_GROUPS:
		for node in tree.get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node):
				continue
			found_group_node = true
			var instance_id := node.get_instance_id()
			if seen.has(instance_id):
				continue
			seen[instance_id] = true
			if _is_visible_projected_actor(node):
				count += 1
	return count if found_group_node else -1


func _is_visible_projected_actor(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	if node is Node3D:
		return (node as Node3D).is_visible_in_tree()
	if node is CanvasItem:
		return (node as CanvasItem).is_visible_in_tree()
	return true


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
