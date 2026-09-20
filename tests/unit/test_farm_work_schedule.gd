extends GutTest
## Exercise coarse labor budgets without starting an engine world.

const CONTROLLER = preload("res://features/world_sim/sim/farm_world_simulation_controller.gd")

class FarmProvider extends Node:
	var budgets: Array[float] = []
	var plot_reads := 0
	func get_plots() -> Dictionary:
		plot_reads += 1
		return {}
	func advance_world_sim_cycle(_id: String, _faction: String, seconds: float, _plots: Dictionary) -> Dictionary:
		budgets.append(seconds)
		return {"changed_cells": 1, "completed_actions": 1}

class SettlementProvider extends Node:
	var slots: Dictionary = {}
	func get_world_sim_labor_snapshots() -> Array:
		return [{"settlement_id": "town", "faction_id": "town", "assignment_slots": slots}]

class Clock extends Node:
	var minute := 0
	func get_absolute_minute() -> int:
		return minute

class PopulationProvider extends Node:
	var live_actor: Node
	func get_live_actor(_id: String) -> Node:
		return live_actor

var controller: Node
var farm: FarmProvider
var settlement: SettlementProvider
var clock: Clock

func before_each() -> void:
	controller = autofree(CONTROLLER.new())
	farm = autofree(FarmProvider.new())
	settlement = autofree(SettlementProvider.new())
	clock = autofree(Clock.new())
	var context := BootstrapContext.new()
	context.register(&"world_time", clock)
	controller.initialize(context)
	controller.farm_controller = farm
	controller.settlement_controller = settlement
	settlement.slots = {"farmer": _slot("farmer")}

func _slot(actor_id: String, schedule: Dictionary = {}) -> Dictionary:
	var slot := {
		"assignment_domain": "employment", "filled": true,
		"uses_settlement_jobs": true, "allowed_job_entry_ids": ["category:farm"],
		"occupant_actor_id": actor_id,
	}
	if not schedule.is_empty():
		slot["work_schedule"] = schedule
	return slot

func test_night_produces_no_labor_or_farm_scan() -> void:
	clock.minute = 7 * 60
	controller.advance_world_sim_minutes(60)
	assert_eq(farm.budgets.size(), 0, "Default farmers do not work before 08:00")
	assert_eq(farm.plot_reads, 0, "No farm scan with zero scheduled labor")

func test_replayed_hours_use_each_signal_boundary_not_final_clock() -> void:
	clock.minute = 22 * 60
	controller._on_hour_changed(8, 0, 8)
	assert_eq(farm.budgets.size(), 0, "07:00–08:00 is off shift")
	controller._on_hour_changed(9, 0, 9)
	assert_eq(farm.budgets.size(), 1, "08:00–09:00 still works when final clock is 22:00")
	if not farm.budgets.is_empty():
		assert_almost_eq(farm.budgets[0], 4.8, 0.000001)
	controller._on_hour_changed(20, 0, 20)
	assert_eq(farm.budgets.size(), 2, "19:00–20:00 includes the final working hour")
	controller._on_hour_changed(21, 0, 21)
	assert_eq(farm.budgets.size(), 2, "20:00–21:00 is off shift")

func test_partial_shift_overlap_uses_context_clock() -> void:
	clock.minute = 8 * 60 + 15
	controller.advance_world_sim_minutes(30)
	assert_eq(farm.budgets.size(), 1)
	assert_almost_eq(farm.budgets[0], 15 * 0.08, 0.000001)
	farm.budgets.clear()
	clock.minute = 20 * 60 + 15
	controller.advance_world_sim_minutes(30)
	assert_eq(farm.budgets.size(), 1)
	assert_almost_eq(farm.budgets[0], 15 * 0.08, 0.000001)

func test_explicit_end_overrides_clock_and_duplicate_slots_count_once() -> void:
	clock.minute = 23 * 60
	settlement.slots["duplicate"] = _slot("farmer")
	var summary: Dictionary = controller.advance_world_sim_minutes(60, 9 * 60)
	assert_eq(summary.assigned_farmers, 1)
	assert_eq(farm.budgets.size(), 1)
	assert_almost_eq(farm.budgets[0], 60 * 0.08, 0.000001)

func test_authored_overnight_schedule_sums_both_sides_of_midnight() -> void:
	settlement.slots = {"night": _slot("night", {"start_hour": 22, "end_hour": 6})}
	controller.advance_world_sim_minutes(12 * 60, 1440 + 8 * 60)
	assert_eq(farm.budgets.size(), 1)
	assert_almost_eq(farm.budgets[0], 8 * 60 * 0.08, 0.000001)

func test_multiday_budget_sums_distinct_worker_schedules_without_replay() -> void:
	settlement.slots["night"] = _slot("night", {"start_hour": 22, "end_hour": 6})
	# A huge elapsed interval still makes one farm mutation and one plot read.
	var days := 1000000
	controller.advance_world_sim_minutes(days * 1440, days * 1440)
	assert_eq(farm.budgets.size(), 1)
	assert_eq(farm.plot_reads, 1)
	assert_almost_eq(farm.budgets[0], days * (12 + 8) * 60 * 0.08, 0.001)

func test_authored_equal_endpoints_allow_round_the_clock_labor() -> void:
	settlement.slots = {"always": _slot("always", {"start_hour": 0, "end_hour": 0})}
	controller.advance_world_sim_minutes(1440, 1440)
	assert_almost_eq(farm.budgets[0], 1440 * 0.08, 0.000001)

func test_missing_clock_refuses_labor_but_explicit_end_allows_it() -> void:
	controller.initialize(BootstrapContext.new())
	var summary: Dictionary = controller.advance_world_sim_minutes(60)
	assert_eq(farm.budgets.size(), 0)
	assert_eq(summary.get("skipped_reason"), "missing_world_time")
	controller.advance_world_sim_minutes(60, 9 * 60)
	assert_eq(farm.budgets.size(), 1)
	assert_almost_eq(farm.budgets[0], 60 * 0.08, 0.000001)

func test_any_realized_farmer_still_prevents_coarse_labor() -> void:
	var population: PopulationProvider = autofree(PopulationProvider.new())
	population.live_actor = autofree(Node.new())
	controller.population_controller = population
	controller.advance_world_sim_minutes(60, 9 * 60)
	assert_eq(farm.budgets.size(), 0)
	assert_eq(farm.plot_reads, 0)

func test_ineligible_slots_and_nonpositive_elapsed_never_add_labor() -> void:
	var not_farm := _slot("miner")
	not_farm.allowed_job_entry_ids = ["category:mine"]
	var unfilled := _slot("unfilled")
	unfilled.filled = false
	var not_employment := _slot("resident")
	not_employment.assignment_domain = "residence"
	var not_settlement := _slot("private")
	not_settlement.uses_settlement_jobs = false
	settlement.slots = {"miner": not_farm, "unfilled": unfilled,
		"resident": not_employment, "private": not_settlement, "empty": _slot("")}
	controller.advance_world_sim_minutes(60, 9 * 60)
	assert_eq(farm.budgets.size(), 0)
	settlement.slots = {"farmer": _slot("farmer")}
	controller.advance_world_sim_minutes(0, 9 * 60)
	controller.advance_world_sim_minutes(-60, 9 * 60)
	assert_eq(farm.budgets.size(), 0)
