extends GutTest

const SHOP = preload("res://features/settlements/bridge/settlement_shop.gd")
const SEEDS = preload("res://features/inventory/resources/items/eggplant_seeds.tres")
const SWORD = preload("res://features/inventory/resources/items/golden_sword.tres")
const SILVER = preload("res://features/inventory/resources/items/silver.tres")

class ServiceGate extends Node:
	func available() -> bool:
		return true

func test_freed_shop_cannot_leave_its_trader_open() -> void:
	var role := MerchantRole.new()
	var gate := ServiceGate.new()
	role.trade_availability = gate.available
	assert_true(role.is_available_for_trade())
	gate.free()
	assert_false(role.is_available_for_trade())
	role.free()

func test_shop_availability_blocks_prices_and_late_trade_arrival() -> void:
	var role := MerchantRole.new()
	var shop := SHOP.new()
	shop.configure_new_merchant(role)
	var state := {"open": true}
	role.set("trade_availability", func(): return state.open)
	var buyer := Node.new()
	role.register_trader(buyer)
	state.open = false
	assert_eq(role.get_buy_price(SEEDS), -1, "Closed shop refuses sale settlement")
	assert_eq(role.get_sell_price(SEEDS), -1, "Closed shop refuses purchase settlement")
	assert_false(role.resolve_trade(buyer), "Arrival after closing cannot open trade")
	state.open = true
	assert_eq(role.get_buy_price(SEEDS), 1)
	assert_eq(role.get_sell_price(SEEDS), 2)
	role.register_trader(buyer)
	assert_true(role.resolve_trade(buyer))
	buyer.free()
	role.free()
	shop.free()

func test_general_prices_unlisted_goods_but_preserves_legacy_whitelist() -> void:
	var role := MerchantRole.new()
	var shop := SHOP.new()
	shop.configure_new_merchant(role)
	assert_eq(role.get_buy_price(SWORD), 1)
	assert_eq(role.get_sell_price(SWORD), 2)
	assert_eq(role.get_buy_price(SILVER), -1)
	role.trading_policy = {}
	assert_eq(role.get_buy_price(SWORD), -1, "old merchants retain explicit pricing only")
	role.free()
	shop.free()

func test_specialization_refuses_unlisted_purchase_but_can_resell_acquired_goods() -> void:
	var role := MerchantRole.new()
	var shop := SHOP.new()
	shop.merchant_profile = load("res://features/settlements/resources/merchants/scrap.tres")
	shop.configure_new_merchant(role)
	assert_eq(role.get_buy_price(SWORD), -1)
	assert_eq(role.get_sell_price(SWORD), 2)
	role.free()
	shop.free()

func test_initial_stock_seeds_once_and_profile_is_not_mutated() -> void:
	var role := MerchantRole.new()
	var shop := SHOP.new()
	var original: Dictionary = shop.merchant_profile.stock.duplicate(true)
	shop.stock_overrides = {SWORD.resource_path: {"quantity": 1, "replenishes": false}}
	shop.configure_new_merchant(role)
	role._seed_shop_inventory()
	var inventory := role.get_shop_inventory()
	assert_eq(inventory.count_item(SWORD), 1)
	assert_eq(inventory.count_item(SILVER), 100)
	inventory.remove_item_count(SWORD, 1)
	role._seed_shop_inventory()
	assert_eq(inventory.count_item(SWORD), 0)
	assert_eq_deep(shop.merchant_profile.stock, original)
	role.free()
	shop.free()

func test_proprietor_has_linked_home_and_default_work_hours() -> void:
	var shop: SettlementShop = load("res://features/settlements/bridge/settlement_shop.tscn").instantiate()
	shop.facility_id = "unit.shop"
	var slots: Array[Dictionary] = shop.get_assignment_slot_specs()
	assert_eq(slots.size(), 2)
	assert_eq(slots[0].assignment_domain, "employment")
	assert_eq_deep(slots[0].work_schedule, {"start_hour": 8, "end_hour": 20})
	assert_eq(slots[1].assignment_domain, "residence")
	assert_eq(slots[1].resident_employment_slot_id, slots[0].slot_id)
	var component := CGameStaffSlot.new()
	component.apply_slot(slots[1])
	assert_eq(component.to_slot().resident_employment_slot_id, "unit.shop.proprietor")
	var population := PopulationController.new()
	assert_false(population._matches_resident_employment({"assignments": {}}, slots[1]))
	assert_true(population._matches_resident_employment({"assignments": {"employment": "unit.shop.proprietor"}}, slots[1]))
	population.free()
	shop.free()

func test_all_presets_fit_and_overfilled_authoring_reports_capacity() -> void:
	var shop := SHOP.new()
	for preset in ["general", "scrap", "weapons", "armor", "clothing"]:
		shop.merchant_profile = load("res://features/settlements/resources/merchants/%s.tres" % preset)
		assert_eq(shop.stock_capacity_warning(), "", preset)
		var role := MerchantRole.new()
		shop.configure_new_merchant(role)
		role._seed_shop_inventory()
		for stock in role.initial_stock:
			assert_eq(role.get_shop_inventory().count_item(stock.item_definition), stock.quantity, stock.item_definition.display_name)
		role.free()
	shop.stock_overrides = {SWORD.resource_path: {"quantity": 9999, "replenishes": false}}
	assert_false(shop.stock_capacity_warning().is_empty())
	shop.free()
