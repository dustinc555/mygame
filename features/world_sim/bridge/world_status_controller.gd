extends Node

class_name WorldStatusController

const SERVICE_ID := &"world_status"

const FPS_REFRESH_INTERVAL := 0.25
const BRAIN_LOG_MAX_LINES := 200
const WORLD_MAP_OVERLAY_SCRIPT = preload("res://features/ui/projection/world_map_overlay.gd")
const LOD_RADIUS_OVERLAY_SCRIPT = preload("res://features/world/projection/lod_radius_overlay.gd")
const DEBUG_MENU_SCRIPT = preload("res://features/ui/projection/debug_menu.gd")
const WINDOW_BG := Color(0.12, 0.12, 0.14, 1.0)
const WINDOW_BORDER := Color(0.42, 0.38, 0.28, 1.0)
const TITLE_BAR_BG := Color(0.18, 0.17, 0.15, 1.0)
const TITLE_BAR_BORDER := Color(0.34, 0.30, 0.22, 1.0)

var root: Node
var _context: BootstrapContext
var hud_layer: CanvasLayer
var world_time: Node
var time_label: Label
var phase_label: Label
var fps_label: Label
var gecs_metrics_label: Label
var gecs_world: Node
var brain_log_panel: Panel
var brain_log_label: RichTextLabel
var brain_log_title_bar: PanelContainer
var world_map_overlay: Control
var lod_radius_overlay: Node3D
var debug_menu: Control
var escape_menu_panel: PanelContainer
var escape_menu_resume_button: Button
var escape_menu_debug_buttons: VBoxContainer
var pause_button: Button
var slow_button: Button
var normal_button: Button
var fast_button: Button
var very_fast_button: Button
var pause_overlay: Control
var paused_label: Label
var conversation_window: Control
var _initialized := false
var _fps_refresh_elapsed := 0.0
var _brain_log_lines: PackedStringArray = []
var _brain_log_connected := false
var _brain_log_dragging := false
var _brain_log_drag_offset := Vector2.ZERO
var _escape_menu_requested_pause := false


func initialize(context: BootstrapContext) -> void:
	root = context.root_scene
	hud_layer = context.hud_layer
	_context = context
	_try_initialize()


func _ready() -> void:
	add_to_group("world_status_controller")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_try_initialize()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE and not _is_text_input_focused():
		if _close_debug_menu_if_visible():
			get_viewport().set_input_as_handled()
			return
		_toggle_escape_menu()
		get_viewport().set_input_as_handled()
		return
	if not _initialized or world_time == null:
		return
	if key_event.keycode != KEY_SPACE:
		return
	if _is_text_input_focused():
		return
	if _is_conversation_visible():
		return
	world_time.toggle_manual_pause()
	get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _brain_log_dragging:
		return
	if event is InputEventMouseMotion:
		_move_brain_log_panel((event as InputEventMouseMotion).position - _brain_log_drag_offset)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed:
			_brain_log_dragging = false
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _initialized or fps_label == null:
		return
	_fps_refresh_elapsed += delta
	if _fps_refresh_elapsed < FPS_REFRESH_INTERVAL:
		return
	_fps_refresh_elapsed = 0.0
	_refresh_fps_label()
	_refresh_gecs_metrics_label()


func _try_initialize() -> void:
	if _initialized or root == null or hud_layer == null or not is_inside_tree():
		return
	world_time = _context.get_optional(WorldTimeController.SERVICE_ID) if _context != null else null
	if world_time == null:
		return
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	time_label = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/TimeLabel") as Label
	phase_label = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/PhaseLabel") as Label
	fps_label = hud_layer.get_node_or_null("FPSLabel") as Label
	gecs_metrics_label = hud_layer.get_node_or_null("GecsMetricsLabel") as Label
	if gecs_metrics_label != null:
		gecs_metrics_label.visible = _debug_enabled()
	gecs_world = _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null
	if _debug_enabled():
		_setup_brain_log_panel()
	_setup_world_map_overlay()
	_setup_debug_tools()
	pause_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/PauseButton") as Button
	slow_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/SlowButton") as Button
	normal_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/NormalButton") as Button
	fast_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/FastButton") as Button
	very_fast_button = hud_layer.get_node_or_null("WorldClockPanel/Margin/ClockRow/SpeedButtonRow/VeryFastButton") as Button
	pause_overlay = hud_layer.get_node_or_null("PauseOverlay") as Control
	if pause_overlay != null:
		pause_overlay.z_index = 30
	paused_label = hud_layer.get_node_or_null("PauseOverlay/PausedLabel") as Label
	conversation_window = hud_layer.get_node_or_null("ConversationWindow") as Control
	_setup_escape_menu()
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
	_refresh_gecs_metrics_label()


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


