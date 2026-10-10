extends SceneTree
## Opt-in authored-content proof; no world startup, save mutation or live merchant reset.
const BAG_PATH := "res://features/inventory/resources/items/medium_leather_bag.tres"
const POLICY = preload("res://features/settlements/resources/merchant_stock_policy.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	await process_frame
	var bag: ItemDefinition = load(BAG_PATH)
	var zone: PackedScene = load("res://scenes/zones/rustwash_basin/rustwash_basin.tscn")
	var state := zone.get_state()
	var shop = load("res://features/settlements/bridge/settlement_shop.gd").new()
	var found := false
	for index in state.get_node_count():
		if state.get_node_name(index) != &"CanyonTradeStation": continue
		found = true
		for property in state.get_node_property_count(index):
			var key := state.get_node_property_name(index, property)
			if key in [&"stock_overrides", &"merchant_profile", &"stock_columns", &"stock_rows", &"starting_silver", &"replenishment_days", &"replenishment_hour"]:
				shop.set(key, state.get_node_property_value(index, property))
	check(found, "Canonical Canyon trading station exists")
	var rule: Dictionary = shop.effective_stock().get(BAG_PATH, {})
	check(rule == {"quantity": 2, "replenishes": true}, "Canyon replenishes to two bags")
	check(shop.stock_capacity_warning().is_empty(), "Authored stock fits the real merchant grid")
	var role = load("res://features/settlements/bridge/merchant_role.gd").new()
	shop.configure_new_merchant(role)
	var inventory := InventoryData.new()
	inventory.columns = role.shop_inventory_columns
	inventory.rows = role.shop_inventory_rows
	inventory.use_weight = false
	for stock in role.initial_stock:
		inventory.add_item_count(stock.item_definition, stock.quantity)
	check(inventory.count_item(bag) == 2, "Fresh merchant actually starts with two bags")
	var silver: ItemDefinition = load("res://features/inventory/resources/items/silver.tres")
	var money_before := inventory.count_item(silver)
	check(inventory.remove_item_count(bag, 1), "One bag can leave stock")
	check(inventory.count_item(bag) == 1, "Purchase reduces stock")
	POLICY.replenish(inventory, role.trading_policy.stock)
	check(inventory.count_item(bag) == 2, "Restock replaces the missing bag")
	POLICY.replenish(inventory, role.trading_policy.stock)
	check(inventory.count_item(bag) == 2, "Restock does not accumulate bags")
	inventory.add_item_count(bag, 1)
	POLICY.replenish(inventory, role.trading_policy.stock)
	check(inventory.count_item(bag) == 3, "Goods sold above target remain real stock")
	check(inventory.count_item(silver) == money_before, "Replenishment never mints currency")
	check(POLICY.first_due_minute(600, role.trading_policy.days, role.trading_policy.hour) == 4800, "Normal three-day, 08:00 delivery schedule")
	print("MEDIUM_LEATHER_BAG_STOCK ", JSON.stringify({"failures": failures, "initial": 2, "after_restock": 2, "above_target_retained": inventory.count_item(bag), "days": shop.replenishment_days, "hour": shop.replenishment_hour, "silver_preserved": inventory.count_item(silver) == money_before}))
	role.free()
	shop.free()
	quit(0 if failures.is_empty() else 1)
