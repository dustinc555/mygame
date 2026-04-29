extends Node

class_name HumanoidDetailsController

var root_scene: Node
var hud_layer: CanvasLayer
var details_panel: Control
var name_label: Label
var faction_label: Label
var state_label: Label
var stance_label: Label
var hunger_bar_stack: Control
var hunger_fill: ColorRect
var hunger_value: Label
var blood_bar_stack: Control
var blood_fill: ColorRect
var blood_value: Label
var hp_bar_stack: Control
var hp_health_fill: ColorRect
var hp_bandaged_fill: ColorRect
var hp_cut_outline: Control
var hp_value: Label
var fatigue_bar_stack: Control
var fatigue_fill: ColorRect
var fatigue_value: Label
var current_target
var _initialized := false


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	if root_scene != null:
		if hud_layer == null and root_scene != null:
			hud_layer = root_scene.get_node_or_null("GameHUD")
		_do_initialize()


func _process(_delta: float) -> void:
	if not _initialized:
		return
	_update_panel()


func inspect_humanoid(target) -> void:
	if current_target == target:
		return
	if current_target != null and current_target.has_method("set_inspected"):
		current_target.set_inspected(false)
	current_target = target
	if current_target != null and current_target.has_method("set_inspected"):
		current_target.set_inspected(true)
	_update_panel()


func clear_if_not_party_target() -> void:
	if current_target != null and not (current_target is PartyMember):
		inspect_humanoid(null)


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	if hud_layer == null:
		hud_layer = root_scene.get_node_or_null("GameHUD")
	if hud_layer == null:
		return
	details_panel = hud_layer.get_node_or_null("HudLayout/BottomHud/HumanoidDetailsPanel")
	if details_panel == null:
		return
	name_label = details_panel.get_node("Margin/DetailsVBox/Name")
	faction_label = details_panel.get_node("Margin/DetailsVBox/Faction")
	state_label = details_panel.get_node("Margin/DetailsVBox/State")
	stance_label = details_panel.get_node("Margin/DetailsVBox/Stance")
	hunger_bar_stack = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack")
	hunger_fill = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack/HungerFill")
	hunger_value = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBarFrame/HungerBarStack/HungerValue")
	blood_bar_stack = details_panel.get_node("Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack")
	blood_fill = details_panel.get_node("Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack/BloodFill")
	blood_value = details_panel.get_node("Margin/DetailsVBox/BloodRow/BloodBarFrame/BloodBarStack/BloodValue")
	hp_bar_stack = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack")
	hp_health_fill = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/HealthFill")
	hp_bandaged_fill = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/BandagedFill")
	hp_cut_outline = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/CutOutline")
	hp_value = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBarFrame/HpBarStack/HpValue")
	fatigue_bar_stack = details_panel.get_node("Margin/DetailsVBox/FatigueRow/FatigueBarFrame/FatigueBarStack")
	fatigue_fill = details_panel.get_node("Margin/DetailsVBox/FatigueRow/FatigueBarFrame/FatigueBarStack/FatigueFill")
	fatigue_value = details_panel.get_node("Margin/DetailsVBox/FatigueRow/FatigueBarFrame/FatigueBarStack/FatigueValue")
	details_panel.visible = false
	_initialized = true


