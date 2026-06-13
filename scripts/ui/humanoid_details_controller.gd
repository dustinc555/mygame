extends Node

class_name HumanoidDetailsController

signal inspector_action_requested(target, action_key: String)

const CHARACTER_SKILLS_WINDOW_SCRIPT = preload("res://scripts/ui/character_skills_window.gd")
const CHARACTER_JOBS_WINDOW_SCRIPT = preload("res://scripts/ui/character_jobs_window.gd")

const BLOOD_GLOW_CRITICAL_LOSS_PER_SECOND := 8.0
const ACTION_ATTACK := "attack"
const ACTION_CARRY := "carry"
const ACTION_FINISH_OFF := "finish_off"
const ACTION_HEAL := "heal"
const ACTION_INVENTORY := "inventory"
const ACTION_JOBS := "jobs"
const ACTION_MINE := "mine"
const ACTION_OPEN_CONTAINER := "open_container"
const ACTION_ORDER := "order"
const ACTION_PICKUP_ITEM := "pickup_item"
const ACTION_SKILLS := "skills"
const ACTION_STAND_UP := "stand_up"
const ACTION_TALK := "talk"
const ACTION_TRADE := "trade"
const ACTION_UNLOCK_CONTAINER := "unlock_container"
const ACTION_WAKE_UP := "wake_up"
const WORLD_ACTION_PREFIX := "world:"
const INFO_LABEL_COLOR := Color(0.58, 0.56, 0.5, 1.0)
const INFO_VALUE_COLOR := Color(0.8, 0.75, 0.62, 1.0)
const INFO_RESTRICTED_COLOR := Color(0.94, 0.34, 0.28, 1.0)
const INFO_CRIME_COLOR := Color(1.0, 0.16, 0.12, 1.0)
const INFO_JAILED_COLOR := Color(0.95, 0.58, 0.24, 1.0)

var root_scene: Node
var hud_layer: CanvasLayer
var details_panel: Control
var name_label: Label
var faction_label: Label
var work_label: Label
var state_label: Label
var hunger_label: Label
var hunger_bar_stack: Control
var hunger_fill: ColorRect
var hunger_value: Label
var blood_label: Label
var blood_bar_stack: Control
var blood_fill: ColorRect
var blood_value: Label
var blood_bleed_glow: Panel
var _blood_bleed_glow_style := StyleBoxFlat.new()
var hp_label: Label
var hp_bar_stack: Control
var hp_health_fill: ColorRect
var hp_bandaged_fill: ColorRect
var hp_cut_outline: Control
var hp_value: Label
var fatigue_label: Label
var fatigue_bar_stack: Control
var fatigue_fill: ColorRect
var fatigue_value: Label
var action_buttons: Array[Button] = []
var vital_rows: Array[Control] = []
var hunger_row: Control
var blood_row: Control
var hp_row: Control
var fatigue_row: Control
var info_rows: Array[Control] = []
var info_labels: Array[Label] = []
var info_values: Array[Label] = []
var skills_window: Control
var jobs_window: Control
var current_target
var _initialized := false


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	add_to_group("humanoid_details_controller")
	if root_scene != null:
		if hud_layer == null and root_scene != null:
			hud_layer = root_scene.get_node_or_null("GameHUD")
		_do_initialize()


func _process(_delta: float) -> void:
	if not _initialized:
		return
	_update_panel()


func inspect_humanoid(target) -> void:
	inspect_target(target)


func inspect_target(target) -> void:
	if current_target == target:
		_update_panel()
		return
	_set_target_inspected(current_target, false)
	current_target = target
	_set_target_inspected(current_target, true)
	_update_panel()


func clear_if_not_party_target() -> void:
	if not _has_valid_current_target():
		inspect_target(null)
		return
	if not _target_is_player_party_member(current_target):
		inspect_target(null)


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	if hud_layer == null:
		hud_layer = root_scene.get_node_or_null("GameHUD")
	if hud_layer == null:
		return
	details_panel = hud_layer.get_node_or_null("HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel")
	if details_panel == null:
		return
	name_label = details_panel.get_node("Margin/DetailsVBox/HeaderRow/Name")
	faction_label = details_panel.get_node("Margin/DetailsVBox/Faction")
	work_label = details_panel.get_node("Margin/DetailsVBox/WorkStatus")
	state_label = details_panel.get_node("Margin/DetailsVBox/HeaderRow/State")
	hunger_label = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerLabel")
	hunger_bar_stack = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack")
	hunger_fill = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack/HungerFill")
	hunger_value = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack/HungerValue")
	blood_label = details_panel.get_node("Margin/DetailsVBox/BloodRow/BloodLabel")
	blood_bar_stack = details_panel.get_node("Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack")
	blood_fill = details_panel.get_node("Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack/BloodFill")
	blood_value = details_panel.get_node("Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack/BloodValue")
	_setup_blood_bleed_glow()
	hp_label = details_panel.get_node("Margin/DetailsVBox/HpRow/HpLabel")
	hp_bar_stack = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack")
	hp_health_fill = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/HealthFill")
	hp_bandaged_fill = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/BandagedFill")
	hp_cut_outline = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/CutOutline")
	hp_value = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/HpValue")
	fatigue_label = details_panel.get_node("Margin/DetailsVBox/FatigueRow/FatigueLabel")
	fatigue_bar_stack = details_panel.get_node("Margin/DetailsVBox/FatigueRow/FatigueBarFrame/FatigueBarStack")
	fatigue_fill = details_panel.get_node("Margin/DetailsVBox/FatigueRow/FatigueBarFrame/FatigueBarStack/FatigueFill")
	fatigue_value = details_panel.get_node("Margin/DetailsVBox/FatigueRow/FatigueBarFrame/FatigueBarStack/FatigueValue")
	hunger_row = details_panel.get_node("Margin/DetailsVBox/HungerRow")
	blood_row = details_panel.get_node("Margin/DetailsVBox/BloodRow")
	hp_row = details_panel.get_node("Margin/DetailsVBox/HpRow")
	fatigue_row = details_panel.get_node("Margin/DetailsVBox/FatigueRow")
	vital_rows = [hunger_row, blood_row, hp_row, fatigue_row]
	for index in range(1, 5):
		var info_row := details_panel.get_node("Margin/DetailsVBox/InfoRows/InfoRow%d" % index) as Control
		info_rows.append(info_row)
		info_labels.append(info_row.get_node("InfoLabel") as Label)
		info_values.append(info_row.get_node("InfoValue") as Label)
	_register_action_button("Margin/DetailsVBox/ActionRow/PrimaryActionButton")
	_register_action_button("Margin/DetailsVBox/ActionRow/SecondaryActionButton")
	_register_action_button("Margin/DetailsVBox/ActionRow/TertiaryActionButton")
	_register_action_button("Margin/DetailsVBox/ActionRow/MoreActionButton")
	_register_action_button("Margin/DetailsVBox/ActionRow/JobsActionButton")
	details_panel.visible = true
	_initialized = true
	_update_panel()


