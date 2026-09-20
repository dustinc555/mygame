extends "res://tests/validation/test_case.gd"

const LEDGER := preload("res://features/inventory/resources/items/town_ledger.tres")
const BREAD := preload("res://features/inventory/resources/items/bread.tres")
const BOTTLE := preload("res://features/inventory/resources/items/bottle_1.tres")
var SAVE_PATH := "user://town_ledger_lifecycle_validation_%d.tres" % OS.get_process_id()

var _failed := false


class FakeWorldItem:
	extends Node3D

	var stack_id := "town.alpha.ruler_desk.slot.ledger"
	var item_definition: ItemDefinition = LEDGER
	var quantity := 1
	var contained_item_counts: Dictionary = {}
	var item_metadata: Dictionary = {"tabletop_origin_host_id": "town.alpha.ruler_desk", "tabletop_origin_slot_id": "ledger"}
	var location_kind := "tabletop_slot"
	var placement_host_id := "town.alpha.ruler_desk"
	var placement_slot_id := "ledger"
	var location_settlement_id := "town.alpha"


class FakeActor:
	extends Node

	var stable_id := "actor.player"
	var inventory := InventoryData.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_save()
	var source := _make_gecs_root()
	var bridge: Node = source["bridge"]
	var lifecycle: Node = source["lifecycle"]
	_validate_reentrant_metadata(lifecycle)
	var build_command := ItemBuildCommand.new()
	build_command.command_id = "build.town_ledger.validation"
	build_command.actor_id = "actor.player"
	build_command.item_definition_path = LEDGER.resource_path
	var build_result: Dictionary = lifecycle.call("validate_build_command", build_command)
	_assert(bool(build_result.get("valid", false)), "Generic item build contract must accept the town ledger")
	var item := FakeWorldItem.new()
	(source["root"] as Node).add_child(item)
	var item_transform := Transform3D(Basis(), Vector3(4, 1, 9))
	await _submit_and_wait(lifecycle, "submit_world_stack", [_world_record(item, item_transform)])
	# Binding and snapshots must be produced by the live read model, not this test.
	var ledger_controller: Node = source["ledger"]
	await process_frame
	lifecycle.call("_drain_commands")
	var metadata: Dictionary = lifecycle.call("get_stack_record", item.stack_id).get("metadata", {})
	_assert(str(metadata.get("town_ledger", {}).get("original_settlement_id", "")) == "town.alpha", "Production controller binds ledger to its original town")
	_assert(ledger_controller.call("get_report", item.stack_id).get("record_state", "") == "current", "Placed origin-town ledger is current")
	await _validate_live_refresh(source, item.stack_id)
	metadata = lifecycle.call("get_stack_record", item.stack_id).get("metadata", {})
	# Exercise the real destructive inventory mirror path: the ledger metadata
	# must survive stack entity replacement, not only direct lifecycle calls.
	await _submit_and_wait(lifecycle, "submit_inventory", [item.stack_id, "actor.player", "actor.player.inventory"])
	var actor := FakeActor.new()
	(source["root"] as Node).add_child(actor)
	actor.inventory.configure_stack_allocator("actor.player.inventory", 1)
	actor.inventory.entries.append(actor.inventory.create_entry(LEDGER, Vector2i.ZERO, 1, {}, metadata, item.stack_id))
	bridge.call("sync_actor_inventory", actor)
	lifecycle.call("_rebuild_indexes")
	var mirrored_record: Dictionary = lifecycle.call("get_stack_record", item.stack_id)
	var mirrored_ledger := ((mirrored_record.get("metadata", {}) as Dictionary).get("town_ledger", {}) as Dictionary)
	_assert(str(mirrored_ledger.get("original_settlement_id", "")) == "town.alpha", "Actor inventory resync must preserve ledger binding")
	_assert(str((mirrored_ledger.get("snapshot", {}) as Dictionary).get("settlement_name", "")) == "Alpha", "Actor inventory resync must preserve ledger snapshot")
	await _submit_and_wait(lifecycle, "submit_placed", [item.stack_id, item_transform, item.placement_host_id, item.placement_slot_id, item.location_settlement_id, true])
	var loose_item := FakeWorldItem.new()
	loose_item.stack_id = "world.loose.validation"
	loose_item.location_kind = "world_loose"
	loose_item.placement_host_id = ""
	loose_item.placement_slot_id = ""
	loose_item.location_settlement_id = "town.alpha"
	(source["root"] as Node).add_child(loose_item)
	await _submit_and_wait(lifecycle, "submit_world_stack", [_world_record(loose_item, Transform3D(Basis(), Vector3(8, 2, 3)))])
	var coalesced_metadata := {"coalesced_validation": true}
	var pending_metadata_result: Dictionary = lifecycle.call("submit_metadata", loose_item.stack_id, coalesced_metadata)
	_assert(bool(pending_metadata_result.get("accepted", false)), "Pending metadata command must queue")
	var pending_save_result: Dictionary = lifecycle.call("submit_world_loose", loose_item.stack_id, Transform3D(Basis(), Vector3(9, 2, 3)), "town.alpha")
	_assert(bool(pending_save_result.get("accepted", false)), "Pending lifecycle command must queue before save")
	_assert(bool(bridge.call("save_gecs_world", SAVE_PATH, false)), "Ledger GECS state must save")

	var ledger_stack_id := item.stack_id
	var loose_stack_id := loose_item.stack_id
	(source["root"] as Node).free()
	await process_frame
	var loaded := _make_gecs_root(true)
	var loaded_bridge: Node = loaded["bridge"]
	var loaded_lifecycle: Node = loaded["lifecycle"]
	_assert(bool(loaded_bridge.call("load_gecs_world", SAVE_PATH)), "Ledger GECS state must load")
	await create_timer(0.06).timeout
	var restored_loose := _world_item("world.loose.validation")
	_assert(restored_loose != null, "Loose world item projection must restore after GECS load")
	if restored_loose is Node3D:
		_assert((restored_loose as Node3D).global_position.distance_to(Vector3(9, 2, 3)) < 0.25, "Pending lifecycle command must resolve after GECS load")
		_assert(loaded_lifecycle.call("get_stack_record", loose_stack_id).get("metadata", {}) == coalesced_metadata, "Location coalescing must preserve pending metadata")
		await _submit_and_wait(loaded_lifecycle, "submit_inventory", ["world.loose.validation", "actor.player", "actor.player.inventory"])
		await process_frame
		_assert(not is_instance_valid(restored_loose), "World projection must disappear after its stack moves into inventory")
	await _submit_and_wait(loaded_lifecycle, "submit_world_loose", ["world.loose.validation", Transform3D(Basis(), Vector3(8, 2, 3)), "town.alpha"])
	await process_frame
	var equipment_projection := _world_item("world.loose.validation")
	if equipment_projection != null:
		await _submit_and_wait(loaded_lifecycle, "submit_placed", ["world.loose.validation", Transform3D(Basis(), Vector3(8, 2, 3)), "validation.table", "slot.1", "town.alpha", true])
		await process_frame
		_assert(is_instance_valid(equipment_projection) and not equipment_projection.is_queued_for_deletion(), "Tabletop lifecycle must leave its externally managed projection intact")
		loaded_bridge.call("_ensure_equipment_item_stack", "actor.player", "weapon", LEDGER.resource_path, "world.loose.validation")
		(loaded["projection"] as Node).call("_on_item_location_changed", "world.loose.validation", loaded_bridge.call("get_item_stack", "world.loose.validation"))
		_assert(equipment_projection.is_queued_for_deletion(), "World projection must be queued for removal after its stack moves into equipment")
		await process_frame
	else:
		_assert(false, "World projection must restore before equipment cleanup validation")
	var loaded_record: Dictionary = loaded_lifecycle.call("get_stack_record", ledger_stack_id)
	var loaded_ledger := (((loaded_record.get("metadata", {}) as Dictionary).get("town_ledger", {}) as Dictionary).duplicate(true))
	_assert(not loaded_ledger.is_empty(), "Ledger stack metadata must survive save/load")
	if not loaded_ledger.is_empty():
		_assert(str(loaded_ledger.get("original_settlement_id", "")) == "town.alpha", "Original town binding must survive save/load")
		_assert(str((loaded_ledger.get("snapshot", {}) as Dictionary).get("settlement_name", "")) == "Alpha", "Ledger snapshot must survive save/load")
		_assert(loaded["ledger"].get_report(ledger_stack_id).get("record_state") == "current", "Loaded ledger must retain placed status")
		await _submit_and_wait(loaded_lifecycle, "submit_inventory", [ledger_stack_id, "actor.player", "actor.player.inventory"])
		_assert(loaded["ledger"].get_report(ledger_stack_id).get("record_state") == "outdated", "Inventory/theft must freeze the report")
		var place_result: Dictionary = loaded_lifecycle.call("validate_place_command", ledger_stack_id, Transform3D.IDENTITY, "town.alpha.ruler_desk", "ledger")
		_assert(bool(place_result.get("valid", false)), "Generic item place contract must accept an inventory-held ledger")
		await _submit_and_wait(loaded_lifecycle, "submit_placed", [ledger_stack_id, Transform3D.IDENTITY, "town.beta.ruler_desk", "ledger", "town.beta", true])
		_assert(loaded["ledger"].get_report(ledger_stack_id).get("record_state") == "outdated", "Moved ledger must stay stale")
		await _submit_and_wait(loaded_lifecycle, "submit_placed", [ledger_stack_id, Transform3D.IDENTITY, "town.alpha.ruler_desk", "ledger", "town.alpha", true])
		_assert(loaded["ledger"].get_report(ledger_stack_id).get("record_state") == "current", "Returning ledger must become live immediately")

	(loaded["root"] as Node).free()
	await process_frame
	_remove_save()
	if _failed:
		quit(1)
		return
	print("TOWN_LEDGER_LIFECYCLE_OK")
	quit()


