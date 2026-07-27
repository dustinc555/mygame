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
	await _wait_frames(180)
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
	var origin := Vector3(0.0, 1.0, 0.0)
	var canyon_town: Node = law.call("_find_settlement_by_id", "canyon")
	if canyon_town != null:
		canyon_town.call("contains_town_border_position", mira.global_position)
		var border_probe_started := Time.get_ticks_usec()
		for _probe in range(5):
			canyon_town.call("contains_town_border_position", mira.global_position)
		var border_probe_ms := float(Time.get_ticks_usec() - border_probe_started) / 1000.0
		_expect(border_probe_ms < 10.0, "Cached town-border checks must stay below 10ms for five warrants (%.2fms)" % border_probe_ms)
	else:
		_fail("NPC response validation could not resolve Canyon settlement")
	for index in range(members.size()):
		var member = members[index]
		member.global_position = origin + Vector3(float(index) * 1.5, 0.0, 0.0)
		member.set("combat_stance", NpcRules.CombatStance.DEFENSIVE)
		member.call("set_active_player_order", false)
	await _wait_frames(3)
	var mira_id := _actor_id(mira)
	var attacker_id := "validation.synthetic_attacker"
	var mira_record: Dictionary = gecs.call("get_population_record", mira_id)
	_expect(str(mira_record.get("party_id", "")) == PartyManager.PLAYER_PARTY_ID, "Stable party membership must persist in the population record")

	# Every attack is queued. Selection policy, not the emitter, filters responders.
	members[2].set("combat_stance", NpcRules.CombatStance.PASSIVE)
	members[3].call("set_active_player_order", true)
	members[4].global_position = origin + Vector3(NpcRules.NPC_ALERT_PROXIMITY_RADIUS + 0.1, 0.0, 0.0)
	await _wait_frames(3)
	var emitted_before := _attack_event_count
	response_system.emit_attack_started(attacker_id, mira_id, origin, 0)
	await _wait_frames(5)
	_expect(_attack_event_count == emitted_before + 1, "Attack emission must be unconditional and observable")
	var intents: Array[Dictionary] = response_system.get_active_intents()
	_expect(_has_intent(intents, _actor_id(members[1]), attacker_id, C_INTENT.Kind.SOCIAL_DEFENSE), "Nearby party member must receive social defense intent")
	_expect(not _has_intent(intents, _actor_id(members[2]), attacker_id, C_INTENT.Kind.SOCIAL_DEFENSE), "Passive party member must not receive response intent")
	_expect(not _has_intent(intents, _actor_id(members[3]), attacker_id, C_INTENT.Kind.SOCIAL_DEFENSE), "Player-ordered party member must not receive response intent")
	_expect(not _has_intent(intents, _actor_id(members[4]), attacker_id, C_INTENT.Kind.SOCIAL_DEFENSE), "Party member outside 40m must not receive response intent")

	# Faction diplomacy is data, not hard-coded response branching.
	var factions := world_scene.find_child("FactionController", true, false)
	mira.remove_meta("party_id")
	members[2].remove_meta("party_id")
	mira.set("faction_name", "validation_protected")
	members[2].set("faction_name", "validation_responder")
	members[2].set("combat_stance", NpcRules.CombatStance.DEFENSIVE)
	if factions != null:
		factions.call("set_diplomatic_state", "validation_protected", "validation_responder", "alliance")
	await _wait_frames(3)
	var alliance_target_id := "validation.synthetic_alliance_attacker"
	response_system.emit_attack_started(alliance_target_id, mira_id, origin, 0)
	await _wait_frames(5)
	intents = response_system.get_active_intents()
	_expect(_has_intent(intents, _actor_id(members[2]), alliance_target_id, C_INTENT.Kind.SOCIAL_DEFENSE), "Formal ally must receive social defense intent")
	if factions != null:
		factions.call("set_diplomatic_state", "validation_protected", "validation_responder", "protectorate", "validation_protected", "validation_responder")
	var protectorate_target_id := "validation.synthetic_protectorate_attacker"
	response_system.emit_attack_started(protectorate_target_id, mira_id, origin, 0)
	await _wait_frames(5)
	intents = response_system.get_active_intents()
	_expect(_has_intent(intents, _actor_id(members[2]), protectorate_target_id, C_INTENT.Kind.SOCIAL_DEFENSE), "Protector must receive social defense intent")

	# A response attack is still emitted, but depth one prevents another recruitment layer.
	var relay_protected = members[2]
	relay_protected.set("combat_stance", NpcRules.CombatStance.DEFENSIVE)
	members[3].call("set_active_player_order", false)
	await _wait_frames(3)
	emitted_before = _attack_event_count
	var relay_target_id := "validation.synthetic_response_attacker"
	response_system.emit_attack_started(relay_target_id, _actor_id(relay_protected), origin, 1)
	await _wait_frames(5)
	_expect(_attack_event_count == emitted_before + 1, "Response attacks must still emit combat events")
	intents = response_system.get_active_intents()
	_expect(not _has_intent(intents, _actor_id(members[3]), relay_target_id, C_INTENT.Kind.SOCIAL_DEFENSE), "Response depth one must not relay to another ally layer")
	var revoke_authority_id := "validation|private|revoke"
	response_system.authorize_response(C_EVENT.Audience.EXPLICIT_ACTORS, "validation.synthetic_private_target", mira_id, revoke_authority_id, "", "", origin, NpcRules.NPC_ALERT_PROXIMITY_RADIUS, C_INTENT.Kind.PRIVATE_DEFENSE, PackedStringArray([_actor_id(members[1])]))
	await _wait_frames(5)
	_expect(response_system.has_active_authority_response(revoke_authority_id), "Typed response authorization must create an indexed authority intent")
	response_system.revoke_response(revoke_authority_id)
	await _wait_frames(5)
	_expect(not response_system.has_active_authority_response(revoke_authority_id), "Typed response revocation must remove indexed authority intents")

	# Real failure case: law authorizes guards, a guard attacks Mira, then Mira's party responds.
	for member in members:
		member.set_meta("party_id", PartyManager.PLAYER_PARTY_ID)
		member.set("faction_name", "Player")
		member.set("combat_stance", NpcRules.CombatStance.DEFENSIVE)
		member.call("set_active_player_order", false)
		member.set_physics_process(false)
	await _wait_frames(3)
	var authority_ids := PackedStringArray()
	for actor_state_value in (gecs.call("get_actor_states") as Dictionary).values():
		var actor_state: Dictionary = actor_state_value
		if str(actor_state.get("settlement_id", "")) == "canyon" and Array(actor_state.get("authority_scopes", [])).has("settlement_authority"):
			authority_ids.append(str(actor_state.get("actor_id", "")))
	authority_ids.sort()
	_expect(not authority_ids.is_empty(), "Rustwash must expose settlement-authority actors")
	var law_origin := origin
	if not authority_ids.is_empty():
		var origin_guard = gecs.call("get_actor_by_stable_id", authority_ids[0])
		if origin_guard != null:
			law_origin = Vector3(origin_guard.global_position.x, 1.0, origin_guard.global_position.z)
	for member in members:
		member.global_position = law_origin + Vector3(float(members.find(member)) * 1.25, 0.0, 0.0)
	for index in range(authority_ids.size()):
		var guard = gecs.call("get_actor_by_stable_id", authority_ids[index])
		if guard != null:
			guard.global_position = law_origin + Vector3(0.8 + float(index) * 0.1, 0.0, 0.8)
			guard.set_physics_process(false)
	var wrong_faction_guard_id := str(authority_ids[-1]) if authority_ids.size() > 1 else ""
	if not wrong_faction_guard_id.is_empty():
		var wrong_faction_guard = gecs.call("get_actor_by_stable_id", wrong_faction_guard_id)
		if wrong_faction_guard != null:
			wrong_faction_guard.set("faction_name", "validation_wrong_authority")
	await _wait_frames(3)
	var law_events_before := _law_event_count
	var warrant: Dictionary = law.call("report_crime", mira, "Canyonites", "canyon", "assault", 10, members[1], null, {"event_origin": law_origin})
	var authority_id := str(warrant.get("response_authority_id", ""))
	await _wait_frames(5)
	_expect(_law_event_count == law_events_before + 1, "Law authorization must emit one typed response event")
	_expect(not authority_id.is_empty(), "Warrant must own a stable response authority ID")
	intents = response_system.get_active_intents()
	var responding_guard_id := ""
	for guard_id in authority_ids:
		if _has_intent(intents, guard_id, mira_id, C_INTENT.Kind.LAW_ENFORCEMENT):
			responding_guard_id = guard_id
			break
	_expect(not responding_guard_id.is_empty(), "Law authorization must create typed guard response intent")
	if not wrong_faction_guard_id.is_empty():
		_expect(not _has_intent(intents, wrong_faction_guard_id, mira_id, C_INTENT.Kind.LAW_ENFORCEMENT), "Authority actors must not enforce another faction's warrant")
	var party_joined := false
	for _frame in range(360):
		await get_tree().process_frame
		intents = response_system.get_active_intents()
		for member_index in range(1, members.size()):
			for guard_id in authority_ids:
				if _has_intent(intents, _actor_id(members[member_index]), guard_id, C_INTENT.Kind.SOCIAL_DEFENSE):
					party_joined = true
					break
			if party_joined:
				break
		if party_joined:
			break
	var guard_state: Dictionary = gecs.call("get_actor_state", responding_guard_id)
	_expect(party_joined, "A guard attack on Mira must trigger nearby party response (guard_target=%s slot=%s slot_target=%s pos=%s attack_events=%d intents=%s)" % [str(guard_state.get("system_target_actor_id", "")), str(guard_state.get("combat_slot_state", "")), str(guard_state.get("combat_slot_target_actor_id", "")), str(guard_state.get("world_position", "")), _attack_event_count, JSON.stringify(intents)])

	_finish()


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
