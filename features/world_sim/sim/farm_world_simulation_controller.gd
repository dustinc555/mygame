extends Node

class_name FarmWorldSimulationController

const SERVICE_ID := &"farm_world_simulation"
## One assigned farmer contributes a small coarse labor budget per world minute.
## This is intentionally cheap world truth, not projected NPC playback.
const WORK_SECONDS_PER_FARMER_WORLD_MINUTE := 0.08

var root_scene: Node
var farm_controller: Node
var settlement_controller: Node
var population_controller: Node
var _context: BootstrapContext
var _initialized := false
var _last_summary: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	_try_initialize()


func _ready() -> void:
	add_to_group("farm_world_simulation_controller")
	_try_initialize()


func get_last_summary() -> Dictionary:
	return _last_summary.duplicate(true)


## Cheap world-sim entry point. Cost scales with settlements and changed farm
## cells, never elapsed minute replay or live NPC count.
func advance_world_sim_minutes(elapsed_world_minutes: int) -> Dictionary:
	var summary := {
		"elapsed_world_minutes": maxi(elapsed_world_minutes, 0),
		"eligible_settlements": 0,
		"advanced_settlements": 0,
		"assigned_farmers": 0,
		"completed_actions": 0,
		"changed_cells": 0,
		"consumed_seeds": 0,
		"stored_produce": 0,
	}
	if elapsed_world_minutes <= 0 or farm_controller == null or settlement_controller == null:
		_last_summary = summary
		return summary
	var states: Array = settlement_controller.call("get_world_sim_labor_snapshots") \
			if settlement_controller.has_method("get_world_sim_labor_snapshots") \
			else settlement_controller.call("get_all_settlement_states") if settlement_controller.has_method("get_all_settlement_states") else []
	var labor_by_settlement: Dictionary = {}
	for state_value in states:
		if not (state_value is Dictionary):
			continue
		var state: Dictionary = state_value
		var settlement_id := str(state.get("settlement_id", ""))
		var farmer_ids := _farm_worker_ids(state)
		if settlement_id.is_empty() or farmer_ids.is_empty():
			continue
		summary["eligible_settlements"] = int(summary["eligible_settlements"]) + 1
		summary["assigned_farmers"] = int(summary["assigned_farmers"]) + farmer_ids.size()
		if _any_worker_realized(farmer_ids):
			continue
		labor_by_settlement[settlement_id] = float(elapsed_world_minutes) * float(farmer_ids.size()) * WORK_SECONDS_PER_FARMER_WORLD_MINUTE
	var plots_snapshot: Dictionary = farm_controller.call("get_plots") \
			if not labor_by_settlement.is_empty() and farm_controller.has_method("get_plots") else {}
	for settlement_id_value in labor_by_settlement.keys():
		var settlement_id := str(settlement_id_value)
		var result: Dictionary = farm_controller.call(
			"advance_world_sim_work",
			settlement_id,
			float(labor_by_settlement[settlement_id_value]),
			plots_snapshot
		) if farm_controller.has_method("advance_world_sim_work") else {}
		if int(result.get("changed_cells", 0)) <= 0:
			continue
		summary["advanced_settlements"] = int(summary["advanced_settlements"]) + 1
		summary["completed_actions"] = int(summary["completed_actions"]) + int(result.get("completed_actions", 0))
		summary["changed_cells"] = int(summary["changed_cells"]) + int(result.get("changed_cells", 0))
		summary["consumed_seeds"] = int(summary["consumed_seeds"]) + int(result.get("consumed_seeds", 0))
		summary["stored_produce"] = int(summary["stored_produce"]) + int(result.get("stored_produce", 0))
	_last_summary = summary
	return summary.duplicate(true)


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree() or _context == null:
		return
	farm_controller = _context.get_optional(&"farming")
	settlement_controller = _context.get_optional(&"settlement")
	population_controller = _context.get_optional(&"population")
	var world_time := _context.get_optional(&"world_time")
	if farm_controller == null or settlement_controller == null or world_time == null:
		return
	if world_time.has_signal("hour_changed"):
		var callback := Callable(self, "_on_hour_changed")
		if not world_time.is_connected("hour_changed", callback):
			world_time.connect("hour_changed", callback)
	_initialized = true


func _on_hour_changed(_absolute_hour: int, _day_index: int, _hour: int) -> void:
	advance_world_sim_minutes(60)


func _farm_worker_ids(state: Dictionary) -> PackedStringArray:
	var actor_ids := PackedStringArray()
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		if not (slot_value is Dictionary):
			continue
		var slot: Dictionary = slot_value
		var allowed := PackedStringArray(slot.get("allowed_job_entry_ids", PackedStringArray()))
		var actor_id := str(slot.get("occupant_actor_id", ""))
		if str(slot.get("assignment_domain", "")) == "employment" \
				and bool(slot.get("filled", false)) \
				and bool(slot.get("uses_settlement_jobs", false)) \
				and allowed.has("category:farm") \
				and not actor_id.is_empty():
			actor_ids.append(actor_id)
	return actor_ids


func _any_worker_realized(actor_ids: PackedStringArray) -> bool:
	if population_controller == null or not population_controller.has_method("get_live_actor"):
		return false
	for actor_id in actor_ids:
		var actor = population_controller.call("get_live_actor", actor_id)
		if actor != null and is_instance_valid(actor):
			return true
	return false
