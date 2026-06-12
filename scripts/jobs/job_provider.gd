extends Node

class_name JobProvider

const DEFAULT_WORK_INVENTORY_COLUMNS := 4
const DEFAULT_WORK_INVENTORY_ROWS := 4
const JOB_DEFINITION_SCRIPT = preload("res://scripts/jobs/job_definition.gd")
const ACTOR_CONDITION_EVALUATOR_SCRIPT = preload("res://scripts/conditions/actor_condition_evaluator.gd")
const AI_JOB_SCRIPT = preload("res://scripts/ai/ai_job.gd")
const AI_ASSIGNED_WORK_STEP_SCRIPT = preload("res://scripts/ai/steps/ai_assigned_work_step.gd")
const SERVER_ORDER_PREP_SECONDS := 3.5
const SERVER_STATE_IDLE := "idle"
const SERVER_STATE_TO_CUSTOMER := "to_customer"
const SERVER_STATE_TO_BARKEEPER := "to_barkeeper"
const SERVER_STATE_WAITING_AT_BAR := "waiting_at_bar"
const SERVER_STATE_DELIVERING := "delivering"
const REPORT_GRACE_SECONDS := 45.0
const PLAYER_PARTY_JOB_ACTION_RADIUS := 35.0

@export var jobs: Array[JobDefinition] = []
@export var wage_item_definition: Resource
@export var bar_service_area_path: NodePath
@export var max_on_duty_seconds := 90.0
@export var break_duration_seconds := 45.0
@export var greeting_return_threshold_seconds := 30.0
@export var guard_shuffle_min_seconds := 120.0
@export var guard_shuffle_max_seconds := 180.0

var _worker_records: Dictionary = {}
var _active_slots: Dictionary = {}
var _sim_time := 0.0
var _pending_job_offers: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _job_system_controller: Node


func _ready() -> void:
	add_to_group("job_provider")
	_rng.randomize()
	_initialize_slots()
	_sync_gecs_state()
	_job_system_controller = _get_job_system_controller()
	if _job_system_controller != null and _job_system_controller.has_method("register_job_provider"):
		_job_system_controller.call("register_job_provider", self)


func _exit_tree() -> void:
	if _job_system_controller != null and is_instance_valid(_job_system_controller) and _job_system_controller.has_method("unregister_job_provider"):
		_job_system_controller.call("unregister_job_provider", self)
	_job_system_controller = null


func set_sim_time(value: float) -> void:
	_sim_time = value
	_sync_gecs_state()


func get_provider_character() -> WorldActor:
	return get_parent() as WorldActor


func get_provider_name() -> String:
	var provider := get_provider_character()
	return provider.member_name if provider != null else str(name)


func get_greeting_text_for(worker: WorldActor, fallback: String) -> String:
	var record := _get_worker_record(worker)
	if float(record.get("total_worked_seconds", 0.0)) >= greeting_return_threshold_seconds:
		return "Back again?"
	return fallback


func build_conversation_options(worker: WorldActor, _context: Dictionary = {}) -> Array:
	var options: Array = []
	if worker == null:
		return options
	_initialize_slots()
	for job_index in range(jobs.size()):
		var job = jobs[job_index]
		if job == null or not _is_job_offer_visible(worker, job_index):
			continue
		options.append({
			"text": "Ask about %s" % job.get_display_name().to_lower(),
			"job_provider_action": "request_job",
			"job_index": job_index,
		})
	var record := _get_worker_record(worker)
	var owed_currency := int(record.get("owed_currency", 0))
	if owed_currency > 0:
		options.append({
			"text": "Can I collect my pay?",
			"disabled": false,
			"reason": "",
			"job_provider_action": "collect_pay",
		})
	return options


func handle_conversation_option(worker: WorldActor, option: Dictionary, context: Dictionary = {}) -> Dictionary:
	var action := str(option.get("job_provider_action", ""))
	match action:
		"request_job":
			var job_index := int(option.get("job_index", -1))
			return _handle_job_request_prompt(worker, job_index, context)
		"accept_job_offer":
			return _handle_job_accept(worker, int(option.get("job_index", -1)))
		"accept_selected_job_offer":
			return _handle_selected_job_accept(worker, int(option.get("job_index", -1)), context)
		"decline_job_offer":
			_clear_pending_offer(worker)
			return {
				"speaker_text": "Suit yourself.",
				"end_conversation": true,
				"show_floating_notice": false,
				"speech_target": get_provider_character(),
				"speech_text": "Suit yourself.",
				"speech_lifetime": 5.0,
			}
		"leave_conversation":
			_clear_pending_offer(worker)
			return {"end_conversation": true}
		"collect_pay":
			return _handle_collect_pay(worker)
	return {"speaker_text": "I have nothing for you.", "end_conversation": true}


func process_jobs(delta: float, sim_time: float) -> void:
	_sim_time = sim_time
	_initialize_slots()
	for job_index in _active_slots.keys():
		var job = jobs[job_index]
		if job == null:
			continue
		var slots: Array = _active_slots[job_index]
		for slot_state in slots:
			_process_slot(job_index, job, slot_state, delta)
	_sync_gecs_state()


func process_contracts(delta: float, sim_time: float) -> void:
	_sim_time = sim_time
	_initialize_slots()
	_process_passive_player_party_server_contracts(delta)
	_sync_gecs_state()


func _process_passive_player_party_server_contracts(delta: float) -> void:
	if delta <= 0.0:
		return
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_job_contracts_for_provider") or not bridge.has_method("get_actor_by_stable_id"):
		return
	for contract in bridge.call("get_job_contracts_for_provider", _provider_id()):
		if not (contract is Dictionary):
			continue
		var contract_data: Dictionary = contract
		if str(contract_data.get("status", "active")) != "active":
			continue
		var job_index := int(contract_data.get("job_index", -1))
		if job_index < 0 or job_index >= jobs.size():
			continue
		var job = jobs[job_index]
		if job == null or str(job.algorithm_id) != "server_shift":
			continue
		var worker := bridge.call("get_actor_by_stable_id", str(contract_data.get("actor_id", ""))) as WorldActor
		if not _is_player_party_worker(worker):
			continue
		if not _is_worker_listening_for_server_shift(worker):
			continue
		if not _find_worker_slot(worker).is_empty():
			continue
		var record := _get_worker_record(worker)
		_accrue_worker_record_pay(record, job, delta, _job_contract_job_id(job, job_index))


func create_assigned_work_ai_job(worker: WorldActor, job_label := ""):
	var assignment := _find_worker_slot(worker)
	if assignment.is_empty():
		return null
	var job_index := int(assignment.get("job_index", -1))
	if job_index < 0 or job_index >= jobs.size():
		return null
	var job_definition = jobs[job_index]
	if job_definition == null:
		return null
	var ai_job = AI_JOB_SCRIPT.new()
	ai_job.job_type = AI_JOB_SCRIPT.JobType.ASSIGNED_WORK
	ai_job.priority = AI_JOB_SCRIPT.priority_for_type(ai_job.job_type)
	ai_job.source_id = "job_provider"
	ai_job.source = self
	ai_job.target = self
	ai_job.target_id = str(get_path()) if is_inside_tree() else str(get_instance_id())
	ai_job.objective_id = str(job_definition.job_id) if not str(job_definition.job_id).is_empty() else str(job_definition.algorithm_id)
	ai_job.package_id = "assigned_work:%s" % str(job_definition.algorithm_id)
	ai_job.debug_label = "Working: %s" % job_label if not job_label.is_empty() else "Working: %s" % job_definition.get_display_name()
	ai_job.debug_reason = "%s assigned %s" % [get_provider_name(), job_definition.get_display_name()]
	ai_job.steps = [AI_ASSIGNED_WORK_STEP_SCRIPT.new()]
	return ai_job


