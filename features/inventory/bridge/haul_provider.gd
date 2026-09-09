extends Node

class_name HaulProvider

signal work_offers_changed(settlement_id: String)
signal work_availability_changed(settlement_id: String)

const SERVICE_ID := &"haul"
const EPSILON := 0.001

var _context: BootstrapContext
var _job_system: Node
var _platforms: Array[Node] = []
var _platform_signal_callbacks: Dictionary = {}
var _platform_offers: Dictionary = {}
var _endpoints_by_id: Dictionary = {}
var _endpoint_exit_callbacks: Dictionary = {}
var _endpoint_meta: Dictionary = {}
var _endpoint_ids_by_settlement: Dictionary = {}
var _transfer_offers: Dictionary = {}
var _offer_cache_by_settlement: Dictionary = {}
var _dirty_offer_caches: Dictionary = {}
var _assignments: Dictionary = {}
var _offer_claims: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_context = context
	_job_system = context.get_optional(&"job_system") if context != null else null
	add_to_group("job_provider")
	if _job_system != null and _job_system.has_method("register_job_provider"):
		_job_system.call("register_job_provider", self)


func teardown() -> void:
	if _job_system != null and is_instance_valid(_job_system) and _job_system.has_method("unregister_job_provider"):
		_job_system.call("unregister_job_provider", self)
	for actor_key in _assignments.keys().duplicate():
		_erase_assignment(int(actor_key), true)
	for platform in _platforms.duplicate():
		unregister_platform(platform)
	for endpoint_id_value in _endpoints_by_id.keys().duplicate():
		_remove_endpoint(str(endpoint_id_value), false)
	_platform_offers.clear()
	_transfer_offers.clear()
	_offer_cache_by_settlement.clear()
	_dirty_offer_caches.clear()
	_offer_claims.clear()
	_job_system = null
	_context = null


func get_provider_name() -> String:
	return "Hauling"


func get_job_category_specs(_settlement_id := "") -> Array:
	return [{
		"entry_id": "category:haul",
		"category": "haul",
		"display_name": "Haul",
		"default_last": true,
	}]


func register_platform(platform: Node) -> void:
	if platform == null or not is_instance_valid(platform) or _platforms.has(platform):
		return
	_platforms.append(platform)
	if platform.has_method("bind_haul_provider"):
		platform.call("bind_haul_provider", self)
	var callback := Callable(self, "_on_platform_changed").bind(platform)
	_platform_signal_callbacks[platform.get_instance_id()] = callback
	if platform.has_signal("inventory_changed") and not platform.inventory_changed.is_connected(callback):
		platform.inventory_changed.connect(callback)
	_refresh_platform_offers(platform)


func unregister_platform(platform: Node) -> void:
	if platform == null:
		return
	var platform_key := platform.get_instance_id()
	var previous_settlements := _offer_settlements(_platform_offers.get(platform_key, []))
	_disconnect_platform(platform)
	if is_instance_valid(platform) and platform.has_method("unbind_haul_provider"):
		platform.call("unbind_haul_provider", self)
	_platforms.erase(platform)
	_platform_offers.erase(platform_key)
	for settlement_id in previous_settlements:
		_mark_offer_cache_dirty(settlement_id)
	for actor_key in _assignments.keys().duplicate():
		var assignment: Dictionary = _assignments.get(actor_key, {})
		if assignment.get("platform") == platform:
			_erase_assignment(int(actor_key), false)


func notify_platform_changed(platform: Node = null) -> void:
	if platform != null and is_instance_valid(platform) and _platforms.has(platform):
		_refresh_platform_offers(platform)