func _register_action_button(path: String) -> void:
	var button := details_panel.get_node_or_null(path) as Button
	if button == null:
		return
	button.pressed.connect(_on_action_button_pressed.bind(button))
	action_buttons.append(button)


func _update_panel() -> void:
	if details_panel == null:
		return
	if current_target != null and not is_instance_valid(current_target):
		current_target = null
	if current_target == null:
		_update_empty_panel()
		return
	if current_target is WorldActor:
		_update_humanoid_panel(current_target as WorldActor)
		return
	_update_world_target_panel(current_target)


func _update_empty_panel() -> void:
	_set_vitals_visible(false)
	_set_info_rows_visible(false)
	name_label.text = "No target"
	faction_label.text = "Left-click a person, item, or resource"
	work_label.text = "Inspector ready"
	state_label.text = "IDLE"
	state_label.modulate = Color(0.58, 0.55, 0.5, 1.0)
	_set_actions([])


func _update_humanoid_panel(target: WorldActor) -> void:
	_set_vitals_visible(true)
	var humanoid_info_rows := _get_humanoid_info_rows(target)
	_set_info_rows_visible(not humanoid_info_rows.is_empty())
	if not humanoid_info_rows.is_empty():
		_set_info_rows(humanoid_info_rows)
	_set_humanoid_row_labels(target)
	_set_humanoid_vital_rows(target)
	name_label.text = target.member_name
	faction_label.text = target.faction_name
	work_label.text = target.get_job_status_text() if target.has_method("get_job_status_text") else ""
	state_label.text = target.get_life_state_label().to_upper()
	state_label.modulate = _get_life_state_color(target.life_state)
	if target.shows_hunger_vital():
		var hunger_stage_label: String = target.get_hunger_stage_label()
		hunger_value.text = "%s %d / 100" % [hunger_stage_label, int(round(target.hunger))]
		_update_fill_bar(hunger_bar_stack, hunger_fill, target.hunger / 100.0, _get_stage_color(target.get_hunger_stage(), NpcRules.HungerStage.WELL_NOURISHED, NpcRules.HungerStage.HUNGRY, NpcRules.HungerStage.STARVING))
	blood_value.text = "%d / %d" % [int(round(target.blood)), int(round(target.max_blood))]
	var vital_fluid_ratio := target.blood / maxf(target.max_blood, 1.0)
	var vital_fluid_color := target.get_vital_fluid_bar_color(_get_ratio_color(vital_fluid_ratio))
	_update_fill_bar(blood_bar_stack, blood_fill, vital_fluid_ratio, vital_fluid_color)
	_update_vital_fluid_blink(target, vital_fluid_color)
	_update_blood_bleed_glow(target.get_bleed_rate() if target.has_method("get_bleed_rate") else 0.0, target.get_vital_fluid_glow_color(Color(1.0, 0.04, 0.02, 1.0)))
	_update_hp_bar_visuals(target.hp, target.get_open_cut_damage(), target.get_bandaged_cut_damage(), target.max_hp, target.get_blunt_damage())
	hp_value.text = "%d / %d" % [int(round(target.hp)), int(round(target.max_hp))]
	if target.shows_fatigue_vital():
		var fatigue_stage_label: String = target.get_fatigue_stage_label()
		fatigue_value.text = "%s %d / 100" % [fatigue_stage_label, int(round(target.fatigue))]
		_update_fill_bar(fatigue_bar_stack, fatigue_fill, target.fatigue / 100.0, _get_stage_color(target.get_fatigue_stage(), NpcRules.FatigueStage.WELL_RESTED, NpcRules.FatigueStage.WINDED, NpcRules.FatigueStage.EXHAUSTED))
	_set_actions(_get_humanoid_actions(target))


