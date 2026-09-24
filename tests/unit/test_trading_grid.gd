extends GutTest

const WINDOW = preload("res://features/ui/projection/inventory_window.tscn")
const SEEDS = preload("res://features/inventory/resources/items/eggplant_seeds.tres")
const SILVER = InventoryData.SILVER_ITEM

class Owner extends Node3D:
	signal inventory_changed
	var inventory := InventoryData.new()
	var role: MerchantRole
	var starting_equipment: Array = []
	var equipment := EquipmentCapability.new()
	func _init():
		equipment.setup(self)
	func get_equipment():
		return equipment
	func get_equipment_slot_names() -> Array[String]:
		return ["weapon", "offhand", "backpack"]
	func get_equipped_item(slot: String):
		return equipment.get_equipped_item(slot)
	func can_equip_item_to_slot(item, slot: String):
		return equipment.can_equip_item_to_slot(item, slot)
	func get_inventory_for_display():
		return role.get_shop_inventory() if is_instance_valid(role) else inventory
	func get_merchant_role():
		return role
	func get_inventory_display_title():
		return name
	func shows_inventory_equipment():
		return role == null
	func shows_inventory_weight():
		return role == null

class Notice extends Node:
	var messages: Array[String] = []
	func show_message(message: String) -> void:
		messages.append(message)

var notice: Notice
var buyer: Owner
var merchant: Owner
var controller: PartyInventoryController
var viewport: SubViewport
var stock: InventoryData

func before_each() -> void:
	buyer = Owner.new()
	buyer.name = "Mira"
	merchant = Owner.new()
	merchant.name = "Trader"
	add_child_autofree(buyer)
	add_child_autofree(merchant)
	merchant.role = MerchantRole.new()
	merchant.role.trading_policy = {"buys_any": true, "sell_price": 2, "buy_price": 1}
	merchant.add_child(merchant.role)
	stock = merchant.role.get_shop_inventory()
	assert_true(stock.add_item_count(SEEDS, 3))
	assert_true(stock.add_item_count(SILVER, 50))
	assert_true(buyer.inventory.add_item_count(SILVER, 20))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 900)
	add_child_autofree(viewport)
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(layer)
	layer.size = Vector2(1280, 900)
	controller = PartyInventoryController.new()
	add_child_autofree(controller)
	controller.set_process(false)
	notice = Notice.new()
	add_child_autofree(notice)
	controller.floating_notice = notice
	controller.inventory_window_layer = layer
	buyer.inventory.changed.connect(func(): buyer.inventory_changed.emit())
	controller.open_inventory_pair(buyer, merchant)
	await get_tree().process_frame

func test_merchant_matches_character_height_and_expands_stock_viewport() -> void:
	for frame in range(6):
		await get_tree().process_frame
	var player := controller.primary_character_window
	var shop := controller.secondary_inventory_window
	assert_eq(shop.size.y, player.size.y)
	assert_gt(shop.grid_scroll.size.y, 256.0, "Added height belongs to the scrollable stock")
	assert_eq(shop.inventory_grid.cell_size, player.inventory_grid.cell_size)
	assert_lt(shop.trade_footer.get_global_rect().end.y, shop.get_global_rect().end.y)
	assert_gte(shop.trade_footer.global_position.y, shop.grid_scroll.get_global_rect().end.y)

func test_merchant_height_tracks_character_refresh_and_reset() -> void:
	for frame in range(6):
		await get_tree().process_frame
	var player := controller.primary_character_window
	var shop := controller.secondary_inventory_window
	var original_height := player.size.y
	player.custom_minimum_size.y = original_height + 28
	player.fit_to_content()
	for frame in range(6):
		await get_tree().process_frame
	assert_gt(player.size.y, original_height)
	assert_eq(shop.size.y, player.size.y)
	player.custom_minimum_size.y = 0
	controller._cancel_trade()
	for frame in range(6):
		await get_tree().process_frame
	assert_eq(shop.size.y, player.size.y)
	assert_eq(player.size.y, original_height)

func test_ending_trade_releases_merchant_height_match() -> void:
	for frame in range(6):
		await get_tree().process_frame
	var shop := controller.secondary_inventory_window
	var matched_height := shop.size.y
	controller._end_trade()
	for frame in range(6):
		await get_tree().process_frame
	assert_lt(shop.size.y, matched_height)
	assert_eq(shop.size, shop.get_combined_minimum_size())