func tick_worker_job_from_ai(worker: WorldActor, delta: float, _ai_job = null) -> Dictionary:
	_sim_time = _get_job_system_sim_time(delta)
	_initialize_slots()
	var assignment := _find_worker_slot(worker)
	if assignment.is_empty():
		return {"active": false, "ended": true, "failed": true, "blocker": "Worker has no active job slot"}
	var job_index := int(assignment.get("job_index", -1))
	if job_index < 0 or job_index >= jobs.size():
		return {"active": false, "ended": true, "failed": true, "blocker": "Job index is invalid"}
	var slot_state: Dictionary = assignment.get("slot_state", {})
	var job = jobs[job_index]
	if job == null:
		_end_slot_assignment(job_index, slot_state, false)
		return {"active": false, "ended": true, "failed": true, "blocker": "Job definition is missing"}
	_process_slot(job_index, job, slot_state, delta)
	var still_active: bool = worker != null and is_instance_valid(worker) and worker.get_active_job_provider() == self and slot_state.get("worker") == worker
	return {
		"active": still_active,
		"ended": not still_active,
		"blocker": str(slot_state.get("last_ai_blocker", "")),
		"algorithm_id": str(job.algorithm_id),
	}


func pause_worker_job(worker: WorldActor, caused_by_player: bool = false) -> void:
	if worker == null:
		return
	for job_index in _active_slots.keys():
		var slots: Array = _active_slots[job_index]
		for slot_state in slots:
			if slot_state.get("worker") != worker:
				continue
			_end_slot_assignment(job_index, slot_state, caused_by_player)
			return


func _initialize_slots() -> void:
	for job_index in range(jobs.size()):
		var job = jobs[job_index]
		if job == null:
			continue
		var slots: Array = _active_slots.get(job_index, [])
		for slot_index in range(slots.size(), max(job.slot_count, 1)):
			slots.append(_new_slot_state(slot_index))
		_active_slots[job_index] = slots


func _new_slot_state(slot_index: int) -> Dictionary:
	return {
		"slot_index": slot_index,
		"worker": null,
		"work_inventory": null,
		"claimed_resource": null,
		"target_container": null,
		"target_guard_post": null,
		"target_service_point": null,
		"target_service_seat": null,
		"target_service_customer": null,
		"target_service_order_id": "",
		"server_state": SERVER_STATE_IDLE,
		"server_state_elapsed": 0.0,
		"server_order_text": "",
		"guard_shuffle_remaining": _next_guard_shuffle_seconds(),
		"accrued_interval_time": 0.0,
		"last_work_active": false,
		"last_ai_blocker": "",
	}


func _evaluate_job_request(worker: WorldActor, job_index: int) -> Dictionary:
	_initialize_slots()
	if worker == null or job_index < 0 or job_index >= jobs.size():
		return {"allowed": false, "reason": "No job configured"}
	var job = jobs[job_index]
	if job == null:
		return {"allowed": false, "reason": "No job configured"}
	if not _is_job_configured(job):
		return {"allowed": false, "reason": ""}
	var job_id := _job_contract_job_id(job, job_index)
	if _has_worker_contract(worker, job_id):
		return {"allowed": false, "reason": "Already hired"}
	if _get_contract_count_for_job(job_id) >= max(job.slot_count, 1):
		return {"allowed": false, "reason": "No openings right now"}
	var record := _get_worker_record(worker)
	if float(record.get("break_until_time", 0.0)) > _sim_time:
		return {"allowed": false, "reason": "Take a break first"}
	var condition_result := ACTOR_CONDITION_EVALUATOR_SCRIPT.passes_all(job.requirements, {
		"speaker_member": worker,
		"conversation_target": get_provider_character(),
		"job_provider": self,
	})
	if not condition_result.get("passed", false):
		return {"allowed": false, "reason": condition_result.get("reason", "")}
	return {"allowed": true, "reason": ""}


func _handle_job_request_prompt(worker: WorldActor, job_index: int, context: Dictionary = {}) -> Dictionary:
	var evaluation := _evaluate_job_request(worker, job_index)
	if not evaluation.get("allowed", false):
		return _job_unavailable_response(jobs[job_index] if job_index >= 0 and job_index < jobs.size() else null, evaluation)
	var job = jobs[job_index]
	_pending_job_offers[_get_worker_key(worker)] = job_index
	if _supports_selected_group_offer(job):
		var selected_workers := _get_selected_job_group(worker, context)
		if selected_workers.size() > 1:
			var selected_evaluation := _evaluate_group_job_request(selected_workers, job_index)
			if selected_evaluation.get("allowed", false):
				return {
					"speaker_text": "%s You taking the watch alone, or bringing the others?" % _build_job_offer_text(job),
					"end_conversation": false,
					"follow_up_options": [
						{"text": "Just me.", "job_provider_action": "accept_job_offer", "job_index": job_index},
						{"text": "All of us.", "job_provider_action": "accept_selected_job_offer", "job_index": job_index},
						{"text": "Not right now", "job_provider_action": "decline_job_offer", "job_index": job_index},
					],
				}
			var fallback_text := "I only have room for one. You still want it?" if str(selected_evaluation.get("reason", "")) == "No openings right now" else "I can't put everyone on this. You still want it?"
			return {
				"speaker_text": fallback_text,
				"end_conversation": false,
				"follow_up_options": [
					{"text": "I'll do it.", "job_provider_action": "accept_job_offer", "job_index": job_index},
					{"text": "Not right now", "job_provider_action": "decline_job_offer", "job_index": job_index},
				],
			}
	return {
		"speaker_text": _build_job_offer_text(job),
		"end_conversation": false,
		"follow_up_options": [
			{"text": "Accept", "job_provider_action": "accept_job_offer", "job_index": job_index},
			{"text": "Not right now", "job_provider_action": "decline_job_offer", "job_index": job_index},
			{"text": "Leave", "job_provider_action": "leave_conversation", "job_index": job_index},
		],
	}


func _handle_job_accept(worker: WorldActor, job_index: int) -> Dictionary:
	if _pending_job_offers.get(_get_worker_key(worker), -1) != job_index:
		return {"end_conversation": true}
	_clear_pending_offer(worker)
	var job = jobs[job_index]
	var contract := _create_job_contract_for_worker(worker, job_index)
	if not bool(contract.get("allowed", false)):
		return _job_unavailable_response(job, contract)
	return {
		"speaker_text": _build_job_accept_text(job),
		"end_conversation": true,
		"show_floating_notice": false,
		"speech_target": get_provider_character(),
		"speech_text": _build_job_accept_speech(job),
		"speech_lifetime": 5.0,
	}


