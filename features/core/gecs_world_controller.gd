extends Node

class_name GecsWorldController

const SERVICE_ID := &"gecs_world"

const WORLD_SCRIPT_PATH := "res://addons/gecs/ecs/world.gd"
const ENTITY_SCRIPT_PATH := "res://addons/gecs/ecs/entity.gd"
const ECS_SCRIPT_PATH := "res://addons/gecs/ecs/ecs.gd"
const GECS_IO_SCRIPT_PATH := "res://addons/gecs/io/io.gd"
const ACTOR_SYNC_SYSTEM_SCRIPT_PATH := "res://features/actors/sim/game_actor_sync_system.gd"
const AI_JOB_SYSTEM_SCRIPT_PATH := "res://features/ai/sim/game_ai_job_system.gd"
const COMBAT_STATE_SYNC_SYSTEM_SCRIPT_PATH := "res://features/combat/sim/game_combat_state_sync_system.gd"
const COMBAT_SCORE_SYSTEM_SCRIPT_PATH := "res://features/combat/sim/game_combat_score_system.gd"
const COMBAT_TARGETING_SYSTEM_SCRIPT_PATH := "res://features/combat/sim/game_combat_targeting_system.gd"
const COMBAT_SLOT_SYSTEM_SCRIPT_PATH := "res://features/combat/sim/game_combat_slot_system.gd"
const COMBAT_RESOLUTION_SYSTEM_SCRIPT_PATH := "res://features/combat/sim/game_combat_resolution_system.gd"
const VITALS_SYSTEM_SCRIPT_PATH := "res://features/actors/sim/game_vitals_system.gd"
const POPULATION_VITALS_SYSTEM_SCRIPT_PATH := "res://features/world_sim/sim/population/game_population_vitals_system.gd"
const COMBAT_MOVEMENT_SYSTEM_SCRIPT_PATH := "res://features/combat/sim/game_combat_movement_system.gd"

const C_NODE_PATH := "res://features/actors/bridge/c_game_actor_node.gd"
const C_IDENTITY_PATH := "res://features/actors/sim/c_game_actor_identity.gd"
const C_FACTION_PATH := "res://features/actors/sim/c_game_actor_faction.gd"
const C_SETTLEMENT_PATH := "res://features/actors/sim/c_game_actor_settlement.gd"
const C_SPATIAL_PATH := "res://features/actors/sim/c_game_actor_spatial.gd"
const C_VITALS_PATH := "res://features/actors/sim/c_game_actor_vitals.gd"
const C_VITALS_INPUTS_PATH := "res://features/actors/sim/c_game_actor_vitals_inputs.gd"
const C_AI_SCHEDULE_PATH := "res://features/ai/sim/c_game_ai_schedule.gd"
const C_AI_STATE_PATH := "res://features/ai/sim/c_game_ai_state.gd"
const C_GOAL_INTENT_PATH := "res://features/ai/sim/c_game_goal_intent.gd"
const C_POPULATION_RECORD_PATH := "res://features/world_sim/sim/population/c_game_population_record.gd"
const C_ACTIVE_POPULATION_VITALS_PATH := "res://features/world_sim/sim/population/c_game_active_population_vitals.gd"
const C_SETTLEMENT_STATE_PATH := "res://features/settlements/sim/c_game_settlement_state.gd"
const C_SETTLEMENT_FOOD_STATUS_PATH := "res://features/settlements/sim/c_game_settlement_food_status.gd"
const C_STAFF_SLOT_PATH := "res://features/settlements/sim/c_game_staff_slot.gd"
const C_STAFF_VACANCY_PATH := "res://features/settlements/sim/c_game_staff_vacancy.gd"
const C_INVENTORY_CONTAINER_PATH := "res://features/inventory/sim/c_game_inventory_container.gd"
const C_ITEM_STACK_PATH := "res://features/inventory/sim/c_game_item_stack.gd"
const C_EQUIPMENT_SLOT_PATH := "res://features/inventory/sim/c_game_equipment_slot.gd"
const C_SETTLEMENT_EVENT_PATH := "res://features/settlements/sim/c_game_settlement_event.gd"
const C_JOB_PROVIDER_PATH := "res://features/settlements/sim/c_game_job_provider.gd"
const C_JOB_PROVIDER_SLOT_PATH := "res://features/settlements/sim/c_game_job_provider_slot.gd"
const C_JOB_WORKER_RECORD_PATH := "res://features/settlements/sim/c_game_job_worker_record.gd"
const C_JOB_CONTRACT_PATH := "res://features/settlements/sim/c_game_job_contract.gd"
const C_JOB_PROVIDER_MEMORY_PATH := "res://features/settlements/sim/c_game_job_provider_memory.gd"
const C_ACTIVITY_POINT_PATH := "res://features/settlements/sim/c_game_activity_point.gd"
const C_ACTIVITY_ASSIGNMENT_PATH := "res://features/settlements/sim/c_game_activity_assignment.gd"
const C_WORLD_TIME_PATH := "res://features/world_sim/sim/c_game_world_time_state.gd"
const C_LAW_ORDER_PATH := "res://features/settlements/sim/c_game_law_order_state.gd"
const C_FACTION_STATE_PATH := "res://features/world_sim/sim/c_game_faction_state.gd"
const C_WORLD_SQUAD_PATH := "res://features/world_sim/sim/c_game_world_squad_state.gd"
const C_WORLD_EVENT_PATH := "res://features/world_sim/sim/c_game_world_event_state.gd"
const C_NEST_STATE_PATH := "res://features/world_sim/sim/c_game_nest_state.gd"
const C_JOB_SYSTEM_PATH := "res://features/settlements/sim/c_game_job_system_state.gd"
const C_LEDGER_SIMULATION_PATH := "res://features/world_sim/sim/c_game_ledger_simulation_state.gd"
const C_AI_SCHEDULER_STATE_PATH := "res://features/ai/sim/c_game_ai_scheduler_state.gd"
const C_POPULATION_REALIZATION_STATE_PATH := "res://features/world_sim/sim/population/c_game_population_realization_state.gd"
const C_COMBAT_LOADOUT_PATH := "res://features/combat/sim/c_game_combat_loadout.gd"
const C_COMBAT_CONFIG_PATH := "res://features/combat/sim/c_game_combat_config.gd"
const C_COMBAT_STATE_PATH := "res://features/combat/sim/c_game_combat_state.gd"
const C_COMBAT_SLOT_STATE_PATH := "res://features/combat/sim/c_game_combat_slot_state.gd"
const C_COMBAT_ACTION_PATH := "res://features/combat/sim/c_game_combat_action.gd"
const C_MOVEMENT_STATE_PATH := "res://features/actors/sim/c_game_movement_state.gd"
const C_WORLD_SIM_SQUAD_PATH := "res://features/world_sim/sim/c_game_world_sim_squad.gd"
const C_BUILDING_RECORD_PATH := "res://features/world/sim/c_game_building_record.gd"
const CONSTRUCTION_CATALOG_ID_LOAD_MIGRATIONS := {
	"woodbrick_house": "medium_wood_l_hall",
}

@export var spatial_cell_size := 6.0
@export var spatial_rebuild_interval_seconds := 0.25

var root_scene: Node
var _context: BootstrapContext
var world
var _actor_entity_by_actor_id: Dictionary = {}
var _actor_id_by_instance_id: Dictionary = {}
var _population_entity_by_actor_id: Dictionary = {}
var _population_actor_ids_by_settlement: Dictionary = {}
var _population_settlement_by_actor_id: Dictionary = {}
var _population_actor_ids_by_squad: Dictionary = {}
var _population_squad_by_actor_id: Dictionary = {}
var _alive_population_count_by_settlement: Dictionary = {}
var _settlement_entity_by_id: Dictionary = {}
var _settlement_food_entity_by_id: Dictionary = {}
var _staff_slot_entity_by_key: Dictionary = {}
var _staff_vacancy_entity_by_key: Dictionary = {}
var _inventory_container_entity_by_id: Dictionary = {}
var _item_stack_entity_by_id: Dictionary = {}
var _equipment_slot_entity_by_key: Dictionary = {}
var _settlement_event_entity_by_id: Dictionary = {}
var _job_provider_entity_by_id: Dictionary = {}
var _job_provider_slot_entity_by_id: Dictionary = {}
var _job_worker_record_entity_by_id: Dictionary = {}
var _job_contract_entity_by_id: Dictionary = {}
var _job_provider_memory_entity_by_id: Dictionary = {}
var _activity_point_entity_by_id: Dictionary = {}
var _activity_assignment_entity_by_actor_id: Dictionary = {}
var _world_sim_squad_entity_by_id: Dictionary = {}
var _building_entity_by_id: Dictionary = {}
var _world_time_entity
var _law_order_entity
var _faction_state_entity
var _world_squad_entity
var _world_event_entity
var _nest_state_entity
var _job_system_entity
var _ledger_simulation_entity
var _ai_scheduler_state_entity
var _population_realization_state_entity
var _initialized := false

const WORLD_BRAIN_LOG_CAP := 200
signal world_event_logged(entry)
signal world_reindexed
signal population_life_state_changed(actor_id: String, previous_state: int, next_state: int)
var _world_brain_log: Array[Dictionary] = []
var _actor_spatial_nodes_by_cell: Dictionary = {}
const CORPSE_SPATIAL_CELL_SIZE := 32.0
var _corpse_actor_ids_by_cell: Dictionary = {}
var _corpse_cell_by_actor_id: Dictionary = {}
var _actor_spatial_index_valid := false
var _actor_spatial_index_elapsed := 999.0
var _spatial_query_calls := 0
var _spatial_query_cells_checked := 0
var _spatial_query_candidates_checked := 0
var _spatial_query_results_returned := 0
var _spatial_index_rebuilds := 0
var _spatial_index_rebuild_usec := 0
var _actor_query_metrics_enabled := false
var _world_script
var _entity_script
var _ecs_script
var _gecs_io_script
var _actor_sync_system_script
var _ai_job_system_script
var _combat_state_sync_system_script
var _combat_score_system_script
var _combat_targeting_system_script
var _combat_slot_system_script
var _combat_resolution_system_script
var _vitals_system_script
var _vitals_system
var _population_vitals_system_script
var _population_vitals_system
var _combat_movement_system_script
var _registered_direct_script_ecs_singleton := false
var _direct_script_ecs_placeholder: Node
var C_NODE
var C_IDENTITY
var C_FACTION
var C_SETTLEMENT
var C_SPATIAL
var C_VITALS
var C_VITALS_INPUTS
var C_AI_SCHEDULE
var C_AI_STATE
var C_GOAL_INTENT
var C_POPULATION_RECORD
var C_ACTIVE_POPULATION_VITALS
var C_SETTLEMENT_STATE
var C_STAFF_SLOT
var C_STAFF_VACANCY
var C_INVENTORY_CONTAINER
var C_ITEM_STACK
var C_EQUIPMENT_SLOT
var C_SETTLEMENT_EVENT
var C_JOB_PROVIDER
var C_JOB_PROVIDER_SLOT
var C_JOB_WORKER_RECORD
var C_JOB_CONTRACT
var C_JOB_PROVIDER_MEMORY
var C_ACTIVITY_POINT
var C_ACTIVITY_ASSIGNMENT
var C_WORLD_TIME
var C_LAW_ORDER
var C_FACTION_STATE
var C_WORLD_SQUAD
var C_WORLD_EVENT
var C_NEST_STATE
var C_JOB_SYSTEM
var C_LEDGER_SIMULATION
var C_AI_SCHEDULER_STATE
var C_POPULATION_REALIZATION_STATE
var C_COMBAT_LOADOUT
var C_COMBAT_CONFIG
var C_COMBAT_STATE
var C_COMBAT_SLOT_STATE
var C_COMBAT_ACTION
var C_MOVEMENT_STATE
var C_WORLD_SIM_SQUAD
var C_BUILDING_RECORD


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_context = context
	_try_initialize()


func _ready() -> void:
	add_to_group("gecs_world_controller")
	_try_initialize()


func _exit_tree() -> void:
	if world != null and is_instance_valid(world) and world.has_method("purge"):
		world.call("purge", false)
	var ecs_node := get_node_or_null("/root/ECS")
	if ecs_node != null and ecs_node.get("world") == world:
		ecs_node.set("world", null)
	world = null


var _last_world_process_usec := 0

func _process(delta: float) -> void:
	if world != null:
		var t0 := Time.get_ticks_usec()
		world.process(delta)
		_last_world_process_usec = Time.get_ticks_usec() - t0
	_actor_spatial_index_elapsed += delta
	if _actor_spatial_index_elapsed >= maxf(spatial_rebuild_interval_seconds, 0.01):
		_actor_spatial_index_valid = false


