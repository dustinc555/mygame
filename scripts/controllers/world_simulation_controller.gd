extends Node

class_name WorldSimulationController

var root_scene: Node
var world_time: Node
var settlement_controller: Node
var territory_controller: Node
var road_controller: Node
var world_squad_controller: Node
var population_controller: Node
var ai_scheduler_controller: Node
var actor_query_controller: Node
var gecs_world_controller: Node
var population_realization_controller: Node
var ledger_simulation_controller: Node
var faction_controller: Node
var law_order_controller: Node
var world_event_choice_controller: Node
var job_system_controller: Node
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("world_simulation_controller")
	_try_initialize()


func get_summary_text() -> String:
	if settlement_controller == null:
		return "World: Stable"
	return settlement_controller.get_summary_text()


func perform_world_sim_debug_action(action_key: String) -> String:
	if action_key.is_empty():
		return "No action configured"
	var parts := action_key.split(":")
	match parts[0]:
		"advance_hours":
			var hours := float(parts[1]) if parts.size() > 1 else 1.0
			if world_time != null and world_time.has_method("advance_hours"):
				world_time.call("advance_hours", hours)
			return "Advanced %.0f hour(s)" % hours
		"advance_days":
			var days := float(parts[1]) if parts.size() > 1 else 1.0
			if world_time != null and world_time.has_method("advance_days"):
				world_time.call("advance_days", days)
			return "Advanced %.0f day(s)" % days
		"adjust_food":
			if parts.size() < 3 or settlement_controller == null:
				return "Food action is misconfigured"
			var settlement_id := parts[1]
			var amount := float(parts[2])
			var food: float = float(settlement_controller.call("adjust_food", settlement_id, amount, "debug_action"))
			return "%s food is now %.0f" % [settlement_id, food]
		"set_food":
			if parts.size() < 3 or settlement_controller == null:
				return "Food action is misconfigured"
			var settlement_id := parts[1]
			var amount := float(parts[2])
			var food: float = float(settlement_controller.call("set_food", settlement_id, amount, "debug_action"))
			return "%s food is now %.0f" % [settlement_id, food]
		"set_occupancy":
			if parts.size() < 3 or settlement_controller == null or not settlement_controller.has_method("set_occupancy_state"):
				return "Occupancy action is misconfigured"
			var settlement_id := parts[1]
			var state: Dictionary = settlement_controller.call("set_occupancy_state", settlement_id, parts[2], "debug_action")
			if state.is_empty():
				return "Occupancy could not be changed"
			return "%s is %s (%d/%d)" % [settlement_id, state.get("occupancy_label", "Populated"), int(state.get("population", 0)), int(state.get("max_occupancy", 0))]
		"force_raid":
			if parts.size() < 3 or settlement_controller == null:
				return "Raid action is misconfigured"
			var started: bool = bool(settlement_controller.call("force_food_raid", parts[1], parts[2]))
			return "Raid started" if started else "Raid could not start"
		"toggle_faction_territories":
			if territory_controller != null and territory_controller.has_method("toggle_faction_territories_visible"):
				return str(territory_controller.call("toggle_faction_territories_visible"))
			return "Territory controller is not available"
		"toggle_town_borders":
			if territory_controller != null and territory_controller.has_method("toggle_town_borders_visible"):
				return str(territory_controller.call("toggle_town_borders_visible"))
			return "Territory controller is not available"
		"toggle_roads":
			if road_controller != null and road_controller.has_method("toggle_roads_visible"):
				return str(road_controller.call("toggle_roads_visible"))
			return "Road controller is not available"
		"population_summary":
			return _format_population_summary()
		"ledger_summary":
			return _format_ledger_summary()
		"actor_ai":
			return _format_actor_ai(parts[1] if parts.size() > 1 else "")
		_:
			return "Unknown world sim action"


