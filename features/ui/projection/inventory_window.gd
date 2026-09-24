extends PanelContainer

class_name InventoryWindow

signal close_requested(inventory_owner)
signal transfer_requested(source_owner, target_owner, entry, target_cell)
signal quick_transfer_requested(inventory_owner, entry)
signal quick_equip_requested(inventory_owner, entry)
signal notice_requested(message)
signal item_action_requested(inventory_owner, entry, action)
signal equip_requested(source_owner, entry, target_owner, slot_name)
signal equipment_transfer_requested(source_owner, source_slot_name, target_owner, target_slot_name)
signal unequip_requested(source_owner, slot_name, target_owner, target_cell)
signal item_drop_requested(source_owner, entry)
signal equipment_drop_requested(source_owner, slot_name)
signal cursor_item_place_requested(data, target_owner, target_cell)
signal cursor_item_equip_requested(data, target_owner, slot_name)

signal trade_confirmed
signal trade_cancelled
signal trade_item_requested(inventory_owner, entry, amount: int)

@export var transfer_distance := 5.0

const ACTION_EAT := 1
const ACTION_READ := 2
const ACTION_TAKE_ALL := 3
const ACTION_TAKE_SILVER_1 := 101
const ACTION_TAKE_SILVER_5 := 105
const ACTION_TAKE_SILVER_10 := 110
const ACTION_TAKE_SILVER_HALF := 150
const ACTION_TAKE_SILVER_QUARTER := 125
const NO_POUCH_DEPOSIT := "__no_pouch_deposit__"
const GRAB_OPEN = preload("res://assets/ui/cursor_grab.svg")
const GRAB_CLOSED = preload("res://assets/ui/cursor_grabbing.svg")
# Cursor images are global in Godot; only the currently hovered/grabbed header
# owns these overrides, and releases them before another UI uses the shapes.
static var _grab_cursor_owner: WeakRef

var inventory_owner
var _dragging := false
var _header_hovered := false
var _drag_offset := Vector2.ZERO
var _equipment_section: VBoxContainer
var _equipment_grid: Control
var _equipment_slots: Dictionary = {}

var trade_session: RefCounted
var trade_side := -1
var trade_owners: Array = []
var trade_footer: HBoxContainer
var trade_total: Label
var trade_button: Button
var grid_scroll: ScrollContainer
var _height_source: Control

@onready var grab_area: Control = $Margin/WindowVBox/TitleBar/TitleBarHBox/GrabArea
@onready var title_label: Label = $Margin/WindowVBox/TitleBar/TitleBarHBox/GrabArea/Title
@onready var auto_sort_button: Button = $Margin/WindowVBox/Body/BodyVBox/BagActions/AutoSortButton
@onready var bag_actions: HBoxContainer = $Margin/WindowVBox/Body/BodyVBox/BagActions
@onready var close_button: Button = $Margin/WindowVBox/TitleBar/TitleBarHBox/CloseButton
@onready var body_vbox: VBoxContainer = $Margin/WindowVBox/Body/BodyVBox

@onready var weight_label: Label = $Margin/WindowVBox/Body/BodyVBox/BagActions/WeightLabel
@onready var inventory_grid: InventoryGridControl = $Margin/WindowVBox/Body/BodyVBox/InventoryGrid
@onready var title_bar: PanelContainer = $Margin/WindowVBox/TitleBar
@onready var item_menu: PopupMenu = $ItemMenu

var _context_entry


func _ready() -> void:
	title_label.add_theme_font_size_override("font_size", 16)
	auto_sort_button.tooltip_text = "Sort inventory"
	close_button.text = "×"
	close_button.tooltip_text = "Close"
	weight_label.add_theme_font_size_override("font_size", 12)
	_ensure_equipment_section()
	auto_sort_button.pressed.connect(_on_auto_sort_pressed)
	close_button.pressed.connect(_on_close_pressed)
	grab_area.gui_input.connect(_on_title_bar_gui_input)
	grab_area.mouse_entered.connect(_on_header_mouse_entered)
	grab_area.mouse_exited.connect(_on_header_mouse_exited)
	inventory_grid.drop_validator = Callable(self, "_can_accept_drop")
	inventory_grid.drop_handler = Callable(self, "_handle_drop")
	inventory_grid.drop_error_provider = Callable(self, "_get_drop_error")
	inventory_grid.item_clicked.connect(_on_inventory_item_clicked)
	inventory_grid.item_right_clicked.connect(_on_inventory_item_right_clicked)
	inventory_grid.invalid_drop_attempted.connect(_on_invalid_drop_attempted)
	inventory_grid.item_dropped_outside.connect(_on_inventory_item_dropped_outside)
	item_menu.id_pressed.connect(_on_item_menu_id_pressed)
	grid_scroll = ScrollContainer.new()
	grid_scroll.name = "InventoryScroll"
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_vbox.add_child(grid_scroll)
	inventory_grid.reparent(grid_scroll)
	grid_scroll.custom_minimum_size = inventory_grid.custom_minimum_size


