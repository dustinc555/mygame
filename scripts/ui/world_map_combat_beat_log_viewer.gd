extends Node

class_name WorldMapCombatBeatLogViewer

const DEFAULT_MAX_RESOLVED_ENCOUNTERS := 4
const DEFAULT_MAX_VISIBLE_BEATS := 24
const POLL_INTERVAL_SECONDS := 0.25

@export var overlay_path: NodePath = NodePath("../WorldMapOverlay")
@export var encounter_state_source_path: NodePath = NodePath()
@export var max_resolved_encounters := DEFAULT_MAX_RESOLVED_ENCOUNTERS
@export var max_visible_beats := DEFAULT_MAX_VISIBLE_BEATS

var _overlay: Node
var _encounter_state_source: Node
var _panel: PanelContainer
var _title_label: Label
var _summary_list: VBoxContainer
var _beat_list: VBoxContainer
var _important_filter: CheckBox
var _important_only := false
var _poll_elapsed := 0.0
var _last_display_signature := ""
var _visible_encounter_keys: Array[String] = []
var _cleared_encounter_keys := {}


func _ready() -> void:
	add_to_group("world_map_combat_beat_log_viewer")
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_mount_viewer")


func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < POLL_INTERVAL_SECONDS:
		return
	_poll_elapsed = 0.0
	_sync_combat_beats(false)


func clear_local_log() -> void:
	for encounter_key in _visible_encounter_keys:
		_cleared_encounter_keys[encounter_key] = true
	_visible_encounter_keys.clear()
	_last_display_signature = ""
	_sync_combat_beats(true)


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
	_panel.name = "CombatBeatLogViewer"
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
	_summary_list = VBoxContainer.new()
	_summary_list.add_theme_constant_override("separation", 2)
	root.add_child(_summary_list)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 92.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_beat_list = VBoxContainer.new()
	_beat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_beat_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_beat_list)
	logs_layer.add_child(_panel)
	_sync_combat_beats(true)


func _header_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	_title_label = Label.new()
	_title_label.text = "Combat Beats"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66, 1.0))
	_title_label.add_theme_font_size_override("font_size", 12)
	row.add_child(_title_label)
	_important_filter = CheckBox.new()
	_important_filter.text = "Important"
	_important_filter.focus_mode = Control.FOCUS_NONE
	_important_filter.toggled.connect(_set_important_only)
	row.add_child(_important_filter)
	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.focus_mode = Control.FOCUS_NONE
	clear_button.pressed.connect(clear_local_log)
	row.add_child(clear_button)
	return row


func _sync_combat_beats(force_render: bool) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var encounter_state := _get_world_encounter_state()
	var resolved_encounters := _resolved_encounters(encounter_state)
	var summaries: Array[Dictionary] = []
	var beats: Array[Dictionary] = []
	var visible_keys: Array[String] = []
	for encounter in resolved_encounters:
		var encounter_key := _encounter_display_key(encounter)
		visible_keys.append(encounter_key)
		summaries.append(_encounter_summary(encounter))
		_append_visible_beats(beats, encounter)
	var signature := _display_signature(summaries, beats)
	if not force_render and signature == _last_display_signature:
		return
	_last_display_signature = signature
	_visible_encounter_keys = visible_keys
	_render(summaries, beats)


func _resolved_encounters(encounter_state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var encounters = encounter_state.get("encounters_by_id", {})
	if not (encounters is Dictionary):
		return result
	for encounter_id in encounters.keys():
		var encounter = encounters[encounter_id]
		if not (encounter is Dictionary):
			continue
		var encounter_record: Dictionary = encounter.duplicate(true)
		if str(encounter_record.get("status", "")) != "resolved":
			continue
		if _cleared_encounter_keys.has(_encounter_display_key(encounter_record)):
			continue
		var battle_result = encounter_record.get("battle_result", {})
		if not (battle_result is Dictionary):
			continue
		encounter_record["_sort_tick"] = int(encounter_record.get("resolved_tick", encounter_record.get("created_tick", 0)))
		result.append(encounter_record)
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return int(first.get("_sort_tick", 0)) > int(second.get("_sort_tick", 0)))
	while result.size() > maxi(1, max_resolved_encounters):
		result.pop_back()
	return result


func _append_visible_beats(beats: Array[Dictionary], encounter: Dictionary) -> void:
	var battle_result: Dictionary = encounter.get("battle_result", {})
	var source_beats = battle_result.get("beats", [])
	if not (source_beats is Array):
		return
	for beat in source_beats:
		if beats.size() >= maxi(1, max_visible_beats):
			return
		if not (beat is Dictionary):
			continue
		var beat_record: Dictionary = beat.duplicate(true)
		if _important_only and not _beat_is_important(beat_record):
			continue
		beat_record["encounter_id"] = str(encounter.get("encounter_id", ""))
		beats.append(beat_record)