func _debug_enabled() -> bool:
	var debug_node := get_node_or_null("/root/GameDebug")
	if debug_node == null:
		return false
	if debug_node.has_method("is_debug_enabled"):
		return bool(debug_node.call("is_debug_enabled"))
	var value = debug_node.get("debug")
	return bool(value) if value != null else false


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
	if not _debug_enabled():
		fps_label.visible = false
		return
	fps_label.visible = true
	fps_label.text = "FPS: %d" % int(round(Engine.get_frames_per_second()))


func _refresh_gecs_metrics_label() -> void:
	if gecs_metrics_label == null:
		return
	if not _debug_enabled():
		gecs_metrics_label.visible = false
		return
	gecs_metrics_label.visible = true
	if gecs_world == null or not is_instance_valid(gecs_world):
		gecs_world = _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null
	_ensure_brain_log_connected()
	if gecs_world == null or not gecs_world.has_method("get_brain_metrics"):
		gecs_metrics_label.text = "World Sim: --"
		return
	var m: Dictionary = gecs_world.get_brain_metrics()
	# Honest, source-of-truth metrics. "GECS/frame" is THE perf number — the ms spent every
	# frame running the systems over realized actors. "In-world" = actors with live bodies
	# (cost GECS); "Off-screen" = cheap ledger records. If you leave a town and In-world /
	# GECS/frame don't drop, the LOD isn't actually offloading that actor.
	var live_bodies := 0
	if get_tree() != null:
		for body in get_tree().get_nodes_in_group("humanoid_character"):
			live_bodies += 1
	gecs_metrics_label.text = "World Sim   GECS/frame %.1f ms\nNPC records %d  (in-world %d  off-screen %d)\nLive bodies %d   squads %d" % [
		float(m.get("world_process_ms", 0.0)),
		int(m.get("population", 0)),
		int(m.get("realized", 0)),
		int(m.get("ledger", 0)),
		live_bodies,
		int(m.get("squads", 0)),
	]


func _setup_brain_log_panel() -> void:
	if brain_log_panel != null or hud_layer == null or not _debug_enabled():
		return
	brain_log_panel = Panel.new()
	brain_log_panel.name = "WorldBrainLogPanel"
	brain_log_panel.z_index = 35
	brain_log_panel.visible = false
	brain_log_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	brain_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brain_log_panel.add_theme_stylebox_override("panel", _make_window_style())
	brain_log_panel.anchor_left = 0.0
	brain_log_panel.anchor_top = 1.0
	brain_log_panel.anchor_right = 0.0
	brain_log_panel.anchor_bottom = 1.0
	brain_log_panel.offset_left = 8.0
	brain_log_panel.offset_top = -300.0
	brain_log_panel.offset_right = 560.0
	brain_log_panel.offset_bottom = -8.0
	brain_log_title_bar = PanelContainer.new()
	brain_log_title_bar.name = "TitleBar"
	brain_log_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	brain_log_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	brain_log_title_bar.add_theme_stylebox_override("panel", _make_title_bar_style())
	brain_log_title_bar.anchor_right = 1.0
	brain_log_title_bar.offset_left = 8.0
	brain_log_title_bar.offset_top = 8.0
	brain_log_title_bar.offset_right = -8.0
	brain_log_title_bar.offset_bottom = 38.0
	brain_log_title_bar.gui_input.connect(_on_brain_log_title_bar_gui_input)
	brain_log_panel.add_child(brain_log_title_bar)
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 10)
	title_margin.add_theme_constant_override("margin_top", 4)
	title_margin.add_theme_constant_override("margin_right", 10)
	title_margin.add_theme_constant_override("margin_bottom", 4)
	brain_log_title_bar.add_child(title_margin)
	var title := Label.new()
	title.text = "GECS Log"
	title.add_theme_font_size_override("font_size", 14)
	title_margin.add_child(title)
	brain_log_label = RichTextLabel.new()
	brain_log_label.bbcode_enabled = true
	brain_log_label.scroll_following = true
	brain_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brain_log_label.anchor_right = 1.0
	brain_log_label.anchor_bottom = 1.0
	brain_log_label.offset_left = 8.0
	brain_log_label.offset_top = 44.0
	brain_log_label.offset_right = -8.0
	brain_log_label.offset_bottom = -8.0
	brain_log_label.text = ""
	brain_log_panel.add_child(brain_log_label)
	hud_layer.add_child(brain_log_panel)