func setup(target_owner) -> void:
	inventory_owner = target_owner
	if inventory_owner.has_signal("inventory_changed"):
		inventory_owner.inventory_changed.connect(refresh)
	refresh()
	call_deferred("fit_to_content")


func refresh() -> void:
	if not is_instance_valid(inventory_owner):
		return
	title_label.text = _get_owner_inventory_title()
	var inventory = _get_owner_inventory()
	var merchant := MerchantRole.for_display(inventory_owner)
	if trade_session != null:
		inventory = trade_session.views[trade_side]
	inventory_grid.show()
	grid_scroll.show()
	bag_actions.show()
	auto_sort_button.visible = trade_session == null and merchant == null
	if _owner_shows_weight() and merchant == null:
		weight_label.visible = true
		weight_label.text = "%.1f / %.1f" % [inventory.get_total_weight(), inventory.max_weight]
		weight_label.tooltip_text = "Carried weight / capacity"
	else:
		weight_label.visible = false
	inventory_grid.set_inventory_data(inventory)
	var grid_size: Vector2 = inventory_grid.custom_minimum_size
	grid_scroll.custom_minimum_size = Vector2(grid_size.x + (14 if grid_size.y > 256 else 0), minf(grid_size.y, 256))
	# Align the action row to the drawn cells, not extra width from equipment
	# or the window title. Sort occupies two cell columns at the same scale.
	bag_actions.custom_minimum_size.x = InventoryGridControl.ITEM_GEOMETRY.grid_pixel_size(Vector2i(inventory.columns, inventory.rows), inventory_grid.cell_size, inventory_grid.cell_gap).x
	auto_sort_button.custom_minimum_size = Vector2(inventory_grid.cell_size.x * 2 + inventory_grid.cell_gap, inventory_grid.cell_size.y)
	inventory_grid.set_meta("source_owner", inventory_owner)
	_refresh_equipment_slots()
	if merchant != null:
		_equipment_section.hide()
	if trade_session != null:
		weight_label.show()
		var purse := "%d silver" % trade_session.inventories[trade_side].count_item(InventoryData.SILVER_ITEM)
		weight_label.text = "%s · %s" % [weight_label.text, purse] if trade_side == 0 else purse
		var net: int = trade_session.net_silver()
		trade_total.text = "Pay %d silver" % net if net >= 0 else "Receive %d silver" % -net
		trade_button.disabled = trade_session.offers.is_empty() or not trade_session.is_current()
	call_deferred("fit_to_content")

func bind_trade(session: RefCounted, side: int, owners: Array) -> void:
	if session == null:
		match_height_to(null)
	trade_session = session
	trade_side = side
	trade_owners = owners
	inventory_grid.entry_tooltip_provider = Callable()
	inventory_grid.entry_state_provider = Callable()
	if session != null:
		inventory_grid.entry_tooltip_provider = func(entry): return session.entry_tooltip(side, entry)
		inventory_grid.entry_state_provider = func(entry): return session.entry_state(side, entry)
		if trade_footer == null:
			trade_footer = HBoxContainer.new()
			trade_footer.name = "TradeActions"
			body_vbox.add_child(trade_footer)
			trade_total = Label.new()
			trade_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			trade_total.add_theme_font_size_override("font_size", 13)
			trade_footer.add_child(trade_total)
			var cancel := Button.new()
			cancel.name = "CancelTradeButton"
			cancel.text = "Reset"
			cancel.pressed.connect(func(): trade_cancelled.emit())
			trade_footer.add_child(cancel)
			trade_button = Button.new()
			trade_button.name = "TradeButton"
			trade_button.text = "Trade"
			trade_button.pressed.connect(func(): trade_confirmed.emit())
			trade_footer.add_child(trade_button)
	if trade_footer != null:
		trade_footer.visible = session != null and side == 1
	refresh()


