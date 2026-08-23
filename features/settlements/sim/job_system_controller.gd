extends Node

class_name JobSystemController

const SERVICE_ID := &"job_system"
const GECS_SERVICE_ID := &"gecs_world"
const DISPATCH_SLOT_SECONDS := 1.0 / 60.0
const MAX_ACTOR_DISPATCHES_PER_TICK := 16
const RESERVED_ASSIGNMENT_DISPATCHES_PER_TICK := 8
const MAX_ASSIGNMENT_OFFERS_PER_ACTOR := 24
const DEFAULT_UNSCOPED_LOCAL_WORK_RADIUS := 90.0
const FACILITY_DUTY_CONTRACT = preload("res://features/settlements/sim/facility_duty_contract.gd")
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
var _settlement_controller: Node
var _sim_time := 0.0
var _initialized := false
var _job_providers: Array = []
var _actor_policies: Dictionary = {}
var _enabled_party_actors: Dictionary = {}
var _dispatch_actor_order: Array[int] = []
var _known_dispatch_actor_ids: Dictionary = {}
var _dispatch_actor_cursor := 0
var _assignment_workers: Dictionary = {}
var _assignment_actor_order: Array[String] = []
var _assignment_ids_by_settlement: Dictionary = {}
var _assignment_actor_cursor := 0
var _assignment_cache_bound := false
var _dispatch_remaining := 0.0
var _assignment_dispatch_turn := false
var _property_presence_cache: Dictionary = {}
var _last_dispatch_usec := 0


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	_settlement_controller = context.get_optional(&"settlement")
	if is_inside_tree():
		_initialized = true
		_refresh_job_provider_cache()
	refresh_from_gecs_state()
	_bind_party_actor_cache()
	_bind_assignment_worker_cache()


func _ready() -> void:
	add_to_group("job_system_controller")
	if root_scene != null:
		_initialized = true
	_refresh_job_provider_cache()
	refresh_from_gecs_state()
	_bind_party_actor_cache()
	_bind_assignment_worker_cache()


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


