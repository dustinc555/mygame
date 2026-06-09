extends SceneTree

const BATTLE_SIM_SCRIPT := preload("res://scripts/sim/battle/battle_sim.gd")
const CURRENT_TICK := 88
const MAX_GROUP_SIZE := 4
const LIFE_STATE_ALIVE := 0
const LIFE_STATE_DEAD := 3

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_validate_1v1_groups()
	_validate_1v3_groups()
	_validate_5v5_groups()
	_validate_50v50_groups()
	_validate_squad_fallback_groups()
	_finish()


func _validate_1v1_groups() -> void:
	var result := _resolve_member_case("one_v_one", 1, 1)
	_validate_group_contract(result, _member_ids("one_v_one.a", 1), _member_ids("one_v_one.b", 1), [], "1v1")
	_expect(_groups(result).size() == 1, "1v1 creates one engagement group")


func _validate_1v3_groups() -> void:
	var result := _resolve_member_case("one_v_three", 1, 3)
	_validate_group_contract(result, _member_ids("one_v_three.a", 1), _member_ids("one_v_three.b", 3), [], "1v3")
	var groups := _groups(result)
	_expect(groups.size() == 1, "1v3 creates one bounded group")
	if groups.size() == 1 and groups[0] is Dictionary:
		var group: Dictionary = groups[0]
		_expect(_string_array(group.get("side_a_member_ids", [])).size() == 1, "1v3 group has one side A member")
		_expect(_string_array(group.get("side_b_member_ids", [])).size() == 3, "1v3 group has three side B members")
		_expect(_string_array(group.get("support_member_ids", [])).size() == 2, "1v3 extras are classified as support")


func _validate_5v5_groups() -> void:
	var result := _resolve_member_case("five_v_five", 5, 5)
	_validate_group_contract(result, _member_ids("five_v_five.a", 5), _member_ids("five_v_five.b", 5), [], "5v5")
	var groups := _groups(result)
	_expect(groups.size() == 5, "5v5 creates five duel groups")
	for group in groups:
		if group is Dictionary:
			_expect(_group_size(group) == 2, "5v5 group size is two")


func _validate_50v50_groups() -> void:
	var excluded_ids := ["fifty_v_fifty.a.dead.001", "fifty_v_fifty.b.dead.001"]
	var first_result := _resolve_member_case("fifty_v_fifty", 50, 50, 1, 1, "50v50-first")
	var second_result := _resolve_member_case("fifty_v_fifty", 50, 50, 1, 1, "50v50-second")
	_validate_group_contract(first_result, _member_ids("fifty_v_fifty.a", 50), _member_ids("fifty_v_fifty.b", 50), excluded_ids, "50v50")
	_expect(_group_signature(first_result) == _group_signature(second_result), "50v50 grouping is deterministic independent of BattleSim seed")
	_expect(_groups(first_result).size() == 50, "50v50 creates one bounded duel group per pair")


func _validate_squad_fallback_groups() -> void:
	var encounter_id := "encounter:validation:fallback_groups"
	var result: Dictionary = BATTLE_SIM_SCRIPT.resolve_encounter(
		{"encounter_id": encounter_id, "created_tick": 1, "squad_ids": ["fallback.a", "fallback.b"]},
		_squad_fallback_record("fallback.a", 12),
		_squad_fallback_record("fallback.b", 8),
		{"encounter_id": encounter_id, "current_tick": CURRENT_TICK, "rounds": 2, "seed": "fallback-groups"}
	)
	var groups := _groups(result)
	_expect(groups.size() == 1, "Fallback combat emits one engagement group")
	if groups.size() == 1 and groups[0] is Dictionary:
		var group: Dictionary = groups[0]
		_expect(bool(group.get("uses_squad_fallback", false)), "Fallback group is marked as squad fallback")
		_expect(str(group.get("side_a_primary_id", "")) == "fallback.a", "Fallback group side A primary is squad ID")
		_expect(str(group.get("side_b_primary_id", "")) == "fallback.b", "Fallback group side B primary is squad ID")
		_expect(_group_size(group) == 0, "Fallback group does not invent member IDs")
	_validate_beat_group_refs(result, "Fallback")
	for beat in _beats(result):
		if beat is Dictionary:
			_expect(str((beat as Dictionary).get("attacker_member_id", "")).is_empty(), "Fallback beat keeps attacker_member_id empty")
			_expect(str((beat as Dictionary).get("defender_member_id", "")).is_empty(), "Fallback beat keeps defender_member_id empty")