func _can_accept_drop(data, target_cell: Vector2i) -> bool:
	return _get_drop_error(data, target_cell) == ""


func _get_drop_error(data, target_cell: Vector2i) -> String:
	if trade_session != null:
		if data is Dictionary and data.get("equipment_owner") == trade_owners[0] and data.has("equip_slot"):
			return trade_session.drop_error(0, trade_session.equipment_entry(data.equip_slot), trade_side, target_cell)
		if not data is Dictionary or not data.has("entry"):
			return "Unavailable"
		return trade_session.drop_error(trade_owners.find(data.get("source_owner")), data.entry, trade_side, target_cell)
	if inventory_owner == null or typeof(data) != TYPE_DICTIONARY:
		return ""
	var pouch_deposit_error := _get_pouch_deposit_error(data, target_cell)
	if pouch_deposit_error != NO_POUCH_DEPOSIT:
		return pouch_deposit_error
	if data.has("cursor_item") and data.has("item_definition"):
		return _get_cursor_item_drop_error(data, target_cell)
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
	if source_owner != null and source_owner.has_method("can_release_inventory_entry"):
		return "" if bool(source_owner.call("can_release_inventory_entry", entry, inventory)) else "No room"
	if inventory_owner != null and inventory_owner.has_method("can_receive_inventory_entry"):
		return "" if bool(inventory_owner.call("can_receive_inventory_entry", entry)) else "No room"
	var transfer_count := int(entry.count)
	if source_owner != null and source_owner.has_method("get_inventory_transfer_count"):
		transfer_count = maxi(1, int(source_owner.call("get_inventory_transfer_count", entry)))
	if inventory.use_weight and inventory.get_total_weight() + inventory.get_item_weight(entry.definition, transfer_count, entry.contained_item_counts) > inventory.max_weight:
		return "Too heavy"
	if not inventory.can_place_item(entry.definition, target_cell):
		return "No room"
	return ""


func _handle_drop(data, target_cell: Vector2i) -> void:
	if not _can_accept_drop(data, target_cell):
		return
	if data.has("cursor_item") and data.has("item_definition"):
		cursor_item_place_requested.emit(data, inventory_owner, target_cell)
	elif data.has("equipment_owner") and data.has("equip_slot"):
		unequip_requested.emit(data["equipment_owner"], data["equip_slot"], inventory_owner, target_cell)
	else:
		transfer_requested.emit(data["source_owner"], inventory_owner, data["entry"], target_cell)


func _on_close_pressed() -> void:
	_cancel_header_grab()
	close_requested.emit(inventory_owner)


func _on_auto_sort_pressed() -> void:
	if inventory_owner == null:
		return
	if not _get_owner_inventory().auto_sort():
		notice_requested.emit("Sort failed")


func _on_inventory_item_right_clicked(entry, _local_position: Vector2, shift_pressed: bool) -> void:
	if inventory_owner == null or entry == null:
		return
	if trade_session != null:
		_context_entry = entry
		item_menu.clear()
		if trade_session.entry_state(trade_side, entry) == "incoming":
			item_menu.add_item("Withdraw", 200)
		else:
			if not entry.definition.sellable or entry.definition.is_currency_item() or int(trade_session.quote.call(trade_side, entry)) < 0:
				return
			var verb := "Buy" if trade_side == 1 else "Sell"
			item_menu.add_item(verb + " 1", 201)
			if entry.count > 1:
				item_menu.add_item(verb + " stack", 202)
		item_menu.position = Vector2i(get_viewport().get_mouse_position())
		item_menu.popup()
		return
	if shift_pressed:
		quick_transfer_requested.emit(inventory_owner, entry)
		return
	var can_eat := false
	if inventory_owner.has_method("can_eat_inventory_entry"):
		can_eat = inventory_owner.can_eat_inventory_entry(entry)
	else:
		can_eat = inventory_owner.has_method("can_eat_item") and inventory_owner.can_eat_item(entry.definition)
	var can_take_silver := _can_take_silver_from_pouch(entry)
	var can_read: bool = entry.definition != null and entry.definition.read_behavior != ItemDefinition.ReadBehavior.NONE
	var can_take_all: bool = inventory_owner.has_method("release_inventory_entry_count_with_metadata") and int(entry.count) > 0
	if not can_eat and not can_take_silver and not can_read and not can_take_all:
		return
	_context_entry = entry
	item_menu.clear()
	if can_take_all:
		item_menu.add_item("Take All", ACTION_TAKE_ALL)
	if can_eat:
		var digesting: bool = inventory_owner.has_method("is_food_effect_active") and inventory_owner.is_food_effect_active()
		item_menu.add_item("Eat (digesting)" if digesting else "Eat", ACTION_EAT)
		if digesting:
			item_menu.set_item_disabled(item_menu.get_item_index(ACTION_EAT), true)
	if can_read:
		item_menu.add_item("Read", ACTION_READ)
	if can_take_silver:
		item_menu.add_item("Take 1", ACTION_TAKE_SILVER_1)
		item_menu.add_item("Take 5", ACTION_TAKE_SILVER_5)
		item_menu.add_item("Take 10", ACTION_TAKE_SILVER_10)
		item_menu.add_item("Take 1/2", ACTION_TAKE_SILVER_HALF)
		item_menu.add_item("Take 1/4", ACTION_TAKE_SILVER_QUARTER)
	var item_rect := inventory_grid._item_rect(entry)
	var popup_position := inventory_grid.get_global_position() + item_rect.position + Vector2(item_rect.size.x + 8.0, 0.0)
	item_menu.position = Vector2i(popup_position)
	item_menu.popup()


