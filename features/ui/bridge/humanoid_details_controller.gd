extends Node

class_name HumanoidDetailsController

const SERVICE_ID := &"humanoid_details"

signal inspector_action_requested(target, action_key: String)

const CHARACTER_SKILLS_WINDOW_SCRIPT = preload("res://features/ui/projection/character_skills_window.gd")
const CHARACTER_JOBS_WINDOW_SCRIPT = preload("res://features/ui/projection/character_jobs_window.gd")
const FACILITY_PEOPLE_PROJECTION_SCRIPT = preload("res://features/ui/projection/facility_people_projection.gd")

const BLOOD_GLOW_CRITICAL_LOSS_PER_SECOND := 8.0
const BAR_GOOD_COLOR := Color(0.47, 0.78, 0.43, 1.0)
const BAR_WARNING_COLOR := Color(0.82, 0.69, 0.22, 1.0)
const BAR_DANGER_COLOR := Color(0.83, 0.24, 0.24, 1.0)
const BAR_EMPTY_COLOR := Color(0.035, 0.035, 0.035, 1.0)
const FARM_HYDRATION_COLOR := Color(0.15, 0.56, 0.95, 1.0)
## The drained bar area shows the color the vital is heading toward, dimmed
## this much so the live fill still reads clearly on top of it.
const BAR_DRAIN_DIM := 0.45
## Food effect rate (hunger points/second) that reads as maximum glow strength.
## Bread (150 points over 180s) lands at ~0.83, just over half strength.
const HUNGER_GLOW_STRONG_NUTRITION_PER_SECOND := 1.5
const NEED_BAR_RESPONSE_SECONDS := 0.14
const NEED_BAR_SNAP_THRESHOLD := 0.35
const ACTION_ATTACK := "attack"
const ACTION_CARRY := "carry"
const ACTION_FINISH_OFF := "finish_off"
const ACTION_FARM_TILL := "farm_till"
const ACTION_HEAL := "heal"
const ACTION_INVENTORY := "inventory"
const ACTION_JOBS := "jobs"
const ACTION_MINE := "mine"
const ACTION_OPEN_CONTAINER := "open_container"
const ACTION_PEOPLE := "people"
const ACTION_ORDER := "order"
const ACTION_PICKUP_ITEM := "pickup_item"
const ACTION_SKILLS := "skills"
const ACTION_STAND_UP := "stand_up"
const ACTION_TALK := "talk"
const ACTION_TRADE := "trade"
const ACTION_UNLOCK_CONTAINER := "unlock_container"
const ACTION_WAKE_UP := "wake_up"
const WORLD_ACTION_PREFIX := "world:"
const DELETE_FIELD_ACTION := WORLD_ACTION_PREFIX + "farm_plot|delete"
const DESTRUCTIVE_ACTION_COLOR := Color(0.96, 0.28, 0.24, 1.0)
const INFO_LABEL_COLOR := Color(0.58, 0.56, 0.5, 1.0)
const INFO_VALUE_COLOR := Color(0.8, 0.75, 0.62, 1.0)
const INFO_RESTRICTED_COLOR := Color(0.94, 0.34, 0.28, 1.0)
const INFO_CRIME_COLOR := Color(1.0, 0.16, 0.12, 1.0)
const INFO_JAILED_COLOR := Color(0.95, 0.58, 0.24, 1.0)

