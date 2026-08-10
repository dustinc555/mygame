extends Node

class_name JobSystemController

const SERVICE_ID := &"job_system"
const GECS_SERVICE_ID := &"gecs_world"
const DISPATCH_INTERVAL_SECONDS := 0.5
const DEFAULT_UNSCOPED_LOCAL_WORK_RADIUS := 90.0
const CORE_JOB_SPECS := [
	{"entry_id": "category:farm", "category": "farm", "display_name": "Farm"},
	{"entry_id": "category:guard", "category": "guard", "display_name": "Guard"},
	{"entry_id": "category:mine", "category": "mine", "display_name": "Mine"},
	{"entry_id": "category:research", "category": "research", "display_name": "Research"},
	{"entry_id": "category:crafting", "category": "crafting", "display_name": "Crafting"},
	{"entry_id": "category:medicine", "category": "medicine", "display_name": "Medicine"},
]

var root_scene: Node
var _context: BootstrapContext
var _sim_time := 0.0
var _initialized := false
var _job_providers: Array = []
var _actor_policies: Dictionary = {}
var _dispatch_remaining := 0.0


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	if is_inside_tree():
		_initialized = true
		_refresh_job_provider_cache()
	refresh_from_gecs_state()


func _ready() -> void:
	add_to_group("job_system_controller")
	if root_scene != null:
		_initialized = true
	_refresh_job_provider_cache()
	refresh_from_gecs_state()


func register_job_provider(provider: Node) -> void:
	if provider == null or not is_instance_valid(provider):
		return
	if not _is_job_provider_in_scope(provider):
		return
	if _job_providers.has(provider):
		return
	_job_providers.append(provider)


func unregister_job_provider(provider: Node) -> void:
	var index := _job_providers.find(provider)
	if index >= 0:
		_job_providers.remove_at(index)


func collect_work_offers(settlement_id := "") -> Array:
	_refresh_job_provider_cache()
	var offers: Array = []
	for provider in _job_providers:
		if not is_instance_valid(provider) or not provider.has_method("get_available_work_offers"):
			continue
		for offer_value in provider.call("get_available_work_offers", settlement_id):
			var offer: Dictionary = offer_value
			if not offer.has("provider"):
				offer["provider"] = provider
			offers.append(offer)
	return offers


func get_actor_ranked_jobs(actor: Node) -> Array:
	if not _is_player_party_actor(actor):
		return []
	var entries := _available_entries(actor)
	var policy := _ensure_actor_policy(actor, entries)
	var entries_by_id: Dictionary = {}
	for entry_value in entries:
		var entry: Dictionary = entry_value
		entries_by_id[str(entry.get("entry_id", ""))] = entry
	var rows: Array = []
	var ordered_ids := PackedStringArray(policy.get("ordered_entry_ids", PackedStringArray()))
	for index in range(ordered_ids.size()):
		var entry_id := ordered_ids[index]
		if not entries_by_id.has(entry_id):
			continue
		var row: Dictionary = (entries_by_id[entry_id] as Dictionary).duplicate(true)
		row["priority_order"] = index
		rows.append(row)
	return rows


func is_actor_jobs_enabled(actor: Node) -> bool:
	if not _is_player_party_actor(actor):
		return false
	var policy := _ensure_actor_policy(actor, _available_entries(actor))
	return bool(policy.get("jobs_enabled", false))


func set_actor_jobs_enabled(actor: Node, enabled: bool) -> bool:
	if not _is_player_party_actor(actor):
		return false
	var actor_id := _actor_id(actor)
	if actor_id.is_empty():
		return false
	var policy := _ensure_actor_policy(actor, _available_entries(actor))
	policy["jobs_enabled"] = enabled
	_actor_policies[actor_id] = policy
	_sync_job_system_state_to_gecs()
	return true


func move_actor_job_entry(actor: Node, entry_id: String, direction: int) -> bool:
	if not _is_player_party_actor(actor) or direction == 0:
		return false
	var actor_id := _actor_id(actor)
	var policy := _ensure_actor_policy(actor, _available_entries(actor))
	var ordered_ids := PackedStringArray(policy.get("ordered_entry_ids", PackedStringArray()))
	var current_index := ordered_ids.find(entry_id)
	if current_index < 0:
		return false
	var target_index := clampi(current_index + direction, 0, ordered_ids.size() - 1)
	if target_index == current_index:
		return false
	ordered_ids.remove_at(current_index)
	ordered_ids.insert(target_index, entry_id)
	policy["ordered_entry_ids"] = ordered_ids
	_actor_policies[actor_id] = policy
	_sync_job_system_state_to_gecs()
	return true


