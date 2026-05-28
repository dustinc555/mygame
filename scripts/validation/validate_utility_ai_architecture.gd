extends SceneTree

const AI_UTILITY_CONTEXT_SCRIPT := preload("res://scripts/ai/utility/ai_utility_context.gd")
const AI_UTILITY_GOAL_SELECTOR_SCRIPT := preload("res://scripts/ai/utility/ai_utility_goal_selector.gd")
const AI_UTILITY_ADAPTER_SCRIPT := preload("res://scripts/ai/utility/ai_utility_adapter.gd")
const AI_UTILITY_PROFILE := preload("res://resources/ai/utility_profiles/default_humanoid.tres")
const AI_JOB_SCRIPT := preload("res://scripts/ai/ai_job.gd")
const GECS_WORLD_CONTROLLER_SCRIPT := preload("res://scripts/controllers/gecs_world_controller.gd")
const JOB_PROVIDER_SCRIPT := preload("res://scripts/jobs/job_provider.gd")
const JOB_DEFINITION_SCRIPT := preload("res://scripts/jobs/job_definition.gd")
const HUMANOID_CHARACTER_SCRIPT := preload("res://scripts/characters/humanoid_character.gd")

var _failures: Array[String] = []


class FakeUtilityActor:
	extends CharacterBody3D

	var stable_id := "utility.actor"
	var member_name := "Utility Actor"
	var faction_name := "UtilityFaction"
	var squad_name := "UtilitySquad"
	var hostile_factions: PackedStringArray = PackedStringArray()
	var combat_stance := NpcRules.CombatStance.DEFENSIVE
	var life_state := NpcRules.LifeState.ALIVE
	var hp := 100.0
	var max_hp := 100.0
	var blood := 100.0
	var max_blood := 100.0
	var player_party_member := false
	var equipped_items: Dictionary = {}
	var active_job_provider: Node
	var attack_candidate: Node
	var heal_candidate: Node
	var assigned_attack_target: Node
	var assigned_heal_target: Node
	var requested_jobs: Array = []
	var active_job_source_id := ""
	var active_job_id := ""
	var _order_was_player_issued := false
	var _current_order_type := 0
	var _current_heal_target: Node

	func is_player_party_member() -> bool:
		return player_party_member

	func get_active_job_provider():
		return active_job_provider

	func has_active_ai_job_from_source(source_id: String) -> bool:
		return not active_job_source_id.is_empty() and active_job_source_id == source_id

	func request_ai_job(job) -> bool:
		if job == null:
			return false
		requested_jobs.append(job)
		active_job_source_id = str(job.source_id)
		active_job_id = str(job.job_id)
		return true

	func cancel_ai_job(source_id := "") -> void:
		if source_id.is_empty() or source_id == active_job_source_id:
			active_job_source_id = ""
			active_job_id = ""

	func get_ai_debug_snapshot() -> Dictionary:
		return {
			"has_active_job": not active_job_id.is_empty(),
			"active_job": {
				"job_id": active_job_id,
				"source_id": active_job_source_id,
			},
		}

	func _get_active_combat_target():
		return null

	func _should_seek_combat_target() -> bool:
		return attack_candidate != null

	func _find_ai_target():
		return attack_candidate

	func assign_attack_target(target, _issued_by_player := false, _notify_target := true, _notify_allies := true) -> void:
		assigned_attack_target = target

	func _should_seek_auto_heal_target() -> bool:
		return heal_candidate != null

	func _find_auto_heal_target():
		return heal_candidate

	func assign_heal_target(target, _issued_by_player := false) -> void:
		assigned_heal_target = target
		_current_heal_target = target


