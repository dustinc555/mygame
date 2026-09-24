extends GutTest

const WINDOW = preload("res://features/ui/projection/inventory_window.tscn")
const POUCH = preload("res://features/inventory/resources/items/silver_pouch.tres")
const SILVER = InventoryData.SILVER_ITEM

class Owner extends Node3D:
	signal inventory_changed
	var inventory := InventoryData.new()
	func get_inventory_for_display():
		return inventory
	func get_inventory_display_title():
		return "Owner"
	func shows_inventory_equipment():
		return false
	func shows_inventory_weight():
		return true
	func get_inventory_world_position():
		return global_position

var source: Owner
var target: Owner
var controller: PartyInventoryController
var source_window: InventoryWindow
var target_window: InventoryWindow
var viewport: SubViewport
var layer: Control
var entry

func before_each() -> void:
	source = Owner.new()
	target = Owner.new()
	add_child_autofree(source)
	add_child_autofree(target)
	controller = PartyInventoryController.new()
	add_child_autofree(controller)
	controller.set_process(false)
	assert_true(source.inventory.add_entry_with_contents(POUCH, 1, {SILVER.resource_path: 10}, {"origin": "Mira"}, "mira.pouch"))
	entry = source.inventory.entries[0]
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 900)
	add_child_autofree(viewport)
	layer = Control.new()
	viewport.add_child(layer)
	layer.size = Vector2(1280, 900)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_window = WINDOW.instantiate()
	target_window = WINDOW.instantiate()
	layer.add_child(source_window)
	layer.add_child(target_window)
	source.inventory.changed.connect(func(): source.inventory_changed.emit())
	target.inventory.changed.connect(func(): target.inventory_changed.emit())
	source_window.setup(source)
	target_window.setup(target)
	for window in [source_window, target_window]:
		window.transfer_requested.connect(controller._on_inventory_transfer_requested)
	controller.primary_character_window = source_window
	controller.secondary_inventory_window = target_window
	await get_tree().process_frame
	source_window.position = Vector2(20, 20)
	target_window.position = Vector2(500, 20)

func payload() -> Dictionary:
	return {"entry": entry, "source_inventory": source.inventory, "source_owner": source}

func test_pouch_moves_between_bags_with_contents_metadata_and_identity() -> void:
	var grid := target_window.inventory_grid
	var landing := Vector2(95, 31) # 2x2 pouch centered at column 2, row 0.
	assert_true(grid._can_drop_data(landing, payload()), "Pouches are transferable items, not restricted to deposits")
	grid._drop_data(landing, payload())
	assert_false(source.inventory.entries.has(entry))
	var received = target.inventory.get_entry_at_cell(Vector2i(2, 0))
	assert_not_null(received)
	if received != null:
		assert_eq(received.stack_id, "mira.pouch")
		assert_eq(received.metadata, {"origin": "Mira"})
		assert_eq(target.inventory.get_entry_contained_item_count(received, SILVER), 10)
	assert_eq(source.inventory.count_item(SILVER) + target.inventory.count_item(SILVER), 10)

func test_quick_transfer_moves_the_whole_pouch() -> void:
	controller._on_inventory_quick_transfer_requested(source, entry)
	assert_eq(source.inventory.entries.size(), 0)
	assert_eq(target.inventory.entries.size(), 1)
	if not target.inventory.entries.is_empty():
		assert_eq(target.inventory.entries[0].stack_id, "mira.pouch")
		assert_eq(target.inventory.count_item(SILVER), 10)

func test_cursor_pouch_can_be_placed_in_another_bag() -> void:
	var data := {"cursor_item": true, "source_owner": source, "item_definition": POUCH, "count": 1,
		"contained_item_counts": entry.contained_item_counts.duplicate(), "metadata": {"origin": "Mira", "_durable_stack_id": entry.stack_id}}
	assert_true(source.inventory.remove_entry(entry))
	assert_true(target_window._can_accept_drop(data, Vector2i(2, 0)))
	controller._on_cursor_item_place_requested(data, target, Vector2i(2, 0))
	var received = target.inventory.get_entry_at_cell(Vector2i(2, 0))
	assert_not_null(received)
	if received != null:
		assert_eq(received.stack_id, "mira.pouch")
		assert_eq(target.inventory.count_item(SILVER), 10)

func test_refused_drop_over_other_inventory_never_requests_a_world_drop() -> void:
	assert_true(target.inventory.add_entry_with_contents(POUCH, 1, {SILVER.resource_path: 250}))
	var grid := target_window.inventory_grid
	var point := grid.global_position + Vector2(31, 31)
	_move_pointer(point)
	watch_signals(source_window)
	source_window.inventory_grid._active_drag_data = payload()
	assert_false(grid._can_drop_data(Vector2(31, 31), payload()), "Full target pouch refuses deposit")
	source_window.inventory_grid._notification(Control.NOTIFICATION_DRAG_END)
	assert_signal_not_emitted(source_window, "item_drop_requested")
	assert_true(source.inventory.entries.has(entry))
	assert_eq(source.inventory.count_item(SILVER), 10)
	assert_eq(target.inventory.count_item(SILVER), 250)

func test_rejected_equipment_drop_over_other_window_does_not_drop_to_world() -> void:
	_move_pointer(target_window.global_position + Vector2(15, 15))
	watch_signals(source_window)
	source_window._on_equipment_slot_drag_dropped_outside("weapon")
	assert_signal_not_emitted(source_window, "equipment_drop_requested")

func test_release_over_world_still_requests_explicit_ground_drop() -> void:
	_move_pointer(Vector2(1150, 800))
	watch_signals(source_window)
	source_window.inventory_grid._active_drag_data = payload()
	source_window.inventory_grid._notification(Control.NOTIFICATION_DRAG_END)
	assert_signal_emitted(source_window, "item_drop_requested")

func test_full_or_distant_bag_keeps_pouch_and_silver_with_source() -> void:
	target.inventory = InventoryData.new(1, 1)
	target_window.refresh()
	assert_false(target_window._can_accept_drop(payload(), Vector2i.ZERO))
	controller._on_inventory_transfer_requested(source, target, entry, Vector2i.ZERO)
	assert_true(source.inventory.entries.has(entry))
	target.inventory = InventoryData.new()
	target.position.x = 20
	target_window.refresh()
	assert_false(target_window._can_accept_drop(payload(), Vector2i.ZERO))
	controller._on_inventory_transfer_requested(source, target, entry, Vector2i.ZERO)
	assert_true(source.inventory.entries.has(entry))
	assert_eq(source.inventory.count_item(SILVER), 10)
	assert_eq(target.inventory.count_item(SILVER), 0)

func test_pouch_on_pouch_still_deposits_silver_without_losing_coins() -> void:
	assert_true(target.inventory.add_entry_with_contents(POUCH, 1, {SILVER.resource_path: 5}))
	var target_pouch = target.inventory.entries[0]
	assert_true(target_window._can_accept_drop(payload(), Vector2i.ZERO))
	controller._on_inventory_transfer_requested(source, target, entry, Vector2i.ZERO)
	assert_eq(source.inventory.count_item(SILVER), 0)
	assert_eq(target.inventory.get_entry_contained_item_count(target_pouch, SILVER), 15)

func _move_pointer(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)
	assert_eq(source_window.get_global_mouse_position(), at, "Fixture pointer reaches the requested UI position")
