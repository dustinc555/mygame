extends SceneTree

const BATTLE_SIM_SCRIPT := preload("res://scripts/sim/battle/battle_sim.gd")
const CONTINUITY_BUILDER_SCRIPT := preload("res://scripts/sim/battle/combat_projection_continuity_builder.gd")
const CURRENT_TICK := 91
const LIFE_STATE_ALIVE := 0
const LIFE_STATE_DYING := 5

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_validate_resolved_aftermath_continuity()
	_validate_active_continuity_refs()
	_validate_continuity_determinism()
	_finish()


func _validate_resolved_aftermath_continuity() -> void:
	var case_data := _resolved_case("continuity_resolved", 6)
	var encounter_record: Dictionary = case_data.get("encounter_record", {})
	var battle_result: Dictionary = case_data.get("battle_result", {})
	var current_records: Dictionary = case_data.get("current_records", {})
	var truth_signature_before := _truth_signature(battle_result)
	var continuity: Dictionary = CONTINUITY_BUILDER_SCRIPT.build_continuity(encounter_record, battle_result, current_records, {"recent_replay_event_limit": 16})
	_expect(_truth_signature(battle_result) == truth_signature_before, "Continuity builder does not mutate BattleSim truth")
	_validate_common_continuity(continuity, battle_result, "Resolved")
	_expect(str(continuity.get("projection_state", "")) == "aftermath", "Resolved continuity uses aftermath projection state")
	_expect(_string_array(continuity.get("active_group_ids", [])).is_empty(), "Resolved continuity does not expose active groups")
	_expect(_string_array(continuity.get("active_slot_ids", [])).is_empty(), "Resolved continuity does not expose active slots")
	_expect(_string_array(continuity.get("aftermath_member_ids", [])).has("continuity_resolved.a.001"), "Resolved continuity marks current downed/dying member as aftermath")
	for event_id in _string_array(continuity.get("replay_event_ids", [])):
		var event := _schedule_event_by_id(battle_result, event_id)
		_expect(_event_is_important(event), "Resolved continuity replays only important events")


func _validate_active_continuity_refs() -> void:
	var case_data := _active_case("continuity_active", 5)
	var encounter_record: Dictionary = case_data.get("encounter_record", {})
	var battle_result: Dictionary = case_data.get("battle_result", {})
	var current_records: Dictionary = case_data.get("current_records", {})
	var continuity: Dictionary = CONTINUITY_BUILDER_SCRIPT.build_continuity(encounter_record, battle_result, current_records, {"recent_replay_event_limit": 16})
	_validate_common_continuity(continuity, battle_result, "Active")
	_expect(str(continuity.get("projection_state", "")) == "active", "Active continuity uses active projection state")
	_expect(_string_array(continuity.get("active_group_ids", [])).size() == _groups(battle_result).size(), "Active continuity exposes active group ids")
	_expect(_string_array(continuity.get("active_slot_ids", [])).size() == _slots(battle_result).size(), "Active continuity exposes active slot ids")
	_expect((continuity.get("member_states", {}) is Dictionary) and (continuity.get("member_states", {}) as Dictionary).size() >= 10, "Active continuity exposes current member states")


func _validate_continuity_determinism() -> void:
	var case_data := _resolved_case("continuity_deterministic", 8)
	var first: Dictionary = CONTINUITY_BUILDER_SCRIPT.build_continuity(case_data.get("encounter_record", {}), case_data.get("battle_result", {}), case_data.get("current_records", {}), {"recent_replay_event_limit": 8})
	var second: Dictionary = CONTINUITY_BUILDER_SCRIPT.build_continuity(case_data.get("encounter_record", {}), case_data.get("battle_result", {}), case_data.get("current_records", {}), {"recent_replay_event_limit": 8})
	_expect(_continuity_signature(first) == _continuity_signature(second), "Continuity output is deterministic for identical inputs")


