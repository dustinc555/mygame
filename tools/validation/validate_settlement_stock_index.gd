extends SceneTree

const FOOD := preload("res://features/inventory/resources/items/food.tres")
const GECS_SOURCE := "res://features/core/gecs_world_controller.gd"
const STOCK_SOURCE := "res://features/inventory/sim/inventory_stock_controller.gd"
const SAVE_PATH := "user://settlement_stock_index_validation.tres"

var _failed := false


class TestContainer extends Node:
	var container_id := ""
	var settlement_id := "town"
	var facility_id := "town.storehouse"
	var container_kind := "storage"
	var contributes_to_town_stock := true
	var next_stack_sequence := 1
	var inventory := InventoryData.new(4, 2, 0.0, false)
	var inventory_change_count := 0

	func _init(id: String, seed_count: int) -> void:
		container_id = id
		inventory.configure_stack_allocator(container_id, next_stack_sequence)
		inventory.changed.connect(func(): inventory_change_count += 1)
		if seed_count > 0:
			inventory.add_item_count(FOOD, seed_count)
		next_stack_sequence = inventory.next_stack_sequence

	func hydrate_inventory_from_gecs(snapshots: Array, sequence: int) -> void:
		inventory.entries.clear()
		inventory.configure_stack_allocator(container_id, sequence)
		for snapshot in snapshots:
			var definition := load(str(snapshot["item_definition_path"])) as ItemDefinition
			inventory.entries.append(inventory.create_entry(
				definition,
				snapshot.get("grid_position", Vector2i.ZERO),
				int(snapshot.get("count", 1)),
				(snapshot.get("contained_item_counts", {}) as Dictionary).duplicate(true),
				(snapshot.get("metadata", {}) as Dictionary).duplicate(true),
				str(snapshot.get("stack_id", ""))
			))
		next_stack_sequence = inventory.next_stack_sequence
		inventory.changed.emit()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert_changed_scripts_load()
	var validation_root := Node.new()
	root.add_child(validation_root)
	var context := BootstrapContext.new(validation_root)
	var gecs = load(GECS_SOURCE).new()
	validation_root.add_child(gecs)
	context.register(&"gecs_world", gecs)
	gecs.initialize(context)
	var stock = load(STOCK_SOURCE).new()
	validation_root.add_child(stock)
	context.register(&"inventory_stock", stock)
	stock.initialize(context)
	var stock_events := [0]
	stock.stock_changed.connect(func(_settlement_id: String, _facility_id: String): stock_events[0] += 1)

	var ignored := TestContainer.new("town.storage.ignored", 2)
	ignored.contributes_to_town_stock = false
	_sync_projection(gecs, stock, ignored)
	_expect(stock.get_settlement_stock_snapshot("town").is_empty(), "non-opted-in container contributed")

	var container_b := TestContainer.new("town.storage.b", 2)
	var container_a := TestContainer.new("town.storage.a", 2)
	_sync_projection(gecs, stock, container_b)
	_sync_projection(gecs, stock, container_a)
	_assert_stock(stock, 4, 8.0, "initial")
	var events_before_physical_change: int = stock_events[0]
	_expect(container_a.inventory.add_item_count(FOOD, 1), "physical container add setup failed")
	_sync_projection(gecs, stock, container_a)
	_expect(stock_events[0] == events_before_physical_change + 1, "physical container sync did not emit one stock change")
	_expect(container_a.inventory.remove_item_count(FOOD, 1), "physical container remove setup failed")
	_sync_projection(gecs, stock, container_a)
	_expect(stock_events[0] == events_before_physical_change + 2, "second physical container sync did not emit one stock change")
	var initial_ids := _stack_ids(gecs, container_a.container_id)
	_expect(initial_ids == ["town.storage.a.stack.1", "town.storage.a.stack.2"], "persistent stack allocator did not use container sequence")

	stock.detach_world_container(container_a.container_id, container_a)
	stock.detach_world_container(container_b.container_id, container_b)
	var stable_stack_entity = gecs.get_item_stack_entity("town.storage.a.stack.1")
	container_a.free()
	container_b.free()
	_assert_stock(stock, 4, 8.0, "after unload")

	_expect(stock.transact_item_count("town", FOOD, 3, "town.storehouse"), "offscreen add failed")
	_expect(gecs.get_item_stack_entity("town.storage.a.stack.1") == stable_stack_entity, "stock count update recreated an unchanged stack entity")
	_assert_stock(stock, 7, 14.0, "after offscreen add")
	_expect(stock.transact_item_count("town", FOOD, -3, "town.storehouse"), "offscreen remove failed")
	_assert_stock(stock, 4, 8.0, "after offscreen remove")
	var before_failed_transaction := _stack_ids(gecs, "town.storage.a")
	_expect(not stock.transact_item_count("town", FOOD, 20, "town.storehouse"), "over-capacity add was not rejected")
	_expect(not stock.transact_item_count("town", FOOD, -20, "town.storehouse"), "overdraw removal was not rejected")
	_expect(_stack_ids(gecs, "town.storage.a") == before_failed_transaction, "failed transaction partially mutated GECS")

	var rebound := TestContainer.new("town.storage.a", 4)
	var prebind_changes := rebound.inventory_change_count
	_expect(stock.bind_world_container(rebound), "existing GECS container did not bind")
	_expect(rebound.inventory.count_item(FOOD) == 1, "projection rebind did not hydrate durable stock")
	_expect(rebound.inventory_change_count == prebind_changes + 1, "projection hydration did not emit normal inventory change")
	_expect(_stack_ids_from_inventory(rebound.inventory) == _stack_ids(gecs, rebound.container_id), "projection hydration changed stack IDs")
	var loaded_change_count := rebound.inventory_change_count
	_expect(stock.transact_item_count("town", FOOD, 1, "town.storehouse"), "loaded-container add failed")
	_expect(rebound.inventory_change_count == loaded_change_count + 1, "loaded inventory did not receive transaction change")
	_expect(_stack_ids_from_inventory(rebound.inventory) == _stack_ids(gecs, rebound.container_id), "loaded inventory diverged from GECS after add")
	_expect(stock.transact_item_count("town", FOOD, -1, "town.storehouse"), "loaded-container remove failed")
	_assert_stock(stock, 4, 8.0, "after loaded transactions")

	var totals_before_rebuild: Dictionary = stock.get_settlement_stock_snapshot("town")
	var ids_before_rebuild: Array = _all_stack_ids(gecs)
	_expect(gecs.save_gecs_world(SAVE_PATH), "GECS stock save failed")
	_expect(stock.transact_item_count("town", FOOD, -1, "town.storehouse"), "pre-load mutation failed")
	_expect(gecs.load_gecs_world(SAVE_PATH), "GECS stock load failed")
	_expect(stock.get_settlement_stock_snapshot("town") == totals_before_rebuild, "GECS rebuild changed aggregate totals")
	_expect(_all_stack_ids(gecs) == ids_before_rebuild, "GECS rebuild changed stack IDs")
	_assert_indexed_selection_source()
	_assert_population_hot_updates_are_narrow()

	stock.detach_world_container(rebound.container_id, rebound)
	rebound.free()
	ignored.free()
	validation_root.free()
	var absolute_save_path := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(absolute_save_path):
		DirAccess.remove_absolute(absolute_save_path)
	quit(1 if _failed else 0)


