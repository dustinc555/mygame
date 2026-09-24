extends GutTest

func _item(label: String, footprint: Vector2i) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.display_name = label
	item.grid_size = footprint
	return item

func test_sort_keeps_room_for_full_height_weapon_and_preserves_contents() -> void:
	var bag := InventoryData.new()
	bag.columns = 10
	bag.rows = 4
	var sword = bag.create_entry(_item("Sword", Vector2i(1, 4)), Vector2i(9, 0))
	bag.entries.append(sword)
	for index in range(7):
		bag.entries.append(bag.create_entry(_item("Bread", Vector2i(2, 2)), Vector2i((index % 4) * 2, (index / 4) * 2)))
	var pouch = bag.entries[1]
	pouch.contained_item_counts = {"silver": 17}
	pouch.metadata = {"owner": "mira"}
	var original := bag.entries.duplicate()
	var pouch_id: String = pouch.stack_id
	watch_signals(bag)
	assert_true(bag.auto_sort(), "Equal-area squares must not strand a full-height sword")
	assert_eq(bag.entries.size(), original.size())
	for entry in original:
		assert_true(bag.entries.has(entry), "Keep the real entry, not a replacement stack")
		assert_true(bag.can_place_item(entry.definition, entry.grid_position, entry), "Every sorted footprint is in bounds and disjoint")
	assert_eq(pouch.stack_id, pouch_id)
	assert_eq(pouch.contained_item_counts, {"silver": 17})
	assert_eq(pouch.metadata, {"owner": "mira"})
	assert_signal_emit_count(bag, "changed", 1)
	var positions: Array = bag.entries.map(func(entry): return entry.grid_position)
	assert_true(bag.auto_sort())
	assert_eq(bag.entries.map(func(entry): return entry.grid_position), positions, "Repeated sorting is stable")

func test_failed_sort_leaves_original_order_and_positions_untouched() -> void:
	var bag := InventoryData.new()
	bag.columns = 2
	bag.rows = 2
	# Simulate a capacity reduction: neither losing nor partly moving entries is safe.
	var small = bag.create_entry(_item("Small", Vector2i.ONE), Vector2i(1, 1), 3)
	var large = bag.create_entry(_item("Large", Vector2i(2, 2)), Vector2i(2, 0))
	bag.entries.assign([small, large])
	watch_signals(bag)
	assert_false(bag.auto_sort())
	assert_eq(bag.entries, [small, large])
	assert_eq(small.grid_position, Vector2i(1, 1))
	assert_eq(large.grid_position, Vector2i(2, 0))
	assert_eq(small.count, 3)
	assert_signal_not_emitted(bag, "changed")