func register_actor(actor: Node, settlement_id := "", context: Dictionary = {}) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""
	_try_initialize()
	if world == null:
		return ""
	var actor_id: String = _actor_id_for_actor(actor, settlement_id)
	if actor_id.is_empty():
		return ""
	if actor.has_method("set"):
		actor.set("stable_id", actor_id)
	actor.set_meta("actor_record_id", actor_id)
	if not settlement_id.is_empty():
		actor.set_meta("settlement_id", settlement_id)
	if context.has("role_id"):
		actor.set_meta("actor_role_id", str(context.get("role_id", "resident")))
	var entity = _actor_entity_by_actor_id.get(actor_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("Actor", actor_id)
		entity.id = _entity_id("actor", actor_id)
		world.add_entity(entity, [C_NODE.new(), C_IDENTITY.new(), C_FACTION.new(), C_SETTLEMENT.new(), C_SPATIAL.new(), C_VITALS.new(), C_VITALS_INPUTS.new(), C_AI_SCHEDULE.new(), C_AI_STATE.new(), C_GOAL_INTENT.new(), C_COMBAT_LOADOUT.new(), C_COMBAT_CONFIG.new(), C_COMBAT_STATE.new(), C_COMBAT_SLOT_STATE.new(), C_COMBAT_ACTION.new(), C_MOVEMENT_STATE.new()])
		_actor_entity_by_actor_id[actor_id] = entity
	else:
		_ensure_actor_combat_components(entity)
	_write_actor_components(entity, actor, actor_id, settlement_id, context)
	_hydrate_live_vitals_from_population(entity, actor_id)
	_actor_id_by_instance_id[actor.get_instance_id()] = actor_id
	_actor_spatial_index_valid = false
	sync_actor_inventory(actor)
	_connect_actor_gecs_sync(actor)
	return actor_id


## Observe the inventory/equipment capability change signals and mirror to the component.
## This INVERTS the old dependency (capabilities used to fetch + call this controller,
## forming the actor<->capability cycle). Now the capabilities only emit; the controller
## depends on them, never the reverse. The Signal is grabbed inline (no typed capability
## local) so no capability-class graph edge is added.
func _connect_actor_gecs_sync(actor: Node) -> void:
	var world_actor := actor as WorldActor
	if world_actor == null:
		return
	if world_actor.get_inventory() != null:
		var inventory_signal: Signal = world_actor.get_inventory().inventory_changed
		if not inventory_signal.is_connected(sync_actor_inventory.bind(actor)):
			inventory_signal.connect(sync_actor_inventory.bind(actor))
	if world_actor.get_equipment() != null:
		var equipment_signal: Signal = world_actor.get_equipment().equipment_changed
		if not equipment_signal.is_connected(_on_actor_equipment_changed.bind(actor)):
			equipment_signal.connect(_on_actor_equipment_changed.bind(actor))
	if world_actor.get_interaction() != null:
		var rest_signal: Signal = world_actor.get_interaction().rest_state_requested
		if not rest_signal.is_connected(request_actor_rest_state):
			rest_signal.connect(request_actor_rest_state)


func _on_actor_equipment_changed(_changed_slots: Array, actor: Node) -> void:
	sync_actor_inventory(actor)


## Queues a voluntary ALIVE/ASLEEP transition by stable ID. GameVitalsSystem
## validates and applies it; this command boundary never mutates durable vitals.
func request_actor_rest_state(actor_id: String, next_state: int) -> bool:
	if next_state != NpcRules.LifeState.ALIVE and next_state != NpcRules.LifeState.ASLEEP:
		return false
	var entity = _actor_entity_by_actor_id.get(actor_id.strip_edges())
	if entity == null or not is_instance_valid(entity):
		return false
	var inputs = entity.get_component(C_VITALS_INPUTS)
	if inputs == null:
		return false
	inputs.pending_rest_state = next_state
	return true


func _ensure_actor_combat_components(entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	for component_script in [C_COMBAT_LOADOUT, C_COMBAT_CONFIG, C_COMBAT_STATE, C_COMBAT_SLOT_STATE, C_COMBAT_ACTION, C_MOVEMENT_STATE]:
		if component_script != null and entity.get_component(component_script) == null:
			entity.add_component(component_script.new())


func unregister_actor(actor: Node) -> void:
	if actor == null:
		return
	var actor_id: String = _actor_record_id(actor)
	if actor_id.is_empty():
		actor_id = _actor_id_by_instance_id.get(actor.get_instance_id(), "")
	if actor_id.is_empty():
		return
	_disconnect_actor_gecs_sync(actor)
	var entity = _actor_entity_by_actor_id.get(actor_id)
	var final_world_transform := Transform3D.IDENTITY
	var has_final_world_transform := false
	if actor is Node3D:
		final_world_transform = (actor as Node3D).global_transform
		has_final_world_transform = true
	if entity != null and is_instance_valid(entity):
		var population_entity = _population_entity_by_actor_id.get(actor_id)
		var population = population_entity.get_component(C_POPULATION_RECORD) if population_entity != null and is_instance_valid(population_entity) else null
		if population != null:
			population.realization_state = "ledger"
		_copy_live_vitals_to_population(entity, actor_id)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)
	_actor_entity_by_actor_id.erase(actor_id)
	_actor_id_by_instance_id.erase(actor.get_instance_id())
	_actor_spatial_index_valid = false
	var pop_entity = _population_entity_by_actor_id.get(actor_id)
	if pop_entity != null and is_instance_valid(pop_entity):
		var record_component = pop_entity.get_component(C_POPULATION_RECORD)
		if record_component != null:
			record_component.realization_state = "ledger"
			if has_final_world_transform:
				record_component.last_world_transform = final_world_transform
				record_component.last_world_transform_initialized = true
				record_component.last_world_position = final_world_transform.origin
				record_component.last_world_position_initialized = true


func _disconnect_actor_gecs_sync(actor: Node) -> void:
	var world_actor := actor as WorldActor
	if world_actor == null:
		return
	if world_actor.get_inventory() != null:
		var inventory_callback := sync_actor_inventory.bind(actor)
		if world_actor.get_inventory().inventory_changed.is_connected(inventory_callback):
			world_actor.get_inventory().inventory_changed.disconnect(inventory_callback)
	if world_actor.get_equipment() != null:
		var equipment_callback := _on_actor_equipment_changed.bind(actor)
		if world_actor.get_equipment().equipment_changed.is_connected(equipment_callback):
			world_actor.get_equipment().equipment_changed.disconnect(equipment_callback)
	if world_actor.get_interaction() != null and world_actor.get_interaction().rest_state_requested.is_connected(request_actor_rest_state):
		world_actor.get_interaction().rest_state_requested.disconnect(request_actor_rest_state)


## Public entity lookup for tools/probes and controllers that must reach an
## actor's GECS components directly (the sim truth for realized humanoids).
func get_actor_entity(actor: Node):
	return _actor_entity_for_actor(actor)


func get_actor_by_stable_id(actor_id: String) -> Node:
	var entity = _actor_entity_by_actor_id.get(actor_id)
	return _actor_from_entity(entity)


func get_actor_by_instance_id(instance_id: int) -> Node:
	var actor_id: String = _actor_id_by_instance_id.get(instance_id, "")
	return get_actor_by_stable_id(actor_id)


func get_actor_state(actor_id: String) -> Dictionary:
	var entity = _actor_entity_by_actor_id.get(actor_id)
	if (entity == null or not is_instance_valid(entity)) and world != null:
		for candidate in world.query.with_all([C_IDENTITY]).execute():
			var identity = candidate.get_component(C_IDENTITY)
			if identity != null and str(identity.actor_id) == actor_id:
				entity = candidate
				_actor_entity_by_actor_id[actor_id] = candidate
				break
	return _actor_state_from_entity(entity)


func get_actor_states() -> Dictionary:
	var states: Dictionary = {}
	if world == null:
		return states
	for entity in world.query.with_all([C_IDENTITY]).execute():
		var state := _actor_state_from_entity(entity)
		var actor_id := str(state.get("actor_id", ""))
		if not actor_id.is_empty():
			states[actor_id] = state
			_actor_entity_by_actor_id[actor_id] = entity
	return states


func get_all_actors() -> Array:
	return _query_actor_nodes({})


func get_alive_actors(include_party := true) -> Array:
	return _query_actor_nodes({"alive": true, "include_party": include_party})


func get_alive_actors_for_settlement(settlement_id: String, include_party := true) -> Array:
	return _query_actor_nodes({"alive": true, "settlement_id": settlement_id, "include_party": include_party})


func get_alive_actors_for_role(role_id: String, include_party := true) -> Array:
	return _query_actor_nodes({"alive": true, "role_id": role_id, "include_party": include_party})


func get_alive_actors_for_faction(faction_id: String, include_party := true) -> Array:
	return _query_actor_nodes({"alive": true, "faction_id": faction_id, "include_party": include_party})


func get_nearby_actors(position: Vector3, radius: float, include_party := true) -> Array:
	return _query_actor_nodes({"alive": true, "position": position, "radius": radius, "include_party": include_party})


func get_nearby_actors_limited(position: Vector3, radius: float, max_count: int, include_party := true) -> Array:
	return _query_spatial_actor_nodes_limited(position, radius, radius * radius, include_party, true, max_count)


func get_actor_query_metrics() -> Dictionary:
	return {
		"spatial_query_calls": _spatial_query_calls,
		"spatial_query_cells_checked": _spatial_query_cells_checked,
		"spatial_query_candidates_checked": _spatial_query_candidates_checked,
		"spatial_query_results_returned": _spatial_query_results_returned,
		"spatial_index_rebuilds": _spatial_index_rebuilds,
		"spatial_index_rebuild_usec": _spatial_index_rebuild_usec,
		"spatial_index_cell_count": _actor_spatial_nodes_by_cell.size(),
	}


func reset_actor_query_metrics() -> void:
	_spatial_query_calls = 0
	_spatial_query_cells_checked = 0
	_spatial_query_candidates_checked = 0
	_spatial_query_results_returned = 0
	_spatial_index_rebuilds = 0
	_spatial_index_rebuild_usec = 0


func set_actor_query_metrics_enabled(enabled: bool) -> void:
	_actor_query_metrics_enabled = enabled


func get_all_humanoids() -> Array:
	return get_all_actors()


func get_alive_humanoids(include_party := true) -> Array:
	return get_alive_actors(include_party)


func get_alive_humanoids_for_settlement(settlement_id: String, include_party := true) -> Array:
	return get_alive_actors_for_settlement(settlement_id, include_party)


func get_alive_humanoids_for_role(role_id: String, include_party := true) -> Array:
	return get_alive_actors_for_role(role_id, include_party)


func get_alive_humanoids_for_faction(faction_id: String, include_party := true) -> Array:
	return get_alive_actors_for_faction(faction_id, include_party)


func get_nearby_humanoids(position: Vector3, radius: float, include_party := true) -> Array:
	return get_nearby_actors(position, radius, include_party)


func clear_actor_schedule(actor: Node) -> void:
	var entity = _actor_entity_for_actor(actor)
	if entity == null:
		return
	var schedule = entity.get_component(C_AI_SCHEDULE)
	if schedule != null:
		schedule.next_decision_tick = -1.0
		schedule.next_job_tick = -1.0


func set_actor_ai_job(actor: Node, job, driver = null) -> void:
	var entity = _actor_entity_for_actor(actor)
	if entity == null:
		register_actor(actor)
		entity = _actor_entity_for_actor(actor)
	if entity == null:
		return
	var ai_state = entity.get_component(C_AI_STATE)
	if ai_state == null:
		return
	ai_state.apply_job(job)
	ai_state.active_driver = driver
	ai_state.active_target_id = _target_id_for_ai_job(job)


func clear_actor_ai_job(actor: Node) -> void:
	var entity = _actor_entity_for_actor(actor)
	if entity == null:
		return
	var ai_state = entity.get_component(C_AI_STATE)
	if ai_state == null:
		return
	ai_state.clear_job()


func set_actor_goal_intent(actor: Node, intent_data: Dictionary) -> Dictionary:
	var entity = _actor_entity_for_actor(actor)
	if entity == null:
		register_actor(actor)
		entity = _actor_entity_for_actor(actor)
	if entity == null:
		return {}
	var goal_intent = _ensure_actor_goal_intent_component(entity)
	if goal_intent == null:
		return {}
	goal_intent.apply_decision(intent_data)
	return goal_intent.to_dictionary(false)


func get_actor_goal_intent(actor: Node, include_debug := false) -> Dictionary:
	var entity = _actor_entity_for_actor(actor)
	if entity == null:
		return {}
	var goal_intent = entity.get_component(C_GOAL_INTENT)
	return goal_intent.to_dictionary(include_debug) if goal_intent != null and goal_intent.has_method("to_dictionary") else {}


func clear_actor_goal_intent(actor: Node) -> void:
	var entity = _actor_entity_for_actor(actor)
	if entity == null:
		return
	var goal_intent = entity.get_component(C_GOAL_INTENT)
	if goal_intent != null and goal_intent.has_method("clear_intent"):
		goal_intent.call("clear_intent")


func should_tick_actor(actor: Node, sim_time: float, interval_seconds: float, jitter_seconds: float, rng: RandomNumberGenerator) -> bool:
	var entity = _actor_entity_for_actor(actor)
	if entity == null:
		register_actor(actor)
		entity = _actor_entity_for_actor(actor)
	if entity == null:
		return false
	var schedule = entity.get_component(C_AI_SCHEDULE)
	if schedule == null:
		return true
	if float(schedule.next_decision_tick) > sim_time:
		return false
	var interval: float = maxf(interval_seconds, 0.01)
	var jitter: float = maxf(jitter_seconds, 0.0)
	schedule.decision_interval_seconds = interval
	schedule.decision_jitter_seconds = jitter
	schedule.next_decision_tick = sim_time + interval + rng.randf_range(0.0, jitter)
	return true


func upsert_population_record(record: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null or record.is_empty():
		return {}
	var actor_id: String = str(record.get("actor_id", record.get("stable_id", ""))).strip_edges()
	if actor_id.is_empty():
		return {}
	var entity = _population_entity_by_actor_id.get(actor_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("Population", actor_id)
		entity.id = _entity_id("population", actor_id)
		world.add_entity(entity, [C_POPULATION_RECORD.new(), C_VITALS.new(), C_VITALS_INPUTS.new()])
		_population_entity_by_actor_id[actor_id] = entity
	_ensure_population_vitals_components(entity)
	var component = entity.get_component(C_POPULATION_RECORD)
	var vitals = entity.get_component(C_VITALS)
	var vitals_inputs = entity.get_component(C_VITALS_INPUTS)
	var previous_settlement_id := str(component.settlement_id)
	var previous_squad_id := str(component.squad_name)
	var was_alive := not str(component.actor_id).is_empty() and int(component.life_state) != NpcRules.LifeState.DEAD
	component.apply_record(record)
	if record.has("vitals"):
		vitals.apply_durable_state(record.get("vitals", {}))
		vitals.vitals_seeded = true
	else:
		vitals.life_state = component.life_state
	if record.has("vitals_inputs"):
		vitals_inputs.apply_durable_state(record.get("vitals_inputs", {}))
	component.life_state = vitals.life_state
	_sync_active_population_vitals_tag(entity, vitals)
	_adjust_alive_population_count(previous_settlement_id, -1 if was_alive else 0)
	_adjust_alive_population_count(str(component.settlement_id), 1 if int(component.life_state) != NpcRules.LifeState.DEAD else 0)
	_reindex_population_settlement(component, previous_settlement_id)
	_reindex_population_squad(component, previous_squad_id)
	_reindex_corpse_record(component)
	_sync_record_equipment_slots(actor_id, record.get("equipment_slots", {}))
	_sync_record_inventory_entries(actor_id, record.get("inventory_entries", []))
	return _population_record_from_entity(entity)


func update_population_skill_progress(actor_id: String, skill_id: String, level: int, xp: float) -> bool:
	var entity = _population_entity_by_actor_id.get(actor_id)
	var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
	if component == null or skill_id.is_empty():
		return false
	if level > SkillRules.DEFAULT_LEVEL:
		component.skill_levels[skill_id] = level
	else:
		component.skill_levels.erase(skill_id)
	if xp > 0.0:
		component.skill_xp[skill_id] = xp
	else:
		component.skill_xp.erase(skill_id)
	return true


func update_population_ledger_state(actor_id: String, state: Dictionary) -> bool:
	var entity = _population_entity_by_actor_id.get(actor_id)
	var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
	if component == null:
		return false
	component.ledger_activity_state = str(state.get("ledger_activity_state", component.ledger_activity_state))
	component.ledger_minutes_elapsed = int(state.get("ledger_minutes_elapsed", component.ledger_minutes_elapsed))
	component.ledger_work_minutes = int(state.get("ledger_work_minutes", component.ledger_work_minutes))
	component.ledger_rest_minutes = int(state.get("ledger_rest_minutes", component.ledger_rest_minutes))
	component.ledger_activity_minutes = (state.get("ledger_activity_minutes", component.ledger_activity_minutes) as Dictionary).duplicate(true)
	component.last_ledger_absolute_minute = int(state.get("last_ledger_absolute_minute", component.last_ledger_absolute_minute))
	return true


func update_population_realization(actor_id: String, realization_state: String, world_transform: Transform3D, transform_initialized: bool) -> bool:
	var entity = _population_entity_by_actor_id.get(actor_id)
	var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
	if component == null:
		return false
	component.realization_state = realization_state
	component.last_world_transform = world_transform
	component.last_world_transform_initialized = transform_initialized
	component.last_world_position = world_transform.origin
	component.last_world_position_initialized = transform_initialized
	if int(component.life_state) == NpcRules.LifeState.DEAD:
		_reindex_corpse_record(component)
	return true


func update_population_death(actor_id: String, world_transform: Transform3D) -> bool:
	var entity = _population_entity_by_actor_id.get(actor_id)
	var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
	if component == null:
		return false
	if int(component.life_state) != NpcRules.LifeState.DEAD:
		_adjust_alive_population_count(str(component.settlement_id), -1)
	component.life_state = NpcRules.LifeState.DEAD
	var vitals = entity.get_component(C_VITALS)
	if vitals != null:
		vitals.life_state = NpcRules.LifeState.DEAD
	_sync_active_population_vitals_tag(entity, vitals)
	component.body_state = "corpse"
	component.body_container_id = ""
	component.assigned_slot_id = ""
	component.last_world_transform = world_transform
	component.last_world_transform_initialized = true
	component.last_world_position = world_transform.origin
	component.last_world_position_initialized = true
	_reindex_corpse_record(component)
	return true


func update_population_corpse_transform(actor_id: String, world_transform: Transform3D) -> bool:
	var entity = _population_entity_by_actor_id.get(actor_id)
	var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
	if component == null or int(component.life_state) != NpcRules.LifeState.DEAD or str(component.body_state) != "corpse":
		return false
	component.last_world_transform = world_transform
	component.last_world_transform_initialized = true
	component.last_world_position = world_transform.origin
	component.last_world_position_initialized = true
	_reindex_corpse_record(component)
	return true


func update_population_body_state(actor_id: String, body_state: String, body_container_id := "") -> bool:
	var entity = _population_entity_by_actor_id.get(actor_id)
	var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
	if component == null or int(component.life_state) != NpcRules.LifeState.DEAD:
		return false
	component.body_state = body_state
	component.body_container_id = body_container_id
	component.realization_state = "ledger"
	_reindex_corpse_record(component)
	return true


func get_corpse_population_records_near(world_position: Vector3, radius: float) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if radius < 0.0:
		return records
	var min_cell := _corpse_spatial_cell(world_position - Vector3(radius, 0.0, radius))
	var max_cell := _corpse_spatial_cell(world_position + Vector3(radius, 0.0, radius))
	var radius_squared := radius * radius
	for cell_x in range(min_cell.x, max_cell.x + 1):
		for cell_y in range(min_cell.y, max_cell.y + 1):
			var ids: Dictionary = _corpse_actor_ids_by_cell.get(Vector2i(cell_x, cell_y), {})
			for actor_id_value in ids.keys():
				var entity = _population_entity_by_actor_id.get(str(actor_id_value))
				var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
				if component == null:
					continue
				var offset: Vector3 = component.last_world_position - world_position
				offset.y = 0.0
				if offset.length_squared() <= radius_squared:
					records.append(_population_record_from_entity(entity))
	return records


func _corpse_spatial_cell(world_position: Vector3) -> Vector2i:
	return Vector2i(floori(world_position.x / CORPSE_SPATIAL_CELL_SIZE), floori(world_position.z / CORPSE_SPATIAL_CELL_SIZE))


func _reindex_corpse_record(component) -> void:
	if component == null:
		return
	var actor_id := str(component.actor_id)
	var previous_cell = _corpse_cell_by_actor_id.get(actor_id)
	if previous_cell is Vector2i:
		var previous_ids: Dictionary = _corpse_actor_ids_by_cell.get(previous_cell, {})
		previous_ids.erase(actor_id)
		if previous_ids.is_empty():
			_corpse_actor_ids_by_cell.erase(previous_cell)
		else:
			_corpse_actor_ids_by_cell[previous_cell] = previous_ids
		_corpse_cell_by_actor_id.erase(actor_id)
	if int(component.life_state) != NpcRules.LifeState.DEAD or str(component.body_state) != "corpse" or not bool(component.last_world_position_initialized):
		return
	var cell := _corpse_spatial_cell(component.last_world_position)
	var ids: Dictionary = _corpse_actor_ids_by_cell.get(cell, {})
	ids[actor_id] = true
	_corpse_actor_ids_by_cell[cell] = ids
	_corpse_cell_by_actor_id[actor_id] = cell


func _reindex_population_settlement(component, previous_settlement_id := "") -> void:
	if component == null:
		return
	var actor_id := str(component.actor_id)
	var old_settlement_id := str(previous_settlement_id)
	if old_settlement_id.is_empty():
		old_settlement_id = str(_population_settlement_by_actor_id.get(actor_id, ""))
	if not old_settlement_id.is_empty():
		var old_ids: Dictionary = _population_actor_ids_by_settlement.get(old_settlement_id, {})
		old_ids.erase(actor_id)
		if old_ids.is_empty():
			_population_actor_ids_by_settlement.erase(old_settlement_id)
		else:
			_population_actor_ids_by_settlement[old_settlement_id] = old_ids
	var settlement_id := str(component.settlement_id)
	if settlement_id.is_empty():
		_population_settlement_by_actor_id.erase(actor_id)
		return
	var ids: Dictionary = _population_actor_ids_by_settlement.get(settlement_id, {})
	ids[actor_id] = true
	_population_actor_ids_by_settlement[settlement_id] = ids
	_population_settlement_by_actor_id[actor_id] = settlement_id


func _reindex_population_squad(component, previous_squad_id := "") -> void:
	if component == null:
		return
	var actor_id := str(component.actor_id)
	var old_squad_id := str(previous_squad_id)
	if old_squad_id.is_empty():
		old_squad_id = str(_population_squad_by_actor_id.get(actor_id, ""))
	if not old_squad_id.is_empty():
		var old_ids: Dictionary = _population_actor_ids_by_squad.get(old_squad_id, {})
		old_ids.erase(actor_id)
		if old_ids.is_empty():
			_population_actor_ids_by_squad.erase(old_squad_id)
		else:
			_population_actor_ids_by_squad[old_squad_id] = old_ids
	var squad_id := str(component.squad_name)
	if squad_id.is_empty():
		_population_squad_by_actor_id.erase(actor_id)
		return
	var ids: Dictionary = _population_actor_ids_by_squad.get(squad_id, {})
	ids[actor_id] = true
	_population_actor_ids_by_squad[squad_id] = ids
	_population_squad_by_actor_id[actor_id] = squad_id


func get_population_records_for_settlement(settlement_id: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var actor_ids: Dictionary = _population_actor_ids_by_settlement.get(settlement_id, {})
	for actor_id_value in actor_ids.keys():
		var entity = _population_entity_by_actor_id.get(str(actor_id_value))
		var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
		if component == null:
			continue
		records.append(_population_record_from_entity(entity))
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("actor_id", "")) < str(b.get("actor_id", "")))
	return records


func get_population_records_for_squad(squad_id: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var actor_ids: Dictionary = _population_actor_ids_by_squad.get(squad_id, {})
	for actor_id_value in actor_ids.keys():
		var entity = _population_entity_by_actor_id.get(str(actor_id_value))
		var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
		if component != null:
			records.append(_population_record_from_entity(entity))
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("actor_id", "")) < str(b.get("actor_id", "")))
	return records


func count_alive_population_records_for_settlement(settlement_id: String) -> int:
	return int(_alive_population_count_by_settlement.get(settlement_id, 0))


func _adjust_alive_population_count(settlement_id: String, delta: int) -> void:
	if settlement_id.is_empty() or delta == 0:
		return
	var next_count := maxi(0, int(_alive_population_count_by_settlement.get(settlement_id, 0)) + delta)
	if next_count == 0:
		_alive_population_count_by_settlement.erase(settlement_id)
	else:
		_alive_population_count_by_settlement[settlement_id] = next_count


func remove_population_record(actor_id: String) -> void:
	var entity = _population_entity_by_actor_id.get(actor_id)
	var component = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
	if component != null and int(component.life_state) != NpcRules.LifeState.DEAD:
		_adjust_alive_population_count(str(component.settlement_id), -1)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)
	_population_entity_by_actor_id.erase(actor_id)
	var settlement_id := str(_population_settlement_by_actor_id.get(actor_id, ""))
	if not settlement_id.is_empty():
		var settlement_ids: Dictionary = _population_actor_ids_by_settlement.get(settlement_id, {})
		settlement_ids.erase(actor_id)
		if settlement_ids.is_empty():
			_population_actor_ids_by_settlement.erase(settlement_id)
		else:
			_population_actor_ids_by_settlement[settlement_id] = settlement_ids
	_population_settlement_by_actor_id.erase(actor_id)
	var squad_id := str(_population_squad_by_actor_id.get(actor_id, ""))
	if not squad_id.is_empty():
		var squad_ids: Dictionary = _population_actor_ids_by_squad.get(squad_id, {})
		squad_ids.erase(actor_id)
		if squad_ids.is_empty():
			_population_actor_ids_by_squad.erase(squad_id)
		else:
			_population_actor_ids_by_squad[squad_id] = squad_ids
	_population_squad_by_actor_id.erase(actor_id)
	var corpse_cell = _corpse_cell_by_actor_id.get(actor_id)
	if corpse_cell is Vector2i:
		var ids: Dictionary = _corpse_actor_ids_by_cell.get(corpse_cell, {})
		ids.erase(actor_id)
		if ids.is_empty():
			_corpse_actor_ids_by_cell.erase(corpse_cell)
		else:
			_corpse_actor_ids_by_cell[corpse_cell] = ids
	_corpse_cell_by_actor_id.erase(actor_id)