func test_merchant_drag_proposes_a_deal_without_moving_goods_or_silver() -> void:
	var goods = stock.entries[0]
	controller._on_inventory_transfer_requested(merchant, buyer, goods, Vector2i(3, 0))
	assert_eq(stock.count_item(SEEDS), 3, "Dragging merchant goods must wait for Trade")
	assert_eq(buyer.inventory.count_item(SEEDS), 0)
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SILVER), 50)
	assert_same(stock.entries[0], goods)

func test_shopping_uses_the_same_footprint_grid_with_a_visible_trade_button() -> void:
	var window := controller.secondary_inventory_window
	assert_true(window.inventory_grid.is_visible_in_tree(), "Merchant uses the same slots as party bags")
	assert_eq(window.inventory_grid.cell_size, controller.primary_character_window.inventory_grid.cell_size)
	var button = window.find_child("TradeButton", true, false)
	assert_not_null(button, "Settlement must be an explicit visible action")
	if button == null:
		return
	var goods = stock.entries[0]
	controller._on_inventory_transfer_requested(merchant, buyer, goods, Vector2i(3, 0))
	button.pressed.emit()
	assert_eq(stock.count_item(SEEDS), 0)
	assert_eq(buyer.inventory.count_item(SEEDS), 3)
	assert_eq(buyer.inventory.count_item(SILVER), 14)
	assert_eq(stock.count_item(SILVER), 56)
	assert_eq(buyer.inventory.get_entry_at_cell(Vector2i(3, 0)).stack_id, goods.stack_id)

func test_sell_and_buy_settle_only_the_net_silver() -> void:
	var bread = load("res://features/inventory/resources/items/bread.tres")
	assert_true(buyer.inventory.add_item_count(bread, 2))
	controller._cancel_trade()
	for entry in buyer.inventory.entries:
		if entry.definition == bread:
			controller._offer_trade_item(buyer, entry, -1)
	controller._offer_trade_item(merchant, stock.entries[0], -1)
	assert_eq(controller.trade_session.net_silver(), 4)
	controller._confirm_trade()
	assert_eq(buyer.inventory.count_item(bread), 0)
	assert_eq(stock.count_item(bread), 2)
	assert_eq(buyer.inventory.count_item(SEEDS), 3)
	assert_eq(buyer.inventory.count_item(SILVER), 16)
	assert_eq(stock.count_item(SILVER), 54)

func test_sell_only_pays_the_player_and_keeps_metadata() -> void:
	assert_true(buyer.inventory.add_item_count(SEEDS, 2))
	var sold = buyer.inventory.entries[-1]
	sold.metadata = {"origin": "salvage"}
	controller._cancel_trade()
	controller._offer_trade_item(buyer, sold, -1)
	controller._confirm_trade()
	assert_eq(buyer.inventory.count_item(SEEDS), 0)
	assert_eq(buyer.inventory.count_item(SILVER), 22)
	assert_eq(stock.count_item(SILVER), 48)
	var found := false
	for entry in stock.entries:
		if entry.stack_id == sold.stack_id:
			found = entry.metadata == {"origin": "salvage"} and entry.count == 2
	assert_true(found)

func test_partial_purchase_preserves_remainder_and_allocates_new_identity() -> void:
	var goods = stock.entries[0]
	controller._offer_trade_item(merchant, goods, 1)
	controller._confirm_trade()
	assert_eq(goods.count, 2)
	assert_eq(buyer.inventory.count_item(SEEDS), 1)
	assert_eq(buyer.inventory.count_item(SILVER), 18)
	for entry in buyer.inventory.entries:
		if entry.definition == SEEDS:
			assert_ne(entry.stack_id, goods.stack_id)