func register_endpoint(endpoint: Node) -> void:
	if not _valid_endpoint_contract(endpoint):
		return
	var endpoint_id := str(endpoint.call("get_haul_endpoint_id")).strip_edges()
	var existing := _endpoint_by_id(endpoint_id)
	if existing != null and existing != endpoint:
		_disconnect_endpoint(endpoint_id, existing)
		_unindex_endpoint(endpoint_id)
	_endpoints_by_id[endpoint_id] = weakref(endpoint)
	var callback := Callable(self, "_on_endpoint_tree_exiting").bind(endpoint, endpoint_id)
	_endpoint_exit_callbacks[endpoint_id] = callback
	if endpoint.has_signal("tree_exiting") and not endpoint.tree_exiting.is_connected(callback):
		endpoint.tree_exiting.connect(callback, CONNECT_ONE_SHOT)
	_index_endpoint(endpoint_id, endpoint)
	_refresh_endpoint_offers(endpoint_id, endpoint)


func unregister_endpoint(endpoint: Node) -> void:
	if endpoint == null or not is_instance_valid(endpoint) or not endpoint.has_method("get_haul_endpoint_id"):
		return
	var endpoint_id := str(endpoint.call("get_haul_endpoint_id")).strip_edges()
	if _endpoint_by_id(endpoint_id) == endpoint:
		_remove_endpoint(endpoint_id)


func notify_endpoint_changed(endpoint: Node) -> void:
	if not _valid_endpoint_contract(endpoint):
		return
	var endpoint_id := str(endpoint.call("get_haul_endpoint_id")).strip_edges()
	if _endpoint_by_id(endpoint_id) != endpoint:
		register_endpoint(endpoint)
		return
	var previous_meta: Dictionary = _endpoint_meta.get(endpoint_id, {})
	var previous_settlement := str(previous_meta.get("settlement_id", ""))
	var next_meta := _endpoint_metadata(endpoint)
	if previous_meta != next_meta:
		_unindex_endpoint(endpoint_id)
		_index_endpoint(endpoint_id, endpoint)
	_refresh_endpoint_offers(endpoint_id, endpoint)
	if not previous_settlement.is_empty() and previous_settlement != str(next_meta.get("settlement_id", "")):
		_mark_offer_cache_dirty(previous_settlement)
	var settlement_id := str(next_meta.get("settlement_id", ""))
	if not settlement_id.is_empty():
		work_availability_changed.emit(settlement_id)


## Live sources for systems that consume a hauled resource directly. This uses
## the same indexed endpoint registry as hauling rather than resource-specific
## groups or scene-tree scans.
func get_source_candidates(settlement_id: String, resource_id: String) -> Array[Node]:
	var result: Array[Node] = []
	if settlement_id.is_empty() or resource_id.is_empty():
		return result
	for endpoint_id_value in (_endpoint_ids_by_settlement.get(settlement_id, {}) as Dictionary).keys():
		var endpoint_id := str(endpoint_id_value)
		var meta: Dictionary = _endpoint_meta.get(endpoint_id, {})
		var endpoint := _endpoint_by_id(endpoint_id)
		if endpoint != null \
				and (meta.get("resource_ids", PackedStringArray()) as PackedStringArray).has(resource_id) \
				and _endpoint_available(endpoint, resource_id) > EPSILON:
			result.append(endpoint)
	return result


func get_available_work_offers(settlement_id := "") -> Array:
	if settlement_id.is_empty():
		var all_offers: Array = []
		all_offers.append_array(_offers_for_settlement(""))
		var settlement_ids := _known_settlement_ids()
		settlement_ids.sort()
		for settlement_value in settlement_ids:
			all_offers.append_array(_offers_for_settlement(str(settlement_value)))
		return _without_claimed_offers(all_offers)
	return _without_claimed_offers(_offers_for_settlement(settlement_id))


func can_actor_accept_work_offer(offer: Dictionary, actor: Node) -> bool:
	if actor == null or _assignments.has(actor.get_instance_id()):
		return false
	if offer.get("platform") != null:
		var platform := offer.get("platform") as Node
		return platform != null and is_instance_valid(platform) and platform.has_method("can_actor_accept_automatic_haul") \
				and bool(platform.call("can_actor_accept_automatic_haul", actor, str(offer.get("item_path", ""))))
	var offer_id := str(offer.get("offer_id", ""))
	if offer_id.is_empty() or _offer_claims.has(offer_id):
		return false
	var resource_id := str(offer.get("resource_id", ""))
	var destination := _endpoint_by_id(str(offer.get("destination_endpoint_id", "")))
	if resource_id.is_empty() or not _can_actor_use_destination(destination, resource_id, actor):
		return false
	var carried := _carried_amount(destination, resource_id, actor)
	if carried > EPSILON:
		return true
	var source := _nearest_source(destination, resource_id, actor)
	return source != null and _transfer_capacity(source, resource_id, actor) > EPSILON