func clear_population_records() -> void:
	if world == null:
		_population_entity_by_actor_id.clear()
		_alive_population_count_by_settlement.clear()
		_population_actor_ids_by_settlement.clear()
		_population_settlement_by_actor_id.clear()
		_population_actor_ids_by_squad.clear()
		_population_squad_by_actor_id.clear()
		_corpse_actor_ids_by_cell.clear()
		_corpse_cell_by_actor_id.clear()
		return
	var entities: Array = []
	for entity in world.query.with_all([C_POPULATION_RECORD]).execute():
		entities.append(entity)
	for entity in entities:
		if entity != null and is_instance_valid(entity):
			world.remove_entity(entity)
	_population_entity_by_actor_id.clear()
	_alive_population_count_by_settlement.clear()
	_population_actor_ids_by_settlement.clear()
	_population_settlement_by_actor_id.clear()
	_population_actor_ids_by_squad.clear()
	_population_squad_by_actor_id.clear()
	_corpse_actor_ids_by_cell.clear()
	_corpse_cell_by_actor_id.clear()


func get_population_record(actor_id: String) -> Dictionary:
	var entity = _population_entity_by_actor_id.get(actor_id)
	if entity == null or not is_instance_valid(entity):
		return {}
	return _population_record_from_entity(entity)


func get_population_records() -> Dictionary:
	var records: Dictionary = {}
	if world == null:
		return records
	for entity in world.query.with_all([C_POPULATION_RECORD]).execute():
		var component = entity.get_component(C_POPULATION_RECORD)
		if component == null:
			continue
		records[str(component.actor_id)] = _population_record_from_entity(entity)
		_population_entity_by_actor_id[str(component.actor_id)] = entity
	return records


func get_active_population_vitals_count() -> int:
	return world.query.with_all([C_POPULATION_RECORD, C_ACTIVE_POPULATION_VITALS]).execute().size() if world != null else 0


func catch_up_vitals(duration_seconds: float) -> void:
	if duration_seconds <= 0.0:
		return
	if _vitals_system != null:
		_vitals_system.catch_up_seconds(duration_seconds)
		for actor_id_value in _actor_entity_by_actor_id.keys():
			var actor_id := str(actor_id_value)
			var entity = _actor_entity_by_actor_id.get(actor_id)
			if entity != null and is_instance_valid(entity):
				_copy_live_vitals_to_population(entity, actor_id)
	if _population_vitals_system != null:
		_population_vitals_system.catch_up_seconds(duration_seconds)


func _population_record_from_entity(entity) -> Dictionary:
	if entity == null or not is_instance_valid(entity):
		return {}
	var population = entity.get_component(C_POPULATION_RECORD)
	if population == null:
		return {}
	var record: Dictionary = population.to_record()
	var vitals = entity.get_component(C_VITALS)
	if vitals != null and bool(vitals.vitals_seeded):
		record["life_state"] = vitals.life_state
		record["vitals"] = vitals.durable_state()
		var inputs = entity.get_component(C_VITALS_INPUTS)
		if inputs != null:
			record["vitals_inputs"] = inputs.durable_state()
	return _populate_record_inventory_and_equipment(record)


