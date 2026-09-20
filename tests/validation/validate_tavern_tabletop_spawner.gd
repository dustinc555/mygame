extends "res://tests/validation/test_case.gd"
## Authored furniture mounted before services, then real lifecycle/stock, pickup,
## projection destruction, moved remount and GECS disk reload. No source lints.
const TABLE := preload("res://features/world/projection/props/bar_table.tscn")
const SHELF := preload("res://features/world/projection/props/furniture/shelf_stocked.tscn")
const CONTAINER := preload("res://features/world/projection/containers/container.tscn")
const BREAD := preload("res://features/inventory/resources/items/bread.tres")
const WORLD_ITEM := preload("res://features/world/projection/items/world_item.tscn")
const PROJECTION_BRIDGE := preload("res://features/inventory/bridge/world_item_projection_bridge.gd")
const VASE := preload("res://features/inventory/resources/items/expensive_vase.tres")
const SWORD := preload("res://features/inventory/resources/items/iron_sword.tres")
var _failures: Array[String] = []
var _checks := 0
var _gecs: GecsWorldController
var _stock: InventoryStockController
var _lifecycle: ItemLifecycleController


class FacilityScope extends Node3D:
	# Only owning identity is controlled; spawning, stock and inventory are real.
	var facility_id := "validation.tavern"
	var settlement_id := "tabletop_town"


