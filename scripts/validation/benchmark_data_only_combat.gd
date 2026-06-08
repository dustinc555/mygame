extends SceneTree

const BATTLE_SIM_SCRIPT := preload("res://scripts/sim/battle/battle_sim.gd")
const CURRENT_TICK := 104
const LIFE_STATE_ALIVE := 0
const WARMUP_RUNS := 2
const SAMPLE_RUNS := 10
const EVENTS_PER_DETAILED_BEAT := 4
const PHASE_KEYS := [
	"profile_generation_usec",
	"outcome_generation_usec",
	"casualty_generation_usec",
	"engagement_group_generation_usec",
	"combat_slot_generation_usec",
	"completion_resolution_usec",
	"combat_beat_generation_usec",
	"schedule_generation_usec",
	"result_assembly_usec",
	"total_internal_usec",
]
const BENCHMARK_CASES := [
	{"label": "1v1", "side_a_count": 1, "side_b_count": 1, "rounds": 24, "detailed_beat_limit": 64, "expected_group_count": 1, "expected_slot_count": 2},
	{"label": "5v5", "side_a_count": 5, "side_b_count": 5, "rounds": 24, "detailed_beat_limit": 64, "expected_group_count": 5, "expected_slot_count": 10},
	{"label": "50v50", "side_a_count": 50, "side_b_count": 50, "rounds": 50, "detailed_beat_limit": 64, "expected_group_count": 50, "expected_slot_count": 100},
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_benchmark")


func _run_benchmark() -> void:
	var reports: Array[Dictionary] = []
	for benchmark_case in BENCHMARK_CASES:
		reports.append(_benchmark_case(benchmark_case))
	for report in reports:
		_print_case_report(report)
	_finish()


func _benchmark_case(benchmark_case: Dictionary) -> Dictionary:
	var label := str(benchmark_case.get("label", ""))
	for warmup_index in range(WARMUP_RUNS):
		_resolve_case(benchmark_case, "warmup-%02d" % warmup_index)
	var deterministic_first := _resolve_case(benchmark_case, "deterministic")
	var deterministic_second := _resolve_case(benchmark_case, "deterministic")
	var deterministic := _result_signature(deterministic_first) == _result_signature(deterministic_second)
	_expect(deterministic, "%s data-only BattleSim result is deterministic for identical inputs" % label)
	_validate_no_live_refs(deterministic_first, label)
	var counts := _result_counts(deterministic_first)
	_validate_counts(benchmark_case, counts)
	var phase_sums := _empty_phase_totals()
	var total_resolve_usec := 0
	var result_bytes := 0
	var result_value_count := 0
	for sample_index in range(SAMPLE_RUNS):
		var payload := _case_payload(benchmark_case, "sample")
		var started_usec := Time.get_ticks_usec()
		var result := _resolve_payload(payload)
		total_resolve_usec += Time.get_ticks_usec() - started_usec
		_accumulate_phase_totals(phase_sums, _benchmark_metrics(result))
		if sample_index == SAMPLE_RUNS - 1:
			var clean_result := _result_without_benchmark_metrics(result)
			result_bytes = var_to_bytes(clean_result).size()
			result_value_count = _value_count(clean_result)
	return {
		"label": label,
		"samples": SAMPLE_RUNS,
		"deterministic": deterministic,
		"average_resolve_usec": float(total_resolve_usec) / maxf(float(SAMPLE_RUNS), 1.0),
		"average_phases": _average_phase_totals(phase_sums),
		"counts": counts,
		"result_bytes": result_bytes,
		"result_value_count": result_value_count,
	}


func _resolve_case(benchmark_case: Dictionary, seed_suffix: String) -> Dictionary:
	return _resolve_payload(_case_payload(benchmark_case, seed_suffix))


func _case_payload(benchmark_case: Dictionary, seed_suffix: String) -> Dictionary:
	var label := str(benchmark_case.get("label", ""))
	var safe_label := label.to_lower()
	var side_a_id := "benchmark.data_only.%s.a" % safe_label
	var side_b_id := "benchmark.data_only.%s.b" % safe_label
	var encounter_id := "encounter:benchmark:data_only:%s" % safe_label
	var encounter_record := {
		"encounter_id": encounter_id,
		"created_tick": 1,
		"location": Vector3.ZERO,
		"squad_ids": [side_a_id, side_b_id],
	}
	var config := {
		"encounter_id": encounter_id,
		"current_tick": CURRENT_TICK,
		"rounds": int(benchmark_case.get("rounds", 1)),
		"detailed_beat_limit": int(benchmark_case.get("detailed_beat_limit", 64)),
		"seed": "data-only-benchmark:%s:%s" % [label, seed_suffix],
		"collect_benchmark_metrics": true,
	}
	return {
		"encounter_record": encounter_record,
		"squad_a_record": _squad_record(side_a_id, _member_records(side_a_id, int(benchmark_case.get("side_a_count", 0)))),
		"squad_b_record": _squad_record(side_b_id, _member_records(side_b_id, int(benchmark_case.get("side_b_count", 0)))),
		"config": config,
	}


func _resolve_payload(payload: Dictionary) -> Dictionary:
	return BATTLE_SIM_SCRIPT.resolve_encounter(
		payload.get("encounter_record", {}) if payload.get("encounter_record", {}) is Dictionary else {},
		payload.get("squad_a_record", {}) if payload.get("squad_a_record", {}) is Dictionary else {},
		payload.get("squad_b_record", {}) if payload.get("squad_b_record", {}) is Dictionary else {},
		payload.get("config", {}) if payload.get("config", {}) is Dictionary else {}
	)


func _squad_record(squad_id: String, member_records: Array[Dictionary]) -> Dictionary:
	return {
		"squad_id": squad_id,
		"member_count": member_records.size(),
		"member_records": member_records,
		"member_records_are_canonical": true,
		"strength": float(member_records.size()) * 16.0,
		"base_strength": 10.0,
		"base_attack_damage": 12.0,
		"max_hp": 100.0,
		"combat_stance": 1,
		"morale": 1.0,
		"supplies": 100.0,
	}


func _member_records(prefix: String, count: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for index in range(1, count + 1):
		var member_id := "%s.%03d" % [prefix, index]
		var skill_offset := float((index - 1) % 5) * 0.25
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
			"base_attack_damage": 12.0 + skill_offset,
			"base_dodge_chance": 0.0,
			"base_block_chance": 0.0,
			"skill_levels": {
				"attribute.strength": 4.0 + skill_offset,
				"attribute.perception": 4.0,
				"attribute.dexterity": 4.0 + skill_offset,
				"attribute.toughness": 4.0,
				"attribute.endurance": 4.0,
				"combat.swords_one_handed": 5.0 + skill_offset,
				"combat.axes_one_handed": 3.0,
				"combat.daggers": 2.0,
				"combat.unarmed": 2.0,
				"combat.shields": 3.0,
			},
		})
	return records