func _handle_selected_job_accept(worker: WorldActor, job_index: int, context: Dictionary = {}) -> Dictionary:
	if _pending_job_offers.get(_get_worker_key(worker), -1) != job_index:
		return {"end_conversation": true}
	var job = jobs[job_index]
	var selected_workers := _get_selected_job_group(worker, context)
	if selected_workers.size() <= 1:
		return _handle_job_accept(worker, job_index)
	var evaluation := _evaluate_group_job_request(selected_workers, job_index)
	if not evaluation.get("allowed", false):
		return _job_unavailable_response(job, evaluation)
	_clear_pending_offer(worker)
	for selected_worker in selected_workers:
		var contract := _create_job_contract_for_worker(selected_worker, job_index)
		if not contract.get("allowed", false):
			return _job_unavailable_response(job, contract)
	return {
		"speaker_text": "Good. All of you, get to work on %s." % job.get_display_name().to_lower(),
		"end_conversation": true,
		"show_floating_notice": false,
		"speech_target": get_provider_character(),
		"speech_text": "Good. All of you, get to work.",
		"speech_lifetime": 5.0,
	}


func _assign_worker_to_open_slot(worker: WorldActor, job_index: int) -> Dictionary:
	_initialize_slots()
	var evaluation := _evaluate_job_request(worker, job_index)
	if not evaluation.get("allowed", false):
		return evaluation
	return _claim_worker_slot(worker, job_index, true)


func start_contract_shift(worker: WorldActor, contract: Dictionary):
	if worker == null or contract.is_empty():
		return null
	var job_index := int(contract.get("job_index", -1))
	if job_index < 0 or job_index >= jobs.size():
		return null
	var assignment := _find_worker_slot(worker)
	if assignment.is_empty():
		var claimed := _claim_worker_slot(worker, job_index, false)
		if not bool(claimed.get("allowed", false)):
			return null
	_mark_contract_started(str(contract.get("contract_id", "")))
	var ai_job = create_assigned_work_ai_job(worker, str(contract.get("display_name", "")))
	if ai_job != null:
		ai_job.job_id = str(contract.get("contract_id", ""))
		ai_job.objective_id = str(contract.get("contract_id", ""))
	return ai_job


func get_contract_work_status(worker: WorldActor, contract: Dictionary) -> Dictionary:
	_initialize_slots()
	if worker == null or contract.is_empty():
		return {"actionable": false, "reason": "No worker or contract"}
	var job_index := int(contract.get("job_index", -1))
	if job_index < 0 or job_index >= jobs.size():
		return {"actionable": false, "reason": "Job index is invalid"}
	var job = jobs[job_index]
	if job == null or not _is_job_configured(job):
		return {"actionable": false, "reason": "Job is not configured"}
	var assignment := _find_worker_slot(worker)
	if not assignment.is_empty() and int(assignment.get("job_index", -1)) == job_index:
		return _active_slot_work_status(worker, job, assignment.get("slot_state", {}))
	match str(job.algorithm_id):
		"mine_and_haul":
			return {"actionable": not _resolve_nodes(job.resource_paths).is_empty() and not _resolve_nodes(job.container_paths).is_empty(), "reason": "Mine work available"}
		"guard_post":
			var guard_area := _resolve_bar_service_area()
			var guard_post = guard_area.get_available_guard_post(worker) if guard_area != null and guard_area.has_method("get_available_guard_post") else null
			return {"actionable": guard_post != null, "reason": "Guard post available" if guard_post != null else "No guard post available"}
		"server_shift":
			return _server_shift_contract_work_status(worker)
	return {"actionable": false, "reason": "Unsupported job algorithm"}


func on_job_contract_abandoned(contract: Dictionary, _reason := "quit") -> void:
	var actor_id := str(contract.get("actor_id", ""))
	if actor_id.is_empty():
		return
	for job_index in _active_slots.keys():
		for slot_state in _active_slots[job_index]:
			var worker: WorldActor = slot_state.get("worker")
			if worker != null and _get_worker_key(worker) == actor_id:
				_end_slot_assignment(int(job_index), slot_state, true)
				return


func _create_job_contract_for_worker(worker: WorldActor, job_index: int) -> Dictionary:
	var evaluation := _evaluate_job_request(worker, job_index)
	if not bool(evaluation.get("allowed", false)):
		return evaluation
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("upsert_job_contract"):
		return {"allowed": false, "reason": "Job records unavailable"}
	var job = jobs[job_index]
	var actor_id := _get_worker_key(worker)
	var job_id := _job_contract_job_id(job, job_index)
	var contract: Dictionary = bridge.call("upsert_job_contract", {
		"actor_id": actor_id,
		"provider_id": _provider_id(),
		"provider_name": get_provider_name(),
		"provider_path": get_path() if is_inside_tree() else NodePath(),
		"provider_owner_actor_id": _get_worker_key(get_provider_character()),
		"job_id": job_id,
		"job_index": job_index,
		"algorithm_id": str(job.algorithm_id),
		"display_name": job.get_display_name(),
		"status": "active",
		"hired_at": _sim_time,
		"next_shift_time": _sim_time,
		"report_deadline": _sim_time + REPORT_GRACE_SECONDS,
		"shift_end_time": _sim_time + max_on_duty_seconds,
		"last_started_at": -1.0,
		"metadata": {
			"player_party_member": _is_player_party_worker(worker),
		},
	})
	_sync_gecs_state()
	return {"allowed": not contract.is_empty(), "reason": "", "contract": contract}


func _claim_worker_slot(worker: WorldActor, job_index: int, request_ai_job := true) -> Dictionary:
	_initialize_slots()
	if worker == null or job_index < 0 or job_index >= jobs.size():
		return {"allowed": false, "reason": "No job configured"}
	var slot_index := _find_open_slot(job_index)
	if slot_index < 0:
		return {"allowed": false, "reason": "No openings right now"}
	var job = jobs[job_index]
	var slot_state: Dictionary = _active_slots[job_index][slot_index]
	var work_inventory := InventoryData.new(DEFAULT_WORK_INVENTORY_COLUMNS, DEFAULT_WORK_INVENTORY_ROWS, 0.0, false)
	slot_state["worker"] = worker
	slot_state["work_inventory"] = work_inventory
	slot_state["claimed_resource"] = null
	slot_state["target_container"] = null
	slot_state["target_guard_post"] = null
	slot_state["target_service_point"] = null
	slot_state["target_service_seat"] = null
	slot_state["target_service_customer"] = null
	slot_state["target_service_order_id"] = ""
	slot_state["server_state"] = SERVER_STATE_IDLE
	slot_state["server_state_elapsed"] = 0.0
	slot_state["server_order_text"] = ""
	slot_state["guard_shuffle_remaining"] = _next_guard_shuffle_seconds()
	slot_state["accrued_interval_time"] = 0.0
	slot_state["last_work_active"] = false
	slot_state["last_ai_blocker"] = ""
	var record := _get_worker_record(worker)
	record["current_shift_seconds"] = 0.0
	record["last_job_index"] = job_index
	worker.begin_job_assignment(self, job.get_display_name(), work_inventory, request_ai_job)
	_sync_gecs_state()
	return {"allowed": true, "reason": ""}


