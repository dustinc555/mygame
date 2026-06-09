extends Node

class_name JobSystemController

const JOB_ALGORITHM_MINE_AND_HAUL := "mine_and_haul"
const INTERACTION_MINE_RESOURCE := "mine_resource"
const DEFAULT_CARRY_ITEM_THRESHOLD := 3
const DEFAULT_PAY_INTERVAL_SECONDS := 30.0
const DEFAULT_PAY_PER_INTERVAL := 1
const CONTAINER_ARRIVAL_DISTANCE := 2.0

var root_scene: Node
var _sim_time := 0.0
var _initialized := false
var _resource_node_by_id: Dictionary = {}
var _container_node_by_id: Dictionary = {}
var _projection_controller: Node


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	if is_inside_tree():
		_initialized = true
		call_deferred("_rebuild_runtime_indexes")
	refresh_from_gecs_state()


func _ready() -> void:
	add_to_group("job_system_controller")
	if root_scene != null:
		_initialized = true
	call_deferred("_rebuild_runtime_indexes")
	refresh_from_gecs_state()


func _process(delta: float) -> void:
	if not _initialized:
		return
	_sim_time += delta
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("has_job_contracts") and not bool(bridge.call("has_job_contracts")):
		return
	_expire_missed_job_contracts()
	_process_active_job_contracts(delta)
	_sync_job_system_state_to_gecs()


func get_sim_time() -> float:
	return _sim_time


func serialize_state() -> Dictionary:
	_sync_job_system_state_to_gecs()
	return {"state_id": "job_system", "sim_time": _sim_time}


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty():
		refresh_from_gecs_state()
		return
	_sim_time = float(state.get("sim_time", _sim_time))
	_sync_job_system_state_to_gecs()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_job_system_state"):
		return
	var state: Dictionary = bridge.call("get_job_system_state")
	if not state.is_empty():
		_sim_time = float(state.get("sim_time", _sim_time))


func sync_job_system_state() -> void:
	_sync_job_system_state_to_gecs()


func _sync_job_system_state_to_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_job_system_state"):
		bridge.call("upsert_job_system_state", {"state_id": "job_system", "sim_time": _sim_time})


func _expire_missed_job_contracts() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("expire_missed_job_contracts"):
		bridge.call("expire_missed_job_contracts", _sim_time)


func _process_active_job_contracts(delta: float) -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_population_records_core") or not bridge.has_method("get_job_contracts"):
		return
	if bridge.has_method("has_job_contracts") and not bool(bridge.call("has_job_contracts")):
		return
	var contracts: Array = bridge.call("get_job_contracts")
	if contracts.is_empty():
		return
	if _resource_node_by_id.is_empty() or _container_node_by_id.is_empty():
		_rebuild_runtime_indexes()
	var records = bridge.call("get_population_records_core")
	if not (records is Dictionary):
		return
	var processed_actor_ids := {}
	for contract_value in contracts:
		if not (contract_value is Dictionary):
			continue
		var contract: Dictionary = contract_value
		if str(contract.get("status", "active")) != "active":
			continue
		if str(contract.get("algorithm_id", "")) != JOB_ALGORITHM_MINE_AND_HAUL:
			continue
		var actor_id := str(contract.get("actor_id", "")).strip_edges()
		if actor_id.is_empty():
			continue
		if processed_actor_ids.has(actor_id):
			continue
		var record_value = (records as Dictionary).get(actor_id, {})
		if not (record_value is Dictionary):
			continue
		processed_actor_ids[actor_id] = true
		_process_mine_and_haul_contract(bridge, contract, record_value, delta)