class FakeProvider:
	extends Node

	var started_contract_id := ""
	var started_contract_count := 0
	var actionable_by_job_id: Dictionary = {}

	func tick_worker_job_from_ai(_worker, _delta: float, _job = null) -> Dictionary:
		return {"active": true, "ended": false, "blocker": ""}

	func get_provider_name() -> String:
		return "Utility Provider"

	func start_contract_shift(_worker, contract: Dictionary):
		started_contract_id = str(contract.get("contract_id", ""))
		started_contract_count += 1
		var job = AI_JOB_SCRIPT.new()
		job.job_type = AI_JOB_SCRIPT.JobType.ASSIGNED_WORK
		job.priority = AI_JOB_SCRIPT.priority_for_type(job.job_type)
		job.job_id = started_contract_id
		job.source_id = "job_provider"
		job.target = self
		job.target_id = str(get_path()) if is_inside_tree() else str(get_instance_id())
		job.package_id = "assigned_work:%s" % str(contract.get("algorithm_id", "contract"))
		return job

	func get_contract_work_status(_worker, contract: Dictionary) -> Dictionary:
		var job_id := str(contract.get("job_id", ""))
		return {"actionable": bool(actionable_by_job_id.get(job_id, true)), "reason": "validation status"}


class FakeMineNode:
	extends Node3D

	var display_name := "Validation Ore"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_goal_selection()
	_validate_lock_and_cooldown()
	_validate_adapter_and_gecs_intent()
	_validate_job_contract_order_and_quit()
	_validate_dialogue_accept_creates_job_contract()
	_validate_no_show_contract_expiration()
	_validate_contract_driven_work_objective()
	_validate_contract_work_not_restarted_when_active()
	_validate_contract_actionability_priority()
	if _failures.is_empty():
		print("UTILITY_AI_ARCHITECTURE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("UTILITY_AI_ARCHITECTURE_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_goal_selection() -> void:
	var selector = AI_UTILITY_GOAL_SELECTOR_SCRIPT.new()
	var threat_context := _base_context()
	var threat := Node3D.new()
	threat_context.set_fact(&"threat", 1.0)
	threat_context.set_fact(&"can_self_defend", 1.0)
	threat_context.set_targets(&"combat_target", [_candidate(threat, 1.0)])
	var threat_decision = selector.decide(threat_context, AI_UTILITY_PROFILE)
	if threat_decision.selected_goal_id != &"self_defense":
		_fail("Utility selector should choose self_defense when a threat is available")

	var heal_context := _base_context()
	var patient := Node3D.new()
	heal_context.set_fact(&"heal_need", 0.85)
	heal_context.set_targets(&"heal_target", [_candidate(patient, 0.85)])
	var heal_decision = selector.decide(heal_context, AI_UTILITY_PROFILE)
	if heal_decision.selected_goal_id != &"heal":
		_fail("Utility selector should choose heal when medical need is highest")

	var work_context := _base_context()
	var provider := FakeProvider.new()
	work_context.set_fact(&"assigned_work_available", 1.0)
	work_context.set_targets(&"work_provider", [_candidate(provider, 1.0)])
	var work_decision = selector.decide(work_context, AI_UTILITY_PROFILE)
	if work_decision.selected_goal_id != &"assigned_work":
		_fail("Utility selector should choose assigned_work when a provider is available")

	var idle_context := _base_context()
	var idle_decision = selector.decide(idle_context, AI_UTILITY_PROFILE)
	if idle_decision.selected_goal_id != &"wander":
		_fail("Utility selector should fall back to wander when no stronger goal exists")

	threat.free()
	patient.free()
	provider.free()


func _validate_lock_and_cooldown() -> void:
	var selector = AI_UTILITY_GOAL_SELECTOR_SCRIPT.new()
	var locked_context := _base_context()
	var provider := FakeProvider.new()
	var patient := Node3D.new()
	locked_context.current_goal_id = &"assigned_work"
	locked_context.current_goal_lock_until = 10.0
	locked_context.sim_time = 1.0
	locked_context.set_fact(&"assigned_work_available", 1.0)
	locked_context.set_fact(&"heal_need", 0.9)
	locked_context.set_targets(&"work_provider", [_candidate(provider, 1.0)])
	locked_context.set_targets(&"heal_target", [_candidate(patient, 0.9)])
	var locked_decision = selector.decide(locked_context, AI_UTILITY_PROFILE)
	if locked_decision.selected_goal_id != &"assigned_work":
		_fail("Utility selector should respect locks for non-emergency goals")

	var emergency_context := _base_context()
	var threat := Node3D.new()
	emergency_context.current_goal_id = &"assigned_work"
	emergency_context.current_goal_lock_until = 10.0
	emergency_context.sim_time = 1.0
	emergency_context.set_fact(&"assigned_work_available", 1.0)
	emergency_context.set_fact(&"threat", 1.0)
	emergency_context.set_fact(&"can_self_defend", 1.0)
	emergency_context.set_targets(&"work_provider", [_candidate(provider, 1.0)])
	emergency_context.set_targets(&"combat_target", [_candidate(threat, 1.0)])
	var emergency_decision = selector.decide(emergency_context, AI_UTILITY_PROFILE)
	if emergency_decision.selected_goal_id != &"self_defense":
		_fail("Utility selector should allow emergency goals to break locks")

	var cooldown_context := _base_context()
	cooldown_context.sim_time = 1.0
	cooldown_context.goal_cooldowns[&"heal"] = 10.0
	cooldown_context.set_fact(&"heal_need", 1.0)
	cooldown_context.set_targets(&"heal_target", [_candidate(patient, 1.0)])
	var cooldown_decision = selector.decide(cooldown_context, AI_UTILITY_PROFILE)
	if cooldown_decision.selected_goal_id == &"heal":
		_fail("Utility selector should suppress non-current goals that are on cooldown")

	provider.free()
	patient.free()
	threat.free()


func _validate_adapter_and_gecs_intent() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	root_node.add_child(bridge)
	bridge.initialize(root_node)
	var actor := FakeUtilityActor.new()
	actor.stable_id = "utility.actor.adapter"
	root_node.add_child(actor)
	var threat := FakeUtilityActor.new()
	threat.stable_id = "utility.actor.threat"
	threat.position = Vector3(2.0, 0.0, 0.0)
	root_node.add_child(threat)
	bridge.register_actor(actor)
	bridge.register_actor(threat)
	actor.attack_candidate = threat
	var adapter = AI_UTILITY_ADAPTER_SCRIPT.new()
	adapter.setup(AI_UTILITY_PROFILE)
	if not adapter.run_actor_decision(actor):
		_fail("Utility adapter should realize a self-defense decision through the actor handoff")
	if actor.assigned_attack_target != threat:
		_fail("Utility adapter should call the existing combat assignment handoff")
	var intent: Dictionary = bridge.get_actor_goal_intent(actor, false)
	if str(intent.get("goal_id", "")) != "self_defense":
		_fail("Utility adapter should write selected goal intent to GECS")
	if intent.has("full_debug_breakdown"):
		_fail("GECS goal intent should not persist full utility debug breakdown by default")
	var debug_intent: Dictionary = bridge.get_actor_goal_intent(actor, true)
	if not debug_intent.has("full_debug_breakdown"):
		_fail("Runtime utility debug breakdown should be available on demand")
	root_node.queue_free()


func _validate_job_contract_order_and_quit() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	root_node.add_child(bridge)
	bridge.initialize(root_node)
	bridge.upsert_job_contract({"actor_id": "actor.jobs", "provider_id": "provider.jobs", "job_id": "guard", "display_name": "Guard", "priority_order": 0})
	var second: Dictionary = bridge.upsert_job_contract({"actor_id": "actor.jobs", "provider_id": "provider.jobs", "job_id": "server", "display_name": "Server", "priority_order": 1})
	bridge.move_actor_job_contract("actor.jobs", str(second.get("contract_id", "")), -1)
	var contracts: Array = bridge.get_actor_job_contracts("actor.jobs")
	if contracts.size() != 2 or str(contracts[0].get("job_id", "")) != "server":
		_fail("Job contracts should support strict priority reordering")
	bridge.abandon_job_contract("actor.jobs", str(contracts[0].get("contract_id", "")), "quit", 12.0)
	if bridge.get_actor_job_contracts("actor.jobs").size() != 1:
		_fail("Quitting a job contract should remove it from actor jobs")
	var memory: Array = bridge.get_job_provider_memory("provider.jobs")
	if memory.is_empty() or str(memory[0].get("reason", "")) != "quit":
		_fail("Quitting a job contract should record provider memory")
	root_node.queue_free()


func _validate_dialogue_accept_creates_job_contract() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	root_node.add_child(bridge)
	bridge.initialize(root_node)
	var provider: JobProvider = JOB_PROVIDER_SCRIPT.new()
	provider.name = "ContractProvider"
	var resource := FakeMineNode.new()
	resource.name = "MineNode"
	provider.add_child(resource)
	var container := Node3D.new()
	container.name = "OutputNode"
	provider.add_child(container)
	var job: JobDefinition = JOB_DEFINITION_SCRIPT.new()
	job.display_name = "Validation Miner"
	job.job_id = "validation_miner"
	job.algorithm_id = "mine_and_haul"
	job.slot_count = 1
	var resource_paths: Array[NodePath] = [NodePath("MineNode")]
	var container_paths: Array[NodePath] = [NodePath("OutputNode")]
	job.resource_paths = resource_paths
	job.container_paths = container_paths
	var jobs: Array[JobDefinition] = [job]
	provider.jobs = jobs
	root_node.add_child(provider)
	var worker = HUMANOID_CHARACTER_SCRIPT.new()
	worker.stable_id = "utility.actor.dialogue.worker"
	worker.member_name = "Dialogue Worker"
	var request_response: Dictionary = provider.handle_conversation_option(worker, {"job_provider_action": "request_job", "job_index": 0})
	if bool(request_response.get("end_conversation", true)):
		_fail("Dialogue job request should present an acceptable offer")
	provider.handle_conversation_option(worker, {"job_provider_action": "accept_job_offer", "job_index": 0})
	var contracts: Array = bridge.get_actor_job_contracts(worker.stable_id)
	if contracts.size() != 1:
		_fail("Accepting a dialogue job offer should create one durable job contract")
	else:
		var contract: Dictionary = contracts[0]
		if str(contract.get("job_id", "")) != "validation_miner":
			_fail("Dialogue-created job contract should preserve the job id")
		if str(contract.get("provider_id", "")) != str(provider.get_path()):
			_fail("Dialogue-created job contract should preserve the provider id")
		if int(contract.get("priority_order", -1)) != 0:
			_fail("First dialogue-created job contract should get priority 0")
		if float(contract.get("last_started_at", 0.0)) >= 0.0:
			_fail("New dialogue-created job contracts should start as not reported")
	var duplicate_response: Dictionary = provider.handle_conversation_option(worker, {"job_provider_action": "request_job", "job_index": 0})
	if str(duplicate_response.get("speaker_text", "")).find("Already hired") < 0:
		_fail("A worker with an existing contract should not receive a duplicate job offer")
	if bridge.get_actor_job_contracts(worker.stable_id).size() != 1:
		_fail("Duplicate dialogue requests should not create extra job contracts")
	worker.free()
	root_node.queue_free()


func _validate_no_show_contract_expiration() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	root_node.add_child(bridge)
	bridge.initialize(root_node)
	bridge.upsert_job_contract({
		"actor_id": "actor.no_show",
		"provider_id": "provider.no_show",
		"job_id": "guard",
		"display_name": "Guard",
		"priority_order": 0,
		"status": "active",
		"report_deadline": 5.0,
		"last_started_at": -1.0,
	})
	var started_contract: Dictionary = bridge.upsert_job_contract({
		"actor_id": "actor.started",
		"provider_id": "provider.no_show",
		"job_id": "server",
		"display_name": "Server",
		"priority_order": 0,
		"status": "active",
		"report_deadline": 5.0,
		"last_started_at": -1.0,
	})
	bridge.upsert_job_contract({
		"actor_id": "actor.player_party",
		"provider_id": "provider.no_show",
		"job_id": "waiter",
		"display_name": "Waiter",
		"priority_order": 0,
		"status": "active",
		"report_deadline": 5.0,
		"last_started_at": -1.0,
		"metadata": {"player_party_member": true},
	})
	bridge.mark_job_contract_started(str(started_contract.get("contract_id", "")), 0.0)
	var expired_count := int(bridge.expire_missed_job_contracts(6.0))
	if expired_count != 1:
		_fail("No-show expiration should remove exactly never-started non-player overdue contracts")
	if not bridge.get_actor_job_contracts("actor.no_show").is_empty():
		_fail("No-show expiration should remove the missed contract")
	if bridge.get_actor_job_contracts("actor.started").size() != 1:
		_fail("Contracts started at sim time 0 should not expire as no-shows")
	if bridge.get_actor_job_contracts("actor.player_party").size() != 1:
		_fail("Player-party job contracts should not expire as no-shows")
	var memory: Array = bridge.get_job_provider_memory("provider.no_show")
	if memory.is_empty() or str(memory[0].get("reason", "")) != "no_show":
		_fail("No-show expiration should record provider memory with reason no_show")
	root_node.queue_free()


func _validate_contract_driven_work_objective() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	root_node.add_child(bridge)
	bridge.initialize(root_node)
	var actor := FakeUtilityActor.new()
	actor.stable_id = "utility.actor.worker"
	actor._order_was_player_issued = true
	actor._current_order_type = 0
	root_node.add_child(actor)
	var provider := FakeProvider.new()
	provider.name = "UtilityProvider"
	provider.add_to_group("job_provider")
	root_node.add_child(provider)
	bridge.register_actor(actor)
	var contract: Dictionary = bridge.upsert_job_contract({
		"actor_id": actor.stable_id,
		"provider_id": str(provider.get_path()),
		"provider_name": "Utility Provider",
		"provider_path": provider.get_path(),
		"job_id": "server",
		"job_index": 0,
		"algorithm_id": "server_shift",
		"display_name": "Serving Tables",
		"priority_order": 0,
		"next_shift_time": 0.0,
		"report_deadline": 999.0,
	})
	var adapter = AI_UTILITY_ADAPTER_SCRIPT.new()
	adapter.setup(AI_UTILITY_PROFILE)
	if not adapter.run_actor_decision(actor):
		_fail("Utility adapter should realize job contracts as work objectives")
	var intent: Dictionary = bridge.get_actor_goal_intent(actor, false)
	if str(intent.get("goal_id", "")) != "assigned_work":
		_fail("Contract work objective should select assigned_work after completed player orders, got %s" % str(intent.get("goal_id", "")))
	if provider.started_contract_id != str(contract.get("contract_id", "")):
		_fail("Contract work objective should start the provider contract shift")
	if actor.requested_jobs.is_empty():
		_fail("Contract work objective should create a runtime AiJob")
	root_node.queue_free()


func _validate_contract_work_not_restarted_when_active() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	root_node.add_child(bridge)
	bridge.initialize(root_node)
	var actor := FakeUtilityActor.new()
	actor.stable_id = "utility.actor.active_contract"
	root_node.add_child(actor)
	var provider := FakeProvider.new()
	provider.name = "ActiveContractProvider"
	provider.add_to_group("job_provider")
	root_node.add_child(provider)
	bridge.register_actor(actor)
	var contract: Dictionary = bridge.upsert_job_contract({
		"actor_id": actor.stable_id,
		"provider_id": str(provider.get_path()),
		"provider_name": "Active Contract Provider",
		"provider_path": provider.get_path(),
		"job_id": "waiter",
		"job_index": 0,
		"algorithm_id": "server_shift",
		"display_name": "Waiter",
		"priority_order": 0,
		"next_shift_time": 0.0,
	})
	var adapter = AI_UTILITY_ADAPTER_SCRIPT.new()
	adapter.setup(AI_UTILITY_PROFILE)
	if not adapter.run_actor_decision(actor):
		_fail("Utility adapter should start the first active contract job")
	var first_request_count := actor.requested_jobs.size()
	var first_start_count := provider.started_contract_count
	adapter.run_actor_decision(actor)
	if actor.requested_jobs.size() != first_request_count or provider.started_contract_count != first_start_count:
		_fail("Utility adapter should not pause and restart an already-active matching job contract")
	if actor.active_job_id != str(contract.get("contract_id", "")):
		_fail("Active contract regression should keep the active AiJob id equal to the contract id")
	root_node.queue_free()


func _validate_contract_actionability_priority() -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	root_node.add_child(bridge)
	bridge.initialize(root_node)
	var actor := FakeUtilityActor.new()
	actor.stable_id = "utility.actor.multi_job"
	root_node.add_child(actor)
	var provider := FakeProvider.new()
	provider.name = "MultiJobProvider"
	provider.add_to_group("job_provider")
	provider.actionable_by_job_id = {"waiter": false, "guard": true}
	root_node.add_child(provider)
	bridge.register_actor(actor)
	var waiter_contract: Dictionary = bridge.upsert_job_contract({
		"actor_id": actor.stable_id,
		"provider_id": str(provider.get_path()),
		"provider_name": "Multi Job Provider",
		"provider_path": provider.get_path(),
		"job_id": "waiter",
		"job_index": 0,
		"algorithm_id": "server_shift",
		"display_name": "Waiter",
		"priority_order": 0,
		"next_shift_time": 0.0,
	})
	var guard_contract: Dictionary = bridge.upsert_job_contract({
		"actor_id": actor.stable_id,
		"provider_id": str(provider.get_path()),
		"provider_name": "Multi Job Provider",
		"provider_path": provider.get_path(),
		"job_id": "guard",
		"job_index": 1,
		"algorithm_id": "guard_post",
		"display_name": "Guard",
		"priority_order": 1,
		"next_shift_time": 0.0,
	})
	var adapter = AI_UTILITY_ADAPTER_SCRIPT.new()
	adapter.setup(AI_UTILITY_PROFILE)
	if not adapter.run_actor_decision(actor):
		_fail("Utility adapter should choose a lower-priority actionable job when the top job is passive")
	if provider.started_contract_id != str(guard_contract.get("contract_id", "")):
		_fail("Inactive higher-priority contracts should not block lower-priority actionable work")
	provider.actionable_by_job_id["waiter"] = true
	if not adapter.run_actor_decision(actor):
		_fail("Utility adapter should choose the top-priority job once it becomes actionable")
	if provider.started_contract_id != str(waiter_contract.get("contract_id", "")):
		_fail("Actionable higher-priority contracts should interrupt lower-priority work")
	root_node.queue_free()


func _base_context() -> AiUtilityContext:
	var context = AI_UTILITY_CONTEXT_SCRIPT.new()
	context.entity_id = "utility.test.actor"
	context.profile_id = "default_humanoid"
	context.sim_time = 0.0
	context.set_fact(&"alive", 1.0)
	context.set_fact(&"health", 1.0)
	context.set_fact(&"blood", 1.0)
	context.set_fact(&"damage", 0.0)
	context.set_fact(&"critical_damage", 0.0)
	context.set_fact(&"threat", 0.0)
	context.set_fact(&"can_self_defend", 0.0)
	context.set_fact(&"heal_need", 0.0)
	context.set_fact(&"assigned_work_available", 0.0)
	context.set_fact(&"no_player_order", 1.0)
	context.set_fact(&"idle_bias", 0.2)
	return context


func _candidate(target, score: float) -> Dictionary:
	return {
		"target": target,
		"entity_id": str(target.get_instance_id()) if target is Object else str(target),
		"position": (target as Node3D).global_position if target is Node3D and (target as Node3D).is_inside_tree() else Vector3.ZERO,
		"score": score,
	}


func _fail(message: String) -> void:
	_failures.append(message)