func get_actor_job_entry_rank(actor: Node, entry_id: String) -> int:
	for row_value in get_actor_ranked_jobs(actor):
		var row: Dictionary = row_value
		if str(row.get("entry_id", "")) == entry_id:
			return int(row.get("priority_order", 999999))
	return 999999


func dispatch_actor_work(actor: Node) -> bool:
	if not _can_dispatch_actor(actor):
		return false
	var settlement_id := _local_actor_settlement_id(actor)
	var ranks := _actor_rank_map(actor)
	var candidates: Array[Dictionary] = []
	for offer_value in collect_work_offers():
		var offer: Dictionary = offer_value
		if not _offer_matches_actor_scope(offer, actor, settlement_id):
			continue
		if not _offer_allows_actor(offer, actor):
			continue
		var entry_id := str(offer.get("job_entry_id", ""))
		if entry_id.is_empty():
			entry_id = "category:%s" % _normalize_category(str(offer.get("category", "")))
		if not ranks.has(entry_id):
			continue
		var candidate := offer.duplicate(true)
		candidate["entry_id"] = entry_id
		candidate["rank"] = int(ranks[entry_id])
		candidate["distance"] = _offer_distance(actor, offer)
		candidates.append(candidate)
	candidates.sort_custom(_offer_precedes)
	var facility_rank := _highest_actionable_facility_rank(actor, ranks)
	for offer in candidates:
		if facility_rank < int(offer.get("rank", 999999)):
			return false
		var provider := offer.get("provider") as Node
		if provider == null or not is_instance_valid(provider) or not provider.has_method("accept_work_offer"):
			continue
		if provider.has_method("can_actor_accept_work_offer") and not bool(provider.call("can_actor_accept_work_offer", offer, actor)):
			continue
		var result = provider.call("accept_work_offer", offer, actor)
		if _work_offer_was_accepted(result):
			return true
	return false


func _process(delta: float) -> void:
	if not _initialized:
		return
	_sim_time += delta
	_expire_missed_job_contracts()
	_process_job_provider_contracts(delta)
	_dispatch_remaining -= delta
	if _dispatch_remaining <= 0.0:
		_dispatch_remaining = DISPATCH_INTERVAL_SECONDS
		_process_party_job_dispatch()
	_sync_job_system_state_to_gecs()


func get_sim_time() -> float:
	return _sim_time


func serialize_state() -> Dictionary:
	_sync_job_system_state_to_gecs()
	return {"state_id": "job_system", "sim_time": _sim_time, "actor_policies": _actor_policies.duplicate(true)}


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty():
		refresh_from_gecs_state()
		return
	_sim_time = float(state.get("sim_time", _sim_time))
	_actor_policies = (state.get("actor_policies", _actor_policies) as Dictionary).duplicate(true)
	_sync_job_system_state_to_gecs()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_job_system_state"):
		return
	var state: Dictionary = bridge.call("get_job_system_state")
	if not state.is_empty():
		_sim_time = float(state.get("sim_time", _sim_time))
		_actor_policies = (state.get("actor_policies", _actor_policies) as Dictionary).duplicate(true)


func sync_job_system_state() -> void:
	_sync_job_system_state_to_gecs()


func _available_entries(actor: Node) -> Array:
	var entries: Array = []
	for spec in CORE_JOB_SPECS:
		var row: Dictionary = (spec as Dictionary).duplicate(true)
		row["kind"] = "category"
		entries.append(row)
	_append_provider_category_entries(entries, _actor_settlement_id(actor))
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_actor_job_contracts"):
		for contract_value in bridge.call("get_actor_job_contracts", actor):
			var contract: Dictionary = contract_value
			if str(contract.get("status", "active")) != "active":
				continue
			var contract_id := str(contract.get("contract_id", ""))
			if contract_id.is_empty():
				continue
			var role_name := str(contract.get("display_name", "Facility Duty"))
			var provider_name := str(contract.get("provider_name", "Facility"))
			entries.append({
				"entry_id": "facility_contract:%s" % contract_id,
				"display_name": "%s at %s" % [role_name, provider_name],
				"kind": "facility_contract",
				"contract_id": contract_id,
				"contract": contract.duplicate(true),
			})
	_append_assignment_slot_entries(actor, entries)
	return entries


