extends GutTest
## Fast counterparts to inventory, merchant and farming transaction validators.
## Use test-owned definitions so ordinary item balancing cannot break these rules.

var item: ItemDefinition
var source: InventoryData
var destination: InventoryData


func before_each() -> void:
	item = ItemDefinition.new()
	item.item_id = "unit.goods"
	item.grid_size = Vector2i.ONE
	item.max_stack = 5
	item.unit_weight = 1.0
	source = InventoryData.new(2, 1, 0.0, false)
	destination = InventoryData.new(2, 1, 0.0, false)
	source.configure_stack_allocator("unit.source")
	destination.configure_stack_allocator("unit.destination")


func test_count_transfer_publishes_only_the_complete_conserved_balance() -> void:
	assert_true(source.add_item_count(item, 5))
	assert_true(destination.add_item_count(item, 2))
	var observed: Array = []
	source.changed.connect(func(): observed.append([source.count_item(item), destination.count_item(item)]))
	destination.changed.connect(func(): observed.append([source.count_item(item), destination.count_item(item)]))

	assert_true(source.transfer_item_count_to(item, 3, destination))
	assert_eq(source.count_item(item), 2)
	assert_eq(destination.count_item(item), 5)
	assert_eq_deep(observed, [[2, 5], [2, 5]])


func test_full_destination_rolls_back_source_identity_and_emits_nothing() -> void:
	destination.columns = 1
	assert_true(source.add_item_count(item, 5))
	assert_true(destination.add_item_count(item, 4))
	var original = source.entries[0]
	var original_id: String = original.stack_id
	var sequence := source.next_stack_sequence
	var destination_sequence := destination.next_stack_sequence
	watch_signals(source)
	watch_signals(destination)

	assert_false(source.transfer_item_count_to(item, 3, destination))
	assert_eq(source.count_item(item), 5)
	assert_eq(destination.count_item(item), 4)
	assert_eq(source.entries[0], original, "Rollback must keep the live entry used by callers")
	assert_eq(original.stack_id, original_id)
	assert_eq(source.next_stack_sequence, sequence)
	assert_eq(destination.next_stack_sequence, destination_sequence)
	assert_signal_not_emitted(source, "changed")
	assert_signal_not_emitted(destination, "changed")


func test_exact_stack_move_keeps_identity_and_independent_metadata() -> void:
	assert_true(source.add_entry_with_contents(item, 1, {}, {"owner": "other"}, "stack:untouched"))
	var metadata := {"stolen": true, "provenance": {"owner": "town"}}
	assert_true(source.add_entry_with_contents(item, 2, {}, metadata, "stack:chosen"))
	var chosen = source.entries[1]

	assert_true(source.move_entry_to_inventory(chosen, destination, Vector2i.ZERO))
	assert_eq(source.entries.size(), 1)
	assert_eq(source.entries[0].stack_id, "stack:untouched")
	assert_eq(source.count_item(item), 1)
	assert_eq(destination.entries.size(), 1)
	assert_eq(destination.entries[0].stack_id, "stack:chosen")
	assert_eq(destination.count_item(item), 2)
	assert_eq_deep(destination.entries[0].metadata, metadata)
	chosen.metadata.provenance.owner = "stale-reference"
	assert_eq(destination.entries[0].metadata.provenance.owner, "town", "Moved metadata must not alias the old entry")


func test_recipe_refusal_preserves_input_then_consuming_it_frees_output_space() -> void:
	source.columns = 1
	var output := ItemDefinition.new()
	output.item_id = "unit.output"
	output.max_stack = 5
	assert_true(source.add_item_count(item, 2))
	var original = source.entries[0]
	watch_signals(source)

	assert_false(source.exchange_item_counts(item, 1, output, 2))
	assert_eq(source.entries[0], original)
	assert_eq(source.count_item(item), 2)
	assert_eq(source.count_item(output), 0)
	assert_signal_not_emitted(source, "changed")

	assert_true(source.exchange_item_counts(item, 2, output, 2))
	assert_eq(source.count_item(item), 0)
	assert_eq(source.count_item(output), 2)
	assert_signal_emit_count(source, "changed", 1)
