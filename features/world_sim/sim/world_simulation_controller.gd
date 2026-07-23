extends Node

class_name WorldSimulationController

const SERVICE_ID := &"world_simulation"
const DEBUG_FOOD := preload("res://features/inventory/resources/items/food.tres")

var root_scene: Node
var world_time: WorldTimeController
var settlement_controller: SettlementController
var territory_controller: TerritoryController
var road_controller: RoadController
var world_sim_squad_controller: WorldSimSquadController
var population_controller: PopulationController
var ai_scheduler_controller: AiSchedulerController
var actor_query_controller: ActorQueryController
var gecs_world_controller: GecsWorldController
var population_realization_controller: PopulationRealizationController
var ledger_simulation_controller: LedgerSimulationController
var faction_controller: FactionController
var law_order_controller: LawOrderController
var world_event_choice_controller: WorldEventChoiceController
var job_system_controller: JobSystemController
var nest_world_sim_plugin: NestWorldSimPlugin
var _context: BootstrapContext
var _initialized := false


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_context = context
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
			if world_time != null:
				world_time.advance_hours(hours)
			return "Advanced %.0f hour(s)" % hours
		"advance_days":
			var days := float(parts[1]) if parts.size() > 1 else 1.0
			if world_time != null:
				world_time.advance_days(days)
			return "Advanced %.0f day(s)" % days
		"set_hour":
			var hour := int(parts[1]) if parts.size() > 1 else 0
			var minute := int(parts[2]) if parts.size() > 2 else 0
			if world_time != null:
				world_time.set_time_of_day(hour, minute)
				return "Time set to %s" % world_time.format_time()
			return "World time is not available"
		"add_food_items":
			if parts.size() < 3:
				return "Food action is misconfigured"
			var settlement_id := parts[1]
			var count := int(parts[2])
			var stock := _context.get_optional(InventoryStockController.SERVICE_ID) as InventoryStockController
			var changed := stock.transact_item_count(settlement_id, DEBUG_FOOD, count) if stock != null else false
			return "%s food item transaction: %s" % [settlement_id, "ok" if changed else "rejected"]
		"clear_food":
			if parts.size() < 2:
				return "Food action is misconfigured"
			var settlement_id := parts[1]
			var stock := _context.get_optional(InventoryStockController.SERVICE_ID) as InventoryStockController
			var available := stock.get_total_food_units(settlement_id) if stock != null else 0.0
			var removed := stock.consume_food_units(settlement_id, available) if stock != null else {}
			return "%s removed %.1f food units" % [settlement_id, float(removed.get("food_units", 0.0))]
		"set_occupancy":
			if parts.size() < 3 or settlement_controller == null:
				return "Occupancy action is misconfigured"
			var settlement_id := parts[1]
			var state := settlement_controller.set_occupancy_state(settlement_id, parts[2], "debug_action")
			if state.is_empty():
				return "Occupancy could not be changed"
			return "%s is %s (%d/%d)" % [settlement_id, state.get("occupancy_label", "Populated"), int(state.get("population", 0)), int(state.get("max_occupancy", 0))]
		"force_raid", "force_demand_tribute_raid":
			var faction_sim: FactionWorldSimController = _context.get_optional(FactionWorldSimController.SERVICE_ID) if _context != null else null
			if faction_sim != null:
				return faction_sim.force_demand_tribute_raid()
			return "World-sim faction brain is not available"
		"toggle_faction_territories":
			if territory_controller != null:
				return territory_controller.toggle_faction_territories_visible()
			return "Territory controller is not available"
		"toggle_town_borders":
			if territory_controller != null:
				return territory_controller.toggle_town_borders_visible()
			return "Territory controller is not available"
		"toggle_roads":
			if road_controller != null:
				return road_controller.toggle_roads_visible()
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
		"gecs": gecs_world_controller.serialize_state() if gecs_world_controller != null else {},
		"world_time": world_time.serialize_state() if world_time != null else {},
		"settlements": settlement_controller.serialize_state() if settlement_controller != null else {},
		"population": population_controller.serialize_state() if population_controller != null else {},
		"ai_scheduler": ai_scheduler_controller.serialize_state() if ai_scheduler_controller != null else {},
		"actor_query": actor_query_controller.serialize_state() if actor_query_controller != null else {},
		"population_realization": population_realization_controller.serialize_state() if population_realization_controller != null else {},
		"ledger_simulation": ledger_simulation_controller.serialize_state() if ledger_simulation_controller != null else {},
		"factions": faction_controller.serialize_state() if faction_controller != null else {},
		"law_order": law_order_controller.serialize_state() if law_order_controller != null else {},
		"world_events": world_event_choice_controller.serialize_state() if world_event_choice_controller != null else {},
		"job_system": job_system_controller.serialize_state() if job_system_controller != null else {},
		"nests": nest_world_sim_plugin.serialize_state() if nest_world_sim_plugin != null else {},
		"territories": territory_controller.serialize_state() if territory_controller != null else {},
		"roads": road_controller.serialize_state() if road_controller != null else {},
	}