func _append_provider_category_entries(entries: Array, settlement_id: String) -> void:
	var known := {}
	for entry_value in entries:
		known[str((entry_value as Dictionary).get("entry_id", ""))] = true
	_refresh_job_provider_cache()
	for provider in _job_providers:
		if not is_instance_valid(provider) or not provider.has_method("get_job_category_specs"):
			continue
		for spec_value in provider.call("get_job_category_specs", settlement_id):
			if not (spec_value is Dictionary):
				continue
			var spec: Dictionary = (spec_value as Dictionary).duplicate(true)
			var category := _normalize_category(str(spec.get("category", "")))
			if category.is_empty():
				continue
			var entry_id := str(spec.get("entry_id", "category:%s" % category))
			if known.has(entry_id):
				continue
			spec["entry_id"] = entry_id
			spec["category"] = category
			spec["display_name"] = str(spec.get("display_name", category.capitalize()))
			spec["kind"] = "category"
			entries.append(spec)
			known[entry_id] = true


func _append_assignment_slot_entries(actor: Node, entries: Array) -> void:
	var settlement := _context.get_optional(&"settlement") if _context != null else null
	var settlement_id := _actor_settlement_id(actor)
	if settlement == null or settlement_id.is_empty() or not settlement.has_method("get_settlement_state"):
		return
	var state: Dictionary = settlement.call("get_settlement_state", settlement_id)
	var actor_id := _actor_id(actor)
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if str(slot.get("assignment_domain", "employment")) == "residence" or str(slot.get("occupant_actor_id", "")) != actor_id:
			continue
		var slot_id := str(slot.get("slot_id", ""))
		if slot_id.is_empty():
			continue
		var role_name := str(slot.get("role_display_name", slot.get("display_name", str(slot.get("role_id", "Facility Duty")).capitalize())))
		var facility_name := str(slot.get("facility_display_name", slot.get("facility_id", "Facility"))).replace("_", " ").capitalize()
		entries.append({
			"entry_id": "facility_slot:%s" % slot_id,
			"display_name": "%s at %s" % [role_name, facility_name],
			"kind": "facility_slot",
			"slot_id": slot_id,
		})


func _ensure_actor_policy(actor: Node, entries: Array) -> Dictionary:
	var actor_id := _actor_id(actor)
	if actor_id.is_empty():
		return {"jobs_enabled": false, "ordered_entry_ids": PackedStringArray()}
	var policy: Dictionary = (_actor_policies.get(actor_id, {}) as Dictionary).duplicate(true)
	var existing_order := PackedStringArray(policy.get("ordered_entry_ids", PackedStringArray()))
	var available_ids := PackedStringArray()
	for entry_value in entries:
		var entry_id := str((entry_value as Dictionary).get("entry_id", ""))
		if not entry_id.is_empty() and not available_ids.has(entry_id):
			available_ids.append(entry_id)
	var normalized_order := PackedStringArray()
	for entry_id in existing_order:
		if available_ids.has(entry_id) and not normalized_order.has(entry_id):
			normalized_order.append(entry_id)
	for entry_id in available_ids:
		if not normalized_order.has(entry_id):
			normalized_order.append(entry_id)
	var changed := not _actor_policies.has(actor_id) or normalized_order != existing_order or not policy.has("jobs_enabled")
	policy["jobs_enabled"] = bool(policy.get("jobs_enabled", false))
	policy["ordered_entry_ids"] = normalized_order
	_actor_policies[actor_id] = policy
	if changed:
		_sync_job_system_state_to_gecs()
	return policy


func _process_party_job_dispatch() -> void:
	if root_scene == null or not is_instance_valid(root_scene) or not root_scene.is_inside_tree():
		return
	for actor in root_scene.get_tree().get_nodes_in_group("party_member"):
		if actor == root_scene or root_scene.is_ancestor_of(actor):
			dispatch_actor_work(actor)


func _can_dispatch_actor(actor: Node) -> bool:
	if not _is_player_party_actor(actor) or not is_actor_jobs_enabled(actor):
		return false
	if _has_property(actor, "life_state") and int(actor.get("life_state")) != 0:
		return false
	if actor.has_method("has_active_player_order") and bool(actor.call("has_active_player_order")):
		return false
	if actor.has_method("get_active_job_provider"):
		var active_provider = actor.call("get_active_job_provider")
		if active_provider != null and is_instance_valid(active_provider):
			return false
	for provider in _job_providers:
		if is_instance_valid(provider) and provider.has_method("has_active_work_for_actor") and bool(provider.call("has_active_work_for_actor", actor)):
			return false
	return true


func _actor_rank_map(actor: Node) -> Dictionary:
	var ranks := {}
	for row_value in get_actor_ranked_jobs(actor):
		var row: Dictionary = row_value
		ranks[str(row.get("entry_id", ""))] = int(row.get("priority_order", 999999))
	return ranks


