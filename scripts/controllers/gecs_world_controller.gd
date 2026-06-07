extends Node

class_name GecsWorldController

const WORLD_SCRIPT_PATH := "res://addons/gecs/ecs/world.gd"
const ENTITY_SCRIPT_PATH := "res://addons/gecs/ecs/entity.gd"
const ECS_SCRIPT_PATH := "res://addons/gecs/ecs/ecs.gd"
const GECS_IO_SCRIPT_PATH := "res://addons/gecs/io/io.gd"
const ACTOR_SYNC_SYSTEM_SCRIPT_PATH := "res://scripts/ecs/systems/game_actor_sync_system.gd"

const C_NODE_PATH := "res://scripts/ecs/components/c_game_actor_node.gd"
const C_IDENTITY_PATH := "res://scripts/ecs/components/c_game_actor_identity.gd"
const C_FACTION_PATH := "res://scripts/ecs/components/c_game_actor_faction.gd"
const C_SETTLEMENT_PATH := "res://scripts/ecs/components/c_game_actor_settlement.gd"
const C_SPATIAL_PATH := "res://scripts/ecs/components/c_game_actor_spatial.gd"
const C_VITALS_PATH := "res://scripts/ecs/components/c_game_actor_vitals.gd"
const C_POPULATION_RECORD_PATH := "res://scripts/ecs/components/c_game_population_record.gd"
const C_SETTLEMENT_STATE_PATH := "res://scripts/ecs/components/c_game_settlement_state.gd"
const C_STAFF_SLOT_PATH := "res://scripts/ecs/components/c_game_staff_slot.gd"
const C_STAFF_VACANCY_PATH := "res://scripts/ecs/components/c_game_staff_vacancy.gd"
const C_INVENTORY_CONTAINER_PATH := "res://scripts/ecs/components/c_game_inventory_container.gd"
const C_ITEM_STACK_PATH := "res://scripts/ecs/components/c_game_item_stack.gd"
const C_EQUIPMENT_SLOT_PATH := "res://scripts/ecs/components/c_game_equipment_slot.gd"
const C_SETTLEMENT_EVENT_PATH := "res://scripts/ecs/components/c_game_settlement_event.gd"
const C_JOB_PROVIDER_PATH := "res://scripts/ecs/components/c_game_job_provider.gd"
const C_JOB_PROVIDER_SLOT_PATH := "res://scripts/ecs/components/c_game_job_provider_slot.gd"
const C_JOB_WORKER_RECORD_PATH := "res://scripts/ecs/components/c_game_job_worker_record.gd"
const C_JOB_CONTRACT_PATH := "res://scripts/ecs/components/c_game_job_contract.gd"
const C_JOB_PROVIDER_MEMORY_PATH := "res://scripts/ecs/components/c_game_job_provider_memory.gd"
const C_ACTIVITY_POINT_PATH := "res://scripts/ecs/components/c_game_activity_point.gd"
const C_ACTIVITY_ASSIGNMENT_PATH := "res://scripts/ecs/components/c_game_activity_assignment.gd"
const C_WORLD_TIME_PATH := "res://scripts/ecs/components/c_game_world_time_state.gd"
const C_LAW_ORDER_PATH := "res://scripts/ecs/components/c_game_law_order_state.gd"
const C_FACTION_STATE_PATH := "res://scripts/ecs/components/c_game_faction_state.gd"
const C_WORLD_SQUAD_PATH := "res://scripts/ecs/components/c_game_world_squad_state.gd"
const C_WORLD_ENCOUNTER_PATH := "res://scripts/ecs/components/c_game_world_encounter_state.gd"
const C_WORLD_EVENT_PATH := "res://scripts/ecs/components/c_game_world_event_state.gd"
const C_NEST_STATE_PATH := "res://scripts/ecs/components/c_game_nest_state.gd"
const C_JOB_SYSTEM_PATH := "res://scripts/ecs/components/c_game_job_system_state.gd"
const C_LEDGER_SIMULATION_PATH := "res://scripts/ecs/components/c_game_ledger_simulation_state.gd"
const C_POPULATION_REALIZATION_STATE_PATH := "res://scripts/ecs/components/c_game_population_realization_state.gd"