func _validate_counts(benchmark_case: Dictionary, counts: Dictionary) -> void:
	var label := str(benchmark_case.get("label", ""))
	var expected_group_count := int(benchmark_case.get("expected_group_count", 0))
	var expected_slot_count := int(benchmark_case.get("expected_slot_count", 0))
	var expected_beat_count := int(benchmark_case.get("rounds", 0))
	var detailed_beat_count := mini(expected_beat_count, int(benchmark_case.get("detailed_beat_limit", 0)))
	_expect(int(counts.get("engagement_group_count", 0)) == expected_group_count, "%s emits expected engagement group count" % label)
	_expect(int(counts.get("combat_slot_count", 0)) == expected_slot_count, "%s emits expected combat slot count" % label)
	_expect(int(counts.get("beat_count", 0)) == expected_beat_count, "%s emits configured CombatBeat count" % label)
	_expect(int(counts.get("scheduled_event_count", 0)) == detailed_beat_count * EVENTS_PER_DETAILED_BEAT, "%s emits expected detailed schedule event count" % label)
	_expect(int(counts.get("summarized_beat_count", 0)) == maxi(0, expected_beat_count - detailed_beat_count), "%s emits expected summarized beat count" % label)


func _result_counts(result: Dictionary) -> Dictionary:
	var beats: Array = result.get("beats", []) if result.get("beats", []) is Array else []
	var groups: Array = result.get("engagement_groups", []) if result.get("engagement_groups", []) is Array else []
	var slots: Dictionary = result.get("combat_slots", {}) if result.get("combat_slots", {}) is Dictionary else {}
	var schedule: Dictionary = result.get("combat_schedule", {}) if result.get("combat_schedule", {}) is Dictionary else {}
	return {
		"beat_count": beats.size(),
		"engagement_group_count": groups.size(),
		"combat_slot_count": slots.size(),
		"scheduled_event_count": int(schedule.get("scheduled_event_count", 0)),
		"detailed_beat_count": int(schedule.get("detailed_beat_count", 0)),
		"summarized_beat_count": int(schedule.get("summarized_beat_count", 0)),
		"skipped_beat_count": int(schedule.get("skipped_beat_count", 0)),
	}


