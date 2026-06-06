extends Node

class_name WorldMapDemoDebugMetricsViewer

const POLL_INTERVAL_SECONDS := 0.25

@export var overlay_path: NodePath = NodePath("../WorldMapOverlay")
@export var metrics_source_path: NodePath = NodePath("../DemoSimBootstrap")

var _overlay: Node
var _metrics_source: Node
var _panel: PanelContainer
var _metrics_label: Label
var _selected_squad_label: Label
var _squad_picker: OptionButton
var _selected_squad_id := ""
var _squad_picker_signature := ""
var _last_metrics_signature := ""
var _poll_elapsed := 0.0
var _rebuilding_squad_picker := false


func _ready() -> void:
	add_to_group("world_map_demo_debug_metrics_viewer")
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_mount_viewer")


func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < POLL_INTERVAL_SECONDS:
		return
	_poll_elapsed = 0.0
	_sync_metrics(false)


func _mount_viewer() -> void:
	var overlay := _get_overlay()
	if overlay == null or not overlay.has_method("get_logs_layer"):
		return
	var logs_layer := overlay.call("get_logs_layer") as Control
	if logs_layer == null:
		return
	if _panel != null and is_instance_valid(_panel):
		return
	_panel = PanelContainer.new()
	_panel.name = "DemoDebugMetricsViewer"
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_stylebox_override("panel", _panel_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	_panel.add_child(margin)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 4)
	margin.add_child(root)
	root.add_child(_header_row())
	_metrics_label = _label("Waiting for sim metrics...", Color(0.7, 0.66, 0.56, 1.0), 11)
	root.add_child(_metrics_label)
	_selected_squad_label = _label("Selected squad: none", Color(0.58, 0.53, 0.43, 1.0), 11)
	root.add_child(_selected_squad_label)
	logs_layer.add_child(_panel)
	logs_layer.move_child(_panel, 0)
	_sync_metrics(true)


func _header_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Demo Metrics"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66, 1.0))
	title.add_theme_font_size_override("font_size", 12)
	row.add_child(title)
	_squad_picker = OptionButton.new()
	_squad_picker.custom_minimum_size = Vector2(210.0, 24.0)
	_squad_picker.focus_mode = Control.FOCUS_NONE
	_squad_picker.item_selected.connect(_select_squad_index)
	row.add_child(_squad_picker)
	return row


func _sync_metrics(force_render: bool) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var metrics := _get_sim_metrics()
	var state: Dictionary = metrics.get("state", {}) if metrics.get("state", {}) is Dictionary else {}
	var squad_state: Dictionary = state.get("world_squad_state", {}) if state.get("world_squad_state", {}) is Dictionary else {}
	var encounter_state: Dictionary = state.get("world_encounter_state", {}) if state.get("world_encounter_state", {}) is Dictionary else {}
	var active_squads: Dictionary = squad_state.get("active_squads", {}) if squad_state.get("active_squads", {}) is Dictionary else {}
	_update_squad_picker(active_squads)
	var signature := _metrics_signature(metrics, active_squads, encounter_state)
	if not force_render and signature == _last_metrics_signature:
		return
	_last_metrics_signature = signature
	_render_metrics(metrics, active_squads, encounter_state)


func _render_metrics(metrics: Dictionary, active_squads: Dictionary, encounter_state: Dictionary) -> void:
	var encounter_stats := _encounter_stats(encounter_state)
	var beat_stats := _combat_beat_stats(encounter_state)
	var objective_stats := _active_objective_stats(active_squads)
	_metrics_label.text = "Tick %d | avg %.3f ms | squads %d | active objectives %s | active encounters %d | beats %d (%d important)" % [
		int(metrics.get("tick_count", 0)),
		float(metrics.get("average_tick_time_ms", 0.0)),
		active_squads.size(),
		str(objective_stats.get("summary", "0")),
		int(encounter_stats.get("active_count", 0)),
		int(beat_stats.get("beat_count", 0)),
		int(beat_stats.get("important_beat_count", 0)),
	]
	var last_result := str(encounter_stats.get("last_result", "none"))
	var selected_record := _selected_squad_record(active_squads)
	_selected_squad_label.text = "Last encounter: %s\n%s" % [last_result, _selected_squad_text(selected_record)]