@export var spatial_cell_size := 12.0

var root_scene: Node
var world
var _actor_entity_by_actor_id: Dictionary = {}
var _actor_id_by_instance_id: Dictionary = {}
var _population_entity_by_actor_id: Dictionary = {}
var _settlement_entity_by_id: Dictionary = {}
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
var _world_time_entity
var _law_order_entity
var _faction_state_entity
var _world_squad_entity
var _world_encounter_entity
var _world_event_entity
var _nest_state_entity
var _job_system_entity
var _ledger_simulation_entity
var _population_realization_state_entity
var _initialized := false
var _world_script
var _entity_script
var _ecs_script
var _gecs_io_script
var _actor_sync_system_script
var _registered_direct_script_ecs_singleton := false
var _direct_script_ecs_placeholder: Node
var C_NODE
var C_IDENTITY
var C_FACTION
var C_SETTLEMENT
var C_SPATIAL
var C_VITALS
var C_POPULATION_RECORD
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
var C_WORLD_ENCOUNTER
var C_WORLD_EVENT
var C_NEST_STATE
var C_JOB_SYSTEM
var C_LEDGER_SIMULATION
var C_POPULATION_REALIZATION_STATE


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
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


func _process(delta: float) -> void:
	if world != null:
		world.process(delta)


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
		world.add_entity(entity, [C_NODE.new(), C_IDENTITY.new(), C_FACTION.new(), C_SETTLEMENT.new(), C_SPATIAL.new(), C_VITALS.new()])
		_actor_entity_by_actor_id[actor_id] = entity
	_write_actor_components(entity, actor, actor_id, settlement_id, context)
	_actor_id_by_instance_id[actor.get_instance_id()] = actor_id
	sync_actor_inventory(actor)
	return actor_id


func unregister_actor(actor: Node) -> void:
	if actor == null:
		return
	var actor_id: String = _actor_record_id(actor)
	if actor_id.is_empty():
		actor_id = _actor_id_by_instance_id.get(actor.get_instance_id(), "")
	if actor_id.is_empty():
		return
	sync_actor_inventory(actor)
	var entity = _actor_entity_by_actor_id.get(actor_id)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)
	_actor_entity_by_actor_id.erase(actor_id)
	_actor_id_by_instance_id.erase(actor.get_instance_id())
	var pop_entity = _population_entity_by_actor_id.get(actor_id)
	if pop_entity != null and is_instance_valid(pop_entity):
		var record_component = pop_entity.get_component(C_POPULATION_RECORD)
		if record_component != null:
			var record: Dictionary = record_component.to_record() if record_component.has_method("to_record") else {}
			record["realization_state"] = "ledger"
			record.erase("live_node_path")
			if actor is Node3D:
				record["last_world_position"] = (actor as Node3D).global_position
				record["last_world_position_initialized"] = true
			upsert_population_record(record)


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
		world.add_entity(entity, [C_POPULATION_RECORD.new()])
		_population_entity_by_actor_id[actor_id] = entity
	var component = entity.get_component(C_POPULATION_RECORD)
	component.apply_record(record)
	_sync_record_equipment_slots(actor_id, record.get("equipment_slots", {}))
	_sync_record_inventory_entries(actor_id, record.get("inventory_entries", []))
	return _populate_record_inventory_and_equipment(component.to_record())


func remove_population_record(actor_id: String) -> void:
	var entity = _population_entity_by_actor_id.get(actor_id)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)
	_population_entity_by_actor_id.erase(actor_id)


