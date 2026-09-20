extends "res://tests/validation/test_case.gd"
## Run: python3 tests/run_validation.py --jobs 1 --filter tests/validation/validate_generic_assignment_worker.gd

const REMOVED_PROVIDER_PATH := "res://features/settlements/bridge/scheduled_farm_worker_provider.gd"
const TOMATO := preload("res://features/inventory/resources/items/tomato.tres")

class SyntheticCraftingProvider:
	extends Node3D
	signal work_offers_changed(settlement_id: String)
	var offer_enabled := true
	var target_actor_id := "granary_worker"
	var active_actor: Node
	var derealization_prepared := false
	func get_available_work_offers(settlement_id := "") -> Array:
		if not offer_enabled or (not settlement_id.is_empty() and settlement_id != "granary_demo"):
			return []
		return [{
			"offer_id": "synthetic:crafting",
			"category": "crafting",
			"job_entry_id": "category:crafting",
			"settlement_id": "granary_demo",
			"owner_faction_id": "Player",
			"world_position": Vector3(12, 0, -8),
			"provider": self,
			"allowed_actor_ids": PackedStringArray([target_actor_id]),
		}]
	func accept_work_offer(_offer: Dictionary, actor: Node) -> Dictionary:
		active_actor = actor
		return {"accepted": true}
	func has_active_work_for_actor(actor: Node) -> bool:
		return active_actor == actor
	func cancel_work_for_actor(actor: Node) -> bool:
		if active_actor != actor:
			return false
		active_actor = null
		return true
	func prepare_actor_for_derealization(actor: Node) -> void:
		derealization_prepared = true
		cancel_work_for_actor(actor)
	func clear_work() -> void:
		offer_enabled = false
		active_actor = null
		work_offers_changed.emit("granary_demo")
	func enable_work() -> void:
		offer_enabled = true
		active_actor = null
		work_offers_changed.emit("granary_demo")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_expect(not ResourceLoader.exists(REMOVED_PROVIDER_PATH), "farming-specific scheduled provider is removed")
	var game := (load("res://scenes/test_levels/granary_town_test.tscn") as PackedScene).instantiate()
	var granary := game.get_node("GranaryTown/Facilities/Granary")
	var role_slots: Array = granary.role_slots.duplicate()
	for index in range(2):
		var slot = role_slots[0].duplicate(true)
		slot.slot_id = "validation_worker_%d" % index
		slot.named_character = null
		role_slots.append(slot)
	granary.role_slots.assign(role_slots)
	root.add_child(game)
	current_scene = game
	for _frame in range(600):
		var ready_context := BootstrapContext.active
		if ready_context != null and ready_context.get_optional(&"job_system") != null and ready_context.get_optional(&"population") != null:
			if ready_context.require(&"population").get_live_actor("granary_worker") != null: break
		await process_frame
	var context := BootstrapContext.active
	var farming = context.get_optional(&"farming")
	for plot_id in (farming.get_plots() as Dictionary).keys():
		farming.remove_plot(str(plot_id))
	var jobs = context.get_optional(&"job_system")
	_expect(jobs != null and jobs.has_method("dispatch_actor_work_for_assignment"), "JobSystem owns generic assignment dispatch")
	_expect(game.get_node_or_null("GranaryTown/Facilities/Granary/ScheduledFarmWorkerProvider") == null, "Granary has no bespoke work provider")
	var synthetic := SyntheticCraftingProvider.new()
	game.add_child(synthetic)
	synthetic.add_to_group("job_provider")
	jobs.register_job_provider(synthetic)
	var worker = context.get_optional(&"population").get_live_actor("granary_worker")
	context.get_optional(&"world_time").advance_minutes(5.0)
	for _frame in 3:
		await process_frame
	jobs._process_party_job_dispatch()
	_expect(synthetic.active_actor == worker, "generic assignment worker claims a non-farming JobSystem offer")
	_expect(worker.has_meta(&"active_facility_duty"), "duty precedence starts only after generic work acceptance")
	synthetic.clear_work()
	jobs._process_party_job_dispatch()
	await process_frame
	var interaction = worker.get_interaction()
	var home = game.get_node("GranaryTown/Housing/WorkerHouse")
	_expect(not worker.has_meta(&"active_facility_duty") and interaction.current_seat_target != null and home.is_ancestor_of(interaction.current_seat_target), "no generic work returns assignment worker to residence")
	var seat = interaction.current_seat_target
	var stable_idle: bool = seat != null and bool(interaction.sit_at_seat_immediately(seat))
	for _attempt in 20:
		jobs._process_party_job_dispatch()
		await process_frame
		stable_idle = stable_idle and interaction.is_sitting and interaction.current_seat_target == seat and not worker.has_meta(&"active_facility_duty")
	_expect(stable_idle, "repeated generic dispatch keeps an idle resident stably seated")
	interaction.stop_seat_assignment()
	worker.global_position = Vector3(0, 0.6, -8)
	worker.inventory.add_item_count(TOMATO, 3)
	jobs.notify_work_offers_changed("granary_demo")
	jobs._process_party_job_dispatch()
	var bulk_haul = context.get_optional(&"haul")
	var haul_platform = bulk_haul._assignment_platform(worker) if bulk_haul != null else null
	_expect(haul_platform != null, "generic assignment worker claims the ordinary Haul category")
	if haul_platform != null:
		worker.container_reached.emit(worker, haul_platform)
		_expect(worker.inventory.count_item(TOMATO) == 0 and haul_platform.get_stored_item_count(TOMATO) == 3, "Haul provider owns NPC arrival and authoritative deposit")
	var overnight := {"schedule_enabled": true, "open_hour": 20, "close_hour": 6}
	_expect(not jobs._assignment_schedule_is_active(overnight), "overnight assignment is closed during daytime")
	context.get_optional(&"world_time").advance_hours(12.0)
	_expect(jobs._assignment_schedule_is_active(overnight), "overnight assignment is open after 20:00")
	context.get_optional(&"world_time").advance_hours(10.0)
	_expect(not jobs._assignment_schedule_is_active(overnight), "overnight assignment closes at 06:00")
	synthetic.enable_work()
	context.get_optional(&"world_time").advance_hours(2.0)
	jobs._process_party_job_dispatch()
	_expect(synthetic.active_actor == worker and worker.has_meta(&"active_facility_duty"), "assignment work is active before removal")
	jobs._process_party_job_dispatch()
	_expect(jobs._pending_assignment_actor_ids.is_empty(), "active-worker queue drains before LOD without injected clears")
	var settlements = context.get_optional(&"settlement")
	var worker_slot := _assignment_slot_for_actor(settlements.get_settlement_state("granary_demo"), "granary_worker")
	var old_worker_instance_id: int = int(worker.get_instance_id())
	settlements.derealize_assignment_slot("granary_demo", str(worker_slot.get("assignment_domain", "employment")), str(worker_slot.get("slot_id", "")))
	await process_frame
	await process_frame
	_expect(synthetic.derealization_prepared and synthetic.active_actor == null, "assignment LOD asks providers to finish volatile work before freeing the worker")
	_expect(settlements.realize_assignment_slot("granary_demo", str(worker_slot.get("assignment_domain", "employment")), str(worker_slot.get("slot_id", ""))), "assignment worker re-realizes after an LOD round trip")
	await process_frame
	worker = context.get_optional(&"population").get_live_actor("granary_worker")
	jobs._process_party_job_dispatch()
	_expect(worker != null and worker.get_instance_id() != old_worker_instance_id and synthetic.active_actor == worker, "re-realized assignment worker is immediately requeued and resumes ordinary Jobs work")
	await _validate_three_worker_lod(context, synthetic)
	worker = context.require(&"population").get_live_actor("granary_worker")
	synthetic.target_actor_id = "granary_worker"
	synthetic.enable_work()
	jobs._process_party_job_dispatch()
	_expect(synthetic.active_actor == worker, "provider removal starts with active accepted work")
	jobs.unregister_job_provider(synthetic)
	synthetic.free()
	await process_frame
	jobs._process_party_job_dispatch()
	_expect(not worker.has_meta(&"active_facility_duty"), "removing the active provider must release obsolete duty on next dispatch")
	# A different lifetime: the destination disappears while the worker carries real stock.
	worker.inventory.add_item_count(TOMATO, 2)
	jobs.notify_work_offers_changed("granary_demo")
	jobs._process_party_job_dispatch()
	var removed_target = bulk_haul._assignment_platform(worker)
	_expect(removed_target != null, "target-loss fixture must start a pending real haul")
	if removed_target != null:
		removed_target.free()
		await process_frame
		jobs._process_party_job_dispatch()
		_expect(not bulk_haul.has_active_work_for_actor(worker) and worker.inventory.count_item(TOMATO) == 2, "destroyed destination cancels haul without consuming carried stock")
	jobs._rebuild_assignment_workers_for_settlement("granary_demo", {"settlement_id": "granary_demo", "assignment_slots": {}, "facilities": {}})
	_expect(not worker.has_meta(&"active_facility_duty"), "removing assignment clears facility duty")
	root.remove_child(game)
	game.free()
	_finish()