func test_cancel_and_close_preserve_goods_purses_and_positions() -> void:
	var goods = stock.entries[0]
	var original_cell: Vector2i = goods.grid_position
	controller._offer_trade_item(merchant, goods, -1)
	controller.secondary_inventory_window.find_child("CancelTradeButton", true, false).pressed.emit()
	assert_true(controller.trade_session.offers.is_empty())
	controller._offer_trade_item(merchant, goods, -1)
	controller.secondary_inventory_window.close_button.pressed.emit()
	assert_null(controller.trade_session)
	assert_same(stock.entries[0], goods)
	assert_eq(goods.grid_position, original_cell)
	assert_eq(buyer.inventory.count_item(SEEDS), 0)
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SILVER), 50)

func test_insufficient_funds_refuses_without_partial_transfer() -> void:
	assert_true(buyer.inventory.remove_item_count(SILVER, 19))
	controller._cancel_trade()
	controller._offer_trade_item(merchant, stock.entries[0], -1)
	controller._confirm_trade()
	assert_eq(stock.count_item(SEEDS), 3)
	assert_eq(buyer.inventory.count_item(SEEDS), 0)
	assert_eq(buyer.inventory.count_item(SILVER), 1)
	assert_eq(stock.count_item(SILVER), 50)
	assert_eq(notice.messages, ["Cannot afford"])

func test_rejected_admission_rolls_back_both_purses_and_original_entries() -> void:
	var goods = stock.entries[0]
	var coins = buyer.inventory.entries[0]
	controller._offer_trade_item(merchant, goods, -1)
	buyer.inventory.admission_validator = func(_definition, _amount): return false
	controller._confirm_trade()
	assert_same(stock.entries[0], goods)
	assert_same(buyer.inventory.entries[0], coins)
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SILVER), 50)
	assert_eq(buyer.inventory.count_item(SEEDS), 0)

func test_changed_price_or_closed_shop_cannot_commit_stale_offer() -> void:
	controller._offer_trade_item(merchant, stock.entries[0], -1)
	merchant.role.trading_policy.sell_price = 9
	controller._confirm_trade()
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SEEDS), 3)
	controller._cancel_trade()
	controller._offer_trade_item(merchant, stock.entries[0], -1)
	merchant.role.queue_free()
	await get_tree().process_frame
	controller._confirm_trade()
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SEEDS), 3)

func test_drag_back_withdraws_and_shows_centered_landing_preview() -> void:
	var window := controller.primary_character_window
	var goods = stock.entries[0]
	var payload := {"source_owner": merchant, "entry": goods}
	var center: Vector2 = window.inventory_grid._item_rect_from_definition(SEEDS, Vector2i(3, 0)).get_center()
	assert_true(window.inventory_grid._can_drop_data(center, payload))
	assert_eq(window.inventory_grid._preview_rect.get_center(), center)
	window.inventory_grid._drop_data(center, payload)
	assert_eq(controller.trade_session.offers.size(), 1)
	var incoming = window.inventory_grid.inventory_data.get_entry_at_cell(Vector2i(3, 0))
	controller._on_inventory_transfer_requested(buyer, merchant, incoming, goods.grid_position)
	assert_true(controller.trade_session.offers.is_empty())
	assert_eq(buyer.inventory.count_item(SILVER), 20)

func test_trade_preview_cannot_fall_to_ground() -> void:
	var window := controller.primary_character_window
	watch_signals(window)
	controller._offer_trade_item(merchant, stock.entries[0], -1)
	window._on_inventory_item_dropped_outside(buyer, window.inventory_grid.inventory_data.entries[-1])
	assert_signal_not_emitted(window, "item_drop_requested")
	assert_eq(stock.count_item(SEEDS), 3)

func test_currency_is_not_a_sellable_offer() -> void:
	controller._offer_trade_item(buyer, buyer.inventory.entries[0], -1)
	assert_true(controller.trade_session.offers.is_empty())
	assert_eq(buyer.inventory.count_item(SILVER), 20)

func test_second_item_rejection_rolls_back_the_entire_deal() -> void:
	var bread = load("res://features/inventory/resources/items/bread.tres")
	assert_true(stock.add_item_count(bread, 1))
	controller._cancel_trade()
	var seeds = stock.entries[0]
	var loaf = stock.entries[-1]
	controller._offer_trade_item(merchant, seeds, -1)
	controller._offer_trade_item(merchant, loaf, -1)
	assert_eq(controller.trade_session.offers.size(), 2)
	buyer.inventory.admission_validator = func(definition, _amount): return definition != bread
	controller._confirm_trade()
	assert_same(stock.entries[0], seeds)
	assert_same(stock.entries[-1], loaf)
	assert_eq(buyer.inventory.count_item(SEEDS), 0)
	assert_eq(buyer.inventory.count_item(bread), 0)
	assert_eq(stock.count_item(SEEDS), 3)
	assert_eq(stock.count_item(bread), 1)
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SILVER), 50)