var root_scene: Node
var _context: BootstrapContext
var hud_layer: CanvasLayer
var details_panel: Control
var name_label: Label
var faction_label: Label
var work_label: Label
var state_label: Label
var tool_requirement_label: Label
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
var hunger_nutrition_glow: Panel
var _hunger_nutrition_glow_style := StyleBoxFlat.new()
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
var farm_growth_row: Control
var farm_growth_label: Label
var farm_growth_stack: Control
var farm_growth_fill: ColorRect
var farm_growth_value: Label
var farm_hydration_row: Control
var farm_hydration_label: Label
var farm_hydration_stack: Control
var farm_hydration_fill: ColorRect
var farm_hydration_value: Label
var action_row: Control
var action_buttons: Array[Button] = []
var _farm_crop_menu: PopupMenu
var _farm_crop_menu_target
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
var facility_people_projection: FacilityPeopleProjection
var current_target
var _current_target_world_position := Vector3.ZERO
var _has_current_target_world_position := false
var _initialized := false
var _displayed_hunger_ratio := NAN
var _displayed_fatigue_ratio := NAN
var _displayed_hunger_stage := -1
var _displayed_fatigue_stage := -1
var _ui_delta := 0.0


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	hud_layer = context.hud_layer
	_context = context
	facility_people_projection = FACILITY_PEOPLE_PROJECTION_SCRIPT.new() as FacilityPeopleProjection
	facility_people_projection.setup(context.get_optional(FacilityPeopleProjection.ASSIGNMENT_SERVICE_ID))
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	add_to_group("humanoid_details_controller")
	if root_scene != null:
		if hud_layer == null and root_scene != null:
			hud_layer = root_scene.get_node_or_null("GameHUD")
		_do_initialize()


func _process(delta: float) -> void:
	if not _initialized:
		return
	_ui_delta = clampf(delta / maxf(Engine.time_scale, 0.001), 0.0, 0.1)
	_update_panel()


func inspect_humanoid(target) -> void:
	inspect_target(target)


func inspect_target(target) -> void:
	_inspect_target(target, false, Vector3.ZERO)


func inspect_target_at(target, world_position: Vector3) -> void:
	_inspect_target(target, true, world_position)


func _inspect_target(target, has_world_position: bool, world_position: Vector3) -> void:
	if current_target == target:
		_has_current_target_world_position = has_world_position
		_current_target_world_position = world_position
		if has_world_position and target != null and target.has_method("begin_inspection_at"):
			target.call("begin_inspection_at", world_position)
		_update_panel()
		return
	_set_target_inspected(current_target, false)
	current_target = target
	_has_current_target_world_position = has_world_position
	_current_target_world_position = world_position
	if has_world_position and target != null and target.has_method("begin_inspection_at"):
		target.call("begin_inspection_at", world_position)
	_reset_need_bar_display()
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
	tool_requirement_label = details_panel.get_node("Margin/DetailsVBox/ToolRequirement")
	hunger_label = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerLabel")
	hunger_bar_stack = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack")
	hunger_fill = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack/HungerFill")
	hunger_value = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack/HungerValue")
	_setup_hunger_nutrition_glow()
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
	farm_growth_row = details_panel.get_node("Margin/DetailsVBox/FarmGrowthRow")
	farm_growth_label = details_panel.get_node("Margin/DetailsVBox/FarmGrowthRow/GrowthLabel")
	farm_growth_stack = details_panel.get_node("Margin/DetailsVBox/FarmGrowthRow/GrowthBarFrame/GrowthBarStack")
	farm_growth_fill = details_panel.get_node("Margin/DetailsVBox/FarmGrowthRow/GrowthBarFrame/GrowthBarStack/GrowthFill")
	farm_growth_value = details_panel.get_node("Margin/DetailsVBox/FarmGrowthRow/GrowthBarFrame/GrowthBarStack/GrowthValue")
	farm_hydration_row = details_panel.get_node("Margin/DetailsVBox/FarmHydrationRow")
	farm_hydration_label = details_panel.get_node("Margin/DetailsVBox/FarmHydrationRow/HydrationLabel")
	farm_hydration_stack = details_panel.get_node("Margin/DetailsVBox/FarmHydrationRow/HydrationBarFrame/HydrationBarStack")
	farm_hydration_fill = details_panel.get_node("Margin/DetailsVBox/FarmHydrationRow/HydrationBarFrame/HydrationBarStack/HydrationFill")
	farm_hydration_value = details_panel.get_node("Margin/DetailsVBox/FarmHydrationRow/HydrationBarFrame/HydrationBarStack/HydrationValue")
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
	action_row = details_panel.get_node("Margin/DetailsVBox/ActionRow")
	_register_action_button("Margin/DetailsVBox/ActionRow/PrimaryActionButton")
	_register_action_button("Margin/DetailsVBox/ActionRow/SecondaryActionButton")
	_register_action_button("Margin/DetailsVBox/ActionRow/TertiaryActionButton")
	_register_action_button("Margin/DetailsVBox/ActionRow/QuaternaryActionButton")
	_register_action_button("Margin/DetailsVBox/ActionRow/JobsActionButton")
	_register_action_button("Margin/DetailsVBox/ActionRow/SixthActionButton")
	details_panel.visible = true
	_initialized = true
	_update_panel()


