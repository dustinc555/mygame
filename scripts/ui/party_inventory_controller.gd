extends Node

class_name PartyInventoryController

const INVENTORY_WINDOW_SCENE = preload("res://scenes/ui/inventory_window.tscn")
const SILVER_ITEM = preload("res://resources/items/silver.tres")

@export var inventory_toggle_key := KEY_I

var open_inventory_windows: Dictionary = {}
var root_scene: Node
var hud_layer: CanvasLayer
var party_manager: PartyManager
var inventory_window_layer: Control
var floating_notice
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


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	party_manager = root_scene.get_node("PartyManager")
	if hud_layer == null:
		hud_layer = root_scene.get_node_or_null("GameHUD")
	inventory_window_layer = hud_layer.get_node("InventoryWindowLayer")
	floating_notice = hud_layer.get_node_or_null("FloatingNotice")
	_initialized = true


func _unhandled_input(event: InputEvent) -> void:
	if not _initialized:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == inventory_toggle_key:
		open_selected_inventory()


func open_selected_inventory() -> void:
	if party_manager.selected_members.is_empty():
		return
	open_inventory_for_owner(party_manager.selected_members[0])


func open_inventory_for_member(member: PartyMember) -> void:
	open_inventory_for_owner(member)


func open_inventory_for_owner(inventory_owner) -> void:
	if inventory_owner == null:
		return
	var key: int = inventory_owner.get_instance_id()
	if open_inventory_windows.has(key):
		var existing = open_inventory_windows[key]
		existing.visible = true
		existing.grab_click_focus()
		return

	var window = INVENTORY_WINDOW_SCENE.instantiate()
	open_inventory_windows[key] = window
	inventory_window_layer.add_child(window)
	window.position = Vector2(36 + open_inventory_windows.size() * 24, 160 + open_inventory_windows.size() * 18)
	window.setup(inventory_owner)
	if window.has_method("clamp_to_viewport"):
		window.clamp_to_viewport()
	window.close_requested.connect(_on_inventory_window_close_requested)
	window.notice_requested.connect(_show_floating_notice)
	window.transfer_requested.connect(_on_inventory_transfer_requested)
	window.quick_transfer_requested.connect(_on_inventory_quick_transfer_requested)
	window.item_action_requested.connect(_on_inventory_item_action_requested)


func _on_inventory_window_close_requested(inventory_owner) -> void:
	if inventory_owner == null:
		return
	var key: int = inventory_owner.get_instance_id()
	if not open_inventory_windows.has(key):
		return
	var window = open_inventory_windows[key]
	open_inventory_windows.erase(key)
	window.queue_free()


func _on_inventory_transfer_requested(source_owner, target_owner, entry, target_cell: Vector2i) -> void:
	if source_owner == null or target_owner == null or entry == null:
		return
	if source_owner == target_owner:
		source_owner.inventory.move_entry(entry, target_cell)
		return
	if _try_handle_trade(source_owner, target_owner, entry, target_cell):
		return
	var target_window = open_inventory_windows.get(target_owner.get_instance_id())
	if _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return

	if source_owner.inventory.move_entry_to_inventory(entry, target_owner.inventory, target_cell):
		if target_window != null:
			target_window.clear_warning()


func _on_inventory_quick_transfer_requested(source_owner, entry) -> void:
	if source_owner == null or entry == null:
		return
	var target_window = _first_other_inventory_window(source_owner)
	if target_window == null:
		return
	var target_owner = target_window.inventory_owner
	if target_owner == null:
		return
	if _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return
	var target_cell: Vector2i = target_owner.inventory.find_first_space(entry.definition)
	if target_cell == Vector2i(-1, -1):
		return
	if _try_handle_trade(source_owner, target_owner, entry, target_cell):
		return
	source_owner.inventory.move_entry_to_inventory(entry, target_owner.inventory, target_cell)


func _first_other_inventory_window(source_owner):
	for key in open_inventory_windows.keys():
		var window = open_inventory_windows[key]
		if window.inventory_owner != source_owner:
			return window
	return null


func _show_floating_notice(message: String) -> void:
	if floating_notice != null and floating_notice.has_method("show_message"):
		floating_notice.show_message(message)


func _owners_too_far(source_owner, target_owner) -> bool:
	if source_owner == null or target_owner == null:
		return false
	if source_owner.has_method("get_inventory_world_position") and target_owner.has_method("get_inventory_world_position"):
		return source_owner.get_inventory_world_position().distance_to(target_owner.get_inventory_world_position()) > 5.0
	return false


func _on_inventory_item_action_requested(inventory_owner, entry, action: String) -> void:
	if inventory_owner == null or entry == null:
		return
	if action == "eat" and inventory_owner.has_method("eat_item"):
		inventory_owner.eat_item(entry.definition)


func _try_handle_trade(source_owner, target_owner, entry, target_cell: Vector2i) -> bool:
	var source_role = _get_merchant_role(source_owner)
	var target_role = _get_merchant_role(target_owner)
	if source_role == null and target_role == null:
		return false
	if source_role != null and target_role != null:
		return false
	if source_role != null:
		return _buy_from_merchant(source_owner, target_owner, entry, target_cell, source_role)
	return _sell_to_merchant(source_owner, target_owner, entry, target_cell, target_role)


func _buy_from_merchant(merchant_owner, buyer_owner, entry, target_cell: Vector2i, merchant_role) -> bool:
	var price: int = merchant_role.get_sell_price(entry.definition)
	if price < 0:
		_show_floating_notice("Cannot afford")
		return true
	price *= entry.count
	if buyer_owner.inventory.count_item(SILVER_ITEM) < price:
		_show_floating_notice("Cannot afford")
		return true
	if not buyer_owner.inventory.can_place_item(entry.definition, target_cell):
		_show_floating_notice("Not enough space")
		return true
	if not merchant_owner.inventory.can_add_item_count(SILVER_ITEM, price):
		_show_floating_notice("Merchant does not have space")
		return true
	if not buyer_owner.inventory.remove_item_count(SILVER_ITEM, price):
		_show_floating_notice("Cannot afford")
		return true
	merchant_owner.inventory.add_item_count(SILVER_ITEM, price)
	merchant_owner.inventory.move_entry_to_inventory(entry, buyer_owner.inventory, target_cell)
	return true


func _sell_to_merchant(seller_owner, merchant_owner, entry, target_cell: Vector2i, merchant_role) -> bool:
	var price: int = merchant_role.get_buy_price(entry.definition)
	if price < 0:
		_show_floating_notice("Cannot trade")
		return true
	price *= entry.count
	if not merchant_owner.inventory.can_place_item(entry.definition, target_cell):
		_show_floating_notice("Merchant does not have space")
		return true
	if merchant_owner.inventory.count_item(SILVER_ITEM) < price:
		_show_floating_notice("Cannot afford")
		return true
	if not seller_owner.inventory.can_add_item_count(SILVER_ITEM, price):
		_show_floating_notice("Not enough space")
		return true
	merchant_owner.inventory.remove_item_count(SILVER_ITEM, price)
	seller_owner.inventory.add_item_count(SILVER_ITEM, price)
	seller_owner.inventory.move_entry_to_inventory(entry, merchant_owner.inventory, target_cell)
	return true


func _get_merchant_role(inventory_owner):
	if inventory_owner != null and inventory_owner.has_method("get_merchant_role"):
		return inventory_owner.get_merchant_role()
	return null
