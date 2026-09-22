extends GutTest

const POLICY_PATH := "res://features/settlements/resources/merchant_stock_policy.gd"
const SEEDS = preload("res://features/inventory/resources/items/eggplant_seeds.tres")
const SWORD = preload("res://features/inventory/resources/items/golden_sword.tres")
const SILVER = preload("res://features/inventory/resources/items/silver.tres")

func test_refill_is_target_only_and_preserves_unique_goods_and_money() -> void:
	assert_true(ResourceLoader.exists(POLICY_PATH), "production stock policy exists")
	if not ResourceLoader.exists(POLICY_PATH): return
	var policy = load(POLICY_PATH)
	var inventory := InventoryData.new()
	inventory.columns = 20
	inventory.rows = 20
	inventory.use_weight = false
	inventory.add_item_count(SEEDS, 2)
	inventory.add_item_count(SILVER, 7)
	var rules := {SEEDS.resource_path: {"quantity": 5, "replenishes": true}, SWORD.resource_path: {"quantity": 1, "replenishes": false}, SILVER.resource_path: {"quantity": 100, "replenishes": true}}
	policy.replenish(inventory, rules)
	assert_eq(inventory.count_item(SEEDS), 5)
	assert_eq(inventory.count_item(SWORD), 0, "sold unique item stays sold")
	assert_eq(inventory.count_item(SILVER), 7, "restock never resets money")
	policy.replenish(inventory, rules)
	assert_eq(inventory.count_item(SEEDS), 5, "no accumulation")
	inventory.add_item_count(SEEDS, 3)
	policy.replenish(inventory, rules)
	assert_eq(inventory.count_item(SEEDS), 8, "player sales above target are retained")

func test_due_time_skips_missed_periods_without_replaying_deliveries() -> void:
	assert_true(ResourceLoader.exists(POLICY_PATH))
	if not ResourceLoader.exists(POLICY_PATH): return
	var policy = load(POLICY_PATH)
	assert_eq(policy.first_due_minute(600, 3, 8), 4800)
	assert_eq(policy.advance_due_minute(4800, 4800, 3), 9120)
	assert_eq(policy.advance_due_minute(4800, 15000, 3), 17760)

func test_overrides_do_not_mutate_preset_and_zero_removes_stock() -> void:
	assert_true(ResourceLoader.exists(POLICY_PATH))
	if not ResourceLoader.exists(POLICY_PATH): return
	var policy = load(POLICY_PATH)
	var defaults := {SEEDS.resource_path: {"quantity": 10, "replenishes": true}}
	var overrides := {SEEDS.resource_path: {"quantity": 0, "replenishes": false}, SWORD.resource_path: {"quantity": 1, "replenishes": false}}
	var resolved: Dictionary = policy.resolve(defaults, overrides)
	assert_eq(defaults[SEEDS.resource_path].quantity, 10)
	assert_eq(resolved[SEEDS.resource_path].quantity, 0)
	assert_false(resolved[SWORD.resource_path].replenishes)
