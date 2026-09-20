extends SceneTree
## Focused regression for borrowed hoes starving watering behind expansion work.
const CAN = preload("res://features/inventory/resources/items/watering_can.tres")
const HOE = preload("res://features/inventory/resources/items/hoe.tres")
class Farm:
	extends Node
	var cancelled: Array[String] = []
	func get_cell_work(_plot: String, cell: String) -> Dictionary:
		var watering := cell == "wet"
		return {"plot_id": "field", "cell_key": cell, "request_revision": 7, "settlement_id": "town", "owner_faction_id": "Player", "action": "water" if watering else "till", "required_tool_tag": "tool.water_container" if watering else "tool.hoe", "required_tool_label": "watering can" if watering else "hoe", "world_position": Vector3.ONE if watering else Vector3(9, 0, 0)}
	func can_actor_command_plot(_actor: Node, _plot: String) -> bool: return true
	func cancel_cell_operation(_plot: String, cell: String, _revision: int, _actor: String) -> void: cancelled.append(cell)
class Equipment:
	extends RefCounted
	var definition: ItemDefinition = HOE
	var stack_id := "equipped.hoe"
	var allow_equip := true
	func get_equipped_item(_slot: String): return definition
	func get_equipped_stack_id(_slot: String) -> String: return stack_id
	func can_equip_item_to_slot(_item, _slot: String) -> bool: return allow_equip
	func equip_item_to_slot(item, _slot: String, id := ""):
		definition = item
		stack_id = id
	func unequip_item_from_slot(_slot: String): definition = null
class Actor:
	extends Node3D
	var faction_name := "Player"
	var inventory := InventoryData.new(8, 8, 0.0, false)
	var equipment := Equipment.new()
	var target := Vector3.ZERO
	var visual_active := false
	func get_inventory(): return inventory
	func get_equipment(): return equipment
	func is_player_party_member() -> bool: return false
	func set_move_target(value: Vector3, _issued := false) -> void: target = value
	func set_farming_work_visual(active: bool, _action: String, _target: Vector3, _progress: float) -> void: visual_active = active
class Store:
	extends Node3D
	var is_locked := false
	var reserved := 0
	func get_owner_faction_name() -> String: return "Player"
	func find_reservable_tool(_tag: String, _actor: Node): return CAN
	func reserve_item_for_actor(_definition, _actor: Node, _count: int) -> bool:
		reserved += 1
		return true
	func release_item_reservation(_actor_key: int) -> void: reserved -= 1
	func get_interaction_position(_actor: Node) -> Vector3: return Vector3(5, 0, 0)
class Bridge:
	extends FarmWorkBridge
	var store: Node
	func _tool_container_candidates(_town: String) -> Array[Node]: return [store]
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var bridge := Bridge.new()
	var farm := Farm.new()
	var actor := Actor.new()
	var store := Store.new()
	for node in [bridge, farm, actor, store]: root.add_child(node)
	bridge._farm = farm
	bridge.store = store
	actor.set_meta("settlement_id", "town")
	actor.inventory.add_item_count(HOE, 1)
	var key := actor.get_instance_id()
	bridge._borrowed_tools[key] = {"actor_ref": weakref(actor), "store_ref": weakref(store), "definition": HOE, "stack_id": str(actor.inventory.entries[0].stack_id), "settlement_id": "town", "owner_faction_id": "Player"}
	var result := bridge._assign_cell_to_actor(actor, "field", "wet", true)
	_expect(result.is_empty() and str(bridge._assignments.get(key, {}).get("stage", "")) == "return_tool", "required can starts physical hoe return instead of rejecting watering")
	_expect(actor.target == store.get_interaction_position(actor) and store.reserved == 0, "switch travels to origin without leaking a reservation on the next tool")
	var wet := bridge._append_cached_offer(farm.get_cell_work("field", "wet"))
	var till := bridge._append_cached_offer({"plot_id": "field", "cell_key": "new", "action": "till"})
	_expect(float(wet.urgency) > float(till.urgency), "watering existing plants outranks expanding tilled ground")
	bridge._borrowed_tools.clear()
	bridge._assignments.clear()
	for node in [bridge, farm, actor, store]: node.free()
	_validate_rejected_replacement()
	for failure in failures: push_error(failure)
	print("FARM_TOOL_SWITCH_OK" if failures.is_empty() else "FARM_TOOL_SWITCH_FAILED")
	quit(0 if failures.is_empty() else 1)
func _expect(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _validate_rejected_replacement() -> void:
	var bridge := FarmWorkBridge.new()
	var farm := Farm.new()
	var actor := Actor.new()
	var claimant := Actor.new()
	for node in [bridge, farm, actor, claimant]: root.add_child(node)
	bridge._farm = farm
	_expect(bridge.assign_cell("field", "old", [actor]) == "1 worker assigned", "rejection fixture starts valid manual work")
	_expect(bridge.assign_cell("field", "claimed", [claimant]) == "1 worker assigned", "replacement target has a distinct active claimant")
	actor.visual_active = true
	var key := actor.get_instance_id()
	var old_assignment: Dictionary = bridge._assignments[key].duplicate(true)
	var old_target := actor.target
	_expect(bridge.assign_cell("field", "wet", [actor]).begins_with("Cannot"), "missing required can rejects replacement")
	_expect(bridge._assignments.get(key, {}) == old_assignment and actor.target == old_target and actor.visual_active and farm.cancelled.is_empty(), "missing-tool rejection preserves active work, movement, visuals and durable request")
	# Equipment compatibility is a later rejection, after finding the tool.
	actor.inventory.add_item_count(CAN, 1)
	actor.equipment.allow_equip = false
	_expect(bridge.assign_cell("field", "wet", [actor]) == "Cannot equip watering can", "incompatible slot rejects a carried replacement")
	_expect(bridge._assignments.get(key, {}) == old_assignment and actor.inventory.count_item(CAN) == 1 and actor.equipment.definition == HOE and farm.cancelled.is_empty(), "failed equip cannot cancel old work or consume either tool")
	actor.equipment.allow_equip = true
	actor.inventory.use_weight = true
	actor.inventory.max_weight = 2.0
	_expect(bridge.assign_cell("field", "wet", [actor]) == "Cannot equip watering can", "heavier replaced hoe cannot fit the worker's weight allowance")
	_expect(bridge._assignments.get(key, {}) == old_assignment and actor.inventory.count_item(CAN) == 1 and actor.equipment.definition == HOE and farm.cancelled.is_empty(), "no stow capacity preserves active work and exact tool locations")
	# A claimant is protected even when the requesting actor owns another job.
	actor.equipment.definition = null
	_expect(bridge.assign_cell("field", "claimed", [actor]).begins_with("Cannot"), "missing hoe rejects occupied-cell replacement")
	_expect(bridge._assignments.get(key, {}) == old_assignment and bridge.has_active_work_for_actor(claimant) and farm.cancelled.is_empty(), "rejected takeover preserves both workers and requests")
	bridge._assignments.clear()
	for node in [bridge, farm, actor, claimant]: node.free()
