extends SceneTree
## Bounded production clock -> farming -> GECS recharge regression.
## Run: godot --headless --path . --script res://tests/validation/validate_well_recharge.gd

var failures: Array[String] = []
var placeholder: Node

## Only population handoff is substituted: recharge uses the production skip,
## WorldTimeController, FarmController, GECS bridge and water state component.
class EmptyPopulationHandoff:
	extends Node
	var active := false
	func is_far_simulation_active() -> bool: return active
	func is_realization_loading_active() -> bool: return false
	func begin_far_simulation(_owner: Node) -> bool:
		active = true
		return true
	func step_projection_handoff() -> bool: return true
	func end_far_simulation(_owner: Node) -> void: active = false

func _init() -> void:
	if not Engine.has_singleton("ECS"):
		placeholder = Node.new()
		Engine.register_singleton("ECS", placeholder)
	call_deferred("_run")

func _run() -> void:
	var scene := Node.new()
	root.add_child(scene)
	var context := BootstrapContext.new(scene)
	var gecs = load("res://features/core/gecs_world_controller.gd").new()
	scene.add_child(gecs)
	gecs.initialize(context)
	context.register(&"gecs_world", gecs)
	var clock = load("res://features/core/world_time_controller.gd").new()
	scene.add_child(clock)
	clock.set_process(false)
	context.register(&"world_time", clock)
	var territory := Node.new()
	scene.add_child(territory)
	context.register(&"territory", territory)
	var farm = load("res://features/farming/sim/farm_controller.gd").new()
	scene.add_child(farm)
	farm.initialize(context)
	var origin := float(clock.total_world_minutes)
	farm.register_water_source({"source_id": "well", "source_kind": "well", "owner_faction_name": "Player", "capacity": 100.0, "current_water": 0.0, "renewable": false, "recharge_per_world_minute": 1.0, "last_processed_minute": origin})
	clock._process(0.25)
	var water := float(farm.get_water_source("well").get("current_water", -1.0))
	_expect(water > 0.0 and water <= 0.05 + 0.000001, "first quarter-second recharges progressively by at most 0.05 L, got %f" % water)
	for step in 19:
		clock._process(0.25)
	water = float(farm.get_water_source("well").get("current_water", -1.0))
	_expect(is_equal_approx(water, 1.0), "five normal-speed real seconds restore exactly one liter at capped yield, got %f" % water)
	_test_fractional_save_and_pause(farm, clock, gecs)
	_test_storage_and_capacity(farm, clock)
	_test_clock_conversion(farm, clock)
	_test_skip_equivalence(farm, clock, gecs, context, scene)
	_test_authored_well(farm, clock)
	farm.register_water_source({"source_id": "ledger_cap", "settlement_id": "water_town", "source_kind": "well", "owner_faction_name": "Player", "capacity": 100.0, "current_water": 0.0, "recharge_per_world_minute": 1.0})
	_expect(is_equal_approx(float(farm.get_settlement_water_status("water_town").well_output_per_day), 288.0), "real GECS ledger forecasts capped yield, not authored uncapped yield")
	farm._rebuild_water_storage_index()
	_expect(is_equal_approx(float(farm.get_settlement_water_status("water_town").well_output_per_day), 288.0), "yield index rebuild does not double the forecast")
	farm.remove_water_source("ledger_cap")
	_expect(is_zero_approx(float(farm.get_settlement_water_status("water_town").well_output_per_day)), "removed well contributes no forecast yield")
	scene.free()
	if placeholder != null:
		Engine.unregister_singleton("ECS")
		placeholder.free()
	for failure in failures:
		push_error(failure)
	print("WELL_RECHARGE_OK" if failures.is_empty() else "WELL_RECHARGE_FAILED")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _seed(farm: Node, clock: Node, id: String, kind := "well", current := 0.0, capacity := 100.0, rate := 1.0) -> void:
	farm.register_water_source({"source_id": id, "source_kind": kind, "owner_faction_name": "Player", "capacity": capacity, "current_water": current, "renewable": false, "recharge_per_world_minute": rate, "last_processed_minute": int(clock.get_absolute_minute())})

func _liters(farm: Node, id: String) -> float:
	return float(farm.get_water_source(id).get("current_water", -1.0))

func _authorization(id: String) -> Dictionary:
	return {"source_id": id, "owner_faction_name": "Player", "actor_faction_name": "Player", "owner_access_approved": true}

func _test_fractional_save_and_pause(farm: Node, clock: Node, gecs: Node) -> void:
	clock._process(0.125)
	_seed(farm, clock, "fractional")
	var saved_clock: Dictionary = clock.serialize_state()
	var source: Dictionary = farm.get_water_source("fractional")
	_expect(is_equal_approx(float(source.last_processed_minute), float(clock.total_world_minutes)), "new source starts at exact fractional registration time")
	clock._process(0.25)
	var expected := _liters(farm, "fractional")
	_expect(is_equal_approx(expected, 0.05), "registration cannot recharge time before creation")
	# Persist and restore the real component dictionary and canonical time together.
	gecs.upsert_farm_water_source_state(source)
	clock.apply_serialized_state(saved_clock)
	farm._reconcile_after_world_reindex()
	clock._process(0.25)
	_expect(is_equal_approx(_liters(farm, "fractional"), expected), "fractional save/load neither loses nor duplicates recharge")
	var cursor := float(farm.get_water_source("fractional").last_processed_minute)
	farm._advance_water_source_state(farm.get_water_source("fractional"), cursor - 5.0)
	farm._advance_water_source_state(farm.get_water_source("fractional"), cursor)
	_expect(is_equal_approx(_liters(farm, "fractional"), expected), "backward/repeated advance cannot duplicate water")
	clock.request_manual_pause()
	clock._process(10.0)
	_expect(is_equal_approx(_liters(farm, "fractional"), expected), "paused normal processing does not recharge")
	clock.release_manual_pause()

