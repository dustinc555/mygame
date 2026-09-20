extends "res://tests/validation/test_case.gd"
## Run (serialize with other Godot runs):
## timeout 600s godot --headless --path . res://tests/validation/test_host.tscn -- res://tests/validation/validate_town_work_schedule_runtime.gd
## Physical schedule proof, not a skipped-time/needs or rendered-animation test.
## Only the clock is held between phase boundaries; movement/work run normally.

const SCENE_PATH := "res://scenes/test_levels/granary_town_test.tscn"
const FIELD_PATH := "res://features/settlements/bridge/settlement_field.tscn"
const SETTLEMENT_ID := "granary_demo"
const WALL_LIMIT_SECONDS := 540.0
const APPROACH_SECONDS := 60.0
const WORK_SECONDS := 90.0

var _failures: Array[String] = []
var _scene: Node3D
var _house: SettlementFacilityInstance
var _bed: SleepableBed
var _population: Node
var _settlements: Node
var _jobs: Node
var _farm: Node
var _farm_work: Node
var _clock: Node
var _actor_id := ""
var _employment_slot: Dictionary = {}
var _residence_slot: Dictionary = {}
var _deadline_msec := 0
var _finished := false


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + int(WALL_LIMIT_SECONDS * 1000.0)
	create_timer(WALL_LIMIT_SECONDS, true, false, true).timeout.connect(_watchdog)
	_run.call_deferred()


func _run() -> void:
	if await _load_fixture():
		if await _validate_work_and_home():
			await _validate_night_lod_and_resume()
	_finish()


func _load_fixture() -> bool:
	_scene = (load(SCENE_PATH) as PackedScene).instantiate()
	# Convert the fixture BEFORE bootstrap, using real authoring surfaces. A
	# generated Home resident becomes the structural field's town farmer;
	# there is no Granary employment slot, fake worker map, or actor spawn.
	var town = _scene.get_node("GranaryTown")
	var definition = town.settlement_definition.duplicate(false)
	definition.generation_seed = 48127
	town.settlement_definition = definition
	var granary = town.get_node("Facilities/Granary")
	granary.role_slots.clear()
	_house = town.get_node("Housing/WorkerHouse")
	var resident_slot = _house.role_slots[0].duplicate(true)
	resident_slot.named_character = null
	_house.role_slots.assign([resident_slot])
	# Replace the scripted demo plots with one real field facility so the
	# production town demand calculation, not this test, creates employment.
	var scenario := _scene.get_node("Scenario")
	_scene.remove_child(scenario)
	scenario.free()
	var field = (load(FIELD_PATH) as PackedScene).instantiate()
	field.name = "ScheduleField"
	field.facility_id = "granary_demo.schedule_field"
	field.owner_faction_id = "Player"
	field.dimensions = Vector2i(4, 4)
	field.crop_policy_id = ""
	field.position = Vector3(1.0, 0.02, -2.0)
	town.get_node("Facilities").add_child(field)
	root.add_child(_scene)
	current_scene = _scene
	if not await _wait_until(func() -> bool:
		var pending_context := BootstrapContext.active
		return pending_context != null and pending_context.get_optional(&"world_time") != null and pending_context.get_optional(&"settlement") != null
	, 30.0):
		return _check(false, "fixture must bootstrap real services")
	var context := BootstrapContext.active
	_population = context.require(&"population")
	_settlements = context.require(&"settlement")
	_jobs = context.require(&"job_system")
	_farm = context.require(&"farming")
	_farm_work = context.require(&"farm_work")
	_clock = context.require(&"world_time")
	# Stop automatic CLOCK advancement, not the SceneTree/actors/controllers.
	# Normal WorldTime boundary APIs below still emit their production events.
	_clock.set_process(false)
	_clock.set_time_of_day(7, 55)
	var navigation = context.require(&"world_navigation")
	if not await _wait_until(func() -> bool:
		return navigation.get("_mode") != WorldNavigationController.Mode.INACTIVE and not navigation.is_initial_navigation_pending() and not _clock.is_world_paused()
	, 90.0):
		return _check(false, "navigation/loading must finish without clearing another owner's pause")
	if not await _wait_until(_find_farmer, 30.0):
		return _check(false, "one generated resident must acquire a real town_labor farmer employment slot")
	var record: Dictionary = _population.get_actor_record(_actor_id)
	_check(str(record.get("generation_source", "")).begins_with("assignment_auto") or str(record.get("generation_source", "")) == "census", "farmer must be generated, not the named facility worker")
	_check(str(_employment_slot.get("facility_id", "")).is_empty(), "town employment must not borrow a facility-only Worker assignment")
	_check(str(record.get("assignments", {}).get("employment", "")) == str(_employment_slot.slot_id), "canonical person must own town employment")
	for slot in _settlements.get_settlement_state(SETTLEMENT_ID).get("assignment_slots", {}).values():
		if str(slot.get("assignment_domain", "")) == "residence" and str(slot.get("occupant_actor_id", "")) == _actor_id:
			_residence_slot = slot.duplicate(true)
	if not _check(not _residence_slot.is_empty(), "same generated farmer must own the existing cottage residence"):
		return false
	var npc_ids: Array[String] = []
	for person in _population.get_records_for_settlement(SETTLEMENT_ID):
		if str(person.get("party_id", "")).is_empty():
			npc_ids.append(str(person.get("actor_id", "")))
	if not _check(npc_ids == [_actor_id], "one NPC is required so aggregate farm progress cannot be another worker's work: %s" % [npc_ids]):
		return false
	for actor in _scene.get_node("PartyMembers").get_children():
		_jobs.set_actor_jobs_enabled(actor, false)
	# Finite real inventory is fixture supply, not a work/completion shortcut.
	var hoe = load("res://features/inventory/resources/items/hoe.tres")
	_worker().inventory.add_item_count(hoe, 1)
	_bed = _house.get_node("Furniture/Bed")
	_check(_bed != null, "cottage fixture must retain its actual authored bed")
	if not await _wait_until(func() -> bool: return _town_cell_count() == 16, 30.0):
		return _check(false, "production field must seed sixteen durable cells")
	_check(_tilled_count() == 0, "no farm work may complete before 08:00")
	_check(not _farm_work.has_active_work_for_actor(_worker()), "07:55 town farmer must not claim farm work")
	if not await _wait_until(_is_sitting_at_home, APPROACH_SECONDS):
		return _check(false, "07:55 farmer must physically sit at home: " + _diagnostics())
	print("TOWN_SCHEDULE_SETUP actor=%s employment=%s residence=%s" % [_actor_id, _employment_slot.slot_id, _residence_slot.slot_id])
	return _failures.is_empty()


