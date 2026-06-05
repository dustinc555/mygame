extends SceneTree

const ARMORY_TEST_SCENE := preload("res://scenes/test_levels/armory_test.tscn")
const COMBAT_DUEL_ARMORY_SCENE := preload("res://scenes/test_levels/combat_duel_1v1_armory.tscn")
const BRONZE_SWORD_ITEM := preload("res://resources/items/bronze_sword.tres")
const FANTASY_STEEL_SWORD_ITEM := preload("res://resources/items/fantasy_steel_sword.tres")
const TABLE_FORK_ITEM := preload("res://resources/items/table_fork.tres")
const TABLE_KNIFE_ITEM := preload("res://resources/items/table_knife.tres")
const TABLE_SPOON_ITEM := preload("res://resources/items/table_spoon.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_chest(ARMORY_TEST_SCENE, "ArmoryTest", NodePath("ArmoryContainers/WeaponChest"), 16, 10)
	await _validate_chest(COMBAT_DUEL_ARMORY_SCENE, "CombatDuel1v1Armory", NodePath("ItemChest"), 12, 14)
	if _failures.is_empty():
		print("ARMORY_WEAPON_CHEST_STOCK_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("ARMORY_WEAPON_CHEST_STOCK_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_chest(scene_resource: PackedScene, scene_name: String, chest_path: NodePath, min_columns: int, min_rows: int) -> void:
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	await process_frame
	var chest := scene.get_node_or_null(chest_path)
	if chest == null:
		_fail("%s should have a weapon chest at %s" % [scene_name, str(chest_path)])
		scene.queue_free()
		return
	var inventory = chest.get("inventory")
	if inventory == null:
		_fail("%s weapon chest should build inventory data" % scene_name)
		scene.queue_free()
		return
	if int(inventory.columns) < min_columns or int(inventory.rows) < min_rows:
		_fail("%s weapon chest should have at least %dx%d slots, got %dx%d" % [scene_name, min_columns, min_rows, int(inventory.columns), int(inventory.rows)])
	_validate_item_entry(scene_name, inventory, BRONZE_SWORD_ITEM, "Bronze Sword")
	_validate_item_entry(scene_name, inventory, FANTASY_STEEL_SWORD_ITEM, "Steel Sword")
	_validate_item_entry(scene_name, inventory, TABLE_FORK_ITEM, "Fork")
	_validate_item_entry(scene_name, inventory, TABLE_KNIFE_ITEM, "Table Knife")
	_validate_item_entry(scene_name, inventory, TABLE_SPOON_ITEM, "Spoon")
	scene.queue_free()
	await process_frame


func _validate_item_entry(scene_name: String, inventory, item_definition: ItemDefinition, item_name: String) -> void:
	var matching_entries := 0
	var total_count := 0
	for entry in inventory.entries:
		if not _is_same_item_definition(entry.definition, item_definition):
			continue
		matching_entries += 1
		total_count += int(entry.count)
	if matching_entries != 1 or total_count != 1:
		_fail("%s weapon chest should contain exactly one %s after stock insertion, got entries=%d total=%d" % [scene_name, item_name, matching_entries, total_count])


func _is_same_item_definition(left: ItemDefinition, right: ItemDefinition) -> bool:
	if left == right:
		return true
	if left == null or right == null:
		return false
	return left.resource_path == right.resource_path


func _fail(message: String) -> void:
	_failures.append(message)
