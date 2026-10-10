extends PanelContainer

class_name EquipmentSlotControl

signal slot_drop_requested(slot_name, data)
signal slot_drag_dropped_outside(slot_name)
signal storage_open_requested(slot_name)
signal quick_transfer_requested(slot_name)

const STORAGE_ACTION_HEIGHT := 22.0

var inventory_owner
var slot_name := ""
var slot_label := "Slot"
var grid_dimensions := Vector2i(2, 2)
var _label: Label
var _icon: TextureRect
var _storage_action: Button
var _highlight := false
var _active_drag_data: Dictionary = {}
var _inventory_grid: InventoryGridControl
var item_provider: Callable
var drag_provider: Callable
var drop_validator: Callable
var storage_open_validator: Callable


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Old saves may contain oversized gear. Keep it removable without letting
	# its art spill over adjacent slots; new equips enforce the slot capacity.
	clip_contents = true
	_update_target_size()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.105, 0.095, 0.08, 1)
	panel.border_color = Color(0.34, 0.29, 0.21)
	panel.set_border_width_all(1)
	panel.content_margin_left = 0
	panel.content_margin_top = 0
	panel.content_margin_right = 0
	panel.content_margin_bottom = 0
	add_theme_stylebox_override("panel", panel)
	_icon = TextureRect.new()
	_icon.name = "EquipmentIcon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The target can be race-sized; the item art must keep its inventory scale.
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	art.add_child(_icon)
	_storage_action = Button.new()
	_storage_action.name = "OpenBagButton"
	_storage_action.text = "Open"
	_storage_action.tooltip_text = "Open bag · double-click the bag to open"
	_storage_action.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_storage_action.add_theme_font_size_override("font_size", 11)
	var action_style := StyleBoxFlat.new()
	action_style.bg_color = Color(0.14, 0.125, 0.095, 1)
	action_style.border_color = panel.border_color
	action_style.set_border_width_all(1)
	_storage_action.add_theme_stylebox_override("normal", action_style)
	var active_style := action_style.duplicate()
	active_style.bg_color = Color(0.22, 0.185, 0.12, 1)
	active_style.border_color = Color(0.65, 0.51, 0.30, 1)
	for state in ["hover", "pressed", "focus"]:
		_storage_action.add_theme_stylebox_override(state, active_style)
	_storage_action.pressed.connect(_request_storage_open)
	art.add_child(_storage_action)
	_label = Label.new()
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 10)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_entered.connect(func(): _highlight = true; queue_redraw())
	mouse_exited.connect(func(): _highlight = false; queue_redraw())
	resized.connect(_layout_icon)
	refresh()


func setup(target_owner, target_slot_name: String, target_slot_label: String, inventory_grid: InventoryGridControl = null) -> void:
	inventory_owner = target_owner
	_inventory_grid = inventory_grid
	slot_name = target_slot_name
	slot_label = target_slot_label
	grid_dimensions = CharacterRaceDefinition.default_slot_grid_size(slot_name)
	if inventory_owner != null and inventory_owner.has_method("get_equipment_slot_grid_size"):
		grid_dimensions = inventory_owner.get_equipment_slot_grid_size(slot_name)
	grid_dimensions = Vector2i(maxi(1, grid_dimensions.x), maxi(1, grid_dimensions.y))
	_update_target_size()
	size = custom_minimum_size
	queue_redraw()
	refresh()


func refresh() -> void:
	_update_target_size()
	queue_redraw()
	if _label == null:
		return
	var item = _get_equipped_item()
	_layout_icon()
	if item == null:
		_label.text = slot_label
		_label.modulate = Color(0.74, 0.72, 0.68, 1.0)
		tooltip_text = slot_label
		return
	_label.text = item.display_name if item.icon == null else ""
	_label.modulate = Color(0.96, 0.9, 0.72, 1.0)
	tooltip_text = "%s\n%s" % [slot_label, item.display_name]
	if _can_open_storage():
		tooltip_text += "\nDouble-click to open"
	queue_redraw()


func _item_footprint(item: ItemDefinition) -> Vector2:
	if is_instance_valid(_inventory_grid):
		return InventoryGridControl.item_pixel_size(item, _inventory_grid.cell_size, _inventory_grid.cell_gap)
	return InventoryGridControl.item_pixel_size(item)


func _item_padding() -> float:
	return _inventory_grid.item_padding if is_instance_valid(_inventory_grid) else InventoryGridControl.DEFAULT_ITEM_PADDING


func _cell_size() -> Vector2:
	return _inventory_grid.cell_size if is_instance_valid(_inventory_grid) else InventoryGridControl.DEFAULT_CELL_SIZE


