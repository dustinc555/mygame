extends Node

class_name NavigationLoadingOverlay

## Holds the game in a LOADING state until the first usable navmesh of the
## session is live. Without it the player spawns into an unwalkable world
## with the clock ticking. The gate pauses the tree (which freezes the
## WorldTimeController time authority and all actors) and shows a themed
## loading veil; bake progress is not queryable from Recast, so the bar is
## deliberately indeterminate (a sweeping segment, never a fake percentage).
##
## Only the initial bake gates play: later rebakes keep the previous navmesh
## live, so the game never blocks on them.

const SERVICE_ID := &"navigation_loading_overlay"

const NAVIGATION_SERVICE := &"world_navigation"

const BACKDROP_COLOR := Color(0.055, 0.048, 0.04, 1.0)
const PANEL_BG := Color(0.115, 0.105, 0.09, 1.0)
const PANEL_BORDER := Color(0.42, 0.38, 0.28, 1.0)
const TEXT_COLOR := Color(0.86, 0.84, 0.78, 1.0)
const TEXT_DIM := Color(0.58, 0.55, 0.47, 1.0)
const BAR_TRACK := Color(0.16, 0.145, 0.12, 1.0)
const BAR_SWEEP := Color(0.71, 0.58, 0.32, 1.0)

const VIGNETTE_SHADER := "
shader_type canvas_item;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.35, 0.95, d) * 0.85);
}"

var _navigation: Node
var _layer: CanvasLayer
var _title_label: Label
var _detail_label: Label
var _bar_track: Control
var _bar_sweep: ColorRect
var _elapsed := 0.0
var _gated := false
var _idle_frames := 0


func initialize(context: BootstrapContext) -> void:
	_navigation = context.get_optional(NAVIGATION_SERVICE)
	if _navigation == null:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	# STARTUP ONLY: the whole world bakes once behind this gate; after release
	# the game never shows LOADING again (dynamic patches are instant and
	# non-blocking).
	set_process(true)


func _engage_gate() -> void:
	if _gated:
		return
	_build_veil()
	_gated = true
	_elapsed = 0.0
	get_tree().paused = true


func _release_gate() -> void:
	if not _gated:
		return
	_gated = false
	get_tree().paused = false
	if _layer != null:
		_layer.queue_free()
		_layer = null
	# One-shot: never gate again this session.
	set_process(false)


func _process(delta: float) -> void:
	if _navigation == null or not is_instance_valid(_navigation):
		set_process(false)
		return
	var pending := int(_navigation.call("gate_tiles_pending")) if _navigation.has_method("gate_tiles_pending") else 0
	if pending > 0 and not _gated:
		_engage_gate()
	elif pending == 0 and _gated:
		_release_gate()
		return
	if not _gated:
		# Dormant scenes never gate; stop polling after a settling window.
		_idle_frames += 1
		if _idle_frames > 300:
			set_process(false)
		return
	if _layer == null:
		return
	_elapsed += delta
	var done := int(_navigation.call("initial_tiles_done")) if _navigation.has_method("initial_tiles_done") else 0
	var total := int(_navigation.call("initial_tiles_total")) if _navigation.has_method("initial_tiles_total") else 0
	if _detail_label != null:
		if total > 0:
			_detail_label.text = "Charting safe ground  ·  %d / %d" % [done, total]
		else:
			_detail_label.text = "Charting safe ground  ·  %.0fs" % _elapsed
	if _bar_sweep == null or _bar_track == null:
		return
	var track_width := _bar_track.size.x
	if total > 0:
		# Real progress: critical tiles baked out of tiles needed.
		_bar_sweep.position = Vector2.ZERO
		_bar_sweep.size = Vector2(track_width * (float(done) / float(total)), _bar_track.size.y)
	else:
		# Indeterminate sweep (FULL_SCENE mode has one unmeasurable bake).
		var sweep_width := track_width * 0.28
		_bar_sweep.size = Vector2(sweep_width, _bar_track.size.y)
		var travel := track_width - sweep_width
		var t := pingpong(_elapsed * 0.55, 1.0)
		_bar_sweep.position = Vector2(travel * ease(t, -2.0), 0.0)


func _build_veil() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP_COLOR
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(backdrop)
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	vignette.material = shader_material
	_layer.add_child(vignette)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420.0, 0.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_title_label = Label.new()
	_title_label.text = "LOADING"
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", TEXT_COLOR)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title_label)
	var divider := ColorRect.new()
	divider.color = PANEL_BORDER
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	column.add_child(divider)
	_bar_track = Control.new()
	_bar_track.custom_minimum_size = Vector2(0.0, 8.0)
	_bar_track.clip_contents = true
	column.add_child(_bar_track)
	var track_bg := ColorRect.new()
	track_bg.color = BAR_TRACK
	track_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_track.add_child(track_bg)
	_bar_sweep = ColorRect.new()
	_bar_sweep.color = BAR_SWEEP
	_bar_track.add_child(_bar_sweep)
	_detail_label = Label.new()
	_detail_label.text = "Charting safe ground"
	_detail_label.add_theme_font_size_override("font_size", 14)
	_detail_label.add_theme_color_override("font_color", TEXT_DIM)
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_detail_label)


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