func accept_work_offer(offer: Dictionary, actor: Node) -> Dictionary:
	if not can_actor_accept_work_offer(offer, actor):
		return {"accepted": false}
	if offer.get("platform") != null:
		return _accept_platform_offer(offer, actor)
	return _accept_transfer_offer(offer, actor)


func has_active_work_for_actor(actor: Node) -> bool:
	if actor == null:
		return false
	var assignment: Dictionary = _assignments.get(actor.get_instance_id(), {})
	if assignment.is_empty():
		return false
	var platform := assignment.get("platform") as Node
	if platform == null:
		return true
	if is_instance_valid(platform) and platform.has_method("has_pending_automatic_haul") \
			and bool(platform.call("has_pending_automatic_haul", actor)):
		return true
	_erase_assignment(actor.get_instance_id(), false)
	return false


func cancel_work_for_actor(actor: Node) -> bool:
	if actor == null or not _assignments.has(actor.get_instance_id()):
		return false
	var assignment: Dictionary = _assignments.get(actor.get_instance_id(), {})
	var platform := assignment.get("platform") as Node
	if platform != null and is_instance_valid(platform) and platform.has_method("cancel_pending_automatic_haul"):
		platform.call("cancel_pending_automatic_haul", actor)
	_erase_assignment(actor.get_instance_id(), false)
	return true


func prepare_actor_for_derealization(actor: Node) -> void:
	if actor != null and is_instance_valid(actor):
		_erase_assignment(actor.get_instance_id(), true)


func _accept_platform_offer(offer: Dictionary, actor: Node) -> Dictionary:
	var platform := offer.get("platform") as Node
	if platform == null or not bool(platform.call("begin_automatic_haul", actor, str(offer.get("item_path", "")))):
		return {"accepted": false}
	var actor_key := actor.get_instance_id()
	var callbacks := _connect_actor(actor, actor_key, "_on_platform_arrival")
	_assignments[actor_key] = {
		"platform": platform,
		"actor": weakref(actor),
		"arrival_callback": callbacks.get("arrival_callback", Callable()),
		"exit_callback": callbacks.get("exit_callback", Callable()),
	}
	return {"accepted": true}


func _accept_transfer_offer(offer: Dictionary, actor: Node) -> Dictionary:
	var resource_id := str(offer.get("resource_id", ""))
	var destination_id := str(offer.get("destination_endpoint_id", ""))
	var destination := _endpoint_by_id(destination_id)
	var carried := _carried_amount(destination, resource_id, actor)
	var source: Node
	var requested := minf(carried, _endpoint_free_capacity(destination, resource_id))
	if carried <= EPSILON:
		source = _nearest_source(destination, resource_id, actor)
		if source == null:
			return {"accepted": false}
		requested = minf(_transfer_capacity(source, resource_id, actor), minf(
				_endpoint_available(source, resource_id), _endpoint_free_capacity(destination, resource_id)))
	if requested <= EPSILON:
		return {"accepted": false}
	var destination_reserved := float(destination.call("reserve_haul_incoming", resource_id, requested, actor))
	var source_reserved := 0.0
	if carried <= EPSILON and destination_reserved > EPSILON:
		source_reserved = float(source.call("reserve_haul_outgoing", resource_id, destination_reserved, actor))
		if source_reserved + EPSILON < destination_reserved:
			destination.call("release_haul_incoming", resource_id, destination_reserved - source_reserved, actor)
			destination_reserved = source_reserved
	if destination_reserved <= EPSILON or (carried <= EPSILON and source_reserved <= EPSILON):
		if source_reserved > EPSILON:
			source.call("release_haul_outgoing", resource_id, source_reserved, actor)
		if destination_reserved > EPSILON:
			destination.call("release_haul_incoming", resource_id, destination_reserved, actor)
		return {"accepted": false}
	var actor_key := actor.get_instance_id()
	var callbacks := _connect_actor(actor, actor_key, "_on_transfer_arrival")
	var offer_id := str(offer.get("offer_id", ""))
	_assignments[actor_key] = {
		"actor": weakref(actor),
		"offer_id": offer_id,
		"resource_id": resource_id,
		"source_endpoint_id": str(source.call("get_haul_endpoint_id")) if source != null else "",
		"destination_endpoint_id": destination_id,
		"source_reserved": source_reserved,
		"destination_reserved": destination_reserved,
		"stage": "unload" if carried > EPSILON else "load",
		"arrival_callback": callbacks.get("arrival_callback", Callable()),
		"exit_callback": callbacks.get("exit_callback", Callable()),
	}
	_offer_claims[offer_id] = actor_key
	actor.call("assign_open_container", destination if carried > EPSILON else source, false)
	return {"accepted": true}