func _highest_actionable_facility_rank(actor: Node, ranks: Dictionary) -> int:
	var best_rank := 999999
	for row_value in get_actor_ranked_jobs(actor):
		var row: Dictionary = row_value
		if str(row.get("kind", "")) != "facility_contract":
			continue
		var provider := _resolve_contract_provider(row.get("contract", {}) as Dictionary)
		if provider == null:
			continue
		var status: Dictionary = provider.call("get_contract_work_status", actor, row.get("contract", {})) if provider.has_method("get_contract_work_status") else {"actionable": true}
		if bool(status.get("actionable", true)):
			best_rank = mini(best_rank, int(ranks.get(str(row.get("entry_id", "")), 999999)))
	return best_rank


func _resolve_contract_provider(contract: Dictionary) -> Node:
	var provider_id := str(contract.get("provider_id", ""))
	var provider_path: NodePath = contract.get("provider_path", NodePath())
	for provider in _job_providers:
		if provider == null or not is_instance_valid(provider):
			continue
		if provider_path != NodePath() and provider.get_path() == provider_path:
			return provider
		if not provider_id.is_empty():
			if provider.has_method("get_provider_id") and str(provider.call("get_provider_id")) == provider_id:
				return provider
			if str(provider.get_path()) == provider_id:
				return provider
	return null


func _actor_settlement_id(actor: Node) -> String:
	if actor == null:
		return ""
	if actor.has_meta("assigned_settlement_id"):
		var assigned := str(actor.get_meta("assigned_settlement_id", ""))
		if not assigned.is_empty():
			return assigned
	if actor.has_meta("settlement_id"):
		var metadata_settlement := str(actor.get_meta("settlement_id", ""))
		if not metadata_settlement.is_empty():
			return metadata_settlement
	if _has_property(actor, "settlement_id"):
		var direct := str(actor.get("settlement_id"))
		if not direct.is_empty():
			return direct
	var population := _context.get_optional(&"population") if _context != null else null
	if population != null and population.has_method("get_actor_record"):
		return str((population.call("get_actor_record", _actor_id(actor)) as Dictionary).get("settlement_id", ""))
	return ""


func _actor_id(actor: Node) -> String:
	if actor == null:
		return ""
	if _has_property(actor, "stable_id"):
		return str(actor.get("stable_id")).strip_edges()
	return str(actor.get_meta("stable_id", "")).strip_edges()


func _is_player_party_actor(actor: Node) -> bool:
	return actor != null and actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member"))


func _offer_allows_actor(offer: Dictionary, actor: Node) -> bool:
	var allowed_actor_ids := PackedStringArray(offer.get("allowed_actor_ids", PackedStringArray()))
	return allowed_actor_ids.is_empty() or allowed_actor_ids.has(_actor_id(actor))


func _offer_matches_actor_scope(offer: Dictionary, actor: Node, settlement_id: String) -> bool:
	var offer_settlement_id := str(offer.get("settlement_id", ""))
	var actor_faction := _actor_faction_id(actor)
	var owner_faction := str(offer.get("owner_faction_id", ""))
	if actor_faction.is_empty() or (not owner_faction.is_empty() and owner_faction != actor_faction):
		return false
	if not settlement_id.is_empty():
		if not offer_settlement_id.is_empty() and offer_settlement_id != settlement_id:
			return false
		if not _offer_is_inside_settlement(offer, settlement_id, actor):
			return false
		if not offer_settlement_id.is_empty():
			return true
	if not offer_settlement_id.is_empty():
		return false
	if owner_faction.is_empty():
		return false
	return not settlement_id.is_empty() or _offer_distance(actor, offer) <= DEFAULT_UNSCOPED_LOCAL_WORK_RADIUS


## Jobs follows the town the actor is physically standing in. Permanent town or
## facility assignments remain available to the separate contract AI, but do not
## make autonomous category work pull a party member across the world.
func _local_actor_settlement_id(actor: Node) -> String:
	if not (actor is Node3D):
		return ""
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_settlement_states"):
		return _actor_settlement_id(actor)
	var states: Dictionary = bridge.call("get_settlement_states")
	if states.is_empty():
		# Isolated test levels may scope work without bootstrapping a town record.
		return _actor_settlement_id(actor)
	var actor_position := (actor as Node3D).global_position
	var actor_faction := _actor_faction_id(actor)
	var best_id := ""
	var best_distance := INF
	for settlement_id_value in states.keys():
		var settlement_id := str(settlement_id_value)
		var state: Dictionary = states.get(settlement_id_value, {})
		if str(state.get("faction_id", "")) != actor_faction:
			continue
		var center = state.get("world_position")
		var radius := float(state.get("radius", 0.0))
		if not center is Vector3 or radius <= 0.0:
			continue
		var distance := _horizontal_distance(actor_position, center as Vector3)
		if distance <= radius and (distance < best_distance or (is_equal_approx(distance, best_distance) and settlement_id < best_id)):
			best_id = settlement_id
			best_distance = distance
	return best_id


