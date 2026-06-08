extends SceneTree

const BATTLE_SIM_SCRIPT := preload("res://scripts/sim/battle/battle_sim.gd")
const CURRENT_TICK := 90
const LIFE_STATE_ALIVE := 0
const DETAILED_EVENTS_PER_BEAT := 4

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_validate_1v1_sequence()
	_validate_5v5_interleaving()
	_validate_bounded_summarization()
	_validate_deterministic_schedule()
	_finish()


func _validate_1v1_sequence() -> void:
	var result := _resolve_member_case("schedule_one_v_one", 1, 1, 3, 32, "schedule-1v1")
	_validate_schedule_contract(result, "1v1")
	var schedule := _schedule(result)
	var events := _events(schedule)
	_expect(events.size() == 12, "1v1 schedules four events for each of three beats")
	var first_beat_id := str(_beats(result)[0].get("beat_id", "")) if _beats(result).size() > 0 and _beats(result)[0] is Dictionary else ""
	var first_beat_events := _events_for_beat(events, first_beat_id)
	_expect(_event_types(first_beat_events) == ["move_to_slot", "face_target", "attack", "reaction"], "1v1 event sequence is move, face, attack, reaction")


func _validate_5v5_interleaving() -> void:
	var result := _resolve_member_case("schedule_five_v_five", 5, 5, 5, 32, "schedule-5v5")
	_validate_schedule_contract(result, "5v5")
	var simultaneous_groups := {}
	for event in _events(_schedule(result)):
		if event is Dictionary and str((event as Dictionary).get("event_type", "")) == "move_to_slot" and is_equal_approx(float((event as Dictionary).get("start_time", -1.0)), 0.0):
			simultaneous_groups[str((event as Dictionary).get("engagement_group_id", ""))] = true
	_expect(simultaneous_groups.size() >= 2, "5v5 schedule interleaves multiple engagement groups at the same start time")


func _validate_bounded_summarization() -> void:
	var detailed_limit := 2
	var result := _resolve_member_case("schedule_bounded", 1, 1, 40, detailed_limit, "schedule-bounded")
	_validate_schedule_contract(result, "Bounded")
	var schedule := _schedule(result)
	var beats := _beats(result)
	var detailed_beat_ids := _string_array(schedule.get("detailed_beat_ids", []))
	var summarized_beat_ids := _string_array(schedule.get("summarized_beat_ids", []))
	_expect(int(schedule.get("detailed_beat_limit", 0)) == detailed_limit, "Bounded schedule records configured detailed limit")
	_expect(detailed_beat_ids.size() == detailed_limit, "Bounded schedule caps detailed beats")
	_expect(_events(schedule).size() == detailed_limit * DETAILED_EVENTS_PER_BEAT, "Bounded schedule caps detailed event count")
	_expect(summarized_beat_ids.size() == beats.size() - detailed_limit, "Bounded schedule summarizes non-detailed beats")
	var first_normal_beat_id := str((beats[0] as Dictionary).get("beat_id", "")) if beats.size() > 0 and beats[0] is Dictionary else ""
	var high_beat_id := str((beats[beats.size() - 1] as Dictionary).get("beat_id", "")) if not beats.is_empty() and beats[beats.size() - 1] is Dictionary else ""
	_expect(detailed_beat_ids.has(high_beat_id), "Bounded schedule prioritizes high-importance beat")
	_expect(detailed_beat_ids.has(first_normal_beat_id), "Bounded schedule fills remaining budget with earliest normal beat")
	var source_beat_ids := _beat_id_lookup(beats)
	for summarized_beat_id in summarized_beat_ids:
		_expect(source_beat_ids.has(summarized_beat_id), "Summarized beat still exists in source battle_result beats")


func _validate_deterministic_schedule() -> void:
	var first_result := _resolve_member_case("schedule_deterministic", 5, 5, 8, 32, "schedule-deterministic")
	var second_result := _resolve_member_case("schedule_deterministic", 5, 5, 8, 32, "schedule-deterministic")
	_expect(_schedule_signature(first_result) == _schedule_signature(second_result), "Schedule is deterministic for identical inputs")


func _validate_schedule_contract(result: Dictionary, label: String) -> void:
	var schedule := _schedule(result)
	_expect(not schedule.is_empty(), "%s emits combat_schedule" % label)
	_expect(bool(schedule.get("presentation_only", false)), "%s schedule is presentation-only" % label)
	_expect(str(schedule.get("strategy", "")) == "prioritize_important_then_earliest", "%s schedule uses approved priority strategy" % label)
	_expect(str(schedule.get("complexity", "")) == "O(B log B + E)", "%s schedule declares bounded non-frame complexity" % label)
	_expect(int(schedule.get("event_count", -1)) == _events(schedule).size(), "%s schedule event_count matches events" % label)
	_expect(int(schedule.get("source_beat_count", -1)) == _beats(result).size(), "%s schedule records source beat count" % label)
	_expect(int(schedule.get("event_count", 0)) <= int(schedule.get("max_detailed_event_count", 0)), "%s schedule is bounded by detailed event limit" % label)
	_validate_event_refs(result, label)