func _update_squad_picker(active_squads: Dictionary) -> void:
	var squad_ids := _squad_ids(active_squads)
	var signature := _join_strings(squad_ids, "|")
	if signature == _squad_picker_signature:
		return
	_squad_picker_signature = signature
	_rebuilding_squad_picker = true
	_squad_picker.clear()
	for squad_id in squad_ids:
		_squad_picker.add_item(squad_id)
	if squad_ids.is_empty():
		_selected_squad_id = ""
		_squad_picker.disabled = true
	else:
		_squad_picker.disabled = false
		if _selected_squad_id.is_empty() or not active_squads.has(_selected_squad_id):
			_selected_squad_id = squad_ids[0]
		var selected_index := squad_ids.find(_selected_squad_id)
		_squad_picker.select(maxi(0, selected_index))
	_rebuilding_squad_picker = false


func _select_squad_index(index: int) -> void:
	if _rebuilding_squad_picker or _squad_picker == null:
		return
	if index < 0 or index >= _squad_picker.get_item_count():
		return
	_selected_squad_id = _squad_picker.get_item_text(index)
	_last_metrics_signature = ""
	_sync_metrics(true)


func _active_objective_stats(active_squads: Dictionary) -> Dictionary:
	var active_count := 0
	var by_objective := {}
	for squad_id in active_squads.keys():
		var record = active_squads[squad_id]
		if not (record is Dictionary):
			continue
		var squad_record: Dictionary = record
		if str(squad_record.get("objective_state", "")) != "active":
			continue
		active_count += 1
		var objective_id := str(squad_record.get("objective_id", "unknown"))
		by_objective[objective_id] = int(by_objective.get(objective_id, 0)) + 1
	return {"count": active_count, "summary": _objective_summary(active_count, by_objective)}


func _objective_summary(active_count: int, by_objective: Dictionary) -> String:
	if active_count <= 0:
		return "0"
	var parts: Array[String] = []
	var objective_ids := []
	for objective_id in by_objective.keys():
		objective_ids.append(str(objective_id))
	objective_ids.sort()
	for objective_id in objective_ids:
		parts.append("%s:%d" % [objective_id, int(by_objective.get(objective_id, 0))])
	return "%d [%s]" % [active_count, _join_strings(parts, ", ")]


func _encounter_stats(encounter_state: Dictionary) -> Dictionary:
	var encounters = encounter_state.get("encounters_by_id", {})
	var active_count := 0
	var latest_tick := -1
	var latest_summary := "none"
	if not (encounters is Dictionary):
		return {"active_count": active_count, "last_result": latest_summary}
	for encounter_id in encounters.keys():
		var encounter = encounters[encounter_id]
		if not (encounter is Dictionary):
			continue
		var encounter_record: Dictionary = encounter
		match str(encounter_record.get("status", "")):
			"engaged", "resolving":
				active_count += 1
			"resolved":
				var resolved_tick := int(encounter_record.get("resolved_tick", encounter_record.get("created_tick", 0)))
				if resolved_tick > latest_tick:
					latest_tick = resolved_tick
					latest_summary = _encounter_result_text(encounter_record)
	return {"active_count": active_count, "last_result": latest_summary}


func _encounter_result_text(encounter: Dictionary) -> String:
	var battle_result = encounter.get("battle_result", {})
	if battle_result is Dictionary:
		var summary := str(battle_result.get("summary", "")).strip_edges()
		if not summary.is_empty():
			return summary
		var outcome := str(battle_result.get("outcome", "")).strip_edges()
		if not outcome.is_empty():
			return "%s: %s" % [str(encounter.get("encounter_id", "encounter")), outcome]
	return "%s resolved" % str(encounter.get("encounter_id", "encounter"))


