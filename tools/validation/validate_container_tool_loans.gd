extends SceneTree

## Reusable tool-loan transaction used by town occupations.
## Run: godot --headless --path . --script res://tools/validation/validate_container_tool_loans.gd

const TOOL_CHEST_PATH := "res://features/world/projection/props/furniture/tool_chest.tscn"
const HOE_PATH := "res://features/inventory/resources/items/hoe.tres"
const SWORD_PATH := "res://features/inventory/resources/items/iron_sword.tres"
const FARM_BRIDGE_PATH := "res://features/farming/bridge/farm_work_bridge.gd"

var _failures: Array[String] = []


class FakeEquipment:
	extends RefCounted
	var equipped: ItemDefinition
	var stack_id := ""
	func get_equipped_item(_slot: String): return equipped
	func get_equipped_stack_id(_slot: String) -> String: return stack_id
	func can_equip_item_to_slot(definition: ItemDefinition, _slot: String) -> bool: return definition != null
	func equip_item_to_slot(definition: ItemDefinition, _slot: String, incoming_stack_id := ""):
		var previous := equipped
		equipped = definition
		stack_id = incoming_stack_id
		return previous
	func unequip_item_from_slot(_slot: String):
		var previous := equipped
		equipped = null
		stack_id = ""
		return previous
	func begin_equipment_update_batch() -> void: pass
	func end_equipment_update_batch() -> void: pass


class FakeActor:
	extends Node3D
	var stable_id := "town.worker"
	var faction_name := "Town"
	var inventory := InventoryData.new(2, 4, 100.0, true)
	var equipment := FakeEquipment.new()
	var move_target := Vector3.ZERO
	func get_inventory(): return inventory
	func get_equipment(): return equipment
	func is_player_party_member() -> bool: return false
	func has_active_player_order() -> bool: return false
	func get_active_job_provider(): return null
	func get_skill_level(_skill: String) -> float: return 10.0
	func set_move_target(target: Vector3, _issued := false) -> void: move_target = target
	func has_move_target() -> bool: return false


class FakeFarm:
	extends Node
	var hoe: ItemDefinition
	var required_tool_tag := "tool.hoe"
	func get_plot(_plot_id: String) -> Dictionary:
		return {"plot_id": "farm:test", "owner_faction_id": "Town", "settlement_id": "town"}
	func get_cell_work(_plot_id: String, _cell_key: String) -> Dictionary:
		return {
			"plot_id": "farm:test", "cell_key": "0:0", "action": "till",
			"settlement_id": "town", "owner_faction_id": "Town",
			"world_position": Vector3(5.0, 0.0, 0.0), "required_tool_tag": required_tool_tag,
			"required_tool_label": "Hoe", "required_seconds": 1.0, "progress_seconds": 0.0,
		}
	func can_actor_command_plot(_actor: Node, _plot_id: String) -> bool: return true
	func get_available_work_records() -> Array: return []