func _offer_is_inside_settlement(offer: Dictionary, settlement_id: String, actor: Node) -> bool:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_settlement_states"):
		return _offer_distance(actor, offer) <= DEFAULT_UNSCOPED_LOCAL_WORK_RADIUS
	var states: Dictionary = bridge.call("get_settlement_states")
	if states.is_empty():
		return _offer_distance(actor, offer) <= DEFAULT_UNSCOPED_LOCAL_WORK_RADIUS
	var state: Dictionary = states.get(settlement_id, {})
	var center = state.get("world_position")
	var position = offer.get("world_position")
	var radius := float(state.get("radius", 0.0))
	return center is Vector3 and position is Vector3 and radius > 0.0 \
			and _horizontal_distance(center as Vector3, position as Vector3) <= radius


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _actor_faction_id(actor: Node) -> String:
	if actor == null:
		return ""
	if _has_property(actor, "faction_name"):
		var faction_name := str(actor.get("faction_name"))
		if not faction_name.is_empty():
			return faction_name
	if _has_property(actor, "faction_id"):
		return str(actor.get("faction_id"))
	return ""


func _normalize_category(category: String) -> String:
	var normalized := category.strip_edges().to_lower()
	if normalized == "farming":
		return "farm"
	if normalized == "mining":
		return "mine"
	return normalized


func _offer_distance(actor: Node, offer: Dictionary) -> float:
	if not (actor is Node3D) or not offer.get("world_position") is Vector3:
		return INF
	return (actor as Node3D).global_position.distance_to(offer.get("world_position") as Vector3)


func _offer_precedes(a: Dictionary, b: Dictionary) -> bool:
	var a_rank := int(a.get("rank", 999999))
	var b_rank := int(b.get("rank", 999999))
	if a_rank != b_rank:
		return a_rank < b_rank
	var a_urgency := float(a.get("urgency", 0.0))
	var b_urgency := float(b.get("urgency", 0.0))
	if not is_equal_approx(a_urgency, b_urgency):
		return a_urgency > b_urgency
	var a_distance := float(a.get("distance", INF))
	var b_distance := float(b.get("distance", INF))
	if not is_equal_approx(a_distance, b_distance):
		return a_distance < b_distance
	return str(a.get("offer_id", "")) < str(b.get("offer_id", ""))


func _work_offer_was_accepted(result: Variant) -> bool:
	if result is bool:
		return bool(result)
	if result is Dictionary:
		return bool((result as Dictionary).get("accepted", (result as Dictionary).get("allowed", false)))
	var message := str(result).strip_edges().to_lower()
	return message.begins_with("1 worker assigned") or message.begins_with("worker assigned") or message.begins_with("accepted") or message.begins_with("started")


func _sync_job_system_state_to_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_job_system_state"):
		bridge.call("upsert_job_system_state", {"state_id": "job_system", "sim_time": _sim_time, "actor_policies": _actor_policies.duplicate(true)})


func _expire_missed_job_contracts() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("expire_missed_job_contracts"):
		bridge.call("expire_missed_job_contracts", _sim_time)


func _process_job_provider_contracts(delta: float) -> void:
	for index in range(_job_providers.size() - 1, -1, -1):
		var provider = _job_providers[index]
		if provider == null or not is_instance_valid(provider) or not provider.is_inside_tree():
			_job_providers.remove_at(index)
			continue
		if provider.has_method("process_contracts"):
			provider.call("process_contracts", delta, _sim_time)


func _refresh_job_provider_cache() -> void:
	if not is_inside_tree():
		return
	var refreshed_providers: Array = []
	for provider in get_tree().get_nodes_in_group("job_provider"):
		if provider == null or not is_instance_valid(provider) or not provider.is_inside_tree():
			continue
		if not _is_job_provider_in_scope(provider):
			continue
		if not refreshed_providers.has(provider):
			refreshed_providers.append(provider)
	_job_providers = refreshed_providers


func _is_job_provider_in_scope(provider: Node) -> bool:
	if provider == null:
		return false
	if root_scene == null or not is_instance_valid(root_scene):
		return true
	return provider == root_scene or _is_node_descendant_of(provider, root_scene)


func _is_node_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _get_gecs_world() -> Node:
	return _context.get_optional(GECS_SERVICE_ID) if _context != null else null
