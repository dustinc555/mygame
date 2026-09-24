extends GutTest

const SWORD = preload("res://features/inventory/resources/items/steel_sword.tres")
const SESSION = preload("res://features/inventory/bridge/inventory_trade_session.gd")

func test_owned_equipping_during_trade_preserves_durable_stack_metadata() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var context := BootstrapContext.new(root)
	var bridge := GecsWorldController.new()
	root.add_child(bridge)
	context.register(GecsWorldController.SERVICE_ID, bridge)
	bridge.initialize(context)
	var actor := HumanoidCharacter.new()
	actor.stable_id = "test.trade.equipment"
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(actor)
	bridge.register_actor(actor)
	assert_true(actor.inventory.add_entry_with_contents(SWORD, 1, {}, {"quality": 0.37, "maker": "retained"}, "test.exact.sword"))
	var session = SESSION.new(actor.inventory, InventoryData.new(), func(_side, _entry): return 1)
	session.bind_equipment(actor.get_equipment(), bridge.get_item_stack)
	assert_eq(session.equip_owned(actor.inventory.entries[0], "weapon"), "")
	var saved: Dictionary = bridge.get_item_stack("test.exact.sword")
	assert_eq(saved.get("metadata"), {"quality": 0.37, "maker": "retained"})
	assert_eq(saved.get("location_kind"), "equipment")
	assert_eq(session.propose(0, session.equipment_entry("weapon"), 0, Vector2i(3, 0)), "")
	saved = bridge.get_item_stack("test.exact.sword")
	assert_eq(saved.get("metadata"), {"quality": 0.37, "maker": "retained"})
	assert_eq(saved.get("location_kind"), "inventory")
	bridge.unregister_actor(actor)