func _validate_work_and_home() -> bool:
	var home_position: Vector3 = _worker().global_position
	_cross_boundary(8)
	if not await _wait_until(func() -> bool: return _tilled_count() > 0, WORK_SECONDS):
		return _check(false, "08:00 town farmer must physically reach the field and commit durable soil: " + _diagnostics())
	_check(_worker().global_position.distance_to(home_position) > 3.0, "08:00 must produce actual home-to-field displacement")
	_check(_worker().get_interaction().current_seat_target == null, "working farmer must release the Home chair")
	# Observe a SECOND unfinished till operation after proving a full commit.
	# Read bridge state only to identify the actual operation; never seed it.
	if not await _wait_until(_has_unfinished_physical_work, WORK_SECONDS):
		return _check(false, "closing probe needs actual partially worked, unfinished soil: " + _diagnostics())
	var work := _active_work().duplicate()
	var plot_id := str(work.get("plot_id", ""))
	var cell_key := str(work.get("cell_key", ""))
	var completed_before := _tilled_count()
	var field_position: Vector3 = _worker().global_position
	_cross_boundary(20)
	if not await _wait_until(func() -> bool:
		return not _farm_work.has_active_work_for_actor(_worker()) and not _worker().has_meta(&"active_facility_duty") and not _worker().has_meta(&"active_settlement_work")
	, 3.0):
		return _check(false, "20:00 must cancel actual unfinished farm work and release duty: " + _diagnostics())
	var cancelled_cell := _cell(plot_id, cell_key).duplicate(true)
	_check(not bool(cancelled_cell.get("soil_created", false)), "closing must interrupt rather than finish the in-flight till")
	_check(str(cancelled_cell.get("claimed_by", "")).is_empty(), "closing must release the durable field claim")
	if not await _wait_until(_is_sitting_at_home, APPROACH_SECONDS):
		return _check(false, "20:00 worker must navigate back and actually sit, not merely claim a seat: " + _diagnostics())
	_check(_worker().global_position.distance_to(field_position) > 3.0, "return-home phase must produce real field-to-home displacement")
	# Wait a complete work interval: a late provider callback cannot commit
	# canceled soil, and idle dispatch must not continuously restart seating.
	var hold_seconds := maxf(3.0, float(work.get("required_seconds", 1.0)) + 1.0)
	var until := Time.get_ticks_msec() + int(hold_seconds * 1000.0)
	while Time.get_ticks_msec() < until and Time.get_ticks_msec() < _deadline_msec:
		if not _check(_is_sitting_at_home() and not _farm_work.has_active_work_for_actor(_worker()), "off-shift farmer must remain seated without reclaiming farm work"):
			return false
		await physics_frame
	var held_cell := _cell(plot_id, cell_key)
	_check(_tilled_count() == completed_before, "no late farm completion is allowed after 20:00")
	_check(is_equal_approx(float(held_cell.get("work_progress", 0.0)), float(cancelled_cell.get("work_progress", 0.0))), "canceled durable progress must remain unchanged while home")
	print("TOWN_SCHEDULE_20_HOME actor=%s plot=%s cell=%s progress=%s" % [_actor_id, plot_id, cell_key, held_cell.get("work_progress", 0.0)])
	return _failures.is_empty()