func _get_humanoid_info_rows(target: WorldActor) -> Array:
	var rows: Array = []
	var law_status := _get_humanoid_law_status(target)
	if not law_status.is_empty():
		rows.append({"label": "Law", "value": law_status, "value_color": _get_humanoid_law_status_color(target)})
	var warrant_summary := _get_humanoid_meta_text(target, "law_warrant_summary")
	if not warrant_summary.is_empty():
		rows.append({"label": "Warrant", "value": warrant_summary})
	var sentence_summary := _get_humanoid_meta_text(target, "law_sentence_summary")
	if not sentence_summary.is_empty():
		rows.append({"label": "Sentence", "value": sentence_summary})
	while rows.size() > info_rows.size():
		rows.pop_back()
	return rows


func _get_humanoid_law_status(target: WorldActor) -> String:
	var caught_status := _get_humanoid_meta_text(target, "law_status_label")
	if not caught_status.is_empty():
		return caught_status
	return _get_humanoid_meta_text(target, "law_active_crime_label")


func _get_humanoid_law_status_color(target: WorldActor) -> Color:
	var kind := _get_humanoid_meta_text(target, "law_status_kind")
	if kind == "jailed":
		return INFO_JAILED_COLOR
	if kind == "caught" or not _get_humanoid_meta_text(target, "law_active_crime_label").is_empty():
		return INFO_CRIME_COLOR
	return INFO_VALUE_COLOR


func _get_humanoid_meta_text(target: WorldActor, meta_name: String) -> String:
	if target == null or not target.has_meta(meta_name):
		return ""
	return str(target.get_meta(meta_name))


func _update_world_target_panel(target) -> void:
	_set_vitals_visible(false)
	_set_info_rows_visible(true)
	_clear_bar_values()
	name_label.text = _get_target_display_name(target)
	faction_label.text = _get_target_subtitle(target)
	work_label.text = _get_target_detail(target)
	state_label.text = _get_target_state_label(target)
	state_label.modulate = _get_target_state_color(target)
	_set_world_target_rows(target)
	_set_actions(_get_world_target_actions(target))


func _get_humanoid_actions(target: WorldActor) -> Array:
	var actions: Array = []
	if target.is_player_party_member():
		actions.append({"key": ACTION_INVENTORY, "label": "Inventory"})
		if _target_can_open_skills():
			actions.append({"key": ACTION_SKILLS, "label": "Skills"})
		actions.append({"key": ACTION_JOBS, "label": "Jobs"})
		if target.life_state == NpcRules.LifeState.ASLEEP:
			actions.append({"key": ACTION_WAKE_UP, "label": "Wake"})
		elif target is HumanoidCharacter and target.has_method("is_sitting") and target.is_sitting():
			if _target_can_order_from_waiter(target):
				actions.append({"key": ACTION_ORDER, "label": "Order"})
			actions.append({"key": ACTION_STAND_UP, "label": "Stand"})
		return actions
	if _target_can_open_skills():
		actions.append({"key": ACTION_SKILLS, "label": "Skills"})
	if target is HumanoidCharacter and target.is_downed_state():
		actions.append({"key": ACTION_HEAL, "label": "Heal"})
		actions.append({"key": ACTION_CARRY, "label": "Carry"})
		if target.requires_fire_to_die():
			actions.append({"key": ACTION_FINISH_OFF, "label": "Burn", "disabled": not target.can_be_destroyed_by_cinder()})
		else:
			actions.append({"key": ACTION_FINISH_OFF, "label": "Finish"})
		return actions
	if target.life_state == NpcRules.LifeState.DEAD:
		return actions
	if target.has_method("has_conversation_definition") and target.has_conversation_definition():
		actions.append({"key": ACTION_TALK, "label": "Talk"})
	if target.has_method("get_merchant_role") and target.get_merchant_role() != null:
		actions.append({"key": ACTION_TRADE, "label": "Trade"})
	actions.append({"key": ACTION_JOBS, "label": "Jobs"})
	actions.append({"key": ACTION_ATTACK, "label": "Attack"})
	actions.append({"key": ACTION_HEAL, "label": "Heal"})
	return actions


func _get_world_target_actions(target) -> Array:
	var actions: Array = []
	if target is Node and target.is_in_group("mining_resource"):
		actions.append({"key": ACTION_MINE, "label": "Mine"})
	if target is Node and target.is_in_group("world_container"):
		var is_locked := bool(target.get("is_locked"))
		actions.append({"key": ACTION_UNLOCK_CONTAINER if is_locked else ACTION_OPEN_CONTAINER, "label": "Unlock" if is_locked else "Open"})
	if target is Node and target.is_in_group("world_item"):
		actions.append({"key": ACTION_PICKUP_ITEM, "label": "Pick Up"})
	if target is Node and target.has_method("get_world_context_actions"):
		var context_actions: Array = target.get_world_context_actions(null)
		for action in context_actions:
			if actions.size() >= action_buttons.size():
				break
			var action_key := str(action.get("key", ""))
			if action_key.is_empty():
				continue
			actions.append({
				"key": WORLD_ACTION_PREFIX + action_key,
				"label": str(action.get("label", "Action")),
				"disabled": bool(action.get("disabled", false)) or action_key == "depleted",
			})
	while actions.size() > action_buttons.size():
		actions.pop_back()
	return actions