func _process_mine_and_haul_contract(bridge: Node, contract: Dictionary, core_record: Dictionary, delta: float) -> void:
	var actor_id := str(contract.get("actor_id", core_record.get("actor_id", ""))).strip_edges()
	if actor_id.is_empty() or int(core_record.get("life_state", 0)) != 0:
		return
	var full_record := _population_record_full(bridge, actor_id)
	var actor_record := full_record if not full_record.is_empty() else core_record
	var metadata: Dictionary = contract.get("metadata", {}) if contract.get("metadata", {}) is Dictionary else {}
	var item_path := str(metadata.get("item_definition_path", "")).strip_edges()
	var resource_id := str(metadata.get("resource_id", "")).strip_edges()
	var output_container_id := str(metadata.get("output_container_id", "")).strip_edges()
	var carry_threshold := maxi(1, int(metadata.get("carry_item_threshold", DEFAULT_CARRY_ITEM_THRESHOLD)))
	if item_path.is_empty() or resource_id.is_empty() or output_container_id.is_empty():
		return
	var move_order: Dictionary = actor_record.get("move_order", {}) if actor_record.get("move_order", {}) is Dictionary else {}
	if bool(move_order.get("active", false)):
		_accrue_contract_pay(bridge, contract, delta)
		return
	var work_action: Dictionary = actor_record.get("work_action", {}) if actor_record.get("work_action", {}) is Dictionary else {}
	var inventory_count := _actor_item_count(actor_record, item_path)
	if inventory_count >= carry_threshold or _work_action_is_inventory_full(work_action) or (inventory_count > 0 and _record_last_interaction_is_inventory_full(actor_record)):
		if bool(work_action.get("active", false)):
			_upsert_population_record(bridge, {"actor_id": actor_id, "work_action": {"active": false}})
		_process_haul_to_container(bridge, contract, actor_record, item_path, inventory_count, output_container_id)
		_accrue_contract_pay(bridge, contract, delta)
		return
	if bool(work_action.get("active", false)):
		_accrue_contract_pay(bridge, contract, delta)
		return
	var resource_node := _resource_node_for_id(resource_id)
	if resource_node == null or not resource_node.has_method("get_mining_action_for_actor"):
		return
	var action = resource_node.call("get_mining_action_for_actor", actor_id, actor_record)
	if not (action is Dictionary) or (action as Dictionary).is_empty():
		return
	var mining_action: Dictionary = (action as Dictionary).duplicate(true)
	mining_action["job_contract_id"] = str(contract.get("contract_id", ""))
	mining_action["output_container_id"] = output_container_id
	var target_position: Vector3 = mining_action.get("mining_position", _current_actor_position(actor_id, actor_record))
	var current_position := _current_actor_position(actor_id, actor_record)
	var interaction_radius := maxf(float(mining_action.get("interaction_radius", 1.8)), 0.05)
	if current_position.distance_to(target_position) <= interaction_radius:
		mining_action["active"] = true
		mining_action["progress_seconds"] = 0.0
		mining_action["progress_ratio"] = 0.0
		_upsert_population_record(bridge, {"actor_id": actor_id, "work_action": mining_action, "ledger_activity_state": "mining_resource"})
	else:
		_write_job_move_order(bridge, actor_id, actor_record, target_position, mining_action)
	_accrue_contract_pay(bridge, contract, delta)


func _process_haul_to_container(bridge: Node, contract: Dictionary, actor_record: Dictionary, item_path: String, inventory_count: int, output_container_id: String) -> void:
	if inventory_count <= 0:
		return
	var actor_id := str(actor_record.get("actor_id", contract.get("actor_id", ""))).strip_edges()
	var container_node := _container_node_for_id(output_container_id)
	if actor_id.is_empty() or container_node == null:
		return
	var current_position := _current_actor_position(actor_id, actor_record)
	var target_position := current_position
	if container_node.has_method("get_interaction_position_for_actor"):
		var value = container_node.call("get_interaction_position_for_actor", actor_id, current_position)
		if value is Vector3:
			target_position = value
	elif container_node is Node3D:
		target_position = (container_node as Node3D).global_position
	var arrival_distance := CONTAINER_ARRIVAL_DISTANCE
	if container_node.has_method("get_interaction_distance"):
		arrival_distance = maxf(float(container_node.call("get_interaction_distance")), 0.05)
	if current_position.distance_to(target_position) > arrival_distance:
		_write_job_move_order(bridge, actor_id, actor_record, target_position, {})
		return
	var result = bridge.call("apply_inventory_command", {"action": "transfer_item_count_to_container", "source_actor_id": actor_id, "target_container_id": output_container_id, "item_definition_path": item_path, "count": inventory_count}) if bridge.has_method("apply_inventory_command") else {"ok": false}
	var result_dict: Dictionary = result if result is Dictionary else {"ok": false, "message": "Invalid haul result"}
	_upsert_population_record(bridge, {"actor_id": actor_id, "last_interaction_result": result_dict, "ledger_activity_state": "hauled_mined_ore" if bool(result_dict.get("ok", false)) else "haul_failed"})


func _write_job_move_order(bridge: Node, actor_id: String, actor_record: Dictionary, target_position: Vector3, interaction_action: Dictionary) -> void:
	var current_position := _current_actor_position(actor_id, actor_record)
	var movement_mode := int(actor_record.get("movement_mode", 0))
	var move_order := {
		"active": true,
		"source": "job",
		"target_position": target_position,
		"issued_position": target_position,
		"movement_mode": movement_mode,
		"issued_msec": Time.get_ticks_msec(),
	}
	if not interaction_action.is_empty():
		move_order["interaction_action"] = interaction_action.duplicate(true)
	_upsert_population_record(bridge, {
		"actor_id": actor_id,
		"last_world_position": current_position,
		"last_world_position_initialized": true,
		"move_order": move_order,
		"work_action": {"active": false},
		"ledger_activity_state": "job_move_order",
	})