func clear_population_records() -> void:
	if world == null:
		_population_entity_by_actor_id.clear()
		return
	var entities: Array = []
	for entity in world.query.with_all([C_POPULATION_RECORD]).execute():
		entities.append(entity)
	for entity in entities:
		if entity != null and is_instance_valid(entity):
			world.remove_entity(entity)
	_population_entity_by_actor_id.clear()


func get_population_record(actor_id: String) -> Dictionary:
	var entity = _population_entity_by_actor_id.get(actor_id)
	if entity == null or not is_instance_valid(entity):
		return {}
	var component = entity.get_component(C_POPULATION_RECORD)
	return _populate_record_inventory_and_equipment(component.to_record()) if component != null and component.has_method("to_record") else {}


func get_population_records() -> Dictionary:
	var records: Dictionary = {}
	if world == null:
		return records
	for entity in world.query.with_all([C_POPULATION_RECORD]).execute():
		var component = entity.get_component(C_POPULATION_RECORD)
		if component == null:
			continue
		records[str(component.actor_id)] = _populate_record_inventory_and_equipment(component.to_record()) if component.has_method("to_record") else {}
		_population_entity_by_actor_id[str(component.actor_id)] = entity
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


func record_settlement_event(event_record: Dictionary) -> void:
	_try_initialize()
	if world == null or event_record.is_empty():
		return
	var settlement_id := str(event_record.get("settlement_id", "world"))
	var event_type := str(event_record.get("type", "event"))
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
	var container_id := _node_container_id(container)
	_sync_inventory_container("", container_id, container, inventory, false, true)


func sync_world_item(item: Node) -> void:
	if item == null or not is_instance_valid(item):
		return
	_try_initialize()
	if world == null:
		return
	var definition = item.get("item_definition") if _has_property(item, "item_definition") else null
	var item_path := _resource_path(definition)
	if item_path.is_empty():
		return
	var stack_id := _world_item_stack_id(item)
	var entity = _item_stack_entity_by_id.get(stack_id)
	if entity == null or not is_instance_valid(entity):
		entity = _entity_script.new()
		entity.name = _entity_node_name("WorldItem", stack_id)
		entity.id = _entity_id("item_stack", stack_id)
		world.add_entity(entity, [C_ITEM_STACK.new()])
		_item_stack_entity_by_id[stack_id] = entity
	var component = entity.get_component(C_ITEM_STACK)
	component.stack_id = stack_id
	component.container_id = "world"
	component.owner_actor_id = ""
	component.item_definition_path = item_path
	component.count = int(item.get("quantity")) if _has_property(item, "quantity") else 1
	component.grid_position = Vector2i.ZERO
	component.contained_item_counts = (item.get("contained_item_counts") as Dictionary).duplicate(true) if _has_property(item, "contained_item_counts") else {}
	component.metadata = (item.get("item_metadata") as Dictionary).duplicate(true) if _has_property(item, "item_metadata") else {}
	component.world_item_path = item.get_path() if item.is_inside_tree() else NodePath()


func remove_world_item(item: Node) -> void:
	if item == null:
		return
	var stack_id := _world_item_stack_id(item)
	var entity = _item_stack_entity_by_id.get(stack_id)
	if entity != null and is_instance_valid(entity) and world != null:
		world.remove_entity(entity)
	_item_stack_entity_by_id.erase(stack_id)


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
		})
	return stacks


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
	return bool(get_actor_state(actor_id).get("player_party_member", false))


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


func upsert_world_encounter_state(state: Dictionary) -> Dictionary:
	_world_encounter_entity = _upsert_state_entity(_world_encounter_entity, "WorldEncounterState", _entity_id("world_encounter", "state"), C_WORLD_ENCOUNTER)
	return _apply_state_component(_world_encounter_entity, C_WORLD_ENCOUNTER, state)


