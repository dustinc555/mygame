extends GutTest

const TABLE = preload("res://features/settlements/resources/furnishing/container_stock_table.gd")
const ENTRY = preload("res://features/settlements/resources/furnishing/container_stock_entry.gd")
const FOOD = preload("res://features/inventory/resources/items/food.tres")

func test_weighted_pool_guarantees_stock_and_excludes_zero_weights() -> void:
	var table = TABLE.new()
	assert_true("weighted_draws" in table, "Stock tables support a bounded weighted pool")
	if not "weighted_draws" in table:
		return
	table.weighted_draws = 3
	var included = ENTRY.new()
	included.item_definition = FOOD
	included.chance = 1.0
	included.min_quantity = 2
	included.max_quantity = 2
	var excluded = ENTRY.new()
	excluded.item_definition = preload("res://features/inventory/resources/items/bread.tres")
	excluded.chance = 0.0
	table.entries.assign([included, excluded])
	var rng = RandomNumberGenerator.new()
	rng.seed = 91
	for index in 20:
		var result = table.roll(rng)
		assert_eq(result.size(), 1, "Duplicate picks merge")
		assert_eq(result[0].item_definition, FOOD)
		assert_eq(result[0].quantity, 6)

func test_empty_weighted_pool_is_safe() -> void:
	var table = TABLE.new()
	if not "weighted_draws" in table:
		fail_test("Missing weighted stock mode")
		return
	table.weighted_draws = 2
	assert_eq(table.roll(RandomNumberGenerator.new()).size(), 0)

func test_weighted_stock_fits_small_container_instead_of_rejecting_batch() -> void:
	var table = TABLE.new()
	table.weighted_draws = 2
	var entry = ENTRY.new()
	entry.item_definition = preload("res://features/inventory/resources/items/bread.tres")
	entry.min_quantity = 2
	entry.max_quantity = 2
	table.entries.assign([entry])
	var capacity := InventoryData.new(4, 2, 0.0, false)
	var result = table.roll(RandomNumberGenerator.new(), capacity)
	assert_eq(result.size(), 1)
	if not result.is_empty():
		assert_eq(result[0].quantity, 1, "one loaf fits; a two-loaf atomic batch does not")
	assert_eq(capacity.entries.size(), 1)

func test_weighted_stock_excludes_items_too_large_for_container() -> void:
	var table = TABLE.new()
	table.weighted_draws = 1
	var too_large = ENTRY.new()
	too_large.item_definition = preload("res://features/inventory/resources/items/bread.tres")
	var fits = ENTRY.new()
	fits.item_definition = FOOD
	table.entries.assign([too_large, fits])
	for seed in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var result = table.roll(rng, InventoryData.new(2, 1, 0.0, false))
		assert_eq(result.size(), 1)
		if not result.is_empty():
			assert_eq(result[0].item_definition, FOOD)