func _handle_collect_pay(worker: WorldActor) -> Dictionary:
	var provider := get_provider_character()
	var record := _get_worker_record(worker)
	var owed_currency := int(record.get("owed_currency", 0))
	if owed_currency <= 0:
		return {
			"speaker_text": "You have not earned anything yet.",
			"end_conversation": true,
			"show_floating_notice": false,
			"speech_target": provider,
			"speech_text": "You have not earned anything yet.",
			"speech_lifetime": 5.0,
		}
	if wage_item_definition == null:
		return {
			"speaker_text": "I can't pay you right now.",
			"end_conversation": true,
			"show_floating_notice": false,
			"speech_target": provider,
			"speech_text": "I can't pay you right now.",
			"speech_lifetime": 5.0,
		}
	var worker_inventory = worker.get("inventory") if worker != null else null
	if worker_inventory == null or not worker_inventory.has_method("add_item_count") or not worker_inventory.add_item_count(wage_item_definition, owed_currency):
		return {
			"speaker_text": "Make some room first.",
			"end_conversation": true,
			"show_floating_notice": false,
			"speech_target": provider,
			"speech_text": "Make some room first.",
			"speech_lifetime": 5.0,
		}
	record["owed_currency"] = 0
	_sync_gecs_state()
	return {
		"speaker_text": "Here you go.",
		"end_conversation": true,
		"show_floating_notice": false,
		"world_notice_target": provider,
		"world_notice_text": "Paid %d" % owed_currency,
		"world_notice_color": Color(0.5, 1.0, 0.65, 1.0),
		"world_notice_lifetime": 5.0,
	}


func _find_open_slot(job_index: int) -> int:
	var slots: Array = _active_slots.get(job_index, [])
	for slot_index in range(slots.size()):
		if slots[slot_index].get("worker") == null:
			return slot_index
	return -1


func _get_open_slot_count(job_index: int) -> int:
	var open_count := 0
	var slots: Array = _active_slots.get(job_index, [])
	for slot_state in slots:
		if slot_state.get("worker") == null:
			open_count += 1
	return open_count


func _evaluate_group_job_request(workers: Array, job_index: int) -> Dictionary:
	_initialize_slots()
	if workers.is_empty():
		return {"allowed": false, "reason": "No workers selected"}
	var job = jobs[job_index] if job_index >= 0 and job_index < jobs.size() else null
	var job_id := _job_contract_job_id(job, job_index)
	if max(job.slot_count if job != null else 1, 1) - _get_contract_count_for_job(job_id) < workers.size():
		return {"allowed": false, "reason": "No openings right now"}
	for worker in workers:
		if not (worker is WorldActor):
			return {"allowed": false, "reason": "No workers selected"}
		var evaluation := _evaluate_job_request(worker, job_index)
		if not evaluation.get("allowed", false):
			return evaluation
	return {"allowed": true, "reason": ""}


func _get_selected_job_group(worker: WorldActor, context: Dictionary) -> Array:
	var selected_workers: Array = []
	var context_selected: Array = context.get("selected_party_members", [])
	for selected_worker in context_selected:
		if selected_worker == null or not is_instance_valid(selected_worker):
			continue
		if not (selected_worker is WorldActor):
			continue
		if selected_workers.has(selected_worker):
			continue
		selected_workers.append(selected_worker)
	if worker == null or not selected_workers.has(worker):
		return [worker] if worker != null else []
	return selected_workers


func _supports_selected_group_offer(job) -> bool:
	return job != null and str(job.algorithm_id) == "guard_post"


func _job_unavailable_response(job, evaluation: Dictionary) -> Dictionary:
	var reason := str(evaluation.get("reason", ""))
	var message := reason
	if job != null and str(job.get("algorithm_id")) == "guard_post" and reason == "No openings right now":
		message = "No. I have enough guards right now."
	elif message.is_empty():
		message = "I don't have work for you right now."
	return {
		"speaker_text": message,
		"end_conversation": true,
		"show_floating_notice": false,
		"speech_target": get_provider_character(),
		"speech_text": message,
		"speech_lifetime": 5.0,
	}


func _process_slot(job_index: int, job, slot_state: Dictionary, delta: float) -> void:
	slot_state["last_ai_blocker"] = ""
	var worker: WorldActor = slot_state.get("worker")
	if worker == null:
		slot_state["last_ai_blocker"] = "No worker"
		return
	if not is_instance_valid(worker) or worker.life_state != NpcRules.LifeState.ALIVE:
		slot_state["last_ai_blocker"] = "Worker is not alive"
		_end_slot_assignment(job_index, slot_state, false)
		return
	if worker.get_active_job_provider() != self:
		slot_state["last_ai_blocker"] = "Worker is no longer assigned here"
		_end_slot_assignment(job_index, slot_state, false)
		return
	if worker.is_in_combat():
		slot_state["last_ai_blocker"] = "Worker is in combat"
		return
	var is_meaningfully_working := false
	var completed_server_order := false
	match job.algorithm_id:
		"mine_and_haul":
			is_meaningfully_working = _process_mine_and_haul(job_index, job, slot_state, worker)
		"guard_post":
			is_meaningfully_working = _process_guard_post(job_index, job, slot_state, worker, delta)
		"server_shift":
			var service_result := _process_server_shift(job_index, job, slot_state, worker, delta)
			is_meaningfully_working = bool(service_result.get("active", false))
			completed_server_order = bool(service_result.get("completed_order", false))
	slot_state["last_work_active"] = is_meaningfully_working
	if not is_meaningfully_working:
		if str(job.algorithm_id) == "server_shift" and _is_player_party_worker(worker):
			_end_slot_assignment(job_index, slot_state, false)
		return
	var record := _get_worker_record(worker)
	var on_duty_seconds := float(record.get("current_shift_seconds", 0.0)) + delta
	record["current_shift_seconds"] = on_duty_seconds
	if str(job.algorithm_id) == "server_shift" and _is_player_party_worker(worker):
		_accrue_worker_record_pay(record, job, delta, _job_contract_job_id(job, job_index))
	else:
		slot_state["accrued_interval_time"] = float(slot_state.get("accrued_interval_time", 0.0)) + delta
		while float(slot_state.get("accrued_interval_time", 0.0)) >= maxf(job.pay_interval_seconds, 0.01):
			slot_state["accrued_interval_time"] = float(slot_state.get("accrued_interval_time", 0.0)) - maxf(job.pay_interval_seconds, 0.01)
			record["owed_currency"] = int(record.get("owed_currency", 0)) + job.pay_per_interval
			record["total_worked_seconds"] = float(record.get("total_worked_seconds", 0.0)) + job.pay_interval_seconds
	if completed_server_order:
		_award_server_order_completion(job, worker, record)
		if _is_player_party_worker(worker):
			_end_slot_assignment(job_index, slot_state, false)
			return
	if on_duty_seconds >= max_on_duty_seconds:
		record["break_until_time"] = _sim_time + break_duration_seconds
		worker.show_world_notice("%s says take a break" % get_provider_name(), Color(0.95, 0.85, 0.45, 1.0))
		_end_slot_assignment(job_index, slot_state, false)
		return


