extends Node

class_name JobProvider

const DEFAULT_WORK_INVENTORY_COLUMNS := 4
const DEFAULT_WORK_INVENTORY_ROWS := 4
const JOB_DEFINITION_SCRIPT = preload("res://scripts/jobs/job_definition.gd")
const ACTOR_CONDITION_EVALUATOR_SCRIPT = preload("res://scripts/conditions/actor_condition_evaluator.gd")

@export var jobs: Array[JobDefinition] = []
@export var wage_item_definition: Resource
@export var bar_venue_path: NodePath
@export var max_on_duty_seconds := 90.0
@export var break_duration_seconds := 45.0
@export var greeting_return_threshold_seconds := 30.0

var _worker_records: Dictionary = {}
var _active_slots: Dictionary = {}
var _sim_time := 0.0
var _pending_job_offers: Dictionary = {}


func _ready() -> void:
	add_to_group("job_provider")
	_initialize_slots()


func set_sim_time(value: float) -> void:
	_sim_time = value


func get_provider_character() -> HumanoidCharacter:
	return get_parent() as HumanoidCharacter


func get_provider_name() -> String:
	var provider := get_provider_character()
	return provider.member_name if provider != null else name


func get_greeting_text_for(worker: HumanoidCharacter, fallback: String) -> String:
	var record := _get_worker_record(worker)
	if float(record.get("total_worked_seconds", 0.0)) >= greeting_return_threshold_seconds:
		return "Back again?"
	return fallback


func build_conversation_options(worker: HumanoidCharacter) -> Array:
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


func handle_conversation_option(worker: HumanoidCharacter, option: Dictionary) -> Dictionary:
	var action := str(option.get("job_provider_action", ""))
	match action:
		"request_job":
			var job_index := int(option.get("job_index", -1))
			return _handle_job_request_prompt(worker, job_index)
		"accept_job_offer":
			return _handle_job_accept(worker, int(option.get("job_index", -1)))
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


func pause_worker_job(worker: HumanoidCharacter, caused_by_player: bool = false) -> void:
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
		if _active_slots.has(job_index):
			continue
		var slots: Array = []
		for slot_index in range(max(job.slot_count, 1)):
			slots.append({
				"slot_index": slot_index,
				"worker": null,
				"work_inventory": null,
				"claimed_resource": null,
				"target_container": null,
				"target_guard_post": null,
				"target_service_point": null,
				"accrued_interval_time": 0.0,
			})
		_active_slots[job_index] = slots


func _evaluate_job_request(worker: HumanoidCharacter, job_index: int) -> Dictionary:
	var job = jobs[job_index]
	if job == null:
		return {"allowed": false, "reason": "No job configured"}
	if not _is_job_configured(job):
		return {"allowed": false, "reason": ""}
	if worker.get_active_job_provider() != null:
		return {"allowed": false, "reason": "Already working"}
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
	if _find_open_slot(job_index) < 0:
		return {"allowed": false, "reason": "No openings right now"}
	return {"allowed": true, "reason": ""}


func _handle_job_request_prompt(worker: HumanoidCharacter, job_index: int) -> Dictionary:
	var evaluation := _evaluate_job_request(worker, job_index)
	if not evaluation.get("allowed", false):
		return {"end_conversation": true}
	var job = jobs[job_index]
	_pending_job_offers[_get_worker_key(worker)] = job_index
	return {
		"speaker_text": _build_job_offer_text(job),
		"end_conversation": false,
		"follow_up_options": [
			{"text": "Accept", "job_provider_action": "accept_job_offer", "job_index": job_index},
			{"text": "Not right now", "job_provider_action": "decline_job_offer", "job_index": job_index},
			{"text": "Leave", "job_provider_action": "leave_conversation", "job_index": job_index},
		],
	}