func _benchmark_metrics(result: Dictionary) -> Dictionary:
	return result.get("benchmark_metrics", {}) if result.get("benchmark_metrics", {}) is Dictionary else {}


func _empty_phase_totals() -> Dictionary:
	var totals := {}
	for phase_key in PHASE_KEYS:
		totals[phase_key] = 0
	return totals


func _accumulate_phase_totals(totals: Dictionary, metrics: Dictionary) -> void:
	for phase_key in PHASE_KEYS:
		totals[phase_key] = int(totals.get(phase_key, 0)) + int(metrics.get(phase_key, 0))


func _average_phase_totals(totals: Dictionary) -> Dictionary:
	var averages := {}
	for phase_key in PHASE_KEYS:
		averages[phase_key] = float(totals.get(phase_key, 0)) / maxf(float(SAMPLE_RUNS), 1.0)
	return averages


func _result_without_benchmark_metrics(result: Dictionary) -> Dictionary:
	var clean_result := result.duplicate(true)
	clean_result.erase("benchmark_metrics")
	return clean_result


func _result_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("outcome=%s" % str(result.get("outcome", "")))
	parts.append("winner=%s" % str(result.get("winner_squad_id", "")))
	parts.append("loser=%s" % str(result.get("loser_squad_id", "")))
	parts.append("rounds=%d" % int(result.get("rounds", 0)))
	parts.append("groups=%s" % _group_signature(result))
	parts.append("slots=%s" % _slot_signature(result))
	parts.append("beats=%s" % _beat_signature(result))
	parts.append("schedule=%s" % _schedule_signature(result))
	parts.append("casualties=%s" % _casualty_signature(result))
	return "|".join(parts)


func _group_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	var groups: Array = result.get("engagement_groups", []) if result.get("engagement_groups", []) is Array else []
	for group in groups:
		if group is Dictionary:
			var group_record: Dictionary = group
			parts.append("%s:%s:%s:%s:%s" % [
				str(group_record.get("engagement_group_id", "")),
				str(group_record.get("side_a_primary_id", "")),
				str(group_record.get("side_b_primary_id", "")),
				",".join(_string_array(group_record.get("side_a_member_ids", []))),
				",".join(_string_array(group_record.get("side_b_member_ids", []))),
			])
	return ";".join(parts)


func _slot_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	var slots: Dictionary = result.get("combat_slots", {}) if result.get("combat_slots", {}) is Dictionary else {}
	var slot_ids := _sorted_string_keys(slots)
	for slot_id in slot_ids:
		var slot: Dictionary = slots.get(slot_id, {}) if slots.get(slot_id, {}) is Dictionary else {}
		parts.append("%s:%s:%s:%s:%s:%s" % [
			slot_id,
			str(slot.get("occupant_id", "")),
			str(slot.get("engagement_group_id", "")),
			str(slot.get("formation_role", "")),
			_vector_signature(slot.get("world_position_hint", Vector3.ZERO)),
			str(slot.get("facing_target_slot_id", "")),
		])
	return ";".join(parts)


func _beat_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	var beats: Array = result.get("beats", []) if result.get("beats", []) is Array else []
	for beat in beats:
		if beat is Dictionary:
			var beat_record: Dictionary = beat
			parts.append("%s:%s:%s:%s:%s:%.3f" % [
				str(beat_record.get("beat_id", "")),
				str(beat_record.get("engagement_group_id", "")),
				str(beat_record.get("attacker_id", "")),
				str(beat_record.get("defender_id", "")),
				str(beat_record.get("result", "")),
				float(beat_record.get("damage", 0.0)),
			])
	return ";".join(parts)