func _on_brain_log_title_bar_gui_input(event: InputEvent) -> void:
	if brain_log_panel == null:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		_brain_log_dragging = mouse_event.pressed
		if _brain_log_dragging:
			_brain_log_drag_offset = get_viewport().get_mouse_position() - brain_log_panel.global_position
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _brain_log_dragging:
		_move_brain_log_panel(get_viewport().get_mouse_position() - _brain_log_drag_offset)
		get_viewport().set_input_as_handled()


func _move_brain_log_panel(target_position: Vector2) -> void:
	if brain_log_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := brain_log_panel.size
	target_position.x = clampf(target_position.x, 0.0, maxf(0.0, viewport_size.x - panel_size.x))
	target_position.y = clampf(target_position.y, 0.0, maxf(0.0, viewport_size.y - panel_size.y))
	brain_log_panel.global_position = target_position


func _ensure_brain_log_connected() -> void:
	if _brain_log_connected or gecs_world == null:
		return
	if not gecs_world.has_signal("world_event_logged"):
		return
	gecs_world.connect("world_event_logged", _on_world_event_logged)
	_brain_log_connected = true
	if gecs_world.has_method("get_world_event_log"):
		for entry in gecs_world.get_world_event_log():
			_append_brain_line(entry)


func _on_world_event_logged(entry: Dictionary) -> void:
	_append_brain_line(entry)


func _append_brain_line(entry: Dictionary) -> void:
	var line := "[color=#66ccff]%s[/color] [color=#99ff99][%s][/color] %s" % [
		str(entry.get("time", "")),
		str(entry.get("category", "world")),
		str(entry.get("message", "")),
	]
	_brain_log_lines.append(line)
	if _brain_log_lines.size() > BRAIN_LOG_MAX_LINES:
		_brain_log_lines = _brain_log_lines.slice(_brain_log_lines.size() - BRAIN_LOG_MAX_LINES)
	if brain_log_label != null:
		brain_log_label.text = "\n".join(_brain_log_lines)


func set_brain_log_visible(value: bool) -> void:
	if not _debug_enabled():
		return
	if brain_log_panel == null:
		_setup_brain_log_panel()
	if brain_log_panel != null:
		brain_log_panel.visible = value


func is_brain_log_visible() -> bool:
	return brain_log_panel != null and brain_log_panel.visible


func _setup_world_map_overlay() -> void:
	if world_map_overlay != null or hud_layer == null:
		return
	world_map_overlay = WORLD_MAP_OVERLAY_SCRIPT.new()
	world_map_overlay.name = "WorldMapOverlay"
	world_map_overlay.z_index = 10
	hud_layer.add_child(world_map_overlay)


func _setup_debug_tools() -> void:
	if not _debug_enabled():
		return
	if lod_radius_overlay == null and root != null:
		lod_radius_overlay = LOD_RADIUS_OVERLAY_SCRIPT.new()
		lod_radius_overlay.name = "LodRadiusOverlay"
		root.add_child(lod_radius_overlay)
	if debug_menu == null and hud_layer != null:
		debug_menu = DEBUG_MENU_SCRIPT.new()
		debug_menu.name = "DebugMenu"
		debug_menu.z_index = 40
		hud_layer.add_child(debug_menu)


func _setup_escape_menu() -> void:
	if pause_overlay == null or escape_menu_panel != null:
		return
	escape_menu_panel = PanelContainer.new()
	escape_menu_panel.name = "EscapeMenu"
	escape_menu_panel.visible = false
	escape_menu_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	escape_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	escape_menu_panel.add_theme_stylebox_override("panel", _make_window_style())
	escape_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	escape_menu_panel.offset_left = -170.0
	escape_menu_panel.offset_top = -96.0
	escape_menu_panel.offset_right = 170.0
	escape_menu_panel.offset_bottom = 96.0
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	escape_menu_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title_bar := PanelContainer.new()
	title_bar.add_theme_stylebox_override("panel", _make_title_bar_style())
	column.add_child(title_bar)
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 12)
	title_margin.add_theme_constant_override("margin_top", 5)
	title_margin.add_theme_constant_override("margin_right", 12)
	title_margin.add_theme_constant_override("margin_bottom", 5)
	title_bar.add_child(title_margin)
	var title := Label.new()
	title.text = "Menu"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_margin.add_child(title)
	escape_menu_resume_button = Button.new()
	escape_menu_resume_button.text = "Resume"
	escape_menu_resume_button.focus_mode = Control.FOCUS_NONE
	escape_menu_resume_button.pressed.connect(_on_escape_menu_resume_pressed)
	column.add_child(escape_menu_resume_button)
	escape_menu_debug_buttons = VBoxContainer.new()
	escape_menu_debug_buttons.add_theme_constant_override("separation", 6)
	column.add_child(escape_menu_debug_buttons)
	pause_overlay.add_child(escape_menu_panel)