class FakeToolStore:
	extends Node3D
	var container_id := "town.tool_store"
	var settlement_id := "town"
	var container_type := "tools"
	var container_kind := "tool_store"
	var owner_faction_name := "Town"
	var inventory := InventoryData.new(8, 8, 100.0, true)
	var reservations := {}
	func get_owner_faction_name() -> String: return owner_faction_name
	func get_interaction_position(_actor: Node) -> Vector3: return global_position
	func find_reservable_tool(tag: String, actor: Node):
		var actor_key := actor.get_instance_id()
		for entry in inventory.entries:
			if entry.definition.has_tool_tag(tag) and (reservations.is_empty() or reservations.has(actor_key)):
				return entry.definition
		return null
	func reserve_item_for_actor(definition: ItemDefinition, actor: Node, _amount := 1) -> bool:
		var actor_key := actor.get_instance_id()
		if not reservations.is_empty() and not reservations.has(actor_key): return false
		var entry = inventory.entries[0]
		reservations[actor_key] = {"definition": definition, "stack_id": str(entry.stack_id), "checked_out": false}
		return true
	func release_item_reservation(actor_key: int) -> void: reservations.erase(actor_key)
	func get_item_reservation_snapshot(actor: Node) -> Dictionary: return (reservations.get(actor.get_instance_id(), {}) as Dictionary).duplicate(true)
	func withdraw_reserved_item_to(definition: ItemDefinition, actor: Node, target) -> bool:
		var actor_key := actor.get_instance_id()
		var reservation: Dictionary = reservations.get(actor_key, {})
		if reservation.get("definition") != definition: return false
		var entry = inventory.entries[0]
		var moved: bool = inventory.move_entry_to_inventory(entry, target, target.find_first_space(definition))
		if moved:
			reservation["checked_out"] = true
			reservations[actor_key] = reservation
		return moved
	func return_borrowed_item_from(definition: ItemDefinition, actor: Node, source, stack_id: String) -> bool:
		var actor_key := actor.get_instance_id()
		var reservation: Dictionary = reservations.get(actor_key, {})
		if reservation.get("definition") != definition or str(reservation.get("stack_id", "")) != stack_id: return false
		var entry = source.entries.filter(func(candidate): return str(candidate.stack_id) == stack_id)[0]
		var moved: bool = source.move_entry_to_inventory(entry, inventory, inventory.find_first_space(definition))
		if moved: reservations.erase(actor_key)
		return moved
	func return_borrowed_equipped_item(definition: ItemDefinition, actor: Node, equipment, stack_id: String, _snapshot := {}) -> bool:
		var actor_key := actor.get_instance_id()
		var reservation: Dictionary = reservations.get(actor_key, {})
		if reservation.get("definition") != definition or str(reservation.get("stack_id", "")) != stack_id: return false
		equipment.unequip_item_from_slot("weapon")
		var moved: bool = inventory.add_entry_with_contents(definition, 1, {}, {}, stack_id)
		if not moved:
			equipment.equip_item_to_slot(definition, "weapon", stack_id)
			return false
		reservations.erase(actor_key)
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	load("res://addons/gecs/ecs/ecs.gd")
	var hoe: ItemDefinition = load(HOE_PATH)
	var sword: ItemDefinition = load(SWORD_PATH)
	var chest: Node = (load(TOOL_CHEST_PATH) as PackedScene).instantiate()
	chest.owner_faction_name = "Town"
	root.add_child(chest)
	await process_frame
	_expect(chest.inventory.count_item(hoe) == 0, "Raw/player-built tool furniture must start empty")
	chest.inventory.add_item_count(hoe, 1)
	var original_entry = chest.inventory.entries[0]
	original_entry.metadata = {"durability": 37}
	var original_stack_id := str(original_entry.stack_id)
	var worker_a := FakeActor.new()
	var worker_b := FakeActor.new()
	var foreign_worker := FakeActor.new()
	foreign_worker.faction_name = "Other"
	_expect(chest.has_method("find_reservable_tool"), "Tool containers must find a tool by capability tag")
	_expect(chest.has_method("reserve_item_for_actor"), "Tool checkout must reserve before travel")
	_expect(chest.has_method("withdraw_reserved_item_to"), "Tool checkout must transfer the reserved item atomically on arrival")
	if chest.has_method("find_reservable_tool") and chest.has_method("reserve_item_for_actor") and chest.has_method("withdraw_reserved_item_to"):
		_expect(chest.call("find_reservable_tool", "tool.hoe", foreign_worker) == null and not bool(chest.call("reserve_item_for_actor", hoe, foreign_worker, 1)), "Foreign workers must not bypass tool-store ownership")
		chest.is_locked = true
		_expect(chest.call("find_reservable_tool", "tool.hoe", worker_a) == null and not bool(chest.call("reserve_item_for_actor", hoe, worker_a, 1)), "Locked tool stores must reject automatic checkout at the authoritative boundary")
		chest.is_locked = false
		var selected = chest.call("find_reservable_tool", "tool.hoe", worker_a)
		_expect(selected == hoe, "Tool chest must resolve the authored hoe by tool tag")
		_expect(bool(chest.call("reserve_item_for_actor", hoe, worker_a, 1)), "First worker must reserve the hoe")
		_expect(chest.call("find_reservable_tool", "tool.hoe", worker_b) == null, "Second worker must not target a reserved hoe")
		var carried := InventoryData.new(8, 8, 100.0, true)
		_expect(bool(chest.call("withdraw_reserved_item_to", hoe, worker_a, carried)), "Reserved hoe must transfer on worker arrival")
		_expect(chest.inventory.count_item(hoe) == 0 and carried.count_item(hoe) == 1, "Checkout must leave one authoritative hoe in the worker inventory")
		_expect(str(carried.entries[0].stack_id) == original_stack_id and carried.entries[0].metadata == {"durability": 37}, "Checkout must preserve the exact reserved stack identity and metadata")
		_expect(chest.call("find_reservable_tool", "tool.hoe", worker_b) == null, "Checked-out tool must remain unavailable until returned")
		_expect(bool(chest.call("return_borrowed_item_from", hoe, worker_a, carried, original_stack_id)), "Borrowed hoe must return to its origin container")
		_expect(chest.inventory.count_item(hoe) == 1 and carried.count_item(hoe) == 0, "Return must restore the same authoritative tool count")
		_expect(str(chest.inventory.entries[0].stack_id) == original_stack_id and chest.inventory.entries[0].metadata == {"durability": 37}, "Return must preserve exact stack identity and metadata")
		_expect(bool(chest.call("reserve_item_for_actor", hoe, worker_a, 1)) and bool(chest.call("withdraw_reserved_item_to", hoe, worker_a, carried)), "Exact tool must support another checkout")
		var equipped_entry = carried.entries[0]
		var equipment := worker_a.equipment
		equipment.equip_item_to_slot(hoe, "weapon", str(equipped_entry.stack_id))
		carried.remove_entry(equipped_entry)
		_expect(bool(chest.call("return_borrowed_equipped_item", hoe, worker_a, equipment, original_stack_id, {"count": 1, "metadata": {"durability": 22}})), "Equipped borrowed tool must return without requiring a free personal-inventory slot")
		_expect(equipment.equipped == null and str(chest.inventory.entries[0].stack_id) == original_stack_id and chest.inventory.entries[0].metadata == {"durability": 22}, "Direct equipped return must preserve current mutable state and exact identity")
	worker_a.free()
	worker_b.free()
	foreign_worker.free()
	chest.queue_free()
	await process_frame
	var farm_source := FileAccess.get_file_as_string(FARM_BRIDGE_PATH)
	for symbol in ["_nearest_tool_store", "_complete_tool_fetch", "_append_borrowed_tool_return_offers", "_complete_tool_return"]:
		_expect(farm_source.contains("func %s" % symbol), "Farm work bridge is missing the exact tool-loan transaction: %s" % symbol)
	var accept_source := farm_source.get_slice("func _assign_cell_to_actor", 1).get_slice("func _process_assignment", 0)
	var fetch_source := farm_source.get_slice("func _complete_tool_fetch", 1).get_slice("func _ensure_tool", 0)
	_expect(not accept_source.contains("_farm.get_plot") and not fetch_source.contains("_farm.get_plot"), "Worker acceptance/fetch must use indexed cell headers without deep-copying whole plots")
	await _validate_farm_bridge_tool_route(hoe, sword)
	_finish()


