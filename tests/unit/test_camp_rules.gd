extends GutTest

func _rules():
	var path := "res://features/camps/sim/camp_rules.gd"
	assert_true(ResourceLoader.exists(path), "Camp lifecycle rules exist")
	return load(path) if ResourceLoader.exists(path) else null

func test_surviving_patrol_keeps_camp_alive_and_replacements_are_slow() -> void:
	var rules = _rules()
	if rules == null:
		return
	var state = {"status": "occupied", "population_limit": 10, "replacement_due": -1.0, "replacement_interval": 10080.0}
	assert_eq(rules.advance_lifecycle(state, 1, 100.0), 0)
	assert_eq(state.status, "occupied")
	assert_eq(state.replacement_due, 10180.0)
	assert_eq(rules.advance_lifecycle(state, 1, 10179.0), 0)
	assert_eq(rules.advance_lifecycle(state, 1, 10180.0), 1)
	assert_eq(rules.advance_lifecycle(state, 10, 999999.0), 0)

func test_wipe_cannot_replenish_and_cleanup_uses_clear_time() -> void:
	var rules = _rules()
	if rules == null:
		return
	var state = {"status": "occupied", "population_limit": 10, "replacement_due": 1.0, "replacement_interval": 10.0, "cleanup_delay": 10080.0}
	assert_eq(rules.advance_lifecycle(state, 0, 200.0), 0)
	assert_eq(state.status, "cleared")
	assert_eq(state.cleared_at, 200.0)
	rules.advance_lifecycle(state, 0, 10279.0)
	assert_eq(state.status, "cleared")
	rules.advance_lifecycle(state, 0, 10280.0)
	assert_eq(state.status, "empty")
	assert_eq(rules.advance_lifecycle(state, 0, 999999.0), 0)

func test_patrol_stays_inside_radius_and_avoids_crossing_town() -> void:
	var rules = _rules()
	if rules == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var towns = [{"position": Vector3(40, 0, 0), "radius": 25.0}]
	var start := Vector3.ZERO
	for index in 200:
		var target: Vector3 = rules.patrol_target(start, Vector3.ZERO, 100.0, towns, 0.0, rng)
		assert_lte(target.length(), 100.001)
		assert_true(rules.segment_clear(start, target, towns))
		start = target

func test_night_watch_excludes_roaming_squads() -> void:
	var rules = _rules()
	if rules == null:
		return
	assert_eq(rules.routine(0, 10, 21, true, 0.1), "patrol")
	assert_eq(rules.routine(0, 10, 21, false, 0.1), "guard")
	assert_eq(rules.routine(1, 10, 21, false, 0.1), "sleep")
	assert_ne(rules.routine(1, 10, 12, false, 0.1), "sleep")
