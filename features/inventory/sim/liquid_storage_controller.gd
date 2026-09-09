extends Node

class_name LiquidStorageController

signal liquid_stock_changed(settlement_id: String, facility_id: String, liquid_id: String)
signal liquid_container_removed(liquid_container_id: String, previous_state: Dictionary)
signal liquid_container_changed(liquid_container_id: String, previous_state: Dictionary, saved_state: Dictionary)

const SERVICE_ID := &"liquid_storage"

var _gecs: Node
var _states_by_id: Dictionary = {}
var _ids_by_scope: Dictionary = {}
var _available_ids_by_scope: Dictionary = {}
var _ids_by_settlement_liquid: Dictionary = {}
var _totals_by_settlement_liquid: Dictionary = {}
var _live_projection_by_id: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_gecs = context.require(&"gecs_world")
	_rebuild_indexes()
	if _gecs.has_signal("world_reindexed") and not _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.connect(_on_world_reindexed)


func teardown() -> void:
	if _gecs != null and is_instance_valid(_gecs) and _gecs.has_signal("world_reindexed") \
			and _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.disconnect(_on_world_reindexed)
	_states_by_id.clear()
	_ids_by_scope.clear()
	_available_ids_by_scope.clear()
	_ids_by_settlement_liquid.clear()
	_totals_by_settlement_liquid.clear()
	_live_projection_by_id.clear()
	_gecs = null


func ensure_container(seed: Dictionary) -> Dictionary:
	var container_id := str(seed.get("liquid_container_id", "")).strip_edges()
	if container_id.is_empty():
		return {}
	var existing := get_container_state(container_id)
	if not existing.is_empty():
		return existing
	return _save_state(_normalized_state(seed))


func bind_liquid_container(container: Node) -> bool:
	if container == null or not is_instance_valid(container):
		return false
	var container_id := str(container.get("liquid_container_id")).strip_edges()
	if container_id.is_empty():
		return false
	var authored_state := {
		"public_water_access": container.get("public_water_access") == true,
		"liquid_container_id": container_id,
		"settlement_id": str(container.get("settlement_id")),
		"facility_id": str(container.get("facility_id")),
		"owner_faction_name": str(container.get("owner_faction_name")),
		"world_position": container.global_position if container is Node3D else Vector3.ZERO,
		"assigned_liquid_id": str(container.get("assigned_liquid_id")),
		"capacity_liters": float(container.get("capacity_liters")),
		"current_liters": float(container.get("current_liters")),
		"reserved_incoming_liters": float(container.get("reserved_incoming_liters")),
		"reserved_outgoing_liters": float(container.get("reserved_outgoing_liters")),
	}
	if container.has_method("get_authored_liquid_state"):
		var baseline := container.call("get_authored_liquid_state") as Dictionary
		if not baseline.is_empty():
			for key in ["assigned_liquid_id", "current_liters", "reserved_incoming_liters", "reserved_outgoing_liters"]:
				authored_state[key] = baseline.get(key, authored_state[key])
	var state := get_container_state(container_id)
	if state.is_empty():
		state = ensure_container(authored_state)
	else:
		# Identity and physical capacity belong to the current projection/facility.
		if not state.has("public_water_access"):
			state["public_water_access"] = authored_state["public_water_access"]
		# Contents, liquid assignment, and reservations remain durable simulation state.
		for key in ["settlement_id", "facility_id", "owner_faction_name", "world_position", "capacity_liters"]:
			state[key] = authored_state[key]
		state = _save_state(state)
	if state.is_empty():
		return false
	_live_projection_by_id[container_id] = weakref(container)
	if container.has_method("apply_liquid_state"):
		container.call("apply_liquid_state", state)
	return true


func detach_liquid_container(container_id: String, container: Node) -> void:
	var projection_ref := _live_projection_by_id.get(container_id) as WeakRef
	if projection_ref != null and projection_ref.get_ref() == container:
		_live_projection_by_id.erase(container_id)


func get_container_state(container_id: String) -> Dictionary:
	return (_states_by_id.get(container_id, {}) as Dictionary).duplicate(true)


func get_live_container_candidates(settlement_id: String, liquid_id: String) -> Array[Node]:
	var result: Array[Node] = []
	for container_id_value in (_ids_by_settlement_liquid.get(_settlement_liquid_key(settlement_id, liquid_id), []) as Array):
		var container_id := str(container_id_value)
		var projection_ref := _live_projection_by_id.get(container_id) as WeakRef
		var projection: Node = projection_ref.get_ref() as Node if projection_ref != null else null
		if projection == null or not is_instance_valid(projection):
			_live_projection_by_id.erase(container_id)
			continue
		result.append(projection)
	return result