func _validate_farm_bridge_tool_route(hoe: ItemDefinition, sword: ItemDefinition) -> void:
	var bridge: Node = (load(FARM_BRIDGE_PATH) as Script).new()
	var farm := FakeFarm.new()
	farm.hoe = hoe
	var actor := FakeActor.new()
	actor.set_meta("settlement_id", "town")
	actor.equipment.equip_item_to_slot(sword, "weapon", "town.worker.sword")
	var store := FakeToolStore.new()
	store.inventory.add_item_count(hoe, 1)
	var stock_index := InventoryStockController.new()
	root.add_child(farm)
	root.add_child(bridge)
	root.add_child(actor)
	root.add_child(store)
	root.add_child(stock_index)
	bridge.set("_farm", farm)
	var context := BootstrapContext.new(root)
	context.register(InventoryStockController.SERVICE_ID, stock_index)
	BootstrapContext.active = context
	stock_index.bind_world_container(store)
	var result: String = bridge.call("_assign_cell_to_actor", actor, "farm:test", "0:0", true)
	var actor_key := actor.get_instance_id()
	_expect(result.is_empty() and str((bridge.get("_assignments") as Dictionary)[actor_key].get("stage", "")) == "work", "Town farmer must instantly check out a reserved tool and travel directly to field work")
	_expect(store.inventory.count_item(hoe) == 0 and actor.equipment.equipped == hoe and actor.inventory.count_item(sword) == 1, "Immediate checkout must withdraw the exact hoe and safely stow prior equipment")
	_expect((bridge.get("_borrowed_tools") as Dictionary).has(actor_key), "Borrowed tool must retain its origin contract across farm cells")
	(bridge.get("_assignments") as Dictionary).erase(actor_key)
	farm.required_tool_tag = "tool.scythe"
	var incompatible_result: String = bridge.call("_assign_cell_to_actor", actor, "farm:test", "0:0", true)
	_expect(incompatible_result.contains("Return borrowed tool") and (bridge.get("_borrowed_tools") as Dictionary).has(actor_key), "A worker must return one borrowed tool before checking out a different tool")
	var offers: Array = bridge.call("get_available_work_offers", "town")
	_expect(offers.size() == 1 and str(offers[0].get("action", "")) == "return_borrowed_tool", "No remaining field work must publish one exact-worker tool return")
	_expect(str(bridge.call("accept_work_offer", offers[0], actor)).begins_with("Worker assigned"), "Farmer must accept the physical return trip")
	bridge.call("_complete_tool_return", actor_key)
	_expect(store.inventory.count_item(hoe) == 1 and actor.inventory.count_item(hoe) == 0, "Tool return must restore the hoe to its origin chest exactly once")
	_expect(actor.equipment.equipped == sword and actor.inventory.count_item(sword) == 0, "Tool return must restore the worker's exact prior equipment")
	_expect(not (bridge.get("_borrowed_tools") as Dictionary).has(actor_key), "Completed return must close the loan contract")
	BootstrapContext.active = null
	for node in [stock_index, store, actor, bridge, farm]:
		node.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CONTAINER_TOOL_LOANS_OK")
	else:
		print("CONTAINER_TOOL_LOANS_FAILED count=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
