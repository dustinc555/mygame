extends Node

class_name HumanoidDetailsController

var root_scene: Node
var details_panel: Control
var name_label: Label
var faction_label: Label
var hunger_bar: ProgressBar
var hunger_value: Label
var blood_bar: ProgressBar
var blood_value: Label
var hp_bar: ProgressBar
var hp_value: Label
var current_target
var _initialized := false


func initialize(target_root: Node) -> void:
	root_scene = target_root
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	if root_scene == null:
		var parent_node := get_parent()
		if parent_node != null and parent_node.get_parent() != null:
			root_scene = parent_node.get_parent()
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
	details_panel = root_scene.get_node_or_null("CanvasLayer/HumanoidDetailsPanel")
	if details_panel == null:
		return
	name_label = details_panel.get_node("Margin/DetailsVBox/Name")
	faction_label = details_panel.get_node("Margin/DetailsVBox/Faction")
	hunger_bar = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerBar")
	hunger_value = details_panel.get_node("Margin/DetailsVBox/HungerRow/HungerValue")
	blood_bar = details_panel.get_node("Margin/DetailsVBox/BloodRow/BloodBar")
	blood_value = details_panel.get_node("Margin/DetailsVBox/BloodRow/BloodValue")
	hp_bar = details_panel.get_node("Margin/DetailsVBox/HpRow/HpBar")
	hp_value = details_panel.get_node("Margin/DetailsVBox/HpRow/HpValue")
	details_panel.visible = false
	_initialized = true


func _update_panel() -> void:
	if details_panel == null:
		return
	if current_target == null:
		details_panel.visible = false
		return
	details_panel.visible = true
	name_label.text = current_target.member_name
	faction_label.text = current_target.faction_name
	hunger_bar.value = current_target.hunger
	hunger_value.text = "%d / 100" % int(round(current_target.hunger))
	blood_bar.value = current_target.blood
	blood_value.text = "%d / %d" % [int(round(current_target.blood)), int(round(current_target.max_blood))]
	hp_bar.value = current_target.hp
	hp_value.text = "%d / %d" % [int(round(current_target.hp)), int(round(current_target.max_hp))]