func _register_action_button(path: String) -> void:
	var button := details_panel.get_node_or_null(path) as Button
	if button == null:
		return
	button.pressed.connect(_on_action_button_pressed.bind(button))
	button.gui_input.connect(_on_action_button_gui_input.bind(button))
	action_buttons.append(button)


func _update_panel() -> void:
	if details_panel == null:
		return
	if current_target != null and not is_instance_valid(current_target):
		current_target = null
		_reset_need_bar_display()
	if current_target == null:
		_update_empty_panel()
		return
	if current_target is WorldActor:
		_update_humanoid_panel(current_target as WorldActor)
		return
	_update_world_target_panel(current_target)


func _update_empty_panel() -> void:
	_set_vitals_visible(false)
	_set_farm_rows_visible(false)
	_set_info_rows_visible(false)
	faction_label.visible = true
	work_label.visible = true
	name_label.text = "No target"
	faction_label.text = "Left-click a person, item, or resource"
	work_label.text = "Inspector ready"
	state_label.text = "IDLE"
	state_label.modulate = Color(0.58, 0.55, 0.5, 1.0)
	_set_actions([])


func _update_humanoid_panel(target: WorldActor) -> void:
	_set_vitals_visible(true)
	_set_farm_rows_visible(false)
	faction_label.visible = true
	work_label.visible = true
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
		var hunger_stage := target.get_hunger_stage()
		var hunger_stage_label: String = target.get_hunger_stage_label()
		hunger_value.text = "%s %d / 100" % [hunger_stage_label, int(round(target.hunger))]
		_displayed_hunger_ratio = _smooth_need_ratio(_displayed_hunger_ratio, target.hunger / 100.0, _displayed_hunger_stage, hunger_stage)
		_displayed_hunger_stage = hunger_stage
		_update_fill_bar(hunger_bar_stack, hunger_fill, _displayed_hunger_ratio, _get_stage_color(hunger_stage, NpcRules.HungerStage.WELL_NOURISHED, NpcRules.HungerStage.HUNGRY, NpcRules.HungerStage.STARVING), _get_stage_drain_color(hunger_stage, NpcRules.HungerStage.WELL_NOURISHED, NpcRules.HungerStage.HUNGRY, NpcRules.HungerStage.STARVING))
		_update_hunger_nutrition_glow(target.get_food_effect_rate() if target.has_method("get_food_effect_rate") else 0.0)
	else:
		_displayed_hunger_ratio = NAN
		_displayed_hunger_stage = -1
		_update_hunger_nutrition_glow(0.0)
	blood_value.text = "%d / %d" % [int(round(target.blood)), int(round(target.max_blood))]
	var vital_fluid_ratio := target.blood / maxf(target.max_blood, 1.0)
	var vital_fluid_color := target.get_vital_fluid_bar_color(_get_ratio_color(vital_fluid_ratio))
	_update_fill_bar(blood_bar_stack, blood_fill, vital_fluid_ratio, vital_fluid_color, _get_ratio_drain_color(vital_fluid_ratio))
	_update_vital_fluid_blink(target, vital_fluid_color)
	_update_blood_bleed_glow(target.get_bleed_rate() if target.has_method("get_bleed_rate") else 0.0, target.get_vital_fluid_glow_color(Color(1.0, 0.04, 0.02, 1.0)))
	_update_hp_bar_visuals(target.hp, target.get_open_cut_damage(), target.get_bandaged_cut_damage(), target.max_hp, target.get_blunt_damage())
	hp_value.text = "%d / %d" % [int(round(target.hp)), int(round(target.max_hp))]
	if target.shows_fatigue_vital():
		var fatigue_stage := target.get_fatigue_stage()
		var fatigue_stage_label: String = target.get_fatigue_stage_label()
		fatigue_value.text = "%s %d / 100" % [fatigue_stage_label, int(round(target.fatigue))]
		_displayed_fatigue_ratio = _smooth_need_ratio(_displayed_fatigue_ratio, target.fatigue / 100.0, _displayed_fatigue_stage, fatigue_stage)
		_displayed_fatigue_stage = fatigue_stage
		_update_fill_bar(fatigue_bar_stack, fatigue_fill, _displayed_fatigue_ratio, _get_stage_color(fatigue_stage, NpcRules.FatigueStage.WELL_RESTED, NpcRules.FatigueStage.WINDED, NpcRules.FatigueStage.EXHAUSTED), _get_stage_drain_color(fatigue_stage, NpcRules.FatigueStage.WELL_RESTED, NpcRules.FatigueStage.WINDED, NpcRules.FatigueStage.EXHAUSTED))
	else:
		_displayed_fatigue_ratio = NAN
		_displayed_fatigue_stage = -1
	_set_actions(_get_humanoid_actions(target))