func get_world_encounter_state() -> Dictionary:
	_world_encounter_entity = _find_state_entity(_world_encounter_entity, C_WORLD_ENCOUNTER)
	return _state_component_to_dictionary(_world_encounter_entity, C_WORLD_ENCOUNTER)


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
	_clear_world_entities()
	for entity in entities:
		if entity != null:
			world.add_entity(entity)
	_rebuild_entity_indexes()
	return true


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
		"staff_slot_entity_count": _staff_slot_entity_by_key.size(),
		"inventory_container_entity_count": _inventory_container_entity_by_id.size(),
		"item_stack_entity_count": _item_stack_entity_by_id.size(),
		"equipment_slot_entity_count": _equipment_slot_entity_by_key.size(),
		"world_time_entity_count": 1 if _world_time_entity != null and is_instance_valid(_world_time_entity) else 0,
		"law_order_entity_count": 1 if _law_order_entity != null and is_instance_valid(_law_order_entity) else 0,
		"faction_state_entity_count": 1 if _faction_state_entity != null and is_instance_valid(_faction_state_entity) else 0,
		"world_squad_entity_count": 1 if _world_squad_entity != null and is_instance_valid(_world_squad_entity) else 0,
		"world_encounter_entity_count": 1 if _world_encounter_entity != null and is_instance_valid(_world_encounter_entity) else 0,
		"world_event_entity_count": 1 if _world_event_entity != null and is_instance_valid(_world_event_entity) else 0,
		"nest_state_entity_count": 1 if _nest_state_entity != null and is_instance_valid(_nest_state_entity) else 0,
		"job_system_entity_count": 1 if _job_system_entity != null and is_instance_valid(_job_system_entity) else 0,
		"ledger_simulation_entity_count": 1 if _ledger_simulation_entity != null and is_instance_valid(_ledger_simulation_entity) else 0,
		"population_realization_state_entity_count": 1 if _population_realization_state_entity != null and is_instance_valid(_population_realization_state_entity) else 0,
		"job_contract_entity_count": _job_contract_entity_by_id.size(),
		"job_provider_memory_entity_count": _job_provider_memory_entity_by_id.size(),
		"spatial_cell_count": get_spatial_cell_count(),
		"world_entity_count": world.entities.size() if world != null else 0,
	}


func _load_gecs_scripts() -> bool:
	if _world_script != null and _entity_script != null and _ecs_script != null and _gecs_io_script != null and _actor_sync_system_script != null and _component_scripts_loaded():
		return true
	_ensure_direct_script_ecs_singleton()
	_load_component_scripts()
	_world_script = load(WORLD_SCRIPT_PATH) if _world_script == null else _world_script
	_entity_script = load(ENTITY_SCRIPT_PATH) if _entity_script == null else _entity_script
	_ecs_script = load(ECS_SCRIPT_PATH) if _ecs_script == null else _ecs_script
	_gecs_io_script = load(GECS_IO_SCRIPT_PATH) if _gecs_io_script == null else _gecs_io_script
	_actor_sync_system_script = load(ACTOR_SYNC_SYSTEM_SCRIPT_PATH) if _actor_sync_system_script == null else _actor_sync_system_script
	return _world_script != null and _entity_script != null and _ecs_script != null and _gecs_io_script != null and _actor_sync_system_script != null and _component_scripts_loaded()