func _render(summaries: Array[Dictionary], beats: Array[Dictionary]) -> void:
	_clear_children(_summary_list)
	_clear_children(_beat_list)
	_title_label.text = "Combat Beats: %d encounters, %d beats" % [summaries.size(), beats.size()]
	if summaries.is_empty():
		_summary_list.add_child(_label("No resolved encounters yet.", Color(0.58, 0.53, 0.43, 1.0), 11))
		_beat_list.add_child(_label("Use Force Encounter, then inspect resolved BattleSim beats here.", Color(0.58, 0.53, 0.43, 1.0), 11))
		return
	for summary in summaries:
		_summary_list.add_child(_label(_summary_text(summary), Color(0.72, 0.82, 0.64, 1.0), 11))
	if beats.is_empty():
		_beat_list.add_child(_label("No beats match the current filter.", Color(0.58, 0.53, 0.43, 1.0), 11))
		return
	for beat in beats:
		_beat_list.add_child(_label(_beat_text(beat), _beat_color(str(beat.get("importance", ""))), 11))


func _encounter_summary(encounter: Dictionary) -> Dictionary:
	var battle_result: Dictionary = encounter.get("battle_result", {})
	return {
		"encounter_id": str(encounter.get("encounter_id", "")),
		"resolved_tick": int(encounter.get("resolved_tick", 0)),
		"outcome": str(battle_result.get("outcome", "")),
		"winner_squad_id": str(battle_result.get("winner_squad_id", "")),
		"loser_squad_id": str(battle_result.get("loser_squad_id", "")),
		"summary": str(battle_result.get("summary", "")),
	}


func _summary_text(summary: Dictionary) -> String:
	var resolved_tick := int(summary.get("resolved_tick", 0))
	var text := str(summary.get("summary", "")).strip_edges()
	if text.is_empty():
		text = "%s resolved as %s" % [str(summary.get("encounter_id", "encounter")), str(summary.get("outcome", "unknown"))]
	return "T%d %s" % [resolved_tick, text]


func _beat_text(beat: Dictionary) -> String:
	var summary := str(beat.get("summary", "")).strip_edges()
	if summary.is_empty():
		summary = "%s %s %s" % [str(beat.get("attacker_id", "?")), str(beat.get("action", "acted on")), str(beat.get("defender_id", "?"))]
	return "T%s %s -> %s %s/%s dmg %.1f [%s] %s" % [
		str(beat.get("tick", 0)),
		str(beat.get("attacker_id", "?")),
		str(beat.get("defender_id", "?")),
		str(beat.get("action", "action")),
		str(beat.get("result", "result")),
		float(beat.get("damage", 0.0)),
		str(beat.get("importance", "normal")),
		summary,
	]


func _display_signature(summaries: Array[Dictionary], beats: Array[Dictionary]) -> String:
	var parts: Array[String] = [str(_important_only), str(summaries.size()), str(beats.size())]
	for summary in summaries:
		parts.append("%s:%s:%s" % [str(summary.get("encounter_id", "")), str(summary.get("resolved_tick", "")), str(summary.get("outcome", ""))])
	for beat in beats:
		parts.append("%s:%s:%s:%s:%s" % [str(beat.get("encounter_id", "")), str(beat.get("round", "")), str(beat.get("attacker_id", "")), str(beat.get("defender_id", "")), str(beat.get("importance", ""))])
	return _join_strings(parts, "|")


func _join_strings(parts: Array[String], delimiter: String) -> String:
	var result := ""
	for index in range(parts.size()):
		if index > 0:
			result += delimiter
		result += parts[index]
	return result


func _encounter_display_key(encounter: Dictionary) -> String:
	return "%s:%s:%s" % [str(encounter.get("encounter_id", "")), str(encounter.get("created_tick", "")), str(encounter.get("resolved_tick", ""))]


func _beat_is_important(beat: Dictionary) -> bool:
	match str(beat.get("importance", "normal")):
		"high", "critical", "important":
			return true
		_:
			return false


func _set_important_only(enabled: bool) -> void:
	_important_only = enabled
	_last_display_signature = ""
	_sync_combat_beats(true)


func _get_world_encounter_state() -> Dictionary:
	var source := _get_encounter_state_source()
	if source == null or not source.has_method("get_world_encounter_state"):
		return {}
	var state = source.call("get_world_encounter_state")
	return state.duplicate(true) if state is Dictionary else {}


func _get_overlay() -> Node:
	if _overlay != null and is_instance_valid(_overlay):
		return _overlay
	if overlay_path == NodePath():
		return null
	_overlay = get_node_or_null(overlay_path)
	return _overlay


func _get_encounter_state_source() -> Node:
	if _encounter_state_source != null and is_instance_valid(_encounter_state_source):
		return _encounter_state_source
	if encounter_state_source_path != NodePath():
		_encounter_state_source = get_node_or_null(encounter_state_source_path)
		if _encounter_state_source != null:
			return _encounter_state_source
	if get_tree() != null:
		_encounter_state_source = get_tree().get_first_node_in_group("world_map_combat_sim_source")
	return _encounter_state_source


func _clear_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _beat_color(importance: String) -> Color:
	match importance:
		"high", "critical", "important":
			return Color(0.96, 0.64, 0.34, 1.0)
		_:
			return Color(0.66, 0.62, 0.54, 1.0)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.032, 0.03, 0.92)
	style.border_color = Color(0.22, 0.18, 0.13, 1.0)
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	return style
