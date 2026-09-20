extends SceneTree
## Exact minute replay oracle: full detached dictionaries vs indexed GECS commits.
## Covers drought/ripeness/soil boundaries and invalidation by external mutations.
const SIM = preload("res://features/farming/sim/farm_simulation.gd")
var failures: Array[String] = []
var placeholder: Node

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
	var farm = load("res://features/farming/sim/farm_controller.gd").new()
	scene.add_child(farm)
	farm._gecs = gecs
	for id in farm.CROP_PATHS:
		farm._crops[id] = load(farm.CROP_PATHS[id])
	var cells := {}
	for index in 341:
		var cell := SIM.new_cell(Vector2i(index, 0), Vector3(index, 0, 0))
		if index < 6:
			cell = SIM.complete_planting(SIM.complete_tilling(cell), "eggplant", 0.02 if index % 2 == 0 else 20.0)
			cell["growth"] = 0.999 if index < 2 else 0.1
			if index == 2:
				cell["water"] = 0.0
				cell["dry_minutes"] = maxf(0.0, float(farm.get_crop("eggplant").dry_grace_minutes) - 0.5)
		elif index == 6:
			cell = SIM.complete_tilling(cell)
			cell["soil_recovery_started_minute"] = -1
		elif index == 7:
			cell["state"] = SIM.STATE_RIPE
			cell["crop_id"] = "eggplant"
			cell["ripe_minutes"] = 719.5
		cells[str(index)] = cell
	gecs.upsert_farm_plot_state({"plot_id": "equivalence", "settlement_id": "town", "owner_faction_id": "Player", "cells": cells, "crop_policy_id": "eggplant"})
	_expect(cells["2"].state == SIM.STATE_GROWING and cells["2"].water == 0.0, "drought fixture begins growing without water")
	for minute in range(1, 361):
		if minute in [3, 60, 120, 240]:
			var state: Dictionary = gecs.get_farm_plot_state("equivalence")
			state["crop_policy_id"] = "" if minute in [60, 240] else "eggplant"
			state["state_revision"] = int(state.state_revision) + 1
			state.cells["340"] = SIM.complete_tilling(state.cells["340"])
			gecs.upsert_farm_plot_state(state)
		if minute == 180:
			var replacement: Dictionary = gecs.get_farm_plot_state("equivalence")
			farm.remove_plot("equivalence")
			replacement.cells["339"] = SIM.complete_tilling(replacement.cells["339"])
			gecs.upsert_farm_plot_state(replacement)
		var before: Dictionary = gecs.get_farm_plot_state("equivalence")
		var expected := _reference_minute(before, farm, minute)
		farm._on_minute_changed(minute, 0, minute / 60, minute % 60)
		var actual: Dictionary = gecs.get_farm_plot_state("equivalence")
		_expect(actual == expected, "exact farm dictionary at minute %d" % minute)
		if minute == 1:
			_expect(actual.cells["2"].state == SIM.STATE_WITHERED, "dry crop crosses its configured drought deadline")
		var counts := {}
		for cell in expected.cells.values():
			if cell.state == SIM.STATE_GROWING:
				counts[cell.crop_id] = int(counts.get(cell.crop_id, 0)) + 1
		_expect(gecs.get_growing_farm_crop_counts_for_settlement("town") == counts, "aggregate crop index at minute %d" % minute)
		# Public snapshots/signals may be retained and mutated, never GECS aliases.
		actual.cells["0"]["water"] = -12345.0
		_expect(gecs.get_farm_plot_state("equivalence").cells["0"].water != -12345.0, "public snapshot remains detached")
	_test_soil_expiry(gecs, farm)
	_test_ledger(gecs, context, scene)
	scene.free()
	if placeholder != null:
		Engine.unregister_singleton("ECS")
		placeholder.free()
	if failures.is_empty():
		print("TIME_SKIP_EQUIVALENCE_OK minutes=360 cells=341 ledger_boundaries=5")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_soil_expiry(gecs: Node, farm: Node) -> void:
	var deadline: int = farm.SOIL_RECOVERY_MINUTES
	var cultivated := SIM.complete_tilling(SIM.new_cell(Vector2i.ZERO, Vector3(0, 0, 10)), 0)
	gecs.upsert_farm_plot_state({"plot_id": "soil-expiry", "settlement_id": "soil-town", "owner_faction_id": "Player",
		"cells": {"0:0": cultivated}, "crop_policy_id": "", "last_simulated_minute": deadline - 2})
	for minute in [deadline - 1, deadline]:
		var before: Dictionary = gecs.get_farm_plot_state("soil-expiry")
		_expect(before.cells["0:0"].soil_created and before.cells["0:0"].state == SIM.STATE_TILLED,
			"soil expiry begins with cultivated ground before the deadline")
		var expected := _reference_minute(before, farm, minute)
		farm._on_minute_changed(minute, 0, minute / 60, minute % 60)
		var actual: Dictionary = gecs.get_farm_plot_state("soil-expiry")
		_expect(actual == expected, "soil expiry matches detached replay at minute %d" % minute)
		if minute < deadline:
			_expect(actual.cells["0:0"].soil_created, "cultivated soil survives immediately before expiry")
		else:
			_expect(not actual.cells["0:0"].soil_created and actual.cells["0:0"].state == SIM.STATE_UNTILLED,
				"cultivated soil actually recovers at its configured deadline")


