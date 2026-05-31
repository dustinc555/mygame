extends SceneTree

const AI_BRAIN_SCRIPT := preload("res://scripts/ai/ai_brain.gd")
const AI_JOB_SCRIPT := preload("res://scripts/ai/ai_job.gd")
const AI_ASSIGNED_WORK_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_assigned_work_step.gd")
const AI_START_ACTIVITY_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_start_activity_step.gd")
const AI_WAIT_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_wait_step.gd")
const AI_RELEASE_ACTIVITY_STEP_SCRIPT := preload("res://scripts/ai/steps/ai_release_activity_step.gd")
const GECS_WORLD_CONTROLLER_SCRIPT := preload("res://scripts/controllers/gecs_world_controller.gd")
const POPULATION_CONTROLLER_SCRIPT := preload("res://scripts/controllers/population_controller.gd")
const ACTOR_QUERY_CONTROLLER_SCRIPT := preload("res://scripts/controllers/actor_query_controller.gd")
const AI_SCHEDULER_CONTROLLER_SCRIPT := preload("res://scripts/controllers/ai_scheduler_controller.gd")
const POPULATION_REALIZATION_CONTROLLER_SCRIPT := preload("res://scripts/controllers/population_realization_controller.gd")

var _failures: Array[String] = []


class FakeHumanoid:
	extends CharacterBody3D

	var stable_id := ""
	var member_name := "Fake Actor"
	var faction_name := "TestFaction"
	var squad_name := "TestSquad"
	var hostile_factions: PackedStringArray = PackedStringArray()
	var combat_stance := NpcRules.CombatStance.DEFENSIVE
	var auto_heal_enabled := false
	var auto_burn_rustdead_enabled := false
	var life_state := NpcRules.LifeState.ALIVE
	var appearance_data: Resource
	var equipped_items: Dictionary = {}
	var starting_equipment: Array[Resource] = []
	var starting_skill_levels: Dictionary = {}
	var inventory: InventoryData = InventoryData.new(4, 4, 0.0, false)
	var active_job_provider: Node
	var player_party_member := false

	func assign_attack_target(_target = null) -> void:
		pass

	func get_active_job_provider():
		return active_job_provider

	func is_player_party_member() -> bool:
		return player_party_member


class FakeProvider:
	extends Node

	var ticks := 0

	func tick_worker_job_from_ai(_worker, _delta: float, _job = null) -> Dictionary:
		ticks += 1
		return {"active": true, "ended": false, "blocker": ""}


class FakeFailingProvider:
	extends Node

	func tick_worker_job_from_ai(_worker, _delta: float, _job = null) -> Dictionary:
		return {"active": false, "ended": true, "failed": true, "blocker": "Invalid test assignment"}


class FakePartyManager:
	extends Node

	var party_members: Array = []


