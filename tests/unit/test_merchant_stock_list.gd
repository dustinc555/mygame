extends GutTest

const SEEDS = preload("res://features/inventory/resources/items/eggplant_seeds.tres")
const SILVER = InventoryData.SILVER_ITEM

func test_quantity_purchase_preserves_remainder_identity_and_pays_exactly() -> void:
	var stock := InventoryData.new(10, 10, 0, false)
	var bag := InventoryData.new()
	stock.add_item_count(SEEDS, 12)
	bag.add_item_count(SILVER, 20)
	var entry = stock.entries[0]
	var original_id: String = entry.stack_id
	if not stock.has_method("trade_entries_to_inventory"):
		fail_test("Stock needs a counted, atomic purchase")
		return
	assert_true(stock.call("trade_entries_to_inventory", [entry], 3, bag, 6))
	assert_eq(entry.count, 9)
	assert_eq(entry.stack_id, original_id)
	assert_eq(bag.count_item(SEEDS), 3)
	assert_eq(bag.count_item(SILVER), 14)
	assert_eq(stock.count_item(SILVER), 6)
	for bought in bag.entries:
		if bought.definition == SEEDS:
			assert_ne(bought.stack_id, original_id, "Split stack gets its own identity")


class ShopOwner extends Node3D:
	signal inventory_changed
	var role: MerchantRole
	func get_inventory_for_display():
		return role.get_shop_inventory()
	func get_inventory_display_title():
		return "Pearl"
	func shows_inventory_equipment():
		return true
	func shows_inventory_weight():
		return true


func test_shop_window_uses_bounded_stock_grid_instead_of_personal_equipment() -> void:
	var owner := ShopOwner.new()
	owner.role = MerchantRole.new()
	owner.role.name = "MerchantRole"
	owner.add_child(owner.role)
	owner.role.trading_policy = {"buys_any": true, "sell_price": 2, "buy_price": 1}
	owner.role.get_shop_inventory().add_item_count(SEEDS, 12)
	owner.role.get_shop_inventory().add_item_count(SILVER, 100)
	var window = load("res://features/ui/projection/inventory_window.tscn").instantiate()
	add_child_autofree(window)
	window.setup(owner)
	await get_tree().process_frame
	assert_true(window.inventory_grid.visible, "Shop stock uses the shared footprint grid")
	assert_false(window.weight_label.visible, "Shop stock is not carried weight")
	assert_false(window.auto_sort_button.visible, "Shopping must not rearrange physical stock")
	assert_false(window._equipment_section.visible)
	assert_same(window.inventory_grid.inventory_data, owner.role.get_shop_inventory())
	assert_lte(window.grid_scroll.custom_minimum_size.y, 256.0)
	assert_lt(window.size.y, get_viewport().get_visible_rect().size.y)
	owner.free()


func test_batch_purchase_rolls_back_items_currency_and_identity_when_later_item_wont_fit() -> void:
	var stock := InventoryData.new(10, 10, 0, false)
	var bag := InventoryData.new(2, 2, 60, true)
	var goods := ItemDefinition.new()
	goods.max_stack = 1
	stock.add_item_count(goods, 3)
	assert_true(bag.add_item_count(SILVER, 20), "Fixture must fund the purchase before testing rollback")
	var originals: Array = stock.entries.duplicate()
	watch_signals(stock)
	watch_signals(bag)
	assert_false(stock.trade_entries_to_inventory(originals, 3, bag, 6))
	assert_eq(stock.count_item(goods), 3)
	assert_eq(bag.count_item(goods), 0)
	assert_eq(bag.count_item(SILVER), 20)
	assert_eq(stock.count_item(SILVER), 0)
	for i in range(originals.size()):
		assert_same(stock.entries[i], originals[i])
	assert_signal_not_emitted(stock, "changed")
	assert_signal_not_emitted(bag, "changed")