func _process_mine_and_haul(job_index: int, job, slot_state: Dictionary, worker: WorldActor) -> bool:
	if not worker.has_method("get_assigned_mining_node") or not worker.has_method("assign_mining_resource"):
		slot_state["last_ai_blocker"] = "Worker cannot mine"
		return false
	var work_inventory: InventoryData = slot_state.get("work_inventory")
	if work_inventory == null:
		work_inventory = InventoryData.new(DEFAULT_WORK_INVENTORY_COLUMNS, DEFAULT_WORK_INVENTORY_ROWS, 0.0, false)
		slot_state["work_inventory"] = work_inventory
	var total_items := _get_total_item_count(work_inventory)
	if total_items >= max(job.carry_item_threshold, 1) or _work_inventory_contains_blocked_stack(work_inventory):
		var container = _resolve_best_container(job, slot_state, worker)
		if container == null:
			return false
		slot_state["target_container"] = container
		var interaction_position: Vector3 = container.get_interaction_position(worker)
		if worker.global_position.distance_to(interaction_position) > worker.interact_distance:
			worker.set_move_target(interaction_position, false)
			return true
		_transfer_work_inventory_to_output(job, work_inventory, container)
		return true

	var resource_node = _resolve_best_resource(job_index, job, slot_state, worker)
	if resource_node == null:
		return false
	if slot_state.get("claimed_resource") != resource_node:
		slot_state["claimed_resource"] = resource_node
	if worker.get_assigned_mining_node() != resource_node:
		worker.assign_mining_resource(resource_node, false)
	return true


func _process_guard_post(_job_index: int, _job, slot_state: Dictionary, worker: WorldActor, delta: float) -> bool:
	if worker.is_in_combat():
		return true
	var service_area := _resolve_bar_service_area()
	if service_area == null:
		return false
	var post = slot_state.get("target_guard_post")
	if post == null or not is_instance_valid(post):
		post = service_area.get_available_guard_post(worker)
		if post == null:
			return false
		if post.has_method("claim_worker") and not post.claim_worker(worker):
			return false
		slot_state["target_guard_post"] = post
		slot_state["guard_shuffle_remaining"] = _next_guard_shuffle_seconds()
	post = _process_guard_post_shuffle(service_area, slot_state, worker, post, delta)
	var work_position: Vector3 = post.get_work_position()
	if worker.global_position.distance_to(work_position) > worker.interact_distance:
		worker.set_move_target(work_position, false)
		return false
	if post.has_method("is_worker_at_post"):
		return post.is_worker_at_post(worker)
	return true


func _process_server_shift(_job_index: int, _job, slot_state: Dictionary, worker: WorldActor, delta: float) -> Dictionary:
	if not worker.has_method("show_world_speech"):
		return {"active": false, "completed_order": false}
	var service_area := _resolve_bar_service_area()
	if service_area == null:
		return {"active": false, "completed_order": false}
	var state := str(slot_state.get("server_state", SERVER_STATE_IDLE))
	if state == SERVER_STATE_IDLE:
		var order: Dictionary = {}
		if _is_player_party_worker(worker) and service_area.has_method("claim_waiter_order"):
			order = service_area.claim_waiter_order(worker)
		var claimed_seat = order.get("seat") if not order.is_empty() else null
		if claimed_seat == null and not _is_player_party_worker(worker) and service_area.has_method("claim_waiting_customer_seat"):
			claimed_seat = service_area.claim_waiting_customer_seat(worker)
		if claimed_seat == null:
			if _is_player_party_worker(worker):
				_release_waiter_service_point(slot_state, worker)
				return {"active": false, "completed_order": false}
			return {"active": _hold_waiter_service_point(service_area, slot_state, worker), "completed_order": false}
		_release_waiter_service_point(slot_state, worker)
		slot_state["target_service_seat"] = claimed_seat
		var order_customer = order.get("customer") if not order.is_empty() else null
		if order_customer == null and service_area.has_method("get_customer_for_seat"):
			order_customer = service_area.get_customer_for_seat(claimed_seat)
		slot_state["target_service_customer"] = order_customer
		slot_state["target_service_order_id"] = str(order.get("order_id", ""))
		var order_text := str(order.get("order_text", ""))
		if order_text.is_empty() and service_area.has_method("generate_customer_order_text"):
			order_text = service_area.generate_customer_order_text(slot_state.get("target_service_customer"))
		slot_state["server_order_text"] = order_text
		if str(slot_state.get("server_order_text", "")).is_empty():
			slot_state["server_order_text"] = "Something to eat."
		_set_server_state(slot_state, SERVER_STATE_TO_CUSTOMER)
		state = SERVER_STATE_TO_CUSTOMER
	var seat = slot_state.get("target_service_seat")
	var customer: HumanoidCharacter = slot_state.get("target_service_customer")
	if not _is_valid_service_customer(customer):
		_release_server_customer_service(service_area, slot_state)
		return {"active": true, "completed_order": false}
	match state:
		SERVER_STATE_TO_CUSTOMER:
			var customer_position := service_area.get_waiter_customer_service_position(worker, seat) if service_area.has_method("get_waiter_customer_service_position") else customer.global_position
			if not _move_worker_to_service_position(worker, customer_position, _server_customer_service_distance(service_area, worker)):
				return {"active": true, "completed_order": false}
			worker.show_world_speech("Can I take your order?", 2.0)
			customer.show_world_speech(str(slot_state.get("server_order_text", "Something to eat.")), 2.4)
			_set_server_state(slot_state, SERVER_STATE_TO_BARKEEPER)
		SERVER_STATE_TO_BARKEEPER:
			var barkeeper_position := service_area.get_barkeeper_order_position(worker) if service_area.has_method("get_barkeeper_order_position") else service_area.global_position
			if not _move_worker_to_service_position(worker, barkeeper_position, worker.interact_distance):
				return {"active": true, "completed_order": false}
			worker.show_world_speech("Order for the table: %s" % str(slot_state.get("server_order_text", "Something to eat.")), 2.4)
			var provider := get_provider_character()
			if provider != null:
				provider.show_world_speech("Coming up.", 1.6)
			_set_server_state(slot_state, SERVER_STATE_WAITING_AT_BAR)
		SERVER_STATE_WAITING_AT_BAR:
			slot_state["server_state_elapsed"] = float(slot_state.get("server_state_elapsed", 0.0)) + delta
			if float(slot_state.get("server_state_elapsed", 0.0)) < SERVER_ORDER_PREP_SECONDS:
				return {"active": true, "completed_order": false}
			_set_server_state(slot_state, SERVER_STATE_DELIVERING)
		SERVER_STATE_DELIVERING:
			var delivery_position := service_area.get_waiter_customer_service_position(worker, seat) if service_area.has_method("get_waiter_customer_service_position") else customer.global_position
			if not _move_worker_to_service_position(worker, delivery_position, _server_customer_service_distance(service_area, worker)):
				return {"active": true, "completed_order": false}
			worker.show_world_speech("Here you go.", 1.8)
			if service_area.has_method("generate_customer_thanks_text"):
				customer.show_world_speech(service_area.generate_customer_thanks_text(customer), 1.8)
			if service_area.has_method("complete_waiter_customer_service"):
				service_area.complete_waiter_customer_service(seat)
			_reset_server_service_state(slot_state)
			return {"active": true, "completed_order": true}
	return {"active": true, "completed_order": false}