func _connect_actor(actor: Node, actor_key: int, arrival_method: String) -> Dictionary:
	var arrival_callback := Callable(self, arrival_method).bind(actor_key)
	var exit_callback := Callable(self, "_on_actor_tree_exiting").bind(actor_key)
	if actor.has_signal("container_reached") and not actor.container_reached.is_connected(arrival_callback):
		actor.container_reached.connect(arrival_callback)
	if actor.has_signal("tree_exiting") and not actor.tree_exiting.is_connected(exit_callback):
		actor.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)
	return {"arrival_callback": arrival_callback, "exit_callback": exit_callback}


func _on_platform_arrival(actor: Node, container: Node, actor_key: int) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var platform := assignment.get("platform") as Node
	if actor == null or container != platform or platform == null or not is_instance_valid(platform):
		return
	if platform.has_method("has_pending_automatic_haul") and bool(platform.call("has_pending_automatic_haul", actor)):
		platform.call("resolve_pending_deposit", actor)
	_erase_assignment(actor_key, false)


func _on_transfer_arrival(actor: Node, container: Node, actor_key: int) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	if assignment.is_empty() or actor == null or container == null:
		return
	var resource_id := str(assignment.get("resource_id", ""))
	var source := _endpoint_by_id(str(assignment.get("source_endpoint_id", "")))
	var destination := _endpoint_by_id(str(assignment.get("destination_endpoint_id", "")))
	if str(assignment.get("stage", "")) == "load":
		if container != source or source == null or destination == null:
			return
		var source_reserved := maxf(0.0, float(assignment.get("source_reserved", 0.0)))
		var destination_reserved := maxf(0.0, float(assignment.get("destination_reserved", 0.0)))
		assignment["source_reserved"] = 0.0
		_assignments[actor_key] = assignment
		var loaded := clampf(float(source.call("load_reserved_haul", resource_id, minf(source_reserved, destination_reserved), actor)), 0.0, minf(source_reserved, destination_reserved))
		if source_reserved > loaded + EPSILON:
			source.call("release_haul_outgoing", resource_id, source_reserved - loaded, actor)
		if destination_reserved > loaded + EPSILON:
			destination.call("release_haul_incoming", resource_id, destination_reserved - loaded, actor)
		if not _assignments.has(actor_key):
			return
		if loaded <= EPSILON:
			_erase_assignment(actor_key, true)
			return
		assignment = _assignments.get(actor_key, {})
		assignment["destination_reserved"] = loaded
		assignment["stage"] = "unload"
		_assignments[actor_key] = assignment
		actor.call("assign_open_container", destination, false)
		return
	if str(assignment.get("stage", "")) != "unload" or container != destination or destination == null:
		return
	var reserved := maxf(0.0, float(assignment.get("destination_reserved", 0.0)))
	assignment["destination_reserved"] = 0.0
	_assignments[actor_key] = assignment
	var unloaded := clampf(float(destination.call("unload_reserved_haul", resource_id, reserved, actor)), 0.0, reserved)
	if reserved > unloaded + EPSILON:
		destination.call("release_haul_incoming", resource_id, reserved - unloaded, actor)
	_erase_assignment(actor_key, false)