func _set_actions(actions: Array) -> void:
	for index in range(action_buttons.size()):
		var button := action_buttons[index]
		if button == null:
			continue
		if index >= actions.size():
			button.visible = false
			button.disabled = true
			button.set_meta("inspector_action_key", "")
			continue
		var action: Dictionary = actions[index]
		button.visible = true
		button.text = str(action.get("label", "Action"))
		button.disabled = bool(action.get("disabled", false))
		button.set_meta("inspector_action_key", str(action.get("key", "")))


func _on_action_button_pressed(button: Button) -> void:
	var action_key := str(button.get_meta("inspector_action_key", ""))
	if action_key.is_empty():
		return
	if action_key == ACTION_SKILLS:
		_on_skills_button_pressed()
		return
	if action_key == ACTION_JOBS:
		_on_jobs_button_pressed()
		return
	if not _has_valid_current_target():
		return
	inspector_action_requested.emit(current_target, action_key)


func _set_vitals_visible(is_visible: bool) -> void:
	for row in vital_rows:
		if row != null:
			row.visible = is_visible


func _set_info_rows_visible(is_visible: bool) -> void:
	var info_rows_container := details_panel.get_node_or_null("Margin/DetailsVBox/InfoRows") as Control
	if info_rows_container != null:
		info_rows_container.visible = is_visible
	for row in info_rows:
		if row != null:
			row.visible = is_visible


func _set_humanoid_row_labels(target: WorldActor) -> void:
	_set_row_label(hunger_label, "Hunger")
	_set_row_label(blood_label, target.get_vital_fluid_label() if target != null else "Blood")
	_set_row_label(hp_label, target.get_health_vital_label() if target != null else "Health")
	_set_row_label(fatigue_label, "Fatigue")


func _set_humanoid_vital_rows(target: WorldActor) -> void:
	if hunger_row != null:
		hunger_row.visible = target != null and target.shows_hunger_vital()
	if blood_row != null:
		blood_row.visible = target != null
	if hp_row != null:
		hp_row.visible = target != null
	if fatigue_row != null:
		fatigue_row.visible = target != null and target.shows_fatigue_vital()


func _set_world_target_rows(target) -> void:
	if _is_building_target(target):
		_set_info_rows([
			{"label": "Type", "value": _get_building_type_label(target)},
			{"label": "Ownership", "value": _get_building_ownership_text(target)},
			{"label": "Jurisdiction", "value": _get_building_jurisdiction_text(target)},
			{"label": "Access", "value": _get_building_status_text(target), "value_color": _get_building_access_color(target)},
		])
		return
	if target is Node and target.is_in_group("mining_resource"):
		_set_info_rows([
			{"label": "Type", "value": _get_target_type_text(target)},
			{"label": "Tool", "value": _get_string_property(target, "required_tool_label", "Tool")},
			{"label": "Skill", "value": "Mining %d" % _get_int_property(target, "required_mining_level", 0)},
			{"label": "Status", "value": _get_target_state_text(target)},
		])
		return
	if target is Node and target.is_in_group("scavenging_resource"):
		var charges := _get_int_property(target, "current_charges", -1)
		_set_info_rows([
			{"label": "Type", "value": _get_target_type_text(target)},
			{"label": "Difficulty", "value": "Scavenging %d" % _get_int_property(target, "scavenging_difficulty", 0)},
			{"label": "Remaining", "value": "Unknown" if charges < 0 else str(charges)},
			{"label": "Status", "value": _get_target_state_text(target)},
		])
		return
	if target is Node and target.is_in_group("world_container"):
		_set_info_rows([
			{"label": "Type", "value": _get_target_type_text(target)},
			{"label": "Ownership", "value": _get_target_owner_text(target)},
			{"label": "Lock", "value": "Locked" if bool(target.get("is_locked")) else "Open"},
			{"label": "Status", "value": _get_target_state_text(target)},
		])
		return
	if target is Node and target.is_in_group("world_item"):
		var quantity := _get_int_property(target, "quantity", 1)
		_set_info_rows([
			{"label": "Type", "value": _get_target_type_text(target)},
			{"label": "Ownership", "value": _get_target_owner_text(target)},
			{"label": "Quantity", "value": str(maxi(quantity, 1))},
			{"label": "Status", "value": _get_target_state_text(target)},
		])
		return
	_set_info_rows([
		{"label": "Type", "value": _get_target_type_text(target)},
		{"label": "Ownership", "value": _get_target_owner_text(target)},
		{"label": "Action", "value": _get_target_requirement_text(target)},
		{"label": "Status", "value": _get_target_state_text(target)},
	])


func _set_info_rows(rows: Array) -> void:
	for index in range(info_rows.size()):
		var row := info_rows[index]
		if row == null:
			continue
		row.visible = index < rows.size()
		if index >= rows.size():
			continue
		_set_info_row(info_labels[index], info_values[index], rows[index])


func _set_info_row(label: Label, value_label: Label, data: Dictionary) -> void:
	_set_row_label(label, str(data.get("label", "-")))
	if label != null:
		label.add_theme_color_override("font_color", data.get("label_color", INFO_LABEL_COLOR))
	if value_label != null:
		value_label.text = str(data.get("value", "-"))
		value_label.add_theme_color_override("font_color", data.get("value_color", INFO_VALUE_COLOR))