func _validate_three_worker_lod(context: BootstrapContext, provider: SyntheticCraftingProvider) -> void:
	var settlements: Node = context.require(&"settlement")
	var population: Node = context.require(&"population")
	var jobs: Node = context.require(&"job_system")
	var haul: Node = context.require(&"haul")
	var slots: Array[Dictionary] = []
	for slot in settlements.get_settlement_state("granary_demo").get("assignment_slots", {}).values():
		if slot.get("assignment_domain") == "employment" and slot.get("role_id") == "worker": slots.append(slot)
	_expect(slots.size() == 3, "three-worker LOD proof requires three real authored employment assignments")
	var completed := 0
	for slot in slots:
		var actor_id := str(slot.get("occupant_actor_id", ""))
		_expect(not actor_id.is_empty(), "each worker slot needs a canonical person")
		settlements.realize_assignment_slot("granary_demo", "employment", str(slot.slot_id))
		await process_frame
		var actor: Node = population.get_live_actor(actor_id)
		if actor == null:
			_expect(false, "assigned worker did not realize: " + actor_id)
			continue
		provider.target_actor_id = actor_id
		provider.enable_work()
		jobs._process_party_job_dispatch()
		_expect(provider.active_actor == actor, "each worker accepts normal category work before LOD: " + actor_id)
		var old_instance_id := actor.get_instance_id()
		var before: Dictionary = population.get_actor_record(actor_id)
		settlements.derealize_assignment_slot("granary_demo", "employment", str(slot.slot_id))
		await process_frame
		_expect(not is_instance_valid(actor), "LOD must actually destroy the previous worker instance")
		settlements.realize_assignment_slot("granary_demo", "employment", str(slot.slot_id))
		await process_frame
		actor = population.get_live_actor(actor_id)
		jobs._process_party_job_dispatch()
		_expect(actor != null and actor.get_instance_id() != old_instance_id and provider.active_actor == actor, "real settlement re-realization requeues and dispatches each permanent worker")
		var after: Dictionary = population.get_actor_record(actor_id)
		_expect(after.get("assignments") == before.get("assignments") and after.get("member_name") == before.get("member_name"), "real LOD preserves stable identity and one residence/employment mapping")
		provider.clear_work()
		actor.inventory.add_item_count(TOMATO, 1)
		jobs.notify_work_offers_changed("granary_demo")
		jobs._process_party_job_dispatch()
		var platform = haul._assignment_platform(actor)
		_expect(platform != null, "re-realized worker can start productive ordinary haul")
		if platform != null:
			var stock_before: int = platform.get_stored_item_count(TOMATO)
			actor.container_reached.emit(actor, platform)
			_expect(actor.inventory.count_item(TOMATO) == 0 and platform.get_stored_item_count(TOMATO) == stock_before + 1, "each restored worker transfers actual inventory to stock, not just a requeue notification")
			completed += 1
	_expect(completed == 3, "all three restored workers must complete the real stock deposit")


func _assignment_slot_for_actor(state: Dictionary, actor_id: String) -> Dictionary:
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if str(slot.get("occupant_actor_id", "")) == actor_id:
			return slot
	return {}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("GENERIC_ASSIGNMENT_WORKER_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("GENERIC_ASSIGNMENT_WORKER_FAILED count=%d" % failures.size())
	quit(1)
