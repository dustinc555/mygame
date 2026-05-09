extends PanelContainer

class_name EquipmentSlotControl

signal slot_drop_requested(slot_name, data)
signal slot_drag_dropped_outside(slot_name)

var inventory_owner
var slot_name := ""
var slot_label := "Slot"
var _label: Label
var _active_drag_data: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(124.0, 34.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
	style.border_color = Color(0.36, 0.34, 0.28, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 10)
	add_child(_label)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	refresh()


func setup(target_owner, target_slot_name: String, target_slot_label: String) -> void:
	inventory_owner = target_owner
	slot_name = target_slot_name
	slot_label = target_slot_label
	refresh()


func refresh() -> void:
	if _label == null:
		return
	var item = _get_equipped_item()
	if item == null:
		_label.text = "%s\n-" % slot_label
		_label.modulate = Color(0.74, 0.72, 0.68, 1.0)
		return
	_label.text = "%s\n%s" % [slot_label, item.display_name]
	_label.modulate = Color(0.96, 0.9, 0.72, 1.0)


func _get_equipped_item():
	if inventory_owner == null or not inventory_owner.has_method("get_equipped_item"):
		return null
	return inventory_owner.get_equipped_item(slot_name)


func _get_drag_data(_at_position: Vector2):
	var item = _get_equipped_item()
	if item == null:
		return null
	var preview := Label.new()
	preview.text = item.display_name
	preview.add_theme_font_size_override("font_size", 12)
	set_drag_preview(preview)
	_active_drag_data = {
		"equipment_owner": inventory_owner,
		"equip_slot": slot_name,
		"item_definition": item,
	}
	return _active_drag_data


func _can_drop_data(_at_position: Vector2, data) -> bool:
	var definition: ItemDefinition = _get_item_definition_from_drag(data)
	if definition == null:
		return false
	if inventory_owner == null or not inventory_owner.has_method("can_equip_item_to_slot"):
		return false
	return inventory_owner.can_equip_item_to_slot(definition, slot_name)


func _drop_data(_at_position: Vector2, data) -> void:
	slot_drop_requested.emit(slot_name, data)


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	if _active_drag_data.is_empty():
		return
	if not is_drag_successful():
		slot_drag_dropped_outside.emit(slot_name)
	_active_drag_data.clear()


func _get_item_definition_from_drag(data) -> ItemDefinition:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	if data.has("entry") and data["entry"] != null:
		return data["entry"].definition as ItemDefinition
	if data.has("item_definition"):
		return data["item_definition"] as ItemDefinition
	return null
