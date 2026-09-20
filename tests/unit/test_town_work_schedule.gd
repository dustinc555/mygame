extends GutTest

const JOBS = preload("res://features/settlements/sim/job_system_controller.gd")
const POPULATION = preload("res://features/world_sim/sim/population/population_controller.gd")
const SCHEDULE = preload("res://features/settlements/resources/work_schedule.gd")
const STAFF_SLOT = preload("res://features/settlements/sim/c_game_staff_slot.gd")
const HOME = preload("res://features/settlements/bridge/home_resident_projection.gd")
const BED = preload("res://features/world/projection/props/sleepable_bed.gd")

class RestInteraction extends RefCounted:
	var current_sleep_target: Node
	var wakes := 0
	func stop_sleep_assignment() -> void: wakes += 1

class Sleeper extends Node:
	signal life_state_changed(previous: int, current: int)
	var life_state := NpcRules.LifeState.ASLEEP
	var interaction := RestInteraction.new()
	func get_interaction(): return interaction

class Worker extends Node:
	var party := false
	var fighting := false
	var player_order := false
	func is_player_party_member() -> bool: return party
	func is_in_combat() -> bool: return fighting
	func has_active_player_order() -> bool: return player_order

class Clock extends Node:
	signal hour_changed(absolute_hour: int, day: int, hour: int)
	var hour := 7
	func get_hour() -> int: return hour

class Residents extends Node:
	var actor: Node
	func get_live_actor(_id: String) -> Node: return actor

class Settlement extends Node:
	var home_requests: Array[String] = []
	var employment_requests := 0
	var releases := 0
	func release_actor_employment_duty(_town: String, _actor: String, _slot: String) -> void:
		releases += 1
	func refresh_assignment_slot_projection(_town: String, domain: String, _slot: String, _activity: String) -> void:
		if domain == "employment": employment_requests += 1
	func refresh_actor_residence_projection(_town: String, _actor: String, activity := "home_day") -> void:
		home_requests.append(activity)

class Provider extends Node:
	var active: Node
	var cancel_count := 0
	func has_active_work_for_actor(actor: Node) -> bool: return active == actor
	func cancel_work_for_actor(actor: Node) -> bool:
		if active != actor: return false
		active = null
		cancel_count += 1
		actor.remove_meta(&"active_settlement_work")
		return true

class Ledger extends Node:
	var slot: Dictionary
	func get_assignment_slot(_town: String, _domain: String, _slot: String) -> Dictionary: return slot

func _slot(scope := "town_labor") -> Dictionary:
	return {"slot_id": "town.farmer.0", "assignment_domain": "employment", "assignment_scope": scope,
		"filled": true, "uses_settlement_jobs": true, "occupant_actor_id": "farmer",
		"facility_id": "" if scope == "town_labor" else "granary", "owner_id": "town",
		"allowed_job_entry_ids": PackedStringArray(["category:farm", "category:haul"]),
		"work_schedule": {} if scope == "town_labor" else {"start_hour": 20, "end_hour": 6}}

func _fixture(scope := "town_labor") -> Dictionary:
	var host := Node.new()
	add_child_autofree(host)
	var clock := Clock.new()
	var residents := Residents.new()
	var settlement := Settlement.new()
	var provider := Provider.new()
	var actor := Worker.new()
	actor.set_meta("stable_id", "farmer")
	var jobs := JOBS.new()
	for node in [clock, residents, settlement, provider, actor]: host.add_child(node)
	residents.actor = actor
	var context := BootstrapContext.new(host)
	context.register(&"world_time", clock)
	context.register(&"population", residents)
	context.register(&"settlement", settlement)
	# Detached controller avoids unrelated startup. The real dispatcher still
	# resolves a live actor and uses real duty, queue and cancellation behavior.
	autofree(jobs)
	jobs._context = context
	jobs._settlement_controller = settlement
	jobs._job_providers = [provider]
	clock.hour_changed.connect(jobs._on_assignment_schedule_hour_changed)
	jobs._rebuild_assignment_workers_for_settlement("town", {"assignment_slots": {"employment:town.farmer.0": _slot(scope)},
		"facilities": {"granary": {"door_schedule_enabled": true, "door_open_hour": 20, "door_close_hour": 6}}})
	return {"jobs": jobs, "clock": clock, "actor": actor, "provider": provider, "settlement": settlement, "context": context}

func _dispatch(f: Dictionary, hour: int) -> void:
	f.clock.hour = hour
	f.clock.hour_changed.emit(hour, 0, hour)
	f.jobs._process_assignment_worker_dispatch({}, {}, {}, 8)