func _set_row_label(label: Label, text: String) -> void:
	if label == null:
		return
	label.text = text
	label.tooltip_text = ""
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _clear_bar_values() -> void:
	hunger_value.text = ""
	blood_value.text = ""
	hp_value.text = ""
	fatigue_value.text = ""
	_update_fill_bar(hunger_bar_stack, hunger_fill, 0.0, Color(0.47, 0.78, 0.43, 1.0))
	_update_fill_bar(blood_bar_stack, blood_fill, 0.0, Color(0.47, 0.78, 0.43, 1.0))
	_update_blood_bleed_glow(0.0)
	_update_hp_bar_visuals(0.0, 0.0, 0.0, 1.0)
	_update_fill_bar(fatigue_bar_stack, fatigue_fill, 0.0, Color(0.47, 0.78, 0.43, 1.0))


func _get_target_display_name(target) -> String:
	if target is HumanoidCharacter:
		return target.member_name
	if target is WorldActor:
		return (target as WorldActor).member_name
	if target is Node and target.is_in_group("world_item"):
		var definition = target.get("item_definition")
		if definition != null:
			var item_name := _get_string_property(definition, "display_name", "Item")
			var quantity := _get_int_property(target, "quantity", 1)
			return item_name if quantity <= 1 else "%s x%d" % [item_name, quantity]
	var display_name := _get_string_property(target, "display_name", "")
	if not display_name.is_empty():
		return display_name
	if target is Node:
		return target.name.capitalize()
	return "World Target"


func _get_target_subtitle(target) -> String:
	if target == null:
		return ""
	if _is_building_target(target):
		var settlement_name := _get_building_settlement_name(target)
		return settlement_name if not settlement_name.is_empty() else "Building"
	if target.has_method("get_owner_faction_name"):
		var owner_text := str(target.call("get_owner_faction_name"))
		if not owner_text.is_empty():
			return "Owned by %s" % owner_text
	if target is Node and target.is_in_group("mining_resource"):
		return "Mining resource"
	if target is Node and target.is_in_group("scavenging_resource"):
		return "Scavenging site"
	if target is Node and target.is_in_group("world_container"):
		return "Storage"
	if target is Node and target.is_in_group("world_item"):
		return "Dropped item"
	return "World object"


func _get_target_detail(target) -> String:
	if target == null:
		return ""
	if _is_building_target(target):
		return ""
	if target is Node and target.is_in_group("mining_resource"):
		var tool_label := _get_string_property(target, "required_tool_label", "Tool")
		var required_level := _get_int_property(target, "required_mining_level", 0)
		return "%s required | Mining %d+" % [tool_label, required_level]
	if target is Node and target.is_in_group("scavenging_resource"):
		if target.has_method("is_depleted") and target.is_depleted():
			return "Picked clean"
		var charges := _get_int_property(target, "current_charges", -1)
		return "Charges unknown" if charges < 0 else "%d searches left" % charges
	if target is Node and target.is_in_group("world_container"):
		var locked := bool(target.get("is_locked"))
		return "Locked" if locked else "Can be opened"
	if target is Node and target.is_in_group("world_item"):
		var owner_text := _get_target_subtitle(target)
		return owner_text if owner_text != "Dropped item" else "On the ground"
	if target is Node and target.has_method("get_world_context_actions"):
		var actions: Array = target.get_world_context_actions(null)
		return "No available actions" if actions.is_empty() else "Context actions available"
	return "Right-click for context actions"


func _get_target_type_text(target) -> String:
	if _is_building_target(target):
		return _get_building_type_label(target)
	if target is Node and target.is_in_group("mining_resource"):
		return "Mining vein"
	if target is Node and target.is_in_group("scavenging_resource"):
		return "Scavenge"
	if target is Node and target.is_in_group("world_container"):
		return "Container"
	if target is Node and target.is_in_group("world_item"):
		return "Item"
	if target is Node and target.is_in_group("sleepable_bed"):
		return "Bed"
	if target is Node and target.is_in_group("sittable_seat"):
		return "Seat"
	return "Object"


func _get_target_owner_text(target) -> String:
	if _is_building_target(target):
		var building_owner := _get_building_owner_text(target)
		return "None" if building_owner.is_empty() else building_owner
	if target != null and target.has_method("get_owner_faction_name"):
		var owner_text := str(target.call("get_owner_faction_name"))
		if not owner_text.is_empty():
			return owner_text
	var owner_property := _get_string_property(target, "owner_faction_name", "")
	return "None" if owner_property.is_empty() else owner_property


func _get_target_requirement_text(target) -> String:
	if target is Node and target.is_in_group("mining_resource"):
		var tool_label := _get_string_property(target, "required_tool_label", "Tool")
		var required_level := _get_int_property(target, "required_mining_level", 0)
		return "%s | Mining %d" % [tool_label, required_level]
	if target is Node and target.is_in_group("scavenging_resource"):
		return "Scavenging %d" % _get_int_property(target, "scavenging_difficulty", 0)
	if target is Node and target.is_in_group("world_container"):
		return "Unlock" if bool(target.get("is_locked")) else "Open"
	if target is Node and target.is_in_group("world_item"):
		return "Inventory space"
	if target is Node and target.has_method("get_world_context_actions"):
		return "Context action"
	return "None"


