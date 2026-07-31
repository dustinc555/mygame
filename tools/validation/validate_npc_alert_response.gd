extends Node

const WORLD_SCENE := "res://scenes/zones/rustwash_basin/rustwash_basin.tscn"
const C_EVENT := preload("res://features/combat/sim/c_game_combat_event.gd")
const C_INTENT := preload("res://features/combat/sim/c_game_combat_response_intent.gd")

var _failures: Array[String] = []
var _attack_event_count := 0
var _law_event_count := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_scene := (load(WORLD_SCENE) as PackedScene).instantiate()
	var terrain := world_scene.get_node_or_null("Terrain")
	if terrain != null:
		world_scene.remove_child(terrain)
		terrain.free()
	add_child(world_scene)
	await _wait_frames(60)
	var party_manager := world_scene.find_child("PartyManager", true, false)
	var gecs := world_scene.find_child("GecsWorldController", true, false)
	var response_system := world_scene.find_child("GameCombatResponseSystem", true, false)
	var law := world_scene.find_child("LawOrderController", true, false)
	if party_manager == null or gecs == null or response_system == null or law == null:
		_fail("NPC response validation could not resolve party, GECS, response, or law system")
		_finish()
		return
	response_system.combat_event_emitted.connect(_on_combat_event_emitted)
	var members: Array = party_manager.get("party_members")
	if members.size() < 5:
		_fail("NPC response validation needs five party members")
		_finish()
		return
	var mira = members[0]
	var mira_id := _actor_id(mira)
	for member in members:
		member.set("protected_from_combat", true)
		member.set_physics_process(false)
	var resident = _first_realized_outsider(gecs, members, {})
	for _frame in range(180):
		if resident != null:
			break
		await get_tree().process_frame
		resident = _first_realized_outsider(gecs, members, {})
	if resident == null:
		_fail("NPC response validation needs one realized non-party resident")
		_finish()
		return
	var resident_id := _actor_id(resident)
	var origin := Vector3(0.0, 1.0, 0.0)
	for index in range(members.size()):
		var member = members[index]
		member.global_position = origin + Vector3(float(index) * 1.5, 0.0, 0.0)
		member.set("combat_stance", NpcRules.CombatStance.DEFENSIVE)
		member.set("protected_from_combat", true)
		member.call("set_active_player_order", false)
		member.set_physics_process(false)
	resident.global_position = origin + Vector3(0.0, 0.0, 2.0)
	resident.set("protected_from_combat", true)
	resident.set_physics_process(false)
	members[2].set("combat_stance", NpcRules.CombatStance.PASSIVE)
	members[3].call("set_active_player_order", true)
	members[4].global_position = origin + Vector3(NpcRules.NPC_ALERT_PROXIMITY_RADIUS + 0.1, 0.0, 0.0)
	await _wait_frames(120)
	for member in members:
		member.set("protected_from_combat", false)
	resident.set("protected_from_combat", false)
	await _wait_frames(3)

	var emitted_before := _attack_event_count
	response_system.emit_attack_started(mira_id, resident_id, origin, 0)
	await _wait_frames(5)
	_expect(_attack_event_count == emitted_before + 1, "Attack emission must be unconditional and observable")
	var encounter := _encounter_for_actor(response_system.get_active_encounters(), mira_id)
	_expect(not encounter.is_empty(), "Mira's attack must create a combat encounter")
	_expect(str(encounter.get("root_aggressor_actor_id", "")) == mira_id, "Mira must remain the root aggressor")
	_expect(_on_side(encounter, "aggressor_side_actor_ids", _actor_id(members[1])), "Nearby party member must join Mira's encounter")
	_expect(not _encounter_has_actor(encounter, _actor_id(members[2])), "Passive party member must not join the encounter")
	_expect(_on_side(encounter, "aggressor_side_actor_ids", _actor_id(members[3])), "Player-ordered party member must still join its party encounter: %s" % JSON.stringify(encounter))
	var ordered_member_state: Dictionary = gecs.call("get_actor_state", _actor_id(members[3]))
	_expect(str(ordered_member_state.get("system_target_actor_id", "")).is_empty(), "Encounter membership must not override an explicit player order with automatic combat")
	_expect(not _encounter_has_actor(encounter, _actor_id(members[4])), "Party member outside 40m must not join the encounter")
	_expect(not PackedStringArray(encounter.get("committed_actor_ids", PackedStringArray())).has(_actor_id(members[1])), "Joining alone must not make a party member a committed aggressor")

	# Put the encounter at the guards. The existing encounter is kept so this
	# validates the exact progression from root aggressor to arriving allies.
	var authority_ids := PackedStringArray()
	for actor_state_value in (gecs.call("get_actor_states") as Dictionary).values():
		var actor_state: Dictionary = actor_state_value
		if str(actor_state.get("settlement_id", "")) == "canyon" and Array(actor_state.get("authority_scopes", [])).has("settlement_authority"):
			authority_ids.append(str(actor_state.get("actor_id", "")))
	authority_ids.sort()
	_expect(authority_ids.size() >= 2, "Rustwash must expose at least two settlement-authority actors")
	if authority_ids.is_empty():
		_finish()
		return
	var law_origin := origin
	var first_guard = gecs.call("get_actor_by_stable_id", authority_ids[0])
	if first_guard != null:
		law_origin = Vector3(first_guard.global_position.x, 1.0, first_guard.global_position.z)
	resident.global_position = law_origin + Vector3(0.0, 0.0, 2.5)
	for index in range(members.size()):
		members[index].global_position = law_origin + Vector3(float(index) * 0.65, 0.0, 0.0)
		members[index].set_physics_process(false)
	for index in range(authority_ids.size()):
		var guard = gecs.call("get_actor_by_stable_id", authority_ids[index])
		if guard != null:
			guard.global_position = law_origin + Vector3(3.0 + float(index) * 0.35, 0.0, 0.2)
			guard.set_physics_process(false)
	var wrong_faction_guard_id := str(authority_ids[-1])
	if authority_ids.size() > 2:
		var wrong_guard = gecs.call("get_actor_by_stable_id", wrong_faction_guard_id)
		if wrong_guard != null:
			wrong_guard.set("faction_name", "validation_wrong_authority")
	else:
		wrong_faction_guard_id = ""
	await _wait_frames(5)

	var law_events_before := _law_event_count
	var warrant: Dictionary = law.call("report_player_assault", mira, resident)
	var authority_id := str(warrant.get("response_authority_id", ""))
	await _wait_frames(8)
	_expect(_law_event_count == law_events_before + 1, "Law authorization must emit one typed response event")
	_expect(not authority_id.is_empty(), "Mira's warrant must own a stable response authority ID")
	_expect(str(warrant.get("faction_id", "")) == "Canyonites", "Settlement jurisdiction must own the assault warrant")
	var intents: Array[Dictionary] = response_system.get_active_intents()
	var responding_guard_ids := PackedStringArray()
	var encounters_before_guard_entry: Array[Dictionary] = response_system.get_active_encounters()
	for guard_id in authority_ids:
		if _has_intent(intents, guard_id, mira_id, C_INTENT.Kind.LAW_ENFORCEMENT) and _encounter_for_actor(encounters_before_guard_entry, guard_id).is_empty():
			responding_guard_ids.append(guard_id)
	_expect(not responding_guard_ids.is_empty(), "Law alert must create typed guard response intents")
	if not wrong_faction_guard_id.is_empty():
		_expect(not responding_guard_ids.has(wrong_faction_guard_id), "Authority actors must not enforce another faction's warrant")

	var initial_target_seen := false
	for _frame in range(180):
		await get_tree().process_frame
		for guard_id in responding_guard_ids:
			var guard_state: Dictionary = gecs.call("get_actor_state", guard_id)
			if str(guard_state.get("system_target_actor_id", "")) == mira_id:
				initial_target_seen = true
				break
		if initial_target_seen:
			break
	_expect(initial_target_seen, "Guards must initially target Mira while she is the only committed aggressor")

	# The doorway blockers become lawful guard targets only when they swing.
	var responding_guard_id := str(responding_guard_ids[0]) if not responding_guard_ids.is_empty() else ""
	if not responding_guard_id.is_empty():
		response_system.emit_attack_started(responding_guard_id, mira_id, law_origin, 0, str(encounter.get("encounter_id", "")), true)
		await _wait_frames(4)
	var blocker_ids := PackedStringArray([_actor_id(members[1]), _actor_id(members[3])])
	for blocker_id in blocker_ids:
		response_system.emit_attack_started(blocker_id, responding_guard_id, law_origin, 0)
		await _wait_frames(3)
	encounter = _encounter_for_actor(response_system.get_active_encounters(), mira_id)
	var committed := PackedStringArray(encounter.get("committed_actor_ids", PackedStringArray()))
	var aggressions: Dictionary = encounter.get("aggression_target_by_actor", {})
	for blocker_id in blocker_ids:
		_expect(committed.has(blocker_id), "A party member must become committed after attacking: %s" % blocker_id)
		_expect(aggressions.has(blocker_id), "A committed party attacker must become a lawful guard candidate: %s" % blocker_id)

	var distributed_targets := {}
	for _frame in range(240):
		await get_tree().process_frame
		distributed_targets.clear()
		for guard_id in responding_guard_ids:
			var guard_state: Dictionary = gecs.call("get_actor_state", guard_id)
			var target_id := str(guard_state.get("system_target_actor_id", ""))
			if target_id == mira_id or blocker_ids.has(target_id):
				distributed_targets[target_id] = true
		if distributed_targets.size() >= mini(2, responding_guard_ids.size()):
			break
	_expect(distributed_targets.keys().any(func(target_id) -> bool: return blocker_ids.has(str(target_id))), "Guards must target committed party blockers instead of all walking past them to Mira")
	if responding_guard_ids.size() >= 2:
		_expect(distributed_targets.size() >= 2, "Guard pressure must distribute across multiple committed aggressors")

	await _wait_frames(30)
	for blocker_id in blocker_ids:
		var blocker = gecs.call("get_actor_by_stable_id", blocker_id)
		_expect(not (law.call("get_warrant_record", blocker, "Canyonites") as Dictionary).is_empty(), "Each committed party attacker must receive an individual assault warrant: %s" % blocker_id)

	if not responding_guard_id.is_empty():
		var warrants: Dictionary = law.get("warrants")
		_expect(not warrants.has(responding_guard_id), "Authorized law attacks must not create warrants against guards")
		var retaliation_warrant: Dictionary = law.call("report_player_assault", mira, gecs.call("get_actor_by_stable_id", responding_guard_id))
		_expect(retaliation_warrant.is_empty(), "Retaliation against an opposing encounter participant must remain lawful")

	_finish()


