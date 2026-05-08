extends Node

class_name WorldStatusController

var root: Node
var hud_layer: CanvasLayer
var world_time: Node
var time_label: Label
var phase_label: Label
var stats_label: Label
var speed_option: OptionButton
var _initialized := false


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root = target_root
	hud_layer = target_hud
	_try_initialize()


func _ready() -> void:
	_try_initialize()


func _try_initialize() -> void:
	if _initialized or root == null or hud_layer == null or not is_inside_tree():
		return
	world_time = get_parent().get_node_or_null("WorldTimeController")
	if world_time == null:
		return
	time_label = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/TimeLabel") as Label
	phase_label = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/PhaseLabel") as Label
	stats_label = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/StatsLabel") as Label
	speed_option = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/WorldStatusPanel/Margin/StatusColumn/SpeedOption") as OptionButton
	if time_label == null or phase_label == null or speed_option == null:
		return
	_populate_speed_options()
	world_time.time_changed.connect(_on_time_changed)
	world_time.speed_changed.connect(_on_speed_changed)
	_initialized = true
	_refresh_labels()


func _populate_speed_options() -> void:
	speed_option.clear()
	for label in world_time.get_speed_options():
		speed_option.add_item(label)
	speed_option.select(world_time.get_speed_index())
	if not speed_option.item_selected.is_connected(_on_speed_option_selected):
		speed_option.item_selected.connect(_on_speed_option_selected)


func _on_speed_option_selected(index: int) -> void:
	world_time.set_speed_index(index)


func _on_time_changed(_day_index: int, _weekday_name: String, _hour: int, _minute: int, _phase_name: String, _speed_label: String) -> void:
	_refresh_labels()


func _on_speed_changed(speed_index: int, _speed_label: String, _speed_scale: float) -> void:
	if speed_option != null and speed_option.selected != speed_index:
		speed_option.select(speed_index)
	_refresh_labels()


func _refresh_labels() -> void:
	if world_time == null or time_label == null or phase_label == null:
		return
	time_label.text = world_time.format_time()
	phase_label.text = "%s  %s" % [world_time.get_phase_name(), world_time.get_speed_label()]
	if stats_label != null:
		stats_label.text = "World: Stable"
