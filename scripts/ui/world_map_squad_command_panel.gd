extends Node

class_name WorldMapSquadCommandPanel

signal command_requested(command: Dictionary)

const MAX_LOG_LABELS := 10

@export var world_definition: Resource
@export var overlay_path: NodePath = NodePath("../WorldMapOverlay")
@export var squad_state_source_path: NodePath = NodePath("../DemoSimBootstrap")

var _overlay: Node
var _squad_state_source: Node
var _button_panel: PanelContainer
var _log_column: VBoxContainer
var _command_index := 0
var _rendered_sim_log_keys := {}
var _ui_log_entries: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("world_map_squad_command_panel")
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_mount_panel")


func _process(_delta: float) -> void:
	_sync_sim_command_log()


func append_log_entry(entry: Dictionary) -> void:
	_ui_log_entries.append(entry.duplicate(true))
	while _ui_log_entries.size() > MAX_LOG_LABELS:
		_ui_log_entries.pop_front()
	_render_logs()


func _mount_panel() -> void:
	var overlay := _get_overlay()
	if overlay == null:
		return
	_mount_buttons(overlay)
	_mount_logs(overlay)
	_sync_sim_command_log()


func _mount_buttons(overlay: Node) -> void:
	var buttons_layer := _get_buttons_layer(overlay)
	if buttons_layer == null:
		return
	if _button_panel != null and is_instance_valid(_button_panel):
		return
	_button_panel = PanelContainer.new()
	_button_panel.name = "SquadCommandPanel"
	_button_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_button_panel.add_theme_stylebox_override("panel", _panel_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	_button_panel.add_child(margin)
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	margin.add_child(row)
	var title := Label.new()
	title.text = "Squad Commands"
	title.custom_minimum_size = Vector2(110.0, 24.0)
	title.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66, 1.0))
	title.add_theme_font_size_override("font_size", 12)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var squad_ids := _squad_ids()
	var towns := _town_targets()
	var first_squad_id := squad_ids[0] if squad_ids.size() > 0 else ""
	var second_squad_id := squad_ids[1] if squad_ids.size() > 1 else ""
	var first_town: Dictionary = towns[0].duplicate(true) if towns.size() > 0 else {}
	var second_town: Dictionary = towns[1].duplicate(true) if towns.size() > 1 else {}
	var fight_squad_ids: Array[String] = []
	for index in range(min(2, squad_ids.size())):
		fight_squad_ids.append(squad_ids[index])
	var fight_location := _fight_location()
	row.add_child(_create_button(_send_squad_to_town_label(first_squad_id, first_town, "Send Squad A to Town 1"), _request_send_squad_to_town.bind(first_squad_id, first_town)))
	row.add_child(_create_button(_send_squad_to_town_label(second_squad_id, second_town, "Send Squad B to Town 2"), _request_send_squad_to_town.bind(second_squad_id, second_town)))
	row.add_child(_create_button("Send Both to Fight", _request_send_both_to_fight_location.bind(fight_squad_ids, fight_location)))
	row.add_child(_create_button("Force Encounter", _request_force_encounter.bind(fight_squad_ids, fight_location)))
	row.add_child(_create_button("Clear/Reset Demo Squads", _request_reset_demo_squads))
	buttons_layer.add_child(_button_panel)


func _mount_logs(overlay: Node) -> void:
	var logs_layer := _get_logs_layer(overlay)
	if logs_layer == null:
		return
	if _log_column != null and is_instance_valid(_log_column):
		return
	for child in logs_layer.get_children():
		if child.name == "LogPlaceholder":
			child.visible = false
	_log_column = VBoxContainer.new()
	_log_column.name = "SquadCommandLog"
	_log_column.add_theme_constant_override("separation", 2)
	logs_layer.add_child(_log_column)
	_render_logs()


func _create_button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 24.0)
	button.pressed.connect(handler)
	return button


func _request_send_squad_to_town(squad_id: String, town: Dictionary) -> void:
	if squad_id.is_empty() or town.is_empty():
		append_log_entry(_ui_log("error", "Missing squad or town for command"))
		return
	var town_id := str(town.get("id", "")).strip_edges()
	var town_name := str(town.get("display_name", "town")).strip_edges()
	_request_command({
		"action": "set_squad_objective",
		"squad_id": squad_id,
		"objective_id": "move_to_location",
		"target_id": town_id,
		"target_location": town.get("location", Vector3.ZERO),
		"squad_state": "commanded",
		"label": "Send %s to %s" % [squad_id, town_name if not town_name.is_empty() else "town"],
	})


func _request_send_both_to_fight_location(squad_ids: Array[String], target_location: Vector3) -> void:
	if squad_ids.size() < 2:
		append_log_entry(_ui_log("error", "Need two squads for fight command"))
		return
	_request_command({
		"action": "set_squads_objective",
		"squad_ids": squad_ids.slice(0, 2),
		"objective_id": "debug_fight_location",
		"target_id": "debug_fight_location",
		"target_location": target_location,
		"squad_state": "commanded",
		"label": "Send squads to debug fight location",
	})


func _request_force_encounter(squad_ids: Array[String], target_location: Vector3) -> void:
	if squad_ids.size() < 2:
		append_log_entry(_ui_log("error", "Need two squads for force encounter"))
		return
	_request_command({
		"action": "force_encounter",
		"squad_ids": squad_ids.slice(0, 2),
		"objective_id": "debug_force_encounter",
		"target_id": "debug_force_encounter",
		"target_location": target_location,
		"squad_state": "commanded",
		"debug_only": true,
		"label": "Debug-only force encounter placeholder",
	})


func _request_reset_demo_squads() -> void:
	_request_command({
		"action": "reset_demo_squads",
		"label": "Reset demo squad records",
	})