func _assignment_platform(actor: Node):
	if actor == null:
		return null
	var assignment: Dictionary = _assignments.get(actor.get_instance_id(), {})
	var platform: Node = assignment.get("platform") as Node
	return platform if platform != null and is_instance_valid(platform) else null


func _refresh_platform_offers(platform: Node) -> void:
	if platform == null or not is_instance_valid(platform) or not platform.is_inside_tree():
		return
	var platform_key := platform.get_instance_id()
	var previous_settlements := _offer_settlements(_platform_offers.get(platform_key, []))
	var offers: Array = platform.call("get_automatic_haul_offers", "") if platform.has_method("get_automatic_haul_offers") \
			else [platform.call("get_automatic_haul_offer", "")] if platform.has_method("get_automatic_haul_offer") else []
	for offer_value in offers:
		var offer := offer_value as Dictionary
		offer["provider"] = self
		offer["haul_kind"] = "platform_deposit"
	_platform_offers[platform_key] = offers
	var settlements := previous_settlements
	for settlement_id in _offer_settlements(offers):
		settlements[settlement_id] = true
	for settlement_id in settlements:
		_mark_offer_cache_dirty(settlement_id)


func _refresh_endpoint_offers(endpoint_id: String, endpoint: Node) -> void:
	_remove_transfer_offers_for_endpoint(endpoint_id)
	if endpoint == null or not is_instance_valid(endpoint):
		return
	var meta: Dictionary = _endpoint_meta.get(endpoint_id, {})
	var settlement_id := str(meta.get("settlement_id", ""))
	var owner := str(meta.get("owner_faction_name", ""))
	for resource_value in meta.get("resource_ids", PackedStringArray()):
		var resource_id := str(resource_value)
		if _endpoint_free_capacity(endpoint, resource_id) <= EPSILON:
			continue
		var offer_id := "haul:%s:%s" % [resource_id, endpoint_id]
		_transfer_offers[offer_id] = {
			"offer_id": offer_id,
			"category": "haul",
			"job_entry_id": "category:haul",
			"display_name": "Haul %s" % resource_id.capitalize(),
			"settlement_id": settlement_id,
			"owner_faction_id": owner,
			"faction_neutral": false,
			"world_position": endpoint.global_position if endpoint is Node3D else Vector3.ZERO,
			"urgency": _destination_urgency(endpoint, resource_id),
			"resource_id": resource_id,
			"destination_endpoint_id": endpoint_id,
			"provider": self,
		}
	_mark_offer_cache_dirty(settlement_id)


func _remove_transfer_offers_for_endpoint(endpoint_id: String) -> void:
	var affected_settlements: Dictionary = {}
	for offer_id_value in _transfer_offers.keys().duplicate():
		var offer: Dictionary = _transfer_offers[offer_id_value]
		if str(offer.get("destination_endpoint_id", "")) != endpoint_id:
			continue
		affected_settlements[str(offer.get("settlement_id", ""))] = true
		_transfer_offers.erase(offer_id_value)
	for settlement_id in affected_settlements:
		_mark_offer_cache_dirty(settlement_id)


func _offers_for_settlement(settlement_id: String) -> Array:
	if not _dirty_offer_caches.has(settlement_id) and _offer_cache_by_settlement.has(settlement_id):
		return _offer_cache_by_settlement[settlement_id]
	var offers: Array = []
	for offer_value in _transfer_offers.values():
		var offer := offer_value as Dictionary
		if str(offer.get("settlement_id", "")) == settlement_id:
			offers.append(offer)
	for platform_offers_value in _platform_offers.values():
		for offer_value in platform_offers_value as Array:
			var offer := offer_value as Dictionary
			if str(offer.get("settlement_id", "")) == settlement_id:
				offers.append(offer)
	offers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.get("offer_id", "")) < str(right.get("offer_id", "")))
	_offer_cache_by_settlement[settlement_id] = offers
	_dirty_offer_caches.erase(settlement_id)
	return offers