func test_merchant_cannot_pay_for_sale_without_silver() -> void:
	assert_true(stock.remove_item_count(SILVER, 50))
	assert_true(buyer.inventory.add_item_count(SEEDS, 2))
	controller._cancel_trade()
	controller._offer_trade_item(buyer, buyer.inventory.entries[-1], -1)
	controller._confirm_trade()
	assert_eq(buyer.inventory.count_item(SEEDS), 2)
	assert_eq(stock.count_item(SEEDS), 3)
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SILVER), 0)
	assert_eq(notice.messages, ["Cannot afford"])

func test_weight_failure_rolls_back_goods_and_payment() -> void:
	var bread = load("res://features/inventory/resources/items/bread.tres")
	assert_true(stock.add_item_count(bread, 1))
	controller._cancel_trade()
	controller._offer_trade_item(merchant, stock.entries[-1], -1)
	buyer.inventory.use_weight = true
	buyer.inventory.max_weight = buyer.inventory.get_total_weight()
	controller._confirm_trade()
	assert_eq(buyer.inventory.count_item(bread), 0)
	assert_eq(stock.count_item(bread), 1)
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SILVER), 50)
	assert_eq(notice.messages, ["No room or carrying capacity"])

func test_full_pouch_count_fits_inside_its_item_footprint() -> void:
	var grid := controller.primary_character_window.inventory_grid
	var rect: Rect2 = grid._item_rect(buyer.inventory.entries[0])
	var label := "250/250"
	var font_size: int = grid.call("_count_label_font_size", rect, label)
	var text_width: float = grid.get_theme_default_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	assert_lte(text_width, rect.size.x - 12.0)
	assert_gte(font_size, 10)

func test_pending_purchase_can_be_repositioned_without_changing_the_deal() -> void:
	var window := controller.primary_character_window
	controller._on_inventory_transfer_requested(merchant, buyer, stock.entries[0], Vector2i(3, 0))
	var incoming = window.inventory_grid.inventory_data.get_entry_at_cell(Vector2i(3, 0))
	var payload := {"source_owner": buyer, "entry": incoming}
	var center: Vector2 = window.inventory_grid._item_rect_from_definition(SEEDS, Vector2i(5, 1)).get_center()
	assert_true(window.inventory_grid._can_drop_data(center, payload))
	window.inventory_grid._drop_data(center, payload)
	assert_eq(controller.trade_session.offers.size(), 1)
	assert_eq(controller.trade_session.net_silver(), 6)
	controller._confirm_trade()
	var bought = buyer.inventory.get_entry_at_cell(Vector2i(5, 1))
	assert_not_null(bought)
	if bought != null:
		assert_eq(bought.definition, SEEDS)
	assert_eq(buyer.inventory.count_item(SILVER), 14)

func test_reset_keeps_owned_rearrangement_and_clears_only_offers() -> void:
	controller._on_inventory_transfer_requested(merchant, buyer, stock.entries[0], Vector2i(3, 0))
	var coins = controller.primary_character_window.inventory_grid.inventory_data.entries[0]
	controller._on_inventory_transfer_requested(buyer, buyer, coins, Vector2i(7, 2))
	assert_eq(buyer.inventory.entries[0].grid_position, Vector2i(7, 2))
	assert_eq(controller.trade_session.offers.size(), 1)
	assert_true(controller.trade_session.is_current())
	var reset = controller.secondary_inventory_window.find_child("CancelTradeButton", true, false)
	assert_eq(reset.text, "Reset")
	reset.pressed.emit()
	assert_true(controller.trade_session.offers.is_empty())
	assert_eq(buyer.inventory.entries[0].grid_position, Vector2i(7, 2))
	assert_eq(buyer.inventory.count_item(SILVER), 20)