func _load_component_scripts() -> void:
	C_NODE = load(C_NODE_PATH) if C_NODE == null else C_NODE
	C_IDENTITY = load(C_IDENTITY_PATH) if C_IDENTITY == null else C_IDENTITY
	C_FACTION = load(C_FACTION_PATH) if C_FACTION == null else C_FACTION
	C_SETTLEMENT = load(C_SETTLEMENT_PATH) if C_SETTLEMENT == null else C_SETTLEMENT
	C_SPATIAL = load(C_SPATIAL_PATH) if C_SPATIAL == null else C_SPATIAL
	C_VITALS = load(C_VITALS_PATH) if C_VITALS == null else C_VITALS
	C_POPULATION_RECORD = load(C_POPULATION_RECORD_PATH) if C_POPULATION_RECORD == null else C_POPULATION_RECORD
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
	C_WORLD_ENCOUNTER = load(C_WORLD_ENCOUNTER_PATH) if C_WORLD_ENCOUNTER == null else C_WORLD_ENCOUNTER
	C_WORLD_EVENT = load(C_WORLD_EVENT_PATH) if C_WORLD_EVENT == null else C_WORLD_EVENT
	C_NEST_STATE = load(C_NEST_STATE_PATH) if C_NEST_STATE == null else C_NEST_STATE
	C_JOB_SYSTEM = load(C_JOB_SYSTEM_PATH) if C_JOB_SYSTEM == null else C_JOB_SYSTEM
	C_LEDGER_SIMULATION = load(C_LEDGER_SIMULATION_PATH) if C_LEDGER_SIMULATION == null else C_LEDGER_SIMULATION
	C_POPULATION_REALIZATION_STATE = load(C_POPULATION_REALIZATION_STATE_PATH) if C_POPULATION_REALIZATION_STATE == null else C_POPULATION_REALIZATION_STATE


func _component_scripts_loaded() -> bool:
	for component_script in [
		C_NODE,
		C_IDENTITY,
		C_FACTION,
		C_SETTLEMENT,
		C_SPATIAL,
		C_VITALS,
		C_POPULATION_RECORD,
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
		C_WORLD_ENCOUNTER,
		C_WORLD_EVENT,
		C_NEST_STATE,
		C_JOB_SYSTEM,
		C_LEDGER_SIMULATION,
		C_POPULATION_REALIZATION_STATE,
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
	var ecs_node = get_node_or_null("/root/ECS")
	if ecs_node == null:
		ecs_node = _ecs_script.new()
		ecs_node.name = "ECS"
		get_tree().root.add_child(ecs_node)
	if _registered_direct_script_ecs_singleton:
		Engine.unregister_singleton("ECS")
		if _direct_script_ecs_placeholder != null:
			_direct_script_ecs_placeholder.free()
			_direct_script_ecs_placeholder = null
		Engine.register_singleton("ECS", ecs_node)
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
	component.owner_path = inventory_owner.get_path() if inventory_owner != null and inventory_owner.is_inside_tree() else NodePath()
	component.columns = int(inventory.get("columns")) if _has_property(inventory, "columns") else 0
	component.rows = int(inventory.get("rows")) if _has_property(inventory, "rows") else 0
	component.max_weight = float(inventory.get("max_weight")) if _has_property(inventory, "max_weight") else 0.0
	component.accepts_input = true
	component.is_world_container = is_world_container
	component.is_job_work_inventory = is_work_inventory
	_clear_item_stacks_for_container(container_id)
	var entries: Array = inventory.get("entries") if _has_property(inventory, "entries") else []
	for index in range(entries.size()):
		_sync_item_stack(actor_id, container_id, index, entries[index], NodePath())


func _sync_item_stack(actor_id: String, container_id: String, index: int, entry, world_item_path: NodePath) -> void:
	if entry == null:
		return
	var item_path := _resource_path(entry.get("definition")) if _has_property(entry, "definition") else ""
	if item_path.is_empty():
		return
	var stack_id := "%s.stack.%03d" % [container_id, index]
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
	component.world_item_path = world_item_path


func _sync_equipment_slots(actor_id: String, actor: Node) -> void:
	_clear_equipment_slots_for_actor(actor_id)
	if actor == null or not _has_property(actor, "equipped_items"):
		return
	var equipped = actor.get("equipped_items")
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
		component.stack_id = ""


func _sync_record_equipment_slots(actor_id: String, equipment_slots) -> void:
	if actor_id.is_empty() or not (equipment_slots is Dictionary):
		return
	_clear_equipment_slots_for_actor(actor_id)
	for slot_name_value in (equipment_slots as Dictionary).keys():
		var slot_name := str(slot_name_value)
		var item_path := str((equipment_slots as Dictionary)[slot_name_value])
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
		component.stack_id = ""


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
	_clear_item_stacks_for_container(container_id)
	for index in range((inventory_entries as Array).size()):
		var snapshot = (inventory_entries as Array)[index]
		if snapshot is Dictionary:
			_sync_item_stack_from_snapshot(actor_id, container_id, index, snapshot)


func _sync_item_stack_from_snapshot(actor_id: String, container_id: String, index: int, snapshot: Dictionary) -> void:
	var item_path := str(snapshot.get("item_id", snapshot.get("item_definition_path", "")))
	if item_path.is_empty():
		return
	var stack_id := "%s.stack.%03d" % [container_id, index]
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
			"item_id": str(stack.get("item_definition_path", "")),
			"count": int(stack.get("count", 1)),
			"grid_position": stack.get("grid_position", Vector2i.ZERO),
			"contained_item_counts": (stack.get("contained_item_counts", {}) as Dictionary).duplicate(true),
			"metadata": (stack.get("metadata", {}) as Dictionary).duplicate(true),
		})
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
			component.last_work_blocker = str(slot_data.get("last_work_blocker", ""))
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
		if str(stack_id).begins_with("%s.stack." % container_id):
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
	return state


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
	return actor.is_in_group("settlement_authority") or actor.has_meta("settlement_staff_role") or actor.has_meta("law_prisoner")


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