func _without_claimed_offers(offers: Array) -> Array:
	if _offer_claims.is_empty():
		return offers
	var available: Array = []
	for offer_value in offers:
		var offer := offer_value as Dictionary
		if not _offer_claims.has(str(offer.get("offer_id", ""))):
			available.append(offer)
	return available


func _nearest_source(destination: Node, resource_id: String, actor: Node) -> Node:
	if destination == null or not is_instance_valid(destination):
		return null
	var destination_id := str(destination.call("get_haul_endpoint_id"))
	var meta: Dictionary = _endpoint_meta.get(destination_id, {})
	var settlement_id := str(meta.get("settlement_id", ""))
	var owner := str(meta.get("owner_faction_name", ""))
	var best: Node
	var best_distance := INF
	for endpoint_id_value in (_endpoint_ids_by_settlement.get(settlement_id, {}) as Dictionary).keys():
		var endpoint_id := str(endpoint_id_value)
		if endpoint_id == destination_id:
			continue
		var source := _endpoint_by_id(endpoint_id)
		var source_meta: Dictionary = _endpoint_meta.get(endpoint_id, {})
		if source == null or str(source_meta.get("owner_faction_name", "")) != owner \
				or not (source_meta.get("resource_ids", PackedStringArray()) as PackedStringArray).has(resource_id) \
				or _endpoint_available(source, resource_id) <= EPSILON or not _actor_can_access_owner(actor, owner):
			continue
		var distance: float = destination.global_position.distance_squared_to(source.global_position) \
				if destination is Node3D and source is Node3D else 0.0
		if distance < best_distance:
			best = source
			best_distance = distance
	return best


func _can_actor_use_destination(destination: Node, resource_id: String, actor: Node) -> bool:
	if destination == null or not is_instance_valid(destination) or _endpoint_free_capacity(destination, resource_id) <= EPSILON:
		return false
	var endpoint_id := str(destination.call("get_haul_endpoint_id"))
	var owner := str((_endpoint_meta.get(endpoint_id, {}) as Dictionary).get("owner_faction_name", ""))
	return _actor_can_access_owner(actor, owner)


func _actor_can_access_owner(actor: Node, owner: String) -> bool:
	if actor == null or owner.is_empty():
		return false
	if actor.has_method("is_authorized_for_owner"):
		return bool(actor.call("is_authorized_for_owner", null, owner))
	return str(actor.get("faction_name")) == owner


func _endpoint_available(endpoint: Node, resource_id: String) -> float:
	return maxf(0.0, float(endpoint.call("get_haul_available", resource_id))) \
			if endpoint != null and endpoint.has_method("get_haul_available") else 0.0


func _endpoint_free_capacity(endpoint: Node, resource_id: String) -> float:
	return maxf(0.0, float(endpoint.call("get_haul_free_capacity", resource_id))) \
			if endpoint != null and endpoint.has_method("get_haul_free_capacity") else 0.0


func _transfer_capacity(endpoint: Node, resource_id: String, actor: Node) -> float:
	return maxf(0.0, float(endpoint.call("get_haul_transfer_capacity", resource_id, actor))) \
			if endpoint != null and endpoint.has_method("get_haul_transfer_capacity") else 0.0


func _carried_amount(endpoint: Node, resource_id: String, actor: Node) -> float:
	return maxf(0.0, float(endpoint.call("get_carried_haul_amount", resource_id, actor))) \
			if endpoint != null and endpoint.has_method("get_carried_haul_amount") else 0.0


func _destination_urgency(endpoint: Node, resource_id: String) -> float:
	if endpoint.has_method("get_haul_destination_urgency"):
		return clampf(float(endpoint.call("get_haul_destination_urgency", resource_id)), 0.0, 1.0)
	return 0.5


