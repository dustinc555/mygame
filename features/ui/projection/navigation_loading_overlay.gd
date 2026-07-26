extends Node

class_name NavigationLoadingOverlay

## Holds the game in a LOADING state until the first usable navmesh of the
## session is live. Without it the player spawns into an unwalkable world
## with the clock ticking. The gate pauses the tree (which freezes the
## WorldTimeController time authority and all actors) and shows a themed
## compact loading indicator over the paused world.
##
## Other controller-owned loading work may reuse the same pause owner through
## set_loading_request().

const SERVICE_ID := &"navigation_loading_overlay"

const NAVIGATION_SERVICE := &"world_navigation"
const WORLD_TIME_SERVICE := &"world_time"
const LOADING_PAUSE_REASON := "loading"
const MIN_VISIBLE_SECONDS := 0.35

const PANEL_BG := Color(0.115, 0.105, 0.09, 0.88)
const PANEL_BORDER := Color(0.42, 0.38, 0.28, 1.0)
const TEXT_COLOR := Color(0.86, 0.84, 0.78, 1.0)
const SPINNER_COLOR := Color(0.71, 0.58, 0.32, 1.0)

var _navigation: Node
var _world_time: Node
var _layer: CanvasLayer
var _title_label: Label
var _spinner_dots: Array[ColorRect] = []
var _elapsed := 0.0
var _gated := false
var _idle_frames := 0
var _requests: Dictionary = {}
var _visible_elapsed := 0.0
var _loading_pause_requested := false


func initialize(context: BootstrapContext) -> void:
	_navigation = context.get_optional(NAVIGATION_SERVICE)
	_world_time = context.require(WORLD_TIME_SERVICE)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# STARTUP ONLY: the whole world bakes once behind this gate; after release
	# the game never shows LOADING again (dynamic patches are instant and
	# non-blocking).
	set_process(true)


func _exit_tree() -> void:
	if _loading_pause_requested and _world_time != null and is_instance_valid(_world_time):
		_world_time.call("release_pause", LOADING_PAUSE_REASON)
	_loading_pause_requested = false


func set_loading_request(owner_id: String, pending: bool) -> void:
	if owner_id.is_empty():
		return
	if pending:
		_requests[owner_id] = true
	else:
		_requests.erase(owner_id)
	set_process(true)


func is_loading_gate_active(owner_id := "") -> bool:
	return _gated and (owner_id.is_empty() or _requests.has(owner_id))


func _engage_gate() -> void:
	if _gated:
		return
	_build_veil()
	_gated = true
	_elapsed = 0.0
	_visible_elapsed = 0.0
	_loading_pause_requested = bool(_world_time.call("request_pause", LOADING_PAUSE_REASON))


func _release_gate() -> void:
	if not _gated:
		return
	_gated = false
	if _loading_pause_requested:
		_world_time.call("release_pause", LOADING_PAUSE_REASON)
	_loading_pause_requested = false
	if _layer != null:
		_layer.queue_free()
		_layer = null


func _process(delta: float) -> void:
	var navigation_pending := int(_navigation.call("gate_tiles_pending")) if _navigation != null and is_instance_valid(_navigation) and _navigation.has_method("gate_tiles_pending") else 0
	if _gated:
		_visible_elapsed += delta
	var requested := navigation_pending > 0 or not _requests.is_empty()
	if requested:
		if not _gated:
			_engage_gate()
	elif _gated and _visible_elapsed >= MIN_VISIBLE_SECONDS:
		_release_gate()
		return
	if not _gated:
		_idle_frames += 1
		if _idle_frames > 300 and _requests.is_empty():
			set_process(false)
		return
	_idle_frames = 0
	if _layer == null:
		return
	_elapsed += delta
	var active_dot := int(_elapsed * 10.0) % maxi(_spinner_dots.size(), 1)
	for index in range(_spinner_dots.size()):
		_spinner_dots[index].modulate.a = 1.0 if index == active_dot else 0.2 + 0.6 * float((index - active_dot + _spinner_dots.size()) % _spinner_dots.size()) / float(_spinner_dots.size())


func _build_veil() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var input_blocker := Control.new()
	input_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(input_blocker)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(190.0, 0.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	_title_label = Label.new()
	_title_label.text = "Loading"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", TEXT_COLOR)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)
	var spinner := Control.new()
	spinner.custom_minimum_size = Vector2(36.0, 36.0)
	spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(spinner)
	_spinner_dots.clear()
	for index in range(8):
		var dot := ColorRect.new()
		dot.color = SPINNER_COLOR
		dot.size = Vector2(5.0, 5.0)
		var angle := TAU * float(index) / 8.0
		dot.position = Vector2(15.5, 15.5) + Vector2(cos(angle), sin(angle)) * 12.0
		spinner.add_child(dot)
		_spinner_dots.append(dot)


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style