func _hold_waiter_service_point(service_area: BarServiceArea, slot_state: Dictionary, worker: WorldActor) -> bool:
	var service_point = slot_state.get("target_service_point")
	if service_point == null or not is_instance_valid(service_point):
		service_point = service_area.get_available_waiter_point(worker)
		if service_point == null:
			return false
		if service_area.has_method("claim_waiter_point") and not service_area.claim_waiter_point(worker, service_point):
			return false
		slot_state["target_service_point"] = service_point
	if not service_point.has_method("get_work_position"):
		return false
	var work_position: Vector3 = service_point.get_work_position()
	if worker.global_position.distance_to(work_position) > worker.interact_distance:
		worker.set_move_target(work_position, false)
		return true
	if service_point.has_method("is_worker_at_point"):
		return service_point.is_worker_at_point(worker)
	return true


func _release_waiter_service_point(slot_state: Dictionary, worker: WorldActor) -> void:
	var service_point = slot_state.get("target_service_point")
	if service_point != null and is_instance_valid(service_point) and service_point.has_method("release_worker"):
		service_point.release_worker(worker)
	slot_state["target_service_point"] = null


func _is_valid_service_customer(customer: HumanoidCharacter) -> bool:
	return customer != null and is_instance_valid(customer) and customer.life_state == NpcRules.LifeState.ALIVE and customer.has_method("is_sitting") and customer.is_sitting()


func _move_worker_to_service_position(worker: WorldActor, target_position: Vector3, arrival_distance: float) -> bool:
	if worker.global_position.distance_to(target_position) > arrival_distance:
		worker.set_move_target(target_position, false)
		return false
	return true


func _server_customer_service_distance(service_area: BarServiceArea, worker: WorldActor) -> float:
	var configured = service_area.get("waiter_service_distance") if service_area != null else null
	return maxf(worker.interact_distance, float(configured) if configured != null else 2.4)


func _is_player_party_worker(worker: WorldActor) -> bool:
	return worker != null and worker.has_method("is_player_party_member") and bool(worker.call("is_player_party_member"))


func _is_worker_listening_for_server_shift(worker: WorldActor) -> bool:
	if worker == null or not is_instance_valid(worker) or worker.life_state != NpcRules.LifeState.ALIVE or worker.is_in_combat():
		return false
	var service_area := _resolve_bar_service_area()
	return service_area != null and _is_worker_near_service_area(worker, service_area)


func _accrue_worker_record_pay(record: Dictionary, job, delta: float, job_id: String) -> void:
	if record.is_empty() or job == null or delta <= 0.0:
		return
	var accruals: Dictionary = record.get("contract_accrued_interval_time", {}) if record.get("contract_accrued_interval_time", {}) is Dictionary else {}
	var key := job_id if not job_id.is_empty() else str(job.algorithm_id)
	var accrued := float(accruals.get(key, 0.0)) + delta
	var interval := maxf(float(job.pay_interval_seconds), 0.01)
	while accrued >= interval:
		accrued -= interval
		record["owed_currency"] = int(record.get("owed_currency", 0)) + int(job.pay_per_interval)
		record["total_worked_seconds"] = float(record.get("total_worked_seconds", 0.0)) + interval
	accruals[key] = accrued
	record["contract_accrued_interval_time"] = accruals


func _active_slot_work_status(worker: WorldActor, job, slot_state: Dictionary) -> Dictionary:
	if str(job.algorithm_id) != "server_shift":
		return {"actionable": true, "reason": "Shift already active"}
	var state := str(slot_state.get("server_state", SERVER_STATE_IDLE))
	if state != SERVER_STATE_IDLE or slot_state.get("target_service_seat") != null:
		return {"actionable": true, "reason": "Order in progress"}
	if not _is_player_party_worker(worker):
		return {"actionable": true, "reason": "NPC waiter idle duty"}
	return _server_shift_contract_work_status(worker)


func _server_shift_contract_work_status(worker: WorldActor) -> Dictionary:
	var service_area := _resolve_bar_service_area()
	if service_area == null:
		return {"actionable": false, "reason": "No service area"}
	if not _is_player_party_worker(worker):
		return {"actionable": not service_area.get_waiter_service_points().is_empty(), "reason": "NPC waiter idle duty"}
	if not _is_worker_near_service_area(worker, service_area):
		return {"actionable": false, "reason": "Worker is away from the bar"}
	var pending_order: Dictionary = service_area.call("get_pending_waiter_order_for_worker", worker) if service_area.has_method("get_pending_waiter_order_for_worker") else {}
	var has_customer := not pending_order.is_empty() and _is_best_player_party_waiter_for_order(worker, pending_order)
	return {"actionable": has_customer, "reason": "Customer order ready" if has_customer else "No customer orders ready"}


func _is_best_player_party_waiter_for_order(worker: WorldActor, order: Dictionary) -> bool:
	if worker == null or order.is_empty():
		return false
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_job_contracts_for_provider") or not bridge.has_method("get_actor_by_stable_id"):
		return true
	var best_worker: WorldActor
	var best_priority := INF
	var best_distance := INF
	var seat = order.get("seat")
	for contract in bridge.call("get_job_contracts_for_provider", _provider_id()):
		if not (contract is Dictionary):
			continue
		var contract_data: Dictionary = contract
		if str(contract_data.get("status", "active")) != "active" or str(contract_data.get("algorithm_id", "")) != "server_shift":
			continue
		var metadata: Dictionary = contract_data.get("metadata", {}) if contract_data.get("metadata", {}) is Dictionary else {}
		if not bool(metadata.get("player_party_member", false)):
			continue
		var candidate := bridge.call("get_actor_by_stable_id", str(contract_data.get("actor_id", ""))) as WorldActor
		if not _is_worker_listening_for_server_shift(candidate):
			continue
		var candidate_priority := int(contract_data.get("priority_order", 0))
		var candidate_distance := _waiter_order_distance_squared(candidate, seat)
		if candidate_priority < best_priority or (candidate_priority == best_priority and candidate_distance < best_distance):
			best_worker = candidate
			best_priority = candidate_priority
			best_distance = candidate_distance
	return best_worker == worker


func _waiter_order_distance_squared(worker: WorldActor, seat) -> float:
	if worker == null or seat == null or not is_instance_valid(seat):
		return INF
	if seat is Node3D:
		return worker.global_position.distance_squared_to((seat as Node3D).global_position)
	return 0.0


func _is_worker_near_service_area(worker: WorldActor, service_area: BarServiceArea) -> bool:
	if worker == null or service_area == null:
		return false
	return worker.global_position.distance_to(service_area.global_position) <= PLAYER_PARTY_JOB_ACTION_RADIUS


func _set_server_state(slot_state: Dictionary, state: String) -> void:
	slot_state["server_state"] = state
	slot_state["server_state_elapsed"] = 0.0


func _reset_server_service_state(slot_state: Dictionary) -> void:
	slot_state["target_service_seat"] = null
	slot_state["target_service_customer"] = null
	slot_state["target_service_order_id"] = ""
	slot_state["server_state"] = SERVER_STATE_IDLE
	slot_state["server_state_elapsed"] = 0.0
	slot_state["server_order_text"] = ""


