extends "res://tests/validation/law_order_cases.gd"

## Complete picking -> actual sight -> warrant -> physical law response.
## Reuses the production jail fixture; positioning isolates sight, not navigation.
func _case_names() -> Array[String]:
	return ["_validate_lockpicking_sight_response"]

func _validate_lockpicking_sight_response() -> void:
	var player := _get_player()
	var law := _get_law_controller() as LawOrderController
	var jail := _get_jail()
	var cell := jail.get_node("Furniture/Cell1") as JailCell
	var bridge := BootstrapContext.service(&"lockpick_interactions")
	var locks := BootstrapContext.service(&"lockpicking")
	var perception := BootstrapContext.service(PerceptionController.SERVICE_ID) as PerceptionController
	var query := BootstrapContext.service(ActorQueryController.SERVICE_ID) as ActorQueryController
	# Isolate one initially unseeing authority without inventing its employment,
	# crime, combat intent, perception result or law record.
	for other in query.get_alive_actors(false):
		FIXTURE.reset_order(other)
		other.process_mode = Node.PROCESS_MODE_DISABLED
		other.global_position = Vector3(65, 0.6, 0)
	locks.settings = locks.settings.duplicate()
	locks.settings.careful_risk = 0.0
	player.set_skill_level(SkillRules.SUBTERFUGE_LOCKPICKING, 1.0)
	if not player.inventory.add_item(load("res://features/inventory/resources/items/lockpick.tres")):
		_fail("Fixture must give the actor an actual carried pick")
		return
	player.global_position = cell.get_lockpick_position(player)
	player.velocity = Vector3.ZERO
	if not bridge.request_pick(player, cell):
		_fail("Real foreign jail cell must accept the physical picking command")
		return
	if not await _wait_until(func() -> bool: return player.is_actively_lockpicking(), 480):
		_fail("Player must reach and begin working the actual cage")
		return
	# Use the work position after arrival, beside the actor in the cage aisle.
	# The cage-front offset crosses this fixture's wall; it is not a sightline.
	var guard_offset := cell.global_basis.x * 2.0
	_jail_guard.global_position = player.global_position + guard_offset
	_jail_guard.velocity = Vector3.ZERO
	_jail_guard._face_world_position(_jail_guard.global_position + guard_offset)
	await _wait_frames(3)
	if bool(perception.evaluate_observer(_jail_guard, player).get("clearly_seen", false)):
		_fail("Facing-away fixture must start without actual sight")
		return
	await _wait_frames(40)
	if law.actor_has_active_warrant(player, FACTION_ID):
		_fail("Unseen picking must not create an omniscient warrant")
		return
	var lock_id := str(cell.get_lockpick_record().lock_id)
	if int(locks.get_state(lock_id).check_sequence) != 0:
		_fail("Sight case must precede any pass or slip")
		return
	_jail_guard._face_world_position(player.global_position)
	var sight_result := perception.evaluate_observer(_jail_guard, player)
	print("LOCKPICK_SIGHT_TRACE ", JSON.stringify({"actor": player.stable_id, "guard": _jail_guard.stable_id, "cell": lock_id, "faction": law._settlement_faction_id(law._find_containing_settlement(cell)), "vision": sight_result}))
	if not bool(sight_result.get("clearly_seen", false)):
		for sample in player.get_stealth_sample_positions():
			var ray := PhysicsRayQueryParameters3D.create(_jail_guard.get_perception_eye_position(), sample)
			ray.exclude = [_jail_guard.get_rid(), player.get_rid()]
			var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
			print("LOCKPICK_OCCLUSION_TRACE guard=%s player=%s eye=%s sample=%s collider=%s hit=%s" % [_jail_guard.global_position, player.global_position, ray.from, sample, hit.collider.get_path() if not hit.is_empty() else "none", hit.get("position")])
		_fail("Facing the picking actor must supply real clear sight, not a stub")
		return
	var attack_before := _attack_sequence(_jail_guard)
	if not await _wait_until(func() -> bool: return law.actor_has_active_warrant(player, FACTION_ID), 120):
		print("LOCKPICK_REPORT_TRACE actor_faction=%s guard_faction=%s picking=%s sessions=%s sight=%s" % [player.faction_name, _jail_guard.faction_name, player.is_actively_lockpicking(), bridge._sessions, perception.evaluate_observer(_jail_guard, player)])
		_fail("A guard seeing ongoing clean picking must create a warrant")
		return
	_jail_guard.process_mode = Node.PROCESS_MODE_INHERIT
	var alarm_found := false
	for notice in get_tree().current_scene.get_children():
		var label := notice.get_node_or_null("Label3D") as Label3D
		if label != null and label.text == "Guards! Lockpick!":
			alarm_found = true
			break
	if not alarm_found:
		_fail("The actual witness must emit the visible lockpicking alarm")
	var record := law.get_warrant_record(player, FACTION_ID)
	if record.crimes.size() != 1 or not _record_has_crime(record, LawOrderController.CRIME_LOCKPICKING):
		_fail("Witnessed picking must create exactly one lockpicking charge")
	if int(locks.get_state(lock_id).check_sequence) != 0:
		_fail("Detection must not wait for a pass/fail result")
	if not await _wait_until(func() -> bool: return FIXTURE.is_law_response(_jail_guard, player), 180):
		_fail("Witnessed picking must dispatch the real jail guard's law response")
	if not await _wait_until(func() -> bool: return _attack_started_against(_jail_guard, player, attack_before), 600):
		_fail("The responding jail guard must physically engage the exact offender")
	if not await _wait_until(func() -> bool: return not player.is_actively_lockpicking(), 120):
		_fail("Combat must interrupt lock work and release the held-pick pose")
	if bridge._sessions.has(player.stable_id):
		_fail("Combat must release the volatile picking session")
	if law.get_warrant_record(player, FACTION_ID).crimes.size() != 1:
		_fail("Sustained observation must not multiply the charge")
	print("LOCKPICK_LAW_RESPONSE_TRACE guard=%s alarm=%s response=%s attacks_before=%d attacks_after=%d picking=%s" % [_jail_guard.stable_id, alarm_found, FIXTURE.is_law_response(_jail_guard, player), attack_before, _attack_sequence(_jail_guard), player.is_actively_lockpicking()])
