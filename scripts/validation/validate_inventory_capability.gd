extends SceneTree

const WORLD_ACTOR_SCRIPT = preload("res://scripts/actors/world_actor.gd")
const INVENTORY_STOCK_SCRIPT = preload("res://scripts/items/inventory_stock.gd")
const BANDAGE = preload("res://resources/items/bandage.tres")
const CINDER_FLASK = preload("res://resources/items/cinder_flask.tres")

var _failures: Array[String] = []
var _inventory_changed_count := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_validate_inventory_capability_registration()
	_validate_starting_inventory_seed()
	_validate_work_inventory_override()
	_validate_inventory_change_signal()
	if _failures.is_empty():
		print("INVENTORY_CAPABILITY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("INVENTORY_CAPABILITY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_inventory_capability_registration() -> void:
	var actor := _make_actor()
	var capability = actor.get_actor_capability(&"inventory")
	if capability == null:
		_fail("Expected WorldActor to register InventoryCapability")
	elif not capability.has_method("initialize_from_actor"):
		_fail("Expected InventoryCapability to expose initialize_from_actor")
	actor.free()


func _validate_starting_inventory_seed() -> void:
	var actor := _make_actor(false)
	actor.inventory_columns = 4
	actor.inventory_rows = 4
	actor.starting_items = [_stock(BANDAGE, 1), _stock(CINDER_FLASK, 1)]
	actor.call("_setup_inventory_capability")
	if actor.inventory == null:
		_fail("Expected inventory setup to create actor inventory")
		actor.free()
		return
	if actor.inventory.count_item(BANDAGE) != 1:
		_fail("Expected starting bandage to be seeded")
	if actor.inventory.count_item(CINDER_FLASK) != 1:
		_fail("Expected starting cinder flask to be seeded")
	actor.free()


func _validate_work_inventory_override() -> void:
	var actor := _make_actor()
	var work_inventory := InventoryData.new(2, 2, 0.0, false)
	actor.call("_set_work_inventory_override", work_inventory)
	if actor.get_inventory_for_display() != work_inventory:
		_fail("Expected work inventory to drive display inventory")
	if not actor.is_displaying_work_inventory():
		_fail("Expected actor to report work inventory display state")
	if actor.can_transfer_display_inventory_to(null):
		_fail("Expected work inventory transfer-out to be locked")
	actor.call("_set_work_inventory_override", null)
	if actor.get_inventory_for_display() != actor.inventory:
		_fail("Expected display inventory to return to actor inventory")
	if actor.is_displaying_work_inventory():
		_fail("Expected work inventory display state to clear")
	actor.free()


func _validate_inventory_change_signal() -> void:
	var actor := _make_actor()
	_inventory_changed_count = 0
	actor.inventory_changed.connect(_on_inventory_changed)
	actor.inventory.add_item_count(BANDAGE, 1)
	if _inventory_changed_count != 1:
		_fail("Expected inventory changed signal through capability, got %d" % _inventory_changed_count)
	actor.free()


func _make_actor(setup_inventory := true) -> WorldActor:
	var actor := WORLD_ACTOR_SCRIPT.new() as WorldActor
	actor.call("_setup_actor_capabilities")
	if setup_inventory:
		actor.call("_setup_inventory_capability")
	return actor


func _stock(definition: ItemDefinition, quantity: int) -> InventoryStock:
	var stock := INVENTORY_STOCK_SCRIPT.new() as InventoryStock
	stock.item_definition = definition
	stock.quantity = quantity
	return stock


func _on_inventory_changed() -> void:
	_inventory_changed_count += 1


func _fail(message: String) -> void:
	_failures.append(message)