func _on_inventory_item_clicked(entry, shift_pressed: bool) -> void:
	if inventory_owner == null or entry == null or not shift_pressed:
		return
	quick_equip_requested.emit(inventory_owner, entry)


func _on_invalid_drop_attempted(message: String) -> void:
	if message == "Too far away":
		notice_requested.emit(message)


func _on_inventory_item_dropped_outside(source_owner, entry) -> void:
	if trade_session != null:
		return
	if is_pointer_over_inventory_window(self):
		return
	item_drop_requested.emit(source_owner, entry)


static func is_pointer_over_inventory_window(control: Control) -> bool:
	var parent_node := control.get_parent()
	if parent_node == null:
		return false
	var mouse_position := control.get_global_mouse_position()
	for child in parent_node.get_children():
		if child is InventoryWindow and child.is_visible_in_tree() and child.get_global_rect().has_point(mouse_position):
			return true
	return false


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = mouse_button.pressed
		if _dragging:
			_drag_offset = get_global_mouse_position() - position
		_update_header_cursor()
		# Mouse-button events do not refresh Godot's cursor until the next motion.
		if _header_hovered or _dragging:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_DRAG if _dragging else DisplayServer.CURSOR_MOVE)
		accept_event()
		return

	if event is InputEventMouseMotion and _dragging:
		position = _clamp_position_to_viewport(get_global_mouse_position() - _drag_offset)
		accept_event()


func _on_header_mouse_entered() -> void:
	_header_hovered = true
	_update_header_cursor()


func _on_header_mouse_exited() -> void:
	_header_hovered = false
	if not _dragging:
		_release_header_cursor()


func _update_header_cursor() -> void:
	grab_area.mouse_default_cursor_shape = Control.CURSOR_DRAG if _dragging else Control.CURSOR_MOVE
	if _header_hovered or _dragging:
		_grab_cursor_owner = weakref(self)
		Input.set_custom_mouse_cursor(GRAB_OPEN, Input.CURSOR_MOVE, Vector2(16, 16))
		Input.set_custom_mouse_cursor(GRAB_CLOSED, Input.CURSOR_DRAG, Vector2(16, 16))
	else:
		_release_header_cursor()


func _release_header_cursor() -> void:
	if _grab_cursor_owner != null and _grab_cursor_owner.get_ref() == self:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_MOVE)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_DRAG)
		_grab_cursor_owner = null


func _cancel_header_grab() -> void:
	_dragging = false
	_header_hovered = false
	if is_instance_valid(grab_area):
		grab_area.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_release_header_cursor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_header_grab()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and not is_visible_in_tree():
		_cancel_header_grab()


func _exit_tree() -> void:
	_cancel_header_grab()


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


func _owner_shows_equipment() -> bool:
	if inventory_owner != null and inventory_owner.has_method("shows_inventory_equipment"):
		return inventory_owner.shows_inventory_equipment()
	return true


func _ensure_equipment_section() -> void:
	if _equipment_section != null:
		return

	_equipment_section = VBoxContainer.new()
	_equipment_section.name = "EquipmentSection"
	_equipment_section.visible = false
	_equipment_section.add_theme_constant_override("separation", 4)
	_equipment_grid = preload("res://features/ui/projection/equipment_layout.gd").new()
	_equipment_grid.name = "EquipmentLayout"
	_equipment_section.add_child(_equipment_grid)
	body_vbox.add_child(_equipment_section)
	body_vbox.move_child(_equipment_section, 0)


