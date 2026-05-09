extends Node

class_name PartyInventoryController

const INVENTORY_WINDOW_SCENE = preload("res://scenes/ui/inventory_window.tscn")
const WORLD_ITEM_SCENE = preload("res://scenes/world/items/world_item.tscn")
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


func open_inventory_for_member(member: HumanoidCharacter) -> void:
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
	if window.has_method("fit_to_content"):
		window.call_deferred("fit_to_content")
	if window.has_method("clamp_to_viewport"):
		window.clamp_to_viewport()
	window.close_requested.connect(_on_inventory_window_close_requested)
	window.notice_requested.connect(_show_floating_notice)
	window.transfer_requested.connect(_on_inventory_transfer_requested)
	window.quick_transfer_requested.connect(_on_inventory_quick_transfer_requested)
	window.item_action_requested.connect(_on_inventory_item_action_requested)
	window.equip_requested.connect(_on_inventory_equip_requested)
	window.equipment_transfer_requested.connect(_on_equipment_transfer_requested)
	window.unequip_requested.connect(_on_inventory_unequip_requested)
	window.item_drop_requested.connect(_on_inventory_item_drop_requested)
	window.equipment_drop_requested.connect(_on_inventory_equipment_drop_requested)


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
	if source_owner != target_owner and not _can_transfer_between_owners(source_owner, target_owner):
		_show_floating_notice("Job inventory is locked")
		return
	if source_owner == target_owner:
		var source_inventory = _get_owner_inventory(source_owner)
		if source_inventory != null:
			source_inventory.move_entry(entry, target_cell)
		return
	if _try_handle_trade(source_owner, target_owner, entry, target_cell):
		return
	var source_inventory = _get_owner_inventory(source_owner)
	var target_inventory = _get_owner_inventory(target_owner)
	if source_inventory == null or target_inventory == null:
		return
	var target_window = open_inventory_windows.get(target_owner.get_instance_id())
	if _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return

	if source_inventory.move_entry_to_inventory(entry, target_inventory, target_cell):
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
	if not _can_transfer_between_owners(source_owner, target_owner):
		_show_floating_notice("Job inventory is locked")
		return
	if _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return
	var source_inventory = _get_owner_inventory(source_owner)
	var target_inventory = _get_owner_inventory(target_owner)
	if source_inventory == null or target_inventory == null:
		return
	var target_cell: Vector2i = target_inventory.find_first_space(entry.definition)
	if target_cell == Vector2i(-1, -1):
		return
	if _try_handle_trade(source_owner, target_owner, entry, target_cell):
		return
	source_inventory.move_entry_to_inventory(entry, target_inventory, target_cell)


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


func _on_inventory_equip_requested(source_owner, entry, target_owner, slot_name: String) -> void:
	if source_owner == null or target_owner == null or entry == null:
		return
	if not target_owner.has_method("can_equip_item_to_slot") or not target_owner.can_equip_item_to_slot(entry.definition, slot_name):
		_show_floating_notice("Cannot equip")
		return
	if source_owner != target_owner:
		if not _can_transfer_between_owners(source_owner, target_owner):
			_show_floating_notice("Job inventory is locked")
			return
		if _owners_too_far(source_owner, target_owner):
			_show_floating_notice("Too far away")
			return
	var source_inventory = _get_owner_inventory(source_owner)
	var target_inventory = _get_owner_inventory(target_owner)
	if source_inventory == null or target_inventory == null or not source_inventory.entries.has(entry):
		return
	var previous = target_owner.get_equipped_item(slot_name) if target_owner.has_method("get_equipped_item") else null
	if previous != null and source_inventory != target_inventory and not target_inventory.can_add_item(previous):
		_show_floating_notice("No room")
		return
	if not _try_pay_for_equipment_transfer(source_owner, target_owner, entry):
		return
	if not source_inventory.remove_entry(entry):
		return
	var replaced = target_owner.equip_item_to_slot(entry.definition, slot_name)
	if replaced != null and not target_inventory.add_item(replaced):
		target_owner.equip_item_to_slot(replaced, slot_name)
		source_inventory.add_item_count(entry.definition, entry.count)
		_show_floating_notice("No room")
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_equipment_transfer_requested(source_owner, source_slot_name: String, target_owner, target_slot_name: String) -> void:
	if source_owner == null or target_owner == null:
		return
	if source_owner != target_owner and _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return
	if not source_owner.has_method("get_equipped_item") or not source_owner.has_method("unequip_item_from_slot"):
		return
	if not target_owner.has_method("can_equip_item_to_slot") or not target_owner.has_method("equip_item_to_slot"):
		return
	var moving_item: ItemDefinition = source_owner.get_equipped_item(source_slot_name)
	if moving_item == null or not target_owner.can_equip_item_to_slot(moving_item, target_slot_name):
		_show_floating_notice("Cannot equip")
		return
	if source_owner == target_owner and source_slot_name == target_slot_name:
		return
	var target_previous: ItemDefinition = target_owner.get_equipped_item(target_slot_name)
	var target_inventory = _get_owner_inventory(target_owner)
	var can_swap_back: bool = source_owner == target_owner and target_previous != null and target_previous.can_equip_to_slot(source_slot_name)
	if target_previous != null and not can_swap_back and (target_inventory == null or not target_inventory.can_add_item(target_previous)):
		_show_floating_notice("No room")
		return
	source_owner.unequip_item_from_slot(source_slot_name)
	var replaced = target_owner.equip_item_to_slot(moving_item, target_slot_name)
	if replaced != null:
		if can_swap_back:
			source_owner.equip_item_to_slot(replaced, source_slot_name)
		else:
			target_inventory.add_item(replaced)
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_inventory_unequip_requested(source_owner, slot_name: String, target_owner, target_cell: Vector2i) -> void:
	if source_owner == null or target_owner == null:
		return
	if source_owner != target_owner:
		if not _can_transfer_between_owners(source_owner, target_owner):
			_show_floating_notice("Job inventory is locked")
			return
		if _owners_too_far(source_owner, target_owner):
			_show_floating_notice("Too far away")
			return
	if not source_owner.has_method("get_equipped_item") or not source_owner.has_method("unequip_item_from_slot"):
		return
	var item: ItemDefinition = source_owner.get_equipped_item(slot_name)
	var target_inventory = _get_owner_inventory(target_owner)
	if item == null or target_inventory == null:
		return
	if target_inventory.use_weight and target_inventory.get_total_weight() + item.unit_weight > target_inventory.max_weight:
		_show_floating_notice("Too heavy")
		return
	if not target_inventory.can_place_item(item, target_cell):
		_show_floating_notice("No room")
		return
	var removed: ItemDefinition = source_owner.unequip_item_from_slot(slot_name)
	if removed == null:
		return
	target_inventory.entries.append(InventoryData.InventoryEntry.new(removed, target_cell, 1))
	target_inventory.changed.emit()
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_inventory_item_drop_requested(source_owner, entry) -> void:
	if source_owner == null or entry == null:
		return
	var source_inventory = _get_owner_inventory(source_owner)
	if source_inventory == null or not source_inventory.entries.has(entry):
		return
	if not source_inventory.remove_entry(entry):
		return
	_spawn_world_item(source_owner, entry.definition, entry.count)


