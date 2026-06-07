extends PanelContainer

class_name HumanoidDetailsPanel

signal inspector_action_requested(actor_id: String, action_key: String)

const ACTION_ATTACK := "attack"
const ACTION_CARRY := "carry"
const ACTION_FINISH_OFF := "finish_off"
const ACTION_HEAL := "heal"
const ACTION_INVENTORY := "inventory"
const ACTION_JOBS := "jobs"
const ACTION_SKILLS := "skills"
const ACTION_WAKE_UP := "wake_up"

const BLOOD_GLOW_CRITICAL_LOSS_PER_SECOND := 8.0

var _name_label: Label
var _state_label: Label
var _faction_label: Label
var _work_status_label: Label
var _info_rows: VBoxContainer
var _hunger_row: Control
var _info_labels: Array[Label] = []
var _info_values: Array[Label] = []
var _hunger_label: Label
var _hunger_bar_stack: Control
var _hunger_fill: ColorRect
var _hunger_value: Label
var _blood_row: Control
var _blood_label: Label
var _blood_bar_stack: Control
var _blood_fill: ColorRect
var _blood_value: Label
var _blood_bleed_glow: Panel
var _blood_bleed_glow_style := StyleBoxFlat.new()
var _hp_row: Control
var _hp_label: Label
var _hp_bar_stack: Control
var _health_fill: ColorRect
var _bandaged_fill: ColorRect
var _cut_outline: Panel
var _hp_value: Label
var _fatigue_row: Control
var _fatigue_label: Label
var _fatigue_bar_stack: Control
var _fatigue_fill: ColorRect
var _fatigue_value: Label
var _action_buttons: Array[Button] = []
var _last_snapshot: Dictionary = {}


func _ready() -> void:
	_bind_nodes()
	show_empty()


func show_empty() -> void:
	_last_snapshot = {}
	_bind_nodes()
	_set_vitals_visible(false)
	_set_text(_name_label, "No target")
	_set_text(_state_label, "IDLE")
	if _state_label != null:
		_state_label.modulate = Color(0.58, 0.55, 0.5, 1.0)
	_set_text(_faction_label, "Left-click a person, item, or resource")
	_set_text(_work_status_label, "Inspector ready")
	_set_info_rows_visible(false)
	_set_text(_hunger_label, "Hunger")
	_set_text(_hunger_value, "-")
	_update_fill_bar(_hunger_bar_stack, _hunger_fill, 0.0, Color(0.47, 0.78, 0.43, 1.0))
	_set_text(_blood_label, "Blood")
	_set_text(_blood_value, "-")
	_update_fill_bar(_blood_bar_stack, _blood_fill, 0.0, Color(0.47, 0.78, 0.43, 1.0))
	_update_blood_bleed_glow(0.0)
	_set_text(_hp_label, "Health")
	_set_text(_hp_value, "-")
	_update_hp_bar_visuals(0.0, 0.0, 0.0, 1.0)
	_set_text(_fatigue_label, "Fatigue")
	_set_text(_fatigue_value, "-")
	_update_fill_bar(_fatigue_bar_stack, _fatigue_fill, 0.0, Color(0.47, 0.78, 0.43, 1.0))
	_set_actions([])