func _actor_item_count(record: Dictionary, item_path: String) -> int:
	var total := 0
	var entries: Array = record.get("inventory_entries", []) if record.get("inventory_entries", []) is Array else []
	for entry_value in entries:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("item_definition_path", entry.get("item_id", ""))) == item_path:
			total += int(entry.get("count", 1))
	return total


func _work_action_is_inventory_full(work_action: Dictionary) -> bool:
	if not bool(work_action.get("active", false)):
		return false
	var result: Dictionary = work_action.get("last_result", {}) if work_action.get("last_result", {}) is Dictionary else {}
	return str(result.get("message", "")) == "No room"


func _record_last_interaction_is_inventory_full(record: Dictionary) -> bool:
	var result: Dictionary = record.get("last_interaction_result", {}) if record.get("last_interaction_result", {}) is Dictionary else {}
	return str(result.get("message", "")) == "No room"


func _accrue_contract_pay(bridge: Node, contract: Dictionary, delta: float) -> void:
	if delta <= 0.0 or bridge == null or not bridge.has_method("upsert_job_contract"):
		return
	var metadata: Dictionary = contract.get("metadata", {}) if contract.get("metadata", {}) is Dictionary else {}
	var interval := maxf(float(metadata.get("pay_interval_seconds", DEFAULT_PAY_INTERVAL_SECONDS)), 0.01)
	var pay_per_interval := maxi(0, int(metadata.get("pay_per_interval", DEFAULT_PAY_PER_INTERVAL)))
	if pay_per_interval <= 0:
		return
	var accrued := float(metadata.get("accrued_interval_time", 0.0)) + delta
	var owed := int(contract.get("owed_currency", 0))
	while accrued >= interval:
		accrued -= interval
		owed += pay_per_interval
	metadata["accrued_interval_time"] = accrued
	bridge.call("upsert_job_contract", {"contract_id": str(contract.get("contract_id", "")), "actor_id": str(contract.get("actor_id", "")), "metadata": metadata, "owed_currency": owed})


func _rebuild_runtime_indexes() -> void:
	_resource_node_by_id.clear()
	_container_node_by_id.clear()
	_projection_controller = null
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("mining_resource"):
		if node != null and node.has_method("get_resource_id"):
			var resource_id := str(node.call("get_resource_id")).strip_edges()
			if not resource_id.is_empty():
				_resource_node_by_id[resource_id] = node
	for node in get_tree().get_nodes_in_group("world_container"):
		if node != null and node.has_method("get_container_id"):
			var container_id := str(node.call("get_container_id")).strip_edges()
			if not container_id.is_empty():
				_container_node_by_id[container_id] = node
	_projection_controller = _find_projection_controller()


func _resource_node_for_id(resource_id: String) -> Node:
	var normalized_id := resource_id.strip_edges()
	if normalized_id.is_empty() or not is_inside_tree():
		return null
	var cached = _resource_node_by_id.get(normalized_id)
	if cached is Node and is_instance_valid(cached):
		return cached
	_resource_node_by_id.erase(normalized_id)
	return null


func _container_node_for_id(container_id: String) -> Node:
	var normalized_id := container_id.strip_edges()
	if normalized_id.is_empty() or not is_inside_tree():
		return null
	var cached = _container_node_by_id.get(normalized_id)
	if cached is Node and is_instance_valid(cached):
		return cached
	_container_node_by_id.erase(normalized_id)
	return null


func _current_actor_position(actor_id: String, record: Dictionary) -> Vector3:
	var projection := _projection_for_actor(actor_id)
	if projection is Node3D:
		return (projection as Node3D).global_position
	var position = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return position if position is Vector3 else Vector3.ZERO


func _projection_for_actor(actor_id: String) -> Node:
	if not is_inside_tree() or actor_id.strip_edges().is_empty():
		return null
	var projection_controller := _projection_controller
	if projection_controller == null or not is_instance_valid(projection_controller):
		_projection_controller = null
		return null
	if projection_controller != null and projection_controller.has_method("get_projection_for_actor"):
		var projection = projection_controller.call("get_projection_for_actor", actor_id)
		return projection as Node if projection is Node else null
	return null


func _find_projection_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldActorProjectionController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_actor_projection_controller") if is_inside_tree() else null


func _population_record_full(bridge: Node, actor_id: String) -> Dictionary:
	if bridge == null or actor_id.strip_edges().is_empty() or not bridge.has_method("get_population_record"):
		return {}
	var record = bridge.call("get_population_record", actor_id)
	return record if record is Dictionary else {}


func _upsert_population_record(bridge: Node, record: Dictionary) -> void:
	if bridge != null and bridge.has_method("upsert_population_record_core") and not record.is_empty():
		bridge.call("upsert_population_record_core", record)


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	var existing := get_tree().get_first_node_in_group("gecs_world_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	return null
