extends PanelContainer

class_name InventoryWindow

signal close_requested(inventory_owner)
signal transfer_requested(source_owner, target_owner, entry, target_cell)
signal quick_transfer_requested(inventory_owner, entry)
signal notice_requested(message)
signal item_action_requested(inventory_owner, entry, action)
signal equip_requested(source_owner, entry, target_owner, slot_name)
signal equipment_transfer_requested(source_owner, source_slot_name, target_owner, target_slot_name)
signal unequip_requested(source_owner, slot_name, target_owner, target_cell)
signal item_drop_requested(source_owner, entry)
signal equipment_drop_requested(source_owner, slot_name)

@export var transfer_distance := 5.0

var inventory_owner
var _dragging := false
var _drag_offset := Vector2.ZERO
var _equipment_section: VBoxContainer
var _equipment_grid: GridContainer
var _equipment_slots: Dictionary = {}

@onready var title_label: Label = $Margin/WindowVBox/TitleBar/TitleBarHBox/Title
@onready var auto_sort_button: Button = $Margin/WindowVBox/TitleBar/TitleBarHBox/AutoSortButton
@onready var close_button: Button = $Margin/WindowVBox/TitleBar/TitleBarHBox/CloseButton
@onready var warning_label: Label = $Margin/WindowVBox/WarningLabel
@onready var weight_label: Label = $Margin/WindowVBox/WeightLabel
@onready var inventory_grid: InventoryGridControl = $Margin/WindowVBox/InventoryGrid
@onready var title_bar: PanelContainer = $Margin/WindowVBox/TitleBar
@onready var item_menu: PopupMenu = $ItemMenu

var _context_entry


func _ready() -> void:
	_ensure_equipment_section()
	auto_sort_button.pressed.connect(_on_auto_sort_pressed)
	close_button.pressed.connect(_on_close_pressed)
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	inventory_grid.drop_validator = Callable(self, "_can_accept_drop")
	inventory_grid.drop_handler = Callable(self, "_handle_drop")
	inventory_grid.drop_error_provider = Callable(self, "_get_drop_error")
	inventory_grid.item_right_clicked.connect(_on_inventory_item_right_clicked)
	inventory_grid.invalid_drop_attempted.connect(_on_invalid_drop_attempted)
	inventory_grid.item_dropped_outside.connect(_on_inventory_item_dropped_outside)
	item_menu.id_pressed.connect(_on_item_menu_id_pressed)


func setup(target_owner) -> void:
	inventory_owner = target_owner
	if inventory_owner.has_signal("inventory_changed"):
		inventory_owner.inventory_changed.connect(refresh)
	refresh()
	call_deferred("fit_to_content")


func refresh() -> void:
	if inventory_owner == null:
		return
	title_label.text = _get_owner_inventory_title()
	var inventory = _get_owner_inventory()
	if _owner_shows_weight():
		weight_label.visible = true
		weight_label.text = "Weight: %.1f / %.1f" % [inventory.get_total_weight(), inventory.max_weight]
	else:
		weight_label.visible = false
	if inventory_owner.has_method("get_inventory_cell_size"):
		inventory_grid.cell_size = inventory_owner.get_inventory_cell_size()
	else:
		inventory_grid.cell_size = Vector2(30.0, 30.0)
	inventory_grid.set_inventory_data(inventory)
	inventory_grid.set_meta("source_owner", inventory_owner)
	_refresh_equipment_slots()
	call_deferred("fit_to_content")


func show_warning(message: String) -> void:
	warning_label.text = message
	warning_label.visible = true
	call_deferred("fit_to_content")


func clear_warning() -> void:
	warning_label.visible = false
	warning_label.text = ""
	call_deferred("fit_to_content")


func _can_accept_drop(data, target_cell: Vector2i) -> bool:
	clear_warning()
	return _get_drop_error(data, target_cell) == ""