func _refresh_equipment_slots() -> void:
	if _equipment_section == null or _equipment_grid == null:
		return
	if inventory_owner == null or not _owner_shows_equipment() or not inventory_owner.has_method("get_equipment_slot_names"):
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
		slot_control.item_provider = Callable()
		slot_control.drag_provider = Callable()
		slot_control.drop_validator = Callable()
		if trade_session != null and trade_side == 0:
			slot_control.item_provider = func(slot):
				var entry = trade_session.equipment_entry(slot)
				return entry.definition if entry != null else null
			slot_control.drag_provider = _trade_equipment_drag
			slot_control.drop_validator = _trade_equipment_accepts
		slot_control.setup(inventory_owner, slot_name, slot_label, inventory_grid)
	_equipment_grid.arrange()

func _trade_equipment_drag(slot: String) -> Dictionary:
	var entry = trade_session.equipment_entry(slot)
	if entry == null:
		return {}
	if not trade_session.offer_for(entry).is_empty():
		return {"source_owner": inventory_owner, "entry": entry}
	return {"equipment_owner": inventory_owner, "equip_slot": slot, "item_definition": entry.definition}

func _trade_equipment_accepts(slot: String, data) -> bool:
	if not data is Dictionary:
		return false
	if data.has("entry"):
		var side := trade_owners.find(data.get("source_owner"))
		if side == 1 or not trade_session.offer_for(data.entry).is_empty():
			return trade_session.equipment_drop_error(side, data.entry, slot).is_empty()
		return side == 0 and trade_session.owned_equipment_error(data.entry, slot).is_empty()
	if data.get("equipment_owner") == inventory_owner and data.has("equip_slot"):
		return trade_session.owned_equipment_error(trade_session.equipment_entry(data.equip_slot), slot).is_empty()
	return false


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


func _get_cursor_item_drop_error(data: Dictionary, target_cell: Vector2i) -> String:
	var source_owner = data.get("source_owner", null)
	var definition: ItemDefinition = data["item_definition"]
	var count := int(data.get("count", 1))
	var contained_item_counts: Dictionary = data.get("contained_item_counts", {})
	if source_owner != inventory_owner and _owners_too_far(source_owner, inventory_owner):
		return "Too far away"
	var inventory = _get_owner_inventory()
	if inventory.use_weight and inventory.get_total_weight() + inventory.get_item_weight(definition, count, contained_item_counts) > inventory.max_weight:
		return "Too heavy"
	if not inventory.can_place_item(definition, target_cell):
		return "No room"
	return ""