func test_batch_purchase_refuses_stale_duplicate_mixed_and_unaffordable_requests() -> void:
	var stock := InventoryData.new()
	var bag := InventoryData.new()
	stock.add_item_count(SEEDS, 5)
	bag.add_item_count(SILVER, 4)
	var entry = stock.entries[0]
	assert_false(stock.trade_entries_to_inventory([entry], 3, bag, 6))
	assert_false(stock.trade_entries_to_inventory([entry], 6, bag, 0))
	assert_false(stock.trade_entries_to_inventory([entry, entry], 2, bag, 0))
	assert_false(stock.trade_entries_to_inventory([entry], 0, bag, 0))
	stock.add_entry_with_contents(SEEDS, 1, {}, {"stolen": true})
	assert_false(stock.trade_entries_to_inventory([entry, stock.entries[1]], 2, bag, 0))
	stock.entries.erase(entry)
	assert_false(stock.trade_entries_to_inventory([entry], 1, bag, 0))
	assert_eq(bag.count_item(SILVER), 4)
	assert_eq(bag.count_item(SEEDS), 0)


func test_catalog_groups_only_identical_variants_and_does_not_mutate_stock() -> void:
	var stock := InventoryData.new()
	var a := ItemDefinition.new()
	a.display_name = "Axe"
	var z := ItemDefinition.new()
	z.display_name = "Zinc"
	stock.add_item_count(z, 3)
	stock.add_item_count(a, 2)
	stock.add_entry_with_contents(a, 1, {}, {"stolen": true})
	stock.add_item_count(SILVER, 8)
	var originals: Array = stock.entries.duplicate()
	var list_script = load("res://features/ui/projection/merchant_stock_list.gd")
	var offers: Array = list_script.collect_offers(stock)
	assert_eq(offers.size(), 3)
	assert_eq(offers[0].definition, a)
	assert_eq(offers[0].quantity, 2)
	assert_eq(offers[1].quantity, 1)
	assert_eq(offers[2].definition, z)
	assert_eq(offers[2].quantity, 3)
	for i in range(originals.size()):
		assert_same(stock.entries[i], originals[i])


func test_full_stack_purchase_keeps_contents_metadata_and_stable_id() -> void:
	var stock := InventoryData.new()
	var bag := InventoryData.new()
	stock.add_entry_with_contents(SEEDS, 2, {"condition": 3}, {"origin": "Canyon"}, "shop.exact")
	bag.add_item_count(SILVER, 10)
	var entry = stock.entries[0]
	assert_true(stock.trade_entries_to_inventory([entry], 2, bag, 4))
	var bought = bag.entries[-1]
	assert_eq(bought.stack_id, "shop.exact")
	assert_eq_deep(bought.contained_item_counts, {"condition": 3})
	assert_eq_deep(bought.metadata, {"origin": "Canyon"})
	assert_eq(stock.count_item(SEEDS), 0)


func test_stock_tile_quantity_and_buyer_funds_update_without_mutating_stock() -> void:
	var role := MerchantRole.new()
	role.trading_policy = {"buys_any": true, "sell_price": 2, "buy_price": 1}
	role.get_shop_inventory().add_item_count(SEEDS, 12)
	var bag := InventoryData.new()
	bag.add_item_count(SILVER, 10)
	var panel = load("res://features/ui/projection/merchant_stock_list.gd").new()
	add_child_autofree(panel)
	panel.setup(role)
	if not panel.has_method("set_buyer_inventory"):
		fail_test("Catalog must show the buying character's purse and affordability")
		role.free()
		return
	panel.set_buyer_inventory(bag)
	assert_false(panel.checkout.visible)
	var tile = panel.stock_grid.get_child(0)
	assert_not_null(tile)
	tile.pressed.emit()
	assert_true(panel.checkout.visible)
	assert_true(tile.button_pressed)
	panel.quantity.value = 3
	assert_false(panel.buy_button.disabled)
	assert_string_contains(panel.buy_button.text, "6 silver")
	watch_signals(panel)
	panel.buy_button.pressed.emit()
	assert_signal_emit_count(panel, "purchase_requested", 1)
	var request: Array = get_signal_parameters(panel, "purchase_requested")
	assert_eq(request[1], 3)
	assert_same(request[0][0], role.get_shop_inventory().entries[0])
	bag.remove_item_count(SILVER, 6)
	assert_true(panel.buy_button.disabled)
	assert_string_contains(panel.purse.text, "4 silver")
	assert_eq(role.get_shop_inventory().count_item(SEEDS), 12)

	role.get_shop_inventory().remove_item_count(SEEDS, 12)
	panel.refresh()
	assert_eq(panel.stock_grid.get_child_count(), 0)
	assert_false(panel.checkout.visible)
	assert_true(panel.buy_button.disabled)
	role.free()


