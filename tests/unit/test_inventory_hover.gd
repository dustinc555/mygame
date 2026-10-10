extends GutTest

const WINDOW = preload("res://features/ui/projection/inventory_window.tscn")
const STORED_PATH := "user://inventory_hover.hover_item"

# Count actual ResourceLoader constructions without loading expensive item art.
# A closed bag retains paths, not the ItemDefinition's reference-counted graph.
class CountingItemLoader extends ResourceFormatLoader:
	var loads := 0
	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["hover_item"])
	func _handles_type(type: StringName) -> bool:
		return type == &"Resource"
	func _get_resource_type(path: String) -> String:
		return "Resource" if path.get_extension() == "hover_item" else ""
	func _exists(path: String) -> bool:
		return path.get_extension() == "hover_item"
	func _load(_path: String, _original: String, _threads: bool, _cache: int) -> Variant:
		loads += 1
		var definition := ItemDefinition.new()
		definition.unit_weight = 3.0
		return definition

class Owner extends Node:
	var inventory := InventoryData.new()
	func shows_inventory_equipment() -> bool: return false

var loader: CountingItemLoader

func before_each() -> void:
	loader = CountingItemLoader.new()
	ResourceLoader.add_resource_format_loader(loader, true)

func after_each() -> void:
	ResourceLoader.remove_resource_format_loader(loader)
	loader = null

func _stored_metadata() -> Dictionary:
	return {"item_storage": {"entries": [{"item_definition_path": STORED_PATH, "count": 2}]}}

func test_sustained_closed_bag_hover_does_not_reload_item_resources() -> void:
	var source := Owner.new()
	var target := Owner.new()
	add_child_autofree(source)
	add_child_autofree(target)
	var incoming := ItemDefinition.new()
	incoming.grid_size = Vector2i(2, 2)
	assert_true(source.inventory.add_item(incoming))
	assert_true(target.inventory.add_item(incoming))
	var saved := _stored_metadata()
	target.inventory.additional_weight_provider = func(): return target.inventory.get_item_storage_weight("closed.bag", saved)
	var window: InventoryWindow = WINDOW.instantiate()
	add_child_autofree(window)
	window.setup(target) # Initial weight display resolves the stored definition.
	assert_almost_eq(target.inventory.get_total_weight(), 7.0, 0.00001)
	assert_false(ResourceLoader.has_cached(STORED_PATH), "Weight queries must not retain the item's art graph")
	var initial_loads := loader.loads
	var grid: InventoryGridControl = window.inventory_grid
	var payload := {"source_owner": source, "source_inventory": source.inventory, "entry": source.inventory.entries[0]}
	for i in 60:
		var cell := Vector2i(4 + i % 3, 2)
		assert_true(grid._can_drop_data(grid._item_rect_from_definition(incoming, cell).get_center(), payload))
		assert_false(grid._can_drop_data(grid._item_rect_from_definition(incoming, Vector2i.ZERO).get_center(), payload))
	assert_eq(loader.loads, initial_loads, "Sustained hover must perform zero new resource loads")
	assert_eq(source.inventory.entries.size(), 1, "Hover cannot move goods")
	assert_eq(target.inventory.entries.size(), 1)

func test_invalid_hover_validates_once_and_keeps_the_error_message() -> void:
	var owner := Owner.new()
	add_child_autofree(owner)
	var item := ItemDefinition.new()
	assert_true(owner.inventory.add_item(item))
	var window: InventoryWindow = WINDOW.instantiate()
	add_child_autofree(window)
	window.setup(owner)
	var validations := [0]
	var grid := window.inventory_grid
	grid.drop_validator = func(data, cell):
		validations[0] += 1
		return window._can_accept_drop(data, cell)
	grid.drop_error_provider = func(data, cell):
		validations[0] += 1
		return window._get_drop_error(data, cell)
	var payload := {"source_owner": owner, "entry": owner.inventory.entries[0]}
	assert_false(grid._can_drop_data(Vector2(-100, -100), payload))
	assert_eq(validations[0], 1, "The error result already contains the validation result")
	assert_eq(grid._last_invalid_drop_message, "No room")

func test_stationary_hover_redraws_only_when_the_preview_changes() -> void:
	var grid := InventoryGridControl.new()
	add_child_autofree(grid)
	grid.set_inventory_data(InventoryData.new())
	grid.size = grid.custom_minimum_size
	var item := ItemDefinition.new()
	var valid := [true]
	grid.drop_validator = func(_data, _cell): return valid[0]
	var draws := [0]
	grid.draw.connect(func(): draws[0] += 1)
	var payload := {"item_definition": item}
	var at := grid._item_rect_from_definition(item, Vector2i.ZERO).get_center()
	assert_true(grid._can_drop_data(at, payload))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(draws[0], 0, "The production grid actually drew the initial preview")
	var initial_draws: int = draws[0]
	for i in 4:
		assert_true(grid._can_drop_data(at, payload))
		await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(draws[0], initial_draws, "Holding the same item over the same square must not redraw the grid")
	valid[0] = false
	assert_false(grid._can_drop_data(at, payload), "Validation still observes changed capacity/access")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(grid._preview_visible)
	assert_gt(draws[0], initial_draws, "Changing validity must remove the highlight")

