extends SceneTree

## Historical audit identity; the contract is independent of authored towns.
const FIXTURE := "res://tests/validation/fixtures/farming_replay/farming_replay.tscn"
const SETTLEMENT_ID := "farming_replay"
const EGGPLANT := preload("res://features/inventory/resources/items/eggplant.tres")
const SEEDS := preload("res://features/inventory/resources/items/eggplant_seeds.tres")
const GENERIC_FOOD := preload("res://features/inventory/resources/items/food.tres")
var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = (load(FIXTURE) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	var deadline := Time.get_ticks_msec() + 60000
	while not _fixture_ready() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _fixture_ready():
		_expect(false, "fixture services, physical farm and funded containers did not become ready")
		_finish()
		return
	var context := BootstrapContext.active
	var clock = context.get_optional(&"world_time")
	clock.request_manual_pause()
	var seed_container = game.get_node("Town/Seeds")
	var pallet = game.get_node("Town/Produce")
	var reserve = game.get_node("Town/FoodReserve")
	_expect(seed_container.container_type == "seeds" and seed_container.inventory.count_item(SEEDS) > 0, "seed exclusion starts with real funded typed storage")
	_expect(not seed_container.can_accept_item_count(EGGPLANT, 1), "funded seed container rejects harvested produce")
	_expect(pallet.container_type == "food" and pallet.contributes_to_town_stock and pallet.can_accept_item_count(EGGPLANT, 1), "produce pallet is authoritative physical storage")
	var nav_obstacle := pallet.get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
	_expect(pallet.collision_layer == 1 and nav_obstacle != null and nav_obstacle.affect_navigation_mesh, "real produce pallet retains collision and navigation obstruction")
	var settlements = context.get_optional(&"settlement")
	var food = context.get_optional(&"settlement_food")
	var stock = context.get_optional(&"inventory_stock")
	var seed_before := int(seed_container.inventory.count_item(SEEDS))
	var pallet_before := int(pallet.inventory.count_item(EGGPLANT))
	var physical_before := int(pallet.inventory.count_item(EGGPLANT)) + int(reserve.inventory.count_item(EGGPLANT))
	var stock_before: Dictionary = stock.get_settlement_stock_snapshot(SETTLEMENT_ID).get("items", {}).duplicate(true)
	_expect(int(stock_before.get(SEEDS.item_id, 0)) == seed_before, "funded seeds are present in the stock index")
	_expect(int(stock_before.get(EGGPLANT.item_id, 0)) == physical_before, "initial produce index equals physical inventory")
	_expect(stock.transact_item_count(SETTLEMENT_ID, EGGPLANT, 1), "produce routing transaction failed")
	var physical_after := int(pallet.inventory.count_item(EGGPLANT)) + int(reserve.inventory.count_item(EGGPLANT))
	_expect(physical_after == physical_before + 1 and int(seed_container.inventory.count_item(EGGPLANT)) == 0, "one produce transaction adds exactly one physical item and no seed-container item")
	_expect(int(pallet.inventory.count_item(EGGPLANT)) == pallet_before + 1 and int(reserve.inventory.count_item(EGGPLANT)) == 0, "produce is routed to the admitting physical pallet, not the generic-food-only reserve")
	var after: Dictionary = stock.get_settlement_stock_snapshot(SETTLEMENT_ID).get("items", {})
	_expect(int(after.get(EGGPLANT.item_id, 0)) == int(stock_before.get(EGGPLANT.item_id, 0)) + 1, "stock index agrees with exact physical produce delta")
	_expect(seed_container.inventory.count_item(SEEDS) == seed_before and int(after.get(SEEDS.item_id, 0)) == seed_before, "produce deposit cannot debit or replace funded seeds")
	var definition = settlements.get_settlement_definition(SETTLEMENT_ID)
	_expect(definition.get_behavior_profile().food_outputs_per_day[0].item == GENERIC_FOOD and reserve.can_accept_item_count(GENERIC_FOOD, 7), "abstract-food suppression has a configured output and an admitting real destination")
	var outputs: Array = food.call("_production_outputs", definition, settlements.get_settlement_state(SETTLEMENT_ID))
	_expect(outputs.is_empty(), "physical farming suppresses abstract profile production")
	# Exercise the normal clock/upkeep route, not only the output selector.
	clock.advance_hours(24.0)
	_expect(int(food.get_status(SETTLEMENT_ID).get("last_processed_day", -1)) >= 0, "real daily upkeep ran")
	_expect(food.get_status(SETTLEMENT_ID).get("last_produced_item_counts", {}).is_empty(), "upkeep minted no abstract food")
	_expect(int(stock.get_settlement_stock_snapshot(SETTLEMENT_ID).get("items", {}).get(GENERIC_FOOD.item_id, 0)) == 0 and reserve.inventory.count_item(GENERIC_FOOD) == 0, "no abstract food exists physically or in the index")
	print("FARM_STORAGE_FIXTURE ", JSON.stringify({"physical_before": physical_before, "physical_after": physical_after, "seeds": seed_before, "upkeep": food.get_status(SETTLEMENT_ID)}))
	_finish()

func _fixture_ready() -> bool:
	var context := BootstrapContext.active
	if context == null: return false
	for id in [&"farming", &"world_time", &"settlement", &"inventory_stock", &"settlement_food"]:
		if context.get_optional(id) == null: return false
	var field = game.get_node("Town/Facilities/Farm")
	if field.get_plot_id().is_empty(): return false
	var stock: Dictionary = context.get_optional(&"inventory_stock").get_settlement_stock_snapshot(SETTLEMENT_ID).get("items", {})
	return int(stock.get(SEEDS.item_id, 0)) == 64 and int(stock.get(EGGPLANT.item_id, 0)) == 12

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if game != null and is_instance_valid(game):
		root.remove_child(game)
		game.free()
	if failures.is_empty():
		print("CANYON_FARM_STORAGE_CONTRACT_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CANYON_FARM_STORAGE_CONTRACT_FAILED count=%d" % failures.size())
	quit(1)