func _sync_projection(gecs: Node, stock: Node, container: TestContainer) -> void:
	gecs.sync_world_container(container)
	stock.sync_world_container(container)


func _assert_stock(stock: Node, expected_count: int, expected_units: float, label: String) -> void:
	var settlement: Dictionary = stock.get_settlement_stock_snapshot("town")
	var facility: Dictionary = stock.get_facility_stock_snapshot("town.storehouse")
	for snapshot in [settlement, facility]:
		_expect(int((snapshot.get("items", {}) as Dictionary).get("food.generic", 0)) == expected_count, "%s item total is wrong" % label)
		_expect(int((snapshot.get("food_types", {}) as Dictionary).get("prepared_food", 0)) == expected_count, "%s food type total is wrong" % label)
		_expect(is_equal_approx(float((snapshot.get("food_units", {}) as Dictionary).get("prepared_food", 0.0)), expected_units), "%s food units are wrong" % label)


func _stack_ids(gecs: Node, container_id: String) -> Array:
	var result: Array = []
	for stack in gecs.get_inventory_stacks(container_id):
		result.append(str(stack["stack_id"]))
	result.sort()
	return result


func _all_stack_ids(gecs: Node) -> Array:
	return _stack_ids(gecs, "")


func _stack_ids_from_inventory(inventory: InventoryData) -> Array:
	var result: Array = []
	for entry in inventory.entries:
		result.append(entry.stack_id)
	result.sort()
	return result


