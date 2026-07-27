extends SceneTree

const SCENE_PATH := "res://scenes/zones/rustwash_basin/rustwash_basin.tscn"
const SETTLEMENT_ID := "canyon"
const C_RESPONSE_INTENT := preload("res://features/combat/sim/c_game_combat_response_intent.gd")

var _failures: Array[String] = []
var _ecs_compile_placeholder: Node


func _initialize() -> void:
	_register_ecs_compile_placeholder()
	call_deferred("_run")


func _register_ecs_compile_placeholder() -> void:
	if Engine.has_singleton("ECS") or root.get_node_or_null("ECS") != null:
		return
	_ecs_compile_placeholder = Node.new()
	_ecs_compile_placeholder.name = "ECS"
	Engine.register_singleton("ECS", _ecs_compile_placeholder)


func _run() -> void:
	var scene := (load(SCENE_PATH) as PackedScene).instantiate()
	var terrain := scene.get_node_or_null("Terrain")
	if terrain != null:
		scene.remove_child(terrain)
		terrain.free()
	root.add_child(scene)
	await _wait_frames(180)
	var settlement := root.find_child("SettlementController", true, false)
	var population := root.find_child("PopulationController", true, false)
	var realization := root.find_child("PopulationRealizationController", true, false)
	var world_time := root.find_child("WorldTimeController", true, false)
	var house := scene.get_node_or_null("Towns/Canyon/House") as Node3D
	if settlement == null or population == null or realization == null or world_time == null or house == null:
		_fail("Rustwash residence validation could not resolve its controllers or first Home")
		_finish()
		return
	var debug_settings := load("res://tools/game_debug.gd").new() as Node
	debug_settings.name = "GameDebug"
	root.add_child(debug_settings)
	var debug_menu := load("res://features/ui/projection/debug_menu.gd").new() as Control
	root.add_child(debug_menu)
	await process_frame
	if not debug_menu.call("get_window_titles").has("Law & Order"):
		_fail("Debug menu should expose the Law & Order window")
	world_time.call("set_time_of_day", 12, 0)
	var anchors: Array[Vector3] = [house.global_position]
	for _cycle in range(12):
		realization.call("_resync_settlement_assignments", anchors)
		await process_frame
	var state: Dictionary = settlement.call("get_settlement_state", SETTLEMENT_ID)
	var residence_slots: Array[Dictionary] = []
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if str(slot.get("assignment_domain", "")) == "residence":
			residence_slots.append(slot)
	if residence_slots.size() != 4:
		_fail("Rustwash should expose four residence assignments across its two Homes")
	var live_residents: Array[Node] = []
	var seen_actor_ids := {}
	var first_house_actor_ids: Array[String] = []
	for slot in residence_slots:
		var actor_id := str(slot.get("occupant_actor_id", ""))
		var record: Dictionary = population.call("get_actor_record", actor_id)
		if actor_id.is_empty() or record.is_empty():
			_fail("Every residence slot must have a permanent population record")
			continue
		if seen_actor_ids.has(actor_id):
			_fail("Residence realization produced a duplicate stable actor ID")
		seen_actor_ids[actor_id] = true
		if not bool(record.get("last_world_position_initialized", false)):
			_fail("Residence actor %s has no durable Home position" % actor_id)
		var actor = population.call("get_live_actor", actor_id)
		if actor == null or not is_instance_valid(actor):
			_fail("Residence actor %s did not realize near its Home" % actor_id)
			continue
		if str(actor.get_meta("settlement_assignment_domain", "")) != "residence":
			_fail("Residence actor %s realized through the wrong assignment domain" % actor_id)
		live_residents.append(actor)
		if str(slot.get("facility_id", "")) == "canyon.house":
			first_house_actor_ids.append(actor_id)
	var building := house.get_node_or_null("BuildingSlot/CurrentBuilding")
	var home_door: Node
	for door_value in get_nodes_in_group("world_door"):
		var door := door_value as Node
		if building != null and building.is_ancestor_of(door):
			home_door = door
			break
	if home_door == null:
		_fail("The first Home should expose its runtime door")
	else:
		var door_controller := root.find_child("DoorController", true, false)
		var door_state: Dictionary = door_controller.call("get_door_state", str(home_door.get("door_id"))) if door_controller != null else {}
		var authorized_actor_ids := PackedStringArray(door_state.get("authorized_actor_ids", []))
		for actor_id in first_house_actor_ids:
			if not authorized_actor_ids.has(actor_id):
				_fail("Private Home door must authorize resident %s" % actor_id)
		if not PackedStringArray(door_state.get("authorized_faction_ids", [])).is_empty():
			_fail("Private Home door must not authorize the resident's entire faction")
	if live_residents.size() >= 2:
		var first_house_residents := live_residents.filter(func(actor: Node) -> bool: return house.is_ancestor_of(actor))
		if first_house_residents.size() != 2:
			_fail("The first Home should own exactly two realized resident projections")
		else:
			var seat_targets := {}
			for actor in first_house_residents:
				var interaction = actor.call("get_interaction") if actor.has_method("get_interaction") else null
				var seat = interaction.current_seat_target if interaction != null else null
				if seat == null:
					_fail("Daytime Home resident should claim an available chair")
				elif seat_targets.has(seat.get_instance_id()):
					_fail("Two Home residents must not reserve the same chair")
				else:
					seat_targets[seat.get_instance_id()] = true
			var protected_actor: Node = first_house_residents[0]
			var protected_interaction = protected_actor.call("get_interaction")
			protected_interaction.stop_seat_assignment()
			protected_actor.call("set_active_player_order", true)
			house.call("refresh_settlement_assignment_actor", protected_actor, {"assignment_domain": "residence", "routine_activity_state": "home_day"})
			if protected_interaction.current_seat_target != null:
				_fail("Home fallback must not replace an explicit player order")
			protected_actor.call("set_active_player_order", false)
			house.call("refresh_settlement_assignment_actor", protected_actor, {"assignment_domain": "residence", "routine_activity_state": "home_day"})
	world_time.call("set_time_of_day", 0, 0)
	for _cycle in range(4):
		for slot in residence_slots:
			settlement.call("refresh_assignment_slot_projection", SETTLEMENT_ID, "residence", str(slot.get("slot_id", "")))
		await process_frame
	await _wait_frames(180)
	var sleeping_residents := 0
	var awake_residents := 0
	var sleep_diagnostics: Array[String] = []
	for actor in live_residents:
		if not house.is_ancestor_of(actor):
			continue
		var interaction = actor.call("get_interaction") if actor.has_method("get_interaction") else null
		if interaction != null and interaction.current_sleep_target != null and int(actor.get("life_state")) == NpcRules.LifeState.ASLEEP:
			sleeping_residents += 1
		elif interaction != null and interaction.current_sleep_target == null and int(actor.get("life_state")) == NpcRules.LifeState.ALIVE:
			awake_residents += 1
		sleep_diagnostics.append("%s(state=%s,target=%s,pos=%s)" % [actor.name, actor.get("life_state"), interaction.current_sleep_target.name if interaction != null and interaction.current_sleep_target != null else "none", actor.global_position])
	if sleeping_residents != 1 or awake_residents != 1:
		_fail("A one-bed Home must have one sleeper and one awake resident at night: %s" % [sleep_diagnostics])
	world_time.call("set_time_of_day", 6, 0)
	for _cycle in range(4):
		for slot in residence_slots:
			settlement.call("refresh_assignment_slot_projection", SETTLEMENT_ID, "residence", str(slot.get("slot_id", "")))
		await process_frame
	await _wait_frames(30)
	for actor in live_residents:
		if not house.is_ancestor_of(actor):
			continue
		var interaction = actor.call("get_interaction") if actor.has_method("get_interaction") else null
		if interaction != null and (interaction.current_sleep_target != null or int(actor.get("life_state")) == NpcRules.LifeState.ASLEEP):
			_fail("Dawn must wake residents and release Home sleep targets")
	world_time.call("set_time_of_day", 12, 0)
	await _wait_frames(4)
	await _validate_home_trespass_response(root.find_child("LawOrderController", true, false), house, live_residents)
	_finish()