func get_settlement_liquid_totals(settlement_id: String, liquid_id: String) -> Dictionary:
	var key := _settlement_liquid_key(settlement_id, liquid_id)
	return (_totals_by_settlement_liquid.get(key, {"stored_liters": 0.0, "capacity_liters": 0.0}) as Dictionary).duplicate(true)


func get_settlement_liquid_container_states(settlement_id: String, liquid_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for container_id_value in (_ids_by_settlement_liquid.get(_settlement_liquid_key(settlement_id, liquid_id), []) as Array):
		var state := get_container_state(str(container_id_value))
		if not state.is_empty():
			result.append(state)
	return result


func get_settlement_liquid_snapshot(settlement_id: String) -> Dictionary:
	var liquids: Dictionary = {}
	var prefix := "%s\n" % settlement_id
	for key_value in _totals_by_settlement_liquid.keys():
		var key := str(key_value)
		if key.begins_with(prefix):
			liquids[key.trim_prefix(prefix)] = (_totals_by_settlement_liquid[key] as Dictionary).duplicate(true)
	return {"settlement_id": settlement_id, "liquids": liquids}


func reassign_settlement_owner(settlement_id: String, owner_faction_name: String) -> int:
	var normalized_settlement := settlement_id.strip_edges()
	var normalized_owner := owner_faction_name.strip_edges()
	if normalized_settlement.is_empty():
		return 0
	var changed := 0
	for state_value in _states_by_id.values().duplicate(true):
		var state := state_value as Dictionary
		if str(state.get("settlement_id", "")) != normalized_settlement \
				or str(state.get("owner_faction_name", "")) == normalized_owner:
			continue
		state["owner_faction_name"] = normalized_owner
		if not _save_state(state).is_empty():
			changed += 1
	return changed


func assign_liquid(container_id: String, liquid_id: String, authorization: Dictionary = {}) -> bool:
	var state := get_container_state(container_id)
	if state.is_empty() or not _container_authorized(container_id, state, authorization):
		return false
	var normalized := liquid_id.strip_edges().to_lower()
	if float(state.get("current_liters", 0.0)) > 0.001 \
			or float(state.get("reserved_incoming_liters", 0.0)) > 0.001 \
			or float(state.get("reserved_outgoing_liters", 0.0)) > 0.001:
		return str(state.get("assigned_liquid_id", "")) == normalized
	if str(state.get("assigned_liquid_id", "")) == normalized:
		return true
	state["assigned_liquid_id"] = normalized
	return not _save_state(state).is_empty()


func deposit(container_id: String, liquid_id: String, offered_liters: float, authorization: Dictionary = {}) -> float:
	var state := get_container_state(container_id)
	var normalized := liquid_id.strip_edges().to_lower()
	if state.is_empty() or not _container_authorized(container_id, state, authorization) \
			or normalized.is_empty() or str(state.get("assigned_liquid_id", "")) != normalized:
		return 0.0
	var available_capacity := maxf(0.0, float(state.get("capacity_liters", 0.0)) \
			- float(state.get("current_liters", 0.0)) - float(state.get("reserved_incoming_liters", 0.0)))
	var deposited := minf(maxf(0.0, offered_liters), available_capacity)
	if deposited <= 0.0:
		return 0.0
	state["current_liters"] = float(state.get("current_liters", 0.0)) + deposited
	return deposited if not _save_state(state).is_empty() else 0.0


func deposit_staged(container_id: String, liquid_id: String, offered_liters: float, authorization: Dictionary = {}) -> Dictionary:
	var state := get_container_state(container_id)
	var normalized := liquid_id.strip_edges().to_lower()
	if state.is_empty() or not _container_authorized(container_id, state, authorization) \
			or normalized.is_empty() or str(state.get("assigned_liquid_id", "")) != normalized:
		return {}
	var free := maxf(0.0, float(state.get("capacity_liters", 0.0)) \
			- float(state.get("current_liters", 0.0)) - float(state.get("reserved_incoming_liters", 0.0)))
	var deposited := minf(maxf(0.0, offered_liters), free)
	if deposited <= 0.0:
		return {}
	var previous := state.duplicate(true)
	state["current_liters"] = float(state.get("current_liters", 0.0)) + deposited
	if _save_state(state, false).is_empty():
		return {}
	return {
		"liquid_container_id": container_id,
		"liquid_id": normalized,
		"owner_faction_name": str(state.get("owner_faction_name", "")),
		"liters": deposited,
		"previous_state": previous,
	}


func rollback_staged_deposit(transaction: Dictionary) -> bool:
	var previous := transaction.get("previous_state", {}) as Dictionary
	return not previous.is_empty() and not _save_state(previous, false).is_empty()


func rollback_staged_draw(transaction: Dictionary) -> bool:
	var previous := transaction.get("previous_state", {}) as Dictionary
	return not previous.is_empty() and not _save_state(previous, false).is_empty()


func reserve_incoming(container_id: String, liquid_id: String, requested_liters: float, authorization: Dictionary = {}) -> float:
	var state := get_container_state(container_id)
	var normalized := liquid_id.strip_edges().to_lower()
	if state.is_empty() or not _container_authorized(container_id, state, authorization) \
			or normalized.is_empty() or str(state.get("assigned_liquid_id", "")) != normalized:
		return 0.0
	var free := maxf(0.0, float(state.get("capacity_liters", 0.0)) \
			- float(state.get("current_liters", 0.0)) - float(state.get("reserved_incoming_liters", 0.0)))
	var reserved := minf(maxf(0.0, requested_liters), free)
	if reserved <= 0.0:
		return 0.0
	state["reserved_incoming_liters"] = float(state.get("reserved_incoming_liters", 0.0)) + reserved
	return reserved if not _save_state(state).is_empty() else 0.0


func release_incoming(container_id: String, liquid_id: String, liters: float, authorization: Dictionary = {}) -> float:
	var state := get_container_state(container_id)
	if state.is_empty() or not _container_authorized(container_id, state, authorization) \
			or str(state.get("assigned_liquid_id", "")) != liquid_id.strip_edges().to_lower():
		return 0.0
	var released := minf(maxf(0.0, liters), float(state.get("reserved_incoming_liters", 0.0)))
	if released <= 0.0:
		return 0.0
	state["reserved_incoming_liters"] = float(state.get("reserved_incoming_liters", 0.0)) - released
	return released if not _save_state(state).is_empty() else 0.0


## Cancellation frees capacity but cannot create or remove stock, so it must
## survive ownership changes and projection loss.
func release_incoming_system(container_id: String, liquid_id: String, liters: float) -> float:
	var state := get_container_state(container_id)
	if state.is_empty() or str(state.get("assigned_liquid_id", "")) != liquid_id.strip_edges().to_lower():
		return 0.0
	var released := minf(maxf(0.0, liters), float(state.get("reserved_incoming_liters", 0.0)))
	if released <= 0.0:
		return 0.0
	state["reserved_incoming_liters"] = float(state.get("reserved_incoming_liters", 0.0)) - released
	return released if not _save_state(state).is_empty() else 0.0


func deposit_reserved(container_id: String, liquid_id: String, offered_liters: float, authorization: Dictionary = {}) -> float:
	var state := get_container_state(container_id)
	var normalized := liquid_id.strip_edges().to_lower()
	if state.is_empty() or not _container_authorized(container_id, state, authorization) \
			or normalized.is_empty() or str(state.get("assigned_liquid_id", "")) != normalized:
		return 0.0
	var deposited := minf(maxf(0.0, offered_liters), minf(
			float(state.get("reserved_incoming_liters", 0.0)),
			maxf(0.0, float(state.get("capacity_liters", 0.0)) - float(state.get("current_liters", 0.0)))
	))
	if deposited <= 0.0:
		return 0.0
	state["reserved_incoming_liters"] = float(state.get("reserved_incoming_liters", 0.0)) - deposited
	state["current_liters"] = float(state.get("current_liters", 0.0)) + deposited
	return deposited if not _save_state(state).is_empty() else 0.0


func draw(container_id: String, liquid_id: String, requested_liters: float, authorization: Dictionary = {}, publish_changes := true) -> float:
	var state := get_container_state(container_id)
	var normalized := liquid_id.strip_edges().to_lower()
	if state.is_empty() or not _container_authorized(container_id, state, authorization) \
			or normalized.is_empty() or str(state.get("assigned_liquid_id", "")) != normalized:
		return 0.0
	var available := maxf(0.0, float(state.get("current_liters", 0.0)) - float(state.get("reserved_outgoing_liters", 0.0)))
	var drawn := minf(maxf(0.0, requested_liters), available)
	if drawn <= 0.0:
		return 0.0
	state["current_liters"] = float(state.get("current_liters", 0.0)) - drawn
	return drawn if not _save_state(state, publish_changes).is_empty() else 0.0


func reserve_outgoing(container_id: String, liquid_id: String, requested_liters: float, authorization: Dictionary = {}) -> float:
	var state := get_container_state(container_id)
	var normalized := liquid_id.strip_edges().to_lower()
	if state.is_empty() or not _container_authorized(container_id, state, authorization) \
			or normalized.is_empty() or str(state.get("assigned_liquid_id", "")) != normalized:
		return 0.0
	var available := maxf(0.0, float(state.get("current_liters", 0.0)) - float(state.get("reserved_outgoing_liters", 0.0)))
	var reserved := minf(maxf(0.0, requested_liters), available)
	if reserved <= 0.0:
		return 0.0
	state["reserved_outgoing_liters"] = float(state.get("reserved_outgoing_liters", 0.0)) + reserved
	return reserved if not _save_state(state).is_empty() else 0.0


func release_outgoing(container_id: String, liquid_id: String, liters: float, authorization: Dictionary = {}) -> float:
	var state := get_container_state(container_id)
	if state.is_empty() or not _container_authorized(container_id, state, authorization) \
			or str(state.get("assigned_liquid_id", "")) != liquid_id.strip_edges().to_lower():
		return 0.0
	var released := minf(maxf(0.0, liters), float(state.get("reserved_outgoing_liters", 0.0)))
	if released <= 0.0:
		return 0.0
	state["reserved_outgoing_liters"] = float(state.get("reserved_outgoing_liters", 0.0)) - released
	return released if not _save_state(state).is_empty() else 0.0


func draw_reserved(container_id: String, liquid_id: String, requested_liters: float, authorization: Dictionary = {}) -> float:
	var state := get_container_state(container_id)
	var normalized := liquid_id.strip_edges().to_lower()
	if state.is_empty() or not _container_authorized(container_id, state, authorization) \
			or normalized.is_empty() or str(state.get("assigned_liquid_id", "")) != normalized:
		return 0.0
	var drawn := minf(maxf(0.0, requested_liters), minf(
			float(state.get("reserved_outgoing_liters", 0.0)),
			float(state.get("current_liters", 0.0))
	))
	if drawn <= 0.0:
		return 0.0
	state["reserved_outgoing_liters"] = float(state.get("reserved_outgoing_liters", 0.0)) - drawn
	state["current_liters"] = float(state.get("current_liters", 0.0)) - drawn
	return drawn if not _save_state(state).is_empty() else 0.0


func draw_from_settlement(
		settlement_id: String,
		owner_faction_name: String,
		liquid_id: String,
		requested_liters: float,
		authorization: Dictionary = {}
) -> Dictionary:
	return _draw_from_settlement(settlement_id, owner_faction_name, liquid_id, requested_liters, authorization, true)


## Off-screen farm commits stage every physical storage mutation silently, then
## publish only after the matching crop cells are durable.
func draw_from_settlement_staged(
		settlement_id: String,
		owner_faction_name: String,
		liquid_id: String,
		requested_liters: float,
		authorization: Dictionary = {}
) -> Dictionary:
	return _draw_from_settlement(settlement_id, owner_faction_name, liquid_id, requested_liters, authorization, false)


func _draw_from_settlement(
		settlement_id: String,
		owner_faction_name: String,
		liquid_id: String,
		requested_liters: float,
		authorization: Dictionary,
		publish_changes: bool
) -> Dictionary:
	var remaining := maxf(0.0, requested_liters)
	var transactions: Array[Dictionary] = []
	if settlement_id.is_empty() or owner_faction_name.is_empty() or liquid_id.is_empty() or remaining <= 0.0:
		return {}
	var scope := _scope_key(settlement_id, owner_faction_name, liquid_id)
	var cursor := 0
	while remaining > 0.001:
		var available_ids := _available_ids_by_scope.get(scope, []) as Array
		if cursor >= available_ids.size():
			break
		var container_id := str(available_ids[cursor])
		var state := get_container_state(container_id)
		var scoped_authorization := _authorization_for_container(authorization, container_id)
		if state.is_empty() or not _container_authorized(container_id, state, scoped_authorization) \
				or str(state.get("assigned_liquid_id", "")) != liquid_id.strip_edges().to_lower():
			cursor += 1
			continue
		var previous := state.duplicate(true)
		var available := maxf(0.0, float(state.get("current_liters", 0.0)) - float(state.get("reserved_outgoing_liters", 0.0)))
		var drawn := minf(remaining, available)
		if drawn > 0.0:
			state["current_liters"] = float(state.get("current_liters", 0.0)) - drawn
			if _save_state(state, publish_changes).is_empty():
				drawn = 0.0
		if drawn <= 0.0:
			cursor += 1
			continue
		transactions.append({
			"liquid_container_id": container_id,
			"liquid_id": liquid_id,
			"owner_faction_name": owner_faction_name,
			"liters": drawn,
			"previous_state": previous,
		})
		remaining -= drawn
		# Empty containers remove themselves from the available index. Keep the
		# cursor in place so the next available container is consumed directly.
	var total_drawn := requested_liters - remaining
	return {"drawn": total_drawn, "transactions": transactions} if total_drawn > 0.0 else {}


func restore_transactions(transactions: Array, liters: float, authorization: Dictionary = {}) -> float:
	return _restore_transactions(transactions, liters, authorization, true)


func restore_transactions_staged(transactions: Array, liters: float, authorization: Dictionary = {}) -> float:
	return _restore_transactions(transactions, liters, authorization, false)


func _restore_transactions(transactions: Array, liters: float, authorization: Dictionary, publish_changes: bool) -> float:
	var remaining := maxf(0.0, liters)
	for index in range(transactions.size() - 1, -1, -1):
		if remaining <= 0.001:
			break
		var transaction := transactions[index] as Dictionary
		var restoring := minf(remaining, maxf(0.0, float(transaction.get("liters", 0.0))))
		var container_id := str(transaction.get("liquid_container_id", ""))
		var state := get_container_state(container_id)
		var liquid_id := str(transaction.get("liquid_id", "")).strip_edges().to_lower()
		var scoped_authorization := _authorization_for_container(authorization, container_id)
		if state.is_empty() or not _container_authorized(container_id, state, scoped_authorization) \
				or str(state.get("assigned_liquid_id", "")) != liquid_id:
			continue
		var restored := minf(restoring, maxf(0.0, float(state.get("capacity_liters", 0.0)) - float(state.get("current_liters", 0.0))))
		if restored > 0.0:
			state["current_liters"] = float(state.get("current_liters", 0.0)) + restored
			if _save_state(state, publish_changes).is_empty():
				restored = 0.0
		remaining -= restored
	return liters - remaining


func publish_staged_transactions(transactions: Array) -> void:
	var previous_by_id: Dictionary = {}
	for transaction_value in transactions:
		var transaction := transaction_value as Dictionary
		var container_id := str(transaction.get("liquid_container_id", ""))
		if container_id.is_empty() or previous_by_id.has(container_id):
			continue
		previous_by_id[container_id] = (transaction.get("previous_state", {}) as Dictionary).duplicate(true)
	for container_id_value in previous_by_id.keys():
		var container_id := str(container_id_value)
		var previous := previous_by_id[container_id_value] as Dictionary
		var current := get_container_state(container_id)
		if previous != current:
			var projection_ref := _live_projection_by_id.get(container_id) as WeakRef
			var projection: Node = projection_ref.get_ref() as Node if projection_ref != null else null
			if is_instance_valid(projection) and projection.has_method("apply_liquid_state"):
				projection.call("apply_liquid_state", current)
			_emit_state_change(container_id, previous, current)


func _authorization_for_container(authorization: Dictionary, container_id: String) -> Dictionary:
	var scoped := authorization.duplicate(true)
	scoped["liquid_container_id"] = container_id
	return scoped


func _container_authorized(container_id: String, state: Dictionary, authorization: Dictionary) -> bool:
	var owner := str(state.get("owner_faction_name", "")).strip_edges()
	if owner.is_empty() or str(authorization.get("liquid_container_id", "")) != container_id \
			or str(authorization.get("owner_faction_name", "")) != owner:
		return false
	var actor_faction := str(authorization.get("actor_faction_name", "")).strip_edges()
	if bool(authorization.get("public_access_approved", false)):
		return bool(state.get("public_water_access", false)) and not actor_faction.is_empty()
	return actor_faction == owner \
			or bool(authorization.get("owner_access_approved", false)) \
			or bool(authorization.get("theft_approved", false))


func clear_all_reservations() -> void:
	for state_value in _states_by_id.values().duplicate(true):
		var state := state_value as Dictionary
		if float(state.get("reserved_incoming_liters", 0.0)) <= 0.001 \
				and float(state.get("reserved_outgoing_liters", 0.0)) <= 0.001:
			continue
		state["reserved_incoming_liters"] = 0.0
		state["reserved_outgoing_liters"] = 0.0
		_save_state(state)


func remove_container(container_id: String) -> bool:
	var previous := get_container_state(container_id)
	if previous.is_empty() or _gecs == null or not _gecs.has_method("remove_liquid_container_state"):
		return false
	_gecs.call("remove_liquid_container_state", container_id)
	_reindex_state(previous, {})
	_states_by_id.erase(container_id)
	_live_projection_by_id.erase(container_id)
	liquid_container_changed.emit(container_id, previous, {})
	liquid_container_removed.emit(container_id, previous)
	liquid_stock_changed.emit(str(previous.get("settlement_id", "")), str(previous.get("facility_id", "")), str(previous.get("assigned_liquid_id", "")))
	return true


func _save_state(state: Dictionary, publish_changes := true) -> Dictionary:
	if _gecs == null or not _gecs.has_method("upsert_liquid_container_state"):
		return {}
	var normalized := _normalized_state(state)
	var container_id := str(normalized.get("liquid_container_id", ""))
	if container_id.is_empty():
		return {}
	var previous := get_container_state(container_id)
	var saved := _gecs.call("upsert_liquid_container_state", normalized) as Dictionary
	if saved.is_empty():
		return {}
	if _same_index_identity(previous, saved):
		_adjust_totals(previous, -1.0)
		_adjust_totals(saved, 1.0)
		_sync_available_membership(previous, saved)
	else:
		_reindex_state(previous, saved)
	_states_by_id[container_id] = saved.duplicate(true)
	var projection_ref := _live_projection_by_id.get(container_id) as WeakRef
	var projection: Node = projection_ref.get_ref() as Node if projection_ref != null else null
	if publish_changes and projection != null and is_instance_valid(projection) and projection.has_method("apply_liquid_state"):
		projection.call("apply_liquid_state", saved)
	if publish_changes:
		_emit_state_change(container_id, previous, saved)
	return saved.duplicate(true)


func _emit_state_change(container_id: String, previous: Dictionary, saved: Dictionary) -> void:
	liquid_container_changed.emit(container_id, previous, saved)
	if not previous.is_empty() and (str(previous.get("settlement_id", "")) != str(saved.get("settlement_id", "")) \
			or str(previous.get("facility_id", "")) != str(saved.get("facility_id", "")) \
			or str(previous.get("assigned_liquid_id", "")) != str(saved.get("assigned_liquid_id", ""))):
		liquid_stock_changed.emit(str(previous.get("settlement_id", "")), str(previous.get("facility_id", "")), str(previous.get("assigned_liquid_id", "")))
	liquid_stock_changed.emit(str(saved.get("settlement_id", "")), str(saved.get("facility_id", "")), str(saved.get("assigned_liquid_id", "")))


func _normalized_state(state: Dictionary) -> Dictionary:
	var capacity := maxf(0.0, float(state.get("capacity_liters", 0.0)))
	var current := clampf(float(state.get("current_liters", 0.0)), 0.0, capacity)
	return {
		"public_water_access": bool(state.get("public_water_access", false)),
		"liquid_container_id": str(state.get("liquid_container_id", "")).strip_edges(),
		"settlement_id": str(state.get("settlement_id", "")).strip_edges(),
		"facility_id": str(state.get("facility_id", "")).strip_edges(),
		"owner_faction_name": str(state.get("owner_faction_name", "")).strip_edges(),
		"world_position": state.get("world_position", Vector3.ZERO),
		"assigned_liquid_id": str(state.get("assigned_liquid_id", "")).strip_edges().to_lower(),
		"capacity_liters": capacity,
		"current_liters": current,
		"reserved_incoming_liters": clampf(float(state.get("reserved_incoming_liters", 0.0)), 0.0, maxf(0.0, capacity - current)),
		"reserved_outgoing_liters": clampf(float(state.get("reserved_outgoing_liters", 0.0)), 0.0, current),
	}


func _rebuild_indexes() -> void:
	_states_by_id.clear()
	_ids_by_scope.clear()
	_available_ids_by_scope.clear()
	_ids_by_settlement_liquid.clear()
	_totals_by_settlement_liquid.clear()
	if _gecs == null or not _gecs.has_method("get_liquid_container_states"):
		return
	for state_value in (_gecs.call("get_liquid_container_states") as Dictionary).values():
		var state := state_value as Dictionary
		var container_id := str(state.get("liquid_container_id", ""))
		if container_id.is_empty():
			continue
		_states_by_id[container_id] = state.duplicate(true)
		_reindex_state({}, state)


func _reindex_state(previous: Dictionary, saved: Dictionary) -> void:
	if not previous.is_empty():
		_remove_from_indexes(previous)
	if saved.is_empty():
		return
	var settlement_id := str(saved.get("settlement_id", ""))
	var owner := str(saved.get("owner_faction_name", ""))
	var liquid_id := str(saved.get("assigned_liquid_id", ""))
	var container_id := str(saved.get("liquid_container_id", ""))
	if settlement_id.is_empty() or owner.is_empty() or liquid_id.is_empty() or container_id.is_empty():
		return
	var scope := _scope_key(settlement_id, owner, liquid_id)
	var ids := _ids_by_scope.get(scope, []) as Array
	if not ids.has(container_id):
		ids.append(container_id)
		ids.sort()
	_ids_by_scope[scope] = ids
	_add_available_id(saved)
	var settlement_liquid_key := _settlement_liquid_key(settlement_id, liquid_id)
	var settlement_ids := _ids_by_settlement_liquid.get(settlement_liquid_key, []) as Array
	if not settlement_ids.has(container_id):
		settlement_ids.append(container_id)
		settlement_ids.sort()
	_ids_by_settlement_liquid[settlement_liquid_key] = settlement_ids
	_adjust_totals(saved, 1.0)


func _same_index_identity(previous: Dictionary, saved: Dictionary) -> bool:
	if previous.is_empty() or saved.is_empty():
		return false
	for key in ["liquid_container_id", "settlement_id", "owner_faction_name", "assigned_liquid_id"]:
		if str(previous.get(key, "")) != str(saved.get(key, "")):
			return false
	return true


func _remove_from_indexes(state: Dictionary) -> void:
	var settlement_id := str(state.get("settlement_id", ""))
	var owner := str(state.get("owner_faction_name", ""))
	var liquid_id := str(state.get("assigned_liquid_id", ""))
	var container_id := str(state.get("liquid_container_id", ""))
	if settlement_id.is_empty() or owner.is_empty() or liquid_id.is_empty() or container_id.is_empty():
		return
	var scope := _scope_key(settlement_id, owner, liquid_id)
	var ids := _ids_by_scope.get(scope, []) as Array
	ids.erase(container_id)
	if ids.is_empty():
		_ids_by_scope.erase(scope)
	else:
		_ids_by_scope[scope] = ids
	_remove_available_id(scope, container_id)
	var settlement_liquid_key := _settlement_liquid_key(settlement_id, liquid_id)
	var settlement_ids := _ids_by_settlement_liquid.get(settlement_liquid_key, []) as Array
	settlement_ids.erase(container_id)
	if settlement_ids.is_empty():
		_ids_by_settlement_liquid.erase(settlement_liquid_key)
	else:
		_ids_by_settlement_liquid[settlement_liquid_key] = settlement_ids
	_adjust_totals(state, -1.0)


func _sync_available_membership(previous: Dictionary, saved: Dictionary) -> void:
	var previous_scope := _state_scope(previous)
	var saved_scope := _state_scope(saved)
	var container_id := str(saved.get("liquid_container_id", previous.get("liquid_container_id", "")))
	var was_available := _state_has_available_liquid(previous)
	var is_available := _state_has_available_liquid(saved)
	if previous_scope == saved_scope and was_available == is_available:
		return
	if was_available and not previous_scope.is_empty():
		_remove_available_id(previous_scope, container_id)
	if is_available:
		_add_available_id(saved)


func _add_available_id(state: Dictionary) -> void:
	if not _state_has_available_liquid(state):
		return
	var scope := _state_scope(state)
	var container_id := str(state.get("liquid_container_id", ""))
	if scope.is_empty() or container_id.is_empty():
		return
	var ids := _available_ids_by_scope.get(scope, []) as Array
	if not ids.has(container_id):
		ids.append(container_id)
		ids.sort()
	_available_ids_by_scope[scope] = ids


func _remove_available_id(scope: String, container_id: String) -> void:
	var ids := _available_ids_by_scope.get(scope, []) as Array
	ids.erase(container_id)
	if ids.is_empty():
		_available_ids_by_scope.erase(scope)
	else:
		_available_ids_by_scope[scope] = ids


func _state_scope(state: Dictionary) -> String:
	var settlement_id := str(state.get("settlement_id", ""))
	var owner := str(state.get("owner_faction_name", ""))
	var liquid_id := str(state.get("assigned_liquid_id", ""))
	if settlement_id.is_empty() or owner.is_empty() or liquid_id.is_empty():
		return ""
	return _scope_key(settlement_id, owner, liquid_id)


func _state_has_available_liquid(state: Dictionary) -> bool:
	return not state.is_empty() \
			and float(state.get("current_liters", 0.0)) - float(state.get("reserved_outgoing_liters", 0.0)) > 0.001


func _adjust_totals(state: Dictionary, direction: float) -> void:
	var settlement_id := str(state.get("settlement_id", ""))
	var liquid_id := str(state.get("assigned_liquid_id", ""))
	if settlement_id.is_empty() or liquid_id.is_empty():
		return
	var key := _settlement_liquid_key(settlement_id, liquid_id)
	var totals := (_totals_by_settlement_liquid.get(key, {"stored_liters": 0.0, "capacity_liters": 0.0}) as Dictionary).duplicate(true)
	totals["stored_liters"] = maxf(0.0, float(totals.get("stored_liters", 0.0)) + direction * float(state.get("current_liters", 0.0)))
	totals["capacity_liters"] = maxf(0.0, float(totals.get("capacity_liters", 0.0)) + direction * float(state.get("capacity_liters", 0.0)))
	if float(totals["stored_liters"]) <= 0.001 and float(totals["capacity_liters"]) <= 0.001:
		_totals_by_settlement_liquid.erase(key)
	else:
		_totals_by_settlement_liquid[key] = totals


func _scope_key(settlement_id: String, owner_faction_name: String, liquid_id: String) -> String:
	return "%s\n%s\n%s" % [settlement_id, owner_faction_name, liquid_id.strip_edges().to_lower()]


func _settlement_liquid_key(settlement_id: String, liquid_id: String) -> String:
	return "%s\n%s" % [settlement_id, liquid_id.strip_edges().to_lower()]


func _on_world_reindexed() -> void:
	var changed_scopes: Dictionary = {}
	for state_value in _states_by_id.values():
		var previous_state := state_value as Dictionary
		var previous_key := "%s\n%s\n%s" % [
			str(previous_state.get("settlement_id", "")),
			str(previous_state.get("facility_id", "")),
			str(previous_state.get("assigned_liquid_id", "")),
		]
		changed_scopes[previous_key] = previous_state
	_rebuild_indexes()
	for container_id_value in _live_projection_by_id.keys().duplicate():
		var container_id := str(container_id_value)
		var projection_ref := _live_projection_by_id.get(container_id) as WeakRef
		var projection: Node = projection_ref.get_ref() as Node if projection_ref != null else null
		if projection == null or not is_instance_valid(projection):
			_live_projection_by_id.erase(container_id)
			continue
		var state := get_container_state(container_id)
		if projection.has_method("cancel_refill_interactions"):
			projection.call("cancel_refill_interactions")
		if state.is_empty():
			var seed := {
				"public_water_access": projection.get("public_water_access") == true,
				"liquid_container_id": container_id,
				"settlement_id": str(projection.get("settlement_id")),
				"facility_id": str(projection.get("facility_id")),
				"owner_faction_name": str(projection.get("owner_faction_name")),
				"world_position": projection.global_position if projection is Node3D else Vector3.ZERO,
				"assigned_liquid_id": "",
				"capacity_liters": float(projection.get("capacity_liters")),
				"current_liters": 0.0,
				"reserved_incoming_liters": 0.0,
				"reserved_outgoing_liters": 0.0,
			}
			if projection.has_method("get_authored_liquid_state"):
				var baseline := projection.call("get_authored_liquid_state") as Dictionary
				if not baseline.is_empty():
					seed["assigned_liquid_id"] = baseline.get("assigned_liquid_id", "")
					seed["capacity_liters"] = baseline.get("capacity_liters", seed["capacity_liters"])
					seed["current_liters"] = baseline.get("current_liters", 0.0)
			state = ensure_container(seed)
			if not state.is_empty() and projection.has_method("apply_liquid_state"):
				projection.call("apply_liquid_state", state)
		elif projection.has_method("apply_liquid_state"):
			projection.call("apply_liquid_state", state)
	for state_value in _states_by_id.values():
		var current_state := state_value as Dictionary
		var current_key := "%s\n%s\n%s" % [
			str(current_state.get("settlement_id", "")),
			str(current_state.get("facility_id", "")),
			str(current_state.get("assigned_liquid_id", "")),
		]
		changed_scopes[current_key] = current_state
	for state_value in changed_scopes.values():
		var changed_state := state_value as Dictionary
		liquid_stock_changed.emit(
			str(changed_state.get("settlement_id", "")),
			str(changed_state.get("facility_id", "")),
			str(changed_state.get("assigned_liquid_id", ""))
		)