func _validate_common_continuity(continuity: Dictionary, battle_result: Dictionary, label: String) -> void:
	_expect(not continuity.is_empty(), "%s continuity exists" % label)
	_expect(str(continuity.get("encounter_id", "")).strip_edges() != "", "%s continuity has encounter_id" % label)
	_expect(str(continuity.get("status", "")).strip_edges() != "", "%s continuity has status" % label)
	_expect(continuity.get("member_states", {}) is Dictionary, "%s continuity has member_states dictionary" % label)
	_expect(bool(continuity.get("presentation_only", false)), "%s continuity is presentation-only" % label)
	_expect(int(continuity.get("recent_replay_event_limit", 0)) > 0, "%s continuity records replay cap" % label)
	_validate_event_refs(continuity, battle_result, label)
	_validate_no_live_refs(continuity, label)


func _validate_event_refs(continuity: Dictionary, battle_result: Dictionary, label: String) -> void:
	var schedule_event_ids := _schedule_event_ids(battle_result)
	for event_id in _string_array(continuity.get("replay_event_ids", [])):
		_expect(schedule_event_ids.has(event_id), "%s replay_event_id references existing schedule event" % label)
	for event_id in _string_array(continuity.get("summarized_event_ids", [])):
		_expect(schedule_event_ids.has(event_id), "%s summarized_event_id references existing schedule event" % label)
	var replay_lookup := {}
	for event_id in _string_array(continuity.get("replay_event_ids", [])):
		replay_lookup[event_id] = true
	for event_id in _string_array(continuity.get("summarized_event_ids", [])):
		_expect(not replay_lookup.has(event_id), "%s event is not both replayed and summarized" % label)


func _validate_no_live_refs(value, label: String, path := "continuity") -> void:
	if value is Node:
		_failures.append("%s stores live Node at %s" % [label, path])
		return
	if value is NodePath:
		_failures.append("%s stores NodePath at %s" % [label, path])
		return
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			_validate_no_live_refs((value as Dictionary).get(key), label, "%s.%s" % [path, str(key)])
	elif value is Array:
		for index in range((value as Array).size()):
			_validate_no_live_refs((value as Array)[index], label, "%s[%d]" % [path, index])


func _resolved_case(label: String, rounds: int) -> Dictionary:
	var case_data := _case_data(label, rounds, "resolved", label)
	var current_records: Dictionary = case_data.get("current_records", {})
	var squad_records: Array = current_records.get("squad_records", []) if current_records.get("squad_records", []) is Array else []
	if squad_records.size() > 0 and squad_records[0] is Dictionary:
		var squad_record: Dictionary = squad_records[0]
		var members: Array = squad_record.get("member_records", []) if squad_record.get("member_records", []) is Array else []
		if members.size() > 0 and members[0] is Dictionary:
			var member: Dictionary = members[0]
			member["life_state"] = LIFE_STATE_DYING
			member["hp"] = 0.0
			members[0] = member
			squad_record["member_records"] = members
			squad_records[0] = squad_record
			current_records["squad_records"] = squad_records
			case_data["current_records"] = current_records
	return case_data


func _active_case(label: String, rounds: int) -> Dictionary:
	return _case_data(label, rounds, "resolving", label)


func _case_data(label: String, rounds: int, status: String, seed: String) -> Dictionary:
	var encounter_id := "encounter:validation:%s" % label
	var squad_a := _squad_record("%s.a" % label, _member_records("%s.a" % label, 5))
	var squad_b := _squad_record("%s.b" % label, _member_records("%s.b" % label, 5))
	var encounter_record := {"encounter_id": encounter_id, "created_tick": 1, "status": status, "location": Vector3.ZERO, "squad_ids": ["%s.a" % label, "%s.b" % label]}
	var battle_result: Dictionary = BATTLE_SIM_SCRIPT.resolve_encounter(encounter_record, squad_a, squad_b, {"encounter_id": encounter_id, "current_tick": CURRENT_TICK, "rounds": rounds, "seed": seed})
	return {
		"encounter_record": encounter_record,
		"battle_result": battle_result,
		"current_records": {"squad_records": [squad_a.duplicate(true), squad_b.duplicate(true)]},
	}