func serialize_state() -> Dictionary:
	return {
		"gecs": gecs_world_controller.call("serialize_state") if gecs_world_controller != null and gecs_world_controller.has_method("serialize_state") else {},
		"world_time": world_time.call("serialize_state") if world_time != null and world_time.has_method("serialize_state") else {},
		"settlements": settlement_controller.call("serialize_state") if settlement_controller != null and settlement_controller.has_method("serialize_state") else {},
		"squads": world_squad_controller.call("serialize_state") if world_squad_controller != null and world_squad_controller.has_method("serialize_state") else {},
		"population": population_controller.call("serialize_state") if population_controller != null and population_controller.has_method("serialize_state") else {},
		"ai_scheduler": ai_scheduler_controller.call("serialize_state") if ai_scheduler_controller != null and ai_scheduler_controller.has_method("serialize_state") else {},
		"actor_query": actor_query_controller.call("serialize_state") if actor_query_controller != null and actor_query_controller.has_method("serialize_state") else {},
		"population_realization": population_realization_controller.call("serialize_state") if population_realization_controller != null and population_realization_controller.has_method("serialize_state") else {},
		"ledger_simulation": ledger_simulation_controller.call("serialize_state") if ledger_simulation_controller != null and ledger_simulation_controller.has_method("serialize_state") else {},
		"factions": faction_controller.call("serialize_state") if faction_controller != null and faction_controller.has_method("serialize_state") else {},
		"law_order": law_order_controller.call("serialize_state") if law_order_controller != null and law_order_controller.has_method("serialize_state") else {},
		"world_events": world_event_choice_controller.call("serialize_state") if world_event_choice_controller != null and world_event_choice_controller.has_method("serialize_state") else {},
		"job_system": job_system_controller.call("serialize_state") if job_system_controller != null and job_system_controller.has_method("serialize_state") else {},
		"territories": territory_controller.call("serialize_state") if territory_controller != null and territory_controller.has_method("serialize_state") else {},
		"roads": road_controller.call("serialize_state") if road_controller != null and road_controller.has_method("serialize_state") else {},
	}


func apply_serialized_state(state: Dictionary) -> void:
	_try_initialize()
	_apply_controller_state(world_time, state.get("world_time", {}))
	_apply_controller_state(settlement_controller, state.get("settlements", {}))
	_apply_controller_state(world_squad_controller, state.get("squads", {}))
	_apply_controller_state(population_controller, state.get("population", {}))
	_apply_controller_state(ai_scheduler_controller, state.get("ai_scheduler", {}))
	_apply_controller_state(population_realization_controller, state.get("population_realization", {}))
	_apply_controller_state(ledger_simulation_controller, state.get("ledger_simulation", {}))
	_apply_controller_state(faction_controller, state.get("factions", {}))
	_apply_controller_state(law_order_controller, state.get("law_order", {}))
	_apply_controller_state(world_event_choice_controller, state.get("world_events", {}))
	_apply_controller_state(job_system_controller, state.get("job_system", {}))
	_apply_controller_state(territory_controller, state.get("territories", {}))
	_apply_controller_state(road_controller, state.get("roads", {}))


func save_world_to_file(path: String, binary := false) -> bool:
	_try_initialize()
	_sync_controller_states_for_save()
	return bool(gecs_world_controller.call("save_gecs_world", path, binary)) if gecs_world_controller != null and gecs_world_controller.has_method("save_gecs_world") else false


func load_world_from_file(path: String) -> bool:
	_try_initialize()
	var loaded := bool(gecs_world_controller.call("load_gecs_world", path)) if gecs_world_controller != null and gecs_world_controller.has_method("load_gecs_world") else false
	if loaded:
		_refresh_controller_states_from_gecs()
	return loaded


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	world_time = get_parent().get_node_or_null("WorldTimeController")
	settlement_controller = get_parent().get_node_or_null("SettlementController")
	territory_controller = get_parent().get_node_or_null("TerritoryController")
	road_controller = get_parent().get_node_or_null("RoadController")
	world_squad_controller = get_parent().get_node_or_null("WorldSquadController")
	population_controller = get_parent().get_node_or_null("PopulationController")
	ai_scheduler_controller = get_parent().get_node_or_null("AiSchedulerController")
	actor_query_controller = get_parent().get_node_or_null("ActorQueryController")
	gecs_world_controller = get_parent().get_node_or_null("GecsWorldController")
	population_realization_controller = get_parent().get_node_or_null("PopulationRealizationController")
	ledger_simulation_controller = get_parent().get_node_or_null("LedgerSimulationController")
	faction_controller = get_parent().get_node_or_null("FactionController")
	law_order_controller = get_parent().get_node_or_null("LawOrderController")
	world_event_choice_controller = get_parent().get_node_or_null("WorldEventChoiceController")
	job_system_controller = get_parent().get_node_or_null("JobSystemController")
	if world_time == null or settlement_controller == null or world_squad_controller == null:
		return
	var action_requested_callable := Callable(self, "_on_settlement_action_requested")
	if settlement_controller.has_signal("settlement_action_requested") and not settlement_controller.is_connected("settlement_action_requested", action_requested_callable):
		settlement_controller.connect("settlement_action_requested", action_requested_callable)
	_initialized = true