func _validate_event_refs(result: Dictionary, label: String) -> void:
	var beat_ids := _beat_id_lookup(_beats(result))
	var slots := _slots(result)
	for event in _events(_schedule(result)):
		if not (event is Dictionary):
			_failures.append("%s schedule event is not a Dictionary" % label)
			continue
		var event_record: Dictionary = event
		_expect(not str(event_record.get("event_id", "")).strip_edges().is_empty(), "%s event has event_id" % label)
		_expect(beat_ids.has(str(event_record.get("beat_id", ""))), "%s event references existing beat" % label)
		_expect(slots.has(str(event_record.get("attacker_slot_id", ""))), "%s event attacker_slot_id references existing slot" % label)
		_expect(slots.has(str(event_record.get("defender_slot_id", ""))), "%s event defender_slot_id references existing slot" % label)
		_expect(float(event_record.get("start_time", -1.0)) >= 0.0, "%s event has non-negative start_time" % label)
		_expect(float(event_record.get("duration", 0.0)) > 0.0, "%s event has positive duration" % label)
		_expect(bool(event_record.get("presentation_only", false)), "%s event is presentation-only" % label)


func _resolve_member_case(label: String, side_a_count: int, side_b_count: int, rounds: int, detailed_beat_limit: int, seed: String) -> Dictionary:
	var encounter_id := "encounter:validation:%s" % label
	return BATTLE_SIM_SCRIPT.resolve_encounter(
		{"encounter_id": encounter_id, "created_tick": 1, "location": Vector3.ZERO, "squad_ids": ["%s.a" % label, "%s.b" % label]},
		_squad_record("%s.a" % label, _member_records("%s.a" % label, side_a_count)),
		_squad_record("%s.b" % label, _member_records("%s.b" % label, side_b_count)),
		{"encounter_id": encounter_id, "current_tick": CURRENT_TICK, "rounds": rounds, "detailed_beat_limit": detailed_beat_limit, "seed": seed}
	)


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
		records.append({
			"actor_id": "%s.%03d" % [prefix, index],
			"stable_id": "%s.%03d" % [prefix, index],
			"member_id": "%s.%03d" % [prefix, index],
			"member_name": "%s.%03d" % [prefix, index],
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


func _schedule(result: Dictionary) -> Dictionary:
	return result.get("combat_schedule", {}) if result.get("combat_schedule", {}) is Dictionary else {}


func _events(schedule: Dictionary) -> Array:
	return schedule.get("events", []) if schedule.get("events", []) is Array else []


func _beats(result: Dictionary) -> Array:
	return result.get("beats", []) if result.get("beats", []) is Array else []


func _slots(result: Dictionary) -> Dictionary:
	return result.get("combat_slots", {}) if result.get("combat_slots", {}) is Dictionary else {}


func _events_for_beat(events: Array, beat_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if event is Dictionary and str((event as Dictionary).get("beat_id", "")) == beat_id:
			result.append(event)
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return float(first.get("start_time", 0.0)) < float(second.get("start_time", 0.0)))
	return result


func _event_types(events: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for event in events:
		result.append(str(event.get("event_type", "")))
	return result


func _beat_id_lookup(beats: Array) -> Dictionary:
	var result := {}
	for beat in beats:
		if beat is Dictionary:
			var beat_id := str((beat as Dictionary).get("beat_id", "")).strip_edges()
			if not beat_id.is_empty():
				result[beat_id] = true
	return result


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _schedule_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	for event in _events(_schedule(result)):
		if event is Dictionary:
			parts.append("%s|%s|%.2f|%.2f" % [
				str((event as Dictionary).get("event_id", "")),
				str((event as Dictionary).get("event_type", "")),
				float((event as Dictionary).get("start_time", 0.0)),
				float((event as Dictionary).get("duration", 0.0)),
			])
	parts.append(_join_strings(_string_array(_schedule(result).get("summarized_beat_ids", [])), ","))
	return _join_strings(parts, ";")


func _join_strings(parts: Array[String], delimiter: String) -> String:
	var result := ""
	for index in range(parts.size()):
		if index > 0:
			result += delimiter
		result += parts[index]
	return result


func _finish() -> void:
	if _failures.is_empty():
		print("COMBAT_SCHEDULE_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