func _test_storage_and_capacity(farm: Node, clock: Node) -> void:
	_seed(farm, clock, "tank", "storage", 7.0, 100.0, 1000.0)
	_seed(farm, clock, "full", "well", 2.0, 2.0)
	_seed(farm, clock, "slow", "well", 0.0, 100.0, 0.01)
	clock.advance_minutes(10.0)
	_expect(is_equal_approx(_liters(farm, "tank"), 7.0), "finite storage cannot autoregenerate even with a stale recharge field")
	_expect(is_equal_approx(_liters(farm, "slow"), 0.1), "slower authored groundwater yield is preserved")
	_expect(is_equal_approx(_liters(farm, "full"), 2.0), "recharge is capacity bounded")
	_expect(is_equal_approx(float(farm.draw_water_source("full", 2.0, _authorization("full"))), 2.0), "existing authorized draw API remains exact")
	clock._process(0.25)
	_expect(is_equal_approx(_liters(farm, "full"), 0.05), "full well discards surplus elapsed yield instead of banking it")
	_expect(is_equal_approx(float(farm.deposit_water_source("full", 0.5, _authorization("full"))), 0.5), "existing authorized deposit API remains exact")
	_expect(is_equal_approx(_liters(farm, "full"), 0.55), "manual deposit and recharge conserve their independent amounts")
	farm.remove_water_source("slow")
	clock._process(0.25)
	_expect(farm.get_water_source("slow").is_empty(), "deleted well never regenerates or reappears from the fractional index")

func _test_clock_conversion(farm: Node, clock: Node) -> void:
	for conversion in [0.5, 2.0]:
		clock.real_seconds_per_game_minute = conversion
		var id := "conversion_%s" % conversion
		_seed(farm, clock, id)
		for step in 20:
			clock._process(0.25)
		_expect(is_equal_approx(_liters(farm, id), 1.0), "five real seconds per liter respects canonical seconds/minute=%s" % conversion)
	clock.real_seconds_per_game_minute = 1.0

func _test_skip_equivalence(farm: Node, clock: Node, gecs: Node, context: BootstrapContext, scene: Node) -> void:
	_seed(farm, clock, "equivalence")
	var initial_source: Dictionary = farm.get_water_source("equivalence")
	var initial_clock: Dictionary = clock.serialize_state()
	var elapsed_seconds := 7.75
	for step in 31:
		clock._process(0.25)
	var normal := _liters(farm, "equivalence")
	_expect(is_equal_approx(normal, elapsed_seconds / 5.0), "normal fractional replay produces 1.55 liters")
	var fast := 0.0
	for speed in [2, 3]:
		clock.apply_serialized_state(initial_clock)
		gecs.upsert_farm_water_source_state(initial_source)
		clock.set_speed_index(speed)
		var real_step := 0.25 / float(clock.get_speed_scale())
		# Engine passes scaled delta to _process; don't multiply again in the sim.
		for step in 31:
			clock._process(real_step * Engine.time_scale)
		fast = _liters(farm, "equivalence")
		_expect(is_equal_approx(fast, normal), "speed index %d yields identical water for equal canonical time" % speed)
	clock.apply_serialized_state(initial_clock)
	gecs.upsert_farm_water_source_state(initial_source)
	clock.advance_minutes(elapsed_seconds / float(clock.real_seconds_per_game_minute))
	_expect(is_equal_approx(_liters(farm, "equivalence"), normal), "single canonical skip equals progressive normal/fast replay")
	clock.apply_serialized_state(initial_clock)
	gecs.upsert_farm_water_source_state(initial_source)
	var lod := EmptyPopulationHandoff.new()
	scene.add_child(lod)
	context.register(&"population_realization", lod)
	var skip = load("res://features/world_sim/bridge/debug_time_skip_controller.gd").new()
	scene.add_child(skip)
	skip.initialize(context)
	skip.set_process(false)
	var result: Dictionary = skip.request_skip(elapsed_seconds / 60.0, "Hours")
	_expect(bool(result.get("accepted", false)), "production debug skip accepts bounded fractional request")
	for frame in 32:
		if not skip.is_active(): break
		skip._process(0.0)
	_expect(not skip.is_active() and bool(skip.get_last_result().get("completed", false)), "production debug skip completes its handoff/advance/restore path")
	_expect(is_equal_approx(_liters(farm, "equivalence"), normal), "production debug skip equals normal and fast-forward recharge")
	print("WELL_RECHARGE_EQUIVALENCE normal=%.6f fast=%.6f skip=%.6f canonical_minutes=%.2f" % [normal, fast, _liters(farm, "equivalence"), elapsed_seconds])
	skip.free()
	lod.free()

func _test_authored_well(farm: Node, clock: Node) -> void:
	# This checks the reusable well prefab, not any town's placed overrides.
	var well = load("res://features/world/projection/props/water/well_1.tscn").instantiate()
	_expect(str(well.source_kind) == "well" and not bool(well.renewable), "authored Well 1 is a finite groundwater source")
	_seed(farm, clock, "authored_well", str(well.source_kind), 0.0, float(well.capacity), float(well.recharge_per_world_hour) / 60.0)
	clock._process(0.25)
	_expect(is_equal_approx(_liters(farm, "authored_well"), 0.05), "authored Well 1 yield obeys progressive five-second floor")
	well.free()
