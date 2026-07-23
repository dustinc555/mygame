extends SceneTree

const SAVE_PATH := "user://settlement_physical_food_validation.tres"
const FOOD := preload("res://features/inventory/resources/items/food.tres")
const BREAD := preload("res://features/inventory/resources/items/bread.tres")

var _failed := false
var _stock_events := 0


class TestPopulation extends Node:
	var counts := {"surf_city": 4}

	func count_alive_records_for_settlement(settlement_id: String) -> int:
		return int(counts.get(settlement_id, 0))


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node.new()
	root.add_child(host)
	var context := BootstrapContext.new(host)
	var gecs: Node = load("res://features/core/gecs_world_controller.gd").new()
	var time: Node = load("res://features/core/world_time_controller.gd").new()
	var population := TestPopulation.new()
	var buildings: Node = load("res://features/world/sim/building_registry.gd").new()
	var settlements: Node = load("res://features/settlements/bridge/settlement_controller.gd").new()
	var stock: Node = load("res://features/inventory/sim/inventory_stock_controller.gd").new()
	var food: Node = load("res://features/settlements/sim/settlement_food_controller.gd").new()
	for service in [gecs, time, population, buildings, settlements, stock, food]:
		host.add_child(service)
	context.register(&"gecs_world", gecs)
	context.register(&"world_time", time)
	context.register(&"population", population)
	context.register(&"building_registry", buildings)
	context.register(&"settlement", settlements)
	context.register(&"inventory_stock", stock)
	context.register(&"settlement_food", food)
	gecs.initialize(context)
	time.initialize(context)
	buildings.initialize(context)
	settlements.initialize(context)
	stock.initialize(context)
	food.initialize(context)
	stock.stock_changed.connect(func(_settlement_id: String, _facility_id: String): _stock_events += 1)

	var definition := load("res://features/world_sim/resources/settlements/surf_city.tres") as SettlementDefinition
	_expect(definition != null and not Array(definition.get("storage_seeds")).is_empty(), "authored settlement lacks concrete storage seed")
	settlements.call("_register_settlement_definition", definition, null)
	food.call("_bootstrap_registered_settlements")
	await process_frame
	var initial: Dictionary = stock.get_settlement_stock_snapshot("surf_city")
	_expect(int((initial.get("items", {}) as Dictionary).get("food.generic", 0)) == 48, "concrete seed count is wrong")
	_expect(_container_exists(gecs, "surf_city.granary"), "stable granary container was not seeded")
	var detached: Dictionary = stock.get_settlement_stock_snapshot("surf_city")
	detached["items"] = {}
	_expect(int((stock.get_settlement_stock_snapshot("surf_city").get("items", {}) as Dictionary).get("food.generic", 0)) == 48, "cached O(1) snapshot leaked mutable state")
	_assert_cached_snapshot_source()

	var before_units: float = stock.get_total_food_units("surf_city")
	food.call("_on_hour_changed", 6, 0, 6)
	var status: Dictionary = food.get_status("surf_city")
	_expect(float(status.get("last_produced", 0.0)) == 12.0, "daily concrete production is wrong")
	_expect(float(status.get("last_consumed", 0.0)) == 4.0, "daily physical consumption is wrong")
	_expect(int((status.get("last_produced_item_counts", {}) as Dictionary).get("food.generic", 0)) == 6, "daily production history must retain actual item count")
	_expect(int((status.get("last_consumed_item_counts", {}) as Dictionary).get("food.generic", 0)) == 2, "daily consumption history must retain actual item count")
	_expect(float(stock.get_total_food_units("surf_city")) == before_units + 8.0, "daily physical stock delta is wrong")
	_expect(int(status.get("last_processed_day", -1)) == 0, "daily status did not persist processed day")
	_expect(str(status.get("reserve_state", "")) == "sustainable", "sustainable reserve is not explicit")

	_seed_test_container(stock, "depletion", "depletion.a", "depletion.a.stack.1", FOOD, 2)
	_seed_test_container(stock, "depletion", "depletion.b", "depletion.b.stack.1", BREAD, 2)
	var removed: Dictionary = stock.consume_food_units("depletion", 2.0)
	_expect(float(removed.get("food_units", 0.0)) == 2.0, "food-unit removal returned wrong amount")
	_expect(_stack_count(gecs, "depletion.a.stack.1") == 1, "depletion did not choose lowest container/stack id")
	_expect(_stack_exists(gecs, "depletion.b.stack.1"), "depletion touched later eligible container")

	population.counts["surf_city"] = 200
	food.refresh_status("surf_city")
	var low_status: Dictionary = food.get_status("surf_city")
	_expect(str(low_status.get("pressure_state", "")) == "hungry", "low reserve did not create hungry pressure")
	var events_before := _stock_events
	stock.transact_item_count("surf_city", FOOD, 1)
	_expect(_stock_events == events_before + 1, "stock transaction did not emit exactly one event")
	stock.transact_item_count("surf_city", FOOD, -1)
	_expect(_stock_events == events_before + 2, "stock removal did not emit exactly one event")

	var saved_stock: Dictionary = stock.get_settlement_stock_snapshot("surf_city")
	var saved_status: Dictionary = food.get_status("surf_city")
	_expect(gecs.save_gecs_world(SAVE_PATH), "physical food save failed")
	stock.consume_food_units("surf_city", 10.0)
	_expect(gecs.load_gecs_world(SAVE_PATH), "physical food load failed")
	_expect(stock.get_settlement_stock_snapshot("surf_city") == saved_stock, "save/load changed physical stock")
	_expect(food.get_status("surf_city") == saved_status, "save/load changed food status")
	_assert_old_food_truth_absent()

	host.free()
	var absolute_path := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	quit(1 if _failed else 0)