func _handle_job_accept(worker: HumanoidCharacter, job_index: int) -> Dictionary:
	if _pending_job_offers.get(_get_worker_key(worker), -1) != job_index:
		return {"end_conversation": true}
	_clear_pending_offer(worker)
	var evaluation := _evaluate_job_request(worker, job_index)
	if not evaluation.get("allowed", false):
		return {"end_conversation": true}
	var slot_index := _find_open_slot(job_index)
	if slot_index < 0:
		return {"end_conversation": true}
	var job = jobs[job_index]
	var slot_state: Dictionary = _active_slots[job_index][slot_index]
	var work_inventory := InventoryData.new(DEFAULT_WORK_INVENTORY_COLUMNS, DEFAULT_WORK_INVENTORY_ROWS, 0.0, false)
	slot_state["worker"] = worker
	slot_state["work_inventory"] = work_inventory
	slot_state["claimed_resource"] = null
	slot_state["target_container"] = null
	slot_state["accrued_interval_time"] = 0.0
	var record := _get_worker_record(worker)
	record["current_shift_seconds"] = 0.0
	record["last_job_index"] = job_index
	worker.begin_job_assignment(self, job.get_display_name(), work_inventory)
	return {
		"speaker_text": "Good. Get to work on %s." % job.get_display_name().to_lower(),
		"end_conversation": true,
		"show_floating_notice": false,
		"speech_target": get_provider_character(),
		"speech_text": "Good. Get to work.",
		"speech_lifetime": 5.0,
	}


func _handle_collect_pay(worker: HumanoidCharacter) -> Dictionary:
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
	if worker.inventory == null or not worker.inventory.add_item_count(wage_item_definition, owed_currency):
		return {
			"speaker_text": "Make some room first.",
			"end_conversation": true,
			"show_floating_notice": false,
			"speech_target": provider,
			"speech_text": "Make some room first.",
			"speech_lifetime": 5.0,
		}
	record["owed_currency"] = 0
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


func _process_slot(job_index: int, job, slot_state: Dictionary, delta: float) -> void:
	var worker: HumanoidCharacter = slot_state.get("worker")
	if worker == null:
		return
	if not is_instance_valid(worker) or worker.life_state != NpcRules.LifeState.ALIVE:
		_end_slot_assignment(job_index, slot_state, false)
		return
	if worker.get_active_job_provider() != self:
		_end_slot_assignment(job_index, slot_state, false)
		return
	var is_meaningfully_working := false
	match job.algorithm_id:
		"mine_and_haul":
			is_meaningfully_working = _process_mine_and_haul(job_index, job, slot_state, worker)
		"guard_post":
			is_meaningfully_working = _process_guard_post(job_index, job, slot_state, worker)
		"server_shift":
			is_meaningfully_working = _process_server_shift(job_index, job, slot_state, worker)
	if not is_meaningfully_working:
		return
	var record := _get_worker_record(worker)
	var on_duty_seconds := float(record.get("current_shift_seconds", 0.0)) + delta
	record["current_shift_seconds"] = on_duty_seconds
	if on_duty_seconds >= max_on_duty_seconds:
		record["break_until_time"] = _sim_time + break_duration_seconds
		worker.show_world_notice("%s says take a break" % get_provider_name(), Color(0.95, 0.85, 0.45, 1.0))
		_end_slot_assignment(job_index, slot_state, false)
		return
	slot_state["accrued_interval_time"] = float(slot_state.get("accrued_interval_time", 0.0)) + delta
	while float(slot_state.get("accrued_interval_time", 0.0)) >= maxf(job.pay_interval_seconds, 0.01):
		slot_state["accrued_interval_time"] = float(slot_state.get("accrued_interval_time", 0.0)) - maxf(job.pay_interval_seconds, 0.01)
		record["owed_currency"] = int(record.get("owed_currency", 0)) + job.pay_per_interval
		record["total_worked_seconds"] = float(record.get("total_worked_seconds", 0.0)) + job.pay_interval_seconds


func _process_mine_and_haul(job_index: int, job, slot_state: Dictionary, worker: HumanoidCharacter) -> bool:
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