# Settlements, actor query, territories, and roads serialize snapshots but have no
# apply path; on load they rebuild from GECS instead (see _refresh_controller_states_from_gecs).
func apply_serialized_state(state: Dictionary) -> void:
	_try_initialize()
	if world_time != null:
		world_time.apply_serialized_state(_state_dict(state, "world_time"))
	if population_controller != null:
		population_controller.apply_serialized_state(_state_dict(state, "population"))
	if ai_scheduler_controller != null:
		ai_scheduler_controller.apply_serialized_state(_state_dict(state, "ai_scheduler"))
	if population_realization_controller != null:
		population_realization_controller.apply_serialized_state(_state_dict(state, "population_realization"))
	if ledger_simulation_controller != null:
		ledger_simulation_controller.apply_serialized_state(_state_dict(state, "ledger_simulation"))
	if faction_controller != null:
		faction_controller.apply_serialized_state(_state_dict(state, "factions"))
	if law_order_controller != null:
		law_order_controller.apply_serialized_state(_state_dict(state, "law_order"))
	if world_event_choice_controller != null:
		world_event_choice_controller.apply_serialized_state(_state_dict(state, "world_events"))
	if job_system_controller != null:
		job_system_controller.apply_serialized_state(_state_dict(state, "job_system"))
	if nest_world_sim_plugin != null:
		nest_world_sim_plugin.apply_serialized_state(_state_dict(state, "nests"))


func save_world_to_file(path: String, binary := false) -> bool:
	_try_initialize()
	if gecs_world_controller == null:
		return false
	_sync_controller_states_for_save()
	return gecs_world_controller.save_gecs_world(path, binary)


func load_world_from_file(path: String) -> bool:
	_try_initialize()
	if gecs_world_controller == null:
		return false
	var loaded := gecs_world_controller.load_gecs_world(path)
	if loaded:
		_refresh_controller_states_from_gecs()
	return loaded


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	if _context == null:
		return
	world_time = _context.get_optional(WorldTimeController.SERVICE_ID)
	settlement_controller = _context.get_optional(SettlementController.SERVICE_ID)
	territory_controller = _context.get_optional(TerritoryController.SERVICE_ID)
	road_controller = _context.get_optional(RoadController.SERVICE_ID)
	world_sim_squad_controller = _context.get_optional(WorldSimSquadController.SERVICE_ID)
	population_controller = _context.get_optional(PopulationController.SERVICE_ID)
	ai_scheduler_controller = _context.get_optional(AiSchedulerController.SERVICE_ID)
	actor_query_controller = _context.get_optional(ActorQueryController.SERVICE_ID)
	gecs_world_controller = _context.get_optional(GecsWorldController.SERVICE_ID)
	population_realization_controller = _context.get_optional(PopulationRealizationController.SERVICE_ID)
	ledger_simulation_controller = _context.get_optional(LedgerSimulationController.SERVICE_ID)
	faction_controller = _context.get_optional(FactionController.SERVICE_ID)
	law_order_controller = _context.get_optional(LawOrderController.SERVICE_ID)
	world_event_choice_controller = _context.get_optional(WorldEventChoiceController.SERVICE_ID)
	job_system_controller = _context.get_optional(JobSystemController.SERVICE_ID)
	if world_time == null or settlement_controller == null:
		return
	if not _ensure_world_sim_plugins():
		return
	_initialized = true