func _valid_endpoint_contract(endpoint: Node) -> bool:
	return endpoint != null and is_instance_valid(endpoint) \
			and endpoint.has_method("get_haul_endpoint_id") \
			and endpoint.has_method("get_haul_resource_ids") \
			and endpoint.has_method("get_haul_available") \
			and endpoint.has_method("get_haul_free_capacity") \
			and endpoint.has_method("reserve_haul_outgoing") \
			and endpoint.has_method("release_haul_outgoing") \
			and endpoint.has_method("reserve_haul_incoming") \
			and endpoint.has_method("release_haul_incoming") \
			and endpoint.has_method("load_reserved_haul") \
			and endpoint.has_method("unload_reserved_haul") \
			and not str(endpoint.call("get_haul_endpoint_id")).strip_edges().is_empty()


func _endpoint_metadata(endpoint: Node) -> Dictionary:
	return {
		"settlement_id": str(endpoint.get("settlement_id")).strip_edges(),
		"owner_faction_name": str(endpoint.get("owner_faction_name")).strip_edges(),
		"resource_ids": endpoint.call("get_haul_resource_ids") as PackedStringArray,
	}


func _index_endpoint(endpoint_id: String, endpoint: Node) -> void:
	var meta := _endpoint_metadata(endpoint)
	_endpoint_meta[endpoint_id] = meta
	var settlement_id := str(meta.get("settlement_id", ""))
	if settlement_id.is_empty():
		return
	var ids: Dictionary = _endpoint_ids_by_settlement.get(settlement_id, {})
	ids[endpoint_id] = true
	_endpoint_ids_by_settlement[settlement_id] = ids


func _unindex_endpoint(endpoint_id: String) -> void:
	var meta: Dictionary = _endpoint_meta.get(endpoint_id, {})
	var settlement_id := str(meta.get("settlement_id", ""))
	var ids: Dictionary = _endpoint_ids_by_settlement.get(settlement_id, {})
	ids.erase(endpoint_id)
	if ids.is_empty():
		_endpoint_ids_by_settlement.erase(settlement_id)
	else:
		_endpoint_ids_by_settlement[settlement_id] = ids
	_endpoint_meta.erase(endpoint_id)


func _endpoint_by_id(endpoint_id: String) -> Node:
	var endpoint_ref := _endpoints_by_id.get(endpoint_id) as WeakRef
	var endpoint := endpoint_ref.get_ref() as Node if endpoint_ref != null else null
	return endpoint if endpoint != null and is_instance_valid(endpoint) else null


func _on_endpoint_tree_exiting(endpoint: Node, endpoint_id: String) -> void:
	if _endpoint_by_id(endpoint_id) == endpoint:
		_remove_endpoint(endpoint_id)


func _remove_endpoint(endpoint_id: String, notify := true) -> void:
	var endpoint := _endpoint_by_id(endpoint_id)
	var settlement_id := str((_endpoint_meta.get(endpoint_id, {}) as Dictionary).get("settlement_id", ""))
	_disconnect_endpoint(endpoint_id, endpoint)
	_remove_transfer_offers_for_endpoint(endpoint_id)
	_unindex_endpoint(endpoint_id)
	_endpoints_by_id.erase(endpoint_id)
	for actor_key_value in _assignments.keys().duplicate():
		var assignment: Dictionary = _assignments.get(actor_key_value, {})
		if str(assignment.get("source_endpoint_id", "")) == endpoint_id \
				or str(assignment.get("destination_endpoint_id", "")) == endpoint_id:
			_erase_assignment(int(actor_key_value), true)
	_mark_offer_cache_dirty(settlement_id)
	if notify and not settlement_id.is_empty():
		work_availability_changed.emit(settlement_id)