func _process_guard_post(_job_index: int, _job, slot_state: Dictionary, worker: HumanoidCharacter) -> bool:
	var post = slot_state.get("target_guard_post")
	if post == null or not is_instance_valid(post):
		var venue := _resolve_bar_venue()
		if venue == null:
			return false
		post = venue.get_available_guard_post(worker)
		if post == null:
			return false
		if post.has_method("claim_worker") and not post.claim_worker(worker):
			return false
		slot_state["target_guard_post"] = post
	var work_position: Vector3 = post.get_work_position()
	if worker.global_position.distance_to(work_position) > worker.interact_distance:
		worker.set_move_target(work_position, false)
		return false
	if post.has_method("is_worker_at_post"):
		return post.is_worker_at_post(worker)
	return true


func _process_server_shift(_job_index: int, _job, slot_state: Dictionary, worker: HumanoidCharacter) -> bool:
	var service_point = slot_state.get("target_service_point")
	if service_point == null or not is_instance_valid(service_point):
		var venue := _resolve_bar_venue()
		if venue == null:
			return false
		service_point = venue.get_service_point()
		if service_point == null:
			return false
		slot_state["target_service_point"] = service_point
	var work_position: Vector3 = service_point.get_work_position()
	if worker.global_position.distance_to(work_position) > worker.interact_distance:
		worker.set_move_target(work_position, false)
		return false
	if service_point.has_method("is_worker_at_point"):
		return service_point.is_worker_at_point(worker)
	return true


func _resolve_best_resource(job_index: int, job, slot_state: Dictionary, worker: HumanoidCharacter):
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


func _resolve_best_container(job, slot_state: Dictionary, worker: HumanoidCharacter):
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


func _end_slot_assignment(job_index: int, slot_state: Dictionary, _caused_by_player: bool) -> void:
	var worker: HumanoidCharacter = slot_state.get("worker")
	if worker != null and is_instance_valid(worker):
		worker.end_job_assignment()
		worker.stop_mining_assignment()
	var guard_post = slot_state.get("target_guard_post")
	if guard_post != null and is_instance_valid(guard_post) and guard_post.has_method("release_worker"):
		guard_post.release_worker(worker)
	if worker != null:
		var record := _get_worker_record(worker)
		record["current_shift_seconds"] = float(record.get("current_shift_seconds", 0.0))
	slot_state["worker"] = null
	slot_state["work_inventory"] = null
	slot_state["claimed_resource"] = null
	slot_state["target_container"] = null
	slot_state["target_guard_post"] = null
	slot_state["target_service_point"] = null
	slot_state["accrued_interval_time"] = 0.0


func _is_job_offer_visible(worker: HumanoidCharacter, job_index: int) -> bool:
	var evaluation := _evaluate_job_request(worker, job_index)
	return evaluation.get("allowed", false)


func _is_job_configured(job) -> bool:
	if job == null:
		return false
	match str(job.algorithm_id):
		"mine_and_haul":
			return not _resolve_nodes(job.resource_paths).is_empty() and not _resolve_nodes(job.container_paths).is_empty()
		"guard_post":
			var venue := _resolve_bar_venue()
			return venue != null and not venue.get_guard_posts().is_empty()
		"server_shift":
			var venue := _resolve_bar_venue()
			return venue != null and not venue.get_service_points().is_empty()
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
			return "I need help serving tables. Stay ready for orders and I'll pay you %d every %d seconds." % [int(job.pay_per_interval), int(round(job.pay_interval_seconds))]
	return "I've got work if you want it. I'll pay you %d every %d seconds you work." % [int(job.pay_per_interval), int(round(job.pay_interval_seconds))]


func _resolve_bar_venue() -> BarVenue:
	if not bar_venue_path.is_empty():
		var explicit_venue := get_node_or_null(bar_venue_path) as BarVenue
		if explicit_venue != null:
			return explicit_venue
	var node: Node = get_parent()
	while node != null:
		if node is BarVenue:
			return node
		node = node.get_parent()
	return null


func _clear_pending_offer(worker: HumanoidCharacter) -> void:
	if worker == null:
		return
	_pending_job_offers.erase(_get_worker_key(worker))


func _get_worker_record(worker: HumanoidCharacter) -> Dictionary:
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


func _get_worker_key(worker: HumanoidCharacter) -> String:
	if worker == null:
		return ""
	if not worker.stable_id.is_empty():
		return worker.stable_id
	return str(worker.get_instance_id())
