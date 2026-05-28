extends Node

class_name WorldEventChoiceController

const WORLD_CONFLICT_EVENT_SCRIPT = preload("res://scripts/world_sim/world_conflict_event.gd")
const GECS_WORLD_CONTROLLER_SCRIPT := preload("res://scripts/controllers/gecs_world_controller.gd")
const PAUSE_REASON_WORLD_EVENT := "world_event_choice"

var root_scene: Node
var hud_layer: CanvasLayer
var faction_controller: Node
var world_time: Node
var events: Dictionary = {}
var _initialized := false
var _prompt_panel: PanelContainer
var _prompt_title: Label
var _prompt_description: Label
var _side_a_button: Button
var _side_b_button: Button
var _ignore_button: Button
var _active_prompt_event_id := ""


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	_try_initialize()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("world_event_choice_controller")
	_try_initialize()


func _process(delta: float) -> void:
	if not _initialized:
		return
	for event_id in events.keys():
		var event = events[event_id]
		if event == null or not is_instance_valid(event):
			events.erase(event_id)
			continue
		if event.completed or event.ignored:
			continue
		if event.committed:
			if get_tree() == null or not get_tree().paused:
				event.process_participation(delta, root_scene, faction_controller)
		elif not event.prompted and _active_prompt_event_id.is_empty() and event.is_player_in_radius(root_scene):
			_show_prompt(event)
	_sync_world_event_state_to_gecs()


func create_conflict_event(data: Dictionary):
	_try_initialize()
	var event = WORLD_CONFLICT_EVENT_SCRIPT.new()
	event.name = str(data.get("event_id", "WorldConflictEvent")).replace(":", "_")
	_ensure_event_root().add_child(event)
	event.configure(data)
	register_conflict_event(event)
	return event


func register_conflict_event(event) -> void:
	if event == null:
		return
	var id: String = event.event_id if not event.event_id.is_empty() else event.name
	event.event_id = id
	events[id] = event
	_sync_world_event_state_to_gecs()
	if _initialized and _active_prompt_event_id.is_empty() and not event.prompted and event.is_player_in_radius(root_scene):
		_show_prompt(event)


func debug_choose_side(event_id: String, faction_id: String) -> void:
	var event = events.get(event_id, null)
	if event == null:
		return
	event.prompted = true
	event.choose_side(faction_id, root_scene)
	_sync_world_event_state_to_gecs()
	if _active_prompt_event_id == event_id:
		_hide_prompt()


func debug_ignore_event(event_id: String) -> void:
	var event = events.get(event_id, null)
	if event == null:
		return
	event.ignore()
	_sync_world_event_state_to_gecs()
	if _active_prompt_event_id == event_id:
		_hide_prompt()


func debug_advance_event_participation(event_id: String, seconds: float) -> void:
	var event = events.get(event_id, null)
	if event == null:
		return
	event.participation_seconds += seconds
	if event.committed and not event.completed and event.participation_seconds >= event.participation_seconds_required:
		event.completed = true
		if faction_controller != null and faction_controller.has_method("apply_helped_faction_result"):
			faction_controller.call("apply_helped_faction_result", event.chosen_faction_id, event.opposed_faction_id, event.reputation_gain, event.favor_gain, event.opposed_reputation_loss)
	_sync_world_event_state_to_gecs()


func get_event(event_id: String):
	return events.get(event_id, null)


func get_event_count() -> int:
	return events.size()


func serialize_state() -> Dictionary:
	_sync_world_event_state_to_gecs()
	return _current_world_event_state()


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty():
		refresh_from_gecs_state()
		return
	_apply_world_event_state(state)
	_sync_world_event_state_to_gecs()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_world_event_state"):
		return
	var state: Dictionary = bridge.call("get_world_event_state")
	if not state.is_empty():
		_apply_world_event_state(state)


func sync_world_event_state() -> void:
	_sync_world_event_state_to_gecs()


func is_prompt_visible() -> bool:
	return _prompt_panel != null and _prompt_panel.visible


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	if hud_layer == null:
		hud_layer = root_scene.get_node_or_null("GameHUD") as CanvasLayer
	faction_controller = get_parent().get_node_or_null("FactionController")
	world_time = get_parent().get_node_or_null("WorldTimeController")
	if hud_layer == null or faction_controller == null:
		return
	_ensure_prompt_ui()
	refresh_from_gecs_state()
	_initialized = true


func _show_prompt(event) -> void:
	if event == null:
		return
	_ensure_prompt_ui()
	event.prompted = true
	_active_prompt_event_id = event.event_id
	_sync_world_event_state_to_gecs()
	_prompt_title.text = event.title
	_prompt_description.text = event.description if not event.description.is_empty() else "%s and %s are fighting nearby." % [event.side_a_label, event.side_b_label]
	_side_a_button.text = "Help %s" % event.side_a_label
	_side_b_button.text = "Help %s" % event.side_b_label
	_prompt_panel.visible = true
	if world_time != null and world_time.has_method("request_pause"):
		world_time.call("request_pause", PAUSE_REASON_WORLD_EVENT)


