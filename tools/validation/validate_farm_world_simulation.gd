extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farm_world_simulation.gd

const CONTROLLER_PATH := "res://features/world_sim/sim/farm_world_simulation_controller.gd"

class FakeFarm:
	extends Node
	var calls: Array[Dictionary] = []
	var plot_reads := 0
	func get_plots() -> Dictionary:
		plot_reads += 1
		return {"snapshot": {}}
	func advance_world_sim_work(settlement_id: String, labor_seconds: float, _plots_snapshot := {}) -> Dictionary:
		calls.append({"settlement_id": settlement_id, "labor_seconds": labor_seconds})
		return {"completed_actions": int(floor(labor_seconds)), "changed_cells": 1}

class FakeSettlements:
	extends Node
	var states: Array[Dictionary] = []
	func get_all_settlement_states() -> Array[Dictionary]:
		return states.duplicate(true)

class FakePopulation:
	extends Node
	var live_actor_ids: Dictionary = {}
	func get_live_actor(actor_id: String) -> Node:
		return self if live_actor_ids.has(actor_id) else null

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script := load(CONTROLLER_PATH) as Script
	_expect(script != null and script.can_instantiate(), "world sim owns an instantiable farm progression controller")
	if script == null or not script.can_instantiate():
		_finish()
		return
	var controller: Node = script.new()
	var farm := FakeFarm.new()
	var settlements := FakeSettlements.new()
	var population := FakePopulation.new()
	root.add_child(controller)
	root.add_child(farm)
	root.add_child(settlements)
	root.add_child(population)
	controller.set("farm_controller", farm)
	controller.set("settlement_controller", settlements)
	controller.set("population_controller", population)
	settlements.states = [_town_state("farmer.a", "farmer.b", "farmer.c")]
	var first: Dictionary = controller.call("advance_world_sim_minutes", 60)
	_expect(farm.calls.size() == 1 and str(farm.calls[0].get("settlement_id", "")) == "town", "unrealized town fields advance through world sim")
	_expect(is_equal_approx(float(farm.calls[0].get("labor_seconds", 0.0)), 14.4), "three durable farmers contribute one cheap aggregate labor budget")
	_expect(int(first.get("advanced_settlements", 0)) == 1, "world sim reports its changed-town count for human inspection")
	farm.calls.clear()
	farm.plot_reads = 0
	settlements.states = [_town_state("farmer.a", "farmer.b", "farmer.c"), _town_state("farmer.d", "", "", "town2")]
	controller.call("advance_world_sim_minutes", 60)
	_expect(farm.calls.size() == 2 and farm.plot_reads == 1, "many towns share one farm snapshot instead of rebuilding every plot per town")
	farm.calls.clear()
	population.live_actor_ids["farmer.b"] = true
	settlements.states = [_town_state("farmer.a", "farmer.b", "farmer.c")]
	controller.call("advance_world_sim_minutes", 60)
	_expect(farm.calls.is_empty(), "any realized farmer hands the whole town back to projection simulation without double work")
	population.live_actor_ids.clear()
	settlements.states = [_town_state("", "", "")]
	controller.call("advance_world_sim_minutes", 60)
	_expect(farm.calls.is_empty(), "towns with no assigned farmers produce no farm labor")
	controller.free()
	farm.free()
	settlements.free()
	population.free()
	_finish()


func _town_state(first: String, second: String, third: String, settlement_id := "town") -> Dictionary:
	var slots := {}
	var index := 0
	for actor_id in [first, second, third]:
		if actor_id.is_empty():
			continue
		slots["employment:farmer.%d" % index] = {
			"assignment_domain": "employment",
			"filled": true,
			"uses_settlement_jobs": true,
			"occupant_actor_id": actor_id,
			"allowed_job_entry_ids": PackedStringArray(["category:farm", "category:haul"]),
		}
		index += 1
	return {"settlement_id": settlement_id, "assignment_slots": slots}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FARM_WORLD_SIMULATION_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARM_WORLD_SIMULATION_FAILED count=%d" % failures.size())
	quit(1)