func _initialize() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var scope := FacilityScope.new()
	scene.add_child(scope)
	var furniture := [_make_furniture(TABLE, "table"), _make_furniture(SHELF, "shelf")]
	for node in furniture:
		scope.add_child(node)
	await process_frame
	_expect(_items(scope).is_empty(), "before bootstrap: authored furniture must not invent unbacked items")
	var context := BootstrapContext.new(scene)
	_gecs = GecsWorldController.new()
	_stock = InventoryStockController.new()
	_lifecycle = ItemLifecycleController.new()
	var projection := PROJECTION_BRIDGE.new()
	for service in [_gecs, _stock, _lifecycle, projection]:
		context.register(service.SERVICE_ID, service)
		scene.add_child(service)
	_gecs.initialize(context)
	_gecs.set_process(false)
	_stock.initialize(context)
	_lifecycle.initialize(context)
	projection.initialize(context)
	BootstrapContext.active = context
	# Match GameBootstrap's readiness broadcast after all services initialize.
	get_tree().call_group(BootstrapContext.SERVICE_CONSUMER_GROUP, "_on_bootstrap_context_ready", context)
	await _settle()
	var durable_slot_count := _validate_authored_items(scope, false)
	_expect(durable_slot_count > 0, "fixture must exercise actual durable tabletop slots")
	var store := CONTAINER.instantiate() as WorldContainer
	store.container_id = "tabletop_town.food_store"
	store.settlement_id = scope.settlement_id
	store.facility_id = scope.facility_id
	store.container_type = "food"
	scene.add_child(store)
	await _settle()
	_expect(_stock.transact_item_count(scope.settlement_id, BREAD, 2), "stock fixture accepts two real bread items")
	await _settle()
	_validate_authored_items(scope, true)
	var before := _origin_records()
	_expect(before.size() == durable_slot_count, "stock display does not mint another durable stack")
	var actor := WorldActor.new()
	actor.stable_id = "validation.tabletop.taker"
	scene.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	_gecs.register_actor(actor)
	var food := _stock_item(scope)
	_expect(food != null, "stock_changed creates the authored food projection")
	if food != null:
		var display_id := food.stack_id
		# Capacity refusal must leave the town debit and its display untouched.
		actor.inventory.set_admission_validator(func(_definition, _count): return false)
		_expect(not food.try_pickup(actor), "full/refusing actor inventory rejects a tabletop take")
		_expect(_bread_stock(scope) == 2 and actor.inventory.count_item(BREAD) == 0 and not food.is_queued_for_deletion(), "refused pickup conserves stock and live offer")
		actor.inventory.set_admission_validator(Callable())
		_expect(food.try_pickup(actor), "real WorldItem pickup accepts stocked bread")
		_expect(_bread_stock(scope) == 1 and actor.inventory.count_item(BREAD) == 1 and store.inventory.count_item(BREAD) == 1, "pickup debits indexed stock and backing container exactly once")
		await _settle()
		food = _stock_item(scope)
		_expect(food != null and food.stack_id == display_id, "remaining stock reconciles one stable display identity")
		if food != null:
			_expect(food.try_pickup(actor), "take last stocked bread")
		await _settle()
		_expect(_stock_item(scope) == null and _bread_stock(scope) == 0 and actor.inventory.count_item(BREAD) == 2, "empty backing stock removes the offer, conserving both bread")
		_expect(_gecs.get_item_stack(display_id).is_empty(), "display identity never becomes a duplicate durable bread stack")
	# Take a durable object too: remount must not reseed its vacated origin slot.
	var durable_items := _items(scope)
	_expect(not durable_items.is_empty(), "durable tabletop pickup has a real subject")
	var taken_id := ""
	if not durable_items.is_empty():
		var item: WorldItem = durable_items[0]
		taken_id = item.stack_id
		_expect(item.try_pickup(actor), "take a real durable tabletop item")
		await _settle()
		_expect(str(_gecs.get_item_stack(taken_id).get("location_kind", "")) == "inventory", "durable pickup commits lifecycle location to actor inventory")
		await _validate_inventory_mirror_publication(actor, taken_id)
	var expected := _origin_records()
	_expect(expected.size() == durable_slot_count, "taken slot retains origin provenance rather than becoming seedable")
	var old_ids: Array[int] = []
	for node in furniture:
		old_ids.append(node.get_instance_id())
		node.queue_free()
	await _settle()
	for id in old_ids:
		_expect(not is_instance_id_valid(id), "remount fixture destroys original authored furniture")
	scope.position = Vector3(31, 2, -17)
	furniture = [_make_furniture(TABLE, "table"), _make_furniture(SHELF, "shelf")]
	for node in furniture:
		scope.add_child(node)
	await _settle()
	_expect(_origin_records() == expected, "moved remount does not reseed, duplicate or reroll durable origin records")
	_check_live_identity(scope, expected, taken_id)
	_expect(_stock_item(scope) == null and _bread_stock(scope) == 0, "moved remount cannot recreate exhausted food stock")
	_expect(_stock.transact_item_count(scope.settlement_id, BREAD, 1), "restock backing container after remount")
	await _settle()
	_expect(_stock_item(scope) != null and _bread_stock(scope) == 1, "restock wakes the remounted authored food slot")
	var save_path := "user://tabletop_%d.tres" % OS.get_process_id()
	_expect(_gecs.save_gecs_world(save_path), "save tabletop lifecycle and real stock entities")
	_expect(_stock.transact_item_count(scope.settlement_id, BREAD, -1), "change stock after save")
	await _settle()
	_expect(_gecs.load_gecs_world(save_path), "reload real tabletop and stock snapshot")
	await _settle()
	_expect(_origin_records() == expected, "world reindex restores exact durable item identities and locations")
	_check_live_identity(scope, expected, taken_id)
	_expect(_stock_item(scope) != null and _bread_stock(scope) == 1 and store.inventory.count_item(BREAD) == 1, "load reconciles the backed offer and live stock container")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	scene.queue_free()
	await process_frame
	await process_frame
	BootstrapContext.active = null
	await _test_authored_world_item_bootstrap()
	await _test_authored_world_item_bootstrap(true)
	for owner_faction in ["Townsfolk", ""]:
		await _test_authored_world_item_round_trip(owner_faction)
		await _test_authored_world_item_round_trip(owner_faction, true)
	for failure in _failures:
		push_error(failure)
	print("TAVERN_TABLETOP_SPAWNER_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)


func _validate_inventory_mirror_publication(actor: WorldActor, stack_id: String) -> void:
	var entry: InventoryData.InventoryEntry
	for candidate in actor.inventory.entries:
		if candidate.stack_id == stack_id:
			entry = candidate
			break
	_expect(entry != null, "mirroring fixture starts with the exact live held stack")
	if entry == null:
		return
	var before := _lifecycle.get_stack_record(stack_id)
	_expect(before == _gecs.get_item_stack(stack_id), "warm lifecycle read initially matches GECS")
	var metadata := entry.metadata.duplicate(true)
	metadata["validation_publication"] = {"revision": 1, "nested": ["retained", 17]}
	actor.inventory.set_entry_metadata(entry, metadata, true)
	var durable := _gecs.get_item_stack(stack_id)
	var cached := _lifecycle.get_stack_record(stack_id)
	_expect(durable.get("metadata", {}) == metadata, "ordinary inventory signal synchronously publishes exact metadata to GECS")
	_expect(cached == durable, "warm lifecycle getter must observe ordinary inventory mirroring immediately")
	var host_id := str(metadata.get("tabletop_origin_host_id", ""))
	var hosted := _lifecycle.get_stack_records_for_host(host_id).filter(func(record: Dictionary) -> bool: return record.stack_id == stack_id)
	_expect(not host_id.is_empty() and hosted.size() == 1 and hosted[0] == durable, "host lookup must observe the same mirrored record exactly once")
	print("ITEM_MIRROR_BOUNDARY ", JSON.stringify({"stack_id": stack_id, "durable": durable, "lifecycle": cached}))
	await _settle()
	_expect(_lifecycle.get_stack_record(stack_id) == _gecs.get_item_stack(stack_id), "ordinary fixed-tick waiting must retain the same current record")
	var destination := CONTAINER.instantiate() as WorldContainer
	destination.container_id = "validation.mirror_destination"
	destination.container_type = "general"
	actor.get_parent().add_child(destination)
	await _settle()
	var source_position := entry.grid_position
	_expect(actor.inventory.move_entry_to_inventory(entry, destination.inventory, Vector2i.ZERO), "move the exact warm stack through ordinary paired-inventory transfer")
	durable = _gecs.get_item_stack(stack_id)
	cached = _lifecycle.get_stack_record(stack_id)
	_expect(durable.get("container_id") == destination.container_id and durable.get("metadata") == metadata, "fresh GECS records the exact destination and metadata after both handlers")
	_expect(cached == durable, "lifecycle location must follow mirrored actor-to-container transfer")
	_expect(_gecs.get_inventory_stacks().filter(func(record: Dictionary) -> bool: return record.stack_id == stack_id).size() == 1, "mirrored transfer leaves exactly one authoritative stack")
	print("ITEM_MIRROR_BOUNDARY ", JSON.stringify({"boundary": "transfer", "stack_id": stack_id, "durable": durable, "lifecycle": cached}))
	if not destination.inventory.entries.is_empty():
		_expect(destination.inventory.move_entry_to_inventory(destination.inventory.entries[0], actor.inventory, source_position), "restore the same stack through the reverse ordinary transfer")
	_expect(_lifecycle.get_stack_record(stack_id) == _gecs.get_item_stack(stack_id), "reverse transfer also refreshes the lifecycle record")
	destination.queue_free()
	var removed_id := "validation.mirror_removed_stack"
	var removed_host := "validation.mirror_removed_host"
	_expect(actor.inventory.add_entry_with_contents(SWORD, 1, {}, {"tabletop_origin_host_id": removed_host}, removed_id), "removal fixture creates one distinct real inventory stack")
	var removed_entry: InventoryData.InventoryEntry
	for candidate in actor.inventory.entries:
		if candidate.stack_id == removed_id:
			removed_entry = candidate
	_expect(not _lifecycle.get_stack_record(removed_id).is_empty(), "removal fixture warms an existing record")
	_expect(actor.inventory.remove_entry(removed_entry), "ordinary removal succeeds")
	_expect(_gecs.get_item_stack(removed_id).is_empty(), "ordinary removal deletes the authoritative stack")
	_expect(_lifecycle.get_stack_record(removed_id).is_empty() and _lifecycle.get_stack_records_for_host(removed_host).is_empty(), "removed inventory stack must leave neither a cached record nor a host entry")


func _make_furniture(packed: PackedScene, local_id: String) -> TabletopFurniture:
	var node := packed.instantiate() as TabletopFurniture
	node.surface_id = local_id
	# Force authored optional slots to participate; definitions/weights/stock flag
	# remain the scene's actual authoring, not a copied expected-output golden.
	for slot in node.get_node("TabletopSurface").get_children():
		if slot is TabletopItemSlot:
			slot.spawn_chance = 1.0
	return node


func _validate_authored_items(scope: Node, has_stock: bool) -> int:
	var count := 0
	for furniture in scope.get_children():
		var surface := furniture.get_node("TabletopSurface") as TabletopItemSpawner
		var host_id := "%s.%s" % [scope.facility_id, furniture.surface_id]
		var by_slot := {}
		for item in _items(furniture):
			_expect(not by_slot.has(item.placement_slot_id), "authored slot projects at most one item")
			by_slot[item.placement_slot_id] = item
		for slot in surface.get_children():
			if not slot is TabletopItemSlot:
				continue
			if slot.slot_id == "food":
				_expect(slot.stock_projection, "authored table food must be stock-backed")
			if slot.stock_projection and not has_stock:
				_expect(not by_slot.has(slot.slot_id), "empty stock cannot project food")
				continue
			_expect(by_slot.has(slot.slot_id), "bootstrap realizes authored slot " + slot.slot_id)
			if not by_slot.has(slot.slot_id):
				continue
			var item: WorldItem = by_slot[slot.slot_id]
			_expect(slot.optional_items.has(item.item_definition) or slot.required_item == item.item_definition, "projected definition comes from authored choices for " + slot.slot_id)
			_expect(item.placement_host_id == host_id and item.location_kind == "tabletop_slot" and item.stock_projection == slot.stock_projection, "projection has stable authored host and correct stock semantics")
			if slot.stock_projection:
				_expect(item.stock_source_settlement_id == scope.settlement_id and _gecs.get_item_stack(item.stack_id).is_empty(), "food is an offer against town stock, not a durable free item")
			else:
				count += 1
				var record := _gecs.get_item_stack(item.stack_id)
				_expect(not record.is_empty() and record.get("placement_slot_id") == slot.slot_id and record.get("item_definition_path") == item.item_definition.resource_path and int(record.get("count", 0)) == 1, "real lifecycle commits one item for " + slot.slot_id)
	return count


func _items(node: Node) -> Array[WorldItem]:
	var result: Array[WorldItem] = []
	for child in node.get_children():
		if child is WorldItem and not child.is_queued_for_deletion():
			result.append(child)
		else:
			result.append_array(_items(child))
	return result


func _stock_item(scope: Node) -> WorldItem:
	var result: WorldItem
	for item in _items(scope):
		if item.stock_projection:
			_expect(result == null, "only one backed offer per authored food slot")
			result = item
	return result


func _bread_stock(scope: Node) -> int:
	return int((_stock.get_settlement_stock_snapshot(scope.settlement_id).get("items", {}) as Dictionary).get(BREAD.item_id, 0))


func _origin_records() -> Dictionary:
	var result := {}
	for record in _gecs.get_inventory_stacks():
		if str((record.get("metadata", {}) as Dictionary).get("tabletop_origin_host_id", "")).begins_with("validation.tavern."):
			_expect(not result.has(record.stack_id), "GECS contains no duplicate tabletop stack entity")
			result[record.stack_id] = record
	return result


func _check_live_identity(scope: Node, records: Dictionary, taken_id: String) -> void:
	var ids := {}
	for item in _items(scope):
		if item.stock_projection:
			continue
		_expect(not ids.has(item.stack_id) and item.stack_id != taken_id, "remount never duplicates or respawns taken durable item")
		ids[item.stack_id] = true
		_expect(records.has(item.stack_id) and records[item.stack_id].item_definition_path == item.item_definition.resource_path, "remount preserves original identity and selected definition")
	var expected_live := 0
	for record in records.values():
		if record.location_kind == "tabletop_slot":
			expected_live += 1
	_expect(ids.size() == expected_live, "every remaining durable tabletop record projects once")


func _settle() -> void:
	# Lifecycle commands run at the production fixed tick; allow deferred stock
	# reconciliation and queued deletion to complete before inspecting both sides.
	await create_timer(0.12).timeout
	await process_frame


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _test_authored_world_item_bootstrap(load_before_deferred_bootstrap := false) -> void:
	# Both demos create WorldItems before bootstrap. The jail configures its
	# vase after add_child; the sneak demo calls setup first. Exercise both.
	var scene := Node3D.new()
	root.add_child(scene)
	var context := BootstrapContext.new(scene)
	var gecs := GecsWorldController.new()
	var lifecycle := ItemLifecycleController.new()
	var projection := PROJECTION_BRIDGE.new()
	for service in [gecs, lifecycle, projection]:
		context.register(service.SERVICE_ID, service)
		scene.add_child(service)
	gecs.initialize(context)
	gecs.set_process(false)
	lifecycle.initialize(context)
	# Existing equipment is an authoritative input, never permission to seed
	# another scene object with its identity. This snapshot also predates vase/sword.
	var equipment_record := gecs.upsert_item_stack_record({
		"stack_id": "authored.already_taken", "container_id": "actor.equipment",
		"owner_actor_id": "actor", "item_definition_path": SWORD.resource_path,
		"count": 1, "location_kind": "equipment", "placement_slot_id": "weapon",
		"metadata": {"quality": 0.75},
	})
	var save_path := "user://authored_world_items_%d.tres" % OS.get_process_id()
	_expect(gecs.save_gecs_world(save_path), "authored: save snapshot before new scene items exist")
	var vase := WORLD_ITEM.instantiate() as WorldItem
	vase.name = "OwnedVase"
	vase.stack_id = "authored.vase"
	scene.add_child(vase)
	vase.item_definition = VASE
	vase.quantity = 1
	vase.owner_faction_name = "Townsfolk"
	vase.item_metadata = {"origin": "authored", "quality": 0.625}
	vase.global_position = Vector3(7, 2, -4)
	vase.freeze = true
	var sword := WORLD_ITEM.instantiate() as WorldItem
	sword.name = "OwnedSword"
	sword.setup(SWORD, 1, {}, "authored.sword")
	sword.owner_faction_name = "Townsfolk"
	sword.position = Vector3(-3, 2, 4)
	sword.freeze = true
	scene.add_child(sword)
	var taken := WORLD_ITEM.instantiate() as WorldItem
	taken.setup(SWORD, 1, {}, "authored.already_taken")
	taken.freeze = true
	scene.add_child(taken)
	var vase_instance := vase.get_instance_id()
	var sword_instance := sword.get_instance_id()
	var taken_instance := taken.get_instance_id()
	var vase_transform := vase.global_transform
	BootstrapContext.active = context
	projection.initialize(context)
	if load_before_deferred_bootstrap:
		_expect(gecs.load_gecs_world(save_path), "authored cold load: snapshot wins before deferred startup")
		await _settle()
		_expect(_items_with_stack_id("authored.vase").is_empty() and _items_with_stack_id("authored.sword").is_empty(), "authored cold load: absent initial props must not be seeded after load")
		_expect(gecs.get_inventory_stacks() == [equipment_record], "authored cold load: exactly the saved equipment survives, with no invented stacks")
		_expect(_items_with_stack_id("authored.already_taken").is_empty(), "authored cold load: equipment never regains a world projection")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		scene.queue_free()
		await process_frame
		await process_frame
		BootstrapContext.active = null
		return
	await _settle()
	_expect(is_instance_id_valid(vase_instance) and is_instance_id_valid(sword_instance), "authored: pre-bootstrap vase and sword survive initial orphan reconciliation")
	var vase_record := gecs.get_item_stack("authored.vase")
	var sword_record := gecs.get_item_stack("authored.sword")
	_expect(_items_with_stack_id("authored.vase").size() == 1 and _items_with_stack_id("authored.sword").size() == 1, "authored: exactly one visible projection per durable identity after commit")
	if is_instance_id_valid(vase_instance) and is_instance_id_valid(sword_instance):
		_expect(vase.get_owner_faction_name() == "Townsfolk" and sword.get_owner_faction_name() == "Townsfolk" and vase.item_metadata == {"origin": "authored", "quality": 0.625}, "authored: commit retains authored ownership and metadata on the original projections")
	_expect(vase_record.get("item_definition_path") == VASE.resource_path and int(vase_record.get("count", 0)) == 1 and vase_record.get("metadata", {}) == {"origin": "authored", "quality": 0.625}, "authored: initial vase becomes one exact durable stack")
	_expect(sword_record.get("item_definition_path") == SWORD.resource_path, "authored: setup-before-tree sword becomes a durable stack")
	_expect((vase_record.get("world_transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(vase_transform), "authored: startup captures configured world transform, not an identity transform")
	_expect(not is_instance_id_valid(taken_instance) and gecs.get_item_stack("authored.already_taken") == equipment_record, "authored: startup never resurrects already-taken equipment")
	projection._reconcile()
	await _settle()
	_expect(gecs.get_inventory_stacks().size() == 3, "authored: repeated reconciliation does not seed duplicates")
	if is_instance_id_valid(vase_instance):
		var actor := WorldActor.new()
		actor.stable_id = "authored.taker"
		scene.add_child(actor)
		actor.set_process(false)
		actor.set_physics_process(false)
		gecs.register_actor(actor)
		_expect(vase.try_pickup(actor), "authored: actual pickup accepts the durably seeded vase")
		await _settle()
		_expect(not is_instance_id_valid(vase_instance) and actor.inventory.count_item(VASE) == 1 and gecs.get_item_stack("authored.vase").get("location_kind") == "inventory", "authored: pickup removes projection and commits the same identity to inventory")
		projection._reconcile()
		await _settle()
		_expect(_items(scene).size() == 1, "authored: reconciliation cannot recreate the taken vase")
	# Reconcile a submitted world drop before its fixed-tick commit. Absence
	# from durable GECS is not orphanhood when an accepted UPSERT is pending.
	var pending := WORLD_ITEM.instantiate() as WorldItem
	pending.setup(VASE, 1, {}, "authored.pending")
	pending.owner_faction_name = "Townsfolk"
	pending.item_metadata = {"pending_origin": true}
	pending.position = Vector3(12, 2, -3)
	pending.freeze = true
	scene.add_child(pending)
	var pending_instance := pending.get_instance_id()
	var pending_transform := pending.global_transform
	var submitted := lifecycle.submit_world_stack({
		"stack_id": pending.stack_id, "container_id": "world", "owner_actor_id": "",
		"owner_faction_name": pending.owner_faction_name,
		"item_definition_path": VASE.resource_path, "count": 1, "location_kind": "world_loose",
		"world_transform": pending_transform, "metadata": pending.item_metadata,
	})
	_expect(bool(submitted.get("accepted", false)) and gecs.get_item_stack(pending.stack_id).is_empty(), "pending: accepted command precedes durable fixed-tick commit")
	projection._reconcile()
	_expect(not pending.is_queued_for_deletion(), "pending: reconcile must not free a projection awaiting its accepted world-stack command")
	await _settle()
	var pending_items := _items_with_stack_id("authored.pending")
	_expect(pending_items.size() == 1 and is_instance_id_valid(pending_instance), "pending: fixed tick retains exactly one original projection, not a nameless replacement")
	if is_instance_id_valid(pending_instance):
		_expect(pending.get_owner_faction_name() == "Townsfolk" and pending.item_metadata == {"pending_origin": true}, "pending: commit preserves authored owner and metadata")
	_expect((gecs.get_item_stack("authored.pending").get("world_transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(pending_transform), "pending: command commits the exact submitted transform")
	var orphan := WORLD_ITEM.instantiate() as WorldItem
	orphan.setup(VASE, 1, {}, "authored.orphan")
	scene.add_child(orphan)
	var orphan_instance := orphan.get_instance_id()
	projection._reconcile()
	await _settle()
	_expect(not is_instance_id_valid(orphan_instance) and gecs.get_item_stack("authored.orphan").is_empty(), "authored: ordinary missing-record orphan is removed, not seeded by reconciliation")
	_expect(gecs.load_gecs_world(save_path), "authored: load older snapshot missing the newly authored items")
	await _settle()
	_expect(not is_instance_id_valid(sword_instance) and gecs.get_item_stack("authored.sword").is_empty(), "authored: load removes missing-record sword instead of reseeding it")
	_expect(gecs.get_item_stack("authored.vase").is_empty() and _items_with_stack_id("authored.vase").is_empty() and _items_with_stack_id("authored.sword").is_empty() and _items_with_stack_id("authored.pending").is_empty(), "authored: missing records on load are not permission to respawn authored stock")
	_expect(gecs.get_item_stack("authored.already_taken") == equipment_record, "authored: saved equipment remains exact after load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	scene.queue_free()
	await process_frame
	await process_frame
	BootstrapContext.active = null


func _make_owned_item_world(owner_faction_name: String) -> Dictionary:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var context := BootstrapContext.new(scene)
	var gecs := GecsWorldController.new()
	var lifecycle := ItemLifecycleController.new()
	var projection := PROJECTION_BRIDGE.new()
	for service in [gecs, lifecycle, projection]:
		context.register(service.SERVICE_ID, service)
		scene.add_child(service)
	gecs.initialize(context)
	gecs.set_process(false)
	lifecycle.initialize(context)
	var item := WORLD_ITEM.instantiate() as WorldItem
	# Like the sneak demo: setup allocates a new ID on every scene construction.
	item.setup(VASE, 1)
	item.owner_faction_name = owner_faction_name
	item.item_metadata = {"origin": "authored", "quality": 0.625, "nested": {"serial": "round_trip"}}
	item.position = Vector3(7, 2, -4)
	item.location_kind = "world_placed"
	scene.add_child(item)
	BootstrapContext.active = context
	projection.initialize(context)
	return {"scene": scene, "context": context, "gecs": gecs, "lifecycle": lifecycle, "projection": projection, "item": item}


func _destroy_item_world(state: Dictionary, previous_scene: Node) -> void:
	current_scene = previous_scene
	state.scene.queue_free()
	await process_frame
	await process_frame
	BootstrapContext.active = null


func _test_authored_world_item_round_trip(owner_faction_name: String, save_pending := false) -> void:
	var previous_scene := current_scene
	var source := _make_owned_item_world(owner_faction_name)
	var label := "%s %s reload: " % ["unowned" if owner_faction_name.is_empty() else "owned", "pending" if save_pending else "committed"]
	if save_pending:
		# Execute the normal one-time ingestion, then save before its fixed tick.
		source.projection._finish_authored_bootstrap()
	else:
		await _settle()
	var saved_id: String = source.item.stack_id
	var original_instance: int = source.item.get_instance_id()
	var world_instance: int = source.scene.get_instance_id()
	var saved_record: Dictionary = source.gecs.get_item_stack(saved_id)
	_expect(source.item.get_owner_faction_name() == owner_faction_name, label + "initial authored ownership is exact")
	_expect(saved_record.is_empty() if save_pending else not saved_record.is_empty(), label + "snapshot is at the intended command boundary")
	var save_path := "user://owned_world_item_%d.tres" % OS.get_process_id()
	_expect(source.gecs.save_gecs_world(save_path), label + "save positive authored snapshot")
	if save_pending:
		_expect(source.lifecycle.has_pending_world_stack(saved_id), label + "accepted UPSERT exists without a durable stack")
		_expect(source.gecs.load_gecs_world(save_path), label + "reload queued UPSERT before fixed tick")
		source.projection._reconcile()
		_expect(source.lifecycle.has_pending_world_stack(saved_id) and not source.item.is_queued_for_deletion(), label + "loaded accepted command retains original projection")
		await _settle()
		saved_record = source.gecs.get_item_stack(saved_id)
		_expect(is_instance_id_valid(original_instance) and _items_with_stack_id(saved_id).size() == 1, label + "loaded command commits on the original instance exactly once")
		_expect(source.item.owner_faction_name == owner_faction_name and not source.lifecycle.has_pending_world_stack(saved_id), label + "commit restores ownership and consumes its command")
	_expect(saved_record.get("owner_faction_name") == owner_faction_name and source.gecs.get_inventory_stacks() == [saved_record], label + "GECS single and bulk snapshots agree on exact owner and payload")
	await _destroy_item_world(source, previous_scene)
	_expect(not is_instance_id_valid(world_instance) and not is_instance_id_valid(original_instance), label + "original world and projection actually destroyed")
	var loaded := _make_owned_item_world(owner_faction_name)
	var regenerated_id: String = loaded.item.stack_id
	var regenerated_instance: int = loaded.item.get_instance_id()
	_expect(regenerated_id != saved_id, label + "fresh authored scene allocates a new identity")
	_expect(loaded.gecs.load_gecs_world(save_path), label + "load before deferred authored bootstrap")
	await _settle()
	var matches := _items_with_stack_id(saved_id)
	_expect(not is_instance_id_valid(regenerated_instance), label + "unsaved regenerated projection is pruned")
	_expect(matches.size() == 1, label + "exactly one saved identity is realized")
	_expect(loaded.gecs.get_inventory_stacks() == [saved_record], label + "exact saved record and no durable duplication")
	_expect(not loaded.lifecycle.has_pending_world_stack(saved_id), label + "no loaded command remains to replay")
	if matches.size() == 1:
		_expect(matches[0].item_metadata == saved_record.metadata and matches[0].contained_item_counts == saved_record.contained_item_counts, label + "nested metadata and contents survive fresh realization")
		_expect(matches[0].global_transform.is_equal_approx(saved_record.world_transform) and matches[0].item_definition == VASE and matches[0].quantity == 1, label + "exact transform, definition and count survive fresh realization")
		_expect(matches[0].get_owner_faction_name() == owner_faction_name, label + "cold-loaded authored ownership is exact")
		loaded.projection._reconcile()
		await _settle()
		_expect(_items_with_stack_id(saved_id).size() == 1 and loaded.gecs.get_inventory_stacks() == [saved_record], label + "repeated reconciliation cannot duplicate or reroll")
		if not save_pending:
			if not owner_faction_name.is_empty():
				await _test_retained_item_owner_clearing(loaded, saved_record)
			await _test_reloaded_item_pickup(loaded, saved_record)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	await _destroy_item_world(loaded, previous_scene)
	print("WORLD_ITEM_ROUND_TRIP owner=%s pending=%s" % [var_to_str(owner_faction_name), save_pending])


func _test_retained_item_owner_clearing(state: Dictionary, owned_record: Dictionary) -> void:
	var item := _items_with_stack_id(owned_record.stack_id)[0]
	var instance_id := item.get_instance_id()
	var unowned := owned_record.duplicate(true)
	unowned["owner_faction_name"] = ""
	_expect(state.lifecycle.submit_world_stack(unowned).get("accepted", false), "owner clear: accept explicit empty stamp")
	await _settle()
	_expect(is_instance_id_valid(instance_id) and item.get_owner_faction_name().is_empty() and state.gecs.get_item_stack(item.stack_id) == unowned, "owner clear: authoritative empty clears the retained projection without payload change")
	var save_path := "user://cleared_world_item_%d.tres" % OS.get_process_id()
	_expect(state.gecs.save_gecs_world(save_path), "owner clear: save legitimately unowned record")
	_expect(state.lifecycle.submit_world_stack(owned_record).get("accepted", false), "owner clear: restamp after save")
	await _settle()
	_expect(item.owner_faction_name == "Townsfolk", "owner clear: subject is owned before in-place load")
	_expect(state.gecs.load_gecs_world(save_path), "owner clear: load unowned snapshot over owned projection")
	await _settle()
	_expect(is_instance_id_valid(instance_id) and item.get_owner_faction_name().is_empty() and state.gecs.get_item_stack(item.stack_id) == unowned, "owner clear: same projection obeys saved empty ownership")
	# Old/full replacement payloads without the new field also mean no stamp.
	_expect(state.lifecycle.submit_world_stack(owned_record).get("accepted", false), "owner clear: prepare legacy replacement")
	await _settle()
	var legacy := owned_record.duplicate(true)
	legacy.erase("owner_faction_name")
	_expect(state.lifecycle.submit_world_stack(legacy).get("accepted", false), "owner clear: accept legacy replacement without owner")
	await _settle()
	_expect(is_instance_id_valid(instance_id) and item.owner_faction_name.is_empty() and state.gecs.get_item_stack(item.stack_id) == unowned, "owner clear: missing field never guesses ownership from stale projection")
	# Preserve the distinct live facility-inheritance contract, not a frozen stamp.
	var facility := SettlementFacility.new()
	facility.facility_id = "ownership.inheritance"
	facility.owner_faction_id = "FacilityOwner"
	state.scene.add_child(facility)
	item.reparent(facility)
	state.projection._reconcile()
	_expect(item.owner_faction_name.is_empty() and item.get_owner_faction_name() == "FacilityOwner", "owner clear: empty stamp still inherits its actual facility")
	facility.owner_faction_id = "NextOwner"
	_expect(item.get_owner_faction_name() == "NextOwner", "owner clear: inherited ownership follows facility turnover")
	item.reparent(state.scene)
	facility.queue_free()
	# Reparenting exits the tree (unregisters) without rerunning WorldItem._ready.
	# Rediscover the moved fixture just as above before submitting another update.
	state.projection._reconcile()
	_expect(item.get_owner_faction_name().is_empty(), "owner clear: no facility means genuinely unowned, not a cached faction")
	_expect(state.lifecycle.submit_world_stack(owned_record).get("accepted", false), "owner clear: restore owned record for pickup semantics")
	await _settle()
	_expect(is_instance_id_valid(instance_id) and _items_with_stack_id(item.stack_id).size() == 1 and item.get_owner_faction_name() == "Townsfolk" and state.gecs.get_item_stack(item.stack_id) == owned_record, "owner clear: ownership changes preserve exact identity and metadata")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _test_reloaded_item_pickup(state: Dictionary, saved_record: Dictionary) -> void:
	var context: BootstrapContext = state.context
	var ownership := OwnershipController.new()
	var law := LawOrderController.new()
	for service in [BuildingRegistry.new(), ActorQueryController.new(), CrimeAlertController.new(), law, ownership]:
		context.register(service.SERVICE_ID, service)
		state.scene.add_child(service)
		service.initialize(context)
	var actor := HumanoidCharacter.new()
	actor.stable_id = "ownership.roundtrip.taker"
	actor.faction_name = "Townsfolk"
	state.scene.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	state.gecs.register_actor(actor)
	var item := _items_with_stack_id(saved_record.stack_id)[0]
	_expect(not ownership.is_take_item_theft(actor, item) and ownership.get_take_item_metadata(actor, item, item.item_metadata) == saved_record.metadata, "loaded pickup: owner-faction take is legal without stolen metadata")
	actor.faction_name = "Player"
	var is_theft := not str(saved_record.owner_faction_name).is_empty()
	_expect(ownership.is_take_item_theft(actor, item) == is_theft, "loaded pickup: canonical ownership distinguishes owned from legitimately unowned")
	var expected_metadata: Dictionary = saved_record.metadata.duplicate(true)
	if is_theft:
		expected_metadata.merge(law.make_stolen_item_metadata(actor, item), true)
	_expect(ownership.get_take_item_metadata(actor, item, item.item_metadata) == expected_metadata, "loaded pickup: only the canonical theft path adds stolen provenance")
	actor.inventory.set_admission_validator(func(_definition, _count): return false)
	_expect(not item.try_pickup(actor) and not item.is_queued_for_deletion() and actor.inventory.count_item(VASE) == 0 and state.gecs.get_item_stack(item.stack_id) == saved_record, "loaded pickup: capacity refusal conserves owned/unowned world record and payload")
	actor.inventory.set_admission_validator(Callable())
	_expect(item.try_pickup(actor), "loaded pickup: real ownership-authorized pickup succeeds without witnesses")
	await _settle()
	var entry = actor.inventory.entries[0] if actor.inventory.entries.size() == 1 else null
	_expect(entry != null and entry.stack_id == saved_record.stack_id and entry.metadata == expected_metadata and entry.contained_item_counts == saved_record.contained_item_counts, "loaded pickup: exact stack enters inventory with canonical metadata")
	_expect(_items_with_stack_id(saved_record.stack_id).is_empty() and state.gecs.get_item_stack(saved_record.stack_id).get("location_kind") == "inventory", "loaded pickup: no world resurrection after inventory commit")
	if entry == null:
		return
	# Use the normal inventory drop handler, not a handcrafted world-stack payload.
	var party := PartyManager.new()
	party.name = "PartyManager"
	state.scene.add_child(party)
	var hud := CanvasLayer.new()
	hud.name = "GameHUD"
	var windows := Control.new()
	windows.name = "InventoryWindowLayer"
	hud.add_child(windows)
	state.scene.add_child(hud)
	var inventory := PartyInventoryController.new()
	state.scene.add_child(inventory)
	inventory.initialize(context)
	inventory._on_inventory_item_drop_requested(actor, entry)
	await _settle()
	var dropped := _items_with_stack_id(saved_record.stack_id)
	_expect(actor.inventory.count_item(VASE) == 0 and dropped.size() == 1, "loaded drop: inventory handler moves exactly one same-ID item back to world")
	if dropped.size() == 1:
		_expect(dropped[0].owner_faction_name.is_empty() and dropped[0].get_owner_faction_name().is_empty() and dropped[0].item_metadata == expected_metadata, "loaded drop: no obsolete authored owner, stolen metadata retained separately")
		_expect(state.gecs.get_item_stack(saved_record.stack_id).get("owner_faction_name") == "" and state.gecs.get_item_stack(saved_record.stack_id).get("metadata") == expected_metadata, "loaded drop: durable state agrees with legitimate drop ownership and payload")


func _items_with_stack_id(stack_id: String) -> Array[WorldItem]:
	var result: Array[WorldItem] = []
	for item in get_tree().get_nodes_in_group("world_item"):
		if item is WorldItem and item.stack_id == stack_id and not item.is_queued_for_deletion():
			result.append(item)
	return result