func _make_gecs_root(with_projection := false) -> Dictionary:
	var test_root := Node.new()
	root.add_child(test_root)
	var context := BootstrapContext.new(test_root)
	var bridge: Node = load("res://features/core/gecs_world_controller.gd").new()
	test_root.add_child(bridge)
	context.register(&"gecs_world", bridge)
	bridge.call("initialize", context)
	_assert(load("res://features/settlements/settlements_module.gd") != null, "Settlements module must compile after GECS initialization")
	_assert(load("res://features/settlements/bridge/town_ledger_controller.gd") != null, "TownLedgerController must compile after GECS initialization")
	_assert(load("res://features/settlements/bridge/item_read_controller.gd") != null, "ItemReadController must compile after GECS initialization")
	_assert(load("res://features/inventory/bridge/world_item_projection_bridge.gd") != null, "WorldItemProjectionBridge must compile after GECS initialization")
	var lifecycle: Node = load("res://features/inventory/sim/item_lifecycle_controller.gd").new()
	test_root.add_child(lifecycle)
	context.register(&"item_lifecycle", lifecycle)
	lifecycle.call("initialize", context)
	var services: Array[Node] = [
		WorldTimeController.new(), PopulationController.new(), BuildingRegistry.new(),
		SettlementController.new(), InventoryStockController.new(), SettlementFoodController.new(),
		TerritoryController.new(), LiquidStorageController.new(), FarmController.new(), TownLedgerReadModel.new(),
	]
	for service in services:
		test_root.add_child(service)
		context.register(service.SERVICE_ID, service)
	for service in services:
		service.initialize(context)
		service.set_process(false)
	var definition := SettlementDefinition.new()
	definition.settlement_id = "town.alpha"
	definition.display_name = "Alpha"
	context.require(&"settlement").call("_register_settlement_definition", definition, null)
	for entry in [["food", BREAD, 2], ["general", BOTTLE, 1]]:
		var seed := SettlementStorageSeed.new()
		seed.container_id = "town.alpha.stock." + str(entry[0])
		seed.facility_id = "town.alpha.store"
		seed.container_kind = "storage"
		seed.container_type = str(entry[0])
		var stack = load("res://features/world_sim/resources/settlement_storage_stack_seed.gd").new()
		stack.item = entry[1]
		stack.count = entry[2]
		seed.stacks.append(stack)
		_assert(context.require(&"inventory_stock").ensure_seeded_container("town.alpha", seed), "typed ledger stock fixture must seed")
	var projection: Node = null
	if with_projection:
		projection = load("res://features/inventory/bridge/world_item_projection_bridge.gd").new()
		test_root.add_child(projection)
		context.register(&"world_item_projection", projection)
		projection.call("initialize", context)
	var tabletop_source := FileAccess.get_file_as_string("res://features/world/projection/props/tabletop_item_spawner.gd")
	_assert(tabletop_source.contains("get_stack_records_for_host") and tabletop_source.contains("tabletop_origin_host_id"), "Tabletop restoration must reserve a stolen required slot instead of respawning it")
	_assert(tabletop_source.find("item.transform = global_transform.affine_inverse() * saved_world_transform") < tabletop_source.find("add_child(item)", tabletop_source.find("func _realize_record")), "Tabletop restoration must apply saved transform before WorldItem._ready syncs GECS")
	_assert(tabletop_source.contains("world_reindexed.connect(_on_world_reindexed)") and tabletop_source.contains("_reconcile_item_projections"), "Tabletop projections must reconcile after loading GECS state")
	var world_item_source := FileAccess.get_file_as_string("res://features/world/projection/items/world_item.gd")
	var pickup_source := world_item_source.get_slice("func try_pickup", 1).get_slice("func _find_ownership_controller", 0)
	_assert(not pickup_source.contains("_remove_world_item_from_gecs"), "Pickup must move the stable stack into inventory instead of deleting it")
	var stock_failure_source := pickup_source.get_slice("if stock == null or not stock.transact_item_count", 1).get_slice("var inventory_stack_id", 0)
	_assert(not stock_failure_source.contains("queue_free"), "Failed stock pickup must leave its visible projection intact")
	_assert(pickup_source.contains("stock.transact_item_count(stock_source_settlement_id, item_definition, quantity)"), "Failed inventory insertion must roll back its stock debit")
	return {"root": test_root, "bridge": bridge, "lifecycle": lifecycle, "projection": projection, "ledger": context.require(&"town_ledger"), "context": context}


