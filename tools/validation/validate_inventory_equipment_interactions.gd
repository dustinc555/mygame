extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_inventory_equipment_interactions.gd

var _root: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/test_levels/farming_test.tscn") as PackedScene
	if packed == null:
		_fail("farming test scene loads for ordinary inventory interaction")
		return
	_root = packed.instantiate()
	get_root().add_child(_root)
	await create_timer(4.0).timeout
	var context := BootstrapContext.active
	var inventory_controller = context.get_optional(&"party_inventory") if context != null else null
	var ada := _root.get_node_or_null("PartyMembers/Ada") as Node
	if inventory_controller == null or ada == null:
		_fail("Ada and the ordinary party inventory controller exist")
		return
	var inventory_capability = ada.call("get_inventory")
	if inventory_capability.get("inventory") == null:
		inventory_capability.call("initialize_from_actor")
	var inventory = inventory_capability.get("inventory")
	var equipment = ada.call("get_equipment")
	var hoe_entry = _entry_with_tool_tag(inventory, "tool.hoe")
	if equipment == null or hoe_entry == null:
		_fail("Ada starts with an inventory hoe and equipment capability")
		return
	if equipment.get_equipped_item("weapon") != null:
		_fail("ordinary drag test starts with an empty weapon slot")
		return
	var shopkeeper_scene := load("res://features/actors/projection/humanoid/vendors/shopkeeper_npc.tscn") as PackedScene
	var shopkeeper = shopkeeper_scene.instantiate() if shopkeeper_scene != null else null
	if shopkeeper == null:
		_fail("shopkeeper fixture loads for paired trade interaction")
		return
	_root.add_child(shopkeeper)
	shopkeeper.position = ada.position + Vector3(2.0, 0.0, 0.0)
	await process_frame
	var merchant_role = shopkeeper.get_merchant_role()
	var shop_inventory = merchant_role.get_shop_inventory() if merchant_role != null else null
	var trade_item := load("res://features/inventory/resources/items/watering_can.tres") as ItemDefinition
	var silver := load("res://features/inventory/resources/items/silver.tres") as ItemDefinition
	if shop_inventory == null or trade_item == null or silver == null:
		_fail("shop inventory and trade fixtures initialize")
		return
	var price := MerchantPrice.new()
	price.item_definition = trade_item
	price.buy_price = 2
	price.sell_price = 3
	var prices: Array[Resource] = [price]
	merchant_role.prices = prices
	shop_inventory.add_item(trade_item)
	shop_inventory.add_item_count(silver, 20)
	inventory.add_item_count(silver, 10)
	var player_silver_before_buy: int = inventory.count_item(silver)
	var shop_silver_before_buy: int = shop_inventory.count_item(silver)
	inventory_controller.open_inventory_pair(ada, shopkeeper)
	await process_frame
	var shop_entry = _entry_with_definition(shop_inventory, trade_item)
	var shop_trade_stack_id := str(shop_entry.stack_id)
	_shift_left_click(inventory_controller.secondary_inventory_window, shop_entry)
	await process_frame
	var bought_entry = _entry_with_stack_id(inventory, shop_trade_stack_id)
	if bought_entry == null or inventory.count_item(silver) != player_silver_before_buy - 3 \
			or shop_inventory.count_item(silver) != shop_silver_before_buy + 3 \
			or equipment.get_equipped_item("weapon") != null:
		_fail("Shift+left-click buys through the existing shop transaction while the trade pair is open")
		return
	var player_silver_before_sell: int = inventory.count_item(silver)
	var shop_silver_before_sell: int = shop_inventory.count_item(silver)
	_shift_left_click(inventory_controller.primary_character_window, bought_entry)
	await process_frame
	if _entry_with_stack_id(inventory, shop_trade_stack_id) != null \
			or _entry_with_stack_id(shop_inventory, shop_trade_stack_id) == null \
			or inventory.count_item(silver) != player_silver_before_sell + 2 \
			or shop_inventory.count_item(silver) != shop_silver_before_sell - 2:
		_fail("Shift+left-click sells the purchased durable stack through the existing shop transaction")
		return
	inventory_controller.call("_close_all_inventory_windows")
	shopkeeper.queue_free()
	await process_frame
	var bram := _root.get_node_or_null("PartyMembers/Bram") as Node
	var bram_inventory_capability = bram.call("get_inventory") if bram != null else null
	if bram_inventory_capability == null:
		_fail("Bram exists for paired-inventory interaction")
		return
	if bram_inventory_capability.get("inventory") == null:
		bram_inventory_capability.call("initialize_from_actor")
	var bram_inventory = bram_inventory_capability.get("inventory")
	var paired_hoe_stack_id := str(hoe_entry.stack_id)
	inventory_controller.open_inventory_pair(ada, bram)
	await process_frame
	_shift_left_click(inventory_controller.primary_character_window, hoe_entry)
	await process_frame
	var transferred_hoe = _entry_with_stack_id(bram_inventory, paired_hoe_stack_id)
	if transferred_hoe == null or equipment.get_equipped_item("weapon") != null:
		_fail("Shift+left-click transfers instead of equipping while two inventories are open")
		return
	_shift_left_click(inventory_controller.secondary_inventory_window, transferred_hoe)
	await process_frame
	hoe_entry = _entry_with_stack_id(inventory, paired_hoe_stack_id)
	if hoe_entry == null or _entry_with_stack_id(bram_inventory, paired_hoe_stack_id) != null:
		_fail("paired Shift+left-click transfers through the existing quick-transfer path in both directions")
		return
	inventory_controller.open_inventory_for_member(ada)
	await process_frame
	var window = inventory_controller.primary_character_window
	var weapon_slot = window._equipment_slots.get("weapon") if window != null else null
	if weapon_slot == null:
		_fail("Ada inventory exposes its Weapon equipment slot")
		return
	var hoe_definition = hoe_entry.definition
	var hoe_stack_id := str(hoe_entry.stack_id)
	var drag_data := {"entry": hoe_entry, "source_owner": ada}
	if not bool(weapon_slot.call("_can_drop_data", Vector2.ZERO, drag_data)):
		_fail("dragging Ada's hoe is accepted by the compatible Weapon slot")
		return
	weapon_slot.call("_drop_data", Vector2.ZERO, drag_data)
	await process_frame
	if equipment.get_equipped_item("weapon") != hoe_definition:
		_fail("dropping Ada's hoe onto Weapon equips it through the ordinary UI transaction")
		return
	if _entry_with_stack_id(inventory, hoe_stack_id) != null:
		_fail("drag equip removes the same durable hoe stack from inventory")
		return
	var details = context.get_optional(&"humanoid_details")
	details.inspect_humanoid(ada)
	await process_frame
	var action_row := _root.get_node_or_null("GameHUD/HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/ActionRow") as Control
	if not _has_visible_button(action_row, "Till"):
		_fail("ordinary inventory hoe equip exposes Till without direct equipment-state manipulation")
		return
	var bread := load("res://features/inventory/resources/items/bread.tres") as ItemDefinition
	if bread == null or not inventory.add_item(bread):
		_fail("non-equippable fixture fits in Ada's inventory")
		return
	var bread_entry = _entry_with_definition(inventory, bread)
	var bread_stack_id := str(bread_entry.stack_id)
	window.refresh()
	_shift_left_click(window, bread_entry)
	await process_frame
	if equipment.get_equipped_item("weapon") != hoe_definition or _entry_with_stack_id(inventory, bread_stack_id) == null:
		_fail("Shift+left-click leaves non-equippable inventory items unchanged")
		return
	inventory.remove_entry(bread_entry)
	var watering_can := load("res://features/inventory/resources/items/watering_can.tres") as ItemDefinition
	if watering_can == null or not inventory.add_item(watering_can):
		_fail("weapon replacement fixture fits in Ada's inventory")
		return
	var watering_entry = _entry_with_definition(inventory, watering_can)
	var watering_stack_id := str(watering_entry.stack_id)
	window.refresh()
	_shift_left_click(window, watering_entry)
	await process_frame
	if equipment.get_equipped_item("weapon") != watering_can:
		_fail("Shift+left-click equips a compatible inventory weapon automatically")
		return
	if _entry_with_stack_id(inventory, watering_stack_id) != null:
		_fail("Shift+left-click removes the equipped durable stack from inventory")
		return
	if _entry_with_stack_id(inventory, hoe_stack_id) == null:
		_fail("Shift+left-click returns the replaced hoe to inventory with its durable stack identity")
		return
	var clothing := load("res://features/inventory/resources/items/peasant_tunic.tres") as ItemDefinition
	var armor := load("res://features/inventory/resources/items/knight_cuirass.tres") as ItemDefinition
	if clothing == null or armor == null or not inventory.add_item(clothing) or not inventory.add_item(armor):
		_fail("clothing and armor fixtures fit in Ada's inventory")
		return
	var clothing_entry = _entry_with_definition(inventory, clothing)
	var clothing_stack_id := str(clothing_entry.stack_id)
	window.refresh()
	_shift_left_click(window, clothing_entry)
	await process_frame
	if equipment.get_equipped_item("chest") != clothing:
		_fail("Shift+left-click equips compatible clothing through its declared slot")
		return
	var armor_entry = _entry_with_definition(inventory, armor)
	window.refresh()
	_shift_left_click(window, armor_entry)
	await process_frame
	if equipment.get_equipped_item("chest") != armor or _entry_with_stack_id(inventory, clothing_stack_id) == null:
		_fail("Shift+left-click armor replaces clothing and returns the clothing to inventory")
		return
	var dagger := load("res://features/inventory/resources/items/steel_dagger.tres") as ItemDefinition
	if dagger == null or not inventory.add_item(dagger):
		_fail("full-inventory replacement fixture fits before blockers are added")
		return
	var dagger_entry = _entry_with_definition(inventory, dagger)
	var dagger_stack_id := str(dagger_entry.stack_id)
	var blocker_definition := load("res://features/inventory/resources/items/tomato_seeds.tres") as ItemDefinition
	if blocker_definition == null:
		_fail("one-cell inventory blocker fixture loads")
		return
	var blocker_sequence := 0
	while true:
		var blocker_cell: Vector2i = inventory.find_first_space(blocker_definition)
		if blocker_cell == Vector2i(-1, -1):
			break
		blocker_sequence += 1
		inventory.entries.append(inventory.create_entry(blocker_definition, blocker_cell, 1, {}, {"validation_blocker": blocker_sequence}))
	window.refresh()
	_shift_left_click(window, dagger_entry)
	await process_frame
	if equipment.get_equipped_item("weapon") != watering_can or _entry_with_stack_id(inventory, dagger_stack_id) == null:
		_fail("Shift+left-click refuses a replacement when the previous equipment cannot return to inventory")
		return
	print("INVENTORY_EQUIPMENT_INTERACTIONS_OK")
	quit(0)


func _entry_with_tool_tag(inventory, tag: String):
	for entry in inventory.entries if inventory != null else []:
		if entry != null and entry.definition != null and entry.definition.has_tool_tag(tag):
			return entry
	return null


func _entry_with_stack_id(inventory, stack_id: String):
	for entry in inventory.entries if inventory != null else []:
		if entry != null and str(entry.stack_id) == stack_id:
			return entry
	return null


func _entry_with_definition(inventory, definition: ItemDefinition):
	for entry in inventory.entries if inventory != null else []:
		if entry != null and entry.definition == definition:
			return entry
	return null


func _shift_left_click(window, entry) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.shift_pressed = true
	event.position = window.inventory_grid._item_rect(entry).get_center()
	window.inventory_grid._gui_input(event)


func _has_visible_button(parent: Control, label: String) -> bool:
	if parent == null:
		return false
	for child in parent.get_children():
		var button := child as Button
		if button != null and button.visible and button.text == label:
			return true
	return false


func _fail(message: String) -> void:
	push_error("INVENTORY_EQUIPMENT_INTERACTIONS_FAILED: %s" % message)
	quit(1)