func _reference_minute(source: Dictionary, farm: Node, minute: int) -> Dictionary:
	var state := source.duplicate(true)
	var elapsed := minute - int(state.last_simulated_minute)
	var policy := str(farm._effective_policy_crop_id(state))
	for key in state.cells:
		var cell: Dictionary = state.cells[key]
		var crop = farm.get_crop(str(cell.get("crop_id", "")))
		if crop != null:
			cell = SIM.advance_cell(cell, crop.to_sim_profile(), elapsed)
		var eligible := str(state.crop_policy_id).is_empty() and str(cell.state) == SIM.STATE_TILLED and str(cell.crop_id).is_empty() and str(cell.get("requested_operation", "")).is_empty()
		cell = SIM.advance_soil_recovery(cell, int(state.last_simulated_minute), minute, eligible, farm.SOIL_RECOVERY_MINUTES)
		cell = farm._with_field_policy_request(cell, policy, true)
		state.cells[key] = cell
	state.last_simulated_minute = minute
	state.state_revision = int(state.state_revision) + 1
	return state

func _test_ledger(gecs: Node, context: BootstrapContext, scene: Node) -> void:
	var population = load("res://features/world_sim/sim/population/population_controller.gd").new()
	scene.add_child(population)
	population._context = context
	for i in 4:
		gecs.upsert_population_record({"actor_id": "ledger.%d" % i, "settlement_id": "town", "role_id": "guard" if i == 1 else "resident", "assignments": {"residence": "bed"} if i == 2 else {}, "realization_state": "realized" if i == 3 else "ledger", "inventory_entries": [], "birth_day_index": -10000})
	population.refresh_from_gecs_state()
	for minute in [359, 360, 1319, 1320, 1440]:
		var expected: Dictionary = gecs.get_population_records()
		var narrow: Dictionary = gecs.get_population_ledger_records()
		for id in narrow:
			for key in narrow[id]:
				_expect(narrow[id][key] == expected[id].get(key), "ledger projection matches authoritative %s/%s" % [id, key])
		population.advance_ledger_minutes(1, minute)
		for id in expected:
			var record: Dictionary = expected[id]
			var activity: String = population._ledger_activity_for_record(record, minute)
			if record.realization_state != "realized":
				record.ledger_minutes_elapsed += 1
				record.ledger_activity_minutes[activity] = int(record.ledger_activity_minutes.get(activity, 0)) + 1
				if activity == "working": record.ledger_work_minutes += 1
				if activity == "resting": record.ledger_rest_minutes += 1
			if record.realization_state != "realized" or record.ledger_activity_state != activity:
				record.ledger_activity_state = activity
				record.last_ledger_absolute_minute = minute
			_expect(gecs.get_population_record(id) == record, "full ledger record preserved at %d/%s" % [minute, id])

func _expect(ok: bool, message: String) -> void:
	if not ok and failures.size() < 20:
		failures.append(message)