func _get_humanoid_info_rows(target: WorldActor) -> Array:
	var rows: Array = []
	var law_status := _get_humanoid_law_status(target)
	if not law_status.is_empty():
		rows.append({"label": "Law", "value": law_status, "value_color": _get_humanoid_law_status_color(target)})
	var warrant_summary := _get_humanoid_law_field(target, "warrant_summary")
	if not warrant_summary.is_empty():
		rows.append({"label": "Warrant", "value": warrant_summary})
	var sentence_summary := _get_humanoid_law_field(target, "sentence_summary")
	if not sentence_summary.is_empty():
		rows.append({"label": "Sentence", "value": sentence_summary})
	while rows.size() > info_rows.size():
		rows.pop_back()
	return rows


func _get_humanoid_law_status(target: WorldActor) -> String:
	var caught_status := _get_humanoid_law_field(target, "status_label")
	if not caught_status.is_empty():
		return caught_status
	return _get_humanoid_law_field(target, "active_crime_label")


func _get_humanoid_law_status_color(target: WorldActor) -> Color:
	var kind := _get_humanoid_law_field(target, "status_kind")
	if kind == "jailed":
		return INFO_JAILED_COLOR
	if kind == "caught" or not _get_humanoid_law_field(target, "active_crime_label").is_empty():
		return INFO_CRIME_COLOR
	return INFO_VALUE_COLOR


func _get_humanoid_law_field(target: WorldActor, field: StringName) -> String:
	if target == null or not target.has_method("get_legal_status"):
		return ""
	var status = target.call("get_legal_status")
	return str(status.get(field)) if status != null else ""


## DETAILS PANEL RULE: this is player-facing game UI, never a debug dump.
## Do not expose class names, node names, script identifiers, generic Object /
## World Object labels, or placeholder Action / Status rows. Inspectable systems
## must provide concise authored language that describes what the player sees.
func _update_world_target_panel(target) -> void:
	if target != null and target.has_method("get_details_panel_data_at"):
		_update_farm_target_panel(target)
		return
	_set_vitals_visible(false)
	_set_farm_rows_visible(false)
	_set_info_rows_visible(true)
	_clear_bar_values()
	faction_label.visible = true
	work_label.visible = true
	name_label.text = _get_target_display_name(target)
	faction_label.text = _get_target_subtitle(target)
	work_label.text = _get_target_detail(target)
	state_label.text = _get_target_state_label(target)
	state_label.modulate = _get_target_state_color(target)
	_set_world_target_rows(target)
	_set_actions(_get_world_target_actions(target))