func _get_drop_error(data, target_cell: Vector2i) -> String:
	if inventory_owner == null or typeof(data) != TYPE_DICTIONARY:
		return ""
	if data.has("equipment_owner") and data.has("equip_slot") and data.has("item_definition"):
		return _get_equipment_drop_to_grid_error(data, target_cell)
	if not data.has("entry") or not data.has("source_owner"):
		return ""
	var source_owner = data["source_owner"]
	var entry = data["entry"]
	var inventory = _get_owner_inventory()
	if source_owner == inventory_owner:
		if inventory.can_place_item(entry.definition, target_cell, entry):
			return ""
		return "No room"
	if _owners_too_far(source_owner, inventory_owner):
		return "Too far away"
	if inventory.use_weight and inventory.get_total_weight() + entry.definition.unit_weight * entry.count > inventory.max_weight:
		return "Too heavy"
	if not inventory.can_place_item(entry.definition, target_cell):
		return "No room"
	return ""


func _handle_drop(data, target_cell: Vector2i) -> void:
	if not _can_accept_drop(data, target_cell):
		return
	if data.has("equipment_owner") and data.has("equip_slot"):
		unequip_requested.emit(data["equipment_owner"], data["equip_slot"], inventory_owner, target_cell)
	else:
		transfer_requested.emit(data["source_owner"], inventory_owner, data["entry"], target_cell)


func _on_close_pressed() -> void:
	close_requested.emit(inventory_owner)


func _on_auto_sort_pressed() -> void:
	if inventory_owner == null:
		return
	clear_warning()
	if not _get_owner_inventory().auto_sort():
		show_warning("Sort failed")


func _on_inventory_item_right_clicked(entry, _local_position: Vector2, shift_pressed: bool) -> void:
	if inventory_owner == null or entry == null:
		return
	if shift_pressed:
		quick_transfer_requested.emit(inventory_owner, entry)
		return
	var can_eat := false
	if inventory_owner.has_method("can_eat_inventory_entry"):
		can_eat = inventory_owner.can_eat_inventory_entry(entry)
	else:
		can_eat = inventory_owner.has_method("can_eat_item") and inventory_owner.can_eat_item(entry.definition)
	if not can_eat:
		return
	_context_entry = entry
	item_menu.clear()
	if can_eat:
		item_menu.add_item("Eat", 1)
	var item_rect := inventory_grid._item_rect(entry)
	var popup_position := inventory_grid.get_global_position() + item_rect.position + Vector2(item_rect.size.x + 8.0, 0.0)
	item_menu.position = Vector2i(popup_position)
	item_menu.popup()


func _on_invalid_drop_attempted(message: String) -> void:
	if message == "Too far away":
		notice_requested.emit(message)


func _on_inventory_item_dropped_outside(source_owner, entry) -> void:
	if Rect2(global_position, size).has_point(get_global_mouse_position()):
		return
	item_drop_requested.emit(source_owner, entry)


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = mouse_button.pressed
		if _dragging:
			_drag_offset = get_global_mouse_position() - position
		accept_event()
		return

	if event is InputEventMouseMotion and _dragging:
		position = _clamp_position_to_viewport(get_global_mouse_position() - _drag_offset)
		accept_event()


func _get_owner_display_name() -> String:
	if inventory_owner != null and inventory_owner.has_method("get_inventory_display_name"):
		return inventory_owner.get_inventory_display_name()
	return inventory_owner.name


func _get_owner_inventory_title() -> String:
	if inventory_owner != null and inventory_owner.has_method("get_inventory_display_title"):
		return inventory_owner.get_inventory_display_title()
	return "%s Inventory" % _get_owner_display_name()


func _get_owner_inventory():
	if inventory_owner != null and inventory_owner.has_method("get_inventory_for_display"):
		return inventory_owner.get_inventory_for_display()
	return inventory_owner.inventory


func _owners_too_far(source_owner, target_owner) -> bool:
	if source_owner == null or target_owner == null:
		return false
	if source_owner.has_method("get_inventory_world_position") and target_owner.has_method("get_inventory_world_position"):
		return source_owner.get_inventory_world_position().distance_to(target_owner.get_inventory_world_position()) > transfer_distance
	return false


func _owner_shows_weight() -> bool:
	if inventory_owner != null and inventory_owner.has_method("shows_inventory_weight"):
		return inventory_owner.shows_inventory_weight()
	return true