func _seed_test_container(stock: Node, settlement_id: String, container_id: String, stack_id: String, item: ItemDefinition, count: int) -> void:
	var seed_script = load("res://features/world_sim/resources/settlement_storage_seed.gd")
	var stack_script = load("res://features/world_sim/resources/settlement_storage_stack_seed.gd")
	var stack = stack_script.new()
	stack.stack_id = stack_id
	stack.item = item
	stack.count = count
	var seed = seed_script.new()
	seed.container_id = container_id
	seed.facility_id = container_id
	seed.columns = 10
	seed.rows = 10
	var stacks: Array[Resource] = [stack]
	seed.stacks = stacks
	_expect(stock.ensure_seeded_container(settlement_id, seed), "test container seed failed: %s" % container_id)


func _container_exists(gecs: Node, container_id: String) -> bool:
	return (gecs.get("_inventory_container_entity_by_id") as Dictionary).has(container_id)


func _stack_exists(gecs: Node, stack_id: String) -> bool:
	return (gecs.get("_item_stack_entity_by_id") as Dictionary).has(stack_id)


func _stack_count(gecs: Node, stack_id: String) -> int:
	var entity = (gecs.get("_item_stack_entity_by_id") as Dictionary).get(stack_id)
	if entity == null:
		return 0
	var script = load("res://features/inventory/sim/c_game_item_stack.gd")
	var component = entity.get_component(script)
	return int(component.count) if component != null else 0


func _assert_cached_snapshot_source() -> void:
	var source := FileAccess.get_file_as_string("res://features/inventory/sim/inventory_stock_controller.gd")
	var start := source.find("func get_settlement_stock_snapshot")
	var finish := source.find("\n\nfunc ", start + 1)
	var body := source.substr(start, finish - start)
	_expect(body.contains("_settlement_stock.get"), "settlement snapshot does not use cached index")
	_expect(not body.contains("world.query"), "settlement snapshot queries GECS")


func _assert_old_food_truth_absent() -> void:
	var forbidden := [
		"func adjust_food(", "func set_food(", "func resolve_food_transfer(",
		"@export var starting_food", "@export var max_food", "@export var food_ratio",
		"@export var last_upkeep_day", "food_production_per_day =", "food_consumption_per_day =",
	]
	for path in _project_text_files("res://features") + _project_text_files("res://scenes"):
		var source := FileAccess.get_file_as_string(path)
		for token in forbidden:
			_expect(not source.contains(token), "old abstract food truth remains in %s: %s" % [path, token])


func _project_text_files(root_path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var path := root_path.path_join(entry)
		if directory.current_is_dir():
			result.append_array(_project_text_files(path))
		elif entry.get_extension() in ["gd", "tres", "tscn"] and path != "res://tools/validation/validate_settlement_physical_food.gd":
			result.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
