extends GutTest

const BAG = preload("res://features/inventory/resources/items/medium_leather_bag.tres")
const FOOD = preload("res://features/inventory/resources/items/food.tres")
const SESSION = preload("res://features/inventory/bridge/inventory_trade_session.gd")

func test_bag_contents_are_separate_and_survive_serialized_handover() -> void:
	var carrier := InventoryData.new()
	assert_true(carrier.add_item(BAG))
	var bag = carrier.entries[0]
	assert_true(carrier.has_method("create_item_storage"), "Items need their own storage inventory")
	if not carrier.has_method("create_item_storage"):
		return
	var storage: InventoryData = carrier.call("create_item_storage", bag.definition, bag.metadata, bag.stack_id)
	assert_eq(Vector2i(storage.columns, storage.rows), Vector2i(10, 10))
	assert_true(storage.add_entry_with_contents(FOOD, 2, {}, {"stolen": true}, "bag-food"))
	bag.metadata["item_storage"] = storage.call("serialize_contents")
	assert_eq(carrier.count_item(FOOD), 0, "Personal slots must not become bag slots")
	var recipient := InventoryData.new()
	assert_true(carrier.move_entry_to_inventory(bag, recipient, Vector2i.ZERO))
	var received = recipient.entries[0]
	var restored: InventoryData = recipient.call("create_item_storage", received.definition, received.metadata, received.stack_id)
	assert_eq(restored.count_item(FOOD), 2)
	assert_eq(restored.entries[0].stack_id, "bag-food")
	assert_true(restored.entries[0].metadata.stolen)
	assert_almost_eq(recipient.get_total_weight(), BAG.unit_weight + FOOD.unit_weight * 2, 0.0001)


func test_trade_buys_directly_into_separate_bag_using_personal_purse() -> void:
	var personal := InventoryData.new()
	var merchant := InventoryData.new()
	var bag := InventoryData.create_item_storage(BAG, {}, "trade-bag")
	assert_true(personal.add_item_count(InventoryData.SILVER_ITEM, 10))
	assert_true(merchant.add_entry_with_contents(FOOD, 1, {}, {"quality": 0.6}, "stock-food"))
	var session = SESSION.new(personal, merchant, func(_side, _entry): return 3)
	assert_true(session.has_method("add_inventory"), "Trade needs distinct storage destinations")
	if not session.has_method("add_inventory"):
		return
	var side: int = session.call("add_inventory", bag)
	assert_eq(session.propose(1, merchant.entries[0], side, Vector2i.ZERO), "")
	assert_eq(bag.count_item(FOOD), 0, "Offers are not owned goods")
	session.reset()
	assert_eq(merchant.count_item(FOOD), 1)
	assert_eq(session.propose(1, merchant.entries[0], side, Vector2i.ZERO), "")
	assert_eq(session.commit(), "")
	assert_eq(personal.count_item(FOOD), 0)
	assert_eq(bag.count_item(FOOD), 1)
	assert_eq(bag.entries[0].stack_id, "stock-food")
	assert_eq(bag.entries[0].metadata, {"quality": 0.6})
	assert_eq(personal.count_item(InventoryData.SILVER_ITEM), 7)
	assert_eq(merchant.count_item(InventoryData.SILVER_ITEM), 3)


func test_personal_to_bag_rearrangement_does_not_create_a_sale_or_clear_pending_purchase() -> void:
	var personal := InventoryData.new()
	var merchant := InventoryData.new()
	var bag := InventoryData.create_item_storage(BAG, {}, "trade-bag")
	assert_true(personal.add_item(FOOD))
	assert_true(personal.add_item_count(InventoryData.SILVER_ITEM, 10))
	assert_true(merchant.add_item(FOOD))
	var session = SESSION.new(personal, merchant, func(_side, _entry): return 3)
	var side: int = session.add_inventory(bag)
	assert_eq(session.propose(1, merchant.entries[0], 0, Vector2i(5, 0)), "")
	var own_food = personal.entries[0]
	assert_eq(session.propose(0, own_food, side, Vector2i.ZERO), "")
	assert_eq(bag.count_item(FOOD), 1)
	assert_eq(personal.count_item(FOOD), 0)
	assert_eq(session.offers.size(), 1)
	assert_eq(session.net_silver(), 3)
	assert_true(session.is_current())
	session.reset()
	assert_eq(bag.count_item(FOOD), 1, "Reset is not an undo for normal inventory management")


func test_unknown_saved_item_refuses_open_without_discarding_contents() -> void:
	var metadata := {"item_storage": {"entries": [{"item_definition_path": "res://missing_saved_item.tres", "stack_id": "unknown", "count": 1}]}}
	var before := metadata.duplicate(true)
	assert_null(InventoryData.create_item_storage(BAG, metadata, "bag"))
	assert_eq(metadata, before)