func _ensure_world_sim_plugins() -> bool:
	if world_sim_squad_controller == null:
		return false
	nest_world_sim_plugin = world_sim_squad_controller.get_world_sim_plugin("nests") as NestWorldSimPlugin
	if nest_world_sim_plugin == null:
		nest_world_sim_plugin = NestWorldSimPlugin.new()
		nest_world_sim_plugin.name = "NestWorldSimPlugin"
		nest_world_sim_plugin.initialize(_context)
		world_sim_squad_controller.add_child(nest_world_sim_plugin)
	world_sim_squad_controller.register_world_sim_plugin(nest_world_sim_plugin)
	return true


func _state_dict(state: Dictionary, key: String) -> Dictionary:
	var value = state.get(key, {})
	return value if value is Dictionary else {}


func _sync_controller_states_for_save() -> void:
	if world_time != null:
		world_time.sync_world_time_state()
	if population_controller != null:
		population_controller.sync_population_state()
	if ai_scheduler_controller != null:
		ai_scheduler_controller.sync_ai_scheduler_state()
	if population_realization_controller != null:
		population_realization_controller.sync_population_realization_state()
	if ledger_simulation_controller != null:
		ledger_simulation_controller.sync_ledger_simulation_state()
	if faction_controller != null:
		faction_controller.sync_faction_state()
	if law_order_controller != null:
		law_order_controller.sync_law_order_state()
	if world_event_choice_controller != null:
		world_event_choice_controller.sync_world_event_state()
	if job_system_controller != null:
		job_system_controller.sync_job_system_state()
	if nest_world_sim_plugin != null:
		nest_world_sim_plugin.sync_nest_state()


func _refresh_controller_states_from_gecs() -> void:
	if world_time != null:
		world_time.refresh_from_gecs_state()
	if settlement_controller != null:
		settlement_controller.refresh_from_gecs_state()
	if population_controller != null:
		population_controller.refresh_from_gecs_state()
	if ai_scheduler_controller != null:
		ai_scheduler_controller.refresh_from_gecs_state()
	if population_realization_controller != null:
		population_realization_controller.refresh_from_gecs_state()
	if ledger_simulation_controller != null:
		ledger_simulation_controller.refresh_from_gecs_state()
	if faction_controller != null:
		faction_controller.refresh_from_gecs_state()
	if law_order_controller != null:
		law_order_controller.refresh_from_gecs_state()
	if world_event_choice_controller != null:
		world_event_choice_controller.refresh_from_gecs_state()
	if job_system_controller != null:
		job_system_controller.refresh_from_gecs_state()
	if nest_world_sim_plugin != null:
		nest_world_sim_plugin.refresh_from_gecs_state()


func _format_population_summary() -> String:
	if population_controller == null:
		return "Population controller is not available"
	var summary := population_controller.get_population_summary()
	return "Population records=%d realized=%d ledger=%d settlements=%s roles=%s" % [
		int(summary.get("total_records", 0)),
		int(summary.get("realized_records", 0)),
		int(summary.get("ledger_records", 0)),
		str(summary.get("by_settlement", {})),
		str(summary.get("by_role", {})),
	]


func _format_ledger_summary() -> String:
	if ledger_simulation_controller == null:
		return "Ledger simulation controller is not available"
	var summary := ledger_simulation_controller.get_debug_summary()
	return "Ledger elapsed=%d updated=%d batches=%s" % [
		int(summary.get("elapsed_minutes", 0)),
		int(summary.get("updated_actor_count", 0)),
		str(summary.get("batches", {})),
	]


func _format_actor_ai(actor_id: String) -> String:
	if actor_id.strip_edges().is_empty():
		return "Actor id is required"
	if actor_query_controller == null:
		return "Actor query controller is not available"
	var actor := actor_query_controller.get_actor_by_stable_id(actor_id)
	if actor == null:
		return "Actor %s is not realized" % actor_id
	# No actor class implements get_ai_debug_snapshot today; keep the honest fallback
	# until a real snapshot API exists on WorldActor.
	return "Actor %s has no AI debug snapshot" % actor_id