func _request_command(command: Dictionary) -> void:
	_command_index += 1
	var command_id := "map_cmd:%d:%03d" % [Time.get_ticks_msec(), _command_index]
	command["command_id"] = command_id
	command_requested.emit(command.duplicate(true))
	append_log_entry(_ui_log("issued", str(command.get("label", command.get("action", "command"))), command_id, str(command.get("action", ""))))


func _sync_sim_command_log() -> void:
	var source := _get_squad_state_source()
	if source == null or not source.has_method("get_world_squad_state"):
		return
	var squad_state = source.call("get_world_squad_state")
	if not (squad_state is Dictionary):
		return
	var command_log = squad_state.get("command_log", [])
	if not (command_log is Array):
		return
	var retained_log_keys := {}
	for entry in command_log:
		if not (entry is Dictionary):
			continue
		var key := "%s:%s:%s" % [str(entry.get("log_id", "")), str(entry.get("command_id", "")), str(entry.get("status", ""))]
		retained_log_keys[key] = true
		if _rendered_sim_log_keys.has(key):
			continue
		_rendered_sim_log_keys[key] = true
		append_log_entry(entry)
	_rendered_sim_log_keys = retained_log_keys


func _render_logs() -> void:
	if _log_column == null or not is_instance_valid(_log_column):
		return
	for child in _log_column.get_children():
		_log_column.remove_child(child)
		child.queue_free()
	for entry in _ui_log_entries:
		var label := Label.new()
		label.text = _log_text(entry)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", _log_color(str(entry.get("status", ""))))
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_log_column.add_child(label)


func _squad_ids() -> Array[String]:
	var result: Array[String] = []
	var active_squads := _active_squads()
	for squad_id in active_squads.keys():
		result.append(str(squad_id))
	result.sort()
	return result


func _send_squad_to_town_label(squad_id: String, town: Dictionary, fallback: String) -> String:
	if squad_id.is_empty() or town.is_empty():
		return fallback
	var town_name := str(town.get("display_name", "town")).strip_edges()
	return "Send %s to %s" % [squad_id, town_name if not town_name.is_empty() else "town"]


func _active_squads() -> Dictionary:
	var source := _get_squad_state_source()
	if source == null or not source.has_method("get_world_squad_state"):
		return {}
	var squad_state = source.call("get_world_squad_state")
	if not (squad_state is Dictionary):
		return {}
	var active_squads = squad_state.get("active_squads", {})
	return active_squads if active_squads is Dictionary else {}


func _town_targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world_definition == null:
		return result
	var placements = world_definition.get("settlement_placements")
	if not (placements is Array):
		return result
	for placement in placements:
		if not (placement is Resource):
			continue
		var settlement_definition := placement.get("settlement_definition") as Resource
		var placement_id := _resource_id(placement)
		result.append({
			"id": placement_id,
			"display_name": _settlement_display_name(settlement_definition, placement_id),
			"location": _placement_world_position(placement),
		})
	return result


func _fight_location() -> Vector3:
	var towns := _town_targets()
	if towns.size() >= 2:
		var first: Vector3 = towns[0].get("location", Vector3.ZERO)
		var second: Vector3 = towns[1].get("location", Vector3.ZERO)
		return first.lerp(second, 0.5)
	return Vector3.ZERO


func _get_overlay() -> Node:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	if overlay_path == NodePath():
		return null
	_overlay = get_node_or_null(overlay_path)
	return _overlay


func _get_squad_state_source() -> Node:
	if _squad_state_source != null and is_instance_valid(_squad_state_source):
		return _squad_state_source
	if squad_state_source_path == NodePath():
		return null
	_squad_state_source = get_node_or_null(squad_state_source_path)
	return _squad_state_source


func _get_buttons_layer(overlay: Node) -> Control:
	if overlay.has_method("get_buttons_layer"):
		return overlay.call("get_buttons_layer") as Control
	return null


func _get_logs_layer(overlay: Node) -> Control:
	if overlay.has_method("get_logs_layer"):
		return overlay.call("get_logs_layer") as Control
	return null


func _placement_world_position(placement: Resource) -> Vector3:
	var transform_value = placement.get("world_transform")
	if transform_value is Transform3D:
		var world_transform: Transform3D = transform_value
		return world_transform.origin
	var settlement_definition := placement.get("settlement_definition") as Resource
	if settlement_definition != null:
		var position_value = settlement_definition.get("world_position")
		if position_value is Vector3:
			return position_value
	return Vector3.ZERO


func _settlement_display_name(settlement_definition: Resource, fallback: String) -> String:
	var display_name := str(settlement_definition.get("display_name")).strip_edges() if settlement_definition != null else ""
	if not display_name.is_empty():
		return display_name
	return fallback.capitalize()


func _resource_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_id"):
		return str(resource.call("get_id")).strip_edges()
	return ""


func _ui_log(status: String, message: String, command_id := "", action := "") -> Dictionary:
	return {
		"status": status,
		"command_id": command_id,
		"action": action,
		"message": message,
	}


func _log_text(entry: Dictionary) -> String:
	var status := str(entry.get("status", "log")).to_upper()
	var action := str(entry.get("action", ""))
	var message := str(entry.get("message", ""))
	return "[%s] %s%s" % [status, message, " (%s)" % action if not action.is_empty() else ""]


func _log_color(status: String) -> Color:
	match status:
		"issued":
			return Color(0.78, 0.72, 0.58, 1.0)
		"applied":
			return Color(0.42, 0.9, 0.52, 1.0)
		"error":
			return Color(1.0, 0.34, 0.22, 1.0)
		_:
			return Color(0.62, 0.58, 0.5, 1.0)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.032, 0.03, 0.94)
	style.border_color = Color(0.35, 0.29, 0.2, 1.0)
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style