func _update_farm_target_panel(target) -> void:
	_set_vitals_visible(false)
	_set_info_rows_visible(false)
	var world_position: Vector3 = _current_target_world_position if _has_current_target_world_position else (target.global_position if target is Node3D else Vector3.ZERO)
	var data: Dictionary = target.call("get_details_panel_data_at", world_position)
	name_label.text = str(data.get("title", "Soil"))
	var subtitle := str(data.get("subtitle", ""))
	var detail := str(data.get("detail", ""))
	faction_label.text = subtitle
	faction_label.visible = not subtitle.is_empty()
	work_label.text = detail
	work_label.visible = not detail.is_empty()
	var crop_state := str(data.get("state", ""))
	state_label.text = crop_state.to_upper()
	state_label.modulate = _get_farm_state_color(crop_state)
	var tool_requirement := str(data.get("tool_requirement", ""))
	tool_requirement_label.text = tool_requirement
	tool_requirement_label.visible = not tool_requirement.is_empty()
	var show_crop_bars := bool(data.get("show_crop_bars", false))
	var show_growth_bar := bool(data.get("show_growth_bar", show_crop_bars))
	var show_resource_bar := bool(data.get("show_resource_bar", show_crop_bars))
	if farm_growth_row != null:
		farm_growth_row.visible = show_growth_bar
	if farm_hydration_row != null:
		farm_hydration_row.visible = show_resource_bar
	if show_growth_bar:
		var growth_ratio := clampf(float(data.get("growth_ratio", 0.0)), 0.0, 1.0)
		farm_growth_label.text = str(data.get("growth_label", "Growth"))
		farm_growth_value.text = str(data.get("growth_value_text", "%d%%" % int(round(growth_ratio * 100.0))))
		_update_fill_bar(farm_growth_stack, farm_growth_fill, growth_ratio, BAR_GOOD_COLOR)
	if show_resource_bar:
		var resource_ratio := clampf(float(data.get("resource_ratio", data.get("hydration_ratio", 0.0))), 0.0, 1.0)
		farm_hydration_label.text = str(data.get("resource_label", "Hydration"))
		farm_hydration_value.text = str(data.get("resource_value_text", "%d%%" % int(round(resource_ratio * 100.0))))
		_update_fill_bar(farm_hydration_stack, farm_hydration_fill, resource_ratio, FARM_HYDRATION_COLOR)
	var actions: Array = []
	if target.has_method("get_details_panel_actions_at"):
		actions = target.call("get_details_panel_actions_at", world_position, _get_focused_party_member()) \
				if target is Node and target.is_in_group("farm_plot") \
				else target.call("get_details_panel_actions_at", world_position)
	var routed_actions: Array = []
	for action_value in actions:
		var action: Dictionary = (action_value as Dictionary).duplicate()
		var key := str(action.get("key", ""))
		if key != "farm_crop_menu" and not key.begins_with(WORLD_ACTION_PREFIX):
			action["key"] = WORLD_ACTION_PREFIX + key
		routed_actions.append(action)
	_set_actions(routed_actions)


func _get_farm_state_color(crop_state: String) -> Color:
	match crop_state:
		"Alive":
			return BAR_GOOD_COLOR
		"Ready for Harvest":
			return Color(0.88, 0.72, 0.25, 1.0)
		"Dead":
			return BAR_DANGER_COLOR
		_:
			return Color(0.66, 0.62, 0.52, 1.0)


