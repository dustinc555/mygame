extends "res://tests/validation/test_case.gd"
## Run: python3 tests/run_validation.py --jobs 1 --filter tests/validation/validate_generic_assignment_work_performance.gd

const JOB_SYSTEM := preload("res://features/settlements/sim/job_system_controller.gd")

class FakeGecs:
	extends Node
	func get_job_system_state() -> Dictionary: return {}
	func upsert_job_system_state(state: Dictionary) -> Dictionary: return state
	func get_actor_job_contracts(_actor: Node) -> Array: return []
	func get_settlement_states() -> Dictionary:
		return {"town": {"settlement_id": "town", "faction_id": "Player", "world_position": Vector3.ZERO, "radius": 1000.0}}

class FakePopulation:
	extends Node
	var actors: Dictionary = {}
	func get_live_actor(actor_id: String): return actors.get(actor_id)
	func get_actor_record(_actor_id: String) -> Dictionary: return {}

class FakeActor:
	extends Node3D
	var stable_id := ""
	var faction_name := "Player"
	var life_state := 0
	func is_player_party_member() -> bool: return false
	func has_active_player_order() -> bool: return false
	func get_active_job_provider(): return null

class FakeProvider:
	extends Node3D
	signal work_offer_delta(settlement_id: String, removed_offer_ids: PackedStringArray, upserted_offers: Array)
	var query_count := 0
	var probe_count := 0
	var accepted_count := 0
	var accepting := false
	func get_available_work_offers(_settlement_id := "") -> Array:
		query_count += 1
		var offers: Array = []
		for index in 300:
			offers.append({"offer_id": "work:%d" % index, "category": "crafting", "job_entry_id": "category:crafting", "settlement_id": "town", "owner_faction_id": "Player", "world_position": Vector3(float(index), 0, 0), "provider": self})
		return offers
	func can_actor_accept_work_offer(_offer: Dictionary, _actor: Node) -> bool:
		probe_count += 1
		return accepting
	func accept_work_offer(_offer: Dictionary, _actor: Node) -> Dictionary:
		accepted_count += 1
		return {"accepted": true}
	func has_active_work_for_actor(_actor: Node) -> bool: return false
	func emit_delta() -> void:
		work_offer_delta.emit("town", PackedStringArray(["work:0"]), [{"offer_id": "work:new", "category": "crafting", "job_entry_id": "category:crafting", "settlement_id": "town", "owner_faction_id": "Player", "world_position": Vector3.ZERO, "provider": self}])

var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var scene_root := Node.new(); root.add_child(scene_root)
	var context := BootstrapContext.new(scene_root)
	var gecs := FakeGecs.new(); scene_root.add_child(gecs); context.register(&"gecs_world", gecs)
	var population := FakePopulation.new(); scene_root.add_child(population); context.register(&"population", population)
	var provider := FakeProvider.new(); scene_root.add_child(provider); provider.add_to_group("job_provider")
	var jobs = JOB_SYSTEM.new(); scene_root.add_child(jobs); context.register(&"job_system", jobs); jobs.initialize(context); jobs.register_job_provider(provider)
	for index in 300:
		var actor := FakeActor.new(); actor.stable_id = "worker:%d" % index; scene_root.add_child(actor); population.actors[actor.stable_id] = actor
		jobs._assignment_workers[actor.stable_id] = {"actor_id": actor.stable_id, "settlement_id": "town", "facility_id": "facility:%d" % index, "allowed_job_entry_ids": PackedStringArray(), "schedule_enabled": false, "idle_projection_active": false}
		jobs._assignment_actor_order.append(actor.stable_id)
	jobs._process_party_job_dispatch()
	_expect(provider.query_count == 0, "idle assignment workers must cost zero provider reads until an offer change queues them")
	for actor_id in population.actors:
		jobs.call("_queue_assignment_worker", str(actor_id))
	jobs._process_party_job_dispatch()
	_expect(provider.query_count == 1, "one offer snapshot serves all assignment workers")
	_expect(provider.probe_count <= 16 * 24, "each queued assignment actor probes a bounded offer slice")
	# Time-budget yields need not fill the count cap; still require progress
	# every tick and a finite drain with at least one actor per tick.
	for _frame in 300:
		if jobs._pending_assignment_actor_ids.is_empty():
			break
		var pending_before: int = jobs._pending_assignment_actor_ids.size()
		jobs._process_party_job_dispatch()
		_expect(jobs._pending_assignment_actor_ids.size() < pending_before, "every nonempty dispatch makes progress")
	_expect(provider.query_count == 1, "one provider snapshot serves the complete bounded event burst")
	_expect(jobs._pending_assignment_actor_ids.is_empty(), "complete event burst drains every pending worker")
	_expect(provider.accepted_count == 0, "rejecting provider accepts no worker")
	var probes_after_event := provider.probe_count
	jobs._process_party_job_dispatch()
	_expect(provider.query_count == 1 and provider.probe_count == probes_after_event, "failed/no-work assignment workers sleep until another offer event")
	jobs.call("notify_work_offers_changed", "town")
	jobs._process_party_job_dispatch()
	_expect(provider.query_count == 2, "provider change wakes relevant idle assignment workers once")
	for _frame in 300:
		if jobs._pending_assignment_actor_ids.is_empty(): break
		jobs._process_party_job_dispatch()
	var probes_before_delta := provider.probe_count
	provider.emit_delta()
	jobs._process_party_job_dispatch()
	_expect(provider.query_count == 2 and provider.probe_count > probes_before_delta, "single-offer deltas wake workers without rebuilding the provider snapshot")
	var town_index: Dictionary = jobs._assignment_offer_index_cache.get("town", {})
	_expect((town_index.get("all", []) as Array).size() == 300, "single-offer deltas preserve every untouched indexed offer")
	for _frame in 300:
		if jobs._pending_assignment_actor_ids.is_empty(): break
		jobs._process_party_job_dispatch()
	_expect(jobs._pending_assignment_actor_ids.is_empty(), "delta event burst drains pending workers")
	provider.accepting = true
	provider.emit_delta()
	jobs._process_party_job_dispatch()
	_expect(provider.accepted_count > 0 and provider.accepted_count <= 16, "eligible offers start work within the dispatch budget")
	_expect(provider.query_count == 2, "positive delta dispatch reuses the existing provider snapshot")
	scene_root.free(); _finish()
func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("GENERIC_ASSIGNMENT_WORK_PERFORMANCE_OK"); quit(0); return
	for failure in failures: push_error(failure)
	print("GENERIC_ASSIGNMENT_WORK_PERFORMANCE_FAILED count=%d" % failures.size()); quit(1)