func _cell_gap() -> float:
	return _inventory_grid.cell_gap if is_instance_valid(_inventory_grid) else InventoryGridControl.DEFAULT_CELL_GAP


func _update_target_size() -> void:
	custom_minimum_size = InventoryGridControl.grid_pixel_size(grid_dimensions, _cell_size(), _cell_gap())
	if _can_open_storage():
		custom_minimum_size.y += STORAGE_ACTION_HEIGHT


func _can_open_storage() -> bool:
	var item = _get_equipped_item()
	return item != null and item.has_storage() and (not storage_open_validator.is_valid() or storage_open_validator.call(slot_name))


func _request_storage_open() -> void:
	if _can_open_storage():
		storage_open_requested.emit(slot_name)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.shift_pressed and _get_equipped_item() != null:
		quick_transfer_requested.emit(slot_name)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click and not event.shift_pressed and _can_open_storage():
		_request_storage_open()
		accept_event()


func get_equipped_item_rect() -> Rect2:
	var item = _get_equipped_item()
	return Rect2(Vector2.ZERO, _item_footprint(item)) if item != null else Rect2()


func _layout_icon() -> void:
	if _icon == null:
		return
	var target_size := InventoryGridControl.grid_pixel_size(grid_dimensions, _cell_size(), _cell_gap())
	_storage_action.visible = _can_open_storage()
	_storage_action.position = Vector2(0, target_size.y)
	_storage_action.size = Vector2(target_size.x, STORAGE_ACTION_HEIGHT)
	# Resizing during setup can precede refresh after an item is unequipped.
	# Resolve texture and footprint from the same current item, not stale art.
	var item = _get_equipped_item()
	_icon.texture = item.icon if item != null else null
	if _icon.texture == null:
		_icon.size = Vector2.ZERO
		_icon.position = Vector2.ZERO
		return
	var rect := InventoryGridControl.fit_icon_rect(_icon.texture, Rect2(Vector2.ZERO, _item_footprint(item)).grow(-_item_padding()))
	_icon.size = rect.size
	_icon.position = rect.position


func _draw() -> void:
	var cells := _cell_size()
	var stride := cells + Vector2.ONE * _cell_gap()
	for y in range(grid_dimensions.y):
		for x in range(grid_dimensions.x):
			var rect := Rect2(Vector2(x, y) * stride, cells)
			draw_rect(rect, Color(0.065, 0.06, 0.048), true)
			draw_rect(rect, Color(0.23, 0.205, 0.16), false, 1.0)
	var occupied := get_equipped_item_rect().intersection(Rect2(Vector2.ZERO, custom_minimum_size))
	if occupied.has_area():
		draw_rect(occupied, Color(0.16, 0.14, 0.095), true)
		draw_rect(occupied, Color(0.49, 0.40, 0.24), false, 1.0)
	if _highlight:
		draw_rect(Rect2(Vector2.ZERO, InventoryGridControl.grid_pixel_size(grid_dimensions, _cell_size(), _cell_gap())), Color(0.64, 0.51, 0.29), false, 1)


func _get_equipped_item():
	if item_provider.is_valid():
		return item_provider.call(slot_name)
	if not is_instance_valid(inventory_owner) or not inventory_owner.has_method("get_equipped_item"):
		return null
	return inventory_owner.get_equipped_item(slot_name)


func _get_drag_data(_at_position: Vector2):
	if _at_position.y >= InventoryGridControl.grid_pixel_size(grid_dimensions, _cell_size(), _cell_gap()).y:
		return null
	var item = _get_equipped_item()
	if item == null:
		return null
	var preview := preload("res://features/ui/projection/item_drag_preview.gd").create(item, "", _item_footprint(item), _item_padding())
	set_drag_preview(preview)
	_active_drag_data = {
		"equipment_owner": inventory_owner,
		"equip_slot": slot_name,
		"item_definition": item,
	}
	if drag_provider.is_valid():
		_active_drag_data = drag_provider.call(slot_name)
	return _active_drag_data


func _can_drop_data(_at_position: Vector2, data) -> bool:
	if drop_validator.is_valid():
		return drop_validator.call(slot_name, data)
	var definition: ItemDefinition = _get_item_definition_from_drag(data)
	if definition == null:
		return false
	if inventory_owner == null or not inventory_owner.has_method("can_equip_item_to_slot"):
		return false
	return inventory_owner.can_equip_item_to_slot(definition, slot_name)


func _drop_data(_at_position: Vector2, data) -> void:
	if _can_drop_data(_at_position, data):
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