func _disconnect_endpoint(endpoint_id: String, endpoint: Node) -> void:
	var callback: Callable = _endpoint_exit_callbacks.get(endpoint_id, Callable())
	if endpoint != null and is_instance_valid(endpoint) and endpoint.has_signal("tree_exiting") \
			and callback.is_valid() and endpoint.tree_exiting.is_connected(callback):
		endpoint.tree_exiting.disconnect(callback)
	_endpoint_exit_callbacks.erase(endpoint_id)


func _disconnect_platform(platform: Node) -> void:
	if platform == null:
		return
	var callback: Callable = _platform_signal_callbacks.get(platform.get_instance_id(), Callable())
	if is_instance_valid(platform) and platform.has_signal("inventory_changed") and callback.is_valid() \
			and platform.inventory_changed.is_connected(callback):
		platform.inventory_changed.disconnect(callback)
	_platform_signal_callbacks.erase(platform.get_instance_id())


func _on_platform_changed(platform: Node) -> void:
	notify_platform_changed(platform)


func _on_actor_tree_exiting(actor_key: int) -> void:
	_erase_assignment(actor_key, true)


func _erase_assignment(actor_key: int, cancel_platform: bool) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	if assignment.is_empty():
		return
	var actor_ref := assignment.get("actor") as WeakRef
	var actor := actor_ref.get_ref() as Node if actor_ref != null else null
	var platform := assignment.get("platform") as Node
	if cancel_platform and platform != null and is_instance_valid(platform) and platform.has_method("cancel_pending_automatic_haul_by_actor_key"):
		platform.call("cancel_pending_automatic_haul_by_actor_key", actor_key)
	_release_assignment_reservations(assignment, actor)
	_disconnect_actor_callbacks(assignment, actor)
	_offer_claims.erase(str(assignment.get("offer_id", "")))
	_assignments.erase(actor_key)


func _release_assignment_reservations(assignment: Dictionary, actor: Node) -> void:
	var resource_id := str(assignment.get("resource_id", ""))
	var source_reserved := maxf(0.0, float(assignment.get("source_reserved", 0.0)))
	var source := _endpoint_by_id(str(assignment.get("source_endpoint_id", "")))
	if source_reserved > EPSILON and source != null:
		source.call("release_haul_outgoing", resource_id, source_reserved, actor)
	var destination_reserved := maxf(0.0, float(assignment.get("destination_reserved", 0.0)))
	var destination := _endpoint_by_id(str(assignment.get("destination_endpoint_id", "")))
	if destination_reserved > EPSILON and destination != null:
		destination.call("release_haul_incoming", resource_id, destination_reserved, actor)


func _disconnect_actor_callbacks(assignment: Dictionary, actor: Node) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var arrival_callback: Callable = assignment.get("arrival_callback", Callable())
	if actor.has_signal("container_reached") and arrival_callback.is_valid() and actor.container_reached.is_connected(arrival_callback):
		actor.container_reached.disconnect(arrival_callback)
	var exit_callback: Callable = assignment.get("exit_callback", Callable())
	if actor.has_signal("tree_exiting") and exit_callback.is_valid() and actor.tree_exiting.is_connected(exit_callback):
		actor.tree_exiting.disconnect(exit_callback)


func _mark_offer_cache_dirty(settlement_id: String) -> void:
	_dirty_offer_caches[settlement_id] = true
	work_offers_changed.emit(settlement_id)


func _known_settlement_ids() -> Array:
	var ids: Dictionary = {}
	for settlement_id_value in _endpoint_ids_by_settlement.keys():
		ids[str(settlement_id_value)] = true
	for offer_value in _transfer_offers.values():
		ids[str((offer_value as Dictionary).get("settlement_id", ""))] = true
	for platform_offers_value in _platform_offers.values():
		for offer_value in platform_offers_value as Array:
			ids[str((offer_value as Dictionary).get("settlement_id", ""))] = true
	ids.erase("")
	return ids.keys()


func _offer_settlements(offers_value) -> Dictionary:
	var settlements: Dictionary = {}
	for offer_value in offers_value as Array:
		var settlement_id := str((offer_value as Dictionary).get("settlement_id", ""))
		settlements[settlement_id] = true
	return settlements