func test_replacing_inventory_cannot_spend_from_old_bag() -> void:
	controller._offer_trade_item(merchant, stock.entries[0], -1)
	var old_bag := buyer.inventory
	buyer.inventory = InventoryData.new()
	controller._confirm_trade()
	assert_eq(old_bag.count_item(SILVER), 20)
	assert_eq(old_bag.count_item(SEEDS), 0)
	assert_eq(buyer.inventory.entries.size(), 0)
	assert_eq(stock.count_item(SEEDS), 3)
	assert_eq(stock.count_item(SILVER), 50)

func test_shop_keeps_player_equipment_and_direct_purchase_waits_for_trade() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	assert_true(stock.add_item_count(sword, 1))
	controller._cancel_trade()
	var goods = stock.entries[-1]
	var window := controller.primary_character_window
	assert_true(window._equipment_section.is_visible_in_tree())
	var slot = window._equipment_slots["weapon"]
	var data := {"source_owner": merchant, "entry": goods}
	assert_true(slot._can_drop_data(Vector2.ZERO, data))
	slot._drop_data(Vector2.ZERO, data)
	assert_null(buyer.get_equipped_item("weapon"), "A purchase preview cannot grant combat equipment")
	assert_eq(stock.count_item(sword), 1)
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(slot._get_equipped_item(), sword)
	controller._confirm_trade()
	assert_eq(buyer.get_equipped_item("weapon"), sword)
	assert_eq(buyer.equipment.get_equipped_stack_id("weapon"), goods.stack_id)
	assert_eq(stock.count_item(sword), 0)
	assert_eq(buyer.inventory.count_item(SILVER), 18)

func test_purchase_swap_preserves_old_gear_and_reset_restores_preview() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	buyer.equipment.equip_item_to_slot(sword, "weapon", "owned-sword")
	assert_true(stock.add_item_count(sword, 1))
	controller._cancel_trade()
	var goods = stock.entries[-1]
	controller._on_inventory_equip_requested(merchant, goods, buyer, "weapon")
	assert_eq(buyer.equipment.get_equipped_stack_id("weapon"), "owned-sword")
	var displaced = controller.primary_character_window.inventory_grid.inventory_data.entries[-1]
	assert_eq(displaced.stack_id, "owned-sword")
	controller._on_inventory_transfer_requested(buyer, buyer, displaced, Vector2i(7, 0))
	assert_eq(controller.primary_character_window.inventory_grid.inventory_data.get_entry_at_cell(Vector2i(7, 0)).stack_id, "owned-sword")
	controller._cancel_trade()
	assert_eq(buyer.equipment.get_equipped_stack_id("weapon"), "owned-sword")
	assert_eq(buyer.inventory.count_item(sword), 0)
	controller._on_inventory_equip_requested(merchant, goods, buyer, "weapon")
	controller._confirm_trade()
	assert_eq(buyer.equipment.get_equipped_stack_id("weapon"), goods.stack_id)
	assert_eq(buyer.inventory.count_item(sword), 1)
	assert_eq(buyer.inventory.entries[-1].stack_id, "owned-sword")

func test_owned_gear_can_unequip_and_reequip_without_resetting_offers() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	buyer.equipment.equip_item_to_slot(sword, "weapon", "owned-sword")
	controller._cancel_trade()
	controller._on_inventory_transfer_requested(merchant, buyer, stock.entries[0], Vector2i(3, 0))
	var window := controller.primary_character_window
	var payload := {"equipment_owner": buyer, "equip_slot": "weapon", "item_definition": sword}
	var center: Vector2 = window.inventory_grid._item_rect_from_definition(sword, Vector2i(7, 0)).get_center()
	assert_true(window.inventory_grid._can_drop_data(center, payload))
	window.inventory_grid._drop_data(center, payload)
	assert_null(buyer.get_equipped_item("weapon"))
	assert_eq(buyer.inventory.count_item(sword), 1)
	assert_true(controller.trade_session.is_current())
	assert_eq(controller.trade_session.offers.size(), 1)
	var moved = window.inventory_grid.inventory_data.get_entry_at_cell(Vector2i(7, 0))
	controller._on_inventory_equip_requested(buyer, moved, buyer, "weapon")
	assert_eq(buyer.get_equipped_item("weapon"), sword)
	assert_true(controller.trade_session.is_current())
	controller._cancel_trade()
	assert_eq(buyer.get_equipped_item("weapon"), sword)
	assert_eq(buyer.inventory.count_item(SILVER), 20)

