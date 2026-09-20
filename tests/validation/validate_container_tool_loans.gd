extends "res://tests/validation/test_case.gd"

## Reusable tool-loan transaction used by town occupations.
## Run: godot --headless --path . --script res://tests/validation/validate_container_tool_loans.gd

const TOOL_CHEST_PATH := "res://features/world/projection/props/furniture/tool_chest.tscn"
const HOE_PATH := "res://features/inventory/resources/items/hoe.tres"
const SWORD_PATH := "res://features/inventory/resources/items/iron_sword.tres"
const FARM_BRIDGE_PATH := "res://features/farming/bridge/farm_work_bridge.gd"

# Keep real reservation/checkout/return methods; isolate navigation and GECS
# mirroring, which need real HumanoidCharacter capability projections.
class ToolStore:
	extends WorldContainer
	func get_interaction_position(_actor) -> Vector3: return global_position
	func _bind_inventory_state() -> void: pass
	func _sync_inventory_to_gecs() -> void: pass

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
	var actor := FakeActor.new()
	actor.set_meta("settlement_id", "town")
	actor.equipment.equip_item_to_slot(sword, "weapon", "town.worker.sword")
	# Real containers enforce one exact loan per actor. A separate next-tool
	# chest prevents a synthetic reservation from overwriting the old loan.
	var store: Node = (load(TOOL_CHEST_PATH) as PackedScene).instantiate()
	var next_store: Node = (load(TOOL_CHEST_PATH) as PackedScene).instantiate()
	store.set_script(ToolStore)
	next_store.set_script(ToolStore)
	store.container_id = "town.hoe_store"
	next_store.container_id = "town.scythe_store"
	for chest in [store, next_store]:
		chest.settlement_id = "town"
		chest.container_type = "tools"
		chest.owner_faction_name = "Town"
	var stock_index := InventoryStockController.new()
	var context := BootstrapContext.new(root)
	context.register(InventoryStockController.SERVICE_ID, stock_index)
	BootstrapContext.active = context
	for node in [stock_index, farm, bridge, actor, store, next_store]: root.add_child(node)
	bridge.set("_farm", farm)
	stock_index.bind_world_container(store)
	stock_index.bind_world_container(next_store)
	store.inventory.add_entry_with_contents(hoe, 1, {}, {"durability": 37}, "loan.exact.hoe")
	var result: String = bridge.call("_assign_cell_to_actor", actor, "farm:test", "0:0", true)
	var actor_key := actor.get_instance_id()
	_expect(result.is_empty() and str((bridge.get("_assignments") as Dictionary).get(actor_key, {}).get("stage", "")) == "work", "Town farmer checks out a reserved tool and travels directly to field work")
	_expect(store.inventory.count_item(hoe) == 0 and actor.equipment.equipped == hoe and actor.equipment.stack_id == "loan.exact.hoe" and actor.inventory.count_item(sword) == 1, "checkout equips exact hoe and safely stows prior sword")
	_expect((bridge.get("_borrowed_tools") as Dictionary).has(actor_key), "loan retains its origin across farm cells")
	bridge.cancel_work_for_actor(actor)
	farm.required_tool_tag = "tool.scythe"
	var unavailable: String = bridge.call("_assign_cell_to_actor", actor, "farm:test", "0:0", true)
	_expect(unavailable.contains("town tool storage") and actor.equipment.stack_id == "loan.exact.hoe" and not bridge.has_active_work_for_actor(actor), "unavailable next tool does not invent a return assignment or discard current hoe")
	_expect(store.get_item_reservation_snapshot(actor).get("stack_id", "") == "loan.exact.hoe" and (bridge.get("_borrowed_tools") as Dictionary).has(actor_key), "unavailable replacement leaves origin loan and reservation intact")
	var scythe: ItemDefinition = load("res://features/inventory/resources/items/scythe.tres")
	next_store.inventory.add_entry_with_contents(scythe, 1, {}, {"durability": 19}, "loan.exact.scythe")
	var switch_result: String = bridge.call("_assign_cell_to_actor", actor, "farm:test", "0:0", true)
	_expect(switch_result.is_empty() and str((bridge.get("_assignments") as Dictionary).get(actor_key, {}).get("stage", "")) == "return_tool", "available next tool starts the physical origin return")
	_expect(next_store.get_item_reservation_snapshot(actor).is_empty() and next_store.inventory.count_item(scythe) == 1, "next tool remains unreserved and unconsumed during return trip")
	actor.global_position = actor.move_target
	bridge.call("_process_assignment", actor_key, 0.01)
	_expect(store.inventory.count_item(hoe) == 1 and str(store.inventory.entries[0].stack_id) == "loan.exact.hoe" and store.inventory.entries[0].metadata == {"durability": 37}, "physical return restores exact hoe and its metadata once")
	_expect(actor.equipment.equipped == sword and actor.equipment.stack_id == "town.worker.sword" and actor.inventory.count_item(sword) == 0, "return restores the exact prior sword")
	_expect(not (bridge.get("_borrowed_tools") as Dictionary).has(actor_key) and store.get_item_reservation_snapshot(actor).is_empty(), "completed return closes loan and origin reservation")
	var reacquire: String = bridge.call("_assign_cell_to_actor", actor, "farm:test", "0:0", true)
	_expect(reacquire.is_empty() and actor.equipment.equipped == scythe and actor.equipment.stack_id == "loan.exact.scythe" and next_store.inventory.count_item(scythe) == 0, "current work reacquires and equips exact next tool after return")
	bridge.cancel_work_for_actor(actor)
	var offers: Array = bridge.call("get_available_work_offers", "town")
	_expect(offers.size() == 1 and str(offers[0].get("action", "")) == "return_borrowed_tool", "idle worker publishes its one exact return offer")
	if offers.size() == 1:
		_expect(str(bridge.call("accept_work_offer", offers[0], actor)) == "Worker assigned to return tool", "worker accepts origin return offer")
		actor.global_position = actor.move_target
		bridge.call("_process_assignment", actor_key, 0.01)
	_expect(next_store.inventory.count_item(scythe) == 1 and str(next_store.inventory.entries[0].stack_id) == "loan.exact.scythe" and next_store.inventory.entries[0].metadata == {"durability": 19}, "second exact-stack return conserves scythe identity and metadata")
	farm.required_tool_tag = "tool.hoe"
	_expect(str(bridge.call("_assign_cell_to_actor", actor, "farm:test", "0:0", true)).is_empty() and store.inventory.count_item(hoe) == 0, "LOD fixture starts with a checked-out hoe")
	bridge.prepare_actor_for_derealization(actor)
	_expect(store.inventory.count_item(hoe) == 1 and not bridge.has_active_work_for_actor(actor) and not (bridge.get("_borrowed_tools") as Dictionary).has(actor_key), "LOD settles loan and work before projection destruction")
	actor.free()
	actor = FakeActor.new()
	actor.set_meta("settlement_id", "town")
	root.add_child(actor)
	_expect(str(bridge.call("_assign_cell_to_actor", actor, "farm:test", "0:0", true)).is_empty() and actor.equipment.stack_id == "loan.exact.hoe", "new projection with same durable worker ID reacquires the returned exact hoe")
	bridge.prepare_actor_for_derealization(actor)
	_expect(store.inventory.count_item(hoe) == 1 and next_store.inventory.count_item(scythe) == 1 and actor.inventory.count_item(hoe) == 0, "final cleanup conserves both real store tools")
	BootstrapContext.active = null
	for node in [stock_index, next_store, store, actor, bridge, farm]: node.queue_free()
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