func test_town_farmer_is_only_available_from_08_inclusive_to_20_exclusive() -> void:
	var f := _fixture()
	var assignment: Dictionary = f.jobs._assignment_workers.farmer
	assert_true(bool(assignment.schedule_enabled))
	for hour in [0, 7, 8, 19, 20, 23]:
		f.clock.hour = hour
		assert_eq(f.jobs._assignment_schedule_is_active(assignment), hour == 8 or hour == 19, "hour=%d" % hour)

func test_closing_wakes_busy_worker_cancels_claim_and_hands_off_to_home() -> void:
	var f := _fixture()
	while not f.jobs._dequeue_assignment_worker().is_empty(): pass
	f.provider.active = f.actor
	f.actor.set_meta(&"active_settlement_work", true)
	f.jobs._begin_assignment_duty(f.actor, f.jobs._assignment_workers.farmer)
	_dispatch(f, 20)
	assert_eq(f.provider.cancel_count, 1)
	assert_null(f.provider.active)
	assert_false(f.actor.has_meta(&"active_facility_duty"))
	assert_eq(f.settlement.home_requests, ["home_day"])

func test_nighttime_realization_uses_bed_routine_not_forced_day_idle() -> void:
	var f := _fixture()
	f.clock.hour = 0
	f.jobs.notify_assignment_worker_realized("farmer")
	f.jobs._process_assignment_worker_dispatch({}, {}, {}, 8)
	assert_eq(f.settlement.home_requests, ["home_sleep"])

func test_off_shift_idle_moves_from_chair_routine_to_sleep_without_new_offers() -> void:
	var f := _fixture()
	_dispatch(f, 20)
	_dispatch(f, 21)
	_dispatch(f, 22)
	assert_eq(f.settlement.home_requests, ["home_day", "home_sleep"], "Stable idle must not restart each hour, but bedtime must refresh it")

func test_next_morning_requeues_worker_and_reopens_work() -> void:
	var f := _fixture()
	_dispatch(f, 20)
	f.clock.hour = 8
	f.clock.hour_changed.emit(32, 1, 8)
	assert_true(f.jobs._pending_assignment_actor_ids.has("farmer"))
	assert_true(f.jobs._assignment_schedule_is_active(f.jobs._assignment_workers.farmer))

func test_authored_facility_overnight_schedule_is_preserved() -> void:
	var f := _fixture("facility")
	for hour in [0, 5, 6, 8, 19, 20]:
		f.clock.hour = hour
		assert_eq(f.jobs._assignment_schedule_is_active(f.jobs._assignment_workers.farmer), hour < 6 or hour >= 20, "hour=%d" % hour)

func test_population_town_routine_agrees_with_work_cutoff_and_bedtime() -> void:
	var host: Node = autofree(Node.new())
	var ledger: Ledger = autofree(Ledger.new())
	ledger.slot = _slot()
	var context := BootstrapContext.new(host)
	context.register(&"gecs_world", ledger)
	var population: Node = autofree(POPULATION.new())
	population._context = context
	var record := {"settlement_id": "town", "assignments": {"employment": "town.farmer.0", "residence": "house.resident"}}
	for row in [[7, "home_day"], [8, "working"], [19, "working"], [20, "home_day"], [22, "home_sleep"], [0, "home_sleep"]]:
		assert_eq(population._ledger_activity_for_record(record, int(row[0]) * 60), str(row[1]), "hour=%d" % row[0])

func test_work_schedule_survives_canonical_slot_round_trip_without_aliasing() -> void:
	var component = STAFF_SLOT.new()
	var source := _slot("facility")
	component.apply_slot(source)
	source.work_schedule.start_hour = 9
	var saved: Dictionary = component.to_slot()
	assert_eq(saved.work_schedule, {"start_hour": 20, "end_hour": 6})
	var restored = STAFF_SLOT.new()
	restored.apply_slot(saved)
	saved.work_schedule.end_hour = 4
	assert_eq(restored.to_slot().work_schedule, {"start_hour": 20, "end_hour": 6})

func test_shift_overlap_counts_only_work_minutes_including_multiday_and_overnight() -> void:
	assert_eq(SCHEDULE.active_minutes({}, 19 * 60 + 30, 21 * 60), 30)
	assert_eq(SCHEDULE.active_minutes({}, 20 * 60, 32 * 60), 0)
	assert_eq(SCHEDULE.active_minutes({}, 0, 7 * 1440), 5040)
	var night := {"start_hour": 20, "end_hour": 6}
	assert_eq(SCHEDULE.active_minutes(night, 23 * 60, 31 * 60), 420)
	assert_eq(SCHEDULE.active_minutes({"start_hour": 8, "end_hour": 8}, 0, 1440), 1440)

