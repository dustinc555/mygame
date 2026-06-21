extends Control

class_name DebugMenu

## Dev-only debug menu. WorldStatusController opens it from the Escape menu when the
## global GameDebug.debug flag is true.

var _lod_overlay: Node3D
var _lod_check: CheckButton
var _brain_log_check: CheckButton
var _radius_slider: HSlider
var _radius_label: Label

const WINDOW_BG := Color(0.12, 0.12, 0.14, 1.0)
const WINDOW_BORDER := Color(0.42, 0.38, 0.28, 1.0)
const TITLE_BAR_BG := Color(0.18, 0.17, 0.15, 1.0)
const TITLE_BAR_BORDER := Color(0.34, 0.30, 0.22, 1.0)
const TEXT_COLOR := Color(0.86, 0.84, 0.78, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if not _debug_enabled():
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.position = Vector2(12.0, 88.0)
	panel.custom_minimum_size = Vector2(340.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_window_style())
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	var title_bar := PanelContainer.new()
	title_bar.add_theme_stylebox_override("panel", _make_title_bar_style())
	vbox.add_child(title_bar)
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 12)
	title_margin.add_theme_constant_override("margin_top", 5)
	title_margin.add_theme_constant_override("margin_right", 12)
	title_margin.add_theme_constant_override("margin_bottom", 5)
	title_bar.add_child(title_margin)
	var title_row := HBoxContainer.new()
	title_margin.add_child(title_row)
	var title := Label.new()
	title.text = "Debug Information"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var title_close := Button.new()
	title_close.text = "X"
	title_close.focus_mode = Control.FOCUS_NONE
	title_close.pressed.connect(close_menu)
	title_row.add_child(title_close)
	_lod_check = CheckButton.new()
	_lod_check.text = "Show LOD radius"
	_lod_check.add_theme_color_override("font_color", TEXT_COLOR)
	_lod_check.toggled.connect(_on_lod_toggled)
	vbox.add_child(_lod_check)
	_brain_log_check = CheckButton.new()
	_brain_log_check.text = "Show world brain log"
	_brain_log_check.add_theme_color_override("font_color", TEXT_COLOR)
	_brain_log_check.toggled.connect(_on_brain_log_toggled)
	vbox.add_child(_brain_log_check)
	_radius_label = Label.new()
	_radius_label.add_theme_color_override("font_color", TEXT_COLOR)
	vbox.add_child(_radius_label)
	_radius_slider = HSlider.new()
	_radius_slider.min_value = 60.0
	_radius_slider.max_value = 1200.0
	_radius_slider.step = 10.0
	_radius_slider.custom_minimum_size = Vector2(300.0, 0.0)
	_radius_slider.value = _current_lod_radius()
	_radius_slider.value_changed.connect(_on_radius_changed)
	vbox.add_child(_radius_slider)
	_update_radius_label(_radius_slider.value)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close_menu)
	vbox.add_child(close_button)
	# LOD ring is on by default (dev tool); the checkbox + slider just adjust it.
	_lod_check.button_pressed = true
	call_deferred("_on_lod_toggled", true)
	# Open by default so dev info is always available without opening it each run.
	visible = true


func open_menu() -> void:
	if not _debug_enabled():
		return
	visible = true
	_sync_toggles()


func close_menu() -> void:
	visible = false


func toggle_menu() -> void:
	if visible:
		close_menu()
	else:
		open_menu()


func _on_lod_toggled(pressed: bool) -> void:
	_lod_overlay = _get_lod_overlay()
	if _lod_overlay != null:
		_lod_overlay.visible = pressed


func _on_brain_log_toggled(pressed: bool) -> void:
	var status := _get_world_status_controller()
	if status != null and status.has_method("set_brain_log_visible"):
		status.call("set_brain_log_visible", pressed)


func _on_radius_changed(value: float) -> void:
	var controller := _get_realization_controller()
	if controller != null:
		controller.set("near_player_radius", value)
		if controller.has_method("sync_population_realization_state"):
			controller.call("sync_population_realization_state")
	_update_radius_label(value)


func _update_radius_label(value: float) -> void:
	if _radius_label != null:
		_radius_label.text = "LOD radius: %dm" % int(value)


func _current_lod_radius() -> float:
	var controller := _get_realization_controller()
	if controller != null and controller.get("near_player_radius") != null:
		return float(controller.get("near_player_radius"))
	return 120.0


func _get_realization_controller() -> Node:
	return get_tree().get_first_node_in_group("population_realization_controller") if get_tree() != null else null


func _sync_toggles() -> void:
	if _lod_check != null:
		var lod := _get_lod_overlay()
		_lod_check.set_pressed_no_signal(lod != null and lod.visible)
	if _brain_log_check != null:
		var status := _get_world_status_controller()
		var shown := bool(status.call("is_brain_log_visible")) if status != null and status.has_method("is_brain_log_visible") else false
		_brain_log_check.set_pressed_no_signal(shown)
	if _radius_slider != null:
		_radius_slider.set_value_no_signal(_current_lod_radius())
		_update_radius_label(_radius_slider.value)


func _get_lod_overlay() -> Node3D:
	if _lod_overlay == null or not is_instance_valid(_lod_overlay):
		_lod_overlay = get_tree().get_first_node_in_group("lod_radius_overlay") as Node3D
	return _lod_overlay


func _get_world_status_controller() -> Node:
	return get_tree().get_first_node_in_group("world_status_controller") if get_tree() != null else null


func _debug_enabled() -> bool:
	var debug_node := get_node_or_null("/root/GameDebug")
	if debug_node == null:
		return false
	if debug_node.has_method("is_debug_enabled"):
		return bool(debug_node.call("is_debug_enabled"))
	var value = debug_node.get("debug")
	return bool(value) if value != null else false


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