func show_character_snapshot(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot.duplicate(true)
	_bind_nodes()
	_set_text(_name_label, str(snapshot.get("member_name", snapshot.get("actor_id", "Unknown"))))
	_set_text(_state_label, str(snapshot.get("life_state_text", "UNKNOWN")).to_upper())
	if _state_label != null:
		_state_label.modulate = _life_state_color(int(snapshot.get("life_state", 0)))
	_set_text(_faction_label, _display_value(snapshot.get("faction_id", "")))
	_set_text(_work_status_label, _job_status_text(snapshot))
	_set_vitals_visible(true)
	var info_rows := _humanoid_info_rows(snapshot)
	_set_info_rows_visible(not info_rows.is_empty())
	if not info_rows.is_empty():
		_set_info_rows(info_rows)
	_set_text(_hunger_label, "Hunger")
	var hunger := float(snapshot.get("hunger", 100.0))
	var hunger_stage := int(snapshot.get("hunger_stage", NpcRules.HungerStage.WELL_NOURISHED))
	_set_text(_hunger_value, "%s %d / 100" % [NpcRules.get_hunger_stage_label(hunger_stage), int(round(hunger))])
	_update_fill_bar(_hunger_bar_stack, _hunger_fill, hunger / 100.0, _stage_color(hunger_stage, NpcRules.HungerStage.WELL_NOURISHED, NpcRules.HungerStage.HUNGRY, NpcRules.HungerStage.STARVING))
	_set_text(_blood_label, "Blood")
	_set_text(_blood_value, "%d / %d" % [int(round(float(snapshot.get("blood", 0.0)))), int(round(float(snapshot.get("max_blood", 0.0))))])
	var blood_ratio := float(snapshot.get("blood", 0.0)) / maxf(float(snapshot.get("max_blood", 0.0)), 1.0)
	_update_fill_bar(_blood_bar_stack, _blood_fill, blood_ratio, _ratio_color(blood_ratio))
	_update_blood_bleed_glow(float(snapshot.get("bleed_rate", 0.0)))
	_set_text(_hp_label, "Health")
	_set_text(_hp_value, "%d / %d" % [int(round(float(snapshot.get("hp", 0.0)))), int(round(float(snapshot.get("max_hp", 0.0))))])
	_update_hp_bar_visuals(float(snapshot.get("hp", 0.0)), float(snapshot.get("open_cut_damage", 0.0)), float(snapshot.get("bandaged_cut_damage", 0.0)), float(snapshot.get("max_hp", 0.0)), float(snapshot.get("blunt_damage", 0.0)))
	_set_text(_fatigue_label, "Fatigue")
	var fatigue := float(snapshot.get("fatigue", 100.0))
	var fatigue_stage := int(snapshot.get("fatigue_stage", NpcRules.FatigueStage.WELL_RESTED))
	_set_text(_fatigue_value, "%s %d / 100" % [NpcRules.get_fatigue_stage_label(fatigue_stage), int(round(fatigue))])
	_update_fill_bar(_fatigue_bar_stack, _fatigue_fill, fatigue / 100.0, _stage_color(fatigue_stage, NpcRules.FatigueStage.WELL_RESTED, NpcRules.FatigueStage.WINDED, NpcRules.FatigueStage.EXHAUSTED))
	_set_actions(_actions_for_snapshot(snapshot))


func get_debug_state() -> Dictionary:
	return {
		"snapshot": _last_snapshot.duplicate(true),
		"name": _name_label.text if _name_label != null else "",
		"state": _state_label.text if _state_label != null else "",
		"faction": _faction_label.text if _faction_label != null else "",
		"work_status": _work_status_label.text if _work_status_label != null else "",
		"info_labels": _info_label_texts(),
		"info_values": _info_value_texts(),
		"info_rows_visible": _info_rows.visible if _info_rows != null else false,
		"vital_labels": _vital_label_texts(),
		"actions": _action_debug_state(),
		"hunger": _hunger_value.text if _hunger_value != null else "",
		"hp": _hp_value.text if _hp_value != null else "",
		"blood": _blood_value.text if _blood_value != null else "",
		"fatigue": _fatigue_value.text if _fatigue_value != null else "",
	}


func _bind_nodes() -> void:
	if _name_label != null and not _action_buttons.is_empty():
		return
	if _name_label == null:
		_name_label = get_node_or_null("Margin/DetailsVBox/HeaderRow/Name") as Label
		_state_label = get_node_or_null("Margin/DetailsVBox/HeaderRow/State") as Label
		_faction_label = get_node_or_null("Margin/DetailsVBox/Faction") as Label
		_work_status_label = get_node_or_null("Margin/DetailsVBox/WorkStatus") as Label
		_info_rows = get_node_or_null("Margin/DetailsVBox/InfoRows") as VBoxContainer
		_info_labels.clear()
		_info_values.clear()
		for index in range(1, 5):
			_info_labels.append(get_node_or_null("Margin/DetailsVBox/InfoRows/InfoRow%d/InfoLabel" % index) as Label)
			_info_values.append(get_node_or_null("Margin/DetailsVBox/InfoRows/InfoRow%d/InfoValue" % index) as Label)
		_hunger_row = get_node_or_null("Margin/DetailsVBox/HungerRow") as Control
		_hunger_label = get_node_or_null("Margin/DetailsVBox/HungerRow/HungerLabel") as Label
		_hunger_bar_stack = get_node_or_null("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack") as Control
		_hunger_fill = get_node_or_null("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack/HungerFill") as ColorRect
		_hunger_value = get_node_or_null("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack/HungerValue") as Label
		_blood_row = get_node_or_null("Margin/DetailsVBox/BloodRow") as Control
		_blood_label = get_node_or_null("Margin/DetailsVBox/BloodRow/BloodLabel") as Label
		_blood_bar_stack = get_node_or_null("Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack") as Control
		_blood_fill = get_node_or_null("Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack/BloodFill") as ColorRect
		_blood_value = get_node_or_null("Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack/BloodValue") as Label
		_setup_blood_bleed_glow()
		_hp_row = get_node_or_null("Margin/DetailsVBox/HpRow") as Control
		_hp_label = get_node_or_null("Margin/DetailsVBox/HpRow/HpLabel") as Label
		_hp_bar_stack = get_node_or_null("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack") as Control
		_health_fill = get_node_or_null("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/HealthFill") as ColorRect
		_bandaged_fill = get_node_or_null("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/BandagedFill") as ColorRect
		_cut_outline = get_node_or_null("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/CutOutline") as Panel
		_hp_value = get_node_or_null("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/HpValue") as Label
		_fatigue_row = get_node_or_null("Margin/DetailsVBox/FatigueRow") as Control
		_fatigue_label = get_node_or_null("Margin/DetailsVBox/FatigueRow/FatigueLabel") as Label
		_fatigue_bar_stack = get_node_or_null("Margin/DetailsVBox/FatigueRow/FatigueBarFrame/FatigueBarStack") as Control
		_fatigue_fill = get_node_or_null("Margin/DetailsVBox/FatigueRow/FatigueBarFrame/FatigueBarStack/FatigueFill") as ColorRect
		_fatigue_value = get_node_or_null("Margin/DetailsVBox/FatigueRow/FatigueBarFrame/FatigueBarStack/FatigueValue") as Label
	_bind_action_buttons()


func _bind_action_buttons() -> void:
	if not _action_buttons.is_empty():
		return
	for path in [
		"Margin/DetailsVBox/ActionRow/PrimaryActionButton",
		"Margin/DetailsVBox/ActionRow/SecondaryActionButton",
		"Margin/DetailsVBox/ActionRow/TertiaryActionButton",
		"Margin/DetailsVBox/ActionRow/MoreActionButton",
		"Margin/DetailsVBox/ActionRow/JobsActionButton",
	]:
		var button := get_node_or_null(path) as Button
		if button == null:
			continue
		button.pressed.connect(_on_action_button_pressed.bind(button))
		_action_buttons.append(button)


func _actions_for_snapshot(snapshot: Dictionary) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var life_state := int(snapshot.get("life_state", 0))
	if bool(snapshot.get("player_party_member", false)):
		actions.append({"key": ACTION_INVENTORY, "label": "Inventory"})
		actions.append({"key": ACTION_SKILLS, "label": "Skills"})
		actions.append({"key": ACTION_JOBS, "label": "Jobs"})
		if life_state == 1:
			actions.append({"key": ACTION_WAKE_UP, "label": "Wake"})
		return actions
	actions.append({"key": ACTION_SKILLS, "label": "Skills"})
	if _is_alive(life_state):
		actions.append({"key": ACTION_JOBS, "label": "Jobs"})
		actions.append({"key": ACTION_ATTACK, "label": "Attack"})
		actions.append({"key": ACTION_HEAL, "label": "Heal"})
	elif _is_dead(life_state):
		return actions
	else:
		actions.append({"key": ACTION_HEAL, "label": "Heal"})
		actions.append({"key": ACTION_CARRY, "label": "Carry"})
		actions.append({"key": ACTION_FINISH_OFF, "label": "Burn" if bool(snapshot.get("requires_fire_to_die", false)) else "Finish"})
	return actions


func _set_actions(actions: Array[Dictionary]) -> void:
	for index in range(_action_buttons.size()):
		var button := _action_buttons[index]
		if button == null:
			continue
		if index >= actions.size():
			button.visible = false
			button.disabled = true
			button.text = ""
			button.set_meta("inspector_action_key", "")
			continue
		var action := actions[index]
		button.visible = true
		button.text = str(action.get("label", "Action"))
		button.disabled = bool(action.get("disabled", false))
		button.set_meta("inspector_action_key", str(action.get("key", "")))


func _on_action_button_pressed(button: Button) -> void:
	if button == null:
		return
	var action_key := str(button.get_meta("inspector_action_key", ""))
	if action_key.is_empty():
		return
	var actor_id := str(_last_snapshot.get("actor_id", "")).strip_edges()
	if actor_id.is_empty():
		return
	inspector_action_requested.emit(actor_id, action_key)


func _action_debug_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for button in _action_buttons:
		if button == null:
			continue
		result.append({
			"text": button.text,
			"visible": button.visible,
			"disabled": button.disabled,
			"key": str(button.get_meta("inspector_action_key", "")),
		})
	return result


func _set_info_row(index: int, label: String, value: String) -> void:
	if index < 0 or index >= _info_labels.size() or index >= _info_values.size():
		return
	_set_text(_info_labels[index], label)
	_set_text(_info_values[index], value)


func _update_fill_bar(bar_stack: Control, fill: ColorRect, ratio: float, color: Color) -> void:
	if bar_stack == null or fill == null:
		return
	var width := bar_stack.size.x
	if width <= 0.0:
		width = maxf(bar_stack.custom_minimum_size.x, 160.0)
	var height := bar_stack.size.y
	if height <= 0.0:
		height = maxf(bar_stack.custom_minimum_size.y, 14.0)
	fill.color = color
	fill.position = Vector2.ZERO
	fill.size = Vector2(width * clampf(ratio, 0.0, 1.0), height)


func _set_text(label: Label, value: String) -> void:
	if label != null:
		label.text = value


func _display_value(value) -> String:
	var text := str(value).strip_edges()
	return text if not text.is_empty() else "-"


func _display_token(value: String) -> String:
	var text := value.strip_edges()
	if text.is_empty():
		return "-"
	var words := text.replace(".", "_").split("_")
	for index in range(words.size()):
		words[index] = str(words[index]).capitalize()
	return " ".join(words)


func _job_status_text(snapshot: Dictionary) -> String:
	var move_order: Dictionary = snapshot.get("move_order", {}) if snapshot.get("move_order", {}) is Dictionary else {}
	if bool(move_order.get("active", false)):
		return "Moving"
	return _display_token(str(snapshot.get("ledger_activity_state", "routine")))


func _humanoid_info_rows(snapshot: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for spec in [
		{"label": "Law", "field": "law_status_label"},
		{"label": "Warrant", "field": "law_warrant_summary"},
		{"label": "Sentence", "field": "law_sentence_summary"},
	]:
		var value := str(snapshot.get(str(spec["field"]), "")).strip_edges()
		if value.is_empty():
			continue
		rows.append({"label": str(spec["label"]), "value": value})
		if rows.size() >= _info_labels.size():
			break
	return rows


func _set_info_rows(rows: Array[Dictionary]) -> void:
	for index in range(_info_labels.size()):
		var row: Control = null
		if _info_labels[index] != null:
			row = _info_labels[index].get_parent() as Control
		if row != null:
			row.visible = index < rows.size()
		if index >= rows.size():
			continue
		var data := rows[index]
		_set_info_row(index, str(data.get("label", "-")), str(data.get("value", "-")))


func _set_vitals_visible(is_visible: bool) -> void:
	for row in [_hunger_row, _blood_row, _hp_row, _fatigue_row]:
		if row != null:
			row.visible = is_visible


func _set_info_rows_visible(is_visible: bool) -> void:
	if _info_rows != null:
		_info_rows.visible = is_visible
	for label in _info_labels:
		var row: Control = null
		if label != null:
			row = label.get_parent() as Control
		if row != null:
			row.visible = is_visible


func _setup_blood_bleed_glow() -> void:
	if _blood_bar_stack == null or _blood_bleed_glow != null:
		return
	_blood_bleed_glow = Panel.new()
	_blood_bleed_glow.name = "BloodBleedGlow"
	_blood_bleed_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood_bleed_glow_style.bg_color = Color(1.0, 0.0, 0.0, 0.0)
	_blood_bleed_glow_style.set_border_width_all(2)
	_blood_bleed_glow_style.corner_radius_top_left = 4
	_blood_bleed_glow_style.corner_radius_top_right = 4
	_blood_bleed_glow_style.corner_radius_bottom_right = 4
	_blood_bleed_glow_style.corner_radius_bottom_left = 4
	_blood_bleed_glow_style.shadow_size = 5
	_blood_bleed_glow.add_theme_stylebox_override("panel", _blood_bleed_glow_style)
	_blood_bleed_glow.visible = false
	_blood_bar_stack.add_child(_blood_bleed_glow)
	if _blood_value != null:
		_blood_bar_stack.move_child(_blood_value, _blood_bar_stack.get_child_count() - 1)


func _update_blood_bleed_glow(bleed_rate: float) -> void:
	if _blood_bleed_glow == null or _blood_bar_stack == null:
		return
	if bleed_rate <= 0.01:
		_blood_bleed_glow.visible = false
		return
	var blood_loss_per_second := bleed_rate * NpcRules.BLEED_TO_BLOOD_RATE
	var severity := clampf(blood_loss_per_second / BLOOD_GLOW_CRITICAL_LOSS_PER_SECOND, 0.0, 1.0)
	var pulse_rate := lerpf(0.55, 0.8, severity)
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * TAU * pulse_rate)
	var alpha := lerpf(lerpf(0.04, 0.82, severity), lerpf(0.48, 1.0, severity), pulse)
	_blood_bleed_glow_style.border_color = Color(1.0, 0.04, 0.02, alpha)
	_blood_bleed_glow_style.shadow_color = Color(1.0, 0.0, 0.0, alpha * 0.7)
	_blood_bleed_glow.position = Vector2(-3.0, -3.0)
	_blood_bleed_glow.size = _blood_bar_stack.size + Vector2(6.0, 6.0)
	_blood_bleed_glow.visible = true


func _update_hp_bar_visuals(current_hp: float, open_cut: float, bandaged_cut: float, max_hp: float, blunt_damage: float = 0.0) -> void:
	if _hp_bar_stack == null or _health_fill == null:
		return
	var total_width := _hp_bar_stack.size.x
	if total_width <= 0.0:
		total_width = maxf(_hp_bar_stack.custom_minimum_size.x, 160.0)
	var total_height := _hp_bar_stack.size.y
	if total_height <= 0.0:
		total_height = maxf(_hp_bar_stack.custom_minimum_size.y, 14.0)
	var safe_max_hp := maxf(max_hp, 1.0)
	var health_width := total_width * clampf(current_hp / safe_max_hp, 0.0, 1.0)
	var bandaged_width := total_width * clampf(bandaged_cut / safe_max_hp, 0.0, 1.0)
	var cut_width := total_width * clampf(open_cut / safe_max_hp, 0.0, 1.0)
	var occupied_width := total_width * clampf((safe_max_hp - blunt_damage) / safe_max_hp, 0.0, 1.0)
	var max_cut_start := maxf(0.0, occupied_width - cut_width)
	var bandaged_start := minf(health_width, occupied_width)
	var cut_start := minf(bandaged_start + bandaged_width, max_cut_start)
	_health_fill.position = Vector2.ZERO
	_health_fill.size = Vector2(maxf(0.0, minf(health_width, occupied_width)), total_height)
	if _bandaged_fill != null:
		_bandaged_fill.visible = bandaged_width > 0.5
		_bandaged_fill.position = Vector2(bandaged_start, 0.0)
		_bandaged_fill.size = Vector2(maxf(0.0, minf(bandaged_width, maxf(0.0, occupied_width - bandaged_start))), total_height)
	if _cut_outline != null:
		_cut_outline.visible = cut_width > 0.5
		_cut_outline.position = Vector2(cut_start, 0.0)
		_cut_outline.size = Vector2(maxf(0.0, minf(cut_width, maxf(0.0, occupied_width - cut_start))), total_height)


func _stage_color(stage: int, good_stage: int, warning_stage: int, danger_stage: int) -> Color:
	if stage == danger_stage:
		return Color(0.83, 0.24, 0.24, 1.0)
	if stage == warning_stage:
		return Color(0.82, 0.69, 0.22, 1.0)
	if stage == good_stage:
		return Color(0.47, 0.78, 0.43, 1.0)
	return Color(0.47, 0.78, 0.43, 1.0)


func _ratio_color(ratio: float) -> Color:
	if ratio <= 0.33:
		return Color(0.83, 0.24, 0.24, 1.0)
	if ratio <= 0.66:
		return Color(0.82, 0.69, 0.22, 1.0)
	return Color(0.47, 0.78, 0.43, 1.0)


func _life_state_color(life_state: int) -> Color:
	match life_state:
		NpcRules.LifeState.DEAD:
			return Color(0.9, 0.2, 0.2, 1.0)
		NpcRules.LifeState.DYING:
			return Color(1.0, 0.22, 0.16, 1.0)
		NpcRules.LifeState.RECOVERY_COMA:
			return Color(1.0, 0.46, 0.18, 1.0)
		NpcRules.LifeState.UNCONSCIOUS:
			return Color(0.95, 0.6, 0.2, 1.0)
		_:
			return Color(0.82, 0.78, 0.66, 1.0)


func _is_alive(life_state: int) -> bool:
	return life_state == NpcRules.LifeState.ALIVE


func _is_dead(life_state: int) -> bool:
	return life_state == NpcRules.LifeState.DEAD


func _vital_label_texts() -> Array[String]:
	return [
		_hunger_label.text if _hunger_label != null else "",
		_blood_label.text if _blood_label != null else "",
		_hp_label.text if _hp_label != null else "",
		_fatigue_label.text if _fatigue_label != null else "",
	]


func _info_label_texts() -> Array[String]:
	var values: Array[String] = []
	for label in _info_labels:
		values.append(label.text if label != null else "")
	return values


func _info_value_texts() -> Array[String]:
	var values: Array[String] = []
	for label in _info_values:
		values.append(label.text if label != null else "")
	return values