class Buyer extends Node3D:
	var inventory := InventoryData.new()
	func get_inventory_for_display():
		return inventory


func _trade_fixture() -> Dictionary:
	var merchant := ShopOwner.new()
	merchant.role = MerchantRole.new()
	merchant.role.name = "MerchantRole"
	merchant.add_child(merchant.role)
	add_child_autofree(merchant)
	merchant.role.trading_policy = {"buys_any": true, "sell_price": 2, "buy_price": 1}
	var stock := merchant.role.get_shop_inventory()
	stock.add_item_count(SEEDS, 12)
	var buyer := Buyer.new()
	add_child_autofree(buyer)
	buyer.inventory.add_item_count(SILVER, 10)
	var window := InventoryWindow.new()
	autofree(window)
	window.inventory_owner = buyer
	var controller := PartyInventoryController.new()
	autofree(controller)
	controller.primary_character_window = window
	return {"merchant": merchant, "buyer": buyer, "stock": stock, "controller": controller}


func test_controller_rechecks_live_price_and_opening_hours_at_purchase() -> void:
	var f := _trade_fixture()
	var entry = f.stock.entries[0]
	f.merchant.role.trade_availability = func(): return false
	f.controller._on_stock_purchase_requested(f.merchant, [entry], 3)
	assert_eq(f.stock.count_item(SEEDS), 12)
	assert_eq(f.buyer.inventory.count_item(SILVER), 10)
	f.merchant.role.trade_availability = Callable()
	f.merchant.role.trading_policy.sell_price = 3
	f.controller._on_stock_purchase_requested(f.merchant, [entry], 3)
	assert_eq(f.stock.count_item(SEEDS), 9)
	assert_eq(f.stock.count_item(SILVER), 9)
	assert_eq(f.buyer.inventory.count_item(SEEDS), 3)
	assert_eq(f.buyer.inventory.count_item(SILVER), 1)


func test_controller_refuses_distant_or_destroyed_merchant_without_payment() -> void:
	var f := _trade_fixture()
	var entry = f.stock.entries[0]
	f.buyer.position = Vector3(6, 0, 0)
	f.controller._on_stock_purchase_requested(f.merchant, [entry], 1)
	assert_eq(f.stock.count_item(SEEDS), 12)
	assert_eq(f.buyer.inventory.count_item(SILVER), 10)
	# The role can disappear when its character projection unloads.
	f.merchant.role.free()
	f.controller._on_stock_purchase_requested(f.merchant, [entry], 1)
	assert_eq(f.buyer.inventory.count_item(SILVER), 10)
	assert_eq(f.buyer.inventory.count_item(SEEDS), 0)


func test_catalog_refresh_after_role_unloads_clears_stale_offers() -> void:
	var role := MerchantRole.new()
	role.get_shop_inventory().add_item_count(SEEDS, 2)
	var panel = load("res://features/ui/projection/merchant_stock_list.gd").new()
	add_child_autofree(panel)
	panel.setup(role)
	role.free()
	panel.refresh()
	assert_eq(panel.stock_grid.get_child_count(), 0)
	assert_true(panel.buy_button.disabled)
	assert_string_contains(panel.merchant_purse.text, "Unavailable")