func _validate_group_contract(result: Dictionary, expected_side_a_ids: Array[String], expected_side_b_ids: Array[String], excluded_ids: Array, label: String) -> void:
	_validate_grouping_summary(result, label)
	var groups := _groups(result)
	_expect(not groups.is_empty(), "%s emits engagement groups" % label)
	var assigned_ids := {}
	var expected_ids := {}
	for id in expected_side_a_ids:
		expected_ids[id] = true
	for id in expected_side_b_ids:
		expected_ids[id] = true
	for group in groups:
		if not (group is Dictionary):
			_failures.append("%s group entry is not a Dictionary" % label)
			continue
		var group_record: Dictionary = group
		var group_id := str(group_record.get("engagement_group_id", "")).strip_edges()
		_expect(not group_id.is_empty(), "%s group has stable engagement_group_id" % label)
		_expect(str(group_record.get("encounter_id", "")).strip_edges() != "", "%s group has encounter_id" % label)
		_expect(int(group_record.get("max_group_size", 0)) == MAX_GROUP_SIZE, "%s group records max size" % label)
		_expect(_group_size(group_record) <= MAX_GROUP_SIZE, "%s group size is bounded" % label)
		var side_a_ids := _string_array(group_record.get("side_a_member_ids", []))
		var side_b_ids := _string_array(group_record.get("side_b_member_ids", []))
		if not side_a_ids.is_empty():
			_expect(side_a_ids.has(str(group_record.get("side_a_primary_id", ""))), "%s side A primary is assigned to side A" % label)
		if not side_b_ids.is_empty():
			_expect(side_b_ids.has(str(group_record.get("side_b_primary_id", ""))), "%s side B primary is assigned to side B" % label)
		_record_assigned_ids(assigned_ids, expected_ids, side_a_ids, label)
		_record_assigned_ids(assigned_ids, expected_ids, side_b_ids, label)
		_validate_classification_subset(group_record, assigned_ids, label)
	_expect(assigned_ids.size() == expected_ids.size(), "%s assigns every living participant exactly once" % label)
	for expected_id in expected_ids.keys():
		_expect(assigned_ids.has(expected_id), "%s does not lose living participant %s" % [label, str(expected_id)])
	for excluded_id in excluded_ids:
		_expect(not assigned_ids.has(str(excluded_id)), "%s excludes non-living participant %s" % [label, str(excluded_id)])
	_validate_beat_group_refs(result, label)


func _validate_grouping_summary(result: Dictionary, label: String) -> void:
	var summary: Dictionary = result.get("engagement_grouping", {}) if result.get("engagement_grouping", {}) is Dictionary else {}
	_expect(str(summary.get("strategy", "")) == "spatial_nearest_frontline", "%s grouping strategy is spatial nearest frontline" % label)
	_expect(str(summary.get("complexity", "")) == "O(N log N) spatial lane sort + O(N) assignment", "%s grouping declares non-quadratic complexity" % label)
	_expect(int(summary.get("max_group_size", 0)) == MAX_GROUP_SIZE, "%s grouping summary records max group size" % label)


func _record_assigned_ids(assigned_ids: Dictionary, expected_ids: Dictionary, ids: Array[String], label: String) -> void:
	for id in ids:
		_expect(expected_ids.has(id), "%s assigned unexpected participant %s" % [label, id])
		_expect(not assigned_ids.has(id), "%s does not duplicate participant %s across groups" % [label, id])
		assigned_ids[id] = true


func _validate_classification_subset(group_record: Dictionary, assigned_ids: Dictionary, label: String) -> void:
	var side_ids := {}
	for id in _string_array(group_record.get("side_a_member_ids", [])):
		side_ids[id] = true
	for id in _string_array(group_record.get("side_b_member_ids", [])):
		side_ids[id] = true
	for id in _string_array(group_record.get("support_member_ids", [])):
		_expect(side_ids.has(id) or assigned_ids.has(id), "%s support id belongs to an assigned member" % label)
	for id in _string_array(group_record.get("reserve_member_ids", [])):
		_expect(side_ids.has(id) or assigned_ids.has(id), "%s reserve id belongs to an assigned member" % label)