func _on_side_button_pressed(side_index: int) -> void:
	var event = events.get(_active_prompt_event_id, null)
	if event != null:
		var faction_id: String = event.side_a_faction_id if side_index == 0 else event.side_b_faction_id
		event.choose_side(faction_id, root_scene)
	_hide_prompt()


func _on_ignore_pressed() -> void:
	var event = events.get(_active_prompt_event_id, null)
	if event != null:
		event.ignore()
	_hide_prompt()


func _hide_prompt() -> void:
	if _prompt_panel != null:
		_prompt_panel.visible = false
	_active_prompt_event_id = ""
	if world_time != null and world_time.has_method("release_pause"):
		world_time.call("release_pause", PAUSE_REASON_WORLD_EVENT)
	_sync_world_event_state_to_gecs()


func _ensure_prompt_ui() -> void:
	if _prompt_panel != null and is_instance_valid(_prompt_panel):
		return
	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "WorldEventChoicePrompt"
	_prompt_panel.visible = false
	_prompt_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_prompt_panel.custom_minimum_size = Vector2(560.0, 220.0)
	_prompt_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_panel.offset_left = -280.0
	_prompt_panel.offset_top = -110.0
	_prompt_panel.offset_right = 280.0
	_prompt_panel.offset_bottom = 110.0
	hud_layer.add_child(_prompt_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_prompt_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_prompt_title = Label.new()
	_prompt_title.name = "Title"
	_prompt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_title.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66, 1.0))
	_prompt_title.add_theme_font_size_override("font_size", 18)
	column.add_child(_prompt_title)
	_prompt_description = Label.new()
	_prompt_description.name = "Description"
	_prompt_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_description.add_theme_color_override("font_color", Color(0.78, 0.72, 0.62, 1.0))
	column.add_child(_prompt_description)
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 10)
	column.add_child(button_row)
	_side_a_button = Button.new()
	_side_a_button.name = "HelpSideAButton"
	_side_a_button.custom_minimum_size = Vector2(150.0, 34.0)
	_side_a_button.pressed.connect(_on_side_button_pressed.bind(0))
	button_row.add_child(_side_a_button)
	_side_b_button = Button.new()
	_side_b_button.name = "HelpSideBButton"
	_side_b_button.custom_minimum_size = Vector2(150.0, 34.0)
	_side_b_button.pressed.connect(_on_side_button_pressed.bind(1))
	button_row.add_child(_side_b_button)
	_ignore_button = Button.new()
	_ignore_button.name = "IgnoreButton"
	_ignore_button.text = "Ignore"
	_ignore_button.custom_minimum_size = Vector2(96.0, 34.0)
	_ignore_button.pressed.connect(_on_ignore_pressed)
	button_row.add_child(_ignore_button)


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.07, 0.065, 0.98)
	style.border_color = Color(0.35, 0.29, 0.2, 1.0)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _current_world_event_state() -> Dictionary:
	var records := {}
	for event_id in events.keys():
		var event = events[event_id]
		if event != null and is_instance_valid(event) and event.has_method("to_record"):
			records[str(event_id)] = event.call("to_record")
	return {
		"state_id": "world_events",
		"active_prompt_event_id": _active_prompt_event_id,
		"events": records,
	}


func _apply_world_event_state(state: Dictionary) -> void:
	for event in events.values():
		if event != null and is_instance_valid(event):
			event.queue_free()
	events.clear()
	_hide_prompt()
	var records: Dictionary = state.get("events", {})
	for event_id in records.keys():
		var record = records[event_id]
		if not (record is Dictionary):
			continue
		var event = WORLD_CONFLICT_EVENT_SCRIPT.new()
		event.name = str((record as Dictionary).get("event_id", event_id)).replace(":", "_")
		_ensure_event_root().add_child(event)
		event.configure(record)
		register_conflict_event(event)
	_active_prompt_event_id = str(state.get("active_prompt_event_id", ""))
	if not _active_prompt_event_id.is_empty() and events.has(_active_prompt_event_id):
		var active_event = events[_active_prompt_event_id]
		if active_event != null and is_instance_valid(active_event) and not active_event.completed and not active_event.ignored:
			_show_prompt(active_event)


func _sync_world_event_state_to_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_world_event_state"):
		bridge.call("upsert_world_event_state", _current_world_event_state())


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	var existing := get_tree().get_first_node_in_group("gecs_world_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	if parent_node == null:
		return null
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	parent_node.add_child(bridge)
	bridge.call("initialize", root_scene if root_scene != null else parent_node)
	return bridge


func _ensure_event_root() -> Node3D:
	var event_root := root_scene.get_node_or_null("WorldEvents") as Node3D
	if event_root != null:
		return event_root
	event_root = Node3D.new()
	event_root.name = "WorldEvents"
	root_scene.add_child(event_root)
	return event_root