func _combat_beat_stats(encounter_state: Dictionary) -> Dictionary:
	var encounters = encounter_state.get("encounters_by_id", {})
	var beat_count := 0
	var important_beat_count := 0
	if not (encounters is Dictionary):
		return {"beat_count": beat_count, "important_beat_count": important_beat_count}
	for encounter_id in encounters.keys():
		var encounter = encounters[encounter_id]
		if not (encounter is Dictionary):
			continue
		var encounter_record: Dictionary = encounter
		var battle_result = encounter_record.get("battle_result", {})
		if not (battle_result is Dictionary):
			continue
		var beats = battle_result.get("beats", [])
		if not (beats is Array):
			continue
		for beat in beats:
			if not (beat is Dictionary):
				continue
			beat_count += 1
			if _beat_is_important(beat):
				important_beat_count += 1
	return {"beat_count": beat_count, "important_beat_count": important_beat_count}


func _selected_squad_record(active_squads: Dictionary) -> Dictionary:
	if _selected_squad_id.is_empty() or not active_squads.has(_selected_squad_id):
		return {}
	var record = active_squads[_selected_squad_id]
	return record.duplicate(true) if record is Dictionary else {}


func _selected_squad_text(record: Dictionary) -> String:
	if record.is_empty():
		return "Selected squad: none"
	return "Selected squad: %s | faction %s | state %s | objective %s/%s | members %d | strength %.1f | morale %.2f | supplies %.1f | encounter %s" % [
		str(record.get("squad_id", _selected_squad_id)),
		str(record.get("faction_id", "")),
		str(record.get("state", "unknown")),
		str(record.get("objective_id", "")),
		str(record.get("objective_state", "")),
		int(record.get("member_count", 0)),
		float(record.get("strength", 0.0)),
		float(record.get("morale", 0.0)),
		float(record.get("supplies", 0.0)),
		str(record.get("active_encounter_id", record.get("last_encounter_id", ""))),
	]


func _metrics_signature(metrics: Dictionary, active_squads: Dictionary, encounter_state: Dictionary) -> String:
	var parts: Array[String] = [
		str(metrics.get("tick_count", 0)),
		"%.3f" % float(metrics.get("average_tick_time_ms", 0.0)),
		str(active_squads.size()),
		_selected_squad_id,
	]
	var objective_stats := _active_objective_stats(active_squads)
	var encounter_stats := _encounter_stats(encounter_state)
	var beat_stats := _combat_beat_stats(encounter_state)
	parts.append(str(objective_stats.get("summary", "0")))
	parts.append(str(encounter_stats.get("active_count", 0)))
	parts.append(str(encounter_stats.get("last_result", "none")))
	parts.append(str(beat_stats.get("beat_count", 0)))
	parts.append(str(beat_stats.get("important_beat_count", 0)))
	parts.append(str(_selected_squad_record(active_squads)))
	return _join_strings(parts, "|")


func _squad_ids(active_squads: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for squad_id in active_squads.keys():
		result.append(str(squad_id))
	result.sort()
	return result


func _beat_is_important(beat: Dictionary) -> bool:
	match str(beat.get("importance", "normal")):
		"high", "critical", "important":
			return true
		_:
			return false


func _get_sim_metrics() -> Dictionary:
	var source := _get_metrics_source()
	if source == null or not source.has_method("get_sim_metrics"):
		return {}
	var metrics = source.call("get_sim_metrics")
	return metrics.duplicate(true) if metrics is Dictionary else {}


func _get_overlay() -> Node:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	if overlay_path == NodePath():
		return null
	_overlay = get_node_or_null(overlay_path)
	return _overlay


func _get_metrics_source() -> Node:
	if _metrics_source != null and is_instance_valid(_metrics_source):
		return _metrics_source
	if metrics_source_path == NodePath():
		return null
	_metrics_source = get_node_or_null(metrics_source_path)
	return _metrics_source


func _label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _join_strings(parts: Array[String], delimiter: String) -> String:
	var result := ""
	for index in range(parts.size()):
		if index > 0:
			result += delimiter
		result += parts[index]
	return result


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.038, 0.034, 0.95)
	style.border_color = Color(0.26, 0.22, 0.16, 1.0)
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style