func _validate_night_lod_and_resume() -> void:
	_cross_boundary(22)
	if not await _wait_until(_is_sleeping_in_bed, APPROACH_SECONDS):
		_check(false, "22:00 must release the chair and physically enter the real Home bed: " + _diagnostics())
		return
	_check(_worker().get_interaction().current_seat_target == null, "sleep phase must release the daytime chair")
	_check(not _farm_work.has_active_work_for_actor(_worker()), "22:00 sleeping farmer cannot own active farm work")
	var before: Dictionary = _population.get_actor_record(_actor_id).duplicate(true)
	var old_actor: WeakRef = weakref(_worker())
	var old_instance_id: int = _worker().get_instance_id()
	var completed_before := _tilled_count()
	# A dual-assigned person can be projected by either assignment owner.
	# Derealize the actual owner; requesting the other slot is a no-op.
	var projection_domain := str(_worker().get_meta("settlement_assignment_domain", ""))
	var projection_slot := str(_worker().get_meta("settlement_assignment_slot_id", ""))
	if not _check(projection_domain in ["employment", "residence"] and str(before.get("assignments", {}).get(projection_domain, "")) == projection_slot, "LOD target must identify this farmer's real projection owner"):
		return
	_settlements.derealize_assignment_slot(SETTLEMENT_ID, projection_domain, projection_slot)
	if not await _wait_until(func() -> bool: return old_actor.get_ref() == null, 5.0):
		_check(false, "overnight LOD must really destroy the former farmer projection")
		return
	_check(not _bed.is_occupied(), "LOD must release the destroyed farmer's bed reservation")
	if not _check(_settlements.realize_assignment_slot(SETTLEMENT_ID, projection_domain, projection_slot), "same durable town farmer must re-realize overnight"):
		return
	if not await _wait_until(_is_sleeping_in_bed, APPROACH_SECONDS):
		_check(false, "overnight replacement must reacquire actual sleep, not start town work: " + _diagnostics())
		return
	var after: Dictionary = _population.get_actor_record(_actor_id)
	_check(_worker().get_instance_id() != old_instance_id, "overnight LOD must create a new physical body")
	_check(after.get("assignments", {}) == before.get("assignments", {}) and after.get("member_name") == before.get("member_name"), "LOD must preserve canonical identity and both assignments")
	_check(_tilled_count() == completed_before and not _farm_work.has_active_work_for_actor(_worker()), "overnight realization cannot advance or claim farm work")
	_cross_boundary(6)
	if not await _wait_until(func() -> bool:
		var actor = _worker()
		return is_instance_valid(actor) and actor.life_state == NpcRules.LifeState.ALIVE and actor.get_interaction().current_sleep_target == null and not _bed.is_occupied()
	, 5.0):
		_check(false, "06:00 must actually wake farmer and release the bed: " + _diagnostics())
		return
	if not await _wait_until(_is_sitting_at_home, APPROACH_SECONDS):
		_check(false, "06:00 awake farmer must physically return to daytime Home seating: " + _diagnostics())
		return
	_check(_tilled_count() == completed_before and not _farm_work.has_active_work_for_actor(_worker()), "06:00 is awake but still off shift")
	var home_position: Vector3 = _worker().global_position
	_cross_boundary(8)
	if not await _wait_until(func() -> bool: return _tilled_count() > completed_before, WORK_SECONDS):
		_check(false, "08:00 restored farmer must resume real farm travel and durable work: " + _diagnostics())
		return
	_check(_worker().global_position.distance_to(home_position) > 3.0, "next 08:00 must leave Home through real movement")
	_check(_worker().get_interaction().current_seat_target == null and _worker().get_interaction().current_sleep_target == null, "resumed work must release both furniture targets")
	print("TOWN_SCHEDULE_OVERNIGHT_RESUME actor=%s old_body=%s new_body=%s tilled=%s" % [_actor_id, old_instance_id, _worker().get_instance_id(), _tilled_count()])