class FakeActivityPoint:
	extends Node

	var begun := 0
	var ended := 0

	func begin_ai_activity(_actor: Node, _job = null) -> bool:
		begun += 1
		return true

	func end_ai_activity(_actor: Node, _job = null) -> void:
		ended += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_population_records_and_ledger()
	_validate_dense_population_indexes_and_batches()
	_validate_actor_query_indexes()
	_validate_ai_scheduler()
	_validate_protected_job_replacement()
	_validate_assigned_work_ai_step()
	_validate_activity_job_cancellation()
	_validate_malformed_ai_step_failure()
	_validate_realization_policy()
	if _failures.is_empty():
		print("AI_POPULATION_ARCHITECTURE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("AI_POPULATION_ARCHITECTURE_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_population_records_and_ledger() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	_add_gecs_bridge(root_node)
	var population = POPULATION_CONTROLLER_SCRIPT.new()
	root_node.add_child(population)
	population.initialize(root_node)
	var actor := FakeHumanoid.new()
	actor.name = "AuthoredWorker"
	root_node.add_child(actor)
	var record: Dictionary = population.register_actor(actor, "test_town", {"role_id": "worker"})
	if str(record.get("actor_id", "")).is_empty() or actor.stable_id.is_empty():
		_fail("PopulationController should assign persistent actor IDs to authored actors")
	if not actor.has_meta("settlement_id") or str(actor.get_meta("actor_role_id")) != "worker":
		_fail("PopulationController should stamp settlement and role metadata for query indexes")
	actor.set_meta("settlement_staff_role", "guard")
	record = population.register_actor(actor, "test_town")
	if str(record.get("role_id", "")) != "guard" or str(actor.get_meta("actor_role_id", "")) != "guard":
		_fail("PopulationController should update actor records when residents become staff roles")
	population.unregister_actor(actor)
	var summary: Dictionary = population.get_population_summary()
	if int(summary.get("ledger_records", 0)) < 1:
		_fail("Unregistered persistent actors should remain as ledger records")
	var generated: Array = population.ensure_generated_population("test_town", "resident", 3, {"role_id": "resident", "faction_id": "TestFaction"})
	if generated.size() != 3:
		_fail("Generated population should create deterministic actor records")
	var generated_guard: Array = population.ensure_generated_population("test_town", "guard", 1, {"role_id": "guard", "faction_id": "TestFaction", "auto_heal_enabled": true, "auto_burn_rustdead_enabled": true})
	if generated_guard.is_empty() or not bool((generated_guard[0] as Dictionary).get("auto_heal_enabled", false)) or not bool((generated_guard[0] as Dictionary).get("auto_burn_rustdead_enabled", false)):
		_fail("Generated population should persist guard auto-heal and auto-burn flags")
	else:
		var realized_guard := FakeHumanoid.new()
		root_node.add_child(realized_guard)
		population.apply_record_to_actor(realized_guard, generated_guard[0] as Dictionary)
		if not realized_guard.auto_heal_enabled or not realized_guard.auto_burn_rustdead_enabled:
			_fail("Population records should apply guard auto-heal and auto-burn flags to realized actors")
	var trimmed: Array = population.ensure_generated_population("test_town", "resident", 1, {"role_id": "resident", "faction_id": "TestFaction"})
	if trimmed.size() != 1:
		_fail("Generated population should trim surplus records when desired count shrinks")
	var worker_id := str(record.get("actor_id", ""))
	population.update_actor_record(worker_id, {"realization_state": "ledger", "role_id": "worker"})
	var ledger: Dictionary = population.advance_ledger_minutes(60, 12 * 60)
	if int(ledger.get("updated_actor_count", 0)) < 1:
		_fail("Ledger advancement should update non-realized actor records")
	if not str(ledger.get("batches", {})).contains("working"):
		_fail("Ledger advancement should batch actors by settlement, role, and activity")
	var serialized: Dictionary = population.serialize_state()
	var serialized_records: Dictionary = serialized.get("actor_records", {})
	for serialized_record in serialized_records.values():
		if serialized_record is Dictionary and (serialized_record as Dictionary).has("live_node_path"):
			_fail("PopulationController serialized state should not persist live node paths")
			break
	var restored = POPULATION_CONTROLLER_SCRIPT.new()
	root_node.add_child(restored)
	restored.apply_serialized_state(serialized)
	if int(restored.get_population_summary().get("total_records", 0)) != int(population.get_population_summary().get("total_records", 0)):
		_fail("PopulationController should round-trip serialized actor records")
	root_node.queue_free()


func _validate_actor_query_indexes() -> void:
	var root_node := Node.new()
	root.add_child(root_node)
	_add_gecs_bridge(root_node)
	var query = ACTOR_QUERY_CONTROLLER_SCRIPT.new()
	query.add_to_group("actor_query_controller")
	root_node.add_child(query)
	var actor := FakeHumanoid.new()
	actor.stable_id = "actor.indexed"
	actor.faction_name = "IndexedFaction"
	actor.set_meta("settlement_id", "indexed_town")
	actor.set_meta("actor_role_id", "guard")
	root_node.add_child(actor)
	query.register_actor(actor)
	if query.get_actor_by_stable_id("actor.indexed") != actor:
		_fail("ActorQueryController should find actors by stable ID")
	if query.get_alive_humanoids_for_settlement("indexed_town", true).size() != 1:
		_fail("ActorQueryController should index actors by settlement")
	if query.get_alive_humanoids_for_role("guard", true).size() != 1:
		_fail("ActorQueryController should index actors by role")
	if query.get_alive_humanoids_for_faction("IndexedFaction", true).size() != 1:
		_fail("ActorQueryController should index actors by faction")
	var population = POPULATION_CONTROLLER_SCRIPT.new()
	root_node.add_child(population)
	var unstamped_actor := FakeHumanoid.new()
	unstamped_actor.name = "BootOrderedActor"
	unstamped_actor.faction_name = "BootFaction"
	root_node.add_child(unstamped_actor)
	query.register_actor(unstamped_actor)
	var boot_record: Dictionary = population.register_actor(unstamped_actor, "boot_town", {"role_id": "worker"})
	var boot_actor_id := str(boot_record.get("actor_id", ""))
	if boot_actor_id.is_empty() or query.get_actor_by_stable_id(boot_actor_id) != unstamped_actor:
		_fail("PopulationController should reindex actors after assigning stable IDs")
	if query.get_alive_humanoids_for_settlement("boot_town", true).size() != 1:
		_fail("PopulationController should refresh settlement query indexes after stamping metadata")
	if query.get_alive_humanoids_for_role("worker", true).size() != 1:
		_fail("PopulationController should refresh role query indexes after stamping metadata")
	population.unregister_actor(unstamped_actor)
	if query.get_actor_by_stable_id(boot_actor_id) != null:
		_fail("PopulationController.unregister_actor should remove actors from ActorQueryController indexes")
	query.unregister_actor(actor)
	query.unregister_actor(unstamped_actor)
	root_node.queue_free()


func _validate_dense_population_indexes_and_batches() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	_add_gecs_bridge(root_node)
	var population = POPULATION_CONTROLLER_SCRIPT.new()
	root_node.add_child(population)
	population.initialize(root_node)
	var dense_records: Array = population.ensure_generated_population("dense_town", "worker", 125, {"role_id": "worker", "faction_id": "DenseFaction"})
	if dense_records.size() != 125:
		_fail("Dense population validation should create at least 100 persistent records")
	var ledger: Dictionary = population.advance_ledger_minutes(30, 9 * 60)
	if int(ledger.get("updated_actor_count", 0)) != 125:
		_fail("Dense ledger simulation should batch-update every unloaded actor record")
	var batches: Dictionary = ledger.get("batches", {})
	if batches.size() != 1:
		_fail("Dense ledger simulation should aggregate matching unloaded actors into one batch")
	else:
		var batch: Dictionary = batches.values()[0]
		if int(batch.get("actor_count", 0)) != 125 or str(batch.get("activity", "")) != "working":
			_fail("Dense ledger batch should summarize worker count and activity")
	var query = ACTOR_QUERY_CONTROLLER_SCRIPT.new()
	root_node.add_child(query)
	var live_actors: Array[FakeHumanoid] = []
	for index in range(125):
		var actor := FakeHumanoid.new()
		actor.stable_id = "dense.actor.%03d" % index
		actor.faction_name = "DenseFaction"
		actor.set_meta("settlement_id", "dense_town")
		actor.set_meta("actor_role_id", "worker")
		root_node.add_child(actor)
		query.register_actor(actor)
		live_actors.append(actor)
	if query.get_alive_humanoids_for_settlement("dense_town", false).size() != 125:
		_fail("Dense actor query should return indexed settlement residents without broad scene scans")
	if query.get_alive_humanoids_for_role("worker", false).size() != 125:
		_fail("Dense actor query should return indexed role residents")
	if query.get_alive_humanoids_for_faction("DenseFaction", false).size() != 125:
		_fail("Dense actor query should return indexed faction residents")
	query.unregister_actor(live_actors[0])
	if query.get_alive_humanoids_for_settlement("dense_town", false).size() != 124:
		_fail("Dense actor query indexes should update when a live actor unregisters")
	root_node.queue_free()


func _validate_ai_scheduler() -> void:
	var root_node := Node.new()
	root.add_child(root_node)
	_add_gecs_bridge(root_node)
	var scheduler = AI_SCHEDULER_CONTROLLER_SCRIPT.new()
	root_node.add_child(scheduler)
	scheduler.initialize(root_node)
	var actor := FakeHumanoid.new()
	actor.stable_id = "actor.scheduled"
	root_node.add_child(actor)
	if not bool(scheduler.should_tick_actor(actor, 1.0, 0.0)):
		_fail("AiSchedulerController should allow the first actor tick")
	if bool(scheduler.should_tick_actor(actor, 1.0, 0.0)):
		_fail("AiSchedulerController should suppress ticks until the scheduled time")
	scheduler.apply_serialized_state({"sim_time": 12.0})
	if not bool(scheduler.should_tick_actor(actor, 1.0, 0.0)):
		_fail("AiSchedulerController apply state should reset volatile schedules")
	root_node.queue_free()


func _validate_protected_job_replacement() -> void:
	var actor := FakeHumanoid.new()
	root.add_child(actor)
	var brain = AI_BRAIN_SCRIPT.new()
	brain.setup(actor)
	var protected_job = AI_JOB_SCRIPT.new()
	protected_job.job_type = AI_JOB_SCRIPT.JobType.AMBIENT_ACTIVITY
	protected_job.priority = AI_JOB_SCRIPT.priority_for_type(protected_job.job_type)
	protected_job.interrupt_policy = AI_JOB_SCRIPT.InterruptPolicy.PROTECTED
	if not brain.request_job(protected_job):
		_fail("AiBrain should accept protected jobs")
	var higher_priority_job = AI_JOB_SCRIPT.new()
	higher_priority_job.job_type = AI_JOB_SCRIPT.JobType.PLAYER_MOVE
	higher_priority_job.priority = AI_JOB_SCRIPT.priority_for_type(higher_priority_job.job_type)
	if brain.request_job(higher_priority_job):
		_fail("AiJob replacement should respect protected interrupt policy")
	if int(brain.get_debug_snapshot().get("active_job", {}).get("job_type", -1)) != AI_JOB_SCRIPT.JobType.AMBIENT_ACTIVITY:
		_fail("Protected job should remain active after rejected replacement")
	actor.queue_free()


func _validate_assigned_work_ai_step() -> void:
	var actor := FakeHumanoid.new()
	var provider := FakeProvider.new()
	root.add_child(actor)
	root.add_child(provider)
	actor.active_job_provider = provider
	var brain = AI_BRAIN_SCRIPT.new()
	brain.setup(actor)
	var job = AI_JOB_SCRIPT.new()
	job.job_type = AI_JOB_SCRIPT.JobType.ASSIGNED_WORK
	job.priority = AI_JOB_SCRIPT.priority_for_type(job.job_type)
	job.source_id = "job_provider"
	job.source = provider
	job.target = provider
	job.steps = [AI_ASSIGNED_WORK_STEP_SCRIPT.new()]
	if not brain.request_job(job):
		_fail("AiBrain should accept assigned work jobs")
	brain.tick(0.25)
	if provider.ticks != 1:
		_fail("Assigned work AI step should tick the provider through AiBrain")
	var failing_provider := FakeFailingProvider.new()
	root.add_child(failing_provider)
	actor.active_job_provider = failing_provider
	var failing_brain = AI_BRAIN_SCRIPT.new()
	failing_brain.setup(actor)
	var failing_job = AI_JOB_SCRIPT.new()
	failing_job.job_type = AI_JOB_SCRIPT.JobType.ASSIGNED_WORK
	failing_job.priority = AI_JOB_SCRIPT.priority_for_type(failing_job.job_type)
	failing_job.source_id = "job_provider"
	failing_job.source = failing_provider
	failing_job.target = failing_provider
	failing_job.steps = [AI_ASSIGNED_WORK_STEP_SCRIPT.new()]
	failing_brain.request_job(failing_job)
	failing_brain.tick(0.25)
	var completed: Dictionary = failing_brain.get_debug_snapshot().get("last_completed_job", {})
	if int(completed.get("status", -1)) != AI_JOB_SCRIPT.JobStatus.FAILED:
		_fail("Assigned work AI step should preserve provider failure state")
	actor.queue_free()
	provider.queue_free()
	failing_provider.queue_free()


func _validate_activity_job_cancellation() -> void:
	var actor := FakeHumanoid.new()
	var point := FakeActivityPoint.new()
	root.add_child(actor)
	root.add_child(point)
	var brain = AI_BRAIN_SCRIPT.new()
	brain.setup(actor)
	var job = AI_JOB_SCRIPT.new()
	job.job_type = AI_JOB_SCRIPT.JobType.AMBIENT_ACTIVITY
	job.priority = AI_JOB_SCRIPT.priority_for_type(job.job_type)
	job.source_id = "settlement_activity"
	job.target = point
	var wait_step = AI_WAIT_STEP_SCRIPT.new()
	wait_step.setup(60.0, "Hold Activity")
	job.steps = [AI_START_ACTIVITY_STEP_SCRIPT.new(), wait_step, AI_RELEASE_ACTIVITY_STEP_SCRIPT.new()]
	if not brain.request_job(job):
		_fail("AiBrain should accept ambient activity jobs")
	brain.tick(0.1)
	if point.begun != 1:
		_fail("Ambient activity job should begin through activity contract")
	brain.clear_active_job()
	if point.ended != 1:
		_fail("Cancelling an ambient activity job should release the activity target")
	actor.queue_free()
	point.queue_free()


func _validate_malformed_ai_step_failure() -> void:
	var actor := FakeHumanoid.new()
	root.add_child(actor)
	var brain = AI_BRAIN_SCRIPT.new()
	brain.setup(actor)
	var job = AI_JOB_SCRIPT.new()
	job.job_type = AI_JOB_SCRIPT.JobType.AMBIENT_ACTIVITY
	job.priority = AI_JOB_SCRIPT.priority_for_type(job.job_type)
	var invalid_step := Node.new()
	job.steps = [invalid_step]
	if not brain.request_job(job):
		_fail("AiBrain should accept malformed jobs so the driver can fail them safely")
	brain.tick(0.1)
	var snapshot: Dictionary = brain.get_debug_snapshot()
	var completed: Dictionary = snapshot.get("last_completed_job", {})
	if int(completed.get("status", -1)) != AI_JOB_SCRIPT.JobStatus.FAILED:
		_fail("Malformed AI job steps should fail safely instead of crashing")
	invalid_step.free()
	actor.queue_free()


func _validate_realization_policy() -> void:
	var root_node := Node.new()
	root.add_child(root_node)
	_add_gecs_bridge(root_node)
	var party_manager := FakePartyManager.new()
	party_manager.name = "PartyManager"
	root_node.add_child(party_manager)
	var party_actor := Node3D.new()
	root_node.add_child(party_actor)
	party_actor.global_position = Vector3.ZERO
	party_manager.party_members = [party_actor]
	var realization = POPULATION_REALIZATION_CONTROLLER_SCRIPT.new()
	root_node.add_child(realization)
	realization.initialize(root_node)
	realization.default_realization_policy = "near_player"
	realization.near_player_radius = 10.0
	if not bool(realization.should_realize_actor(null, {"last_world_position": Vector3(5.0, 0.0, 0.0)})):
		_fail("near_player realization should realize nearby actor records")
	if bool(realization.should_realize_actor(null, {"last_world_position": Vector3(50.0, 0.0, 0.0)})):
		_fail("near_player realization should keep far actor records in ledger")
	realization.default_realization_policy = "important_plus_near"
	if not bool(realization.should_realize_actor(null, {"role_id": "guard", "last_world_position": Vector3(50.0, 0.0, 0.0)})):
		_fail("important_plus_near realization should realize important roles")
	root_node.queue_free()


func _fail(message: String) -> void:
	_failures.append(message)


func _add_gecs_bridge(parent: Node) -> Node:
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	parent.add_child(bridge)
	bridge.call("initialize", parent)
	return bridge
