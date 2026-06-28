extends SceneTree

const BANDAGE := preload("res://features/inventory/resources/items/bandage.tres")
const WORLD_ITEM_SCENE := preload("res://features/world/projection/items/world_item.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_bandage_resource()
	_validate_bandage_uses()
	_validate_bandage_world_drop_state()
	if _failures.is_empty():
		print("BANDAGE_INVENTORY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("BANDAGE_INVENTORY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_bandage_resource() -> void:
	if BANDAGE == null:
		_fail("Bandage resource should load")
		return
	if str(BANDAGE.display_name) != "Bandage":
		_fail("Bandage should have a readable display name")
	if BANDAGE.grid_size != Vector2i(2, 2):
		_fail("Bandage should occupy a 2x2 inventory footprint")
	if int(BANDAGE.max_stack) != 1:
		_fail("Bandage should not stack")
	if int(BANDAGE.bandage_max_uses) != 5:
		_fail("Bandage should have five uses")
	if BANDAGE.icon == null:
		_fail("Bandage should have an inventory icon")
	if BANDAGE.world_scene == null:
		_fail("Bandage should have a Meshy world scene")


func _validate_bandage_uses() -> void:
	var inventory := InventoryData.new(4, 4, 100.0, false)
	if not inventory.add_item_count(BANDAGE, 2):
		_fail("Inventory should accept two non-stacking bandages")
		return
	if inventory.entries.size() != 2:
		_fail("Two bandages should occupy separate inventory entries")
		return
	var entry = inventory.entries[0]
	if inventory.get_entry_bandage_uses(entry) != 5:
		_fail("Fresh bandage entry should start with five uses")
	if not inventory.consume_bandage_entry_use(entry):
		_fail("Consuming a bandage use should succeed")
	if inventory.get_entry_bandage_uses(entry) != 4:
		_fail("Bandage should retain four uses after one application")
	var target := InventoryData.new(4, 4, 100.0, false)
	if not inventory.move_entry_to_inventory(entry, target, Vector2i.ZERO):
		_fail("Partially used bandage should transfer between inventories")
		return
	var moved_entry = target.entries[0]
	if target.get_entry_bandage_uses(moved_entry) != 4:
		_fail("Partially used bandage should preserve uses after transfer")
	for _index in range(4):
		if target.entries.is_empty():
			_fail("Bandage should remain until its fifth use")
			return
		target.consume_bandage_entry_use(target.entries[0])
	if not target.entries.is_empty():
		_fail("Bandage entry should be removed after its final use")


func _validate_bandage_world_drop_state() -> void:
	var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	if world_item == null:
		_fail("World item scene should instantiate")
		return
	world_item.setup(BANDAGE, 1, {InventoryData.ENTRY_BANDAGE_USES_KEY: 2})
	if int(world_item.contained_item_counts.get(InventoryData.ENTRY_BANDAGE_USES_KEY, 0)) != 2:
		_fail("World item should preserve partial bandage uses")
	if not bool(world_item.call("_item_has_contained_counts")):
		_fail("World pickup should restore entries that carry bandage use state")
	world_item.queue_free()


func _fail(message: String) -> void:
	_failures.append(message)
