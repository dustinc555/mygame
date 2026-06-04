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
var nest_controller: Node
var _initialized := false

const CONTROLLER_STATE_SPECS := [
	{"key": "world_time", "property": "world_time", "sync_method": "sync_world_time_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "settlements", "property": "settlement_controller", "refresh_method": "refresh_from_gecs_state"},
	{"key": "squads", "property": "world_squad_controller", "sync_method": "sync_world_squad_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "population", "property": "population_controller", "sync_method": "sync_population_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "ai_scheduler", "property": "ai_scheduler_controller", "sync_method": "sync_ai_scheduler_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "actor_query", "property": "actor_query_controller"},
	{"key": "population_realization", "property": "population_realization_controller", "sync_method": "sync_population_realization_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "ledger_simulation", "property": "ledger_simulation_controller", "sync_method": "sync_ledger_simulation_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "factions", "property": "faction_controller", "sync_method": "sync_faction_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "law_order", "property": "law_order_controller", "sync_method": "sync_law_order_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "world_events", "property": "world_event_choice_controller", "sync_method": "sync_world_event_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "job_system", "property": "job_system_controller", "sync_method": "sync_job_system_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "nests", "property": "nest_controller", "sync_method": "sync_nest_state", "refresh_method": "refresh_from_gecs_state"},
	{"key": "territories", "property": "territory_controller"},
	{"key": "roads", "property": "road_controller"},
]


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
		"set_hour":
			var hour := int(parts[1]) if parts.size() > 1 else 0
			var minute := int(parts[2]) if parts.size() > 2 else 0
			if world_time != null and world_time.has_method("set_time_of_day"):
				world_time.call("set_time_of_day", hour, minute)
				return "Time set to %s" % str(world_time.call("format_time"))
			return "World time is not available"
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
	var state := {"gecs": _gecs_state_snapshot()}
	for spec in CONTROLLER_STATE_SPECS:
		state[str(spec["key"])] = _serialize_controller_state(_controller_from_spec(spec))
	return state


func apply_serialized_state(state: Dictionary) -> void:
	_try_initialize()
	for spec in CONTROLLER_STATE_SPECS:
		_apply_controller_state(_controller_from_spec(spec), state.get(str(spec["key"]), {}))


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
	nest_controller = get_parent().get_node_or_null("NestController")
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


func _serialize_controller_state(controller: Node) -> Dictionary:
	if controller == null or not controller.has_method("serialize_state"):
		return {}
	var controller_state = controller.call("serialize_state")
	return controller_state if controller_state is Dictionary else {}


func _controller_from_spec(spec: Dictionary) -> Node:
	return get(str(spec.get("property", ""))) as Node


func _gecs_state_snapshot() -> Dictionary:
	if gecs_world_controller != null and gecs_world_controller.has_method("serialize_state"):
		return gecs_world_controller.call("serialize_state")
	return {}


func _call_controller_method(controller: Node, method_name: String) -> void:
	if controller != null and not method_name.is_empty() and controller.has_method(method_name):
		controller.call(method_name)


func _sync_controller_states_for_save() -> void:
	for spec in CONTROLLER_STATE_SPECS:
		_call_controller_method(_controller_from_spec(spec), str(spec.get("sync_method", "")))


func _refresh_controller_states_from_gecs() -> void:
	for spec in CONTROLLER_STATE_SPECS:
		_call_controller_method(_controller_from_spec(spec), str(spec.get("refresh_method", "")))


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
