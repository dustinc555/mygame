extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_generic_assignment_work_performance.gd

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
	var query_count := 0
	var probe_count := 0
	var accepted_count := 0
	func get_available_work_offers(_settlement_id := "") -> Array:
		query_count += 1
		var offers: Array = []
		for index in 300:
			offers.append({"offer_id": "work:%d" % index, "category": "crafting", "job_entry_id": "category:crafting", "settlement_id": "town", "owner_faction_id": "Player", "world_position": Vector3(float(index), 0, 0), "provider": self})
		return offers
	func can_actor_accept_work_offer(_offer: Dictionary, _actor: Node) -> bool:
		probe_count += 1
		return false
	func accept_work_offer(_offer: Dictionary, _actor: Node) -> Dictionary:
		accepted_count += 1
		return {"accepted": true}
	func has_active_work_for_actor(_actor: Node) -> bool: return false

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
	_expect(provider.query_count == 1, "one offer snapshot serves all assignment workers")
	_expect(provider.probe_count <= 16 * 24, "each assignment actor probes a bounded offer slice")
	_expect(provider.accepted_count <= 16, "assignment dispatch is frame-budgeted")
	_expect(jobs._assignment_actor_cursor > 0, "assignment dispatch advances a fair round-robin cursor")
	scene_root.queue_free(); _finish()
func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("GENERIC_ASSIGNMENT_WORK_PERFORMANCE_OK"); quit(0); return
	for failure in failures: push_error(failure)
	print("GENERIC_ASSIGNMENT_WORK_PERFORMANCE_FAILED count=%d" % failures.size()); quit(1)