func test_equipped_item_can_be_offered_directly_and_reset_never_unequips_it() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	buyer.equipment.equip_item_to_slot(sword, "weapon", "owned-sword")
	controller._cancel_trade()
	controller._on_inventory_unequip_requested(buyer, "weapon", merchant, Vector2i(5, 0))
	assert_eq(stock.count_item(sword), 0)
	assert_eq(buyer.get_equipped_item("weapon"), sword)
	assert_eq(controller.trade_session.net_silver(), -1)
	controller._cancel_trade()
	assert_eq(buyer.get_equipped_item("weapon"), sword)
	controller._on_inventory_unequip_requested(buyer, "weapon", merchant, Vector2i(5, 0))
	controller._confirm_trade()
	assert_null(buyer.get_equipped_item("weapon"))
	assert_eq(stock.count_item(sword), 1)
	assert_eq(buyer.inventory.count_item(SILVER), 21)

func test_equipment_preview_can_move_back_to_bag_without_changing_price() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	assert_true(stock.add_item_count(sword, 1))
	controller._cancel_trade()
	controller._on_inventory_equip_requested(merchant, stock.entries[-1], buyer, "weapon")
	var window := controller.primary_character_window
	var payload: Dictionary = window._trade_equipment_drag("weapon")
	var center: Vector2 = window.inventory_grid._item_rect_from_definition(sword, Vector2i(7, 0)).get_center()
	assert_true(window.inventory_grid._can_drop_data(center, payload))
	window.inventory_grid._drop_data(center, payload)
	assert_null(window._equipment_slots["weapon"]._get_equipped_item())
	assert_eq(controller.trade_session.net_silver(), 2)
	controller._confirm_trade()
	assert_null(buyer.get_equipped_item("weapon"))
	assert_eq(buyer.inventory.get_entry_at_cell(Vector2i(7, 0)).definition, sword)

func test_withdrawing_equipped_sale_keeps_displaced_item_when_buying_replacement() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	buyer.equipment.equip_item_to_slot(sword, "weapon", "owned-sword")
	assert_true(stock.add_item_count(sword, 1))
	controller._cancel_trade()
	controller._on_inventory_unequip_requested(buyer, "weapon", merchant, Vector2i(5, 0))
	var sold = controller.trade_session.offers[0].entry
	var goods = stock.entries[-1]
	controller._on_inventory_equip_requested(merchant, goods, buyer, "weapon")
	controller.trade_session.withdraw(sold)
	controller._confirm_trade()
	assert_eq(buyer.equipment.get_equipped_stack_id("weapon"), goods.stack_id)
	assert_eq(buyer.inventory.count_item(sword), 1, "Withdrawing the sale must not destroy displaced equipment")
	assert_eq(buyer.inventory.entries[-1].stack_id, "owned-sword")

func test_full_bag_rejects_purchase_replacement_without_touching_equipment() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	buyer.equipment.equip_item_to_slot(sword, "weapon", "owned-sword")
	assert_true(stock.add_item_count(sword, 1))
	buyer.inventory.columns = 1
	buyer.inventory.rows = 1
	controller._cancel_trade()
	controller._on_inventory_equip_requested(merchant, stock.entries[-1], buyer, "weapon")
	assert_true(controller.trade_session.offers.is_empty())
	assert_eq(buyer.equipment.get_equipped_stack_id("weapon"), "owned-sword")
	assert_eq(stock.count_item(sword), 1)

func test_equipment_purchase_weight_refusal_restores_goods_payment_and_old_gear() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	buyer.equipment.equip_item_to_slot(sword, "weapon", "owned-sword")
	assert_true(stock.add_item_count(sword, 1))
	controller._cancel_trade()
	var goods = stock.entries[-1]
	controller._on_inventory_equip_requested(merchant, goods, buyer, "weapon")
	assert_eq(controller.trade_session.offers.size(), 1)
	buyer.inventory.use_weight = true
	buyer.inventory.max_weight = buyer.inventory.get_total_weight()
	controller._confirm_trade()
	assert_eq(buyer.equipment.get_equipped_stack_id("weapon"), "owned-sword")
	assert_true(stock.entries.has(goods), "Rollback retains the exact stock entry")
	assert_eq(buyer.inventory.count_item(sword), 0)
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SILVER), 50)
	assert_true(controller.trade_session.is_current())
	assert_eq(notice.messages, ["No room or carrying capacity"])