func _ensure_equipment_section() -> void:
	if _equipment_section != null:
		return
	var window_vbox := $Margin/WindowVBox as VBoxContainer
	_equipment_section = VBoxContainer.new()
	_equipment_section.name = "EquipmentSection"
	_equipment_section.visible = false
	_equipment_section.add_theme_constant_override("separation", 4)
	var heading := Label.new()
	heading.name = "EquipmentHeading"
	heading.text = "Equipment"
	heading.add_theme_font_size_override("font_size", 11)
	_equipment_section.add_child(heading)
	_equipment_grid = GridContainer.new()
	_equipment_grid.name = "EquipmentGrid"
	_equipment_grid.columns = 4
	_equipment_grid.add_theme_constant_override("h_separation", 5)
	_equipment_grid.add_theme_constant_override("v_separation", 5)
	_equipment_section.add_child(_equipment_grid)
	window_vbox.add_child(_equipment_section)
	window_vbox.move_child(_equipment_section, 1)


func _refresh_equipment_slots() -> void:
	if _equipment_section == null or _equipment_grid == null:
		return
	if inventory_owner == null or not inventory_owner.has_method("get_equipment_slot_names"):
		_equipment_section.visible = false
		return
	_equipment_section.visible = true
	var slot_names: Array[String] = inventory_owner.get_equipment_slot_names()
	var existing_keys := _equipment_slots.keys()
	for existing_slot in existing_keys:
		if slot_names.has(str(existing_slot)):
			continue
		var existing_control: Control = _equipment_slots[existing_slot]
		_equipment_slots.erase(existing_slot)
		existing_control.queue_free()
	for slot_name in slot_names:
		var slot_control: EquipmentSlotControl = _equipment_slots.get(slot_name)
		if slot_control == null:
			slot_control = EquipmentSlotControl.new()
			_equipment_grid.add_child(slot_control)
			_equipment_slots[slot_name] = slot_control
			slot_control.slot_drop_requested.connect(_on_equipment_slot_drop_requested)
			slot_control.slot_drag_dropped_outside.connect(_on_equipment_slot_drag_dropped_outside)
		var slot_label := slot_name.capitalize()
		if inventory_owner.has_method("get_equipment_slot_label"):
			slot_label = inventory_owner.get_equipment_slot_label(slot_name)
		slot_control.setup(inventory_owner, slot_name, slot_label)


func _get_equipment_drop_to_grid_error(data: Dictionary, target_cell: Vector2i) -> String:
	var source_owner = data["equipment_owner"]
	var definition: ItemDefinition = data["item_definition"]
	if source_owner != inventory_owner and _owners_too_far(source_owner, inventory_owner):
		return "Too far away"
	var inventory = _get_owner_inventory()
	if inventory.use_weight and inventory.get_total_weight() + definition.unit_weight > inventory.max_weight:
		return "Too heavy"
	if not inventory.can_place_item(definition, target_cell):
		return "No room"
	return ""


func _on_equipment_slot_drop_requested(slot_name: String, data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.has("entry") and data.has("source_owner"):
		equip_requested.emit(data["source_owner"], data["entry"], inventory_owner, slot_name)
	elif data.has("equipment_owner") and data.has("equip_slot"):
		equipment_transfer_requested.emit(data["equipment_owner"], data["equip_slot"], inventory_owner, slot_name)


func _on_equipment_slot_drag_dropped_outside(slot_name: String) -> void:
	if Rect2(global_position, size).has_point(get_global_mouse_position()):
		return
	equipment_drop_requested.emit(inventory_owner, slot_name)


func _on_item_menu_id_pressed(action_id: int) -> void:
	if inventory_owner == null or _context_entry == null:
		return
	match action_id:
		1:
			if inventory_owner.has_method("consume_inventory_entry"):
				inventory_owner.consume_inventory_entry(_context_entry)
			else:
				item_action_requested.emit(inventory_owner, _context_entry, "eat")
	_context_entry = null


func clamp_to_viewport() -> void:
	position = _clamp_position_to_viewport(position)


func fit_to_content() -> void:
	if not is_inside_tree():
		return
	size = get_combined_minimum_size()
	clamp_to_viewport()


func _clamp_position_to_viewport(target_position: Vector2) -> Vector2:
	var viewport_rect := get_viewport_rect()
	var max_x := maxf(0.0, viewport_rect.size.x - size.x)
	var max_y := maxf(0.0, viewport_rect.size.y - size.y)
	return Vector2(clampf(target_position.x, 0.0, max_x), clampf(target_position.y, 0.0, max_y))