func _cross_boundary(hour: int) -> void:
	# Stage the preceding minute, then cross with the real hour/minute event
	# path. This is phase testing, not a simulation of all intervening hours.
	if hour <= int(_clock.get_hour()):
		_clock.set_time_of_day(23, 59)
		_clock.advance_minutes(1.0)
	_clock.set_time_of_day(posmod(hour - 1, 24), 59)
	_clock.advance_minutes(1.0)
	_check(int(_clock.get_hour()) == hour, "WorldTime must reach exact boundary %02d:00" % hour)
	print("TOWN_SCHEDULE_BOUNDARY %02d:00 %s" % [hour, _diagnostics()])


func _find_farmer() -> bool:
	var matches: Array[Dictionary] = []
	for slot in _settlements.get_settlement_state(SETTLEMENT_ID).get("assignment_slots", {}).values():
		if str(slot.get("assignment_domain", "")) == "employment" and str(slot.get("assignment_scope", "")) == "town_labor" and str(slot.get("role_id", "")) == "farmer":
			matches.append(slot)
	if matches.size() != 1:
		return false
	_employment_slot = matches[0].duplicate(true)
	_actor_id = str(_employment_slot.get("occupant_actor_id", ""))
	return not _actor_id.is_empty() and is_instance_valid(_worker())


func _worker():
	return _population.get_live_actor(_actor_id) if is_instance_valid(_population) else null


func _active_work() -> Dictionary:
	var actor = _worker()
	return _farm_work.get("_assignments").get(actor.get_instance_id(), {}) if is_instance_valid(actor) else {}


func _cell(plot_id: String, cell_key: String) -> Dictionary:
	return _farm.get_plot(plot_id).get("cells", {}).get(cell_key, {})


func _has_unfinished_physical_work() -> bool:
	var work := _active_work()
	if work.is_empty() or str(work.get("action", "")) != "till" or bool(work.get("traveling", true)):
		return false
	var cell := _cell(str(work.get("plot_id", "")), str(work.get("cell_key", "")))
	var progress := float(cell.get("work_progress", 0.0))
	return not bool(cell.get("soil_created", false)) and progress > 0.0 and progress < float(work.get("required_seconds", 0.0))


func _town_cell_count() -> int:
	var count := 0
	for plot in _farm.get_plots().values():
		if str(plot.get("settlement_id", "")) == SETTLEMENT_ID:
			count += plot.get("cells", {}).size()
	return count


func _tilled_count() -> int:
	var count := 0
	for plot in _farm.get_plots().values():
		if str(plot.get("settlement_id", "")) == SETTLEMENT_ID:
			for cell in plot.get("cells", {}).values():
				if bool(cell.get("soil_created", false)):
					count += 1
	return count


func _is_sitting_at_home() -> bool:
	var actor = _worker()
	if not is_instance_valid(actor):
		return false
	var interaction = actor.get_interaction()
	var seat = interaction.current_seat_target
	return interaction.is_sitting and is_instance_valid(seat) and _house.is_ancestor_of(seat) and seat.get_sitter() == actor


func _is_sleeping_in_bed() -> bool:
	var actor = _worker()
	return is_instance_valid(actor) and actor.life_state == NpcRules.LifeState.ASLEEP and actor.get_interaction().current_sleep_target == _bed and _bed.is_occupied() and _bed.get_sleeper() == actor


func _diagnostics() -> String:
	var actor = _worker()
	if not is_instance_valid(actor):
		return "actor=%s absent" % _actor_id
	var interaction = actor.get_interaction()
	return "actor=%s pos=%s life=%s sitting=%s seat=%s bed=%s moving=%s goal=%s work=%s" % [
		_actor_id, actor.global_position, actor.life_state, interaction.is_sitting,
		interaction.current_seat_target, interaction.current_sleep_target,
		actor.has_move_target(), actor.get_move_target(), _active_work()]


func _wait_until(predicate: Callable, seconds: float) -> bool:
	var deadline := mini(_deadline_msec, Time.get_ticks_msec() + int(seconds * 1000.0))
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await physics_frame
	return bool(predicate.call())


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures.append(message)
	return condition


func _watchdog() -> void:
	if not _finished:
		_check(false, "runtime validation exceeded its 540-second wall-clock budget")
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for failure in _failures:
		push_error(failure)
	print("TOWN_WORK_SCHEDULE_RUNTIME_%s count=%d" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	quit(0 if _failures.is_empty() else 1)
