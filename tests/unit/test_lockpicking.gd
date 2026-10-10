extends GutTest

const RULES_PATH := "res://features/lockpicking/sim/lockpick_rules.gd"
var rules
var inventory: InventoryData
var pick: ItemDefinition

func before_each() -> void:
	rules = load(RULES_PATH) if ResourceLoader.exists(RULES_PATH) else null
	inventory = InventoryData.new()
	pick = ItemDefinition.new()
	pick.tool_tags = PackedStringArray(["lockpick"])

func test_lockpick_rules_exist() -> void:
	assert_not_null(rules, "Picking needs one shared inventory and wear authority")

func test_missing_and_depleted_picks_are_ineligible() -> void:
	if rules == null: return
	assert_null(rules.find_pick(inventory))
	var entry = inventory.create_entry(pick, Vector2i.ZERO)
	inventory.entries.append(entry)
	assert_same(rules.find_pick(inventory), entry)
	entry.metadata[rules.WEAR_KEY] = 100000.0
	assert_null(rules.find_pick(inventory))

func test_wear_preserves_other_metadata_and_breaks_only_exact_stack() -> void:
	if rules == null: return
	var first = inventory.create_entry(pick, Vector2i.ZERO)
	var used = inventory.create_entry(pick, Vector2i(1, 0), 1, {}, {"stolen": true})
	inventory.entries.assign([first, used])
	var result: Dictionary = rules.apply_wear(inventory, used.stack_id, 5.0)
	assert_true(result.accepted)
	assert_false(result.broke)
	assert_true(used.metadata.stolen)
	assert_eq(float(used.metadata[rules.WEAR_KEY]), 5.0)
	assert_true(first.metadata.is_empty())
	result = rules.apply_wear(inventory, used.stack_id, 100000.0)
	assert_true(result.broke)
	assert_eq(inventory.entries.size(), 1)
	assert_same(inventory.entries[0], first)

func test_transferred_or_removed_stack_cannot_be_worn() -> void:
	if rules == null: return
	assert_false(rules.apply_wear(inventory, "missing", 10.0).accepted)

func test_quality_is_resilience_not_an_extra_success_roll() -> void:
	if rules == null: return
	var flimsy = load("res://features/inventory/resources/items/lockpick_flimsy.tres")
	var standard = load("res://features/inventory/resources/items/lockpick.tres")
	var fine = load("res://features/inventory/resources/items/lockpick_fine.tres")
	assert_not_null(flimsy)
	assert_not_null(fine)
	if flimsy == null or fine == null: return
	assert_lt(flimsy.lockpick_durability, standard.lockpick_durability)
	assert_lt(standard.lockpick_durability, fine.lockpick_durability)
	for item in [flimsy, standard, fine]:
		assert_eq(item.grid_size, Vector2i(1, 2))
		assert_false(item.is_equippable(), "Carried action tool, not a weapon slot")
