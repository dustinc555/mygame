extends Node

class_name LedgerSimulationController

const SERVICE_ID := &"ledger_simulation"

var root_scene: Node
var _context: BootstrapContext
var world_time: Node
var population_controller: Node
var _last_processed_minute := -1
var _last_batch_summary: Dictionary = {}
var _initialized := false


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_context = context
	_try_initialize()


func _ready() -> void:
	add_to_group("ledger_simulation_controller")
	_try_initialize()


func serialize_state() -> Dictionary:
	_sync_ledger_simulation_state_to_gecs()
	return _current_ledger_simulation_state()


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty():
		refresh_from_gecs_state()
		return
	_last_processed_minute = int(state.get("last_processed_minute", _last_processed_minute))
	_last_batch_summary = (state.get("last_batch_summary", {}) as Dictionary).duplicate(true)
	_sync_ledger_simulation_state_to_gecs()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_ledger_simulation_state"):
		return
	var state: Dictionary = bridge.call("get_ledger_simulation_state")
	if state.is_empty():
		return
	_last_processed_minute = int(state.get("last_processed_minute", _last_processed_minute))
	_last_batch_summary = (state.get("last_batch_summary", {}) as Dictionary).duplicate(true)


func sync_ledger_simulation_state() -> void:
	_sync_ledger_simulation_state_to_gecs()


func get_debug_summary() -> Dictionary:
	return _last_batch_summary.duplicate(true)


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	if _context == null:
		return
	world_time = _context.get_optional(WorldTimeController.SERVICE_ID)
	population_controller = _context.get_optional(PopulationController.SERVICE_ID)
	if world_time == null:
		return
	if world_time.has_signal("minute_changed"):
		var callable := Callable(self, "_on_minute_changed")
		if not world_time.is_connected("minute_changed", callable):
			world_time.connect("minute_changed", callable)
	refresh_from_gecs_state()
	_initialized = true


func _on_minute_changed(absolute_minute: int, _day_index: int, _hour: int, _minute: int) -> void:
	if _last_processed_minute < 0:
		_last_processed_minute = absolute_minute
		_sync_ledger_simulation_state_to_gecs()
		return
	var elapsed: int = max(0, absolute_minute - _last_processed_minute)
	_last_processed_minute = absolute_minute
	if elapsed <= 0:
		_sync_ledger_simulation_state_to_gecs()
		return
	if population_controller != null and population_controller.has_method("advance_ledger_minutes"):
		_last_batch_summary = population_controller.call("advance_ledger_minutes", elapsed, absolute_minute)
	_sync_ledger_simulation_state_to_gecs()


func _current_ledger_simulation_state() -> Dictionary:
	return {
		"state_id": "ledger_simulation",
		"last_processed_minute": _last_processed_minute,
		"last_batch_summary": _last_batch_summary.duplicate(true),
	}


func _sync_ledger_simulation_state_to_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_ledger_simulation_state"):
		bridge.call("upsert_ledger_simulation_state", _current_ledger_simulation_state())


func _get_gecs_world() -> Node:
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null
