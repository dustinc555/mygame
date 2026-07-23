extends SceneTree

const LEDGER := preload("res://features/inventory/resources/items/town_ledger.tres")
const SAVE_PATH := "user://town_ledger_lifecycle_validation.tres"

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
	var metadata := item.item_metadata.duplicate(true)
	var ledger := {"original_settlement_id": "town.alpha", "snapshot": _snapshot()}
	metadata["town_ledger"] = ledger
	await _submit_and_wait(lifecycle, "submit_metadata", [item.stack_id, metadata])
	_assert(lifecycle.call("get_stack_record", item.stack_id).get("metadata", {}) == metadata, "Ledger metadata must attach to its durable item stack")
	_assert(_status(lifecycle.call("get_stack_record", item.stack_id), ledger) == "live", "Placed original-town ledger must be live")
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

	var loaded := _make_gecs_root(true)
	var loaded_bridge: Node = loaded["bridge"]
	var loaded_lifecycle: Node = loaded["lifecycle"]
	_assert(bool(loaded_bridge.call("load_gecs_world", SAVE_PATH)), "Ledger GECS state must load")
	await create_timer(0.06).timeout
	var restored_loose := _world_item("world.loose.validation")
	_assert(restored_loose != null, "Loose world item projection must restore after GECS load")
	if restored_loose is Node3D:
		_assert((restored_loose as Node3D).global_position.distance_to(Vector3(9, 2, 3)) < 0.25, "Pending lifecycle command must resolve after GECS load")
		_assert(loaded_lifecycle.call("get_stack_record", loose_item.stack_id).get("metadata", {}) == coalesced_metadata, "Location coalescing must preserve pending metadata")
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
	var loaded_record: Dictionary = loaded_lifecycle.call("get_stack_record", item.stack_id)
	var loaded_ledger := (((loaded_record.get("metadata", {}) as Dictionary).get("town_ledger", {}) as Dictionary).duplicate(true))
	_assert(not loaded_ledger.is_empty(), "Ledger stack metadata must survive save/load")
	if not loaded_ledger.is_empty():
		_assert(str(loaded_ledger.get("original_settlement_id", "")) == "town.alpha", "Original town binding must survive save/load")
		_assert(str((loaded_ledger.get("snapshot", {}) as Dictionary).get("settlement_name", "")) == "Alpha", "Ledger snapshot must survive save/load")
		_assert(_status(loaded_record, loaded_ledger) == "live", "Loaded ledger must retain placed status")
		await _submit_and_wait(loaded_lifecycle, "submit_inventory", [item.stack_id, "actor.player", "actor.player.inventory"])
		_assert(_status(loaded_lifecycle.call("get_stack_record", item.stack_id), loaded_ledger) == "stale", "Inventory/theft must freeze the report")
		var place_result: Dictionary = loaded_lifecycle.call("validate_place_command", item.stack_id, Transform3D.IDENTITY, "town.alpha.ruler_desk", "ledger")
		_assert(bool(place_result.get("valid", false)), "Generic item place contract must accept an inventory-held ledger")
		await _submit_and_wait(loaded_lifecycle, "submit_placed", [item.stack_id, Transform3D.IDENTITY, "town.beta.ruler_desk", "ledger", "town.beta", true])
		_assert(_status(loaded_lifecycle.call("get_stack_record", item.stack_id), loaded_ledger) == "stale", "Moved ledger must stay stale")
		await _submit_and_wait(loaded_lifecycle, "submit_placed", [item.stack_id, Transform3D.IDENTITY, "town.alpha.ruler_desk", "ledger", "town.alpha", true])
		_assert(_status(loaded_lifecycle.call("get_stack_record", item.stack_id), loaded_ledger) == "live", "Returning ledger must become live immediately")

	(source["root"] as Node).queue_free()
	(loaded["root"] as Node).queue_free()
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
	return {"root": test_root, "bridge": bridge, "lifecycle": lifecycle, "projection": projection}


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
		await create_timer(0.06).timeout
	return accepted


func _snapshot() -> Dictionary:
	return {
		"settlement_name": "Alpha",
		"record_state": "current",
		"overview": {},
		"people": [],
		"buildings": [],
		"food": [],
		"stores": [],
	}


func _status(record: Dictionary, ledger: Dictionary) -> String:
	var original := str(ledger.get("original_settlement_id", ""))
	var kind := str(record.get("location_kind", ""))
	return "live" if str(record.get("location_settlement_id", "")) == original and kind in ["world_placed", "tabletop_slot"] else "stale"


func _remove_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
