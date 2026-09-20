extends "res://tests/validation/test_case.gd"

## Generic Home behavior: all layout, people and capacity belong to this fixture.
## Services, actor realization, furniture, navigation and combat are production.
const SCENE_PATH := "res://tests/validation/fixtures/home_residents/home_residents.tscn"
const SETTLEMENT_ID := "home_residents"
const FACTION_ID := "Farmers"
const COMBAT_FIXTURE := preload("res://tests/validation/helpers/combat_fixture.gd")
const DAYTIME_APPROACH_FRAMES := 600

var _failures: Array[String] = []
var _scene: Node3D
var _house: SettlementFacilityInstance
var _settlement: SettlementController
var _population: PopulationController
var _clock: WorldTimeController
var _slots: Array[Dictionary] = []
var _resident_ids: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if await _load_fixture():
		_validate_records_and_private_door()
		await _validate_daytime_and_priority()
		await _validate_projection_round_trip()
		await _validate_night_and_dawn()
		await _validate_home_trespass_response()
	await COMBAT_FIXTURE.release_world(_scene, get_tree())
	for failure in _failures:
		push_error(failure)
	print("HOME_RESIDENT_REALIZATION_%s count=%d" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _load_fixture() -> bool:
	_scene = (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_scene)
	_house = _scene.get_node("Town/Facilities/Home") as SettlementFacilityInstance
	if not await _wait_until(func() -> bool: return BootstrapContext.service(SettlementController.SERVICE_ID) != null, 600):
		return _check(false, "Home fixture must initialize the real settlement service")
	_settlement = BootstrapContext.service(SettlementController.SERVICE_ID) as SettlementController
	_population = BootstrapContext.service(PopulationController.SERVICE_ID) as PopulationController
	_clock = BootstrapContext.service(WorldTimeController.SERVICE_ID) as WorldTimeController
	var navigation := BootstrapContext.service(WorldNavigationController.SERVICE_ID) as WorldNavigationController
	# Bodies may exist before the navmesh/physics startup allows safe chair exits.
	# Do not manufacture readiness by clearing the loading owner's pause.
	if not await _wait_until(func() -> bool:
		return navigation.get("_mode") != WorldNavigationController.Mode.INACTIVE and not navigation.is_initial_navigation_pending() and not _clock.is_world_paused()
	, 1800):
		return _check(false, "Home fixture must finish actual navigation startup: pauses=%s" % _clock.get("_pause_reasons"))
	_slots = _settlement.get_facility_assignment_slots(_house.facility_id, "residence")
	var specs := _house.get_assignment_slot_specs()
	if not _check(not specs.is_empty() and _slots.size() == specs.size(), "Residence ledger must match fixture-owned Home slots"):
		return false
	for slot in _slots:
		var actor_id := str(slot.get("occupant_actor_id", ""))
		if not _check(not actor_id.is_empty(), "Every Home slot needs a permanent occupant"):
			return false
		_resident_ids.append(actor_id)
	if not await _wait_until(func() -> bool:
		return _resident_ids.all(func(id: String) -> bool: return is_instance_valid(_population.get_live_actor(id)))
	, 600):
		return _check(false, "Real population realization must project every Home occupant")
	_check(_house.get_physical_bed_count() == 1 and _resident_ids.size() == 2, "Fixture contract is two non-working residents competing for one physical bed")
	print("HOME_SETUP_TRACE residents=%s slots=%s pauses=%s" % [_resident_ids, _slots.map(func(slot: Dictionary): return slot.slot_id), _clock.get("_pause_reasons")])
	return true


func _validate_records_and_private_door() -> void:
	var seen := {}
	for slot in _slots:
		var actor_id := str(slot.occupant_actor_id)
		var record := _population.get_actor_record(actor_id)
		_check(not record.is_empty() and not seen.has(actor_id), "Residence occupants need unique durable records")
		seen[actor_id] = true
		_check(actor_id == str(slot.preferred_actor_id), "The fixture's authored resident must occupy its intended Home slot")
		_check(bool(record.get("last_world_position_initialized", false)), "Resident %s needs a durable Home position" % actor_id)
		_check(str(record.get("assignments", {}).get("residence", "")) == str(slot.slot_id), "Resident %s must retain its canonical residence" % actor_id)
		_check(str(record.get("assignments", {}).get("employment", "")).is_empty(), "Home idle fixture must not borrow an on-duty worker")
		var actor := _resident(actor_id)
		_check(_house.is_ancestor_of(actor), "Home must own its realized resident projection")
		_check(_house.get_current_building().is_actor_inside(actor), "Resident %s must physically realize inside its Home" % actor_id)
		var domain := str(actor.get_meta("settlement_assignment_domain", ""))
		var slot_id := str(actor.get_meta("settlement_assignment_slot_id", ""))
		_check(not domain.is_empty() and not slot_id.is_empty() and str(record.get("assignments", {}).get(domain, "")) == slot_id, "Projection metadata must identify the actor's actual assignment")
	var building := _house.get_current_building()
	var doors := get_nodes_in_group("world_door").filter(func(door: Node) -> bool: return building.is_ancestor_of(door))
	_check(not doors.is_empty(), "Home must expose real runtime doors")
	var controller := BootstrapContext.service(DoorController.SERVICE_ID) as DoorController
	for door in doors:
		var state := controller.get_door_state(str(door.get("door_id")))
		var authorized := PackedStringArray(state.get("authorized_actor_ids", []))
		for actor_id in _resident_ids:
			_check(authorized.has(actor_id), "Private Home door must authorize resident %s" % actor_id)
		var registry := BootstrapContext.service(BuildingRegistry.SERVICE_ID) as BuildingRegistry
		_check(str(registry.get_building(_house.building_id).get("access_state", "")) == "private", "Home building must remain private")
		_check(PackedStringArray(state.get("authorized_faction_ids", [])).is_empty(), "Home access must not authorize the residents' entire faction")
		_check(not authorized.has("home_residents.intruder"), "Private Home door must not authorize an unrelated party member")


func _validate_daytime_and_priority() -> void:
	_clock.set_time_of_day(12, 0)
	_refresh_residents()
	# The existing startup budget must cover actual approach, not merely claims.
	_check(await _wait_until(_all_residents_sitting, DAYTIME_APPROACH_FRAMES), "Both residents must actually complete their chair approach: %s" % [_resident_diagnostics()])
	_check(_distinct_chairs_claimed(), "Daytime Home residents must claim distinct available chairs: %s" % [_resident_diagnostics()])
	print("HOME_DAY_TRACE %s" % [_resident_diagnostics()])
	var protected_actor := _resident(_resident_ids[0])
	var interaction := protected_actor.get_interaction()
	interaction.stop_seat_assignment()
	protected_actor.set_active_player_order(true)
	_house.refresh_settlement_assignment_actor(protected_actor, {"assignment_domain": "residence", "routine_activity_state": "home_day"})
	_check(interaction.current_seat_target == null and protected_actor.has_active_player_order(), "Home fallback must not replace an explicit player order")
	protected_actor.set_active_player_order(false)
	_refresh_residents()
	_check(await _wait_until(_all_residents_sitting, 180), "Resident must reacquire ordinary Home seating after player priority ends")


func _validate_projection_round_trip() -> void:
	var prior_projections: Array[WeakRef] = []
	var saved_assignments := {}
	for slot in _slots:
		var id := str(slot.occupant_actor_id)
		prior_projections.append(weakref(_resident(id)))
		saved_assignments[id] = _population.get_actor_record(id).get("assignments", {}).duplicate(true)
		_settlement.derealize_assignment_slot(SETTLEMENT_ID, "residence", str(slot.slot_id))
	_check(await _wait_until(func() -> bool: return prior_projections.all(func(ref: WeakRef) -> bool: return ref.get_ref() == null), 60), "LOD must destroy the old resident projections, not reuse the same nodes")
	for chair in [_house.get_node("Furniture/ChairA"), _house.get_node("Furniture/ChairB")]:
		_check(not chair.is_occupied(), "Disappeared resident must release its chair reservation")
	for slot in _slots:
		var id := str(slot.occupant_actor_id)
		_check(_population.get_actor_record(id).get("assignments", {}) == saved_assignments[id], "LOD must preserve the same resident's durable assignments")
		_check(_settlement.realize_assignment_slot(SETTLEMENT_ID, "residence", str(slot.slot_id)), "Same durable resident must re-realize after LOD")
	_refresh_residents()
	_check(await _wait_until(_all_residents_sitting, 180), "Every replacement resident must reacquire and complete its ordinary Home seating")
	_validate_records_and_private_door()


func _validate_night_and_dawn() -> void:
	_clock.set_time_of_day(0, 0)
	# Submit each routine change once, then observe its asynchronous completion.
	_refresh_residents()
	_check(await _wait_until(_one_sleeper_one_awake, 180), "One-bed Home must have one actual sleeper and one awake resident: %s" % [_resident_diagnostics()])
	var bed := _house.get_node("Furniture/Bed") as SleepableBed
	_check(bed.is_occupied() and bed.get_sleeper() != null, "Nighttime sleep must own the real bed reservation")
	print("HOME_SLEEP_TRACE %s" % [_resident_diagnostics()])
	_clock.set_time_of_day(6, 0)
	_refresh_residents()
	_check(await _wait_until(func() -> bool:
		return _resident_ids.all(func(id: String) -> bool: return _resident(id).life_state == NpcRules.LifeState.ALIVE and _resident(id).get_interaction().current_sleep_target == null)
	, 30), "Dawn must wake residents and release Home sleep targets")
	_check(not bed.is_occupied(), "Dawn must release the scarce physical bed")
	_clock.set_time_of_day(12, 0)
	_refresh_residents()
	# This added physical-approach check is separate from the unchanged 30-frame
	# wake deadline above; the awake overflow resident can be across the room.
	_check(await _wait_until(_all_residents_sitting, DAYTIME_APPROACH_FRAMES), "Residents must return to daytime chairs after waking: %s" % [_resident_diagnostics()])


func _validate_home_trespass_response() -> void:
	var law := BootstrapContext.service(LawOrderController.SERVICE_ID) as LawOrderController
	var responses := BootstrapContext.service(GameCombatResponseSystem.SERVICE_ID) as GameCombatResponseSystem
	var crime_alerts := BootstrapContext.service(CrimeAlertController.SERVICE_ID) as CrimeAlertController
	var factions := BootstrapContext.service(FactionController.SERVICE_ID) as FactionController
	var intruder := _scene.get_node("PartyMembers/Intruder") as HumanoidCharacter
	var companion := _scene.get_node("PartyMembers/Companion") as HumanoidCharacter
	var passive := _scene.get_node("PartyMembers/PassiveCompanion") as HumanoidCharacter
	var guard := await COMBAT_FIXTURE.staff(get_tree(), SETTLEMENT_ID, SETTLEMENT_ID, "guard")
	if not _check(guard != null and law != null and responses != null and crime_alerts != null, "Home trespass needs actual law, alert, combat and registered authority services"):
		return
	var tolerant_profile := FactionLawProfile.new()
	tolerant_profile.trespass_escalation = "warning_only"
	var tolerant_faction := FactionDefinition.new()
	tolerant_faction.faction_id = "validation_tolerant"
	tolerant_faction.law_profile = tolerant_profile
	factions.register_faction(tolerant_faction)
	_check(crime_alerts.crime_is_illegal_for_faction("trespass", FACTION_ID) and not crime_alerts.crime_is_illegal_for_faction("trespass", tolerant_faction.faction_id), "Faction profiles must distinguish criminal and warning-only trespass")
	# Stage this occupancy-service scenario on explicit grounded interior points.
	# No transforms are changed after the warning; pursuit/impact use real motion.
	for actor in [intruder, companion, passive]:
		var marker := _scene.get_node("IntrusionPositions/" + str(actor.name)) as Marker3D
		actor.global_position = actor.get_floor_aligned_origin_position(marker.global_position)
		actor.velocity = Vector3.ZERO
	_check(companion.combat_stance != NpcRules.CombatStance.PASSIVE and passive.combat_stance == NpcRules.CombatStance.PASSIVE, "Assistance fixture must contain both responding and passive companions")
	var perception := BootstrapContext.service(PerceptionController.SERVICE_ID) as PerceptionController
	_check(_resident_ids.any(func(id: String) -> bool: return float(perception.evaluate_observer(_resident(id), intruder).get("line_of_sight_fraction", 0.0)) > 0.0), "Intrusion setup must be inside a real resident's visible field, not behind both chairs")
	var building_id := _house.building_id
	var occupied: Array[String] = [building_id]
	var no_buildings: Array[String] = []
	law.update_actor_building_occupancy(intruder.stable_id, occupied)
	law.call("_process_fixed_tick")
	var pair := _trespass_pair(law, intruder.stable_id)
	_check(int(pair.get("warning_count", 0)) == 1, "Assigned Home resident must detect and confront the grounded intruder: %s" % pair)
	_check(law.get_warrant_record(intruder, FACTION_ID).is_empty(), "Initial Home confrontation must allow time to leave before guard escalation")
	_check(str(intruder.get_legal_status().active_crime_label).is_empty(), "Trespass must not create floating active-crime text")
	law.update_actor_building_occupancy(intruder.stable_id, no_buildings)
	law.call("_process_fixed_tick")
	_check(_trespass_pair(law, intruder.stable_id).is_empty() and law.get_warrant_record(intruder, FACTION_ID).is_empty(), "Leaving during warning grace must clear trespass without a warrant")
	law.update_actor_building_occupancy(intruder.stable_id, occupied)
	law.call("_process_fixed_tick")
	for _tick in range(30):
		law.call("_process_fixed_tick")
	var warrant := law.get_warrant_record(intruder, FACTION_ID)
	if not _check(not warrant.is_empty() and str(warrant.get("state", "")) == "wanted", "Ignoring the Home leave warnings must produce a wanted report"):
		return
	pair = _trespass_pair(law, intruder.stable_id)
	var witness_id := str(pair.get("witness_actor_id", ""))
	if not _check(_resident_ids.has(witness_id), "The actual private-defense witness must be an assigned Home resident"):
		return
	var witness := _resident(witness_id)
	var impacts: Array[Dictionary] = []
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var resolution := gecs.find_child("GameCombatResolutionSystem", true, false)
	var on_impact := func(attacker_id: String, target_id: String, sequence: int, outcome: String, damage: float) -> void:
		impacts.append({"attacker": attacker_id, "target": target_id, "sequence": sequence, "outcome": outcome, "damage": damage, "threats": COMBAT_FIXTURE.defense_threat_actor_ids(responses, intruder.stable_id)})
	resolution.connect("impact_resolved", on_impact)
	_check(await _wait_until(func() -> bool:
		var threats := COMBAT_FIXTURE.defense_threat_actor_ids(responses, intruder.stable_id)
		return threats.has(witness_id) and threats.has(guard.stable_id)
	, 60), "Home threat set must independently contain its actual private witness and dispatched authority guard")
	_check(witness.get_interaction().current_seat_target == null and witness.get_interaction().current_sleep_target == null, "Home witness must leave furniture when defending against ignored warnings")
	var guards: Array = law.call("_find_authority_guards", FACTION_ID, _scene.get_node("Town"))
	var nearby_count := 0
	for responder in guards:
		if responder.global_position.distance_squared_to(intruder.global_position) <= NpcRules.NPC_ALERT_PROXIMITY_RADIUS * NpcRules.NPC_ALERT_PROXIMITY_RADIUS:
			nearby_count += 1
			_check(bool(law.call("_is_guard_in_authority_alert_scope", responder, warrant, intruder)) and responses.is_law_enforcement_pair(responder.stable_id, intruder.stable_id), "Every nearby authority guard must accept the Home crime alert")
	_check(nearby_count > 0, "Guard dispatch coverage must have an actual nearby authority")
	var events: Array = crime_alerts.get_active_events()
	_check(events.any(func(event: Dictionary) -> bool: return absf(float(event.get("radius", 0.0)) - 40.0) <= 0.01), "Trespass report must emit a 40m crime event")
	_validate_law_debug(events)
	var guard_start := guard.global_position
	_check(await _wait_until(func() -> bool: return guard.get_current_combat_target() == intruder, 60), "Dispatched authority guard must acquire the exact offender")
	# Require both real damage and assistance, but retain the observations:
	# a companion can defend early and be downed before a later attack lands.
	var assistance := {"observed": false}
	await _wait_until(func() -> bool:
		var impacted := impacts.any(func(impact: Dictionary) -> bool: return str(impact.target) == intruder.stable_id and float(impact.damage) > 0.0 and impact.threats.has(str(impact.attacker)))
		var target := companion.get_current_combat_target() as WorldActor
		if target != null and COMBAT_FIXTURE.defense_threat_actor_ids(responses, intruder.stable_id).has(target.stable_id):
			assistance.observed = true
		return impacted and bool(assistance.observed)
	, 600)
	resolution.disconnect("impact_resolved", on_impact)
	_check(impacts.any(func(impact: Dictionary) -> bool: return str(impact.target) == intruder.stable_id and float(impact.damage) > 0.0 and impact.threats.has(str(impact.attacker))), "Home defense must actually damage the intruder before assistance can pass")
	_check(bool(assistance.observed), "Nearby non-passive companion must defend against an active Home-defense threat")
	_check(guard.global_position.distance_to(guard_start) > 0.5, "Guard pursuit must produce real displacement, not only an assigned target")
	_check(companion.get_current_combat_target() != intruder and companion.get_current_combat_target() != passive, "Companion assistance must never target a friendly party member")
	_check(passive.get_current_combat_target() == null, "Passive companion must not autonomously join Home defense")
	_check(intruder.global_position.y > -1.0 and companion.global_position.y > -1.0 and passive.global_position.y > -1.0, "Assistance actors must stay on the fixture floor, not fall through a removed world")
	print("HOME_DEFENSE_TRACE witness=%s threats=%s guard_displacement=%.3f companion=%s impacts=%s" % [witness_id, COMBAT_FIXTURE.defense_threat_actor_ids(responses, intruder.stable_id), guard.global_position.distance_to(guard_start), companion.get_current_combat_target(), impacts])
	for actor in [witness, guard, intruder, companion, passive]:
		print("HOME_ACTOR_TRACE %s" % _actor_diagnostics(actor))
	law.update_actor_building_occupancy(intruder.stable_id, no_buildings)


func _validate_law_debug(events: Array) -> void:
	var settings := load("res://tools/game_debug.gd").new() as Node
	settings.name = "GameDebug"
	root.add_child(settings)
	var menu := load("res://features/ui/projection/debug_menu.gd").new() as Control
	root.add_child(menu)
	_check(menu.call("get_window_titles").has("Law & Order"), "Debug menu must expose the Law & Order window")
	var overlay := load("res://features/settlements/projection/law_debug_overlay.gd").new() as Node3D
	root.add_child(overlay)
	overlay.call("set_actor_radii_visible", true)
	overlay.call("set_crime_events_visible", true)
	overlay.call("_rebuild")
	_check(overlay.get_child_count() > events.size(), "Law debug overlay must draw both active crime events and NPC alert radii")
	overlay.queue_free()
	menu.queue_free()
	settings.queue_free()


func _trespass_pair(law: LawOrderController, actor_id: String) -> Dictionary:
	return (law.get("_active_trespass_by_actor").get(actor_id, {}) as Dictionary).get(_house.building_id, {})


func _resident(actor_id: String) -> HumanoidCharacter:
	return _population.get_live_actor(actor_id) as HumanoidCharacter


func _refresh_residents() -> void:
	for slot in _slots:
		_settlement.refresh_assignment_slot_projection(SETTLEMENT_ID, "residence", str(slot.slot_id))


func _distinct_chairs_claimed() -> bool:
	var targets := {}
	for id in _resident_ids:
		var actor := _resident(id)
		if not is_instance_valid(actor):
			return false
		var seat = actor.get_interaction().current_seat_target
		if not is_instance_valid(seat) or not _house.is_ancestor_of(seat) or targets.has(seat.get_instance_id()) or seat.get_sitter() != actor:
			return false
		targets[seat.get_instance_id()] = true
	return targets.size() == _resident_ids.size() and not targets.is_empty()


func _all_residents_sitting() -> bool:
	return _distinct_chairs_claimed() and _resident_ids.all(func(id: String) -> bool: return _resident(id).get_interaction().is_sitting)


func _one_sleeper_one_awake() -> bool:
	var sleeping := 0
	var awake := 0
	for id in _resident_ids:
		var actor := _resident(id)
		var interaction := actor.get_interaction()
		if actor.life_state == NpcRules.LifeState.ASLEEP and interaction.current_sleep_target == _house.get_node("Furniture/Bed"):
			sleeping += 1
		elif actor.life_state == NpcRules.LifeState.ALIVE and interaction.current_sleep_target == null:
			awake += 1
	return sleeping == 1 and awake == 1


func _resident_diagnostics() -> Array[String]:
	var result: Array[String] = []
	for id in _resident_ids:
		var actor := _resident(id)
		if not is_instance_valid(actor):
			result.append("%s(absent)" % id)
			continue
		result.append(_actor_diagnostics(actor))
	return result


func _actor_diagnostics(actor: HumanoidCharacter) -> String:
	var interaction := actor.get_interaction()
	var collisions: Array[String] = []
	for index in range(actor.get_slide_collision_count()):
		var hit := actor.get_slide_collision(index)
		collisions.append(str(hit.get_collider().get_path()))
	return "%s(life=%s,pos=%s,seat=%s,stand=%s,sitting=%s,sleep=%s,sleep_stand=%s,order=%s,moving=%s,goal=%s,combat=%s,hits=%s)" % [actor.stable_id, actor.life_state, actor.global_position, interaction.current_seat_target, interaction.current_seat_stand_position, interaction.is_sitting, interaction.current_sleep_target, interaction.current_sleep_stand_position, interaction.current_order_type, actor.has_move_target(), actor.get_move_target(), actor.get_current_combat_target(), collisions]


func _wait_until(predicate: Callable, frames: int) -> bool:
	# Physical progress and elapsed-time combat timers need fixed physics ticks,
	# not an uncapped count of render-loop iterations in this small fixture.
	for _frame in range(frames):
		if predicate.call():
			return true
		await physics_frame
	return bool(predicate.call())


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures.append(message)
	return condition
