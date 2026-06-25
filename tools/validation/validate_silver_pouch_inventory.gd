extends SceneTree

const SILVER_ITEM := preload("res://resources/items/silver.tres")
const SILVER_POUCH_ITEM := preload("res://resources/items/silver_pouch.tres")
const WORLD_ITEM_SCENE := preload("res://src/world/projection/items/world_item.tscn")
const PARTY_INVENTORY_CONTROLLER_SCRIPT := preload("res://src/inventory/bridge/party_inventory_controller.gd")

var _failures: Array[String] = []


class InventoryOwner:
	extends Node3D

	var inventory: InventoryData = InventoryData.new(10, 6, 0.0, false)

	func get_inventory_world_position() -> Vector3:
		return global_position

	func is_player_party_member() -> bool:
		return true


class CursorRecorder:
	extends RefCounted

	var kept := false
	var consumed := false
	var replaced := false
	var replacement_contents: Dictionary = {}

	func keep_drag(_drag_id: int) -> void:
		kept = true

	func consume_drag(_drag_id: int) -> void:
		consumed = true

	func replace_drag_item(_drag_id: int, _owner, _definition: ItemDefinition, _count := 1, item_contained_item_counts: Dictionary = {}) -> void:
		replaced = true
		replacement_contents = item_contained_item_counts.duplicate(true)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_items()
	_validate_auto_pouches_and_payments()
	_validate_player_extract_actions()
	_validate_drag_deposits()
	_validate_world_pickup_preserves_pouch_contents()
	if _failures.is_empty():
		print("SILVER_POUCH_INVENTORY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SILVER_POUCH_INVENTORY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_items() -> void:
	if SILVER_ITEM.display_name != "Silver Coin":
		_fail("Silver should be the individual Silver Coin item")
	if SILVER_ITEM.icon == null:
		_fail("Silver Coin should have an SVG icon")
	if SILVER_POUCH_ITEM.grid_size != Vector2i(2, 2):
		_fail("Silver Pouch should occupy a 2x2 inventory footprint")
	if int(SILVER_POUCH_ITEM.currency_container_capacity) != 250:
		_fail("Silver Pouch should store 250 coins")
	if bool(SILVER_POUCH_ITEM.sellable):
		_fail("Silver Pouch should be currency storage, not normal merchandise")
	if SILVER_POUCH_ITEM.icon == null:
		_fail("Silver Pouch should have an SVG icon")
	if SILVER_POUCH_ITEM.world_scene == null:
		_fail("Silver Pouch should use the Meshy pouch wrapper as its world scene")
	if float(SILVER_POUCH_ITEM.world_visual_height_meters) <= 0.0:
		_fail("Silver Pouch should normalize its dropped world visual height")


func _validate_auto_pouches_and_payments() -> void:
	var inventory := InventoryData.new(10, 6, 0.0, false)
	if not inventory.add_item_count(SILVER_ITEM, 10):
		_fail("Adding starting silver should succeed")
		return
	if inventory.entries.size() != 1 or not inventory.is_entry_currency_container(inventory.entries[0], SILVER_ITEM):
		_fail("Starting silver should auto-pack into a silver pouch")
	if inventory.count_item(SILVER_ITEM) != 10:
		_fail("Silver count should include coins inside pouches")
	if not inventory.add_item_count(SILVER_ITEM, 300):
		_fail("Adding more silver should create/fill pouches")
	if inventory.count_item(SILVER_ITEM) != 310:
		_fail("Pouch-aware silver count should total all pouch contents")
	if _pouch_count(inventory) != 2:
		_fail("310 silver should fit in two silver pouches")
	if not inventory.remove_item_count(SILVER_ITEM, 65):
		_fail("Payment should remove silver from pouch contents")
	if inventory.count_item(SILVER_ITEM) != 245:
		_fail("Payment should leave the expected pouch-aware silver total")


func _validate_player_extract_actions() -> void:
	var owner := InventoryOwner.new()
	root.add_child(owner)
	owner.inventory.add_item_count(SILVER_ITEM, 80)
	var pouch = _first_pouch(owner.inventory)
	var controller: Node = PARTY_INVENTORY_CONTROLLER_SCRIPT.new()
	root.add_child(controller)
	controller.call("_take_silver_from_pouch", owner, pouch, "take_silver_10")
	if owner.inventory.get_entry_contained_item_count(pouch, SILVER_ITEM) != 70:
		_fail("Take 10 should remove 10 coins from the pouch")
	if _loose_silver_count(owner.inventory) != 10:
		_fail("Take 10 should create loose silver coins, not repack them")
	controller.call("_take_silver_from_pouch", owner, pouch, "take_silver_half")
	if owner.inventory.get_entry_contained_item_count(pouch, SILVER_ITEM) != 35:
		_fail("Take 1/2 should remove half of the pouch's current coins")
	controller.call("_take_silver_from_pouch", owner, pouch, "take_silver_quarter")
	if owner.inventory.get_entry_contained_item_count(pouch, SILVER_ITEM) != 27:
		_fail("Take 1/4 should remove one quarter of the pouch's current coins")
	owner.queue_free()
	controller.queue_free()


func _validate_drag_deposits() -> void:
	var source := InventoryOwner.new()
	var target := InventoryOwner.new()
	root.add_child(source)
	root.add_child(target)
	var controller = PARTY_INVENTORY_CONTROLLER_SCRIPT.new()
	var cursor_layer := Control.new()
	root.add_child(cursor_layer)
	root.add_child(controller)
	controller.set("inventory_window_layer", cursor_layer)

	source.inventory.add_loose_item_count(SILVER_ITEM, 25)
	target.inventory.add_entry_with_contents(SILVER_POUCH_ITEM, 1, _silver_contents(240))
	var loose_entry = source.inventory.entries[0]
	var target_pouch = _first_pouch(target.inventory)
	controller.call("_try_deposit_entry_into_pouch", source, target, loose_entry, target_pouch.grid_position)
	if target.inventory.get_entry_contained_item_count(target_pouch, SILVER_ITEM) != 250:
		_fail("Dragging coins to a pouch should fill the target pouch")
	if source.inventory.count_item(SILVER_ITEM) != 15:
		_fail("Coin-to-pouch overflow should remain as loose silver in the source inventory")

	source.inventory.entries.clear()
	source.inventory.add_entry_with_contents(SILVER_POUCH_ITEM, 1, _silver_contents(80))
	target.inventory.set_entry_contained_item_count(target_pouch, SILVER_ITEM, 230)
	var source_pouch = _first_pouch(source.inventory)
	controller.call("_try_deposit_entry_into_pouch", source, target, source_pouch, target_pouch.grid_position)
	if target.inventory.get_entry_contained_item_count(target_pouch, SILVER_ITEM) != 250:
		_fail("Dragging pouch to pouch should merge contents into the target")
	if source.inventory.entries.size() != 0:
		_fail("Dragging pouch to pouch should lift the source pouch out of its inventory")
	var cursor = controller.get("cursor_item_drag_source")
	if cursor == null or int(cursor.get("contained_item_counts").get(_silver_key(), -1)) != 60:
		_fail("Pouch-to-pouch overflow should remain in the cursor pouch")

	source.inventory.entries.clear()
	target.inventory.entries.clear()
	source.inventory.add_entry_with_contents(SILVER_POUCH_ITEM, 1, _silver_contents(50))
	var blocked_pouch = _first_pouch(source.inventory)
	controller.call("_on_inventory_transfer_requested", source, target, blocked_pouch, Vector2i(0, 0))
	if source.inventory.entries.size() != 1:
		_fail("Dragging a pouch to another inventory's empty slot should keep it in the source inventory")
	if target.inventory.entries.size() != 0:
		_fail("Dragging a pouch to another inventory's empty slot should not move the pouch")

	var cursor_source := CursorRecorder.new()
	var cursor_data := {
		"cursor_item": true,
		"cursor_drag_id": 1,
		"cursor_source": cursor_source,
		"source_owner": source,
		"item_definition": SILVER_POUCH_ITEM,
		"count": 1,
		"contained_item_counts": _silver_contents(40),
	}
	controller.call("_on_cursor_item_place_requested", cursor_data, target, Vector2i(0, 0))
	if target.inventory.entries.size() != 0:
		_fail("Cursor pouch placement into another inventory's empty slot should be blocked")
	if not cursor_source.kept or cursor_source.consumed:
		_fail("Blocked cursor pouch placement should keep the pouch on the cursor")

	var full_source := InventoryOwner.new()
	var full_target := InventoryOwner.new()
	root.add_child(full_source)
	root.add_child(full_target)
	var full_controller = PARTY_INVENTORY_CONTROLLER_SCRIPT.new()
	var full_cursor_layer := Control.new()
	root.add_child(full_cursor_layer)
	root.add_child(full_controller)
	full_controller.set("inventory_window_layer", full_cursor_layer)
	full_source.inventory.add_entry_with_contents(SILVER_POUCH_ITEM, 1, _silver_contents(10))
	full_target.inventory.add_entry_with_contents(SILVER_POUCH_ITEM, 1, _silver_contents(240))
	var full_source_pouch = _first_pouch(full_source.inventory)
	var full_target_pouch = _first_pouch(full_target.inventory)
	full_controller.call("_try_deposit_entry_into_pouch", full_source, full_target, full_source_pouch, full_target_pouch.grid_position)
	if full_target.inventory.get_entry_contained_item_count(full_target_pouch, SILVER_ITEM) != 250:
		_fail("Fully merging pouch contents should fill the target pouch")
	if full_source.inventory.entries.size() != 0:
		_fail("Fully merging pouch contents should remove the source pouch from its inventory")
	var full_cursor = full_controller.get("cursor_item_drag_source")
	if full_cursor != null and bool(full_cursor.get("_has_item")):
		_fail("Fully merging pouch contents should not leave an empty pouch on the cursor")
	full_source.queue_free()
	full_target.queue_free()
	full_controller.queue_free()
	full_cursor_layer.queue_free()

	source.queue_free()
	target.queue_free()
	controller.queue_free()
	cursor_layer.queue_free()


func _validate_world_pickup_preserves_pouch_contents() -> void:
	var owner := InventoryOwner.new()
	root.add_child(owner)
	var world_item = WORLD_ITEM_SCENE.instantiate()
	root.add_child(world_item)
	world_item.setup(SILVER_POUCH_ITEM, 1, _silver_contents(123))
	if world_item.get_node_or_null("ModelRoot/SilverPouchWorld") == null:
		_fail("Dropped silver pouch should render the Meshy pouch wrapper instead of fallback geometry")
	if not world_item.try_pickup(owner):
		_fail("Picking up a dropped silver pouch should succeed")
		return
	var pouch = _first_pouch(owner.inventory)
	if pouch == null or owner.inventory.get_entry_contained_item_count(pouch, SILVER_ITEM) != 123:
		_fail("Dropped silver pouch should preserve contained coin count on pickup")
	owner.queue_free()


func _pouch_count(inventory: InventoryData) -> int:
	var count := 0
	for entry in inventory.entries:
		if inventory.is_entry_currency_container(entry, SILVER_ITEM):
			count += 1
	return count


func _first_pouch(inventory: InventoryData):
	for entry in inventory.entries:
		if inventory.is_entry_currency_container(entry, SILVER_ITEM):
			return entry
	return null


func _loose_silver_count(inventory: InventoryData) -> int:
	var count := 0
	for entry in inventory.entries:
		if entry.definition == SILVER_ITEM:
			count += entry.count
	return count


func _silver_contents(amount: int) -> Dictionary:
	return {_silver_key(): amount}


func _silver_key() -> String:
	return str(SILVER_ITEM.resource_path)


func _fail(message: String) -> void:
	_failures.append(message)