func _on_equipment_slot_drop_requested(slot_name: String, data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.has("cursor_item") and data.has("item_definition"):
		cursor_item_equip_requested.emit(data, inventory_owner, slot_name)
	elif data.has("entry") and data.has("source_owner"):
		equip_requested.emit(data["source_owner"], data["entry"], inventory_owner, slot_name)
	elif data.has("equipment_owner") and data.has("equip_slot"):
		equipment_transfer_requested.emit(data["equipment_owner"], data["equip_slot"], inventory_owner, slot_name)


func _on_equipment_slot_drag_dropped_outside(slot_name: String) -> void:
	if trade_session != null:
		return
	if is_pointer_over_inventory_window(self):
		return
	equipment_drop_requested.emit(inventory_owner, slot_name)


func _on_item_menu_id_pressed(action_id: int) -> void:
	if inventory_owner == null or _context_entry == null:
		return
	if trade_session != null:
		if action_id in [200, 201, 202]:
			trade_item_requested.emit(inventory_owner, _context_entry, 0 if action_id == 200 else (1 if action_id == 201 else -1))
		return
	match action_id:
		ACTION_TAKE_ALL:
			item_action_requested.emit(inventory_owner, _context_entry, "take_all")
		ACTION_READ:
			item_action_requested.emit(inventory_owner, _context_entry, "read")
		ACTION_EAT:
			if inventory_owner.has_method("consume_inventory_entry"):
				inventory_owner.consume_inventory_entry(_context_entry)
			else:
				item_action_requested.emit(inventory_owner, _context_entry, "eat")
		ACTION_TAKE_SILVER_1:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_1")
		ACTION_TAKE_SILVER_5:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_5")
		ACTION_TAKE_SILVER_10:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_10")
		ACTION_TAKE_SILVER_HALF:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_half")
		ACTION_TAKE_SILVER_QUARTER:
			item_action_requested.emit(inventory_owner, _context_entry, "take_silver_quarter")
	_context_entry = null


func _can_take_silver_from_pouch(entry) -> bool:
	if inventory_owner == null or entry == null:
		return false
	if not inventory_owner.has_method("is_player_party_member") or not bool(inventory_owner.call("is_player_party_member")):
		return false
	var inventory = _get_owner_inventory()
	if inventory == null or not inventory.has_method("is_entry_currency_container") or not bool(inventory.call("is_entry_currency_container", entry, InventoryData.SILVER_ITEM)):
		return false
	return int(inventory.call("get_entry_contained_item_count", entry, InventoryData.SILVER_ITEM)) > 0


func _get_pouch_deposit_error(data: Dictionary, target_cell: Vector2i) -> String:
	var inventory = _get_owner_inventory()
	if inventory == null or not inventory.has_method("is_entry_currency_container"):
		return NO_POUCH_DEPOSIT
	var target_entry = inventory.get_entry_at_cell(target_cell)
	if target_entry == null or not bool(inventory.call("is_entry_currency_container", target_entry, InventoryData.SILVER_ITEM)):
		return NO_POUCH_DEPOSIT
	if data.has("entry") and data["entry"] == target_entry:
		return "Same pouch"
	if not _drag_data_is_silver_or_pouch(data):
		return NO_POUCH_DEPOSIT
	var source_owner = data.get("source_owner", null)
	if source_owner != inventory_owner and _owners_too_far(source_owner, inventory_owner):
		return "Too far away"
	if _drag_data_silver_amount(data) <= 0:
		return "No silver"
	if int(inventory.call("get_entry_remaining_currency_capacity", target_entry, InventoryData.SILVER_ITEM)) <= 0:
		return "Pouch full"
	return ""


func _drag_data_is_silver_or_pouch(data: Dictionary) -> bool:
	var definition = null
	if data.has("entry") and data["entry"] != null:
		definition = data["entry"].definition
	elif data.has("item_definition"):
		definition = data["item_definition"]
	if definition == null:
		return false
	return str(definition.currency_id) == str(InventoryData.SILVER_ITEM.currency_id)


func _drag_data_silver_amount(data: Dictionary) -> int:
	if data.has("entry") and data["entry"] != null:
		var entry = data["entry"]
		if entry.definition != null and int(entry.definition.currency_container_capacity) > 0:
			var source_inventory = data.get("source_inventory", null)
			if source_inventory != null and source_inventory.has_method("get_entry_contained_item_count"):
				return int(source_inventory.call("get_entry_contained_item_count", entry, InventoryData.SILVER_ITEM))
			return int(entry.contained_item_counts.get(str(InventoryData.SILVER_ITEM.resource_path), 0))
		return int(entry.count)
	if data.has("item_definition"):
		var definition = data["item_definition"]
		if definition != null and int(definition.currency_container_capacity) > 0:
			var contained: Dictionary = data.get("contained_item_counts", {})
			return int(contained.get(str(InventoryData.SILVER_ITEM.resource_path), 0))
		return int(data.get("count", 1))
	return 0


func clamp_to_viewport() -> void:
	position = _clamp_position_to_viewport(position)


func match_height_to(source: Control) -> void:
	if is_instance_valid(_height_source) and _height_source.resized.is_connected(fit_to_content):
		_height_source.resized.disconnect(fit_to_content)
	_height_source = source
	if is_instance_valid(_height_source):
		_height_source.resized.connect(fit_to_content, CONNECT_DEFERRED)
	fit_to_content()


func fit_to_content() -> void:
	if not is_inside_tree():
		return

	var fitted_size := get_combined_minimum_size()
	if is_instance_valid(_height_source):
		fitted_size.y = maxf(fitted_size.y, _height_source.size.y)
	size = fitted_size
	clamp_to_viewport()


func _clamp_position_to_viewport(target_position: Vector2) -> Vector2:
	var viewport_rect := get_viewport_rect()
	var max_x := maxf(0.0, viewport_rect.size.x - size.x)
	var max_y := maxf(0.0, viewport_rect.size.y - size.y)
	return Vector2(clampf(target_position.x, 0.0, max_x), clampf(target_position.y, 0.0, max_y))
