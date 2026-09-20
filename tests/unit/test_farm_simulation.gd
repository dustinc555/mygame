extends GutTest
## Durable rules from validate_farming_simulation, without a field or world boot.

const FARM = preload("res://features/farming/sim/farm_simulation.gd")

var crop: Dictionary
var planted: Dictionary


func before_each() -> void:
	crop = {
		"growth_minutes": 80.0,
		"dry_grace_minutes": 30.0,
		"ripe_window_minutes": 45.0,
		"water_capacity": 40.0,
		"water_per_growth_minute": 0.5,
		"base_yield": 3,
		"yield_per_farming_level": 0.02,
	}
	planted = FARM.complete_planting(
		FARM.complete_tilling(FARM.new_cell(Vector2i(2, 3), Vector3(4, 1, 6))),
		"unit.crop", 8.0
	)


func test_growth_consumes_only_available_water_independent_of_step_size() -> void:
	var original := planted.duplicate(true)
	var whole := FARM.advance_cell(planted, crop, 20.0)
	var split := FARM.advance_cell(FARM.advance_cell(planted, crop, 10.0), crop, 10.0)

	assert_eq(whole.state, FARM.STATE_GROWING)
	assert_almost_eq(whole.growth, 0.2, 0.000001)
	assert_eq(whole.water, 0.0)
	assert_eq(whole.dry_minutes, 4.0)
	assert_eq_deep(split, whole)
	assert_eq_deep(planted, original)


func test_dry_crop_stops_growing_and_withers_at_the_grace_boundary() -> void:
	planted.water = 0.0
	planted.claimed_by = "unit.worker"
	planted.work_progress = 0.5
	var almost := FARM.advance_cell(planted, crop, 29.5)
	assert_eq(almost.state, FARM.STATE_GROWING)
	assert_eq(almost.growth, 0.0)

	var expired := FARM.advance_cell(almost, crop, 0.5)
	assert_eq(expired.state, FARM.STATE_WITHERED)
	assert_eq(expired.water, 0.0)
	assert_eq(expired.claimed_by, "")
	assert_eq(expired.work_progress, 0.0)


func test_harvest_yields_once_and_keeps_cultivated_soil_at_its_location() -> void:
	var premature := FARM.complete_harvest(planted, crop, 10.0, 100)
	assert_eq(premature.yield, 0)
	assert_eq_deep(premature.cell, planted)
	planted.water = 40.0
	var ripe := FARM.advance_cell(planted, crop, 80.0)
	assert_eq(ripe.state, FARM.STATE_RIPE)

	var harvested := FARM.complete_harvest(ripe, crop, 10.0, 100)
	assert_eq(harvested.yield, 4)
	assert_eq(harvested.cell.state, FARM.STATE_TILLED)
	assert_true(harvested.cell.soil_created)
	assert_eq(harvested.cell.crop_id, "")
	assert_eq(harvested.cell.grid_position, Vector2i(2, 3))
	assert_eq(harvested.cell.world_position, Vector3(4, 1, 6))
	assert_eq(harvested.cell.soil_recovery_started_minute, 100)
	var repeated := FARM.complete_harvest(harvested.cell, crop, 10.0, 100)
	assert_eq(repeated.yield, 0)
	assert_eq_deep(repeated.cell, harvested.cell)