func _squad_record(squad_id: String, member_records: Array[Dictionary]) -> Dictionary:
	return {
		"squad_id": squad_id,
		"member_count": member_records.size(),
		"member_records": member_records,
		"member_records_are_canonical": true,
		"strength": 80.0,
		"base_strength": 10.0,
		"base_attack_damage": 12.0,
		"max_hp": 100.0,
		"combat_stance": 1,
		"morale": 1.0,
		"supplies": 40.0,
	}


func _member_records(prefix: String, count: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for index in range(1, count + 1):
		var member_id := "%s.%03d" % [prefix, index]
		records.append({
			"actor_id": member_id,
			"stable_id": member_id,
			"member_id": member_id,
			"member_name": member_id,
			"squad_id": prefix,
			"life_state": LIFE_STATE_ALIVE,
			"hp": 100.0,
			"max_hp": 100.0,
			"blood": 5.0,
			"max_blood": 5.0,
			"base_attack_damage": 12.0,
			"base_dodge_chance": 0.0,
			"base_block_chance": 0.0,
			"skill_levels": {
				"attribute.strength": 4.0,
				"attribute.perception": 4.0,
				"attribute.dexterity": 4.0,
				"attribute.toughness": 4.0,
				"attribute.endurance": 4.0,
				"combat.swords_one_handed": 5.0,
				"combat.axes_one_handed": 3.0,
				"combat.daggers": 2.0,
				"combat.unarmed": 2.0,
				"combat.shields": 3.0,
			},
		})
	return records


func _truth_signature(battle_result: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [
		str(battle_result.get("outcome", "")),
		str(battle_result.get("winner_squad_id", "")),
		str(battle_result.get("loser_squad_id", "")),
		str(battle_result.get("member_casualties", {})),
		str(battle_result.get("beats", [])),
	]


func _continuity_signature(continuity: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s" % [
		str(continuity.get("encounter_id", "")),
		str(continuity.get("status", "")),
		str(continuity.get("projection_state", "")),
		_join_strings(_string_array(continuity.get("active_group_ids", [])), ","),
		_join_strings(_string_array(continuity.get("active_slot_ids", [])), ","),
		_join_strings(_string_array(continuity.get("replay_event_ids", [])), ","),
		_join_strings(_string_array(continuity.get("aftermath_member_ids", [])), ","),
	]


func _schedule_event_ids(battle_result: Dictionary) -> Dictionary:
	var ids := {}
	var schedule: Dictionary = battle_result.get("combat_schedule", {}) if battle_result.get("combat_schedule", {}) is Dictionary else {}
	var events: Array = schedule.get("events", []) if schedule.get("events", []) is Array else []
	for event in events:
		if event is Dictionary:
			var event_id := str((event as Dictionary).get("event_id", "")).strip_edges()
			if not event_id.is_empty():
				ids[event_id] = true
	return ids


func _schedule_event_by_id(battle_result: Dictionary, event_id: String) -> Dictionary:
	var schedule: Dictionary = battle_result.get("combat_schedule", {}) if battle_result.get("combat_schedule", {}) is Dictionary else {}
	var events: Array = schedule.get("events", []) if schedule.get("events", []) is Array else []
	for event in events:
		if event is Dictionary and str((event as Dictionary).get("event_id", "")) == event_id:
			return event
	return {}


func _event_is_important(event: Dictionary) -> bool:
	match str(event.get("importance", "normal")):
		"high", "critical", "important":
			return true
		_:
			return false


func _groups(battle_result: Dictionary) -> Array:
	return battle_result.get("engagement_groups", []) if battle_result.get("engagement_groups", []) is Array else []


func _slots(battle_result: Dictionary) -> Dictionary:
	return battle_result.get("combat_slots", {}) if battle_result.get("combat_slots", {}) is Dictionary else {}


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _join_strings(parts: Array[String], delimiter: String) -> String:
	var result := ""
	for index in range(parts.size()):
		if index > 0:
			result += delimiter
		result += parts[index]
	return result


func _finish() -> void:
	if _failures.is_empty():
		print("COMBAT_CONTINUITY_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