func _release_server_customer_service(service_area: BarServiceArea, slot_state: Dictionary) -> void:
	var seat = slot_state.get("target_service_seat")
	if service_area != null and service_area.has_method("release_waiter_customer_service") and seat != null and is_instance_valid(seat):
		service_area.release_waiter_customer_service(seat)
	_reset_server_service_state(slot_state)


func _award_server_order_completion(job, worker: WorldActor, record: Dictionary) -> void:
	var chance := _server_order_charisma_chance(job, worker)
	var passed := _passes_server_order_charisma_check(chance)
	var tip := _server_order_tip(job) if passed else 0
	if tip > 0:
		record["owed_currency"] = int(record.get("owed_currency", 0)) + tip
	var charisma_xp := _server_order_charisma_xp(job, chance, passed)
	if worker != null and worker.has_method("add_skill_xp"):
		worker.add_skill_xp(SkillRules.ATTRIBUTE_CHARISMA, charisma_xp, "bar_waiter_service")
	if worker != null:
		if passed and tip > 0:
			worker.show_world_notice("+%d tip, +charisma" % tip, Color(0.5, 1.0, 0.65, 1.0), 1.4)
		else:
			worker.show_world_notice("+charisma" if charisma_xp > 0.0 else "No tip", Color(0.8, 0.82, 0.72, 1.0), 1.4)


func _passes_server_order_charisma_check(chance: float) -> bool:
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	return _rng.randf() <= chance


func _server_order_charisma_chance(job, worker: WorldActor) -> float:
	var level: int = 0
	if worker != null and worker.has_method("get_skill_level"):
		level = int(worker.get_skill_level(SkillRules.ATTRIBUTE_CHARISMA))
	var chance: float = _job_float(job, "server_charisma_base_chance", 0.25) + float(level) * _job_float(job, "server_charisma_chance_per_level", 0.022)
	return clampf(chance, _job_float(job, "server_charisma_min_chance", 0.05), _job_float(job, "server_charisma_max_chance", 0.9))


func _server_order_charisma_xp(job, chance: float, passed: bool) -> float:
	return SkillRules.get_chance_check_xp(chance, passed, _job_float(job, "server_charisma_xp_scale", 0.5))


func _server_order_tip(job) -> int:
	return maxi(0, _job_int(job, "server_tip_on_success", 1))


func _job_float(job, property_name: String, fallback: float) -> float:
	if job == null:
		return fallback
	var value: Variant = job.get(property_name)
	return fallback if value == null else float(value)


func _job_int(job, property_name: String, fallback: int) -> int:
	if job == null:
		return fallback
	var value: Variant = job.get(property_name)
	return fallback if value == null else int(value)


func _process_guard_post_shuffle(service_area: BarServiceArea, slot_state: Dictionary, worker: WorldActor, current_post, delta: float):
	var remaining := float(slot_state.get("guard_shuffle_remaining", _next_guard_shuffle_seconds()))
	remaining -= delta
	if remaining > 0.0:
		slot_state["guard_shuffle_remaining"] = remaining
		return current_post
	slot_state["guard_shuffle_remaining"] = _next_guard_shuffle_seconds()
	if service_area.get_guard_posts().size() <= 1:
		return current_post
	var next_post = service_area.get_available_guard_post(worker, current_post)
	if next_post == null:
		return current_post
	if next_post.has_method("claim_worker") and not next_post.claim_worker(worker):
		return current_post
	if current_post != null and current_post.has_method("release_worker"):
		current_post.release_worker(worker)
	slot_state["target_guard_post"] = next_post
	return next_post


func _resolve_best_resource(job_index: int, job, slot_state: Dictionary, worker: WorldActor):
	var resources := _resolve_nodes(job.resource_paths)
	if resources.is_empty():
		return null
	var claimed: Dictionary = {}
	for other_slot in _active_slots.get(job_index, []):
		var other_resource = other_slot.get("claimed_resource")
		if other_slot == slot_state or other_resource == null:
			continue
		claimed[other_resource.get_instance_id()] = true
	var best_node
	var best_distance := INF
	for resource_node in resources:
		if not (resource_node is MiningResourceNode):
			continue
		if claimed.has(resource_node.get_instance_id()):
			continue
		var distance: float = worker.global_position.distance_squared_to(resource_node.global_position)
		if distance < best_distance:
			best_distance = distance
			best_node = resource_node
	if best_node != null:
		return best_node
	var fallback_slot_index := int(slot_state.get("slot_index", 0)) % resources.size()
	return resources[fallback_slot_index]


func _resolve_best_container(job, slot_state: Dictionary, worker: WorldActor):
	var containers := _resolve_nodes(job.container_paths)
	var best_container = slot_state.get("target_container")
	if best_container != null and is_instance_valid(best_container):
		return best_container
	var best_distance := INF
	for container in containers:
		if not (container is WorldContainer):
			continue
		var distance: float = worker.global_position.distance_squared_to(container.global_position)
		if distance < best_distance:
			best_distance = distance
			best_container = container
	return best_container


func _resolve_nodes(paths: Array[NodePath]) -> Array:
	var nodes: Array = []
	for node_path in paths:
		var node := get_node_or_null(node_path)
		if node != null:
			nodes.append(node)
	return nodes


func _transfer_work_inventory_to_output(job, work_inventory: InventoryData, container: WorldContainer) -> void:
	if work_inventory == null:
		return
	if str(job.output_mode) == "abstract_sink":
		work_inventory.entries.clear()
		work_inventory.changed.emit()
		return
	if container == null or container.inventory == null:
		return
	for index in range(work_inventory.entries.size() - 1, -1, -1):
		var entry = work_inventory.entries[index]
		if entry == null or entry.definition == null:
			continue
		if not container.inventory.add_item_count(entry.definition, entry.count):
			continue
		work_inventory.entries.remove_at(index)
	work_inventory.changed.emit()


func _work_inventory_contains_blocked_stack(work_inventory: InventoryData) -> bool:
	if work_inventory == null:
		return false
	for entry in work_inventory.entries:
		if entry == null or entry.definition == null:
			continue
		if not work_inventory.can_add_item(entry.definition):
			return true
	return false


func _get_total_item_count(work_inventory: InventoryData) -> int:
	var total := 0
	for entry in work_inventory.entries:
		if entry != null:
			total += entry.count
	return total