func _on_inventory_equipment_drop_requested(source_owner, slot_name: String) -> void:
	if source_owner == null or not source_owner.has_method("unequip_item_from_slot"):
		return
	var item: ItemDefinition = source_owner.unequip_item_from_slot(slot_name)
	if item == null:
		return
	_spawn_world_item(source_owner, item, 1)


func _get_owner_inventory(inventory_owner):
	if inventory_owner != null and inventory_owner.has_method("get_inventory_for_display"):
		return inventory_owner.get_inventory_for_display()
	if inventory_owner == null:
		return null
	return inventory_owner.inventory


func _refresh_inventory_windows_for(owner_a, owner_b = null) -> void:
	for owner in [owner_a, owner_b]:
		if owner == null:
			continue
		var window = open_inventory_windows.get(owner.get_instance_id())
		if window != null and window.has_method("refresh"):
			window.refresh()


func _spawn_world_item(source_owner, definition: ItemDefinition, count: int) -> void:
	if root_scene == null or definition == null or count <= 0:
		return
	var world_item = WORLD_ITEM_SCENE.instantiate()
	if world_item.has_method("setup"):
		world_item.setup(definition, count)
	if world_item is Node3D:
		(world_item as Node3D).position = _get_world_drop_position(source_owner)
	root_scene.add_child(world_item)


func _get_world_drop_position(source_owner) -> Vector3:
	var origin := Vector3.ZERO
	if source_owner != null and source_owner.has_method("get_inventory_world_position"):
		origin = source_owner.get_inventory_world_position()
	elif source_owner is Node3D:
		origin = (source_owner as Node3D).global_position
	var forward := Vector3.FORWARD
	if source_owner is Node3D:
		forward = -(source_owner as Node3D).global_transform.basis.z.normalized()
		if forward.length_squared() <= 0.001:
			forward = Vector3.FORWARD
	return origin + forward * 0.9 + Vector3(0.0, 0.08, 0.0)


func _try_pay_for_equipment_transfer(source_owner, target_owner, entry) -> bool:
	var source_role = _get_merchant_role(source_owner)
	var target_role = _get_merchant_role(target_owner)
	if source_role == null and target_role == null:
		return true
	if source_role != null and target_role == null:
		var price: int = source_role.get_sell_price(entry.definition) * entry.count
		if price < 0 or target_owner.inventory.count_item(SILVER_ITEM) < price:
			_show_floating_notice("Cannot afford")
			return false
		if not source_owner.inventory.can_add_item_count(SILVER_ITEM, price):
			_show_floating_notice("Merchant does not have space")
			return false
		target_owner.inventory.remove_item_count(SILVER_ITEM, price)
		source_owner.inventory.add_item_count(SILVER_ITEM, price)
		return true
	_show_floating_notice("Cannot trade")
	return false


func _can_transfer_between_owners(source_owner, target_owner) -> bool:
	if source_owner != null and source_owner.has_method("can_transfer_display_inventory_to"):
		if not source_owner.can_transfer_display_inventory_to(target_owner):
			return false
	if target_owner != null and target_owner.has_method("can_receive_inventory_transfer_from"):
		if not target_owner.can_receive_inventory_transfer_from(source_owner):
			return false
	return true


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