func test_repeated_events_deduplicate_and_dispatch_respects_actor_cap() -> void:
	var f := _fixture()
	f.jobs._assignment_workers.clear()
	f.jobs._pending_assignment_actor_ids.clear()
	f.jobs._pending_assignment_actor_order.clear()
	for index in 50:
		var id := "worker_%d" % index
		f.jobs._assignment_workers[id] = {"actor_id": id, "schedule_enabled": true, "work_schedule": {}}
	f.clock.hour = 20
	for repeat in 3:
		f.jobs._on_assignment_schedule_hour_changed(20, 0, 20)
	assert_eq(f.jobs._pending_assignment_actor_ids.size(), 50)
	f.jobs._process_assignment_worker_dispatch({}, {}, {}, 4)
	assert_between(f.jobs._pending_assignment_actor_ids.size(), 46, 49)

func test_facility_door_hours_do_not_override_employment_schedule() -> void:
	var f := _fixture("facility")
	f.jobs._rebuild_assignment_workers_for_settlement("town", {"assignment_slots": {"employment:farmer": _slot("facility")},
		"facilities": {"granary": {"door_schedule_enabled": true, "door_open_hour": 8, "door_close_hour": 20}}})
	f.clock.hour = 23
	assert_true(f.jobs._assignment_schedule_is_active(f.jobs._assignment_workers.farmer))

func test_shift_expiry_denies_work_before_home_queue_is_processed() -> void:
	var f := _fixture()
	f.clock.hour = 19
	assert_true(f.jobs.is_actor_work_schedule_active(f.actor))
	f.clock.hour = 20
	assert_false(f.jobs.is_actor_work_schedule_active(f.actor))
	assert_true(f.jobs._pending_assignment_actor_ids.has("farmer"), "Still pending, but work is already forbidden")
	f.actor.party = true
	assert_true(f.jobs.is_actor_work_schedule_active(f.actor), "Player party Jobs are not NPC employment")

func test_population_night_shift_uses_employment_instead_of_default_bedtime() -> void:
	var host: Node = autofree(Node.new())
	var ledger: Ledger = autofree(Ledger.new())
	ledger.slot = _slot("facility")
	var context := BootstrapContext.new(host)
	context.register(&"gecs_world", ledger)
	var population: Node = autofree(POPULATION.new())
	population._context = context
	var record := {"settlement_id": "town", "assignments": {"employment": "night.worker", "residence": "house.resident"}}
	assert_eq(population._ledger_activity_for_record(record, 23 * 60), "working")
	assert_eq(population._ledger_activity_for_record(record, 19 * 60), "home_day")

func test_unbound_restored_sleep_requests_wake_before_physical_bed_reentry() -> void:
	var sleeper: Sleeper = autofree(Sleeper.new())
	var home = HOME.new()
	home._refresh_sleep(sleeper, sleeper.interaction)
	assert_eq(sleeper.interaction.wakes, 1, "Saved sleep is not a live bed reservation")
	var bed: Node = autofree(Node.new())
	sleeper.interaction.current_sleep_target = bed
	home._refresh_sleep(sleeper, sleeper.interaction)
	assert_eq(sleeper.interaction.wakes, 1, "An actual sleeping resident stays asleep")

func test_off_shift_wake_requeues_home_projection_after_async_life_transition() -> void:
	var f := _fixture()
	var sleeper := Sleeper.new()
	f.actor.get_parent().add_child(sleeper)
	f.context.get_optional(&"population").actor = sleeper
	_dispatch(f, 6)
	assert_false(f.jobs._pending_assignment_actor_ids.has("farmer"))
	sleeper.life_state_changed.emit(NpcRules.LifeState.ASLEEP, NpcRules.LifeState.ALIVE)
	assert_true(f.jobs._pending_assignment_actor_ids.has("farmer"))

func test_saved_mattress_position_is_not_reused_as_a_standing_exit() -> void:
	var bed = BED.new()
	add_child_autofree(bed)
	assert_false(bed.can_sleep_from_position(Vector3(0.0, 0.515, 0.1)), "Restored mattress origin needs a bed-side exit")
	assert_true(bed.can_sleep_from_position(Vector3(1.5, 0.0, 0.0)), "Normal bed-side arrival remains valid")