## One button per debug panel — opening the menu never floods the screen;
## each panel toggles individually.
func _refresh_escape_debug_buttons() -> void:
	if escape_menu_debug_buttons == null:
		return
	for child in escape_menu_debug_buttons.get_children():
		child.free()
	if not _debug_enabled():
		return
	if debug_menu == null:
		_setup_debug_tools()
	if debug_menu == null or not debug_menu.has_method("get_window_titles"):
		return
	for title in debug_menu.call("get_window_titles"):
		var button := Button.new()
		button.text = "Debug - %s" % str(title).replace(" Debug", "")
		button.toggle_mode = true
		button.button_pressed = bool(debug_menu.call("is_window_open", title))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_escape_debug_window_pressed.bind(str(title)))
		escape_menu_debug_buttons.add_child(button)


func _on_escape_debug_window_pressed(title: String) -> void:
	if debug_menu != null and debug_menu.has_method("toggle_window"):
		debug_menu.call("toggle_window", title)


func _toggle_escape_menu() -> void:
	if escape_menu_panel != null and escape_menu_panel.visible:
		_hide_escape_menu(true)
	else:
		_show_escape_menu()


func _show_escape_menu() -> void:
	if escape_menu_panel == null:
		_setup_escape_menu()
	if escape_menu_panel == null:
		return
	_escape_menu_requested_pause = world_time != null and not bool(world_time.is_manual_paused())
	if _escape_menu_requested_pause and world_time.has_method("request_manual_pause"):
		world_time.request_manual_pause()
	_refresh_escape_debug_buttons()
	escape_menu_panel.visible = true
	if pause_overlay != null:
		pause_overlay.visible = true
	if paused_label != null:
		paused_label.visible = false


func _hide_escape_menu(release_requested_pause: bool) -> void:
	if escape_menu_panel != null:
		escape_menu_panel.visible = false
	if release_requested_pause and _escape_menu_requested_pause and world_time != null and world_time.has_method("release_manual_pause"):
		world_time.release_manual_pause()
	_escape_menu_requested_pause = false
	_refresh_buttons()


func _on_escape_menu_resume_pressed() -> void:
	_escape_menu_requested_pause = false
	if escape_menu_panel != null:
		escape_menu_panel.visible = false
	if paused_label != null:
		paused_label.visible = false
	if world_time != null and world_time.has_method("release_manual_pause"):
		world_time.release_manual_pause()
	_refresh_buttons()


	# Resume the game while the debug menu is open — it's a non-modal overlay, so you can
	# move, command the party, and watch the LOD ring / overlays update live. (Only lift
	# the pause this menu itself requested; respect a manual pause the player set.)
	if _escape_menu_requested_pause and world_time != null and world_time.has_method("release_manual_pause"):
		world_time.release_manual_pause()
	_escape_menu_requested_pause = false
	if pause_overlay != null:
		pause_overlay.visible = false
	if paused_label != null:
		paused_label.visible = false
	_refresh_buttons()


func _close_debug_menu_if_visible() -> bool:
	if debug_menu == null or not bool(debug_menu.get("visible")):
		return false
	if debug_menu.has_method("close_menu"):
		debug_menu.call("close_menu")
	else:
		debug_menu.visible = false
	_refresh_buttons()
	return true


func _make_window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = WINDOW_BG
	style.border_color = WINDOW_BORDER
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _make_title_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = TITLE_BAR_BG
	style.border_color = TITLE_BAR_BORDER
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


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
		pause_overlay.visible = manual_paused or (escape_menu_panel != null and escape_menu_panel.visible)
	if paused_label != null:
		paused_label.visible = manual_paused and not (escape_menu_panel != null and escape_menu_panel.visible) and not (debug_menu != null and debug_menu.visible)
	if not manual_paused and escape_menu_panel != null:
		escape_menu_panel.visible = false
		_escape_menu_requested_pause = false


func _set_speed_button_pressed(button: Button, index: int, manual_paused: bool) -> void:
	if button == null:
		return
	button.set_pressed_no_signal(not manual_paused and world_time.get_speed_index() == index)


func _is_conversation_visible() -> bool:
	return conversation_window != null and conversation_window.visible
