extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_simulation.gd

const FARM = preload("res://features/farming/sim/farm_simulation.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var crop := {
		"growth_minutes": 80.0,
		"dry_grace_minutes": 30.0,
		"ripe_window_minutes": 45.0,
		"water_capacity": 40.0,
		"water_per_growth_minute": 0.5,
		"base_yield": 3,
		"yield_per_farming_level": 0.02,
	}
	var cell := FARM.new_cell(Vector2i(2, 3), Vector3(4.0, 1.0, 6.0))
	_expect(failures, "new cell starts untilled", cell.get("state") == FARM.STATE_UNTILLED)
	cell = FARM.complete_tilling(cell)
	cell = FARM.complete_planting(cell, "tomato", 40.0)
	_expect(failures, "planting creates a growing crop", cell.get("state") == FARM.STATE_GROWING)

	cell = FARM.advance_cell(cell, crop, 40.0)
	_expect_close(failures, "watered crop reaches half growth", float(cell.get("growth")), 0.5)
	_expect(failures, "half-grown crop stays within the seven healthy visual stages", int(cell.get("stage_index")) == 3)
	_expect_close(failures, "water is consumed by growth", float(cell.get("water")), 20.0)

	cell = FARM.advance_cell(cell, crop, 40.0)
	_expect(failures, "fully grown crop becomes ripe", cell.get("state") == FARM.STATE_RIPE)
	_expect_close(failures, "ripe crop reaches full growth", float(cell.get("growth")), 1.0)
	_expect(failures, "ripe crop uses the visually verified healthy stage seven", int(cell.get("stage_index")) == 6)

	var harvested := FARM.complete_harvest(cell, crop, 10.0)
	_expect(failures, "harvest returns crop yield", int(harvested.get("yield")) == 4)
	_expect(failures, "harvest leaves physically cultivated empty soil", (harvested.get("cell") as Dictionary).get("state") == FARM.STATE_TILLED and bool((harvested.get("cell") as Dictionary).get("soil_created", false)))

	var dry_cell := FARM.complete_planting(FARM.complete_tilling(FARM.new_cell(Vector2i.ZERO, Vector3.ZERO)), "tomato", 0.0)
	dry_cell = FARM.advance_cell(dry_cell, crop, 30.0)
	_expect(failures, "crop withers when its dry grace period is exhausted", dry_cell.get("state") == FARM.STATE_WITHERED)
	_expect(failures, "withered crop uses the visually verified dead stage nine", int(dry_cell.get("stage_index")) == 8)

	var blocked := FARM.block_cell(FARM.new_cell(Vector2i.ONE, Vector3.ONE), "rock")
	_expect(failures, "obstacles durably block individual cells", blocked.get("state") == FARM.STATE_BLOCKED and blocked.get("blocked_reason") == "rock")
	blocked = FARM.clear_blockage(blocked)
	_expect(failures, "cleared obstacles return cells to ordinary untilled soil", blocked.get("state") == FARM.STATE_UNTILLED)
	var rain_cell := FARM.complete_planting(FARM.complete_tilling(FARM.new_cell(Vector2i.ZERO, Vector3.ZERO)), "tomato", 0.0)
	rain_cell = FARM.apply_rain(rain_cell, 5.0)
	_expect(failures, "rain waters crops without advancing growth time", is_equal_approx(float(rain_cell.get("water", 0.0)), 5.0))

	_finish(failures)


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)


func _expect_close(failures: Array[String], label: String, actual: float, expected: float) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s expected %.4f got %.4f" % [label, expected, actual])


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("FARMING_SIMULATION_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARMING_SIMULATION_FAILED count=%d" % failures.size())
	quit(1)