func _validate_home_trespass_response(law: Node, house: Node3D, live_residents: Array[Node]) -> void:
	var party_manager := root.find_child("PartyManager", true, false)
	var party_members: Array = party_manager.get("party_members") if party_manager != null else []
	var home_residents := live_residents.filter(func(actor: Node) -> bool: return house.is_ancestor_of(actor))
	if law == null or party_members.is_empty() or home_residents.is_empty():
		_fail("Home trespass validation needs law, Mira, and a realized resident")
		return
	var faction_controller := root.find_child("FactionController", true, false)
	var crime_alerts := root.find_child("CrimeAlertController", true, false)
	var tolerant_profile := FactionLawProfile.new()
	tolerant_profile.trespass_escalation = "warning_only"
	var tolerant_faction := FactionDefinition.new()
	tolerant_faction.faction_id = "validation_tolerant"
	tolerant_faction.law_profile = tolerant_profile
	faction_controller.call("register_faction", tolerant_faction)
	if crime_alerts == null or not bool(crime_alerts.call("crime_is_illegal_for_faction", "trespass", "Farmers")) or bool(crime_alerts.call("crime_is_illegal_for_faction", "trespass", "validation_tolerant")):
		_fail("Faction law profiles must distinguish criminal and warning-only trespass")
	var intruder = party_members[0]
	var witness = home_residents[0]
	var witness_forward: Vector3 = -witness.global_transform.basis.z
	witness_forward.y = 0.0
	intruder.global_position = witness.global_position + witness_forward.normalized()
	for companion_index in range(1, party_members.size()):
		var companion := party_members[companion_index] as WorldActor
		if companion != null:
			companion.global_position = intruder.global_position + Vector3(float(companion_index) * 1.5, 0.0, 2.0)
			companion.velocity = Vector3.ZERO
	var actor_id := str(intruder.get_meta("actor_record_id", intruder.get("stable_id")))
	var occupied_building_ids: Array[String] = ["canyon.house.building"]
	law.call("update_actor_building_occupancy", actor_id, occupied_building_ids)
	law.call("_process_fixed_tick")
	var pairs: Dictionary = law.get("_active_trespass_by_actor")
	var pair: Dictionary = (pairs.get(actor_id, {}) as Dictionary).get("canyon.house.building", {})
	if int(pair.get("warning_count", 0)) != 1:
		var registry := root.find_child("BuildingRegistry", true, false)
		var record: Dictionary = registry.call("get_building", "canyon.house.building") if registry != null else {}
		var resident_ids: PackedStringArray = law.call("_residence_actor_ids_for_building", record)
		var resolved_intruder = law.get("_actor_query").call("get_actor_by_stable_id", actor_id)
		var detected_witness = law.call("_find_trespass_witness", intruder, record)
		var perception := law.call("_get_perception_controller") as Node
		var perception_result: Dictionary = perception.call("evaluate_observer", witness, intruder) if perception != null else {}
		_fail("Assigned Home resident should detect and confront the intruder (actor_id=%s resolved=%s residents=%s witness=%s pair=%s perception=%s)" % [actor_id, resolved_intruder != null, resident_ids, detected_witness != null, pair, perception_result])
	if not (law.call("get_warrant_record", intruder, "Canyonites") as Dictionary).is_empty():
		_fail("Initial Home confrontation must allow time to leave before guard escalation")
	if not str(intruder.call("get_legal_status").active_crime_label).is_empty():
		_fail("Trespassing must not create floating active-crime text")
	var no_buildings: Array[String] = []
	law.call("update_actor_building_occupancy", actor_id, no_buildings)
	law.call("_process_fixed_tick")
	pairs = law.get("_active_trespass_by_actor")
	if pairs.has(actor_id) or not (law.call("get_warrant_record", intruder, "Canyonites") as Dictionary).is_empty():
		_fail("Leaving the Home during the warning grace period must clear trespass without a warrant")
	law.call("update_actor_building_occupancy", actor_id, occupied_building_ids)
	law.call("_process_fixed_tick")
	for _tick in range(30):
		law.call("_process_fixed_tick")
	var warrant: Dictionary = law.call("get_warrant_record", intruder, "Canyonites")
	await _wait_frames(5)
	if warrant.is_empty() or str(warrant.get("state", "")) != "wanted":
		_fail("Resident should report a detected intruder who ignores the leave warning")
	else:
		var settlement_node := law.call("_find_settlement_for_warrant", intruder, warrant) as Node
		var guard_dispatched := false
		var guards: Array = law.call("_find_authority_guards", "Canyonites", settlement_node)
		var nearby_guards := guards.filter(func(guard: Node3D) -> bool: return guard.global_position.distance_squared_to(intruder.global_position) <= NpcRules.NPC_ALERT_PROXIMITY_RADIUS * NpcRules.NPC_ALERT_PROXIMITY_RADIUS)
		var response_system := root.find_child("GameCombatResponseSystem", true, false)
		var response_intents: Array[Dictionary] = response_system.call("get_active_intents") if response_system != null else []
		for guard in nearby_guards:
			var guard_id := str(guard.get_meta("actor_record_id", guard.get("stable_id")))
			var has_law_intent := response_intents.any(func(intent: Dictionary) -> bool: return str(intent.get("responder_actor_id", "")) == guard_id and str(intent.get("target_actor_id", "")) == actor_id and int(intent.get("kind", -1)) == C_RESPONSE_INTENT.Kind.LAW_ENFORCEMENT)
			if bool(law.call("_is_guard_in_authority_alert_scope", guard, warrant, intruder)) and has_law_intent:
				guard_dispatched = true
			else:
				_fail("Every nearby Canyon authority guard should accept the crime alert")
		if not guard_dispatched:
			var guard_diagnostics: Array[String] = []
			for guard in guards:
				var target = guard.call("get_current_combat_target") if guard.has_method("get_current_combat_target") else null
				guard_diagnostics.append("%s(scope=%s,hostile=%s,target=%s)" % [guard.name, law.call("_is_guard_in_authority_alert_scope", guard, warrant, intruder), guard.call("is_hostile_to", intruder), target == intruder])
			_fail("Reported Home trespass should dispatch an authority guard (settlement=%s guards=%s)" % [settlement_node != null, guard_diagnostics])
		var witness_interaction = witness.call("get_interaction")
		var witness_id := str(witness.get_meta("actor_record_id", witness.get("stable_id")))
		var witness_has_private_intent := response_intents.any(func(intent: Dictionary) -> bool: return str(intent.get("responder_actor_id", "")) == witness_id and str(intent.get("target_actor_id", "")) == actor_id and int(intent.get("kind", -1)) == C_RESPONSE_INTENT.Kind.PRIVATE_DEFENSE)
		if witness_interaction.current_seat_target != null or witness_interaction.current_sleep_target != null or not witness_has_private_intent:
			_fail("Home witness should leave furniture and defend against an ignored warning")
		var events: Array = crime_alerts.call("get_active_events")
		if events.is_empty() or absf(float((events[0] as Dictionary).get("radius", 0.0)) - 40.0) > 0.01:
			_fail("Trespass report should emit a 40m crime event")
		var overlay_script = load("res://features/settlements/projection/law_debug_overlay.gd")
		var overlay := overlay_script.new() as Node3D
		root.add_child(overlay)
		overlay.call("set_actor_radii_visible", true)
		overlay.call("set_crime_events_visible", true)
		overlay.call("_rebuild")
		if overlay.get_child_count() <= events.size():
			_fail("Law debug overlay should draw active events and per-NPC alert radii")
		overlay.queue_free()
		await _wait_frames(60)
		var guard_targeted := false
		for guard in guards:
			if guard.call("get_current_combat_target") == intruder:
				guard_targeted = true
				break
		if not guard_targeted:
			_fail("At least one dispatched guard should acquire and pursue the offender")
		var companion_helped := false
		for companion in party_members:
			if companion == intruder or int(companion.get("combat_stance")) == NpcRules.CombatStance.PASSIVE:
				continue
			if companion.global_position.distance_squared_to(intruder.global_position) > NpcRules.NPC_ALERT_PROXIMITY_RADIUS * NpcRules.NPC_ALERT_PROXIMITY_RADIUS:
				continue
			if companion.call("get_current_combat_target") == witness:
				companion_helped = true
				break
		if not companion_helped:
			var companion_states: Array[String] = []
			for companion in party_members:
				var companion_id := str(companion.get_meta("actor_record_id", companion.get("stable_id")))
				companion_states.append("%s(party=%s,stance=%s,pos=%s,target=%s)" % [companion_id, companion.get_meta("party_id", ""), companion.get("combat_stance"), companion.global_position, companion.call("get_current_combat_target")])
			_fail("A nearby non-passive party member should defend an attacked party member (intents=%s companions=%s)" % [response_intents, companion_states])
	law.call("update_actor_building_occupancy", actor_id, no_buildings)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	_free_ecs_compile_placeholder()
	if _failures.is_empty():
		print("HOME_RESIDENT_REALIZATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("HOME_RESIDENT_REALIZATION_FAILED count=%d" % _failures.size())
	quit(1)


func _free_ecs_compile_placeholder() -> void:
	if _ecs_compile_placeholder == null or not is_instance_valid(_ecs_compile_placeholder):
		return
	if Engine.has_singleton("ECS") and Engine.get_singleton("ECS") == _ecs_compile_placeholder:
		return
	_ecs_compile_placeholder.free()
	_ecs_compile_placeholder = null