func _node_container_id(node: Node) -> String:
	if node == null:
		return ""
	if node.is_inside_tree():
		return str(node.get_path())
	return str(node.get_instance_id())


func _world_item_stack_id(item: Node) -> String:
	return "world_item:%s" % _node_container_id(item)


func _sync_live_scene_state_for_save() -> void:
	if not is_inside_tree():
		return
	for actor_id_value in _actor_entity_by_actor_id.keys():
		var actor_id := str(actor_id_value)
		var entity = _actor_entity_by_actor_id.get(actor_id_value)
		var actor := _actor_from_entity(entity)
		if actor == null:
			continue
		_write_actor_components(entity, actor, actor_id, _actor_settlement_id(actor), {})
		sync_actor_inventory(actor)
	for container in get_tree().get_nodes_in_group("world_container"):
		sync_world_container(container)
	for item in get_tree().get_nodes_in_group("world_item"):
		sync_world_item(item)


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
	_settlement_entity_by_id.clear()
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
	_world_time_entity = null
	_law_order_entity = null
	_faction_state_entity = null
	_world_squad_entity = null
	_world_encounter_entity = null
	_world_event_entity = null
	_nest_state_entity = null
	_job_system_entity = null
	_ledger_simulation_entity = null
	_population_realization_state_entity = null


func _rebuild_entity_indexes() -> void:
	if world == null:
		return
	for entity in world.query.with_all([C_IDENTITY]).execute():
		var identity = entity.get_component(C_IDENTITY)
		if identity == null:
			continue
		_actor_entity_by_actor_id[str(identity.actor_id)] = entity
	for entity in world.query.with_all([C_POPULATION_RECORD]).execute():
		var population = entity.get_component(C_POPULATION_RECORD)
		if population != null:
			_population_entity_by_actor_id[str(population.actor_id)] = entity
	for entity in world.query.with_all([C_SETTLEMENT_STATE]).execute():
		var settlement = entity.get_component(C_SETTLEMENT_STATE)
		if settlement != null:
			_settlement_entity_by_id[str(settlement.settlement_id)] = entity
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
	for entity in world.query.with_all([C_WORLD_ENCOUNTER]).execute():
		_world_encounter_entity = entity
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
	for entity in world.query.with_all([C_POPULATION_REALIZATION_STATE]).execute():
		_population_realization_state_entity = entity
		break


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