func is_actor_work_busy(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return true
	if actor.has_method("has_active_player_order") and bool(actor.call("has_active_player_order")):
		return true
	if actor.has_method("get_active_job_provider") and actor.call("get_active_job_provider") != null:
		return true
	for provider in _job_providers:
		if is_instance_valid(provider) and provider.has_method("has_active_work_for_actor") \
				and bool(provider.call("has_active_work_for_actor", actor)):
			return true
	return false


func cancel_work_for_actor(actor: Node) -> void:
	if actor == null:
		return
	for provider in _job_providers:
		if is_instance_valid(provider) and provider.has_method("cancel_work_for_actor"):
			provider.call("cancel_work_for_actor", actor)


func dispatch_actor_work_for_assignment(actor: Node, settlement_id: String, allowed_entry_ids: PackedStringArray = PackedStringArray(), before_accept := Callable(), available_offers = null, settlement_states = null, offer_scope_cache = null) -> bool:
	if actor == null or not is_instance_valid(actor) or settlement_id.is_empty() or is_actor_work_busy(actor):
		return false
	var candidates: Array[Dictionary] = []
	var offers: Array = available_offers if available_offers is Array else collect_work_offers(settlement_id)
	if not settlement_states is Dictionary:
		var bridge := _get_gecs_world()
		settlement_states = bridge.call("get_settlement_states") if bridge != null and bridge.has_method("get_settlement_states") else null
	var actor_id := _actor_id(actor)
	var actor_faction := _actor_faction_id(actor)
	for offer_value in offers:
		var offer: Dictionary = offer_value
		if not _assignment_offer_matches_scope(offer, actor, settlement_id, settlement_states, offer_scope_cache, actor_id, actor_faction):
			continue
		var entry_id := str(offer.get("job_entry_id", ""))
		if entry_id.is_empty():
			entry_id = "category:%s" % _normalize_category(str(offer.get("category", "")))
		if not allowed_entry_ids.is_empty() and not allowed_entry_ids.has(entry_id):
			continue
		var candidate := offer.duplicate(false)
		candidate["entry_id"] = entry_id
		candidate["rank"] = allowed_entry_ids.find(entry_id) if not allowed_entry_ids.is_empty() else 0
		candidate["distance"] = _offer_distance(actor, offer)
		candidates.append(candidate)
	candidates.sort_custom(_offer_precedes)
	for offer in candidates:
		var provider := offer.get("provider") as Node
		if provider == null or not is_instance_valid(provider) or not provider.has_method("accept_work_offer"):
			continue
		if provider.has_method("can_actor_accept_work_offer") and not bool(provider.call("can_actor_accept_work_offer", offer, actor)):
			continue
		var result = provider.call("accept_work_offer", offer, actor)
		if _work_offer_was_accepted(result):
			if before_accept.is_valid():
				before_accept.call()
			return true
	return false


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
	var actor_id := _actor_id(actor)
	if actor_id.is_empty():
		return false
	if _actor_policies.has(actor_id):
		return bool((_actor_policies.get(actor_id, {}) as Dictionary).get("jobs_enabled", false))
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
	_set_enabled_party_actor(actor, enabled)
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


func dispatch_actor_work(actor: Node, available_offers = null, settlement_states = null, offer_scope_cache = null) -> bool:
	if not _can_dispatch_actor(actor):
		return false
	var settlement_id := _local_actor_settlement_id(actor, settlement_states)
	var ranked_rows := get_actor_ranked_jobs(actor)
	var ranks := _actor_rank_map(actor, ranked_rows)
	var actor_id := _actor_id(actor)
	var actor_faction := _actor_faction_id(actor)
	var candidates: Array[Dictionary] = []
	var offers: Array = available_offers if available_offers is Array else collect_work_offers()
	for offer_value in offers:
		var offer: Dictionary = offer_value
		if not _offer_matches_actor_scope(offer, actor, settlement_id, settlement_states, offer_scope_cache, actor_id, actor_faction):
			continue
		if not _offer_allows_actor(offer, actor, actor_id):
			continue
		var entry_id := str(offer.get("job_entry_id", ""))
		if entry_id.is_empty():
			entry_id = "category:%s" % _normalize_category(str(offer.get("category", "")))
		if not ranks.has(entry_id):
			continue
		var candidate := offer.duplicate(false)
		candidate["entry_id"] = entry_id
		candidate["rank"] = int(ranks[entry_id])
		candidate["distance"] = _offer_distance(actor, offer)
		candidates.append(candidate)
	candidates.sort_custom(_offer_precedes)
	var facility_rank := _highest_actionable_facility_rank(actor, ranks, ranked_rows)
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
			_remove_offer_by_id(offers, str(offer.get("offer_id", "")))
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
		# One shared actor-start slot per rendered frame. Low frame rate slows
		# discovery instead of multiplying expensive movement starts into a spike.
		_dispatch_remaining = DISPATCH_SLOT_SECONDS
		var dispatch_started := Time.get_ticks_usec()
		_process_party_job_dispatch(1)
		_last_dispatch_usec = Time.get_ticks_usec() - dispatch_started


func get_last_dispatch_msec() -> float:
	return float(_last_dispatch_usec) / 1000.0


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
	_bind_party_actor_cache()
	_sync_job_system_state_to_gecs()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_job_system_state"):
		return
	var state: Dictionary = bridge.call("get_job_system_state")
	if not state.is_empty():
		_sim_time = float(state.get("sim_time", _sim_time))
		_actor_policies = (state.get("actor_policies", _actor_policies) as Dictionary).duplicate(true)
		_bind_party_actor_cache()


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
	_move_default_last_entries(entries)
	return entries


func _move_default_last_entries(entries: Array) -> void:
	var default_last: Array = []
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		if bool(entry.get("default_last", false)):
			default_last.push_front(entry)
			entries.remove_at(index)
	entries.append_array(default_last)


func _append_provider_category_entries(entries: Array, settlement_id: String) -> void:
	var known := {}
	for entry_value in entries:
		known[str((entry_value as Dictionary).get("entry_id", ""))] = true
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
	_set_enabled_party_actor(actor, bool(policy.get("jobs_enabled", false)))
	if changed:
		_sync_job_system_state_to_gecs()
	return policy


func _process_party_job_dispatch(max_dispatches := MAX_ACTOR_DISPATCHES_PER_TICK) -> void:
	if root_scene == null or not is_instance_valid(root_scene) or not root_scene.is_inside_tree():
		return
	var dispatch_budget := maxi(max_dispatches, 0)
	if dispatch_budget <= 0:
		return
	_bind_assignment_worker_cache()
	if _enabled_party_actors.is_empty():
		_dispatch_actor_order.clear()
		_known_dispatch_actor_ids.clear()
		_dispatch_actor_cursor = 0
	if _enabled_party_actors.is_empty() and _assignment_workers.is_empty():
		return
	var offers: Array = []
	var offers_loaded := false
	var settlement_states: Variant = null
	var offer_scope_cache: Dictionary = {}
	var attempts := 0
	var dispatched := 0
	var party_budget := dispatch_budget
	if not _assignment_workers.is_empty():
		if _enabled_party_actors.is_empty():
			party_budget = 0
		elif dispatch_budget == 1:
			party_budget = 0 if _assignment_dispatch_turn else 1
			_assignment_dispatch_turn = not _assignment_dispatch_turn
		else:
			party_budget = dispatch_budget - mini(RESERVED_ASSIGNMENT_DISPATCHES_PER_TICK, dispatch_budget)
	while attempts < _dispatch_actor_order.size() and dispatched < party_budget:
		if _dispatch_actor_order.is_empty():
			break
		_dispatch_actor_cursor %= _dispatch_actor_order.size()
		var instance_id_value := _dispatch_actor_order[_dispatch_actor_cursor]
		_dispatch_actor_cursor = (_dispatch_actor_cursor + 1) % _dispatch_actor_order.size()
		attempts += 1
		var actor_ref: WeakRef = _enabled_party_actors.get(instance_id_value)
		var actor = actor_ref.get_ref() if actor_ref != null else null
		if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree() or not root_scene.is_ancestor_of(actor):
			_enabled_party_actors.erase(instance_id_value)
			continue
		dispatched += 1
		if not _can_dispatch_actor(actor):
			continue
		if not offers_loaded:
			offers = collect_work_offers()
			var bridge := _get_gecs_world()
			settlement_states = bridge.call("get_settlement_states") if bridge != null and bridge.has_method("get_settlement_states") else null
			offers_loaded = true
		dispatch_actor_work(actor, offers, settlement_states, offer_scope_cache)
	_compact_dispatch_actor_order_if_needed()
	var assignment_budget := dispatch_budget - dispatched
	if assignment_budget <= 0:
		return
	if not offers_loaded:
		offers = collect_work_offers()
		var bridge := _get_gecs_world()
		settlement_states = bridge.call("get_settlement_states") if bridge != null and bridge.has_method("get_settlement_states") else null
	var assignment_offer_index := _build_assignment_offer_index(offers)
	_process_assignment_worker_dispatch(assignment_offer_index, settlement_states, offer_scope_cache, assignment_budget)


func _remove_offer_by_id(offers: Array, offer_id: String) -> void:
	if offer_id.is_empty():
		return
	for index in range(offers.size() - 1, -1, -1):
		if str((offers[index] as Dictionary).get("offer_id", "")) == offer_id:
			offers.remove_at(index)
			return


func _build_assignment_offer_index(offers: Array) -> Dictionary:
	var index: Dictionary = {}
	for offer_value in offers:
		var offer: Dictionary = offer_value
		var settlement_id := str(offer.get("settlement_id", ""))
		if not index.has(settlement_id):
			index[settlement_id] = {"all": [], "by_entry": {}}
		var row: Dictionary = index[settlement_id]
		(row["all"] as Array).append(offer)
		var entry_id := _offer_entry_id(offer)
		var by_entry: Dictionary = row["by_entry"]
		if not by_entry.has(entry_id):
			by_entry[entry_id] = []
		(by_entry[entry_id] as Array).append(offer)
	return index


func _assignment_offer_slice(index: Dictionary, assignment: Dictionary) -> Array:
	var sources: Array[Array] = []
	var total_size := 0
	var settlement_ids := [str(assignment.get("settlement_id", "")), ""]
	var allowed := PackedStringArray(assignment.get("allowed_job_entry_ids", PackedStringArray()))
	for settlement_id in settlement_ids:
		var row: Dictionary = index.get(settlement_id, {})
		if row.is_empty():
			continue
		if allowed.is_empty():
			var all_offers: Array = row.get("all", [])
			if not all_offers.is_empty():
				sources.append(all_offers)
				total_size += all_offers.size()
		else:
			var by_entry: Dictionary = row.get("by_entry", {})
			for entry_id in allowed:
				var entry_offers: Array = by_entry.get(entry_id, [])
				if not entry_offers.is_empty():
					sources.append(entry_offers)
					total_size += entry_offers.size()
	if total_size <= 0:
		return []
	var result: Array = []
	var take_count := mini(total_size, MAX_ASSIGNMENT_OFFERS_PER_ACTOR)
	var cursor := posmod(int(assignment.get("offer_cursor", 0)), total_size)
	for offset in take_count:
		result.append(_offer_from_sources(sources, (cursor + offset) % total_size))
	assignment["offer_cursor"] = (cursor + take_count) % total_size
	return result


func _offer_from_sources(sources: Array[Array], logical_index: int):
	var remaining := logical_index
	for source in sources:
		if remaining < source.size():
			return source[remaining]
		remaining -= source.size()
	return null


func _offer_entry_id(offer: Dictionary) -> String:
	var entry_id := str(offer.get("job_entry_id", ""))
	return entry_id if not entry_id.is_empty() else "category:%s" % _normalize_category(str(offer.get("category", "")))


func _process_assignment_worker_dispatch(assignment_offer_index: Dictionary, settlement_states, offer_scope_cache: Dictionary, budget: int) -> void:
	if budget <= 0 or _assignment_actor_order.is_empty():
		return
	var population := _context.get_optional(&"population") if _context != null else null
	if population == null or not population.has_method("get_live_actor"):
		return
	var attempts := 0
	var dispatched := 0
	while attempts < _assignment_actor_order.size() and dispatched < budget:
		_assignment_actor_cursor %= _assignment_actor_order.size()
		var actor_id := _assignment_actor_order[_assignment_actor_cursor]
		_assignment_actor_cursor = (_assignment_actor_cursor + 1) % _assignment_actor_order.size()
		attempts += 1
		var assignment: Dictionary = _assignment_workers.get(actor_id, {})
		if assignment.is_empty():
			continue
		var actor = population.call("get_live_actor", actor_id)
		if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
			continue
		if _is_player_party_actor(actor):
			continue
		dispatched += 1
		if not _assignment_schedule_is_active(assignment):
			_release_assignment_duty(actor, assignment, true)
			continue
		if is_actor_work_busy(actor):
			continue
		var before_accept := Callable(self, "_begin_assignment_duty").bind(actor, assignment)
		var actor_offers := _assignment_offer_slice(assignment_offer_index, assignment)
		var accepted := dispatch_actor_work_for_assignment(
			actor,
			str(assignment.get("settlement_id", "")),
			PackedStringArray(assignment.get("allowed_job_entry_ids", PackedStringArray())),
			before_accept,
			actor_offers,
			settlement_states,
			offer_scope_cache
		)
		if not accepted:
			_release_assignment_duty(actor, assignment, false)
	_compact_assignment_actor_order_if_needed()


func _compact_dispatch_actor_order_if_needed() -> void:
	if _dispatch_actor_order.size() <= _enabled_party_actors.size() * 2 + 32:
		return
	var compacted: Array[int] = []
	_known_dispatch_actor_ids.clear()
	for instance_id in _dispatch_actor_order:
		if not _enabled_party_actors.has(instance_id):
			continue
		compacted.append(instance_id)
		_known_dispatch_actor_ids[instance_id] = true
	_dispatch_actor_order = compacted
	_dispatch_actor_cursor = 0


func _compact_assignment_actor_order_if_needed() -> void:
	if _assignment_actor_order.size() <= _assignment_workers.size() * 2 + 32:
		return
	var compacted: Array[String] = []
	for actor_id in _assignment_actor_order:
		if _assignment_workers.has(actor_id):
			compacted.append(actor_id)
	_assignment_actor_order = compacted
	_assignment_actor_cursor = 0


func _assignment_schedule_is_active(assignment: Dictionary) -> bool:
	if not bool(assignment.get("schedule_enabled", false)):
		return true
	var world_time := _context.get_optional(&"world_time") if _context != null else null
	if world_time == null or not world_time.has_method("get_hour"):
		return false
	var hour := int(world_time.call("get_hour"))
	var open_hour := int(assignment.get("open_hour", 0))
	var close_hour := int(assignment.get("close_hour", 24))
	if open_hour == close_hour:
		return true
	return hour >= open_hour and hour < close_hour if open_hour < close_hour else hour >= open_hour or hour < close_hour


func _begin_assignment_duty(actor: Node, assignment: Dictionary) -> void:
	assignment["idle_projection_active"] = false
	FACILITY_DUTY_CONTRACT.begin(actor, str(assignment.get("facility_id", "")))
	var interaction = actor.call("get_interaction") if actor != null and actor.has_method("get_interaction") else null
	if interaction == null:
		return
	if interaction.has_method("stop_seat_assignment"):
		interaction.call("stop_seat_assignment")
	if interaction.has_method("stop_sleep_assignment"):
		interaction.call("stop_sleep_assignment")


func _release_assignment_duty(actor: Node, assignment: Dictionary, cancel_active: bool) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if cancel_active:
		cancel_work_for_actor(actor)
	var facility_id := str(assignment.get("facility_id", ""))
	var had_duty := str(actor.get_meta(FACILITY_DUTY_CONTRACT.ACTIVE_DUTY_META, "")) == facility_id
	FACILITY_DUTY_CONTRACT.end(actor, facility_id)
	if not had_duty and bool(assignment.get("idle_projection_active", false)):
		return
	assignment["idle_projection_active"] = true
	var settlements := _get_settlement_controller()
	if settlements != null and settlements.has_method("refresh_actor_residence_projection"):
		settlements.call(
			"refresh_actor_residence_projection",
			str(assignment.get("settlement_id", "")),
			str(assignment.get("actor_id", "")),
			"home_day"
		)


func _bind_party_actor_cache() -> void:
	if root_scene == null or not is_instance_valid(root_scene) or not root_scene.is_inside_tree():
		return
	var scene_tree := root_scene.get_tree()
	if not scene_tree.node_added.is_connected(_on_party_tree_node_added):
		scene_tree.node_added.connect(_on_party_tree_node_added)
	if not scene_tree.node_removed.is_connected(_on_party_tree_node_removed):
		scene_tree.node_removed.connect(_on_party_tree_node_removed)
	for actor in scene_tree.get_nodes_in_group("party_member"):
		_refresh_enabled_party_actor(actor)


func _bind_assignment_worker_cache() -> void:
	if _assignment_cache_bound:
		return
	var settlements := _get_settlement_controller()
	if settlements == null or not settlements.has_signal("settlement_state_changed"):
		return
	if not settlements.settlement_state_changed.is_connected(_on_assignment_settlement_state_changed):
		settlements.settlement_state_changed.connect(_on_assignment_settlement_state_changed)
	_assignment_cache_bound = true
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_settlement_states"):
		for state_value in (bridge.call("get_settlement_states") as Dictionary).values():
			var state: Dictionary = state_value
			_rebuild_assignment_workers_for_settlement(str(state.get("settlement_id", "")), state)


func _on_assignment_settlement_state_changed(settlement_id: String, state: Dictionary) -> void:
	_rebuild_assignment_workers_for_settlement(settlement_id, state)


func _rebuild_assignment_workers_for_settlement(settlement_id: String, state: Dictionary) -> void:
	if settlement_id.is_empty():
		return
	var next_facility_by_actor: Dictionary = {}
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var next_slot: Dictionary = slot_value
		if str(next_slot.get("assignment_domain", "")) == "employment" and bool(next_slot.get("filled", false)) \
				and bool(next_slot.get("uses_settlement_jobs", false)):
			next_facility_by_actor[str(next_slot.get("occupant_actor_id", ""))] = str(next_slot.get("facility_id", next_slot.get("owner_id", "")))
	var previous_entries: Dictionary = {}
	var population := _context.get_optional(&"population") if _context != null else null
	for actor_id_value in (_assignment_ids_by_settlement.get(settlement_id, PackedStringArray()) as PackedStringArray):
		var previous_actor_id := str(actor_id_value)
		var previous_entry: Dictionary = _assignment_workers.get(previous_actor_id, {})
		previous_entries[previous_actor_id] = previous_entry
		if str(next_facility_by_actor.get(previous_actor_id, "")) != str(previous_entry.get("facility_id", "")):
			var previous_actor = population.call("get_live_actor", previous_actor_id) if population != null and population.has_method("get_live_actor") else null
			_release_assignment_duty(previous_actor, previous_entry, true)
		_assignment_workers.erase(previous_actor_id)
	var actor_ids := PackedStringArray()
	var facilities: Dictionary = state.get("facilities", {})
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if str(slot.get("assignment_domain", "")) != "employment" or not bool(slot.get("filled", false)) \
				or not bool(slot.get("uses_settlement_jobs", false)):
			continue
		var actor_id := str(slot.get("occupant_actor_id", ""))
		var facility_id := str(slot.get("facility_id", slot.get("owner_id", "")))
		if actor_id.is_empty() or facility_id.is_empty():
			continue
		var facility: Dictionary = facilities.get(facility_id, {})
		_assignment_workers[actor_id] = {
			"actor_id": actor_id,
			"settlement_id": settlement_id,
			"facility_id": facility_id,
			"allowed_job_entry_ids": PackedStringArray(slot.get("allowed_job_entry_ids", PackedStringArray())),
			"schedule_enabled": bool(facility.get("door_schedule_enabled", false)),
			"open_hour": int(facility.get("door_open_hour", 0)),
			"close_hour": int(facility.get("door_close_hour", 24)),
			"idle_projection_active": bool((previous_entries.get(actor_id, {}) as Dictionary).get("idle_projection_active", false)),
		}
		actor_ids.append(actor_id)
		if not _assignment_actor_order.has(actor_id):
			_assignment_actor_order.append(actor_id)
	_assignment_ids_by_settlement[settlement_id] = actor_ids


func _on_party_tree_node_added(node: Node) -> void:
	if node != null and node.is_in_group("party_member"):
		_refresh_enabled_party_actor(node)


func _on_party_tree_node_removed(node: Node) -> void:
	if node != null:
		_enabled_party_actors.erase(node.get_instance_id())


func _refresh_enabled_party_actor(actor: Node) -> void:
	if not _is_player_party_actor(actor):
		return
	var actor_id := _actor_id(actor)
	var policy: Dictionary = _actor_policies.get(actor_id, {})
	_set_enabled_party_actor(actor, bool(policy.get("jobs_enabled", false)))


func _set_enabled_party_actor(actor: Node, enabled: bool) -> void:
	if actor == null:
		return
	var instance_id := actor.get_instance_id()
	if enabled:
		_enabled_party_actors[instance_id] = weakref(actor)
		if not _known_dispatch_actor_ids.has(instance_id):
			_known_dispatch_actor_ids[instance_id] = true
			_dispatch_actor_order.append(instance_id)
	else:
		_enabled_party_actors.erase(instance_id)


func _can_dispatch_actor(actor: Node) -> bool:
	if not _is_player_party_actor(actor):
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
	return is_actor_jobs_enabled(actor)


func _actor_rank_map(actor: Node, ranked_rows = null) -> Dictionary:
	var ranks := {}
	var rows: Array = ranked_rows if ranked_rows is Array else get_actor_ranked_jobs(actor)
	for row_value in rows:
		var row: Dictionary = row_value
		ranks[str(row.get("entry_id", ""))] = int(row.get("priority_order", 999999))
	return ranks


func _highest_actionable_facility_rank(actor: Node, ranks: Dictionary, ranked_rows = null) -> int:
	var best_rank := 999999
	var rows: Array = ranked_rows if ranked_rows is Array else get_actor_ranked_jobs(actor)
	for row_value in rows:
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


func _offer_allows_actor(offer: Dictionary, actor: Node, known_actor_id := "") -> bool:
	var allowed_actor_ids := PackedStringArray(offer.get("allowed_actor_ids", PackedStringArray()))
	var actor_id := known_actor_id if not known_actor_id.is_empty() else _actor_id(actor)
	return allowed_actor_ids.is_empty() or allowed_actor_ids.has(actor_id)


func _assignment_offer_matches_scope(offer: Dictionary, actor: Node, settlement_id: String, settlement_states = null, offer_scope_cache = null, known_actor_id := "", known_actor_faction := "") -> bool:
	var actor_id := known_actor_id if not known_actor_id.is_empty() else _actor_id(actor)
	if not _offer_allows_actor(offer, actor, actor_id):
		return false
	var offer_settlement_id := str(offer.get("settlement_id", ""))
	if not offer_settlement_id.is_empty() and offer_settlement_id != settlement_id:
		return false
	var actor_faction := known_actor_faction if not known_actor_faction.is_empty() else _actor_faction_id(actor)
	var owner_faction := str(offer.get("owner_faction_id", ""))
	if actor_faction.is_empty() or (not owner_faction.is_empty() and owner_faction != actor_faction):
		return false
	var offer_id := str(offer.get("offer_id", ""))
	var cache_key := "assignment:%s:%s:%s" % [settlement_id, actor_id, offer_id]
	if not offer_id.is_empty() and offer_scope_cache is Dictionary and (offer_scope_cache as Dictionary).has(cache_key):
		return bool((offer_scope_cache as Dictionary).get(cache_key, false))
	var inside := _offer_is_inside_settlement(offer, settlement_id, actor, settlement_states)
	if not offer_id.is_empty() and offer_scope_cache is Dictionary:
		(offer_scope_cache as Dictionary)[cache_key] = inside
	return inside


func _offer_matches_actor_scope(offer: Dictionary, actor: Node, settlement_id: String, settlement_states = null, offer_scope_cache = null, known_actor_id := "", known_actor_faction := "") -> bool:
	var offer_settlement_id := str(offer.get("settlement_id", ""))
	var actor_id := known_actor_id if not known_actor_id.is_empty() else _actor_id(actor)
	var actor_faction := known_actor_faction if not known_actor_faction.is_empty() else _actor_faction_id(actor)
	var owner_faction := str(offer.get("owner_faction_id", ""))
	var faction_neutral := bool(offer.get("faction_neutral", false))
	if actor_faction.is_empty() or (not faction_neutral and not owner_faction.is_empty() and owner_faction != actor_faction):
		return false
	if not settlement_id.is_empty():
		if not offer_settlement_id.is_empty() and offer_settlement_id != settlement_id:
			return false
		var offer_id := str(offer.get("offer_id", ""))
		var scope_cache_key := "%s:%s:%s" % [settlement_id, actor_id, offer_id]
		var inside_settlement: bool
		if not offer_id.is_empty() and offer_scope_cache is Dictionary and (offer_scope_cache as Dictionary).has(scope_cache_key):
			inside_settlement = bool((offer_scope_cache as Dictionary).get(scope_cache_key, false))
		else:
			inside_settlement = _offer_is_inside_settlement(offer, settlement_id, actor, settlement_states)
			if not offer_id.is_empty() and offer_scope_cache is Dictionary:
				(offer_scope_cache as Dictionary)[scope_cache_key] = inside_settlement
		if not inside_settlement:
			return false
		if not offer_settlement_id.is_empty():
			return true
	if not offer_settlement_id.is_empty():
		return false
	if owner_faction.is_empty() and not faction_neutral:
		return false
	return not settlement_id.is_empty() or _offer_distance(actor, offer) <= DEFAULT_UNSCOPED_LOCAL_WORK_RADIUS


## Jobs follows the town the actor is physically standing in. Permanent town or
## facility assignments remain available to the separate contract AI, but do not
## make autonomous category work pull a party member across the world.
func _local_actor_settlement_id(actor: Node, settlement_states = null) -> String:
	if not (actor is Node3D):
		return ""
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_settlement_states"):
		return _actor_settlement_id(actor)
	var states: Dictionary = settlement_states if settlement_states is Dictionary else bridge.call("get_settlement_states")
	if states.is_empty():
		# Isolated test levels may scope work without bootstrapping a town record.
		return _actor_settlement_id(actor)
	var settlement_controller := _get_settlement_controller()
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
		var anchor = settlement_controller.call("get_settlement_anchor", settlement_id) \
				if settlement_controller != null and settlement_controller.has_method("get_settlement_anchor") else null
		if anchor != null and is_instance_valid(anchor) and anchor.has_method("contains_town_border_position") \
				and bool(anchor.call("contains_town_border_position", actor_position)):
			var anchor_distance := _horizontal_distance(actor_position, (anchor as Node3D).global_position)
			if anchor_distance < best_distance or (is_equal_approx(anchor_distance, best_distance) and settlement_id < best_id):
				best_id = settlement_id
				best_distance = anchor_distance
			continue
		var radius := float(state.get("radius", 0.0))
		if not center is Vector3 or radius <= 0.0:
			continue
		var distance := _horizontal_distance(actor_position, center as Vector3)
		if distance <= radius and (distance < best_distance or (is_equal_approx(distance, best_distance) and settlement_id < best_id)):
			best_id = settlement_id
			best_distance = distance
	return best_id


func _offer_is_inside_settlement(offer: Dictionary, settlement_id: String, actor: Node, settlement_states = null) -> bool:
	var position = offer.get("world_position")
	var settlement_controller := _get_settlement_controller()
	var anchor = settlement_controller.call("get_settlement_anchor", settlement_id) \
			if settlement_controller != null and settlement_controller.has_method("get_settlement_anchor") else null
	if anchor != null and is_instance_valid(anchor) and anchor.has_method("contains_town_border_position") and position is Vector3:
		return bool(anchor.call("contains_town_border_position", position as Vector3))
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_settlement_states"):
		return _offer_distance(actor, offer) <= DEFAULT_UNSCOPED_LOCAL_WORK_RADIUS
	var states: Dictionary = settlement_states if settlement_states is Dictionary else bridge.call("get_settlement_states")
	if states.is_empty():
		return _offer_distance(actor, offer) <= DEFAULT_UNSCOPED_LOCAL_WORK_RADIUS
	var state: Dictionary = states.get(settlement_id, {})
	var center = state.get("world_position")
	var radius := float(state.get("radius", 0.0))
	return center is Vector3 and position is Vector3 and radius > 0.0 \
			and _horizontal_distance(center as Vector3, position as Vector3) <= radius


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _get_settlement_controller() -> Node:
	if _settlement_controller == null and _context != null:
		_settlement_controller = _context.get_optional(&"settlement")
	return _settlement_controller


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
	var script = object.get_script()
	var shape_id := str((script as Script).resource_path) if script is Script and not (script as Script).resource_path.is_empty() else object.get_class()
	var cache_key := "%s|%s" % [shape_id, property_name]
	if _property_presence_cache.has(cache_key):
		return bool(_property_presence_cache[cache_key])
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			_property_presence_cache[cache_key] = true
			return true
	_property_presence_cache[cache_key] = false
	return false


func _get_gecs_world() -> Node:
	return _context.get_optional(GECS_SERVICE_ID) if _context != null else null
