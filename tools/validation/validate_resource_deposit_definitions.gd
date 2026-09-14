extends SceneTree

const DEFINITION_PATH := "res://features/world/resources/resource_deposit_definition.gd"
const CATALOG_ROOT := "res://features/world/resources/resource_deposits/"
var failures: Array[String] = []
var change_count := 0

func _initialize() -> void:
	if not ResourceLoader.exists(DEFINITION_PATH):
		_check(false, "Shared deposit definition is missing")
		_finish()
		return
	var script = load(DEFINITION_PATH)
	var definition = script.new()
	definition.changed.connect(func(): change_count += 1)
	definition.deposit_type_id = "test"
	definition.display_name = "Test"
	definition.category = "Ore"
	definition.scene_path = "res://features/world/bridge/resource_nodes/copper_node.tscn"
	definition.min_stock = 2
	definition.max_stock = 4
	_check(definition.validation_errors().is_empty(), "Valid definition accepted")
	_check(change_count > 0, "Tuning emits Resource.changed")
	definition.min_stock = -3
	definition.max_stock = -8
	definition.refill_min_weeks = NAN
	definition.refill_max_weeks = -2.0
	_check(not definition.validation_errors().is_empty(), "Invalid ranges are diagnosed")
	var stock: Vector2i = definition.get_stock_range()
	var delay: Vector2 = definition.get_refill_range_minutes()
	_check(stock.x >= 1 and stock.y >= stock.x, "Runtime stock range is positive and ordered")
	_check(is_finite(delay.x) and delay.x > 0 and delay.y >= delay.x, "Runtime delay is finite, positive and ordered")
	# Validate the contract, not frozen balance numbers: designers can change
	# the actual stock and week settings without rewriting this validator.
	for id in ["copper", "scrap_pile", "twisted_scrap_heap", "robot_wreck"]:
		var path: String = CATALOG_ROOT + id + ".tres"
		if not ResourceLoader.exists(path):
			_check(false, "Catalog entry missing: " + id)
			continue
		var entry = load(path)
		_check(entry.deposit_type_id == id, "Stable type ID: " + id)
		_check(entry.get_stock_range() == Vector2i(entry.min_stock, entry.max_stock), "Authored stock range is used: " + id)
		_check(entry.validation_errors().is_empty(), "Catalog validation: " + id)
		_check(entry.get_refill_range_minutes().is_equal_approx(Vector2(entry.refill_min_weeks, entry.refill_max_weeks) * script.minutes_per_week()), "Authored week range uses the canonical world calendar: " + id)
	var settings_path := "res://features/world/resources/resource_deposit_settings.tres"
	_check(ResourceLoader.exists(settings_path), "Advanced refill budgets have a human-editable settings resource")
	if ResourceLoader.exists(settings_path):
		var settings = load(settings_path)
		var controller = load("res://features/world/sim/resource_deposit_controller.gd").new()
		_check(controller.settings == settings, "Runtime reads the same performance settings shown by the editor")
		_check(controller.max_refills_per_frame == settings.max_refills_per_frame, "Frame count budget uses the shared setting")
		_check(controller.refill_budget_usec == roundi(settings.refill_budget_milliseconds * 1000.0), "Human millisecond budget drives the runtime microsecond budget")
		controller.free()
	_finish()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func _finish() -> void:
	print("RESOURCE_DEPOSIT_DEFINITIONS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