func _first_realized_outsider(gecs, excluded: Array, excluded_ids: Dictionary):
	for actor_state_value in (gecs.call("get_actor_states") as Dictionary).values():
		var actor_state: Dictionary = actor_state_value
		var candidate_id := str(actor_state.get("actor_id", ""))
		if candidate_id.is_empty() or excluded_ids.has(candidate_id):
			continue
		var candidate = gecs.call("get_actor_by_stable_id", candidate_id)
		if candidate != null and not excluded.has(candidate):
			return candidate
	for candidate in gecs.get_tree().get_nodes_in_group("world_actor"):
		var candidate_id := _actor_id(candidate)
		if candidate != null and not candidate_id.is_empty() and not excluded_ids.has(candidate_id) and not excluded.has(candidate):
			return candidate
	return null


func _encounter_for_actor(encounters: Array[Dictionary], actor_id: String) -> Dictionary:
	for encounter in encounters:
		if _encounter_has_actor(encounter, actor_id):
			return encounter
	return {}


func _encounter_has_actor(encounter: Dictionary, actor_id: String) -> bool:
	return _on_side(encounter, "aggressor_side_actor_ids", actor_id) or _on_side(encounter, "defender_side_actor_ids", actor_id)


func _on_side(encounter: Dictionary, key: String, actor_id: String) -> bool:
	return PackedStringArray(encounter.get(key, PackedStringArray())).has(actor_id)


func _has_intent(intents: Array[Dictionary], responder_actor_id: String, target_actor_id: String, kind: int) -> bool:
	for intent in intents:
		if str(intent.get("responder_actor_id", "")) == responder_actor_id and str(intent.get("target_actor_id", "")) == target_actor_id and int(intent.get("kind", -1)) == kind:
			return true
	return false


func _on_combat_event_emitted(_event_id: String, event_type: int) -> void:
	if event_type == C_EVENT.Type.ATTACK_STARTED:
		_attack_event_count += 1
	elif event_type == C_EVENT.Type.RESPONSE_AUTHORIZED:
		_law_event_count += 1


func _actor_id(actor: Node) -> String:
	if actor == null:
		return ""
	var stable_id = actor.get("stable_id")
	return str(stable_id).strip_edges() if stable_id != null else str(actor.get_meta("actor_record_id", "")).strip_edges()


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("NPC_ALERT_RESPONSE_OK")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("NPC_ALERT_RESPONSE_FAILED count=%d" % _failures.size())
	get_tree().quit(1)