func _get_humanoid_actions(target: WorldActor) -> Array:
	var actions: Array = []
	if target.is_player_party_member():
		actions.append({"key": ACTION_INVENTORY, "label": "Inventory"})
		var placement = _context.get_optional(&"farm_placement") if _context != null else null
		if placement != null and placement.has_method("can_begin_manual_till") and bool(placement.call("can_begin_manual_till", target)):
			actions.append({"key": ACTION_FARM_TILL, "label": "Till"})
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
	if _is_building_target(target):
		actions.append({"key": ACTION_PEOPLE, "label": facility_people_projection.get_action_label(target)})
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
	if action_row != null:
		action_row.visible = not actions.is_empty()
	for index in range(action_buttons.size()):
		var button := action_buttons[index]
		if button == null:
			continue
		_set_action_button_destructive(button, false)
		if index >= actions.size():
			button.visible = false
			button.disabled = true
			button.set_meta("inspector_action_key", "")
			continue
		var action: Dictionary = actions[index]
		button.visible = true
		button.text = str(action.get("label", "Action"))
		button.disabled = bool(action.get("disabled", false))
		var action_key := str(action.get("key", ""))
		button.set_meta("inspector_action_key", action_key)
		_set_action_button_destructive(button, action_key == DELETE_FIELD_ACTION)


func _set_action_button_destructive(button: Button, destructive: bool) -> void:
	for color_name in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.remove_theme_color_override(color_name)
		if destructive:
			button.add_theme_color_override(color_name, DESTRUCTIVE_ACTION_COLOR)


func _on_action_button_pressed(button: Button) -> void:
	var action_key := str(button.get_meta("inspector_action_key", ""))
	var shift_armed := bool(button.get_meta("inspector_shift_armed", false))
	button.set_meta("inspector_shift_armed", false)
	if action_key.is_empty():
		return
	if action_key == WORLD_ACTION_PREFIX + "farm_plot|till" and shift_armed:
		action_key = WORLD_ACTION_PREFIX + "farm_plot|till_all"
	if action_key == "farm_crop_menu":
		_open_farm_crop_menu(button)
		return
	if action_key == ACTION_SKILLS:
		_on_skills_button_pressed()
		return
	if action_key == ACTION_JOBS:
		_on_jobs_button_pressed()
		return
	if action_key == ACTION_PEOPLE:
		_on_people_button_pressed()
		return
	if not _has_valid_current_target():
		return
	inspector_action_requested.emit(current_target, action_key)


func _on_action_button_gui_input(event: InputEvent, button: Button) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		button.set_meta("inspector_shift_armed", event.shift_pressed)


func _open_farm_crop_menu(anchor_button: Button) -> void:
	if not _has_valid_current_target() or not current_target.has_method("get_field_crop_options"):
		return
	if _farm_crop_menu == null or not is_instance_valid(_farm_crop_menu):
		_farm_crop_menu = PopupMenu.new()
		_farm_crop_menu.name = "FarmCropMenu"
		(hud_layer if hud_layer != null else details_panel).add_child(_farm_crop_menu)
		_farm_crop_menu.id_pressed.connect(_on_farm_crop_menu_selected)
	_farm_crop_menu.clear()
	_farm_crop_menu_target = current_target
	var options: Array = current_target.call("get_field_crop_options")
	for index in options.size():
		var option: Dictionary = options[index]
		_farm_crop_menu.add_radio_check_item(str(option.get("label", "Crop")), index)
		_farm_crop_menu.set_item_metadata(index, str(option.get("crop_id", "")))
		_farm_crop_menu.set_item_checked(index, bool(option.get("selected", false)))
	var menu_height := mini(360, maxi(44, options.size() * 30 + 12))
	var popup_position := Vector2i(
		roundi(anchor_button.global_position.x),
		roundi(anchor_button.global_position.y) - menu_height - 96
	)
	_farm_crop_menu.popup(Rect2i(popup_position, Vector2i(230, menu_height)))


func _on_farm_crop_menu_selected(item_id: int) -> void:
	if _farm_crop_menu == null or _farm_crop_menu_target == null \
			or not is_instance_valid(_farm_crop_menu_target):
		return
	var item_index := _farm_crop_menu.get_item_index(item_id)
	if item_index < 0:
		return
	var crop_id := str(_farm_crop_menu.get_item_metadata(item_index))
	inspector_action_requested.emit(_farm_crop_menu_target, WORLD_ACTION_PREFIX + "farm_policy|" + crop_id)


func _set_vitals_visible(is_visible: bool) -> void:
	for row in vital_rows:
		if row != null:
			row.visible = is_visible