func _get_target_state_text(target) -> String:
	if _is_building_target(target):
		return _get_building_status_text(target)
	if target is Node and target.is_in_group("mining_resource"):
		return "Mineable"
	if target is Node and target.is_in_group("scavenging_resource"):
		if target.has_method("is_depleted") and target.is_depleted():
			return "Depleted"
		var charges := _get_int_property(target, "current_charges", -1)
		return "Unknown" if charges < 0 else "%d charges" % charges
	if target is Node and target.is_in_group("world_container"):
		return "Locked" if bool(target.get("is_locked")) else "Openable"
	if target is Node and target.is_in_group("world_item"):
		var quantity := _get_int_property(target, "quantity", 1)
		return "Single" if quantity <= 1 else "x%d" % quantity
	if target is Node and target.has_method("get_world_context_actions"):
		var actions: Array = target.get_world_context_actions(null)
		return "No actions" if actions.is_empty() else "%d actions" % actions.size()
	return _get_target_state_label(target).capitalize()


func _get_target_state_label(target) -> String:
	if _is_building_target(target):
		var owner_text := _get_building_owner_text(target)
		return owner_text if not owner_text.is_empty() else "Unowned"
	if target is Node and target.is_in_group("mining_resource"):
		return "VEIN"
	if target is Node and target.is_in_group("scavenging_resource"):
		if target.has_method("is_depleted") and target.is_depleted():
			return "DEPLETED"
		return "SCRAP"
	if target is Node and target.is_in_group("world_container"):
		return "LOCKED" if bool(target.get("is_locked")) else "CACHE"
	if target is Node and target.is_in_group("world_item"):
		return "OWNED" if not _get_string_property(target, "owner_faction_name", "").is_empty() else "ITEM"
	if target is Node and target.is_in_group("sleepable_bed"):
		return "BED"
	if target is Node and target.is_in_group("sittable_seat"):
		return "SEAT"
	return "OBJECT"


func _get_target_state_color(target) -> Color:
	if _is_building_target(target):
		return Color(0.78, 0.66, 0.42, 1.0) if not _get_building_owner_text(target).is_empty() else Color(0.66, 0.62, 0.52, 1.0)
	var state := _get_target_state_label(target)
	match state:
		"LOCKED", "OWNED":
			return Color(0.83, 0.52, 0.24, 1.0)
		"DEPLETED":
			return Color(0.46, 0.44, 0.4, 1.0)
		"ITEM", "CACHE":
			return Color(0.78, 0.66, 0.42, 1.0)
		_:
			return Color(0.66, 0.62, 0.52, 1.0)


func _is_building_target(target) -> bool:
	return target is WorldBuilding or (target is Node and target.is_in_group("world_building"))


func _get_ancestor_facility(target) -> SettlementFacility:
	if not (target is Node):
		return null
	var current: Node = (target as Node).get_parent()
	while current != null:
		if current is SettlementFacility:
			return current as SettlementFacility
		current = current.get_parent()
	return null


func _get_building_type_label(target) -> String:
	var facility := _get_ancestor_facility(target)
	if facility != null:
		var facility_type := _get_string_property(facility, "facility_type", "")
		if not facility_type.is_empty() and facility_type != "generic":
			return _format_building_type_label(facility_type)
	if target != null and target.has_method("get_building_type_label"):
		var label := str(target.call("get_building_type_label"))
		if not label.is_empty():
			return label
	var building_type := _get_string_property(target, "building_type", "home")
	return _format_building_type_label(building_type)


func _format_building_type_label(type_id: String) -> String:
	match type_id:
		"home", "housing":
			return "Home"
		"bar":
			return "Bar"
		"tavern":
			return "Tavern"
		"shop":
			return "Shop"
		"weapon_shop":
			return "Weapon Shop"
		"armor_shop":
			return "Armor Shop"
		"travel_shop":
			return "Travel Shop"
		"potion_shop":
			return "Potion Shop"
		"jail", "police":
			return "Jail"
		"storage":
			return "Storage"
		"guard":
			return "Guard Post"
		"farm":
			return "Farm"
		"mine":
			return "Mine"
		"social":
			return "Social"
		_:
			return "Building"


func _get_building_owner_text(target) -> String:
	if target != null and target.has_method("get_owner_faction_name"):
		var owner_text := str(target.call("get_owner_faction_name"))
		if not owner_text.is_empty():
			return owner_text
	return _get_string_property(target, "owner_faction_name", "")


func _get_building_ownership_text(target) -> String:
	if target != null and target.has_method("get_occupancy_label"):
		var occupancy := str(target.call("get_occupancy_label"))
		if not occupancy.is_empty():
			return occupancy
	var owner_text := _get_building_owner_text(target)
	return owner_text if not owner_text.is_empty() else "None"


func _get_building_jurisdiction_text(target) -> String:
	if target != null and target.has_method("get_jurisdiction_faction_name"):
		var jurisdiction := str(target.call("get_jurisdiction_faction_name"))
		if not jurisdiction.is_empty():
			return jurisdiction
	return "None"


func _get_building_settlement_name(target) -> String:
	if target != null and target.has_method("get_jurisdiction_display_name"):
		return str(target.call("get_jurisdiction_display_name"))
	return ""


func _get_building_status_text(target) -> String:
	var focused_actor := _get_focused_party_member()
	if focused_actor != null and target != null and target.has_method("get_access_state_label_for_actor"):
		return str(target.call("get_access_state_label_for_actor", focused_actor, _get_world_time_minutes()))
	if target != null and target.has_method("get_access_state_label"):
		return str(target.call("get_access_state_label", _get_world_time_minutes()))
	return "Active" if not _get_building_owner_text(target).is_empty() else "Unowned"