func test_equipped_sale_to_broke_merchant_keeps_gear_equipped() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	buyer.equipment.equip_item_to_slot(sword, "weapon", "owned-sword")
	assert_true(stock.remove_item_count(SILVER, 50))
	controller._cancel_trade()
	controller._on_inventory_unequip_requested(buyer, "weapon", merchant, Vector2i(5, 0))
	controller._confirm_trade()
	assert_eq(buyer.equipment.get_equipped_stack_id("weapon"), "owned-sword")
	assert_eq(stock.count_item(sword), 0)
	assert_eq(buyer.inventory.count_item(sword), 0)
	assert_eq(buyer.inventory.count_item(SILVER), 20)
	assert_eq(stock.count_item(SILVER), 0)
	assert_eq(notice.messages, ["Cannot afford"])

func test_full_bag_barter_reuses_offered_cells_in_one_deal() -> void:
	var ore = load("res://features/inventory/resources/items/copper_ore.tres")
	var bread = load("res://features/inventory/resources/items/bread.tres")
	buyer.inventory.entries.clear()
	buyer.inventory.columns = 3
	buyer.inventory.rows = 4
	assert_true(buyer.inventory.add_item_count(ore, 2))
	assert_true(stock.add_item_count(bread, 1))
	var sold = buyer.inventory.entries[0]
	var loaf = stock.entries[-1]
	controller._cancel_trade()
	for entry in buyer.inventory.entries.duplicate():
		controller._offer_trade_item(buyer, entry, -1)
	var session = controller.trade_session
	assert_eq(session.views[0].entries.size(), 0, "Offers free the source cells immediately")
	assert_eq(session.entry_state(1, session._view_entry(1, sold.stack_id)), "incoming")
	controller._on_inventory_transfer_requested(merchant, buyer, loaf, Vector2i.ZERO)
	assert_eq(session.offers.size(), 3)
	assert_null(session._view_entry(1, loaf.stack_id), "No outgoing duplicate in merchant stock")
	assert_eq(buyer.inventory.count_item(ore), 2, "Live goods wait for settlement")
	controller._confirm_trade()
	assert_eq(notice.messages, [])
	assert_eq(buyer.inventory.count_item(ore), 0)
	assert_eq(buyer.inventory.count_item(bread), 1)
	assert_eq(stock.count_item(ore), 2)
	assert_eq(stock.count_item(bread), 0)
	assert_eq(buyer.inventory.count_item(SILVER), 0)

func test_partial_offer_leaves_normal_remainder_and_can_offer_more() -> void:
	var goods = stock.entries[0]
	controller._offer_trade_item(merchant, goods, 1)
	var session = controller.trade_session
	var remainder = session._view_entry(1, goods.stack_id)
	assert_eq(remainder.count, 2)
	assert_eq(session.entry_state(1, remainder), "")
	controller._offer_trade_item(merchant, remainder, -1)
	assert_eq(session.offers.size(), 1)
	assert_eq(session.offers[0].count, 3)
	assert_null(session._view_entry(1, goods.stack_id))
	controller._cancel_trade()
	assert_eq(stock.count_item(SEEDS), 3)
	assert_eq(session.views[1].count_item(SEEDS), 3)

func test_withdraw_cannot_overlap_purchase_in_freed_source_cells() -> void:
	assert_true(buyer.inventory.add_item_count(SEEDS, 2))
	var sold = buyer.inventory.entries[-1]
	var cell: Vector2i = sold.grid_position
	controller._cancel_trade()
	controller._offer_trade_item(buyer, sold, -1)
	var session = controller.trade_session
	controller._on_inventory_transfer_requested(merchant, buyer, stock.entries[0], cell)
	var incoming_sale = session._view_entry(1, sold.stack_id)
	assert_eq(session.propose(1, incoming_sale, 0, cell), "No room")
	assert_eq(session.offers.size(), 2)
	controller._cancel_trade()
	assert_eq(buyer.inventory.count_item(SEEDS), 2)
	assert_eq(stock.count_item(SEEDS), 3)