func _on_settlement_action_requested(action_record: Dictionary) -> void:
	if world_squad_controller != null and world_squad_controller.has_method("start_action"):
		world_squad_controller.call("start_action", action_record)


func _apply_controller_state(controller: Node, state_value) -> void:
	if controller != null and controller.has_method("apply_serialized_state") and state_value is Dictionary:
		controller.call("apply_serialized_state", state_value)


func _sync_controller_states_for_save() -> void:
	for controller in [
		world_time,
		settlement_controller,
		world_squad_controller,
		population_controller,
		ai_scheduler_controller,
		population_realization_controller,
		ledger_simulation_controller,
		faction_controller,
		law_order_controller,
		world_event_choice_controller,
		job_system_controller,
	]:
		if controller == null:
			continue
		for method_name in [
			"sync_population_state",
			"sync_world_time_state",
			"sync_world_squad_state",
			"sync_ai_scheduler_state",
			"sync_population_realization_state",
			"sync_faction_state",
			"sync_law_order_state",
			"sync_world_event_state",
			"sync_job_system_state",
			"sync_ledger_simulation_state",
		]:
			if controller.has_method(method_name):
				controller.call(method_name)


func _refresh_controller_states_from_gecs() -> void:
	for controller in [
		world_time,
		settlement_controller,
		world_squad_controller,
		population_controller,
		ai_scheduler_controller,
		population_realization_controller,
		ledger_simulation_controller,
		faction_controller,
		law_order_controller,
		world_event_choice_controller,
		job_system_controller,
	]:
		if controller != null and controller.has_method("refresh_from_gecs_state"):
			controller.call("refresh_from_gecs_state")


func _format_population_summary() -> String:
	if population_controller == null or not population_controller.has_method("get_population_summary"):
		return "Population controller is not available"
	var summary: Dictionary = population_controller.call("get_population_summary")
	return "Population records=%d realized=%d ledger=%d settlements=%s roles=%s" % [
		int(summary.get("total_records", 0)),
		int(summary.get("realized_records", 0)),
		int(summary.get("ledger_records", 0)),
		str(summary.get("by_settlement", {})),
		str(summary.get("by_role", {})),
	]


func _format_ledger_summary() -> String:
	if ledger_simulation_controller == null or not ledger_simulation_controller.has_method("get_debug_summary"):
		return "Ledger simulation controller is not available"
	var summary: Dictionary = ledger_simulation_controller.call("get_debug_summary")
	return "Ledger elapsed=%d updated=%d batches=%s" % [
		int(summary.get("elapsed_minutes", 0)),
		int(summary.get("updated_actor_count", 0)),
		str(summary.get("batches", {})),
	]


func _format_actor_ai(actor_id: String) -> String:
	if actor_id.strip_edges().is_empty():
		return "Actor id is required"
	if actor_query_controller == null or not actor_query_controller.has_method("get_actor_by_stable_id"):
		return "Actor query controller is not available"
	var actor := actor_query_controller.call("get_actor_by_stable_id", actor_id) as Node
	if actor == null:
		return "Actor %s is not realized" % actor_id
	if actor.has_method("get_ai_debug_snapshot"):
		return str(actor.call("get_ai_debug_snapshot"))
	return "Actor %s has no AI debug snapshot" % actor_id