func _get_building_access_color(target) -> Color:
	var focused_actor := _get_focused_party_member()
	if focused_actor != null and target != null and target.has_method("is_actor_trespassing_now"):
		if bool(target.call("is_actor_trespassing_now", focused_actor, _get_world_time_minutes())):
			return INFO_RESTRICTED_COLOR
	return INFO_VALUE_COLOR


func _get_focused_party_member() -> WorldActor:
	if root_scene == null:
		return null
	var party_manager := root_scene.get_node_or_null("PartyManager") as PartyManager
	if party_manager == null or party_manager.selected_members.is_empty():
		return null
	return party_manager.selected_members[0] as WorldActor


func _get_world_time_minutes() -> int:
	var world_time := root_scene.get_node_or_null("GameBootstrap/WorldTimeController") as WorldTimeController if root_scene != null else null
	return world_time.get_absolute_minute() if world_time != null else -1


func _get_string_property(target, property_name: String, fallback: String = "") -> String:
	if target == null:
		return fallback
	var value = target.get(property_name)
	if value == null:
		return fallback
	var text := str(value)
	return fallback if text.is_empty() else text


func _get_int_property(target, property_name: String, fallback: int = 0) -> int:
	if target == null:
		return fallback
	var value = target.get(property_name)
	if value == null:
		return fallback
	return int(value)


func _has_valid_current_target() -> bool:
	return current_target != null and is_instance_valid(current_target)


func _target_is_player_party_member(target) -> bool:
	return target != null and target.has_method("is_player_party_member") and target.is_player_party_member()


func _set_target_inspected(target, inspected: bool) -> void:
	if target != null and is_instance_valid(target) and target.has_method("set_inspected"):
		target.set_inspected(inspected)


func _target_can_open_skills() -> bool:
	return _has_valid_current_target() and current_target is WorldActor


func _target_can_open_jobs() -> bool:
	return _has_valid_current_target() and current_target is WorldActor


func _target_can_order_from_waiter(target: WorldActor) -> bool:
	if target == null or not target.is_player_party_member() or not target.has_method("is_sitting") or not target.is_sitting():
		return false
	var service_area := _get_bar_service_area_for_seated_actor(target)
	if service_area == null:
		return false
	if service_area.has_method("can_call_waiter_for_customer"):
		return bool(service_area.call("can_call_waiter_for_customer", target))
	return service_area.has_method("has_waiter_service") and bool(service_area.call("has_waiter_service"))


func _get_bar_service_area_for_seated_actor(target: WorldActor) -> BarServiceArea:
	if target == null or not target.has_method("get_current_seat_target"):
		return null
	var seat = target.call("get_current_seat_target")
	if seat != null and is_instance_valid(seat) and seat.has_method("get_bar_service_area"):
		return seat.call("get_bar_service_area") as BarServiceArea
	return null


func _on_skills_button_pressed() -> void:
	if not _target_can_open_skills():
		return
	_ensure_skills_window()
	skills_window.call("show_for_actor", current_target)


func _ensure_skills_window() -> void:
	if skills_window != null and is_instance_valid(skills_window):
		return
	skills_window = CHARACTER_SKILLS_WINDOW_SCRIPT.new() as Control
	skills_window.name = "CharacterSkillsWindow"
	hud_layer.add_child(skills_window)
	skills_window.visible = false


func _on_jobs_button_pressed() -> void:
	if not _target_can_open_jobs():
		return
	_ensure_jobs_window()
	jobs_window.call("show_for_actor", current_target)


func _ensure_jobs_window() -> void:
	if jobs_window != null and is_instance_valid(jobs_window):
		return
	jobs_window = CHARACTER_JOBS_WINDOW_SCRIPT.new() as Control
	jobs_window.name = "CharacterJobsWindow"
	hud_layer.add_child(jobs_window)
	if jobs_window.has_method("setup"):
		jobs_window.call("setup", root_scene)
	jobs_window.visible = false


func _update_hp_bar_visuals(current_hp: float, open_cut: float, bandaged_cut: float, max_hp: float, blunt_damage: float = 0.0) -> void:
	if hp_bar_stack == null:
		return
	var total_width := hp_bar_stack.size.x
	if total_width <= 0.0:
		total_width = maxf(hp_bar_stack.custom_minimum_size.x, 160.0)
	var total_height := hp_bar_stack.size.y
	if total_height <= 0.0:
		total_height = maxf(hp_bar_stack.custom_minimum_size.y, 14.0)
	var safe_max_hp := maxf(max_hp, 1.0)
	var health_width := total_width * clampf(current_hp / safe_max_hp, 0.0, 1.0)
	var bandaged_width := total_width * clampf(bandaged_cut / safe_max_hp, 0.0, 1.0)
	var cut_width := total_width * clampf(open_cut / safe_max_hp, 0.0, 1.0)
	var occupied_width := total_width * clampf((safe_max_hp - blunt_damage) / safe_max_hp, 0.0, 1.0)
	var max_cut_start := maxf(0.0, occupied_width - cut_width)
	var bandaged_start := minf(health_width, occupied_width)
	var cut_start := minf(bandaged_start + bandaged_width, max_cut_start)
	hp_health_fill.position = Vector2.ZERO
	hp_health_fill.size = Vector2(maxf(0.0, minf(health_width, occupied_width)), total_height)
	hp_bandaged_fill.visible = bandaged_width > 0.5
	hp_bandaged_fill.position = Vector2(bandaged_start, 0.0)
	hp_bandaged_fill.size = Vector2(maxf(0.0, minf(bandaged_width, maxf(0.0, occupied_width - bandaged_start))), total_height)
	hp_cut_outline.visible = cut_width > 0.5
	hp_cut_outline.position = Vector2(cut_start, 0.0)
	hp_cut_outline.size = Vector2(maxf(0.0, minf(cut_width, maxf(0.0, occupied_width - cut_start))), total_height)