func _set_farm_rows_visible(is_visible: bool) -> void:
	if farm_growth_row != null:
		farm_growth_row.visible = is_visible
	if farm_hydration_row != null:
		farm_hydration_row.visible = is_visible
	if not is_visible and tool_requirement_label != null:
		tool_requirement_label.visible = false


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
	_set_info_rows_visible(false)


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
	_reset_need_bar_display()
	hunger_value.text = ""
	blood_value.text = ""
	hp_value.text = ""
	fatigue_value.text = ""
	_update_fill_bar(hunger_bar_stack, hunger_fill, 0.0, BAR_GOOD_COLOR)
	_update_fill_bar(blood_bar_stack, blood_fill, 0.0, BAR_GOOD_COLOR)
	_update_blood_bleed_glow(0.0)
	_update_hunger_nutrition_glow(0.0)
	_update_hp_bar_visuals(0.0, 0.0, 0.0, 1.0)
	_update_fill_bar(fatigue_bar_stack, fatigue_fill, 0.0, BAR_GOOD_COLOR)


func _reset_need_bar_display() -> void:
	_displayed_hunger_ratio = NAN
	_displayed_fatigue_ratio = NAN
	_displayed_hunger_stage = -1
	_displayed_fatigue_stage = -1


func _smooth_need_ratio(displayed: float, authoritative: float, displayed_stage: int, authoritative_stage: int) -> float:
	var target := clampf(authoritative, 0.0, 1.0)
	if is_nan(displayed) or displayed_stage != authoritative_stage or absf(displayed - target) >= NEED_BAR_SNAP_THRESHOLD:
		return target
	var alpha := 1.0 - exp(-_ui_delta / NEED_BAR_RESPONSE_SECONDS)
	return lerpf(displayed, target, alpha)


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
	return "Unknown"


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
	return ""


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
		return ""
	return ""


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
	return ""


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
		return ""
	return ""


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
		return ""
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
	return ""


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
	return target is WorldBuilding or (target is Node and (target.is_in_group("world_building") or target.is_in_group("settlement_facility") or target.has_method("get_facility_id")))


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
	var world_time := _context.get_optional(WorldTimeController.SERVICE_ID) as WorldTimeController if _context != null else null
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
	if not _has_valid_current_target() or not current_target is WorldActor:
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


func _on_people_button_pressed() -> void:
	if not _has_valid_current_target() or not _is_building_target(current_target):
		return
	facility_people_projection.show_for_target(hud_layer, current_target)


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


func _update_fill_bar(bar_stack: Control, fill_rect: ColorRect, ratio: float, color: Color, drain_color: Color = BAR_EMPTY_COLOR) -> void:
	if bar_stack == null or fill_rect == null:
		return
	var total_width := bar_stack.size.x
	if total_width <= 0.0:
		total_width = maxf(bar_stack.custom_minimum_size.x, 160.0)
	var total_height := bar_stack.size.y
	if total_height <= 0.0:
		total_height = maxf(bar_stack.custom_minimum_size.y, 14.0)
	var drain_rect := _get_bar_drain_rect(bar_stack)
	drain_rect.color = drain_color
	drain_rect.position = Vector2.ZERO
	drain_rect.size = Vector2(total_width, total_height)
	fill_rect.color = color
	fill_rect.position = Vector2.ZERO
	fill_rect.size = Vector2(total_width * clampf(ratio, 0.0, 1.0), total_height)


## Full-width layer behind the fill so the drained area reads as the color the
## vital is decaying toward instead of the frame's black.
func _get_bar_drain_rect(bar_stack: Control) -> ColorRect:
	var drain_rect := bar_stack.get_node_or_null("DrainFill") as ColorRect
	if drain_rect == null:
		drain_rect = ColorRect.new()
		drain_rect.name = "DrainFill"
		drain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_stack.add_child(drain_rect)
		bar_stack.move_child(drain_rect, 0)
	return drain_rect


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


