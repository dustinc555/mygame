extends GutTest
## Authored clothing sizes are gameplay capacity, not icon-image dimensions.

const FOOTPRINTS := {
	"ranger_leggings": Vector2i(2, 3),
	"ranger_boots": Vector2i(2, 2),
	"noble_shoes": Vector2i(2, 2),
	"peasant_shoes": Vector2i(2, 2),
	"wizard_shoes": Vector2i(2, 2),
	"knight_sabatons": Vector2i(2, 2),
	"traveler_hide_boots": Vector2i(2, 2),
	"knight_gauntlets": Vector2i(2, 2),
	"traveler_hide_gloves": Vector2i(2, 2),
}

func test_wearables_reserve_the_full_authored_inventory_footprint() -> void:
	for key: String in FOOTPRINTS:
		var item := load("res://features/inventory/resources/items/%s.tres" % key) as ItemDefinition
		var expected: Vector2i = FOOTPRINTS[key]
		assert_not_null(item, key)
		if item == null:
			continue
		assert_eq(item.grid_size, expected, key + ": authored footprint")
		var bag := InventoryData.new(expected.x, expected.y, 100.0, false)
		assert_true(bag.can_place_item(item, Vector2i.ZERO), key + ": fits its exact area")
		assert_false(bag.can_place_item(item, Vector2i.RIGHT), key + ": cannot overflow right edge")
		assert_false(bag.can_place_item(item, Vector2i.DOWN), key + ": cannot overflow bottom edge")
		bag.rows -= 1
		assert_false(bag.can_add_item(item), key + ": cannot occupy a bag missing its last row")