func _schedule_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	var schedule: Dictionary = result.get("combat_schedule", {}) if result.get("combat_schedule", {}) is Dictionary else {}
	var events: Array = schedule.get("events", []) if schedule.get("events", []) is Array else []
	for event in events:
		if event is Dictionary:
			var event_record: Dictionary = event
			parts.append("%s:%s:%s:%.3f:%.3f" % [
				str(event_record.get("event_id", "")),
				str(event_record.get("beat_id", "")),
				str(event_record.get("event_type", "")),
				float(event_record.get("start_time", 0.0)),
				float(event_record.get("duration", 0.0)),
			])
	parts.append("summarized=%s" % ",".join(_string_array(schedule.get("summarized_beat_ids", []))))
	return ";".join(parts)


func _casualty_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	var casualties: Dictionary = result.get("member_casualties", {}) if result.get("member_casualties", {}) is Dictionary else {}
	for squad_id in _sorted_string_keys(casualties):
		var casualty_ids: Array[String] = []
		var records: Array = casualties.get(squad_id, []) if casualties.get(squad_id, []) is Array else []
		for record in records:
			if record is Dictionary:
				casualty_ids.append(str((record as Dictionary).get("member_id", "")))
		casualty_ids.sort()
		parts.append("%s:%s" % [squad_id, ",".join(casualty_ids)])
	return ";".join(parts)


func _value_count(value) -> int:
	var count := 1
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			count += _value_count(key)
			count += _value_count((value as Dictionary).get(key))
	elif value is Array:
		for entry in value:
			count += _value_count(entry)
	return count


func _validate_no_live_refs(value, label: String, path := "battle_result") -> void:
	if value is Node:
		_failures.append("%s data-only benchmark stores live Node at %s" % [label, path])
		return
	if value is NodePath:
		_failures.append("%s data-only benchmark stores NodePath at %s" % [label, path])
		return
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			_validate_no_live_refs((value as Dictionary).get(key), label, "%s.%s" % [path, str(key)])
	elif value is Array:
		for index in range((value as Array).size()):
			_validate_no_live_refs((value as Array)[index], label, "%s[%d]" % [path, index])


func _sorted_string_keys(dictionary: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key in dictionary.keys():
		keys.append(str(key))
	keys.sort()
	return keys


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _vector_signature(value) -> String:
	if value is Vector3:
		return "%.2f,%.2f,%.2f" % [value.x, value.y, value.z]
	return "0.00,0.00,0.00"


func _print_case_report(report: Dictionary) -> void:
	var counts: Dictionary = report.get("counts", {}) if report.get("counts", {}) is Dictionary else {}
	var phases: Dictionary = report.get("average_phases", {}) if report.get("average_phases", {}) is Dictionary else {}
	print("DATA_ONLY_COMBAT_BENCHMARK %s samples=%d deterministic=%s average_resolve_usec=%.2f profile_usec=%.2f outcome_usec=%.2f casualty_usec=%.2f engagement_group_usec=%.2f combat_slot_usec=%.2f combat_beat_usec=%.2f schedule_usec=%.2f total_internal_usec=%.2f beats=%d groups=%d slots=%d scheduled_events=%d summarized_beats=%d result_bytes=%d result_values=%d" % [
		str(report.get("label", "")),
		int(report.get("samples", 0)),
		str(report.get("deterministic", false)),
		float(report.get("average_resolve_usec", 0.0)),
		float(phases.get("profile_generation_usec", 0.0)),
		float(phases.get("outcome_generation_usec", 0.0)),
		float(phases.get("casualty_generation_usec", 0.0)),
		float(phases.get("engagement_group_generation_usec", 0.0)),
		float(phases.get("combat_slot_generation_usec", 0.0)),
		float(phases.get("combat_beat_generation_usec", 0.0)),
		float(phases.get("schedule_generation_usec", 0.0)),
		float(phases.get("total_internal_usec", 0.0)),
		int(counts.get("beat_count", 0)),
		int(counts.get("engagement_group_count", 0)),
		int(counts.get("combat_slot_count", 0)),
		int(counts.get("scheduled_event_count", 0)),
		int(counts.get("summarized_beat_count", 0)),
		int(report.get("result_bytes", 0)),
		int(report.get("result_value_count", 0)),
	])


func _finish() -> void:
	if _failures.is_empty():
		print("DATA_ONLY_COMBAT_BENCHMARK_OK cases=%d samples=%d" % [BENCHMARK_CASES.size(), SAMPLE_RUNS])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("DATA_ONLY_COMBAT_BENCHMARK_FAILED cases=%d samples=%d" % [BENCHMARK_CASES.size(), SAMPLE_RUNS])
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
