extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_generic_assignment_worker.gd

const REMOVED_PROVIDER_PATH := "res://features/settlements/bridge/scheduled_farm_worker_provider.gd"
const TOMATO := preload("res://features/inventory/resources/items/tomato.tres")

class SyntheticCraftingProvider:
	extends Node3D
	var offer_enabled := true
	var active_actor: Node
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
	func clear_work() -> void:
		offer_enabled = false
		active_actor = null
	func enable_work() -> void:
		offer_enabled = true
		active_actor = null

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_expect(not ResourceLoader.exists(REMOVED_PROVIDER_PATH), "farming-specific scheduled provider is removed")
	var game := (load("res://scenes/test_levels/granary_town_test.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _frame in 90:
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
	jobs._process_party_job_dispatch()
	var bulk_haul = context.get_optional(&"bulk_storage_haul")
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
	jobs._rebuild_assignment_workers_for_settlement("granary_demo", {"settlement_id": "granary_demo", "assignment_slots": {}, "facilities": {}})
	_expect(synthetic.active_actor == null and not worker.has_meta(&"active_facility_duty"), "removing assignment cancels provider work and facility duty")
	jobs.unregister_job_provider(synthetic)
	root.remove_child(game)
	game.free()
	_finish()

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