func test_rearrangement_into_offered_cells_waits_for_commit() -> void:
	assert_true(buyer.inventory.add_item_count(SEEDS, 1))
	var sold = buyer.inventory.entries[-1]
	var coins = buyer.inventory.entries[0]
	var original_cell: Vector2i = coins.grid_position
	var cell: Vector2i = sold.grid_position
	controller._cancel_trade()
	controller._offer_trade_item(buyer, sold, -1)
	controller._on_inventory_transfer_requested(buyer, buyer, coins, cell)
	assert_eq(controller.trade_session._view_entry(0, coins.stack_id).grid_position, cell)
	assert_eq(coins.grid_position, original_cell, "No overlap in authoritative inventory before Trade")
	controller._confirm_trade()
	assert_eq(notice.messages, [])
	assert_eq(coins.grid_position, cell)
	assert_eq(buyer.inventory.count_item(SEEDS), 0)
	assert_eq(buyer.inventory.count_item(SILVER), 21)

func test_selling_equipped_weapon_allows_replacement_with_full_bag() -> void:
	var sword = load("res://features/inventory/resources/items/steel_sword.tres")
	var ore = load("res://features/inventory/resources/items/copper_ore.tres")
	buyer.inventory.entries.clear()
	buyer.inventory.columns = 3
	buyer.inventory.rows = 4
	assert_true(buyer.inventory.add_item_count(ore, 2))
	buyer.equipment.equip_item_to_slot(sword, "weapon", "old-sword")
	assert_true(stock.add_item_count(sword, 1))
	var replacement = stock.entries[-1]
	controller._cancel_trade()
	controller._on_inventory_unequip_requested(buyer, "weapon", merchant, Vector2i(5, 0))
	controller._on_inventory_equip_requested(merchant, replacement, buyer, "weapon")
	assert_eq(controller.trade_session.offers.size(), 2)
	assert_eq(notice.messages, [])
	assert_eq(controller.trade_session.equipment_entry("weapon").stack_id, replacement.stack_id)
	controller._cancel_trade()
	assert_eq(buyer.equipment.get_equipped_stack_id("weapon"), "old-sword")
	assert_eq(buyer.inventory.count_item(ore), 2)

func test_reset_discards_rearrangement_that_depends_on_a_sale() -> void:
	assert_true(buyer.inventory.add_item_count(SEEDS, 1))
	var sold = buyer.inventory.entries[-1]
	var coins = buyer.inventory.entries[0]
	var original_cell: Vector2i = coins.grid_position
	controller._cancel_trade()
	controller._offer_trade_item(buyer, sold, -1)
	controller._on_inventory_transfer_requested(buyer, buyer, coins, sold.grid_position)
	controller._cancel_trade()
	assert_eq(coins.grid_position, original_cell)
	assert_eq(controller.trade_session._view_entry(0, coins.stack_id).grid_position, original_cell)
	assert_true(controller.trade_session._layout_valid(controller.trade_session.views))
	assert_eq(buyer.inventory.count_item(SEEDS), 1)

func test_trade_error_does_not_shift_any_inventory_controls() -> void:
	assert_true(buyer.inventory.remove_item_count(SILVER, 19))
	controller._cancel_trade()
	controller._offer_trade_item(merchant, stock.entries[0], -1)
	for frame in range(6):
		await get_tree().process_frame
	var shop := controller.secondary_inventory_window
	var player := controller.primary_character_window
	var controls: Array[Control] = [shop, shop.grid_scroll, shop.bag_actions, shop.trade_footer, player, player.inventory_grid]
	var rectangles: Array[Rect2] = []
	for control in controls:
		rectangles.append(control.get_global_rect())
	controller._confirm_trade()
	for frame in range(6):
		await get_tree().process_frame
	assert_eq(notice.messages, ["Cannot afford"])
	for index in range(controls.size()):
		assert_eq(controls[index].get_global_rect(), rectangles[index], controls[index].name)