func _update_fill_bar(bar_stack: Control, fill_rect: ColorRect, ratio: float, color: Color) -> void:
	if bar_stack == null or fill_rect == null:
		return
	var total_width := bar_stack.size.x
	if total_width <= 0.0:
		total_width = maxf(bar_stack.custom_minimum_size.x, 160.0)
	var total_height := bar_stack.size.y
	if total_height <= 0.0:
		total_height = maxf(bar_stack.custom_minimum_size.y, 14.0)
	fill_rect.color = color
	fill_rect.position = Vector2.ZERO
	fill_rect.size = Vector2(total_width * clampf(ratio, 0.0, 1.0), total_height)


func _update_vital_fluid_blink(target: WorldActor, base_color: Color) -> void:
	if blood_fill == null:
		return
	if target == null or not bool(target.get("is_focused")):
		return
	var strength := clampf(target.get_vital_fluid_blink_strength(), 0.0, 1.0)
	if strength <= 0.0:
		return
	var pulse_rate := maxf(0.05, target.get_vital_fluid_blink_speed())
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * TAU * pulse_rate)
	var blink_color := target.get_vital_fluid_blink_color(Color(0.72, 0.64, 0.24, 1.0))
	blood_fill.color = base_color.lerp(blink_color, lerpf(0.35, 0.9, pulse) * strength)


func _setup_blood_bleed_glow() -> void:
	if blood_bar_stack == null:
		return
	blood_bleed_glow = Panel.new()
	blood_bleed_glow.name = "BloodBleedGlow"
	blood_bleed_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood_bleed_glow_style.bg_color = Color(1.0, 0.0, 0.0, 0.0)
	_blood_bleed_glow_style.border_width_left = 2
	_blood_bleed_glow_style.border_width_top = 2
	_blood_bleed_glow_style.border_width_right = 2
	_blood_bleed_glow_style.border_width_bottom = 2
	_blood_bleed_glow_style.corner_radius_top_left = 4
	_blood_bleed_glow_style.corner_radius_top_right = 4
	_blood_bleed_glow_style.corner_radius_bottom_right = 4
	_blood_bleed_glow_style.corner_radius_bottom_left = 4
	_blood_bleed_glow_style.shadow_size = 5
	blood_bleed_glow.add_theme_stylebox_override("panel", _blood_bleed_glow_style)
	blood_bleed_glow.visible = false
	blood_bar_stack.add_child(blood_bleed_glow)
	blood_bar_stack.move_child(blood_value, blood_bar_stack.get_child_count() - 1)


func _update_blood_bleed_glow(bleed_rate: float, glow_color: Color = Color(1.0, 0.04, 0.02, 1.0)) -> void:
	if blood_bleed_glow == null or blood_bar_stack == null:
		return
	if bleed_rate <= 0.01:
		blood_bleed_glow.visible = false
		return
	var blood_loss_per_second := bleed_rate * NpcRules.BLEED_TO_BLOOD_RATE
	var severity := clampf(blood_loss_per_second / BLOOD_GLOW_CRITICAL_LOSS_PER_SECOND, 0.0, 1.0)
	var pulse_rate := lerpf(0.55, 0.8, severity)
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * TAU * pulse_rate)
	var minimum_alpha := lerpf(0.04, 0.82, severity)
	var maximum_alpha := lerpf(0.48, 1.0, severity)
	var alpha := lerpf(minimum_alpha, maximum_alpha, pulse)
	_blood_bleed_glow_style.border_color = Color(glow_color.r, glow_color.g, glow_color.b, alpha)
	_blood_bleed_glow_style.shadow_color = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.7)
	blood_bleed_glow.position = Vector2(-3.0, -3.0)
	blood_bleed_glow.size = blood_bar_stack.size + Vector2(6.0, 6.0)
	blood_bleed_glow.visible = true


func _get_stage_color(stage: int, good_stage: int, warning_stage: int, danger_stage: int) -> Color:
	if stage == danger_stage:
		return Color(0.83, 0.24, 0.24, 1.0)
	if stage == warning_stage:
		return Color(0.82, 0.69, 0.22, 1.0)
	if stage == good_stage:
		return Color(0.47, 0.78, 0.43, 1.0)
	return Color(0.47, 0.78, 0.43, 1.0)


func _get_ratio_color(ratio: float) -> Color:
	if ratio <= 0.33:
		return Color(0.83, 0.24, 0.24, 1.0)
	if ratio <= 0.66:
		return Color(0.82, 0.69, 0.22, 1.0)
	return Color(0.47, 0.78, 0.43, 1.0)


func _get_life_state_color(life_state: int) -> Color:
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