func _world_item(stack_id: String) -> Node:
	for node in get_nodes_in_group("world_item"):
		if str(node.get("stack_id")) == stack_id:
			return node
	return null


func _world_record(item: FakeWorldItem, world_transform: Transform3D) -> Dictionary:
	return {
		"stack_id": item.stack_id,
		"container_id": "world",
		"owner_actor_id": "",
		"item_definition_path": item.item_definition.resource_path,
		"count": item.quantity,
		"grid_position": Vector2i.ZERO,
		"contained_item_counts": item.contained_item_counts.duplicate(true),
		"metadata": item.item_metadata.duplicate(true),
		"location_kind": item.location_kind,
		"world_transform": world_transform,
		"placement_host_id": item.placement_host_id,
		"placement_slot_id": item.placement_slot_id,
		"location_settlement_id": item.location_settlement_id,
	}


func _submit_and_wait(lifecycle: Node, method: String, arguments: Array) -> bool:
	var result: Dictionary = lifecycle.callv(method, arguments)
	var accepted := bool(result.get("accepted", false))
	_assert(accepted, "%s rejected: %s" % [method, str(result.get("result_code", "unknown"))])
	if accepted:
		# Resolve the location command, then any metadata its completion queues.
		lifecycle.call("_drain_commands")
		await process_frame
		lifecycle.call("_drain_commands")
		await process_frame
	return accepted


