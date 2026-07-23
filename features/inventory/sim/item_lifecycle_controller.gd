extends Node

class_name ItemLifecycleController

signal item_location_changed(stack_id: String, record: Dictionary)
signal item_metadata_changed(stack_id: String, metadata: Dictionary)

const SERVICE_ID := &"item_lifecycle"
const ENTITY_SCRIPT := preload("res://addons/gecs/ecs/entity.gd")
const C_ITEM_COMMAND := preload("res://features/inventory/sim/c_game_item_lifecycle_command.gd")
const FIXED_TICK_SECONDS := 1.0 / 20.0
var _gecs: GecsWorldController
var _records_by_stack_id: Dictionary = {}
var _stack_ids_by_host: Dictionary = {}
var _pending_command_by_stack_id: Dictionary = {}
var _next_command_sequence := 1
var _tick_accumulator := 0.0


func initialize(context: BootstrapContext) -> void:
	_gecs = context.require(GecsWorldController.SERVICE_ID) as GecsWorldController
	_gecs.world_reindexed.connect(_rebuild_indexes)
	_rebuild_indexes()


func _physics_process(delta: float) -> void:
	if _pending_command_by_stack_id.is_empty():
		_tick_accumulator = 0.0
		return
	_tick_accumulator += delta
	while _tick_accumulator >= FIXED_TICK_SECONDS:
		_tick_accumulator -= FIXED_TICK_SECONDS
		_drain_commands()


func _drain_commands() -> void:
	if _pending_command_by_stack_id.is_empty():
		return
	for entity in _pending_command_by_stack_id.values().duplicate():
		if entity == null or not is_instance_valid(entity):
			continue
		var command = entity.get_component(C_ITEM_COMMAND)
		if command == null:
			continue
		if _pending_command_by_stack_id.get(str(command.stack_id)) != entity:
			continue
		resolve_command(entity, command)


func get_stack_record(stack_id: String) -> Dictionary:
	var record := _records_by_stack_id.get(stack_id, {}) as Dictionary
	if record.is_empty() and _gecs != null:
		record = _gecs.get_item_stack(stack_id)
		if not record.is_empty():
			_index_record(record)
	return record.duplicate(true)