func _end_slot_assignment(_job_index: int, slot_state: Dictionary, _caused_by_player: bool) -> void:
	var worker: WorldActor = slot_state.get("worker")
	if worker != null and is_instance_valid(worker):
		worker.end_job_assignment()
		if worker.has_method("stop_mining_assignment"):
			worker.stop_mining_assignment()
	var guard_post = slot_state.get("target_guard_post")
	if guard_post != null and is_instance_valid(guard_post) and guard_post.has_method("release_worker"):
		guard_post.release_worker(worker)
	var service_point = slot_state.get("target_service_point")
	if service_point != null and is_instance_valid(service_point) and service_point.has_method("release_worker"):
		service_point.release_worker(worker)
	var service_area := _resolve_bar_service_area()
	var service_seat = slot_state.get("target_service_seat")
	if service_area != null and service_seat != null and is_instance_valid(service_seat) and service_area.has_method("release_waiter_customer_service"):
		service_area.release_waiter_customer_service(service_seat)
	if worker != null:
		var record := _get_worker_record(worker)
		record["current_shift_seconds"] = float(record.get("current_shift_seconds", 0.0))
	slot_state["worker"] = null
	slot_state["work_inventory"] = null
	slot_state["claimed_resource"] = null
	slot_state["target_container"] = null
	slot_state["target_guard_post"] = null
	slot_state["target_service_point"] = null
	slot_state["target_service_seat"] = null
	slot_state["target_service_customer"] = null
	slot_state["target_service_order_id"] = ""
	slot_state["server_state"] = SERVER_STATE_IDLE
	slot_state["server_state_elapsed"] = 0.0
	slot_state["server_order_text"] = ""
	slot_state["guard_shuffle_remaining"] = _next_guard_shuffle_seconds()
	slot_state["accrued_interval_time"] = 0.0
	slot_state["last_work_active"] = false
	_sync_gecs_state()


func _is_job_offer_visible(worker: WorldActor, job_index: int) -> bool:
	if worker == null or job_index < 0 or job_index >= jobs.size():
		return false
	return _is_job_configured(jobs[job_index])


func _is_job_configured(job) -> bool:
	if job == null:
		return false
	match str(job.algorithm_id):
		"mine_and_haul":
			return not _resolve_nodes(job.resource_paths).is_empty() and not _resolve_nodes(job.container_paths).is_empty()
		"guard_post":
			var service_area := _resolve_bar_service_area()
			return service_area != null and not service_area.get_guard_posts().is_empty()
		"server_shift":
			var service_area := _resolve_bar_service_area()
			return service_area != null and not service_area.get_waiter_service_points().is_empty()
	return false


func _build_job_offer_text(job) -> String:
	var target_label := "that resource over there"
	var resources := _resolve_nodes(job.resource_paths)
	if not resources.is_empty() and resources[0] != null:
		var resource_label := str(resources[0].get("display_name"))
		if not resource_label.is_empty():
			target_label = resource_label.to_lower()
	match str(job.algorithm_id):
		"mine_and_haul":
			return "Yeah, if you want to mine %s, I'll pay you %d every %d seconds you work." % [target_label, int(job.pay_per_interval), int(round(job.pay_interval_seconds))]
		"guard_post":
			return "I need someone watching this place. Stand guard and I'll pay you %d every %d seconds on duty." % [int(job.pay_per_interval), int(round(job.pay_interval_seconds))]
		"server_shift":
			return "I need help serving tables. Hold the floor and I'll pay you %d every %d seconds on duty. Good service can earn %d silver in tips." % [int(job.pay_per_interval), int(round(job.pay_interval_seconds)), _server_order_tip(job)]
	return "I've got work if you want it. I'll pay you %d every %d seconds you work." % [int(job.pay_per_interval), int(round(job.pay_interval_seconds))]


func _build_job_accept_text(job) -> String:
	if job != null and str(job.algorithm_id) == "server_shift":
		return "Good. You're on the floor roster. Report for shifts and watch the tables."
	return "Good. You're on for %s." % job.get_display_name().to_lower()


func _build_job_accept_speech(job) -> String:
	if job != null and str(job.algorithm_id) == "server_shift":
		return "You're on the roster."
	return "You're hired."


func _resolve_bar_service_area() -> BarServiceArea:
	if not bar_service_area_path.is_empty():
		var explicit_service_area := get_node_or_null(bar_service_area_path) as BarServiceArea
		if explicit_service_area != null:
			return explicit_service_area
	var node: Node = get_parent()
	while node != null:
		if node is BarServiceArea:
			return node
		node = node.get_parent()
	return null


func _clear_pending_offer(worker: WorldActor) -> void:
	if worker == null:
		return
	_pending_job_offers.erase(_get_worker_key(worker))


func _get_worker_record(worker: WorldActor) -> Dictionary:
	if worker == null:
		return {}
	var key := _get_worker_key(worker)
	if not _worker_records.has(key):
		_worker_records[key] = {
			"owed_currency": 0,
			"total_worked_seconds": 0.0,
			"current_shift_seconds": 0.0,
			"break_until_time": 0.0,
			"last_job_index": -1,
		}
	return _worker_records[key]


func _find_worker_slot(worker: WorldActor) -> Dictionary:
	if worker == null:
		return {}
	for job_index in _active_slots.keys():
		var slots: Array = _active_slots[job_index]
		for slot_state in slots:
			if slot_state.get("worker") == worker:
				return {"job_index": int(job_index), "slot_state": slot_state}
	return {}


func _get_job_system_sim_time(delta: float) -> float:
	if is_inside_tree():
		var controller := get_tree().get_first_node_in_group("job_system_controller")
		if controller != null and controller.has_method("get_sim_time"):
			return float(controller.call("get_sim_time"))
	return _sim_time + delta


func _get_worker_key(worker: WorldActor) -> String:
	if worker == null:
		return ""
	if not worker.stable_id.is_empty():
		return worker.stable_id
	return str(worker.get_instance_id())


func _provider_id() -> String:
	return str(get_path()) if is_inside_tree() else str(get_instance_id())


func _job_contract_job_id(job, job_index: int) -> String:
	if job != null and not str(job.job_id).strip_edges().is_empty():
		return str(job.job_id).strip_edges()
	if job != null and not str(job.algorithm_id).strip_edges().is_empty():
		return str(job.algorithm_id).strip_edges()
	return str(job_index)


func _has_worker_contract(worker: WorldActor, job_id: String) -> bool:
	var bridge := _get_gecs_world()
	return bridge != null and bridge.has_method("has_actor_job_contract") and bool(bridge.call("has_actor_job_contract", _get_worker_key(worker), _provider_id(), job_id))


func _get_contract_count_for_job(job_id: String) -> int:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_job_contracts_for_provider"):
		return 0
	var count := 0
	for contract in bridge.call("get_job_contracts_for_provider", _provider_id()):
		if str(contract.get("job_id", "")) == job_id:
			count += 1
	return count


func _mark_contract_started(contract_id: String) -> void:
	if contract_id.is_empty():
		return
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("mark_job_contract_started"):
		bridge.call("mark_job_contract_started", contract_id, _sim_time)


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var current: Node = self
	while current != null:
		for child in current.get_children():
			if child is Node and (child as Node).is_in_group("gecs_world_controller"):
				return child as Node
		current = current.get_parent()
	return get_tree().get_first_node_in_group("gecs_world_controller")


func _get_job_system_controller() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("job_system_controller")


func _sync_gecs_state() -> void:
	if not is_inside_tree():
		return
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("sync_job_provider"):
		bridge.call("sync_job_provider", self, _active_slots, _worker_records, _sim_time)


func _next_guard_shuffle_seconds() -> float:
	var min_seconds := maxf(1.0, guard_shuffle_min_seconds)
	var max_seconds := maxf(min_seconds, guard_shuffle_max_seconds)
	return _rng.randf_range(min_seconds, max_seconds)