func _validate_beat_group_refs(result: Dictionary, label: String) -> void:
	var group_ids := {}
	for group in _groups(result):
		if group is Dictionary:
			var group_id := str((group as Dictionary).get("engagement_group_id", "")).strip_edges()
			if not group_id.is_empty():
				group_ids[group_id] = true
	_expect(not group_ids.is_empty(), "%s has engagement group ids" % label)
	for beat in _beats(result):
		if beat is Dictionary:
			var beat_group_id := str((beat as Dictionary).get("engagement_group_id", "")).strip_edges()
			_expect(not beat_group_id.is_empty(), "%s beat has engagement_group_id" % label)
			_expect(group_ids.has(beat_group_id), "%s beat group references existing group" % label)


func _resolve_member_case(label: String, side_a_count: int, side_b_count: int, dead_a_count := 0, dead_b_count := 0, seed := "") -> Dictionary:
	var encounter_id := "encounter:validation:%s" % label
	return BATTLE_SIM_SCRIPT.resolve_encounter(
		{"encounter_id": encounter_id, "created_tick": 1, "squad_ids": ["%s.a" % label, "%s.b" % label]},
		_squad_record("%s.a" % label, _member_records("%s.a" % label, side_a_count, dead_a_count)),
		_squad_record("%s.b" % label, _member_records("%s.b" % label, side_b_count, dead_b_count)),
		{"encounter_id": encounter_id, "current_tick": CURRENT_TICK, "rounds": 3, "seed": seed if not seed.is_empty() else label}
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


func _squad_fallback_record(squad_id: String, member_count: int) -> Dictionary:
	return {
		"squad_id": squad_id,
		"member_count": member_count,
		"strength": 80.0,
		"base_strength": 10.0,
		"base_attack_damage": 12.0,
		"max_hp": 100.0,
		"combat_stance": 1,
		"morale": 1.0,
		"supplies": 40.0,
	}


func _member_records(prefix: String, alive_count: int, dead_count: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for index in range(1, alive_count + 1):
		records.append(_member_record("%s.%03d" % [prefix, index], true))
	for index in range(1, dead_count + 1):
		records.append(_member_record("%s.dead.%03d" % [prefix, index], false))
	return records


func _member_record(member_id: String, alive: bool) -> Dictionary:
	return {
		"actor_id": member_id,
		"stable_id": member_id,
		"member_id": member_id,
		"member_name": member_id,
		"life_state": LIFE_STATE_ALIVE if alive else LIFE_STATE_DEAD,
		"hp": 100.0 if alive else 0.0,
		"max_hp": 100.0,
		"blood": 5.0 if alive else 0.0,
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
	}


func _member_ids(prefix: String, count: int) -> Array[String]:
	var ids: Array[String] = []
	for index in range(1, count + 1):
		ids.append("%s.%03d" % [prefix, index])
	return ids


func _groups(result: Dictionary) -> Array:
	return result.get("engagement_groups", []) if result.get("engagement_groups", []) is Array else []


func _beats(result: Dictionary) -> Array:
	return result.get("beats", []) if result.get("beats", []) is Array else []


func _group_size(group) -> int:
	if not (group is Dictionary):
		return 0
	return _string_array((group as Dictionary).get("side_a_member_ids", [])).size() + _string_array((group as Dictionary).get("side_b_member_ids", [])).size()


func _group_signature(result: Dictionary) -> String:
	var parts: Array[String] = []
	for group in _groups(result):
		if group is Dictionary:
			var record: Dictionary = group
			parts.append("%s|%s|%s|%s" % [
				str(record.get("engagement_group_id", "")),
				_join_strings(_string_array(record.get("side_a_member_ids", [])), ","),
				_join_strings(_string_array(record.get("side_b_member_ids", [])), ","),
				str(record.get("group_role", "")),
			])
	return _join_strings(parts, ";")


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
		print("COMBAT_ENGAGEMENT_GROUPS_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