func _ensure_population_vitals_components(entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var population = entity.get_component(C_POPULATION_RECORD)
	if entity.get_component(C_VITALS) == null:
		var vitals = C_VITALS.new()
		if population != null:
			vitals.life_state = population.life_state
		entity.add_component(vitals)
	if entity.get_component(C_VITALS_INPUTS) == null:
		entity.add_component(C_VITALS_INPUTS.new())


func _hydrate_live_vitals_from_population(live_entity, actor_id: String) -> void:
	var population_entity = _population_entity_by_actor_id.get(actor_id)
	if population_entity == null or not is_instance_valid(population_entity):
		return
	_ensure_population_vitals_components(population_entity)
	var stored = population_entity.get_component(C_VITALS)
	var live = live_entity.get_component(C_VITALS)
	if stored == null or live == null or not stored.vitals_seeded:
		return
	stored.copy_durable_state_to(live)
	live.vitals_seeded = true
	var stored_inputs = population_entity.get_component(C_VITALS_INPUTS)
	var live_inputs = live_entity.get_component(C_VITALS_INPUTS)
	if stored_inputs != null:
		stored_inputs.copy_durable_state_to(live_inputs)
	var population = population_entity.get_component(C_POPULATION_RECORD)
	if population != null:
		population.life_state = live.life_state
	_sync_active_population_vitals_tag(population_entity, null)


func _copy_live_vitals_to_population(live_entity, actor_id: String) -> void:
	var population_entity = _population_entity_by_actor_id.get(actor_id)
	if population_entity == null or not is_instance_valid(population_entity):
		return
	_ensure_population_vitals_components(population_entity)
	var live = live_entity.get_component(C_VITALS)
	var stored = population_entity.get_component(C_VITALS)
	if live == null or stored == null:
		return
	var previous_state: int = int(stored.life_state)
	live.copy_durable_state_to(stored)
	stored.vitals_seeded = true
	var live_inputs = live_entity.get_component(C_VITALS_INPUTS)
	var stored_inputs = population_entity.get_component(C_VITALS_INPUTS)
	if live_inputs != null:
		live_inputs.copy_durable_state_to(stored_inputs)
	if live.life_state == NpcRules.LifeState.DEAD:
		var actor := _actor_from_entity(live_entity)
		var population = population_entity.get_component(C_POPULATION_RECORD)
		if actor is Node3D and population != null:
			population.last_world_transform = (actor as Node3D).global_transform
			population.last_world_transform_initialized = true
			population.last_world_position = (actor as Node3D).global_position
			population.last_world_position_initialized = true
	_apply_population_life_state(population_entity, previous_state, stored.life_state)
	_sync_active_population_vitals_tag(population_entity, stored)


func _sync_active_population_vitals_tag(entity, vitals) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var active = entity.get_component(C_ACTIVE_POPULATION_VITALS)
	var population = entity.get_component(C_POPULATION_RECORD)
	var should_be_active: bool = population != null and str(population.realization_state) != "realized" \
		and vitals != null and bool(vitals.vitals_seeded) and bool(vitals.needs_active_simulation())
	if should_be_active and active == null:
		entity.add_component(C_ACTIVE_POPULATION_VITALS.new())
	elif not should_be_active and active != null:
		entity.remove_component(C_ACTIVE_POPULATION_VITALS)


func _on_population_vitals_life_state_changed(entity, previous_state: int, next_state: int) -> void:
	_apply_population_life_state(entity, previous_state, next_state)


func _apply_population_life_state(entity, previous_state: int, next_state: int) -> void:
	var population = entity.get_component(C_POPULATION_RECORD) if entity != null and is_instance_valid(entity) else null
	if population == null:
		return
	population.life_state = next_state
	if previous_state == next_state:
		return
	if previous_state != NpcRules.LifeState.DEAD and next_state == NpcRules.LifeState.DEAD:
		_adjust_alive_population_count(str(population.settlement_id), -1)
		population.body_state = "corpse"
		population.body_container_id = ""
		population.assigned_slot_id = ""
		_reindex_corpse_record(population)
	elif previous_state == NpcRules.LifeState.DEAD and next_state != NpcRules.LifeState.DEAD:
		_adjust_alive_population_count(str(population.settlement_id), 1)
	population_life_state_changed.emit(str(population.actor_id), previous_state, next_state)


## Lightweight counts for the on-screen brain/observability HUD. Reads component
## fields directly and avoids the full record/inventory build of
## get_population_records(), so it is cheap enough to poll a few times a second.
func get_brain_metrics() -> Dictionary:
	var metrics := {
		"population": 0,
		"realized": 0,
		"ledger": 0,
		"live_nodes": get_all_actors().size(),
		"world_process_ms": _last_world_process_usec / 1000.0,
		"squads": _world_sim_squad_entity_by_id.size(),
	}
	if world == null:
		return metrics
	for entity in world.query.with_all([C_POPULATION_RECORD]).execute():
		var component = entity.get_component(C_POPULATION_RECORD)
		if component == null:
			continue
		metrics["population"] += 1
		if str(component.realization_state) == "realized":
			metrics["realized"] += 1
		else:
			metrics["ledger"] += 1
	return metrics


## World-brain debug log. Any world-sim system pushes a one-line "what the
## off-screen brain decided" entry; the HUD panel mirrors it. Bounded ring buffer.
func log_world_event(category: String, message: String, data: Dictionary = {}) -> void:
	var entry := {
		"time": _world_brain_time_stamp(),
		"category": str(category),
		"message": str(message),
		"data": data.duplicate(true),
	}
	_world_brain_log.append(entry)
	if _world_brain_log.size() > WORLD_BRAIN_LOG_CAP:
		_world_brain_log = _world_brain_log.slice(_world_brain_log.size() - WORLD_BRAIN_LOG_CAP)
	world_event_logged.emit(entry.duplicate(true))


func get_world_event_log() -> Array:
	return _world_brain_log.duplicate(true)


func _world_brain_time_stamp() -> String:
	# Format from OUR OWN world-time component via the shared leaf formatter — no reference to
	# WorldTimeController. That back-edge (gecs reaching into the time controller for format_time)
	# was the only thing making time<->gecs a CYCLE; time->gecs one-way (like every other
	# sync controller) is fine.
	var state := get_world_time_state()
	if state.is_empty():
		return ""
	return WorldTimeFormat.format(float(state.get("total_world_minutes", 0.0)))


## World-sim squads: cheap data-only squads with a real world position. One entity
## per squad (mirrors the population-record pattern). WorldSimSquadController moves
## them; the map/log read them. Owner (nest/town/faction) sets the objective.
func upsert_world_sim_squad(record: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null or record.is_empty():
		return {}
	var squad_id := str(record.get("squad_id", "")).strip_edges()
	if squad_id.is_empty():
		return {}
	var entity = _world_sim_squad_entity_by_id.get(squad_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("WorldSimSquad", squad_id)
		entity.id = _entity_id("world_sim_squad", squad_id)
		world.add_entity(entity, [C_WORLD_SIM_SQUAD.new()])
		_world_sim_squad_entity_by_id[squad_id] = entity
	var component = entity.get_component(C_WORLD_SIM_SQUAD)
	component.apply_record(record)
	return component.to_record()


func get_world_sim_squads() -> Array:
	var squads: Array = []
	if world == null:
		return squads
	for entity in world.query.with_all([C_WORLD_SIM_SQUAD]).execute():
		var component = entity.get_component(C_WORLD_SIM_SQUAD)
		if component != null and component.has_method("to_record"):
			squads.append(component.to_record())
	return squads


func remove_world_sim_squad(squad_id: String) -> void:
	var entity = _world_sim_squad_entity_by_id.get(squad_id)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)
	_world_sim_squad_entity_by_id.erase(squad_id)


func upsert_building_record(record: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null or record.is_empty():
		return {}
	var building_id := str(record.get("building_id", "")).strip_edges()
	if building_id.is_empty():
		return {}
	var entity = _building_entity_by_id.get(building_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("Building", building_id)
		entity.id = _entity_id("building", building_id)
		world.add_entity(entity, [C_BUILDING_RECORD.new()])
		_building_entity_by_id[building_id] = entity
	var component = entity.get_component(C_BUILDING_RECORD)
	component.apply_record(record)
	return component.to_record()


func get_building_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if world == null:
		return records
	for entity in world.query.with_all([C_BUILDING_RECORD]).execute():
		var component = entity.get_component(C_BUILDING_RECORD)
		if component == null:
			continue
		var record: Dictionary = component.to_record()
		records.append(record)
		_building_entity_by_id[str(record["building_id"])] = entity
	return records


func upsert_settlement_state(settlement_id: String, state: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null or settlement_id.strip_edges().is_empty():
		return {}
	var entity = _settlement_entity_by_id.get(settlement_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("Settlement", settlement_id)
		entity.id = _entity_id("settlement", settlement_id)
		world.add_entity(entity, [C_SETTLEMENT_STATE.new()])
		_settlement_entity_by_id[settlement_id] = entity
	var component = entity.get_component(C_SETTLEMENT_STATE)
	var updated := state.duplicate(true)
	updated["settlement_id"] = settlement_id
	component.apply_state(updated)
	return component.to_state()


func upsert_settlement_food_status(settlement_id: String, status: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null or settlement_id.is_empty():
		return {}
	var script = load(C_SETTLEMENT_FOOD_STATUS_PATH)
	var entity = _settlement_food_entity_by_id.get(settlement_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("SettlementFood", settlement_id)
		entity.id = _entity_id("settlement_food", settlement_id)
		world.add_entity(entity, [script.new()])
		_settlement_food_entity_by_id[settlement_id] = entity
	var component = entity.get_component(script)
	var updated := status.duplicate(true)
	updated["settlement_id"] = settlement_id
	component.apply_status(updated)
	return component.to_status()


func get_settlement_food_statuses() -> Dictionary:
	var statuses: Dictionary = {}
	if world == null:
		return statuses
	var script = load(C_SETTLEMENT_FOOD_STATUS_PATH)
	for entity in world.query.with_all([script]).execute():
		var component = entity.get_component(script)
		if component != null:
			statuses[str(component.settlement_id)] = component.to_status()
			_settlement_food_entity_by_id[str(component.settlement_id)] = entity
	return statuses


func record_settlement_event(event_record: Dictionary) -> void:
	_try_initialize()
	if world == null or event_record.is_empty():
		return
	var settlement_id := str(event_record.get("settlement_id", "world"))
	var event_type := str(event_record.get("type", "event"))
	log_world_event("town:" + settlement_id, str(event_record.get("summary", event_type)), event_record)
	var absolute_minute := int(event_record.get("absolute_minute", -1))
	var event_id := str(event_record.get("event_id", ""))
	if event_id.is_empty():
		event_id = "%s:%s:%d:%d" % [settlement_id, event_type, absolute_minute, _settlement_event_entity_by_id.size()]
	var entity = _settlement_event_entity_by_id.get(event_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("SettlementEvent", event_id)
		entity.id = _entity_id("settlement_event", event_id)
		world.add_entity(entity, [C_SETTLEMENT_EVENT.new()])
		_settlement_event_entity_by_id[event_id] = entity
	var component = entity.get_component(C_SETTLEMENT_EVENT)
	component.event_id = event_id
	component.settlement_id = settlement_id
	component.event_type = event_type
	component.absolute_minute = absolute_minute
	component.day = int(event_record.get("day", -1))
	component.hour = int(event_record.get("hour", -1))
	component.minute = int(event_record.get("minute", -1))
	component.data = event_record.duplicate(true)


func get_settlement_state(settlement_id: String) -> Dictionary:
	var entity = _settlement_entity_by_id.get(settlement_id)
	if entity == null or not is_instance_valid(entity):
		return {}
	var component = entity.get_component(C_SETTLEMENT_STATE)
	return _derive_settlement_staff_counts(component.to_state()) if component != null and component.has_method("to_state") else {}


func get_settlement_states() -> Dictionary:
	var states: Dictionary = {}
	if world == null:
		return states
	for entity in world.query.with_all([C_SETTLEMENT_STATE]).execute():
		var component = entity.get_component(C_SETTLEMENT_STATE)
		if component == null:
			continue
		states[str(component.settlement_id)] = _derive_settlement_staff_counts(component.to_state()) if component.has_method("to_state") else {}
		_settlement_entity_by_id[str(component.settlement_id)] = entity
	return states


func _derive_settlement_staff_counts(state: Dictionary) -> Dictionary:
	var updated := state.duplicate(true)
	var slots: Dictionary = updated.get("staff_slots", {})
	var vacancies: Dictionary = (updated.get("staff_vacancies", {}) as Dictionary).duplicate(true)
	var required_count := 0
	var assigned_count := 0
	for slot_id_value in slots.keys():
		var slot_id := str(slot_id_value)
		var slot = slots.get(slot_id_value)
		if not (slot is Dictionary):
			continue
		var slot_record: Dictionary = slot
		var cost: int = max(0, int(slot_record.get("population_cost", 1)))
		required_count += cost
		if bool(slot_record.get("filled", false)):
			assigned_count += cost
			vacancies.erase(slot_id)
	updated["population_required_staff"] = required_count
	updated["population_assigned"] = clampi(assigned_count, 0, max(0, int(updated.get("population", assigned_count))))
	updated["population_available"] = max(0, int(updated.get("population", 0)) - int(updated.get("population_assigned", 0)))
	updated["population_shortfall"] = max(0, int(updated.get("population_target", updated.get("population", 0))) - int(updated.get("population", 0)))
	updated["staff_vacancies"] = vacancies
	return updated


func upsert_staff_slot(settlement_id: String, slot_id: String, slot: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null or settlement_id.is_empty() or slot_id.is_empty():
		return {}
	var key: String = "%s:%s" % [settlement_id, slot_id]
	var entity = _staff_slot_entity_by_key.get(key)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("StaffSlot", key)
		entity.id = _entity_id("staff_slot", key)
		world.add_entity(entity, [C_STAFF_SLOT.new()])
		_staff_slot_entity_by_key[key] = entity
	var component = entity.get_component(C_STAFF_SLOT)
	var updated := slot.duplicate(true)
	updated["slot_id"] = slot_id
	updated["settlement_id"] = settlement_id
	component.apply_slot(updated)
	return component.to_slot()


func remove_staff_slot(settlement_id: String, slot_id: String) -> void:
	var key: String = "%s:%s" % [settlement_id, slot_id]
	var entity = _staff_slot_entity_by_key.get(key)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)
	_staff_slot_entity_by_key.erase(key)


func clear_staff_slots_for_settlement(settlement_id: String) -> void:
	if settlement_id.is_empty():
		return
	var remove_keys: Array[String] = []
	for key in _staff_slot_entity_by_key.keys():
		if str(key).begins_with("%s:" % settlement_id):
			remove_keys.append(str(key))
	for key in remove_keys:
		var entity = _staff_slot_entity_by_key.get(key)
		if entity != null and is_instance_valid(entity) and world != null:
			world.remove_entity(entity)
		_staff_slot_entity_by_key.erase(key)


func get_staff_slot(settlement_id: String, slot_id: String) -> Dictionary:
	var key: String = "%s:%s" % [settlement_id, slot_id]
	var entity = _staff_slot_entity_by_key.get(key)
	if entity == null or not is_instance_valid(entity):
		return {}
	var component = entity.get_component(C_STAFF_SLOT)
	return component.to_slot() if component != null and component.has_method("to_slot") else {}


func get_staff_slots(settlement_id := "") -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if world == null:
		return slots
	for entity in world.query.with_all([C_STAFF_SLOT]).execute():
		var component = entity.get_component(C_STAFF_SLOT)
		if component == null:
			continue
		if not settlement_id.is_empty() and str(component.settlement_id) != settlement_id:
			continue
		slots.append(component.to_slot() if component.has_method("to_slot") else {})
		_staff_slot_entity_by_key["%s:%s" % [str(component.settlement_id), str(component.slot_id)]] = entity
	return slots


func sync_actor_inventory(actor: Node) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	_try_initialize()
	if world == null:
		return
	var actor_id := _actor_record_id(actor)
	if actor_id.is_empty():
		actor_id = _actor_id_for_actor(actor, _actor_settlement_id(actor))
	if actor_id.is_empty():
		return
	var inventory = actor.get("inventory")
	if inventory != null:
		_sync_inventory_container(actor_id, "%s.inventory" % actor_id, actor, inventory, false)
	var work_inventory = actor.get("_work_inventory_override") if _has_property(actor, "_work_inventory_override") else null
	if work_inventory != null:
		_sync_inventory_container(actor_id, "%s.work_inventory" % actor_id, actor, work_inventory, true)
	_sync_equipment_slots(actor_id, actor)


func sync_world_container(container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	_try_initialize()
	if world == null:
		return
	var inventory = container.get("inventory") if _has_property(container, "inventory") else null
	if inventory == null:
		return
	var container_id := str(container.get("container_id")).strip_edges() if _has_property(container, "container_id") else ""
	if container_id.is_empty():
		return
	_sync_inventory_container("", container_id, container, inventory, false, true)


func get_item_stack_entity(stack_id: String):
	return _item_stack_entity_by_id.get(stack_id)


func register_item_stack_entity(stack_id: String, entity) -> void:
	_item_stack_entity_by_id[stack_id] = entity


func remove_item_stack_entity(stack_id: String) -> void:
	var entity = _item_stack_entity_by_id.get(stack_id)
	_item_stack_entity_by_id.erase(stack_id)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)


func get_inventory_container_entity(container_id: String):
	return _inventory_container_entity_by_id.get(container_id)


func register_inventory_container_entity(container_id: String, entity) -> void:
	_inventory_container_entity_by_id[container_id] = entity


func remove_inventory_container_entity(container_id: String) -> void:
	var entity = _inventory_container_entity_by_id.get(container_id)
	_inventory_container_entity_by_id.erase(container_id)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)


func upsert_item_stack_record(record: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null:
		return {}
	var item_path := str(record.get("item_definition_path", "")).strip_edges()
	if item_path.is_empty():
		return {}
	var stack_id := str(record.get("stack_id", "")).strip_edges()
	if stack_id.is_empty():
		return {}
	var entity = _item_stack_entity_by_id.get(stack_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("WorldItem", stack_id)
		entity.id = _entity_id("item_stack", stack_id)
		world.add_entity(entity, [C_ITEM_STACK.new()])
		_item_stack_entity_by_id[stack_id] = entity
	var component = entity.get_component(C_ITEM_STACK)
	component.stack_id = stack_id
	component.container_id = str(record.get("container_id", "world"))
	component.owner_actor_id = str(record.get("owner_actor_id", ""))
	component.item_definition_path = item_path
	component.count = maxi(1, int(record.get("count", 1)))
	component.grid_position = record.get("grid_position", Vector2i.ZERO)
	component.contained_item_counts = (record.get("contained_item_counts", {}) as Dictionary).duplicate(true)
	component.metadata = (record.get("metadata", {}) as Dictionary).duplicate(true)
	component.location_kind = str(record.get("location_kind", "inventory"))
	component.world_transform = record.get("world_transform", Transform3D.IDENTITY)
	component.placement_host_id = str(record.get("placement_host_id", ""))
	component.placement_slot_id = str(record.get("placement_slot_id", ""))
	component.location_settlement_id = str(record.get("location_settlement_id", ""))
	return get_item_stack(stack_id)


func get_inventory_stacks(container_id := "") -> Array[Dictionary]:
	var stacks: Array[Dictionary] = []
	if world == null:
		return stacks
	for entity in world.query.with_all([C_ITEM_STACK]).execute():
		var component = entity.get_component(C_ITEM_STACK)
		if component == null:
			continue
		if not container_id.is_empty() and str(component.container_id) != container_id:
			continue
		stacks.append({
			"stack_id": str(component.stack_id),
			"container_id": str(component.container_id),
			"owner_actor_id": str(component.owner_actor_id),
			"item_definition_path": str(component.item_definition_path),
			"count": int(component.count),
			"grid_position": component.grid_position,
			"contained_item_counts": component.contained_item_counts.duplicate(true),
			"metadata": component.metadata.duplicate(true),
			"location_kind": str(component.location_kind),
			"world_transform": component.world_transform,
			"placement_host_id": str(component.placement_host_id),
			"placement_slot_id": str(component.placement_slot_id),
			"location_settlement_id": str(component.location_settlement_id),
		})
	return stacks


func get_item_stack(stack_id: String) -> Dictionary:
	var entity = _item_stack_entity_by_id.get(stack_id)
	var component = entity.get_component(C_ITEM_STACK) if entity != null and is_instance_valid(entity) else null
	if component == null:
		return {}
	return {
		"stack_id": str(component.stack_id),
		"container_id": str(component.container_id),
		"owner_actor_id": str(component.owner_actor_id),
		"item_definition_path": str(component.item_definition_path),
		"count": int(component.count),
		"grid_position": component.grid_position,
		"contained_item_counts": component.contained_item_counts.duplicate(true),
		"metadata": component.metadata.duplicate(true),
		"location_kind": str(component.location_kind),
		"world_transform": component.world_transform,
		"placement_host_id": str(component.placement_host_id),
		"placement_slot_id": str(component.placement_slot_id),
		"location_settlement_id": str(component.location_settlement_id),
	}


func get_equipment_slots(actor_id := "") -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if world == null:
		return slots
	for entity in world.query.with_all([C_EQUIPMENT_SLOT]).execute():
		var component = entity.get_component(C_EQUIPMENT_SLOT)
		if component == null:
			continue
		if not actor_id.is_empty() and str(component.actor_id) != actor_id:
			continue
		slots.append({
			"actor_id": str(component.actor_id),
			"slot_name": str(component.slot_name),
			"item_definition_path": str(component.item_definition_path),
			"stack_id": str(component.stack_id),
		})
	return slots


func sync_job_provider(provider: Node, active_slots: Dictionary = {}, worker_records: Dictionary = {}, sim_time := 0.0) -> void:
	if provider == null or not is_instance_valid(provider):
		return
	_try_initialize()
	if world == null:
		return
	var provider_id := _provider_id(provider)
	var provider_entity = _job_provider_entity_by_id.get(provider_id)
	if provider_entity == null or not is_instance_valid(provider_entity):
		provider_entity = _entity_script.new()
		provider_entity.name = _entity_node_name("JobProvider", provider_id)
		provider_entity.id = _entity_id("job_provider", provider_id)
		world.add_entity(provider_entity, [C_JOB_PROVIDER.new()])
		_job_provider_entity_by_id[provider_id] = provider_entity
	var provider_component = provider_entity.get_component(C_JOB_PROVIDER)
	provider_component.provider_id = provider_id
	provider_component.provider_name = provider.call("get_provider_name") if provider.has_method("get_provider_name") else str(provider.name)
	provider_component.provider_path = provider.get_path() if provider.is_inside_tree() else NodePath()
	var provider_owner = provider.call("get_provider_character") if provider.has_method("get_provider_character") else null
	provider_component.owner_actor_id = _actor_record_id(provider_owner) if provider_owner is Node else ""
	provider_component.sim_time = sim_time
	_sync_job_provider_slots(provider_id, active_slots)
	_sync_job_worker_records(provider_id, worker_records)


func upsert_job_contract(data: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null or data.is_empty():
		return {}
	var contract_id := str(data.get("contract_id", "")).strip_edges()
	if contract_id.is_empty():
		contract_id = _make_job_contract_id(data)
	data["contract_id"] = contract_id
	if not data.has("priority_order"):
		data["priority_order"] = _next_job_contract_priority(str(data.get("actor_id", "")))
	var entity = _job_contract_entity_by_id.get(contract_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("JobContract", contract_id)
		entity.id = _entity_id("job_contract", contract_id)
		world.add_entity(entity, [C_JOB_CONTRACT.new()])
		_job_contract_entity_by_id[contract_id] = entity
	var component = entity.get_component(C_JOB_CONTRACT)
	component.apply_data(data)
	return component.to_dictionary()


func get_actor_job_contracts(actor_or_id) -> Array[Dictionary]:
	var actor_id := _actor_id_from_value(actor_or_id)
	var contracts: Array[Dictionary] = []
	if world == null or actor_id.is_empty():
		return contracts
	for entity in world.query.with_all([C_JOB_CONTRACT]).execute():
		var component = entity.get_component(C_JOB_CONTRACT)
		if component == null or str(component.actor_id) != actor_id:
			continue
		contracts.append(component.to_dictionary())
	contracts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("priority_order", 0)) < int(b.get("priority_order", 0)))
	return contracts


func get_job_contracts_for_provider(provider_or_id) -> Array[Dictionary]:
	var provider_id := _provider_id_from_value(provider_or_id)
	var contracts: Array[Dictionary] = []
	if world == null or provider_id.is_empty():
		return contracts
	for entity in world.query.with_all([C_JOB_CONTRACT]).execute():
		var component = entity.get_component(C_JOB_CONTRACT)
		if component == null or str(component.provider_id) != provider_id:
			continue
		contracts.append(component.to_dictionary())
	contracts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("priority_order", 0)) < int(b.get("priority_order", 0)))
	return contracts


func has_actor_job_contract(actor_or_id, provider_or_id, job_id := "") -> bool:
	var actor_id := _actor_id_from_value(actor_or_id)
	var provider_id := _provider_id_from_value(provider_or_id)
	for contract in get_actor_job_contracts(actor_id):
		if str(contract.get("provider_id", "")) != provider_id:
			continue
		if job_id.is_empty() or str(contract.get("job_id", "")) == job_id:
			return true
	return false


func move_actor_job_contract(actor_or_id, contract_id: String, direction: int) -> Array[Dictionary]:
	var actor_id := _actor_id_from_value(actor_or_id)
	var contracts := get_actor_job_contracts(actor_id)
	var from_index := -1
	for index in range(contracts.size()):
		if str(contracts[index].get("contract_id", "")) == contract_id:
			from_index = index
			break
	if from_index < 0:
		return contracts
	var to_index := clampi(from_index + direction, 0, contracts.size() - 1)
	if to_index == from_index:
		return contracts
	var moved := contracts[from_index]
	contracts.remove_at(from_index)
	contracts.insert(to_index, moved)
	_rewrite_job_contract_priorities(contracts)
	return get_actor_job_contracts(actor_id)


func abandon_job_contract(actor_or_id, contract_id: String, reason := "quit", sim_time := 0.0) -> bool:
	var actor_id := _actor_id_from_value(actor_or_id)
	var entity = _job_contract_entity_by_id.get(contract_id)
	if entity == null or not is_instance_valid(entity):
		return false
	var component = entity.get_component(C_JOB_CONTRACT)
	if component == null or (not actor_id.is_empty() and str(component.actor_id) != actor_id):
		return false
	var contract: Dictionary = component.to_dictionary()
	record_job_provider_memory({
		"provider_id": str(contract.get("provider_id", "")),
		"actor_id": str(contract.get("actor_id", "")),
		"job_id": str(contract.get("job_id", "")),
		"reason": reason,
		"recorded_at": sim_time,
		"note": "Job contract abandoned",
	})
	_notify_live_provider_contract_abandoned(contract, reason)
	world.remove_entity(entity)
	_job_contract_entity_by_id.erase(contract_id)
	_rewrite_job_contract_priorities(get_actor_job_contracts(str(contract.get("actor_id", ""))))
	return true


func expire_missed_job_contracts(sim_time: float) -> int:
	var expired: Array[Dictionary] = []
	if world == null:
		return 0
	for entity in world.query.with_all([C_JOB_CONTRACT]).execute():
		var component = entity.get_component(C_JOB_CONTRACT)
		if component == null:
			continue
		if str(component.status) != "active":
			continue
		if _is_player_party_job_contract(component.to_dictionary()):
			continue
		if float(component.report_deadline) > 0.0 and float(component.last_started_at) < 0.0 and float(component.report_deadline) < sim_time:
			expired.append(component.to_dictionary())
	for contract in expired:
		abandon_job_contract(str(contract.get("actor_id", "")), str(contract.get("contract_id", "")), "no_show", sim_time)
	return expired.size()


func _is_player_party_job_contract(contract: Dictionary) -> bool:
	var metadata: Dictionary = contract.get("metadata", {}) if contract.get("metadata", {}) is Dictionary else {}
	if bool(metadata.get("player_party_member", false)):
		return true
	var actor_id := str(contract.get("actor_id", ""))
	var actor := get_actor_by_stable_id(actor_id)
	return actor != null and actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member"))


func mark_job_contract_started(contract_id: String, sim_time: float) -> void:
	var entity = _job_contract_entity_by_id.get(contract_id)
	if entity == null or not is_instance_valid(entity):
		return
	var component = entity.get_component(C_JOB_CONTRACT)
	if component == null:
		return
	component.last_started_at = sim_time


func record_job_provider_memory(data: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null or data.is_empty():
		return {}
	var provider_id := str(data.get("provider_id", "")).strip_edges()
	var actor_id := str(data.get("actor_id", "")).strip_edges()
	var job_id := str(data.get("job_id", "")).strip_edges()
	if provider_id.is_empty() or actor_id.is_empty():
		return {}
	var memory_id := str(data.get("memory_id", "")).strip_edges()
	if memory_id.is_empty():
		memory_id = "%s:%s:%s:%d" % [provider_id, actor_id, job_id, int(float(data.get("recorded_at", 0.0)) * 1000.0)]
	data["memory_id"] = memory_id
	var entity = _job_provider_memory_entity_by_id.get(memory_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("JobProviderMemory", memory_id)
		entity.id = _entity_id("job_provider_memory", memory_id)
		world.add_entity(entity, [C_JOB_PROVIDER_MEMORY.new()])
		_job_provider_memory_entity_by_id[memory_id] = entity
	var component = entity.get_component(C_JOB_PROVIDER_MEMORY)
	component.apply_data(data)
	return component.to_dictionary()


func get_job_provider_memory(provider_or_id) -> Array[Dictionary]:
	var provider_id := _provider_id_from_value(provider_or_id)
	var records: Array[Dictionary] = []
	if world == null or provider_id.is_empty():
		return records
	for entity in world.query.with_all([C_JOB_PROVIDER_MEMORY]).execute():
		var component = entity.get_component(C_JOB_PROVIDER_MEMORY)
		if component != null and str(component.provider_id) == provider_id:
			records.append(component.to_dictionary())
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("recorded_at", 0.0)) > float(b.get("recorded_at", 0.0)))
	return records


func upsert_activity_point(settlement_id: String, point: Node) -> void:
	if point == null or settlement_id.is_empty():
		return
	_try_initialize()
	if world == null:
		return
	var activity_id := str(point.call("get_activity_id")) if point.has_method("get_activity_id") else str(point.name)
	if activity_id.is_empty():
		return
	var entity = _activity_point_entity_by_id.get(activity_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("ActivityPoint", activity_id)
		entity.id = _entity_id("activity_point", activity_id)
		world.add_entity(entity, [C_ACTIVITY_POINT.new()])
		_activity_point_entity_by_id[activity_id] = entity
	var component = entity.get_component(C_ACTIVITY_POINT)
	component.activity_id = activity_id
	component.settlement_id = settlement_id
	component.point_path = point.get_path() if point.is_inside_tree() else NodePath()
	var weight = point.get("weight") if _has_property(point, "weight") else 1.0
	component.weight = float(weight) if weight != null else 1.0
	var min_seconds = point.get("assignment_min_seconds") if _has_property(point, "assignment_min_seconds") else component.assignment_min_seconds
	var max_seconds = point.get("assignment_max_seconds") if _has_property(point, "assignment_max_seconds") else component.assignment_max_seconds
	component.assignment_min_seconds = float(min_seconds) if min_seconds != null else component.assignment_min_seconds
	component.assignment_max_seconds = float(max_seconds) if max_seconds != null else component.assignment_max_seconds
	component.active = true


func set_activity_assignment(actor: Node, point: Node, duration: float, sim_time: float) -> void:
	if actor == null:
		return
	_try_initialize()
	if world == null:
		return
	var actor_id := _actor_record_id(actor)
	if actor_id.is_empty():
		return
	var activity_id := ""
	if point != null:
		activity_id = str(point.call("get_activity_id")) if point.has_method("get_activity_id") else str(point.name)
	var entity = _activity_assignment_entity_by_actor_id.get(actor_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("ActivityAssignment", actor_id)
		entity.id = _entity_id("activity_assignment", actor_id)
		world.add_entity(entity, [C_ACTIVITY_ASSIGNMENT.new()])
		_activity_assignment_entity_by_actor_id[actor_id] = entity
	var component = entity.get_component(C_ACTIVITY_ASSIGNMENT)
	component.actor_id = actor_id
	component.activity_id = activity_id
	component.settlement_id = _actor_settlement_id(actor)
	component.assigned_at = sim_time
	component.assignment_until = sim_time + maxf(duration, 0.0)
	component.point_path = point.get_path() if point != null and point.is_inside_tree() else NodePath()
	component.active = true
	component.point = point


func clear_activity_assignment(actor: Node) -> void:
	if actor == null:
		return
	var actor_id := _actor_record_id(actor)
	var entity = _activity_assignment_entity_by_actor_id.get(actor_id)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)
	_activity_assignment_entity_by_actor_id.erase(actor_id)


func upsert_world_time_state(state: Dictionary) -> Dictionary:
	_try_initialize()
	if world == null or state.is_empty():
		return {}
	var entity = _world_time_entity
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = "WorldTimeState"
		entity.id = _entity_id("world_time", "state")
		world.add_entity(entity, [C_WORLD_TIME.new()])
		_world_time_entity = entity
	var component = entity.get_component(C_WORLD_TIME)
	if component == null:
		return {}
	component.apply_state(state)
	return component.to_state()


func get_world_time_state() -> Dictionary:
	_try_initialize()
	if world == null:
		return {}
	if _world_time_entity == null or not is_instance_valid(_world_time_entity):
		for entity in world.query.with_all([C_WORLD_TIME]).execute():
			_world_time_entity = entity
			break
	if _world_time_entity == null or not is_instance_valid(_world_time_entity):
		return {}
	var component = _world_time_entity.get_component(C_WORLD_TIME)
	return component.to_state() if component != null and component.has_method("to_state") else {}


func upsert_law_order_state(state: Dictionary) -> Dictionary:
	_law_order_entity = _upsert_state_entity(_law_order_entity, "LawOrderState", _entity_id("law_order", "state"), C_LAW_ORDER)
	return _apply_state_component(_law_order_entity, C_LAW_ORDER, state)


func get_law_order_state() -> Dictionary:
	_law_order_entity = _find_state_entity(_law_order_entity, C_LAW_ORDER)
	return _state_component_to_dictionary(_law_order_entity, C_LAW_ORDER)


func upsert_faction_state(state: Dictionary) -> Dictionary:
	_faction_state_entity = _upsert_state_entity(_faction_state_entity, "FactionState", _entity_id("faction", "state"), C_FACTION_STATE)
	return _apply_state_component(_faction_state_entity, C_FACTION_STATE, state)


func get_faction_state() -> Dictionary:
	_faction_state_entity = _find_state_entity(_faction_state_entity, C_FACTION_STATE)
	return _state_component_to_dictionary(_faction_state_entity, C_FACTION_STATE)


func upsert_world_squad_state(state: Dictionary) -> Dictionary:
	_world_squad_entity = _upsert_state_entity(_world_squad_entity, "WorldSquadState", _entity_id("world_squad", "state"), C_WORLD_SQUAD)
	return _apply_state_component(_world_squad_entity, C_WORLD_SQUAD, state)


func get_world_squad_state() -> Dictionary:
	_world_squad_entity = _find_state_entity(_world_squad_entity, C_WORLD_SQUAD)
	return _state_component_to_dictionary(_world_squad_entity, C_WORLD_SQUAD)


func upsert_world_event_state(state: Dictionary) -> Dictionary:
	_world_event_entity = _upsert_state_entity(_world_event_entity, "WorldEventState", _entity_id("world_event", "state"), C_WORLD_EVENT)
	return _apply_state_component(_world_event_entity, C_WORLD_EVENT, state)


func get_world_event_state() -> Dictionary:
	_world_event_entity = _find_state_entity(_world_event_entity, C_WORLD_EVENT)
	return _state_component_to_dictionary(_world_event_entity, C_WORLD_EVENT)


func upsert_nest_state(state: Dictionary) -> Dictionary:
	_nest_state_entity = _upsert_state_entity(_nest_state_entity, "NestState", _entity_id("nest", "state"), C_NEST_STATE)
	return _apply_state_component(_nest_state_entity, C_NEST_STATE, state)


func get_nest_state() -> Dictionary:
	_nest_state_entity = _find_state_entity(_nest_state_entity, C_NEST_STATE)
	return _state_component_to_dictionary(_nest_state_entity, C_NEST_STATE)


func upsert_job_system_state(state: Dictionary) -> Dictionary:
	_job_system_entity = _upsert_state_entity(_job_system_entity, "JobSystemState", _entity_id("job_system", "state"), C_JOB_SYSTEM)
	return _apply_state_component(_job_system_entity, C_JOB_SYSTEM, state)


func get_job_system_state() -> Dictionary:
	_job_system_entity = _find_state_entity(_job_system_entity, C_JOB_SYSTEM)
	return _state_component_to_dictionary(_job_system_entity, C_JOB_SYSTEM)


func upsert_ledger_simulation_state(state: Dictionary) -> Dictionary:
	_ledger_simulation_entity = _upsert_state_entity(_ledger_simulation_entity, "LedgerSimulationState", _entity_id("ledger_simulation", "state"), C_LEDGER_SIMULATION)
	return _apply_state_component(_ledger_simulation_entity, C_LEDGER_SIMULATION, state)


func get_ledger_simulation_state() -> Dictionary:
	_ledger_simulation_entity = _find_state_entity(_ledger_simulation_entity, C_LEDGER_SIMULATION)
	return _state_component_to_dictionary(_ledger_simulation_entity, C_LEDGER_SIMULATION)


func upsert_ai_scheduler_state(state: Dictionary) -> Dictionary:
	_ai_scheduler_state_entity = _upsert_state_entity(_ai_scheduler_state_entity, "AiSchedulerState", _entity_id("ai_scheduler", "state"), C_AI_SCHEDULER_STATE)
	return _apply_state_component(_ai_scheduler_state_entity, C_AI_SCHEDULER_STATE, state)


func get_ai_scheduler_state() -> Dictionary:
	_ai_scheduler_state_entity = _find_state_entity(_ai_scheduler_state_entity, C_AI_SCHEDULER_STATE)
	return _state_component_to_dictionary(_ai_scheduler_state_entity, C_AI_SCHEDULER_STATE)


func upsert_population_realization_state(state: Dictionary) -> Dictionary:
	_population_realization_state_entity = _upsert_state_entity(_population_realization_state_entity, "PopulationRealizationState", _entity_id("population_realization", "state"), C_POPULATION_REALIZATION_STATE)
	return _apply_state_component(_population_realization_state_entity, C_POPULATION_REALIZATION_STATE, state)


func get_population_realization_state() -> Dictionary:
	_population_realization_state_entity = _find_state_entity(_population_realization_state_entity, C_POPULATION_REALIZATION_STATE)
	return _state_component_to_dictionary(_population_realization_state_entity, C_POPULATION_REALIZATION_STATE)


func save_gecs_world(filepath: String, binary := false) -> bool:
	_try_initialize()
	if world == null or filepath.strip_edges().is_empty():
		return false
	_sync_live_scene_state_for_save()
	var data = _gecs_io_script.serialize_entities(world.entities)
	return bool(_gecs_io_script.save(data, filepath, binary))


func load_gecs_world(filepath: String) -> bool:
	_try_initialize()
	var clean_path := filepath.strip_edges()
	if world == null or clean_path.is_empty():
		return false
	var binary_path := clean_path.replace(".tres", ".res")
	if not ResourceLoader.exists(binary_path) and not ResourceLoader.exists(clean_path):
		return false
	var entities: Array = _gecs_io_script.deserialize(clean_path)
	if entities.is_empty():
		return false
	_migrate_loaded_construction_catalog_ids(entities)
	_clear_world_entities()
	for entity in entities:
		if entity != null:
			world.add_entity(entity)
	_rebuild_entity_indexes()
	world_reindexed.emit()
	return true


func _migrate_loaded_construction_catalog_ids(entities: Array) -> void:
	for entity in entities:
		if entity == null:
			continue
		var building = entity.get_component(C_BUILDING_RECORD)
		if building == null:
			continue
		var old_id := str(building.catalog_id)
		if CONSTRUCTION_CATALOG_ID_LOAD_MIGRATIONS.has(old_id):
			building.catalog_id = CONSTRUCTION_CATALOG_ID_LOAD_MIGRATIONS[old_id]


func can_tick_actor_ai_job(actor: Node) -> bool:
	var entity = _actor_entity_for_actor(actor)
	if entity == null or not is_instance_valid(entity):
		return false
	var ai_state = entity.get_component(C_AI_STATE)
	return ai_state != null and ai_state.active_job != null and ai_state.active_driver != null


func get_spatial_cell_count() -> int:
	var cells := {}
	if world == null:
		return 0
	for entity in world.query.with_all([C_SPATIAL]).execute():
		var spatial = entity.get_component(C_SPATIAL)
		if spatial != null and bool(spatial.position_initialized):
			cells[spatial.spatial_cell] = true
	return cells.size()


func serialize_state() -> Dictionary:
	return {
		"actor_entity_count": _actor_entity_by_actor_id.size(),
		"population_entity_count": _population_entity_by_actor_id.size(),
		"settlement_entity_count": _settlement_entity_by_id.size(),
		"building_entity_count": _building_entity_by_id.size(),
		"staff_slot_entity_count": _staff_slot_entity_by_key.size(),
		"inventory_container_entity_count": _inventory_container_entity_by_id.size(),
		"item_stack_entity_count": _item_stack_entity_by_id.size(),
		"equipment_slot_entity_count": _equipment_slot_entity_by_key.size(),
		"world_time_entity_count": 1 if _world_time_entity != null and is_instance_valid(_world_time_entity) else 0,
		"law_order_entity_count": 1 if _law_order_entity != null and is_instance_valid(_law_order_entity) else 0,
		"faction_state_entity_count": 1 if _faction_state_entity != null and is_instance_valid(_faction_state_entity) else 0,
		"world_squad_entity_count": 1 if _world_squad_entity != null and is_instance_valid(_world_squad_entity) else 0,
		"world_event_entity_count": 1 if _world_event_entity != null and is_instance_valid(_world_event_entity) else 0,
		"nest_state_entity_count": 1 if _nest_state_entity != null and is_instance_valid(_nest_state_entity) else 0,
		"job_system_entity_count": 1 if _job_system_entity != null and is_instance_valid(_job_system_entity) else 0,
		"ledger_simulation_entity_count": 1 if _ledger_simulation_entity != null and is_instance_valid(_ledger_simulation_entity) else 0,
		"ai_scheduler_state_entity_count": 1 if _ai_scheduler_state_entity != null and is_instance_valid(_ai_scheduler_state_entity) else 0,
		"population_realization_state_entity_count": 1 if _population_realization_state_entity != null and is_instance_valid(_population_realization_state_entity) else 0,
		"job_contract_entity_count": _job_contract_entity_by_id.size(),
		"job_provider_memory_entity_count": _job_provider_memory_entity_by_id.size(),
		"spatial_cell_count": get_spatial_cell_count(),
		"world_entity_count": world.entities.size() if world != null else 0,
	}


func _load_gecs_scripts() -> bool:
	if _world_script != null and _entity_script != null and _ecs_script != null and _gecs_io_script != null and _actor_sync_system_script != null and _ai_job_system_script != null and _combat_state_sync_system_script != null and _combat_targeting_system_script != null and _combat_slot_system_script != null and _combat_resolution_system_script != null and _vitals_system_script != null and _population_vitals_system_script != null and _combat_movement_system_script != null and _component_scripts_loaded():
		return true
	_ensure_direct_script_ecs_singleton()
	_load_component_scripts()
	_world_script = load(WORLD_SCRIPT_PATH) if _world_script == null else _world_script
	_entity_script = load(ENTITY_SCRIPT_PATH) if _entity_script == null else _entity_script
	_ecs_script = load(ECS_SCRIPT_PATH) if _ecs_script == null else _ecs_script
	_gecs_io_script = load(GECS_IO_SCRIPT_PATH) if _gecs_io_script == null else _gecs_io_script
	_actor_sync_system_script = load(ACTOR_SYNC_SYSTEM_SCRIPT_PATH) if _actor_sync_system_script == null else _actor_sync_system_script
	_ai_job_system_script = load(AI_JOB_SYSTEM_SCRIPT_PATH) if _ai_job_system_script == null else _ai_job_system_script
	_combat_state_sync_system_script = load(COMBAT_STATE_SYNC_SYSTEM_SCRIPT_PATH) if _combat_state_sync_system_script == null else _combat_state_sync_system_script
	_combat_score_system_script = load(COMBAT_SCORE_SYSTEM_SCRIPT_PATH) if _combat_score_system_script == null else _combat_score_system_script
	_combat_targeting_system_script = load(COMBAT_TARGETING_SYSTEM_SCRIPT_PATH) if _combat_targeting_system_script == null else _combat_targeting_system_script
	_combat_slot_system_script = load(COMBAT_SLOT_SYSTEM_SCRIPT_PATH) if _combat_slot_system_script == null else _combat_slot_system_script
	_combat_resolution_system_script = load(COMBAT_RESOLUTION_SYSTEM_SCRIPT_PATH) if _combat_resolution_system_script == null else _combat_resolution_system_script
	_vitals_system_script = load(VITALS_SYSTEM_SCRIPT_PATH) if _vitals_system_script == null else _vitals_system_script
	_population_vitals_system_script = load(POPULATION_VITALS_SYSTEM_SCRIPT_PATH) if _population_vitals_system_script == null else _population_vitals_system_script
	_combat_movement_system_script = load(COMBAT_MOVEMENT_SYSTEM_SCRIPT_PATH) if _combat_movement_system_script == null else _combat_movement_system_script
	return _world_script != null and _entity_script != null and _ecs_script != null and _gecs_io_script != null and _actor_sync_system_script != null and _ai_job_system_script != null and _combat_state_sync_system_script != null and _combat_targeting_system_script != null and _combat_slot_system_script != null and _combat_resolution_system_script != null and _vitals_system_script != null and _population_vitals_system_script != null and _combat_movement_system_script != null and _component_scripts_loaded()


func _load_component_scripts() -> void:
	C_NODE = load(C_NODE_PATH) if C_NODE == null else C_NODE
	C_IDENTITY = load(C_IDENTITY_PATH) if C_IDENTITY == null else C_IDENTITY
	C_FACTION = load(C_FACTION_PATH) if C_FACTION == null else C_FACTION
	C_SETTLEMENT = load(C_SETTLEMENT_PATH) if C_SETTLEMENT == null else C_SETTLEMENT
	C_SPATIAL = load(C_SPATIAL_PATH) if C_SPATIAL == null else C_SPATIAL
	C_VITALS = load(C_VITALS_PATH) if C_VITALS == null else C_VITALS
	C_VITALS_INPUTS = load(C_VITALS_INPUTS_PATH) if C_VITALS_INPUTS == null else C_VITALS_INPUTS
	C_AI_SCHEDULE = load(C_AI_SCHEDULE_PATH) if C_AI_SCHEDULE == null else C_AI_SCHEDULE
	C_AI_STATE = load(C_AI_STATE_PATH) if C_AI_STATE == null else C_AI_STATE
	C_GOAL_INTENT = load(C_GOAL_INTENT_PATH) if C_GOAL_INTENT == null else C_GOAL_INTENT
	C_POPULATION_RECORD = load(C_POPULATION_RECORD_PATH) if C_POPULATION_RECORD == null else C_POPULATION_RECORD
	C_ACTIVE_POPULATION_VITALS = load(C_ACTIVE_POPULATION_VITALS_PATH) if C_ACTIVE_POPULATION_VITALS == null else C_ACTIVE_POPULATION_VITALS
	C_SETTLEMENT_STATE = load(C_SETTLEMENT_STATE_PATH) if C_SETTLEMENT_STATE == null else C_SETTLEMENT_STATE
	C_STAFF_SLOT = load(C_STAFF_SLOT_PATH) if C_STAFF_SLOT == null else C_STAFF_SLOT
	C_STAFF_VACANCY = load(C_STAFF_VACANCY_PATH) if C_STAFF_VACANCY == null else C_STAFF_VACANCY
	C_INVENTORY_CONTAINER = load(C_INVENTORY_CONTAINER_PATH) if C_INVENTORY_CONTAINER == null else C_INVENTORY_CONTAINER
	C_ITEM_STACK = load(C_ITEM_STACK_PATH) if C_ITEM_STACK == null else C_ITEM_STACK
	C_EQUIPMENT_SLOT = load(C_EQUIPMENT_SLOT_PATH) if C_EQUIPMENT_SLOT == null else C_EQUIPMENT_SLOT
	C_SETTLEMENT_EVENT = load(C_SETTLEMENT_EVENT_PATH) if C_SETTLEMENT_EVENT == null else C_SETTLEMENT_EVENT
	C_JOB_PROVIDER = load(C_JOB_PROVIDER_PATH) if C_JOB_PROVIDER == null else C_JOB_PROVIDER
	C_JOB_PROVIDER_SLOT = load(C_JOB_PROVIDER_SLOT_PATH) if C_JOB_PROVIDER_SLOT == null else C_JOB_PROVIDER_SLOT
	C_JOB_WORKER_RECORD = load(C_JOB_WORKER_RECORD_PATH) if C_JOB_WORKER_RECORD == null else C_JOB_WORKER_RECORD
	C_JOB_CONTRACT = load(C_JOB_CONTRACT_PATH) if C_JOB_CONTRACT == null else C_JOB_CONTRACT
	C_JOB_PROVIDER_MEMORY = load(C_JOB_PROVIDER_MEMORY_PATH) if C_JOB_PROVIDER_MEMORY == null else C_JOB_PROVIDER_MEMORY
	C_ACTIVITY_POINT = load(C_ACTIVITY_POINT_PATH) if C_ACTIVITY_POINT == null else C_ACTIVITY_POINT
	C_ACTIVITY_ASSIGNMENT = load(C_ACTIVITY_ASSIGNMENT_PATH) if C_ACTIVITY_ASSIGNMENT == null else C_ACTIVITY_ASSIGNMENT
	C_WORLD_TIME = load(C_WORLD_TIME_PATH) if C_WORLD_TIME == null else C_WORLD_TIME
	C_LAW_ORDER = load(C_LAW_ORDER_PATH) if C_LAW_ORDER == null else C_LAW_ORDER
	C_FACTION_STATE = load(C_FACTION_STATE_PATH) if C_FACTION_STATE == null else C_FACTION_STATE
	C_WORLD_SQUAD = load(C_WORLD_SQUAD_PATH) if C_WORLD_SQUAD == null else C_WORLD_SQUAD
	C_WORLD_EVENT = load(C_WORLD_EVENT_PATH) if C_WORLD_EVENT == null else C_WORLD_EVENT
	C_NEST_STATE = load(C_NEST_STATE_PATH) if C_NEST_STATE == null else C_NEST_STATE
	C_JOB_SYSTEM = load(C_JOB_SYSTEM_PATH) if C_JOB_SYSTEM == null else C_JOB_SYSTEM
	C_LEDGER_SIMULATION = load(C_LEDGER_SIMULATION_PATH) if C_LEDGER_SIMULATION == null else C_LEDGER_SIMULATION
	C_AI_SCHEDULER_STATE = load(C_AI_SCHEDULER_STATE_PATH) if C_AI_SCHEDULER_STATE == null else C_AI_SCHEDULER_STATE
	C_POPULATION_REALIZATION_STATE = load(C_POPULATION_REALIZATION_STATE_PATH) if C_POPULATION_REALIZATION_STATE == null else C_POPULATION_REALIZATION_STATE
	C_COMBAT_LOADOUT = load(C_COMBAT_LOADOUT_PATH) if C_COMBAT_LOADOUT == null else C_COMBAT_LOADOUT
	C_COMBAT_CONFIG = load(C_COMBAT_CONFIG_PATH) if C_COMBAT_CONFIG == null else C_COMBAT_CONFIG
	C_COMBAT_STATE = load(C_COMBAT_STATE_PATH) if C_COMBAT_STATE == null else C_COMBAT_STATE
	C_COMBAT_SLOT_STATE = load(C_COMBAT_SLOT_STATE_PATH) if C_COMBAT_SLOT_STATE == null else C_COMBAT_SLOT_STATE
	C_COMBAT_ACTION = load(C_COMBAT_ACTION_PATH) if C_COMBAT_ACTION == null else C_COMBAT_ACTION
	C_MOVEMENT_STATE = load(C_MOVEMENT_STATE_PATH) if C_MOVEMENT_STATE == null else C_MOVEMENT_STATE
	C_WORLD_SIM_SQUAD = load(C_WORLD_SIM_SQUAD_PATH) if C_WORLD_SIM_SQUAD == null else C_WORLD_SIM_SQUAD
	C_BUILDING_RECORD = load(C_BUILDING_RECORD_PATH) if C_BUILDING_RECORD == null else C_BUILDING_RECORD


func _component_scripts_loaded() -> bool:
	for component_script in [
		C_NODE,
		C_IDENTITY,
		C_FACTION,
		C_SETTLEMENT,
		C_SPATIAL,
		C_VITALS,
		C_VITALS_INPUTS,
		C_AI_SCHEDULE,
		C_AI_STATE,
		C_GOAL_INTENT,
		C_POPULATION_RECORD,
		C_ACTIVE_POPULATION_VITALS,
		C_SETTLEMENT_STATE,
		C_STAFF_SLOT,
		C_STAFF_VACANCY,
		C_INVENTORY_CONTAINER,
		C_ITEM_STACK,
		C_EQUIPMENT_SLOT,
		C_SETTLEMENT_EVENT,
		C_JOB_PROVIDER,
		C_JOB_PROVIDER_SLOT,
		C_JOB_WORKER_RECORD,
		C_JOB_CONTRACT,
		C_JOB_PROVIDER_MEMORY,
		C_ACTIVITY_POINT,
		C_ACTIVITY_ASSIGNMENT,
		C_WORLD_TIME,
		C_LAW_ORDER,
		C_FACTION_STATE,
		C_WORLD_SQUAD,
		C_WORLD_EVENT,
		C_NEST_STATE,
		C_JOB_SYSTEM,
		C_LEDGER_SIMULATION,
		C_AI_SCHEDULER_STATE,
		C_POPULATION_REALIZATION_STATE,
		C_COMBAT_LOADOUT,
		C_COMBAT_CONFIG,
		C_COMBAT_STATE,
		C_COMBAT_SLOT_STATE,
		C_COMBAT_ACTION,
		C_MOVEMENT_STATE,
		C_WORLD_SIM_SQUAD,
		C_BUILDING_RECORD,
	]:
		if component_script == null:
			return false
	return true


func _ensure_direct_script_ecs_singleton() -> void:
	if get_tree() == null or get_node_or_null("/root/ECS") != null or Engine.has_singleton("ECS"):
		return
	var placeholder := Node.new()
	placeholder.name = "ECS"
	Engine.register_singleton("ECS", placeholder)
	_direct_script_ecs_placeholder = placeholder
	_registered_direct_script_ecs_singleton = true


func _try_initialize() -> void:
	if _initialized or not is_inside_tree():
		return
	if not _load_gecs_scripts():
		return
	world = get_node_or_null("GameECSWorld")
	if world == null:
		world = _world_script.new()
		world.name = "GameECSWorld"
		add_child(world)
		var actor_sync = _actor_sync_system_script.new()
		actor_sync.name = "GameActorSyncSystem"
		world.add_system(actor_sync)
		var combat_state_sync = _combat_state_sync_system_script.new()
		combat_state_sync.name = "GameCombatStateSyncSystem"
		world.add_system(combat_state_sync)
		if _combat_score_system_script != null:
			var combat_score = _combat_score_system_script.new()
			combat_score.name = "GameCombatScoreSystem"
			world.add_system(combat_score)
		var combat_targeting = _combat_targeting_system_script.new()
		combat_targeting.name = "GameCombatTargetingSystem"
		world.add_system(combat_targeting)
		var combat_slot = _combat_slot_system_script.new()
		combat_slot.name = "GameCombatSlotSystem"
		world.add_system(combat_slot)
		var combat_movement = _combat_movement_system_script.new()
		combat_movement.name = "GameCombatMovementSystem"
		world.add_system(combat_movement)
		var combat_resolution = _combat_resolution_system_script.new()
		combat_resolution.name = "GameCombatResolutionSystem"
		world.add_system(combat_resolution)
		_vitals_system = _vitals_system_script.new()
		_vitals_system.name = "GameVitalsSystem"
		world.add_system(_vitals_system)
		_population_vitals_system = _population_vitals_system_script.new()
		_population_vitals_system.name = "GamePopulationVitalsSystem"
		_population_vitals_system.life_state_changed.connect(_on_population_vitals_life_state_changed)
		world.add_system(_population_vitals_system)
		var ai_job_system = _ai_job_system_script.new()
		ai_job_system.name = "GameAiJobSystem"
		world.add_system(ai_job_system)
	var ecs_node = get_node_or_null("/root/ECS")
	if ecs_node == null:
		ecs_node = _ecs_script.new()
		ecs_node.name = "ECS"
		get_tree().root.add_child(ecs_node)
	# Swap any compile-time placeholder singleton (ours or a test harness's) for the real
	# ECS node, so runtime `ECS.world` lookups compiled against the singleton resolve here.
	if Engine.has_singleton("ECS") and Engine.get_singleton("ECS") != ecs_node:
		Engine.unregister_singleton("ECS")
		Engine.register_singleton("ECS", ecs_node)
		if _direct_script_ecs_placeholder != null:
			_direct_script_ecs_placeholder.free()
			_direct_script_ecs_placeholder = null
		_registered_direct_script_ecs_singleton = false
	if ecs_node != null:
		ecs_node.set("world", world)
		world.finalize_system_setup()
	_initialized = true


func _write_actor_components(entity, actor: Node, actor_id: String, settlement_id: String, context: Dictionary) -> void:
	var node_component = entity.get_component(C_NODE)
	node_component.actor = actor
	node_component.actor_path = actor.get_path() if actor.is_inside_tree() else NodePath()
	node_component.instance_id = actor.get_instance_id()

	var identity = entity.get_component(C_IDENTITY)
	identity.actor_id = actor_id
	identity.stable_id = actor_id
	var member_name = actor.get("member_name")
	identity.member_name = str(member_name) if member_name != null else str(actor.name)
	identity.role_id = str(context.get("role_id", _actor_role_id(actor)))
	identity.important = bool(context.get("important", _actor_is_important(actor)))

	var faction = entity.get_component(C_FACTION)
	var faction_value = actor.get("faction_name")
	faction.faction_id = str(faction_value).strip_edges() if faction_value != null else ""
	var squad_value = actor.get("squad_name")
	faction.squad_name = str(squad_value) if squad_value != null else ""
	var hostile_value = actor.get("hostile_factions")
	faction.hostile_faction_ids = hostile_value if hostile_value is PackedStringArray else PackedStringArray(hostile_value if hostile_value is Array else [])
	var stance_value = actor.get("combat_stance")
	faction.combat_stance = int(stance_value) if stance_value != null else 0
	var party_value = actor.get("player_party_member")
	faction.player_party_member = bool(party_value) if party_value != null else false

	var settlement = entity.get_component(C_SETTLEMENT)
	settlement.settlement_id = settlement_id if not settlement_id.is_empty() else _actor_settlement_id(actor)
	settlement.generation_source = str(context.get("generation_source", ""))
	settlement.realization_state = "realized"
	settlement.live_node_path = actor.get_path() if actor.is_inside_tree() else NodePath()

	var spatial = entity.get_component(C_SPATIAL)
	if actor is Node3D:
		spatial.last_world_position = spatial.world_position
		spatial.world_position = (actor as Node3D).global_position
		spatial.spatial_cell = _spatial_cell_coords(spatial.world_position)
		spatial.position_initialized = true

	var vitals = entity.get_component(C_VITALS)
	var life_state = actor.get("life_state")
	vitals.life_state = int(life_state) if life_state != null else NpcRules.LifeState.ALIVE
	var hp = actor.get("hp")
	vitals.hp = float(hp) if hp != null else 100.0
	var max_hp = actor.get("max_hp")
	vitals.max_hp = float(max_hp) if max_hp != null else 100.0
	var blood = actor.get("blood")
	vitals.blood = float(blood) if blood != null else 100.0
	var max_blood = actor.get("max_blood")
	vitals.max_blood = float(max_blood) if max_blood != null else 100.0


func _sync_inventory_container(actor_id: String, container_id: String, inventory_owner: Node, inventory, is_work_inventory: bool, is_world_container := false) -> void:
	if inventory == null or container_id.is_empty():
		return
	var entity = _inventory_container_entity_by_id.get(container_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("Inventory", container_id)
		entity.id = _entity_id("inventory", container_id)
		world.add_entity(entity, [C_INVENTORY_CONTAINER.new()])
		_inventory_container_entity_by_id[container_id] = entity
	var component = entity.get_component(C_INVENTORY_CONTAINER)
	component.container_id = container_id
	component.owner_actor_id = actor_id
	component.settlement_id = str(inventory_owner.get("settlement_id")) if is_world_container and _has_property(inventory_owner, "settlement_id") else ""
	component.facility_id = str(inventory_owner.get("facility_id")) if is_world_container and _has_property(inventory_owner, "facility_id") else ""
	component.container_kind = str(inventory_owner.get("container_kind")) if is_world_container and _has_property(inventory_owner, "container_kind") else "actor_work" if is_work_inventory else "actor"
	component.contributes_to_town_stock = bool(inventory_owner.get("contributes_to_town_stock")) if is_world_container and _has_property(inventory_owner, "contributes_to_town_stock") else false
	component.next_stack_sequence = int(inventory.get("next_stack_sequence")) if _has_property(inventory, "next_stack_sequence") else 1
	component.columns = int(inventory.get("columns")) if _has_property(inventory, "columns") else 0
	component.rows = int(inventory.get("rows")) if _has_property(inventory, "rows") else 0
	component.max_weight = float(inventory.get("max_weight")) if _has_property(inventory, "max_weight") else 0.0
	component.accepts_input = true
	component.is_world_container = is_world_container
	component.is_job_work_inventory = is_work_inventory
	_clear_item_stacks_for_container(container_id)
	var entries: Array = inventory.get("entries") if _has_property(inventory, "entries") else []
	for entry in entries:
		_sync_item_stack(actor_id, container_id, entry)


func _sync_item_stack(actor_id: String, container_id: String, entry) -> void:
	if entry == null:
		return
	var item_path := _resource_path(entry.get("definition")) if _has_property(entry, "definition") else ""
	if item_path.is_empty():
		return
	var stack_id := str(entry.get("stack_id")).strip_edges() if _has_property(entry, "stack_id") else ""
	if stack_id.is_empty():
		return
	var entity = _item_stack_entity_by_id.get(stack_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("ItemStack", stack_id)
		entity.id = _entity_id("item_stack", stack_id)
		world.add_entity(entity, [C_ITEM_STACK.new()])
		_item_stack_entity_by_id[stack_id] = entity
	var component = entity.get_component(C_ITEM_STACK)
	component.stack_id = stack_id
	component.container_id = container_id
	component.owner_actor_id = actor_id
	component.item_definition_path = item_path
	component.count = int(entry.get("count")) if _has_property(entry, "count") else 1
	component.grid_position = entry.get("grid_position") if _has_property(entry, "grid_position") else Vector2i.ZERO
	component.contained_item_counts = (entry.get("contained_item_counts") as Dictionary).duplicate(true) if _has_property(entry, "contained_item_counts") else {}
	component.metadata = (entry.get("metadata") as Dictionary).duplicate(true) if _has_property(entry, "metadata") else {}
	component.location_kind = "inventory"
	component.world_transform = Transform3D.IDENTITY
	component.placement_host_id = ""
	component.placement_slot_id = ""
	component.location_settlement_id = ""


func _sync_equipment_slots(actor_id: String, actor: Node) -> void:
	var previous_stack_ids: Dictionary = {}
	for slot in get_equipment_slots(actor_id):
		previous_stack_ids[str(slot.get("slot_name", ""))] = str(slot.get("stack_id", ""))
	_clear_equipment_slots_for_actor(actor_id)
	var world_actor := actor as WorldActor
	if world_actor == null:
		return
	var equipment = world_actor.get_equipment()
	var equipped = equipment.get_equipped_items() if equipment != null else null
	if not (equipped is Dictionary):
		return
	for slot_name_value in equipped.keys():
		var slot_name := str(slot_name_value)
		var item_path := _resource_path(equipped[slot_name_value])
		if slot_name.is_empty() or item_path.is_empty():
			continue
		var key := "%s:%s" % [actor_id, slot_name]
		var entity = _entity_script.new()
		entity.name = _entity_node_name("Equipment", key)
		entity.id = _entity_id("equipment", key)
		world.add_entity(entity, [C_EQUIPMENT_SLOT.new()])
		_equipment_slot_entity_by_key[key] = entity
		var component = entity.get_component(C_EQUIPMENT_SLOT)
		component.actor_id = actor_id
		component.slot_name = slot_name
		component.item_definition_path = item_path
		component.stack_id = str(equipment.get_equipped_stack_id(slot_name))
		if component.stack_id.is_empty():
			component.stack_id = str(previous_stack_ids.get(slot_name, "%s.equipment.%s" % [actor_id, slot_name]))
		_ensure_equipment_item_stack(actor_id, slot_name, item_path, component.stack_id)


func _sync_record_equipment_slots(actor_id: String, equipment_slots) -> void:
	if actor_id.is_empty() or not (equipment_slots is Dictionary):
		return
	var expected_keys: Dictionary = {}
	for slot_name_value in (equipment_slots as Dictionary).keys():
		var slot_name := str(slot_name_value)
		var item_path := str((equipment_slots as Dictionary)[slot_name_value])
		if slot_name.is_empty() or item_path.is_empty():
			continue
		var key := "%s:%s" % [actor_id, slot_name]
		expected_keys[key] = true
		var entity = _equipment_slot_entity_by_key.get(key)
		if entity == null or not is_instance_valid(entity):
			entity = _entity_script.new()
			entity.name = _entity_node_name("Equipment", key)
			entity.id = _entity_id("equipment", key)
			world.add_entity(entity, [C_EQUIPMENT_SLOT.new()])
			_equipment_slot_entity_by_key[key] = entity
		var component = entity.get_component(C_EQUIPMENT_SLOT)
		component.actor_id = actor_id
		component.slot_name = slot_name
		component.item_definition_path = item_path
		if str(component.stack_id).is_empty():
			component.stack_id = "%s.equipment.%s" % [actor_id, slot_name]
		_ensure_equipment_item_stack(actor_id, slot_name, item_path, str(component.stack_id))
	for key_value in _equipment_slot_entity_by_key.keys():
		var key := str(key_value)
		if not key.begins_with("%s:" % actor_id) or expected_keys.has(key):
			continue
		var entity = _equipment_slot_entity_by_key.get(key)
		if entity != null and is_instance_valid(entity) and world != null:
			world.remove_entity(entity)
		_equipment_slot_entity_by_key.erase(key)


func _ensure_equipment_item_stack(actor_id: String, slot_name: String, item_path: String, stack_id: String) -> void:
	if actor_id.is_empty() or slot_name.is_empty() or item_path.is_empty() or stack_id.is_empty():
		return
	var stack_entity = _item_stack_entity_by_id.get(stack_id)
	if stack_entity == null or not is_instance_valid(stack_entity):
		stack_entity = _entity_script.new()
		stack_entity.name = _entity_node_name("ItemStack", stack_id)
		stack_entity.id = _entity_id("item_stack", stack_id)
		world.add_entity(stack_entity, [C_ITEM_STACK.new()])
		_item_stack_entity_by_id[stack_id] = stack_entity
	var stack_component = stack_entity.get_component(C_ITEM_STACK)
	stack_component.stack_id = stack_id
	stack_component.container_id = ""
	stack_component.owner_actor_id = actor_id
	stack_component.item_definition_path = item_path
	stack_component.count = 1
	stack_component.location_kind = "equipment"
	stack_component.world_transform = Transform3D.IDENTITY
	stack_component.placement_host_id = ""
	stack_component.placement_slot_id = slot_name
	stack_component.location_settlement_id = ""


func _sync_record_inventory_entries(actor_id: String, inventory_entries) -> void:
	if actor_id.is_empty() or not (inventory_entries is Array):
		return
	var container_id := "%s.inventory" % actor_id
	var container = _inventory_container_entity_by_id.get(container_id)
	if container == null or not is_instance_valid(container):
		container = _entity_script.new()
		container.name = _entity_node_name("Inventory", container_id)
		container.id = _entity_id("inventory", container_id)
		world.add_entity(container, [C_INVENTORY_CONTAINER.new()])
		_inventory_container_entity_by_id[container_id] = container
	var container_component = container.get_component(C_INVENTORY_CONTAINER)
	container_component.container_id = container_id
	container_component.owner_actor_id = actor_id
	container_component.container_kind = "actor"
	_clear_item_stacks_for_container(container_id)
	for snapshot in inventory_entries as Array:
		if snapshot is Dictionary:
			_sync_item_stack_from_snapshot(actor_id, container_id, snapshot)


func _sync_item_stack_from_snapshot(actor_id: String, container_id: String, snapshot: Dictionary) -> void:
	var item_path := str(snapshot.get("item_id", snapshot.get("item_definition_path", "")))
	if item_path.is_empty():
		return
	var stack_id := str(snapshot.get("stack_id", "")).strip_edges()
	if stack_id.is_empty():
		stack_id = InventoryData.create_stack_id()
	var entity = _entity_script.new()
	entity.name = _entity_node_name("ItemStack", stack_id)
	entity.id = _entity_id("item_stack", stack_id)
	world.add_entity(entity, [C_ITEM_STACK.new()])
	_item_stack_entity_by_id[stack_id] = entity
	var component = entity.get_component(C_ITEM_STACK)
	component.stack_id = stack_id
	component.container_id = container_id
	component.owner_actor_id = actor_id
	component.item_definition_path = item_path
	component.count = int(snapshot.get("count", 1))
	component.grid_position = snapshot.get("grid_position", Vector2i.ZERO)
	component.contained_item_counts = (snapshot.get("contained_item_counts", {}) as Dictionary).duplicate(true)
	component.metadata = (snapshot.get("metadata", {}) as Dictionary).duplicate(true)


func _populate_record_inventory_and_equipment(record: Dictionary) -> Dictionary:
	var actor_id := str(record.get("actor_id", ""))
	if actor_id.is_empty():
		return record
	var equipment_slots := {}
	for slot in get_equipment_slots(actor_id):
		equipment_slots[str(slot.get("slot_name", ""))] = str(slot.get("item_definition_path", ""))
	record["equipment_slots"] = equipment_slots
	var inventory_entries: Array = []
	for stack in get_inventory_stacks("%s.inventory" % actor_id):
		inventory_entries.append({
			"stack_id": str(stack.get("stack_id", "")),
			"item_id": str(stack.get("item_definition_path", "")),
			"count": int(stack.get("count", 1)),
			"grid_position": stack.get("grid_position", Vector2i.ZERO),
			"contained_item_counts": (stack.get("contained_item_counts", {}) as Dictionary).duplicate(true),
			"metadata": (stack.get("metadata", {}) as Dictionary).duplicate(true),
		})
	inventory_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_position: Vector2i = a.get("grid_position", Vector2i.ZERO)
		var b_position: Vector2i = b.get("grid_position", Vector2i.ZERO)
		if a_position.y != b_position.y:
			return a_position.y < b_position.y
		if a_position.x != b_position.x:
			return a_position.x < b_position.x
		return str(a.get("stack_id", "")).naturalnocasecmp_to(str(b.get("stack_id", ""))) < 0
	)
	record["inventory_entries"] = inventory_entries
	return record


func _sync_job_provider_slots(provider_id: String, active_slots: Dictionary) -> void:
	var expected_slot_ids: Dictionary = {}
	for job_index_value in active_slots.keys():
		var job_index := int(job_index_value)
		var slots: Array = active_slots[job_index_value]
		for slot_state in slots:
			if not (slot_state is Dictionary):
				continue
			var slot_data: Dictionary = slot_state
			var slot_index := int((slot_state as Dictionary).get("slot_index", 0))
			var slot_id := "%s:%d:%d" % [provider_id, job_index, slot_index]
			expected_slot_ids[slot_id] = true
			var entity = _job_provider_slot_entity_by_id.get(slot_id)
			if entity == null or not is_instance_valid(entity):
				entity = _entity_script.new()
				entity.name = _entity_node_name("JobProviderSlot", slot_id)
				entity.id = _entity_id("job_provider_slot", slot_id)
				world.add_entity(entity, [C_JOB_PROVIDER_SLOT.new()])
				_job_provider_slot_entity_by_id[slot_id] = entity
			var component = entity.get_component(C_JOB_PROVIDER_SLOT)
			var worker = slot_data.get("worker")
			component.slot_id = slot_id
			component.provider_id = provider_id
			component.job_index = job_index
			component.slot_index = slot_index
			component.worker_actor_id = _actor_record_id(worker) if worker is Node else ""
			component.active = worker != null and is_instance_valid(worker)
			component.accrued_interval_time = float(slot_data.get("accrued_interval_time", 0.0))
			component.guard_shuffle_remaining = float(slot_data.get("guard_shuffle_remaining", 0.0))
			component.server_state = str(slot_data.get("server_state", "idle"))
			component.server_state_elapsed = float(slot_data.get("server_state_elapsed", 0.0))
			component.server_order_text = str(slot_data.get("server_order_text", ""))
			component.last_ai_blocker = str(slot_data.get("last_ai_blocker", ""))
	var remove_ids: Array[String] = []
	for slot_id in _job_provider_slot_entity_by_id.keys():
		var slot_id_text := str(slot_id)
		if slot_id_text.begins_with("%s:" % provider_id) and not expected_slot_ids.has(slot_id_text):
			remove_ids.append(slot_id_text)
	for slot_id in remove_ids:
		var old_entity = _job_provider_slot_entity_by_id.get(slot_id)
		if old_entity != null and is_instance_valid(old_entity) and world != null:
			world.remove_entity(old_entity)
		_job_provider_slot_entity_by_id.erase(slot_id)


func _sync_job_worker_records(provider_id: String, worker_records: Dictionary) -> void:
	var expected_record_ids: Dictionary = {}
	for worker_id_value in worker_records.keys():
		var worker_id := str(worker_id_value)
		var record: Dictionary = worker_records[worker_id_value]
		var record_id := "%s:%s" % [provider_id, worker_id]
		expected_record_ids[record_id] = true
		var entity = _job_worker_record_entity_by_id.get(record_id)
		if entity == null or not is_instance_valid(entity):
			entity = _entity_script.new()
			entity.name = _entity_node_name("JobWorker", record_id)
			entity.id = _entity_id("job_worker", record_id)
			world.add_entity(entity, [C_JOB_WORKER_RECORD.new()])
			_job_worker_record_entity_by_id[record_id] = entity
		var component = entity.get_component(C_JOB_WORKER_RECORD)
		component.record_id = record_id
		component.provider_id = provider_id
		component.worker_actor_id = worker_id
		component.total_worked_seconds = float(record.get("total_worked_seconds", 0.0))
		component.owed_currency = int(record.get("owed_currency", 0))
		component.break_until_time = float(record.get("break_until_time", 0.0))
	var remove_ids: Array[String] = []
	for record_id in _job_worker_record_entity_by_id.keys():
		var record_id_text := str(record_id)
		if record_id_text.begins_with("%s:" % provider_id) and not expected_record_ids.has(record_id_text):
			remove_ids.append(record_id_text)
	for record_id in remove_ids:
		var old_entity = _job_worker_record_entity_by_id.get(record_id)
		if old_entity != null and is_instance_valid(old_entity) and world != null:
			world.remove_entity(old_entity)
		_job_worker_record_entity_by_id.erase(record_id)


func _upsert_state_entity(current_entity, node_name: String, entity_id: String, component_script):
	_try_initialize()
	if world == null or component_script == null:
		return null
	var entity = current_entity
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = node_name
		entity.id = entity_id
		world.add_entity(entity, [component_script.new()])
	return entity


func _find_state_entity(current_entity, component_script):
	_try_initialize()
	if world == null or component_script == null:
		return null
	if current_entity != null and is_instance_valid(current_entity):
		return current_entity
	for entity in world.query.with_all([component_script]).execute():
		return entity
	return null


func _apply_state_component(entity, component_script, state: Dictionary) -> Dictionary:
	if entity == null or not is_instance_valid(entity) or state.is_empty():
		return {}
	var component = entity.get_component(component_script)
	if component == null or not component.has_method("apply_state"):
		return {}
	component.apply_state(state)
	return component.to_state() if component.has_method("to_state") else {}


func _state_component_to_dictionary(entity, component_script) -> Dictionary:
	if entity == null or not is_instance_valid(entity):
		return {}
	var component = entity.get_component(component_script)
	return component.to_state() if component != null and component.has_method("to_state") else {}


func _clear_item_stacks_for_container(container_id: String) -> void:
	var remove_ids: Array[String] = []
	for stack_id in _item_stack_entity_by_id.keys():
		var entity = _item_stack_entity_by_id.get(stack_id)
		var component = entity.get_component(C_ITEM_STACK) if entity != null and is_instance_valid(entity) else null
		if component != null and str(component.container_id) == container_id:
			remove_ids.append(str(stack_id))
	for stack_id in remove_ids:
		var entity = _item_stack_entity_by_id.get(stack_id)
		if entity != null and is_instance_valid(entity) and world != null:
			world.remove_entity(entity)
		_item_stack_entity_by_id.erase(stack_id)


func _clear_equipment_slots_for_actor(actor_id: String) -> void:
	var remove_keys: Array[String] = []
	for key in _equipment_slot_entity_by_key.keys():
		if str(key).begins_with("%s:" % actor_id):
			remove_keys.append(str(key))
	for key in remove_keys:
		var entity = _equipment_slot_entity_by_key.get(key)
		if entity != null and is_instance_valid(entity) and world != null:
			world.remove_entity(entity)
		_equipment_slot_entity_by_key.erase(key)


func _query_actor_nodes(filters: Dictionary) -> Array:
	_try_initialize()
	var result: Array = []
	if world == null:
		return result
	var include_party: bool = bool(filters.get("include_party", true))
	var require_alive: bool = bool(filters.get("alive", false))
	var settlement_filter: String = str(filters.get("settlement_id", ""))
	var role_filter: String = str(filters.get("role_id", ""))
	var faction_filter: String = str(filters.get("faction_id", ""))
	var has_position_filter: bool = filters.has("position") and filters.get("position") is Vector3 and float(filters.get("radius", -1.0)) >= 0.0
	var position: Vector3 = filters.get("position", Vector3.ZERO)
	var radius: float = maxf(float(filters.get("radius", -1.0)), 0.0)
	var radius_squared: float = radius * radius
	if has_position_filter and settlement_filter.is_empty() and role_filter.is_empty() and faction_filter.is_empty():
		return _query_spatial_actor_nodes(position, radius, radius_squared, include_party, require_alive)
	for entity in world.query.with_all([C_NODE, C_IDENTITY, C_FACTION, C_SETTLEMENT, C_SPATIAL, C_VITALS]).execute():
		var actor = _actor_from_entity(entity)
		if actor == null:
			continue
		var identity = entity.get_component(C_IDENTITY)
		var faction = entity.get_component(C_FACTION)
		var settlement = entity.get_component(C_SETTLEMENT)
		var spatial = entity.get_component(C_SPATIAL)
		var vitals = entity.get_component(C_VITALS)
		if require_alive and (vitals == null or int(vitals.life_state) != NpcRules.LifeState.ALIVE):
			continue
		if not include_party and faction != null and bool(faction.player_party_member):
			continue
		if not settlement_filter.is_empty() and (settlement == null or str(settlement.settlement_id) != settlement_filter):
			continue
		if not role_filter.is_empty() and (identity == null or str(identity.role_id) != role_filter):
			continue
		if not faction_filter.is_empty() and (faction == null or str(faction.faction_id) != faction_filter):
			continue
		if has_position_filter:
			if spatial == null or spatial.world_position.distance_squared_to(position) > radius_squared:
				continue
		result.append(actor)
	return result


func _query_spatial_actor_nodes(position: Vector3, radius: float, radius_squared: float, include_party: bool, require_alive: bool) -> Array:
	_ensure_actor_spatial_index()
	if _actor_query_metrics_enabled:
		_spatial_query_calls += 1
	var result: Array = []
	var checked_actor_ids := {}
	var center_cell := _spatial_cell_coords(position)
	var cell_radius := int(ceil(radius / maxf(spatial_cell_size, 1.0)))
	for cell_x in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
		for cell_y in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
			if _actor_query_metrics_enabled:
				_spatial_query_cells_checked += 1
			var actors = _actor_spatial_nodes_by_cell.get(Vector2i(cell_x, cell_y), [])
			if not (actors is Array):
				continue
			for actor_value in actors:
				var actor := actor_value as Node
				if actor == null or not is_instance_valid(actor) or not (actor is Node3D):
					continue
				var actor_key := actor.get_instance_id()
				if checked_actor_ids.has(actor_key):
					continue
				checked_actor_ids[actor_key] = true
				if _actor_query_metrics_enabled:
					_spatial_query_candidates_checked += 1
				if (actor as Node3D).global_position.distance_squared_to(position) > radius_squared:
					continue
				var party_value = actor.get("player_party_member")
				if not include_party and party_value != null and bool(party_value):
					continue
				var life_state_value = actor.get("life_state")
				if require_alive and (life_state_value == null or int(life_state_value) != NpcRules.LifeState.ALIVE):
					continue
				result.append(actor)
	if _actor_query_metrics_enabled:
		_spatial_query_results_returned += result.size()
	return result


func _query_spatial_actor_nodes_limited(position: Vector3, radius: float, radius_squared: float, include_party: bool, require_alive: bool, max_count: int) -> Array:
	if max_count <= 0:
		return []
	_ensure_actor_spatial_index()
	if _actor_query_metrics_enabled:
		_spatial_query_calls += 1
	var entries: Array = []
	var checked_actor_ids := {}
	var center_cell := _spatial_cell_coords(position)
	var cell_size := maxf(spatial_cell_size, 1.0)
	var cell_radius := int(ceil(radius / cell_size))
	for ring in range(cell_radius + 1):
		_query_spatial_ring(position, radius_squared, include_party, require_alive, max_count, center_cell, ring, checked_actor_ids, entries)
		if entries.size() >= max_count:
			var farthest_entry: Dictionary = entries[entries.size() - 1] if entries[entries.size() - 1] is Dictionary else {}
			var farthest_distance_squared := float(farthest_entry.get("distance_squared", INF))
			var next_ring_min_distance := maxf(0.0, float(ring + 1) * cell_size - cell_size)
			if next_ring_min_distance * next_ring_min_distance > farthest_distance_squared:
				break
	var result: Array = []
	for entry_value in entries:
		var entry: Dictionary = entry_value if entry_value is Dictionary else {}
		var actor = entry.get("actor", null)
		if actor != null and is_instance_valid(actor):
			result.append(actor)
	if _actor_query_metrics_enabled:
		_spatial_query_results_returned += result.size()
	return result


func _query_spatial_ring(position: Vector3, radius_squared: float, include_party: bool, require_alive: bool, max_count: int, center_cell: Vector2i, ring: int, checked_actor_ids: Dictionary, entries: Array) -> void:
	if ring == 0:
		_query_spatial_cell(position, radius_squared, include_party, require_alive, max_count, center_cell, checked_actor_ids, entries)
		return
	for cell_x in range(center_cell.x - ring, center_cell.x + ring + 1):
		_query_spatial_cell(position, radius_squared, include_party, require_alive, max_count, Vector2i(cell_x, center_cell.y - ring), checked_actor_ids, entries)
		_query_spatial_cell(position, radius_squared, include_party, require_alive, max_count, Vector2i(cell_x, center_cell.y + ring), checked_actor_ids, entries)
	for cell_y in range(center_cell.y - ring + 1, center_cell.y + ring):
		_query_spatial_cell(position, radius_squared, include_party, require_alive, max_count, Vector2i(center_cell.x - ring, cell_y), checked_actor_ids, entries)
		_query_spatial_cell(position, radius_squared, include_party, require_alive, max_count, Vector2i(center_cell.x + ring, cell_y), checked_actor_ids, entries)


func _query_spatial_cell(position: Vector3, radius_squared: float, include_party: bool, require_alive: bool, max_count: int, cell: Vector2i, checked_actor_ids: Dictionary, entries: Array) -> void:
	if _actor_query_metrics_enabled:
		_spatial_query_cells_checked += 1
	var actors = _actor_spatial_nodes_by_cell.get(cell, [])
	if not (actors is Array):
		return
	for actor_value in actors:
		var actor := actor_value as Node
		if actor == null or not is_instance_valid(actor) or not (actor is Node3D):
			continue
		var actor_key := actor.get_instance_id()
		if checked_actor_ids.has(actor_key):
			continue
		checked_actor_ids[actor_key] = true
		if _actor_query_metrics_enabled:
			_spatial_query_candidates_checked += 1
		var distance_squared: float = (actor as Node3D).global_position.distance_squared_to(position)
		if distance_squared > radius_squared:
			continue
		var party_value = actor.get("player_party_member")
		if not include_party and party_value != null and bool(party_value):
			continue
		var life_state_value = actor.get("life_state")
		if require_alive and (life_state_value == null or int(life_state_value) != NpcRules.LifeState.ALIVE):
			continue
		_append_limited_spatial_entry(entries, actor, distance_squared, max_count)


func _append_limited_spatial_entry(entries: Array, actor: Node, distance_squared: float, max_count: int) -> void:
	var entry := {"actor": actor, "distance_squared": distance_squared}
	for index in range(entries.size()):
		var existing: Dictionary = entries[index] if entries[index] is Dictionary else {}
		if distance_squared < float(existing.get("distance_squared", INF)):
			entries.insert(index, entry)
			if entries.size() > max_count:
				entries.remove_at(entries.size() - 1)
			return
	entries.append(entry)
	if entries.size() > max_count:
		entries.remove_at(entries.size() - 1)


func _ensure_actor_spatial_index() -> void:
	if _actor_spatial_index_valid:
		return
	_rebuild_actor_spatial_index()


func _rebuild_actor_spatial_index() -> void:
	var started_usec := Time.get_ticks_usec() if _actor_query_metrics_enabled else 0
	_actor_spatial_nodes_by_cell.clear()
	if world != null:
		for entity in world.query.with_all([C_IDENTITY, C_NODE, C_SPATIAL]).execute():
			var identity = entity.get_component(C_IDENTITY)
			var spatial = entity.get_component(C_SPATIAL)
			var actor = _actor_from_entity(entity)
			if identity == null or spatial == null or actor == null or not (actor is Node3D):
				continue
			spatial.world_position = (actor as Node3D).global_position
			spatial.spatial_cell = _spatial_cell_coords(spatial.world_position)
			spatial.position_initialized = true
			var cell = spatial.spatial_cell
			var bucket: Array = _actor_spatial_nodes_by_cell.get(cell, [])
			bucket.append(actor)
			_actor_spatial_nodes_by_cell[cell] = bucket
	_actor_spatial_index_valid = true
	_actor_spatial_index_elapsed = 0.0
	if _actor_query_metrics_enabled:
		_spatial_index_rebuilds += 1
		_spatial_index_rebuild_usec += Time.get_ticks_usec() - started_usec


func _actor_entity_for_actor(actor: Node):
	if actor == null:
		return null
	var actor_id: String = _actor_record_id(actor)
	if actor_id.is_empty():
		actor_id = _actor_id_by_instance_id.get(actor.get_instance_id(), "")
	return _actor_entity_by_actor_id.get(actor_id, null)


func _actor_from_entity(entity) -> Node:
	if entity == null or not is_instance_valid(entity):
		return null
	var component = entity.get_component(C_NODE)
	if component == null:
		return null
	var actor = component.get_actor() if component.has_method("get_actor") else component.actor
	if actor != null and is_instance_valid(actor):
		return actor as Node
	if component.actor_path != NodePath():
		actor = get_node_or_null(component.actor_path)
		if actor != null:
			component.actor = actor
			_actor_id_by_instance_id[actor.get_instance_id()] = _strip_entity_prefix(str(entity.id), "actor")
			return actor as Node
	return null


func _actor_state_from_entity(entity) -> Dictionary:
	if entity == null or not is_instance_valid(entity):
		return {}
	var identity = entity.get_component(C_IDENTITY)
	if identity == null:
		return {}
	var faction = entity.get_component(C_FACTION)
	var settlement = entity.get_component(C_SETTLEMENT)
	var spatial = entity.get_component(C_SPATIAL)
	var vitals = entity.get_component(C_VITALS)
	var goal_intent = entity.get_component(C_GOAL_INTENT) if C_GOAL_INTENT != null else null
	var actor_id := str(identity.actor_id)
	var state := {
		"actor_id": actor_id,
		"stable_id": str(identity.stable_id),
		"member_name": str(identity.member_name),
		"role_id": str(identity.role_id),
		"important": bool(identity.important),
	}
	if faction != null:
		state["faction_id"] = str(faction.faction_id)
		state["squad_name"] = str(faction.squad_name)
		state["hostile_faction_ids"] = Array(faction.hostile_faction_ids)
		state["combat_stance"] = int(faction.combat_stance)
		state["player_party_member"] = bool(faction.player_party_member)
	if settlement != null:
		state["settlement_id"] = str(settlement.settlement_id)
		state["generation_source"] = str(settlement.generation_source)
		state["realization_state"] = str(settlement.realization_state)
		state["live_node_path"] = settlement.live_node_path
	if spatial != null:
		state["world_position"] = spatial.world_position
		state["last_world_position"] = spatial.last_world_position
		state["position_initialized"] = bool(spatial.position_initialized)
		state["spatial_cell"] = spatial.spatial_cell
	if vitals != null:
		state["life_state"] = int(vitals.life_state)
		state["hp"] = float(vitals.hp)
		state["max_hp"] = float(vitals.max_hp)
		state["blood"] = float(vitals.blood)
		state["max_blood"] = float(vitals.max_blood)
	if goal_intent != null and goal_intent.has_method("to_dictionary"):
		state["goal_intent"] = goal_intent.call("to_dictionary", false)
	return state


func _ensure_actor_goal_intent_component(entity):
	if entity == null or C_GOAL_INTENT == null:
		return null
	var goal_intent = entity.get_component(C_GOAL_INTENT)
	if goal_intent == null:
		goal_intent = C_GOAL_INTENT.new()
		entity.add_component(goal_intent)
	return goal_intent


func _actor_id_for_actor(actor: Node, settlement_id: String) -> String:
	var existing: String = _actor_record_id(actor)
	if not existing.is_empty():
		return existing
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).strip_edges().is_empty():
		return str(stable_id).strip_edges()
	var prefix: String = _sanitize_id(settlement_id if not settlement_id.is_empty() else _actor_settlement_id(actor))
	if prefix.is_empty():
		prefix = "world"
	var path_part: String = _sanitize_id(str(actor.get_path()) if actor.is_inside_tree() else str(actor.name))
	if path_part.is_empty():
		path_part = str(actor.get_instance_id())
	return "%s.%s" % [prefix, path_part]


func _actor_record_id(actor: Node) -> String:
	if actor == null:
		return ""
	if actor.has_meta("actor_record_id"):
		return str(actor.get_meta("actor_record_id")).strip_edges()
	var stable_id = actor.get("stable_id")
	return str(stable_id).strip_edges() if stable_id != null else ""


func _actor_settlement_id(actor: Node) -> String:
	if actor == null:
		return ""
	if actor.has_meta("settlement_id"):
		return str(actor.get_meta("settlement_id")).strip_edges()
	var current: Node = actor
	while current != null:
		if current.has_method("get_settlement_id"):
			return str(current.call("get_settlement_id"))
		if current.is_in_group("settlement_anchor"):
			return str(current.name)
		current = current.get_parent()
	return ""


func _actor_role_id(actor: Node) -> String:
	if actor == null:
		return "resident"
	if actor.has_meta("actor_role_id"):
		return str(actor.get_meta("actor_role_id"))
	if actor.has_meta("settlement_staff_role"):
		return str(actor.get_meta("settlement_staff_role"))
	if actor.is_in_group("settlement_authority"):
		return "guard"
	return "resident"


func _actor_is_important(actor: Node) -> bool:
	if actor == null:
		return false
	return actor.is_in_group("settlement_authority") or actor.has_meta("settlement_staff_role") or (actor is WorldActor and (actor as WorldActor).is_law_prisoner())


func _provider_id(provider: Node) -> String:
	if provider == null:
		return ""
	if provider.is_inside_tree():
		return str(provider.get_path())
	return str(provider.get_instance_id())


func _provider_id_from_value(value) -> String:
	if value is Node:
		return _provider_id(value)
	return str(value).strip_edges()


func _actor_id_from_value(value) -> String:
	if value is Node:
		return _actor_record_id(value)
	return str(value).strip_edges()


func _make_job_contract_id(data: Dictionary) -> String:
	return "%s:%s:%s" % [str(data.get("actor_id", "")), str(data.get("provider_id", "")), str(data.get("job_id", data.get("job_index", "job")))]


func _next_job_contract_priority(actor_id: String) -> int:
	var next_priority := 0
	for contract in get_actor_job_contracts(actor_id):
		next_priority = maxi(next_priority, int(contract.get("priority_order", 0)) + 1)
	return next_priority


func _rewrite_job_contract_priorities(contracts: Array[Dictionary]) -> void:
	for index in range(contracts.size()):
		var contract_id := str(contracts[index].get("contract_id", ""))
		var entity = _job_contract_entity_by_id.get(contract_id)
		if entity == null or not is_instance_valid(entity):
			continue
		var component = entity.get_component(C_JOB_CONTRACT)
		if component != null:
			component.priority_order = index


func _notify_live_provider_contract_abandoned(contract: Dictionary, reason: String) -> void:
	var provider_path: NodePath = contract.get("provider_path", NodePath())
	if provider_path == NodePath():
		return
	var provider := get_node_or_null(provider_path)
	if provider != null and provider.has_method("on_job_contract_abandoned"):
		provider.call("on_job_contract_abandoned", contract, reason)


func _target_id_for_ai_job(job) -> String:
	if job == null:
		return ""
	if not str(job.target_id).strip_edges().is_empty():
		return str(job.target_id).strip_edges()
	var target = job.target
	if target == null:
		return ""
	if target is Node:
		var stable_id = target.get("stable_id")
		if stable_id != null and not str(stable_id).strip_edges().is_empty():
			return str(stable_id).strip_edges()
		if target.has_meta("actor_record_id"):
			return str(target.get_meta("actor_record_id"))
		return ""
	return str(target)


func _sync_live_scene_state_for_save() -> void:
	if not is_inside_tree():
		return
	for actor_id_value in _actor_entity_by_actor_id.keys():
		var actor_id := str(actor_id_value)
		var entity = _actor_entity_by_actor_id.get(actor_id_value)
		var actor := _actor_from_entity(entity)
		if actor == null:
			continue
		var stats = actor.call("get_stats") if actor.has_method("get_stats") else null
		if stats != null and stats.has_method("flush_pending_xp"):
			stats.call("flush_pending_xp")
		_write_actor_components(entity, actor, actor_id, _actor_settlement_id(actor), {})
		_copy_live_vitals_to_population(entity, actor_id)
		sync_actor_inventory(actor)
		var population_entity = _population_entity_by_actor_id.get(actor_id)
		var population = population_entity.get_component(C_POPULATION_RECORD) if population_entity != null and is_instance_valid(population_entity) else null
		if population != null and actor is Node3D:
			population.last_world_transform = (actor as Node3D).global_transform
			population.last_world_transform_initialized = true
			population.last_world_position = (actor as Node3D).global_position
			population.last_world_position_initialized = true
			var needs = actor.call("get_needs") if actor.has_method("get_needs") else null
			if needs != null and needs.has_method("durable_state"):
				population.needs_state = needs.call("durable_state")
			population.movement_state = {
				"has_move_target": bool(actor.call("has_move_target")) if actor.has_method("has_move_target") else false,
				"move_target": actor.call("get_move_target") if actor.has_method("get_move_target") else Vector3.ZERO,
				"running": bool(actor.call("is_running_requested")) if actor.has_method("is_running_requested") else false,
				"sneaking": bool(actor.call("is_sneaking")) if actor.has_method("is_sneaking") else false,
				"issued_by_player": bool(actor.call("has_active_player_order")) if actor.has_method("has_active_player_order") else false,
			}
			if int(population.life_state) == NpcRules.LifeState.DEAD and str(population.body_state) == "corpse":
				_reindex_corpse_record(population)
	for container in get_tree().get_nodes_in_group("world_container"):
		sync_world_container(container)


func _clear_world_entities() -> void:
	if world == null:
		return
	var entities: Array = world.entities.duplicate()
	for entity in entities:
		if entity != null and is_instance_valid(entity):
			world.remove_entity(entity)
	_actor_entity_by_actor_id.clear()
	_actor_id_by_instance_id.clear()
	_population_entity_by_actor_id.clear()
	_alive_population_count_by_settlement.clear()
	_population_actor_ids_by_settlement.clear()
	_population_settlement_by_actor_id.clear()
	_population_actor_ids_by_squad.clear()
	_population_squad_by_actor_id.clear()
	_corpse_actor_ids_by_cell.clear()
	_corpse_cell_by_actor_id.clear()
	_settlement_entity_by_id.clear()
	_settlement_food_entity_by_id.clear()
	_staff_slot_entity_by_key.clear()
	_staff_vacancy_entity_by_key.clear()
	_inventory_container_entity_by_id.clear()
	_item_stack_entity_by_id.clear()
	_equipment_slot_entity_by_key.clear()
	_settlement_event_entity_by_id.clear()
	_job_provider_entity_by_id.clear()
	_job_provider_slot_entity_by_id.clear()
	_job_worker_record_entity_by_id.clear()
	_job_contract_entity_by_id.clear()
	_job_provider_memory_entity_by_id.clear()
	_activity_point_entity_by_id.clear()
	_activity_assignment_entity_by_actor_id.clear()
	_world_sim_squad_entity_by_id.clear()
	_building_entity_by_id.clear()
	_actor_spatial_nodes_by_cell.clear()
	_actor_spatial_index_valid = false
	_world_time_entity = null
	_law_order_entity = null
	_faction_state_entity = null
	_world_squad_entity = null
	_world_event_entity = null
	_nest_state_entity = null
	_job_system_entity = null
	_ledger_simulation_entity = null
	_ai_scheduler_state_entity = null
	_population_realization_state_entity = null


func _rebuild_entity_indexes() -> void:
	if world == null:
		return
	_alive_population_count_by_settlement.clear()
	_population_actor_ids_by_settlement.clear()
	_population_settlement_by_actor_id.clear()
	_population_actor_ids_by_squad.clear()
	_population_squad_by_actor_id.clear()
	_corpse_actor_ids_by_cell.clear()
	_corpse_cell_by_actor_id.clear()
	for entity in world.query.with_all([C_IDENTITY]).execute():
		var identity = entity.get_component(C_IDENTITY)
		if identity == null:
			continue
		if entity.get_component(C_NODE) != null:
			_ensure_actor_combat_components(entity)
		_actor_entity_by_actor_id[str(identity.actor_id)] = entity
	var population_entities: Array = world.query.with_all([C_POPULATION_RECORD]).execute()
	for entity in population_entities:
		_ensure_population_vitals_components(entity)
		var population = entity.get_component(C_POPULATION_RECORD)
		if population != null:
			var population_vitals = entity.get_component(C_VITALS)
			if population_vitals != null:
				population.life_state = population_vitals.life_state
			_sync_active_population_vitals_tag(entity, population_vitals)
			_population_entity_by_actor_id[str(population.actor_id)] = entity
			_reindex_population_settlement(population)
			_reindex_population_squad(population)
			if int(population.life_state) != NpcRules.LifeState.DEAD:
				_adjust_alive_population_count(str(population.settlement_id), 1)
			_reindex_corpse_record(population)
	for entity in world.query.with_all([C_SETTLEMENT_STATE]).execute():
		var settlement = entity.get_component(C_SETTLEMENT_STATE)
		if settlement != null:
			_settlement_entity_by_id[str(settlement.settlement_id)] = entity
	for entity in world.query.with_all([C_BUILDING_RECORD]).execute():
		var building = entity.get_component(C_BUILDING_RECORD)
		if building != null:
			_building_entity_by_id[str(building.building_id)] = entity
	var food_status_script = load(C_SETTLEMENT_FOOD_STATUS_PATH)
	for entity in world.query.with_all([food_status_script]).execute():
		var food_status = entity.get_component(food_status_script)
		if food_status != null:
			_settlement_food_entity_by_id[str(food_status.settlement_id)] = entity
	for entity in world.query.with_all([C_STAFF_SLOT]).execute():
		var slot = entity.get_component(C_STAFF_SLOT)
		if slot != null:
			_staff_slot_entity_by_key["%s:%s" % [str(slot.settlement_id), str(slot.slot_id)]] = entity
	for entity in world.query.with_all([C_SETTLEMENT_EVENT]).execute():
		var event = entity.get_component(C_SETTLEMENT_EVENT)
		if event != null:
			_settlement_event_entity_by_id[str(event.event_id)] = entity
	for entity in world.query.with_all([C_STAFF_VACANCY]).execute():
		var vacancy = entity.get_component(C_STAFF_VACANCY)
		if vacancy != null:
			_staff_vacancy_entity_by_key[str(vacancy.vacancy_id)] = entity
	for entity in world.query.with_all([C_INVENTORY_CONTAINER]).execute():
		var inventory = entity.get_component(C_INVENTORY_CONTAINER)
		if inventory != null:
			_inventory_container_entity_by_id[str(inventory.container_id)] = entity
	for entity in world.query.with_all([C_ITEM_STACK]).execute():
		var stack = entity.get_component(C_ITEM_STACK)
		if stack != null:
			_item_stack_entity_by_id[str(stack.stack_id)] = entity
	for entity in world.query.with_all([C_EQUIPMENT_SLOT]).execute():
		var equipment = entity.get_component(C_EQUIPMENT_SLOT)
		if equipment != null:
			_equipment_slot_entity_by_key["%s:%s" % [str(equipment.actor_id), str(equipment.slot_name)]] = entity
	for entity in world.query.with_all([C_JOB_PROVIDER]).execute():
		var provider = entity.get_component(C_JOB_PROVIDER)
		if provider != null:
			_job_provider_entity_by_id[str(provider.provider_id)] = entity
	for entity in world.query.with_all([C_JOB_PROVIDER_SLOT]).execute():
		var provider_slot = entity.get_component(C_JOB_PROVIDER_SLOT)
		if provider_slot != null:
			_job_provider_slot_entity_by_id[str(provider_slot.slot_id)] = entity
	for entity in world.query.with_all([C_JOB_WORKER_RECORD]).execute():
		var worker_record = entity.get_component(C_JOB_WORKER_RECORD)
		if worker_record != null:
			_job_worker_record_entity_by_id[str(worker_record.record_id)] = entity
	for entity in world.query.with_all([C_JOB_CONTRACT]).execute():
		var contract = entity.get_component(C_JOB_CONTRACT)
		if contract != null:
			_job_contract_entity_by_id[str(contract.contract_id)] = entity
	for entity in world.query.with_all([C_JOB_PROVIDER_MEMORY]).execute():
		var memory = entity.get_component(C_JOB_PROVIDER_MEMORY)
		if memory != null:
			_job_provider_memory_entity_by_id[str(memory.memory_id)] = entity
	for entity in world.query.with_all([C_ACTIVITY_POINT]).execute():
		var activity_point = entity.get_component(C_ACTIVITY_POINT)
		if activity_point != null:
			_activity_point_entity_by_id[str(activity_point.activity_id)] = entity
	for entity in world.query.with_all([C_ACTIVITY_ASSIGNMENT]).execute():
		var activity_assignment = entity.get_component(C_ACTIVITY_ASSIGNMENT)
		if activity_assignment != null:
			_activity_assignment_entity_by_actor_id[str(activity_assignment.actor_id)] = entity
	for entity in world.query.with_all([C_WORLD_SIM_SQUAD]).execute():
		var world_sim_squad = entity.get_component(C_WORLD_SIM_SQUAD)
		if world_sim_squad != null:
			_world_sim_squad_entity_by_id[str(world_sim_squad.squad_id)] = entity
	for entity in world.query.with_all([C_WORLD_TIME]).execute():
		_world_time_entity = entity
		break
	for entity in world.query.with_all([C_LAW_ORDER]).execute():
		_law_order_entity = entity
		break
	for entity in world.query.with_all([C_FACTION_STATE]).execute():
		_faction_state_entity = entity
		break
	for entity in world.query.with_all([C_WORLD_SQUAD]).execute():
		_world_squad_entity = entity
		break
	for entity in world.query.with_all([C_WORLD_EVENT]).execute():
		_world_event_entity = entity
		break
	for entity in world.query.with_all([C_NEST_STATE]).execute():
		_nest_state_entity = entity
		break
	for entity in world.query.with_all([C_JOB_SYSTEM]).execute():
		_job_system_entity = entity
		break
	for entity in world.query.with_all([C_LEDGER_SIMULATION]).execute():
		_ledger_simulation_entity = entity
		break
	for entity in world.query.with_all([C_AI_SCHEDULER_STATE]).execute():
		_ai_scheduler_state_entity = entity
		break
	for entity in world.query.with_all([C_POPULATION_REALIZATION_STATE]).execute():
		_population_realization_state_entity = entity
		break
	_actor_spatial_index_valid = false


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _resource_path(resource) -> String:
	if resource == null:
		return ""
	if resource is Resource:
		return str((resource as Resource).resource_path)
	return ""


func _spatial_cell_coords(position: Vector3) -> Vector2i:
	var cell_size: float = maxf(spatial_cell_size, 1.0)
	return Vector2i(int(floor(position.x / cell_size)), int(floor(position.z / cell_size)))


func _entity_id(prefix: String, key: String) -> String:
	return "%s:%s" % [prefix, key]


func _strip_entity_prefix(entity_id: String, prefix: String) -> String:
	var full_prefix: String = "%s:" % prefix
	if entity_id.begins_with(full_prefix):
		return entity_id.substr(full_prefix.length())
	return entity_id


func _entity_node_name(prefix: String, key: String) -> String:
	return "%s_%s" % [prefix, _sanitize_id(key)]


func _sanitize_id(value: String) -> String:
	var text: String = value.strip_edges().to_lower()
	var result := ""
	for index in range(text.length()):
		var ch: String = text.substr(index, 1)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			result += ch
		else:
			result += "_"
	while result.contains("__"):
		result = result.replace("__", "_")
	while result.begins_with("_"):
		result = result.substr(1)
	while result.ends_with("_") and result.length() > 0:
		result = result.substr(0, result.length() - 1)
	return result