func _validate_reentrant_metadata(lifecycle: Node) -> void:
	var stack_id := "validation.reentrant.metadata"
	var marker := {"nested": {"owner": "original", "revision": 7}, "exact_id": stack_id}
	var on_location := func(id: String, _record: Dictionary):
		if id == stack_id:
			var result: Dictionary = lifecycle.submit_metadata(id, marker)
			_assert(bool(result.get("accepted", false)), "completion subscriber accepts metadata for the same exact stack")
	lifecycle.item_location_changed.connect(on_location)
	var result: Dictionary = lifecycle.submit_world_stack({"stack_id": stack_id, "item_definition_path": BOTTLE.resource_path, "count": 1, "location_kind": "world_loose", "world_transform": Transform3D.IDENTITY, "metadata": {}})
	_assert(bool(result.get("accepted", false)), "reentrant metadata fixture submits a real world stack")
	lifecycle._drain_commands()
	lifecycle._drain_commands()
	_assert(lifecycle.get_stack_record(stack_id).get("metadata", {}) == marker, "metadata queued by completion survives the in-flight command retirement")
	lifecycle.item_location_changed.disconnect(on_location)


func _validate_live_refresh(fixture: Dictionary, stack_id: String) -> void:
	var context: BootstrapContext = fixture["context"]
	var lifecycle: Node = fixture["lifecycle"]
	var ledger: Node = fixture["ledger"]
	var buildings: Node = context.require(&"building_registry")
	var liquid: Node = context.require(&"liquid_storage")
	var refreshed := [0]
	var on_refresh := func(id: String, _snapshot: Dictionary):
		if id == stack_id: refreshed[0] += 1
	ledger.report_updated.connect(on_refresh)
	# Seed the building before the measured burst. Creation and update each
	# enqueue a separate deferred settlement-housing notification; measure one
	# real building update together with the independent water/stock changes.
	buildings.create_building({"building_id": "town.alpha.home", "settlement_id": "town.alpha", "display_name": "Alpha Home", "housing_capacity": 5, "bed_count": 2})
	await process_frame
	lifecycle.call("_drain_commands")
	refreshed[0] = 0
	buildings.update_building("town.alpha.home", {"housing_capacity": 7})
	liquid.ensure_container({"liquid_container_id": "town.alpha.water", "settlement_id": "town.alpha", "owner_faction_name": "Settlers", "assigned_liquid_id": "water", "capacity_liters": 50.0, "current_liters": 23.0})
	_assert(is_equal_approx(float(liquid.get_settlement_liquid_totals("town.alpha", "water").get("stored_liters", 0.0)), 23.0), "water mutation must reach actual stock authority before report refresh")
	_assert(context.require(&"inventory_stock").transact_item_count("town.alpha", BREAD, 1), "real food stock transaction must succeed")
	await process_frame
	await process_frame
	lifecycle.call("_drain_commands")
	_assert(refreshed[0] == 1, "building and water signal burst must execute exactly one production refresh; observed=%d" % refreshed[0])
	var live: Dictionary = ledger.get_report(stack_id)
	_assert(int(live.get("overview", {}).get("housing_capacity", 0)) == 7, "real building mutation reaches persisted ledger report")
	_assert(is_equal_approx(float(live.get("water", {}).get("stored_water", 0.0)), 23.0), "real liquid stock reaches persisted water report")
	var food_rows: Array = live.get("food", [])
	var store_rows: Array = live.get("stores", [])
	_assert(food_rows.any(func(row: Dictionary) -> bool: return row.get("food") == "Bread" and row.get("stored") == 3), "food report is classified and counted from real typed stock")
	_assert(store_rows.any(func(row: Dictionary) -> bool: return row.get("item") == "Green Bottle" and row.get("quantity") == 1), "non-food stock appears in Stores")
	_assert(not store_rows.any(func(row: Dictionary) -> bool: return row.get("item") == "Bread") and not food_rows.any(func(row: Dictionary) -> bool: return row.get("food") == "Green Bottle"), "production classification never duplicates food and non-food between sections")
	var saved: Dictionary = lifecycle.get_stack_record(stack_id).get("metadata", {}).get("town_ledger", {}).get("snapshot", {})
	_assert(saved == live, "deferred refresh persists the actual report to stack metadata")
	var window := preload("res://features/settlements/projection/town_ledger_window.tscn").instantiate()
	root.add_child(window)
	window.setup(stack_id, live)
	_assert(window.get("_report") == live, "production report reaches ledger window without synthetic reclassification")
	window.free()
	await _submit_and_wait(lifecycle, "submit_inventory", [stack_id, "actor.player", "actor.player.inventory"])
	var frozen: Dictionary = ledger.get_report(stack_id)
	buildings.update_building("town.alpha.home", {"housing_capacity": 9})
	await process_frame
	lifecycle.call("_drain_commands")
	_assert(ledger.get_report(stack_id) == frozen and frozen.get("record_state") == "outdated", "carried ledger freezes while original town changes")
	await _submit_and_wait(lifecycle, "submit_placed", [stack_id, Transform3D.IDENTITY, "town.beta.desk", "ledger", "town.beta", true])
	buildings.update_building("town.alpha.home", {"housing_capacity": 11})
	await process_frame
	lifecycle.call("_drain_commands")
	_assert(ledger.get_report(stack_id) == frozen, "foreign-town placement never refreshes the original report")
	await _submit_and_wait(lifecycle, "submit_placed", [stack_id, Transform3D.IDENTITY, "town.alpha.ruler_desk", "ledger", "town.alpha", true])
	lifecycle.call("_drain_commands")
	var returned: Dictionary = ledger.get_report(stack_id)
	_assert(returned.get("record_state") == "current" and int(returned.get("overview", {}).get("housing_capacity", 0)) == 11, "return to origin refreshes changed town facts immediately")
	ledger.report_updated.disconnect(on_refresh)


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