func get_stack_records_for_host(host_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if host_id.is_empty():
		return result
	for stack_id in (_stack_ids_by_host.get(host_id, {}) as Dictionary).keys():
		result.append((_records_by_stack_id.get(stack_id, {}) as Dictionary).duplicate(true))
	return result


func submit_world_stack(record: Dictionary) -> Dictionary:
	var stack_id := str(record.get("stack_id", "")).strip_edges()
	if stack_id.is_empty() or str(record.get("item_definition_path", "")).is_empty() or int(record.get("count", 0)) <= 0:
		return {"accepted": false, "result_code": "invalid_world_stack"}
	var command = C_ITEM_COMMAND.new()
	command.operation = C_ITEM_COMMAND.Operation.UPSERT_WORLD
	command.record = record.duplicate(true)
	return _enqueue_command(stack_id, command, true)


func submit_inventory(stack_id: String, owner_actor_id: String, container_id: String) -> Dictionary:
	return _submit_location(stack_id, "inventory", Transform3D.IDENTITY, "", "", "", owner_actor_id, container_id)


func submit_world_loose(stack_id: String, world_transform: Transform3D, settlement_id := "") -> Dictionary:
	return _submit_location(stack_id, "world_loose", world_transform, "", "", settlement_id, "", "world")


func submit_placed(stack_id: String, world_transform: Transform3D, host_id: String, slot_id: String, settlement_id: String, tabletop := false) -> Dictionary:
	return _submit_location(stack_id, "tabletop_slot" if tabletop else "world_placed", world_transform, host_id, slot_id, settlement_id, "", "world")


func submit_metadata(stack_id: String, metadata: Dictionary) -> Dictionary:
	var pending_entity = _pending_command_by_stack_id.get(stack_id)
	var pending = pending_entity.get_component(C_ITEM_COMMAND) if pending_entity != null and is_instance_valid(pending_entity) else null
	if pending != null:
		match int(pending.operation):
			C_ITEM_COMMAND.Operation.UPSERT_WORLD:
				pending.record["metadata"] = metadata.duplicate(true)
			C_ITEM_COMMAND.Operation.SET_LOCATION, C_ITEM_COMMAND.Operation.UPDATE_METADATA:
				pending.metadata = metadata.duplicate(true)
				pending.applies_metadata = true
		return {"accepted": true, "command_id": str(pending.command_id), "coalesced": true}
	if get_stack_record(stack_id).is_empty():
		return {"accepted": false, "result_code": "stack_missing"}
	var command = C_ITEM_COMMAND.new()
	command.operation = C_ITEM_COMMAND.Operation.UPDATE_METADATA
	command.metadata = metadata.duplicate(true)
	command.applies_metadata = true
	return _enqueue_command(stack_id, command)


func validate_build_command(command: ItemBuildCommand) -> Dictionary:
	if command == null or command.command_id.strip_edges().is_empty():
		return {"valid": false, "reason": "Command ID is required"}
	if command.actor_id.strip_edges().is_empty():
		return {"valid": false, "reason": "Actor ID is required"}
	if command.item_definition_path.strip_edges().is_empty():
		return {"valid": false, "reason": "Item definition is invalid"}
	var definition := load(command.item_definition_path) as ItemDefinition
	if definition == null:
		return {"valid": false, "reason": "Item definition is invalid"}
	if command.count <= 0:
		return {"valid": false, "reason": "Count must be positive"}
	return {"valid": true, "reason": ""}


func validate_place_command(stack_id: String, world_transform: Transform3D, host_id := "", slot_id := "") -> Dictionary:
	var record := get_stack_record(stack_id)
	if record.is_empty():
		return {"valid": false, "reason": "Unknown item stack"}
	if str(record.get("location_kind", "")) != "inventory":
		return {"valid": false, "reason": "Item is not held"}
	if world_transform.origin.length() > 1000000.0:
		return {"valid": false, "reason": "Placement is outside world bounds"}
	if host_id.is_empty() != slot_id.is_empty():
		return {"valid": false, "reason": "Host and slot must be supplied together"}
	return {"valid": true, "reason": ""}


func _submit_location(stack_id: String, kind: String, world_transform: Transform3D, host_id: String, slot_id: String, settlement_id: String, owner_actor_id: String, container_id: String) -> Dictionary:
	if get_stack_record(stack_id).is_empty():
		return {"accepted": false, "result_code": "stack_missing"}
	var command = C_ITEM_COMMAND.new()
	command.operation = C_ITEM_COMMAND.Operation.SET_LOCATION
	command.location_kind = kind
	command.world_transform = world_transform
	command.placement_host_id = host_id
	command.placement_slot_id = slot_id
	command.settlement_id = settlement_id
	command.owner_actor_id = owner_actor_id
	command.container_id = container_id
	return _enqueue_command(stack_id, command, true)


func _enqueue_command(stack_id: String, command, replace_pending := false) -> Dictionary:
	if _gecs == null or _gecs.world == null:
		return {"accepted": false, "result_code": "gecs_missing"}
	if _pending_command_by_stack_id.has(stack_id):
		if not replace_pending:
			return {"accepted": false, "result_code": "stack_busy"}
		var previous = _pending_command_by_stack_id.get(stack_id)
		var previous_command = previous.get_component(C_ITEM_COMMAND) if previous != null and is_instance_valid(previous) else null
		if previous_command != null and bool(previous_command.applies_metadata):
			command.metadata = previous_command.metadata.duplicate(true)
			command.applies_metadata = true
		if previous != null and is_instance_valid(previous):
			_gecs.world.remove_entity(previous)
		_pending_command_by_stack_id.erase(stack_id)
	var command_id := "%s:%d" % [stack_id, _next_command_sequence]
	_next_command_sequence += 1
	command.command_id = command_id
	command.stack_id = stack_id
	var entity = ENTITY_SCRIPT.new()
	entity.name = "ItemLifecycleCommand_%d" % _next_command_sequence
	entity.id = "item_lifecycle_command:%s" % command_id
	_gecs.world.add_entity(entity, [command])
	_pending_command_by_stack_id[stack_id] = entity
	return {"accepted": true, "command_id": command_id}


func resolve_command(entity, command) -> void:
	var record: Dictionary
	match int(command.operation):
		C_ITEM_COMMAND.Operation.UPSERT_WORLD:
			record = _gecs.upsert_item_stack_record(command.record)
		C_ITEM_COMMAND.Operation.SET_LOCATION:
			record = _gecs.get_item_stack(command.stack_id)
			if record.is_empty():
				record = get_stack_record(command.stack_id)
			if not record.is_empty():
				var canonical_kind := str(record.get("location_kind", ""))
				var superseded_inventory_move: bool = str(command.location_kind) == "inventory" and canonical_kind in ["inventory", "equipment"]
				if not superseded_inventory_move:
					record["location_kind"] = command.location_kind
					record["world_transform"] = command.world_transform
					record["placement_host_id"] = command.placement_host_id
					record["placement_slot_id"] = command.placement_slot_id
					record["location_settlement_id"] = command.settlement_id
					record["owner_actor_id"] = command.owner_actor_id
					record["container_id"] = command.container_id
					if bool(command.applies_metadata):
						record["metadata"] = command.metadata.duplicate(true)
					record = _gecs.upsert_item_stack_record(record)
				elif bool(command.applies_metadata):
					record["metadata"] = command.metadata.duplicate(true)
					record = _gecs.upsert_item_stack_record(record)
		C_ITEM_COMMAND.Operation.UPDATE_METADATA:
			record = get_stack_record(command.stack_id)
			if not record.is_empty():
				record["metadata"] = command.metadata.duplicate(true)
				record = _gecs.upsert_item_stack_record(record)
	if not record.is_empty():
		_index_record(record)
		if int(command.operation) == C_ITEM_COMMAND.Operation.UPDATE_METADATA:
			item_metadata_changed.emit(command.stack_id, (record.get("metadata", {}) as Dictionary).duplicate(true))
		else:
			item_location_changed.emit(command.stack_id, record.duplicate(true))
	_pending_command_by_stack_id.erase(command.stack_id)
	if entity != null and is_instance_valid(entity) and _gecs.world != null:
		_gecs.world.remove_entity(entity)


func _rebuild_indexes() -> void:
	_records_by_stack_id.clear()
	_stack_ids_by_host.clear()
	_pending_command_by_stack_id.clear()
	if _gecs == null:
		return
	for record in _gecs.get_inventory_stacks():
		_index_record(record)
	if _gecs.world == null:
		return
	for entity in _gecs.world.query.with_all([C_ITEM_COMMAND]).execute():
		var command = entity.get_component(C_ITEM_COMMAND)
		if command == null or str(command.stack_id).is_empty():
			continue
		_pending_command_by_stack_id[str(command.stack_id)] = entity
		_next_command_sequence = maxi(_next_command_sequence, int(str(command.command_id).get_slice(":", str(command.command_id).get_slice_count(":") - 1)) + 1)


func _index_record(record: Dictionary) -> void:
	var stack_id := str(record.get("stack_id", ""))
	if stack_id.is_empty():
		return
	var previous := _records_by_stack_id.get(stack_id, {}) as Dictionary
	_remove_host_index(stack_id, previous)
	_records_by_stack_id[stack_id] = record.duplicate(true)
	var metadata := record.get("metadata", {}) as Dictionary
	var host_id := str(record.get("placement_host_id", ""))
	if host_id.is_empty():
		host_id = str(metadata.get("tabletop_origin_host_id", ""))
	if host_id.is_empty():
		return
	var ids := _stack_ids_by_host.get(host_id, {}) as Dictionary
	ids[stack_id] = true
	_stack_ids_by_host[host_id] = ids


func _remove_host_index(stack_id: String, record: Dictionary) -> void:
	if record.is_empty():
		return
	var metadata := record.get("metadata", {}) as Dictionary
	var host_id := str(record.get("placement_host_id", ""))
	if host_id.is_empty():
		host_id = str(metadata.get("tabletop_origin_host_id", ""))
	var ids := _stack_ids_by_host.get(host_id, {}) as Dictionary
	ids.erase(stack_id)
	if ids.is_empty():
		_stack_ids_by_host.erase(host_id)