func _setup_hunger_nutrition_glow() -> void:
	if hunger_bar_stack == null:
		return
	hunger_nutrition_glow = Panel.new()
	hunger_nutrition_glow.name = "HungerNutritionGlow"
	hunger_nutrition_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hunger_nutrition_glow_style.bg_color = Color(0.0, 1.0, 0.0, 0.0)
	_hunger_nutrition_glow_style.border_width_left = 2
	_hunger_nutrition_glow_style.border_width_top = 2
	_hunger_nutrition_glow_style.border_width_right = 2
	_hunger_nutrition_glow_style.border_width_bottom = 2
	_hunger_nutrition_glow_style.corner_radius_top_left = 4
	_hunger_nutrition_glow_style.corner_radius_top_right = 4
	_hunger_nutrition_glow_style.corner_radius_bottom_right = 4
	_hunger_nutrition_glow_style.corner_radius_bottom_left = 4
	_hunger_nutrition_glow_style.shadow_size = 5
	hunger_nutrition_glow.add_theme_stylebox_override("panel", _hunger_nutrition_glow_style)
	hunger_nutrition_glow.visible = false
	hunger_bar_stack.add_child(hunger_nutrition_glow)
	hunger_bar_stack.move_child(hunger_value, hunger_bar_stack.get_child_count() - 1)


## Pulsing green ring around the hunger bar while a food effect is active;
## pulse speed and brightness scale with how strong the nutrition intake is.
func _update_hunger_nutrition_glow(nutrition_per_second: float, glow_color: Color = Color(0.36, 0.85, 0.3, 1.0)) -> void:
	if hunger_nutrition_glow == null or hunger_bar_stack == null:
		return
	if nutrition_per_second <= 0.001:
		hunger_nutrition_glow.visible = false
		return
	var strength := clampf(nutrition_per_second / HUNGER_GLOW_STRONG_NUTRITION_PER_SECOND, 0.0, 1.0)
	var pulse_rate := lerpf(0.35, 0.7, strength)
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.001 * TAU * pulse_rate)
	var minimum_alpha := lerpf(0.06, 0.55, strength)
	var maximum_alpha := lerpf(0.4, 0.95, strength)
	var alpha := lerpf(minimum_alpha, maximum_alpha, pulse)
	_hunger_nutrition_glow_style.border_color = Color(glow_color.r, glow_color.g, glow_color.b, alpha)
	_hunger_nutrition_glow_style.shadow_color = Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.7)
	hunger_nutrition_glow.position = Vector2(-3.0, -3.0)
	hunger_nutrition_glow.size = hunger_bar_stack.size + Vector2(6.0, 6.0)
	hunger_nutrition_glow.visible = true


func _get_stage_color(stage: int, good_stage: int, warning_stage: int, _danger_stage: int) -> Color:
	if stage == good_stage:
		return BAR_GOOD_COLOR
	if stage == warning_stage:
		return BAR_WARNING_COLOR
	return BAR_DANGER_COLOR


## Drained area previews the next stage down: green drains toward yellow,
## yellow toward red, red toward empty black.
func _get_stage_drain_color(stage: int, good_stage: int, warning_stage: int, _danger_stage: int) -> Color:
	if stage == good_stage:
		return BAR_WARNING_COLOR.darkened(BAR_DRAIN_DIM)
	if stage == warning_stage:
		return BAR_DANGER_COLOR.darkened(BAR_DRAIN_DIM)
	return BAR_EMPTY_COLOR


func _get_ratio_color(ratio: float) -> Color:
	if ratio <= 0.33:
		return BAR_DANGER_COLOR
	if ratio <= 0.66:
		return BAR_WARNING_COLOR
	return BAR_GOOD_COLOR


func _get_ratio_drain_color(ratio: float) -> Color:
	if ratio > 0.66:
		return BAR_WARNING_COLOR.darkened(BAR_DRAIN_DIM)
	if ratio > 0.33:
		return BAR_DANGER_COLOR.darkened(BAR_DRAIN_DIM)
	return BAR_EMPTY_COLOR


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