func _update_panel() -> void:
	if details_panel == null:
		return
	if current_target == null:
		details_panel.visible = true
		name_label.text = ""
		faction_label.text = ""
		state_label.text = ""
		stance_label.text = ""
		_update_fill_bar(hunger_bar_stack, hunger_fill, 0.0, Color(0.47, 0.78, 0.43, 1.0))
		hunger_value.text = ""
		_update_fill_bar(blood_bar_stack, blood_fill, 0.0, Color(0.47, 0.78, 0.43, 1.0))
		blood_value.text = ""
		_update_hp_bar_visuals(0.0, 0.0, 0.0, 1.0)
		hp_value.text = ""
		_update_fill_bar(fatigue_bar_stack, fatigue_fill, 0.0, Color(0.47, 0.78, 0.43, 1.0))
		fatigue_value.text = ""
		return
	details_panel.visible = true
	name_label.text = current_target.member_name
	faction_label.text = "%s / %s" % [current_target.faction_name, current_target.squad_name]
	state_label.text = current_target.get_life_state_label()
	stance_label.text = current_target.get_stance_label()
	var hunger_stage_label: String = current_target.get_hunger_stage_label()
	hunger_value.text = "%s %d / 100" % [hunger_stage_label, int(round(current_target.hunger))]
	_update_fill_bar(hunger_bar_stack, hunger_fill, current_target.hunger / 100.0, _get_stage_color(current_target.get_hunger_stage(), NpcRules.HungerStage.WELL_NOURISHED, NpcRules.HungerStage.HUNGRY, NpcRules.HungerStage.STARVING))
	blood_value.text = "%d / %d" % [int(round(current_target.blood)), int(round(current_target.max_blood))]
	_update_fill_bar(blood_bar_stack, blood_fill, current_target.blood / maxf(current_target.max_blood, 1.0), _get_ratio_color(current_target.blood / maxf(current_target.max_blood, 1.0)))
	_update_hp_bar_visuals(current_target.hp, current_target.get_open_cut_damage(), current_target.get_bandaged_cut_damage(), current_target.max_hp, current_target.get_blunt_damage())
	hp_value.text = "%d / %d" % [int(round(current_target.hp)), int(round(current_target.max_hp))]
	var fatigue_stage_label: String = current_target.get_fatigue_stage_label()
	fatigue_value.text = "%s %d / 100" % [fatigue_stage_label, int(round(current_target.fatigue))]
	_update_fill_bar(fatigue_bar_stack, fatigue_fill, current_target.fatigue / 100.0, _get_stage_color(current_target.get_fatigue_stage(), NpcRules.FatigueStage.WELL_RESTED, NpcRules.FatigueStage.WINDED, NpcRules.FatigueStage.EXHAUSTED))


func _update_hp_bar_visuals(current_hp: float, open_cut: float, bandaged_cut: float, max_hp: float, blunt_damage: float = 0.0) -> void:
	if hp_bar_stack == null:
		return
	var total_width := hp_bar_stack.size.x
	if total_width <= 0.0:
		total_width = maxf(hp_bar_stack.custom_minimum_size.x, 180.0)
	var safe_max_hp := maxf(max_hp, 1.0)
	var health_width := total_width * clampf(current_hp / safe_max_hp, 0.0, 1.0)
	var bandaged_width := total_width * clampf(bandaged_cut / safe_max_hp, 0.0, 1.0)
	var cut_width := total_width * clampf(open_cut / safe_max_hp, 0.0, 1.0)
	var occupied_width := total_width * clampf((safe_max_hp - blunt_damage) / safe_max_hp, 0.0, 1.0)
	var max_cut_start := maxf(0.0, occupied_width - cut_width)
	var bandaged_start := minf(health_width, occupied_width)
	var cut_start := minf(bandaged_start + bandaged_width, max_cut_start)
	hp_health_fill.position = Vector2.ZERO
	hp_health_fill.size = Vector2(maxf(0.0, minf(health_width, occupied_width)), hp_bar_stack.size.y)
	hp_bandaged_fill.visible = bandaged_width > 0.5
	hp_bandaged_fill.position = Vector2(bandaged_start, 0.0)
	hp_bandaged_fill.size = Vector2(maxf(0.0, minf(bandaged_width, maxf(0.0, occupied_width - bandaged_start))), hp_bar_stack.size.y)
	hp_cut_outline.visible = cut_width > 0.5
	hp_cut_outline.position = Vector2(cut_start, 0.0)
	hp_cut_outline.size = Vector2(maxf(0.0, minf(cut_width, maxf(0.0, occupied_width - cut_start))), hp_bar_stack.size.y)


func _update_fill_bar(bar_stack: Control, fill_rect: ColorRect, ratio: float, color: Color) -> void:
	if bar_stack == null or fill_rect == null:
		return
	var total_width := bar_stack.size.x
	if total_width <= 0.0:
		total_width = maxf(bar_stack.custom_minimum_size.x, 180.0)
	fill_rect.color = color
	fill_rect.position = Vector2.ZERO
	fill_rect.size = Vector2(total_width * clampf(ratio, 0.0, 1.0), bar_stack.size.y)


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