func _assert_indexed_selection_source() -> void:
	var source := FileAccess.get_file_as_string(STOCK_SOURCE)
	var function_start := source.find("func _eligible_container_ids")
	var function_end := source.find("\n\nfunc ", function_start + 1)
	var function_source := source.substr(function_start, function_end - function_start)
	_expect(function_source.contains("_container_ids_by_settlement") and function_source.contains("_container_ids_by_facility"), "transaction selection does not use scope indexes")
	_expect(not function_source.contains("_containers_by_id.keys"), "transaction selection scans all containers")
	var container_source := FileAccess.get_file_as_string("res://features/world/projection/containers/world_container.gd")
	_expect(container_source.contains("_inventory_sync_suspended") and container_source.contains("hydrate_inventory_from_gecs"), "WorldContainer hydration lacks recursion suppression")


func _assert_population_hot_updates_are_narrow() -> void:
	var source := FileAccess.get_file_as_string("res://features/world_sim/sim/population/population_controller.gd")
	var skill_start := source.find("func _on_actor_skill_level_changed")
	var skill_end := source.find("\n\nfunc ", skill_start + 1)
	var skill_source := source.substr(skill_start, skill_end - skill_start)
	_expect(skill_source.contains("update_population_skill_progress"), "skill progress does not use the narrow GECS update")
	_expect(not skill_source.contains("_save_actor_record"), "skill progress still performs a full population upsert")
	_expect(not skill_source.contains("_get_actor_record_mutable"), "skill progress still reconstructs the full population record")
	var ledger_start := source.find("func advance_ledger_minutes")
	var ledger_end := source.find("\n\nfunc ", ledger_start + 1)
	var ledger_source := source.substr(ledger_start, ledger_end - ledger_start)
	_expect(ledger_source.contains("update_population_ledger_state"), "ledger simulation does not use the narrow GECS update")
	_expect(not ledger_source.contains("_save_actor_record"), "ledger simulation still performs full population upserts")
	var lod_source := FileAccess.get_file_as_string("res://features/world_sim/bridge/population_realization_controller.gd")
	var lod_start := lod_source.find("func _update_spawner_lod")
	var lod_end := lod_source.find("\n\nfunc ", lod_start + 1)
	var lod_function := lod_source.substr(lod_start, lod_end - lod_start)
	_expect(lod_function.contains("had_lod_state"), "first LOD evaluation does not enforce far-town staff cleanup")
	_expect(lod_source.contains("func _resync_settlement_staff"), "staff LOD still depends on population spawners")
	_expect(lod_source.contains("set_settlement_staff_lod_active"), "staff LOD does not drive settlement realization directly")


func _assert_changed_scripts_load() -> void:
	for path in [
		"res://features/inventory/sim/inventory_data.gd",
		"res://features/inventory/sim/c_game_inventory_container.gd",
		"res://features/inventory/sim/c_game_item_stack.gd",
		STOCK_SOURCE,
		GECS_SOURCE,
		"res://features/world/projection/containers/world_container.gd",
		"res://features/world/projection/items/world_item.gd",
		"res://features/inventory/bridge/party_inventory_controller.gd",
		"res://features/actors/bridge/capabilities/inventory_capability.gd",
		"res://features/world_sim/sim/population/population_controller.gd",
		"res://features/settlements/bridge/settlement_jail.gd",
	]:
		_expect(load(path) != null, "changed script failed to load: %s" % path)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
