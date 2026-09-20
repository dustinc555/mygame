extends "res://tests/validation/test_case.gd"
## Processor exchange contract, not only unused process_counts arithmetic.
const PROCESSOR = preload("res://features/farming/projection/farm_seed_processor.gd")
const INVENTORY = preload("res://features/inventory/sim/inventory_data.gd")
const CROP = preload("res://features/farming/resources/crops/eggplant.tres")
class Actor:
	extends Node3D
	var faction_name := "Player"
var failures: Array[String] = []
func _initialize() -> void:
	var processor := PROCESSOR.new()
	var actor := Actor.new()
	processor.owner_faction_name = "Player"
	processor.inventory = INVENTORY.new(2, 1, 0.0, false)
	processor.inventory.add_item_count(CROP.produce_item, 2)
	_expect(processor.can_process_crop("eggplant", actor), "available produce plus seed space offers conversion")
	var result: Dictionary = processor.complete_processing("eggplant", actor)
	_expect(result.get("completed", false) and processor.inventory.count_item(CROP.produce_item) == 1 and processor.inventory.count_item(CROP.seed_item) == 4, "one exact produce is exchanged for four seeds; other produce remains")
	var before: Array = _snapshot(processor.inventory)
	actor.faction_name = "Foreign"
	_expect(not processor.can_process_crop("eggplant", actor) and not processor.complete_processing("eggplant", actor).get("completed", false), "foreign actor cannot process private stored produce")
	_expect(_snapshot(processor.inventory) == before, "denied access leaves every stack unchanged")
	actor.faction_name = "Player"
	processor.is_locked = true
	_expect(not processor.complete_processing("eggplant", actor).get("completed", false) and _snapshot(processor.inventory) == before, "locked processor leaves exact input/output stacks unchanged")
	processor.is_locked = false
	processor.inventory = INVENTORY.new(2, 1, 0.0, false)
	processor.inventory.set_stack_limit_resolver(func(_item): return 1)
	_expect(processor.inventory.add_item_count(CROP.produce_item, 2), "full-storage probe really starts with two produce")
	before = _snapshot(processor.inventory)
	_expect(not processor.can_process_crop("eggplant", actor) and not processor.complete_processing("eggplant", actor).get("completed", false), "four unstacked output seeds cannot fit beside remaining produce: no partial conversion")
	_expect(_snapshot(processor.inventory) == before, "full output storage cannot consume input")
	processor.inventory.remove_item_count(CROP.produce_item, 1)
	processor.inventory.set_stack_limit_resolver(Callable())
	_expect(processor.complete_processing("eggplant", actor).get("completed", false) and processor.inventory.count_item(CROP.produce_item) == 0 and processor.inventory.count_item(CROP.seed_item) == 4, "last produce frees its slot for the atomic seed exchange")
	before = _snapshot(processor.inventory)
	_expect(not processor.complete_processing("eggplant", actor).get("completed", false) and _snapshot(processor.inventory) == before, "empty input cannot mint seeds")
	actor.free()
	processor.free()
	for failure in failures: push_error(failure)
	print("SEED_PROCESSING_RULES_OK" if failures.is_empty() else "SEED_PROCESSING_RULES_FAILED")
	quit(0 if failures.is_empty() else 1)
func _snapshot(inventory: InventoryData) -> Array:
	var result: Array = []
	for entry in inventory.entries:
		result.append({"stack_id": entry.stack_id, "definition": entry.definition, "count": entry.count, "position": entry.grid_position, "metadata": entry.metadata.duplicate(true), "contents": entry.contained_item_counts.duplicate(true)})
	return result
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