func test_resolved_weights_keep_counts_liquids_and_loaded_definition_edits_live() -> void:
	var inventory := InventoryData.new()
	var saved := _stored_metadata()
	assert_almost_eq(inventory.get_stored_weight(saved), 6.0, 0.00001)
	var initial_loads := loader.loads
	saved.item_storage.entries[0].count = 4
	saved.item_storage.entries[0].metadata = {"farm_water": 2.0, "carried_liquids": {"water": 2.0}}
	assert_almost_eq(inventory.get_stored_weight(saved), 14.0, 0.00001, "Only definitions are remembered, not mutable contents or totals")
	assert_eq(loader.loads, initial_loads)
	var definition := load(STORED_PATH) as ItemDefinition
	definition.unit_weight = 5.0
	assert_almost_eq(inventory.get_stored_weight(saved), 22.0, 0.00001, "A live authoring edit replaces the remembered scalar")
	definition = null
	assert_false(ResourceLoader.has_cached(STORED_PATH))
	assert_almost_eq(inventory.get_stored_weight(saved), 22.0, 0.00001)
	saved.item_storage.entries.clear()
	assert_eq(inventory.get_stored_weight(saved), 0.0, "Removing contents cannot leave cached weight")

func test_currency_contents_share_the_resource_resolution_cache() -> void:
	var inventory := InventoryData.new()
	var container := ItemDefinition.new()
	container.unit_weight = 1.0
	var contents := {STORED_PATH: 2}
	assert_almost_eq(inventory.get_item_weight(container, 1, contents), 7.0, 0.00001)
	var initial_loads := loader.loads
	for i in 10:
		contents[STORED_PATH] = i
		assert_almost_eq(inventory.get_item_weight(container, 1, contents), 1.0 + 3.0 * i, 0.00001)
	assert_eq(loader.loads, initial_loads, "Pouches cannot reintroduce resource loads into hover")

func test_live_storage_overrides_saved_weight_during_unpublished_transaction() -> void:
	var carrier := InventoryData.new()
	var saved := _stored_metadata()
	assert_almost_eq(carrier.get_item_storage_weight("bag", saved), 6.0, 0.00001)
	var live := InventoryData.new()
	carrier.bind_item_storage("bag", live)
	var item := ItemDefinition.new()
	item.unit_weight = 7.0
	assert_true(live.hydrate_entry_with_contents(item, Vector2i.ZERO, 1, {}, {}, "live.child", false))
	assert_almost_eq(carrier.get_item_storage_weight("bag", saved), 7.0, 0.00001)
	var snapshot := live._snapshot_standard_transaction()
	live.entries[0].metadata = {"farm_water": 2.0}
	assert_almost_eq(carrier.get_item_storage_weight("bag", saved), 9.0, 0.00001)
	live._restore_standard_transaction(snapshot)
	assert_almost_eq(carrier.get_item_storage_weight("bag", saved), 7.0, 0.00001)
	live.access_validator = func(): return false
	assert_almost_eq(carrier.get_item_storage_weight("bag", saved), 6.0, 0.00001, "Invalidated projections cannot override durable contents")
	carrier.unbind_item_storage("bag", live)
	live = null
	assert_almost_eq(carrier.get_item_storage_weight("bag", saved), 6.0, 0.00001)

func test_drop_rechecks_capacity_after_successful_hover() -> void:
	var source := Owner.new()
	var target := Owner.new()
	add_child_autofree(source)
	add_child_autofree(target)
	var item := ItemDefinition.new()
	assert_true(source.inventory.add_entry_with_contents(item, 1, {}, {"quality": 0.7}, "incoming"))
	var saved := _stored_metadata()
	target.inventory.additional_weight_provider = func(): return target.inventory.get_item_storage_weight("bag", saved)
	target.inventory.max_weight = 7.0
	var window: InventoryWindow = WINDOW.instantiate()
	add_child_autofree(window)
	window.setup(target)
	var committed := [0]
	window.transfer_requested.connect(func(from, to, entry, cell):
		if from.inventory.move_entry_to_inventory(entry, to.inventory, cell):
			committed[0] += 1)
	var grid := window.inventory_grid
	var payload := {"source_owner": source, "entry": source.inventory.entries[0]}
	var at := grid._item_rect_from_definition(item, Vector2i.ZERO).get_center()
	assert_true(grid._can_drop_data(at, payload))
	saved.item_storage.entries[0].count = 3
	grid._drop_data(at, payload)
	assert_eq(committed[0], 0, "A formerly valid preview is not transfer authority")
	assert_eq(source.inventory.entries.size(), 1)
	assert_eq(target.inventory.entries.size(), 0)
	saved.item_storage.entries[0].count = 2
	assert_true(grid._can_drop_data(at, payload))
	source.inventory.access_validator = func(): return false
	grid._drop_data(at, payload)
	assert_eq(committed[0], 0, "Access loss also rejects a late drop")
	source.inventory.access_validator = Callable()
	grid._drop_data(at, payload)
	assert_eq(committed[0], 1)
	assert_eq(source.inventory.entries.size(), 0)
	assert_eq(target.inventory.entries[0].stack_id, "incoming")
	assert_eq(target.inventory.entries[0].metadata, {"quality": 0.7})
