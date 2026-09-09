extends SceneTree
## Focused regression for borrowed hoes starving watering behind expansion work.
const CAN = preload("res://features/inventory/resources/items/watering_can.tres")
const HOE = preload("res://features/inventory/resources/items/hoe.tres")
class Farm:
	extends Node
	func get_cell_work(_plot: String, _cell: String) -> Dictionary:
		return {"plot_id": "field", "cell_key": "wet", "settlement_id": "town", "owner_faction_id": "Player", "action": "water", "required_tool_tag": "tool.water_container", "required_tool_label": "watering can", "world_position": Vector3.ONE}
class Actor:
	extends Node3D
	var faction_name := "Player"
	var inventory := InventoryData.new(8, 8, 0.0, false)
	var target := Vector3.ZERO
	func get_inventory(): return inventory
	func is_player_party_member() -> bool: return false
	func set_move_target(value: Vector3, _issued := false) -> void: target = value
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
	for failure in failures: push_error(failure)
	print("FARM_TOOL_SWITCH_OK" if failures.is_empty() else "FARM_TOOL_SWITCH_FAILED")
	quit(0 if failures.is_empty() else 1)
func _expect(value: bool, message: String) -> void:
	if not value: failures.append(message)
