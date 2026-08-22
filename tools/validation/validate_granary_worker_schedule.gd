extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_granary_worker_schedule.gd

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/test_levels/granary_town_test.tscn") as PackedScene
	var level = packed.instantiate() if packed != null else null
	_expect(level != null, "granary town runtime level loads")
	if level == null:
		_finish()
		return
	root.add_child(level)
	current_scene = level
	for _frame in 90:
		await process_frame
	var context := BootstrapContext.active
	var world_time = context.get_optional(&"world_time") if context != null else null
	var farm_work = context.get_optional(&"farm_work") if context != null else null
	var farming = context.get_optional(&"farming") if context != null else null
	var jobs = context.get_optional(&"job_system") if context != null else null
	var population = context.get_optional(&"population") if context != null else null
	var settlements = context.get_optional(&"settlement") if context != null else null

	var worker = population.get_live_actor("granary_worker") if population != null and population.has_method("get_live_actor") else null
	_expect(worker != null, "the same permanent resident-worker is realized")
	var non_party_resident_ids: Array[String] = []
	for record_value in population.get_records_for_settlement("granary_demo") if population != null else []:
		var record: Dictionary = record_value
		if str(record.get("party_id", "")).is_empty():
			non_party_resident_ids.append(str(record.get("actor_id", record.get("stable_id", ""))))
	non_party_resident_ids.sort()
	_expect(non_party_resident_ids == ["granary_worker"], "the town realizes exactly one non-party NPC")
	var state: Dictionary = settlements.get_settlement_state("granary_demo") if settlements != null else {}
	var worker_slots := 0
	var resident_slots := 0
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if str(slot.get("occupant_actor_id", "")) != "granary_worker":
			continue
		if str(slot.get("assignment_domain", "")) == "employment" and str(slot.get("role_id", "")) == "worker":
			worker_slots += 1
		elif str(slot.get("assignment_domain", "")) == "residence" and str(slot.get("role_id", "")) == "resident":
			resident_slots += 1
	_expect(worker_slots == 1 and resident_slots == 1, "one NPC holds both Granary Worker and house Resident assignments")
	jobs._process_party_job_dispatch()
	_expect(not worker.has_meta(&"active_facility_duty"), "before opening, assignment work remains inactive")
	await process_frame
	var worker_interaction = worker.get_interaction() if worker != null and worker.has_method("get_interaction") else null
	var home = level.get_node("GranaryTown/Housing/WorkerHouse")
	_expect(worker_interaction != null and worker_interaction.current_seat_target != null \
			and home.is_ancestor_of(worker_interaction.current_seat_target), "before opening, the Resident uses the cottage rather than the Granary")
	var town_plots: Array[Dictionary] = []
	for plot_value in (farming.get_plots() as Dictionary).values() if farming != null else []:
		var plot: Dictionary = plot_value
		if str(plot.get("settlement_id", "")) == "granary_demo":
			town_plots.append(plot)
	_expect(town_plots.size() == 3, "runtime creates exactly three durable Granary Hamlet fields")
	var crop_policies: Dictionary = {}
	for plot in town_plots:
		_expect((plot.get("cells", {}) as Dictionary).size() == 16, "each runtime field has sixteen 4x4 cells")
		crop_policies[str(plot.get("crop_policy_id", ""))] = true
	_expect(crop_policies.size() == 3, "runtime fields keep three distinct crop policies")
	var worker_assignment: Dictionary = jobs._assignment_workers.get("granary_worker", {})
	_expect(bool(worker_assignment.get("schedule_enabled", false)) and int(worker_assignment.get("open_hour", -1)) == 8 \
			and int(worker_assignment.get("close_hour", -1)) == 20, "existing facility hours drive assignment availability")
	var ada = level.get_node("PartyMembers/Ada")
	var party_enabled: bool = jobs != null and bool(jobs.set_actor_jobs_enabled(ada, true))
	var party_dispatched: bool = bool(jobs.dispatch_actor_work(ada)) if jobs != null else false
	_expect(party_enabled and party_dispatched \
			and farm_work != null and farm_work.has_active_work_for_actor(ada), "Jobs-enabled player character assists the same available Farm offers before Granary hours")
	if farm_work != null:
		farm_work.cancel_work_for_actor(ada)
	if jobs != null:
		jobs.set_actor_jobs_enabled(ada, false)
	if world_time != null and world_time.has_method("advance_minutes"):
		world_time.advance_minutes(5.0)
	await process_frame
	jobs._process_party_job_dispatch()
	_expect(farm_work != null and bool(farm_work.has_active_work_for_actor(worker)), "at 08:00 the assigned Worker claims shared Farm work")
	_expect(worker != null and worker.has_meta(&"active_settlement_work") \
			and worker.has_meta(&"active_facility_duty"), "generic employment duty owns the actor over residence behavior during shift")
	_expect(worker_interaction == null or worker_interaction.current_seat_target == null, "employment releases the cottage seat before taking movement ownership")
	var completed_physical_farm_work := false
	for frame_index in 1800:
		await physics_frame
		if frame_index % 6 == 0 and _town_has_physically_tilled_cell(farming):
			completed_physical_farm_work = true
			break
	_expect(completed_physical_farm_work, "the assigned Worker physically reaches a field and completes shared Farm work")
	if farm_work != null and worker != null:
		farm_work.cancel_work_for_actor(worker)
		for plot_id_value in (farming.get_plots() as Dictionary).keys():
			farming.remove_plot(str(plot_id_value))
		for _frame in 3:
			await process_frame
		jobs._process_party_job_dispatch()
		_expect(not worker.has_meta(&"active_facility_duty"), "an on-shift Worker with no available work becomes idle")
		await process_frame
		_expect(not worker.has_meta(&"active_facility_duty") and worker_interaction.current_seat_target != null \
				and home.is_ancestor_of(worker_interaction.current_seat_target), "idle on-shift Worker returns to residence behavior")
	if world_time != null and world_time.has_method("advance_hours"):
		world_time.advance_hours(12.0)
	for _frame in 3:
		await process_frame
	jobs._process_party_job_dispatch()
	_expect(int(world_time.get_hour()) >= 20, "Granary assignment closes at 20:00")
	_expect(farm_work == null or worker == null or not bool(farm_work.has_active_work_for_actor(worker)), "closing time releases unfinished Granary farming work")
	_expect(worker == null or not worker.has_meta(&"active_facility_duty"), "closing time releases the generic facility-duty precedence lock")
	_expect(worker_interaction != null and worker_interaction.current_seat_target != null \
			and home.is_ancestor_of(worker_interaction.current_seat_target), "at closing, residence behavior immediately resumes at the cottage")
	root.remove_child(level)
	level.free()
	_finish()


func _town_has_physically_tilled_cell(farming: Node) -> bool:
	if farming == null:
		return false
	for plot_value in (farming.get_plots() as Dictionary).values():
		var plot: Dictionary = plot_value
		if str(plot.get("settlement_id", "")) != "granary_demo":
			continue
		for cell_value in (plot.get("cells", {}) as Dictionary).values():
			if bool((cell_value as Dictionary).get("soil_created", false)):
				return true
	return false



func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("GRANARY_WORKER_SCHEDULE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("GRANARY_WORKER_SCHEDULE_FAILED count=%d" % failures.size())
	quit(1)