func test_shift_home_handoff_does_not_override_combat_or_player_orders() -> void:
	var f := _fixture()
	f.actor.fighting = true
	_dispatch(f, 20)
	assert_true(f.settlement.home_requests.is_empty())
	f.actor.fighting = false
	f.actor.player_order = true
	_dispatch(f, 22)
	assert_true(f.settlement.home_requests.is_empty())
	f.actor.player_order = false
	f.jobs.notify_assignment_worker_realized("farmer")
	f.jobs._process_assignment_worker_dispatch({}, {}, {}, 8)
	assert_eq(f.settlement.home_requests, ["home_sleep"])

func test_specialized_facility_staff_share_schedule_without_claiming_generic_offers() -> void:
	var f := _fixture("facility")
	var slot := _slot("facility")
	slot.uses_settlement_jobs = false
	slot.work_schedule = {"start_hour": 8, "end_hour": 20}
	f.jobs._rebuild_assignment_workers_for_settlement("town", {"assignment_slots": {"employment:staff": slot}})
	assert_true(f.jobs._assignment_workers.has("farmer"), "All employment shares one schedule lifecycle")
	_dispatch(f, 8)
	assert_eq(f.settlement.employment_requests, 1)
	assert_true(f.settlement.home_requests.is_empty(), "No generic offers does not send specialized staff home")
	_dispatch(f, 9)
	assert_eq(f.settlement.employment_requests, 1, "Same phase does not restart their role")
	_dispatch(f, 20)
	assert_eq(f.settlement.home_requests, ["home_day"])

func test_specialized_role_cannot_execute_until_jobs_grants_duty() -> void:
	var f := _fixture("facility")
	var slot := _slot("facility")
	slot.uses_settlement_jobs = false
	slot.work_schedule = {"start_hour": 0, "end_hour": 0}
	f.jobs._rebuild_assignment_workers_for_settlement("town", {"assignment_slots": {"employment:staff": slot}})
	f.clock.hour = 23
	assert_false(f.jobs.can_execute_assignment_duty(f.actor), "An open shift is not an execution grant")
	f.jobs._process_assignment_worker_dispatch({}, {}, {}, 8)
	assert_true(f.jobs.can_execute_assignment_duty(f.actor))
	assert_eq(f.settlement.employment_requests, 1)
	_dispatch(f, 0)
	assert_true(f.jobs.can_execute_assignment_duty(f.actor), "Always-on duty keeps its post at midnight")
	assert_true(f.settlement.home_requests.is_empty())
	f.actor.player_order = true
	assert_false(f.jobs.can_execute_assignment_duty(f.actor))
	_dispatch(f, 1)
	assert_false(f.actor.has_meta(&"active_facility_duty"), "Interruption revokes the role's authority")
	assert_gt(f.settlement.releases, 0)
	f.actor.player_order = false
	assert_false(f.jobs.can_execute_assignment_duty(f.actor), "Executor requests central reconciliation, not self-authorization")
	f.jobs._process_assignment_worker_dispatch({}, {}, {}, 8)
	assert_true(f.jobs.can_execute_assignment_duty(f.actor))

func test_execution_grant_expires_immediately_and_cannot_cross_employers() -> void:
	var f := _fixture()
	f.clock.hour = 19
	f.jobs._begin_assignment_duty(f.actor, f.jobs._assignment_workers.farmer)
	assert_true(f.jobs.can_execute_assignment_duty(f.actor))
	f.actor.set_meta(&"active_facility_duty", "another_employer")
	assert_false(f.jobs.can_execute_assignment_duty(f.actor))
	f.jobs._begin_assignment_duty(f.actor, f.jobs._assignment_workers.farmer)
	f.clock.hour = 20
	assert_false(f.jobs.can_execute_assignment_duty(f.actor), "Queued shutdown cannot extend a shift")

func test_guard_warden_and_innkeeper_defaults_are_always_on_but_farmer_is_scheduled() -> void:
	for role_id in ["guard", "warden", "barkeeper"]:
		var role = load("res://features/settlements/resources/roles/%s.tres" % role_id)
		assert_true(SCHEDULE.is_active(role.get_work_schedule_record(), 0), role_id)
		assert_true(SCHEDULE.is_active(role.get_work_schedule_record(), 7), role_id)
	var farmer = load("res://features/settlements/resources/roles/farmer.tres")
	assert_false(SCHEDULE.is_active(farmer.get_work_schedule_record(), 0))
