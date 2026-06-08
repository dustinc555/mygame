extends SceneTree

const BATTLE_SIM_SCRIPT := preload("res://scripts/sim/battle/battle_sim.gd")
const CURRENT_TICK := 89
const LIFE_STATE_ALIVE := 0
const LIFE_STATE_DEAD := 3

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_validate_1v1_slots()
	_validate_1v3_slots()
	_validate_5v5_slots()
	_validate_50v50_slots()
	_validate_squad_fallback_slots()
	_finish()


func _validate_1v1_slots() -> void:
	var result := _resolve_member_case("slot_one_v_one", 1, 1)
	_validate_slot_contract(result, _member_ids("slot_one_v_one.a", 1) + _member_ids("slot_one_v_one.b", 1), [], "1v1")
	var side_a_slot := _slot_for_occupant(result, "slot_one_v_one.a.001")
	var side_b_slot := _slot_for_occupant(result, "slot_one_v_one.b.001")
	_expect(_slot_local_offset(side_a_slot).x < 0.0, "1v1 side A slot is left of center")
	_expect(_slot_local_offset(side_b_slot).x > 0.0, "1v1 side B slot is right of center")
	_expect(str(side_a_slot.get("facing_target_slot_id", "")) == str(side_b_slot.get("slot_id", "")), "1v1 side A faces side B")
	_expect(str(side_b_slot.get("facing_target_slot_id", "")) == str(side_a_slot.get("slot_id", "")), "1v1 side B faces side A")


func _validate_1v3_slots() -> void:
	var result := _resolve_member_case("slot_one_v_three", 1, 3)
	_validate_slot_contract(result, _member_ids("slot_one_v_three.a", 1) + _member_ids("slot_one_v_three.b", 3), [], "1v3")
	var groups := _groups(result)
	_expect(groups.size() == 1, "1v3 has one engagement cluster")
	if groups.size() == 1 and groups[0] is Dictionary:
		var slot_ids := _string_array((groups[0] as Dictionary).get("combat_slot_ids", []))
		_expect(slot_ids.size() == 4, "1v3 group references four slots")
		var offset_signatures := {}
		var side_b_support_slots := 0
		for slot_id in slot_ids:
			var slot: Dictionary = _slots(result).get(slot_id, {})
			var offset := _slot_local_offset(slot)
			offset_signatures[_vector_signature(offset)] = true
			if str(slot.get("side", "")) == "b" and absf(offset.z) > 0.5:
				side_b_support_slots += 1
		_expect(offset_signatures.size() == 4, "1v3 slot offsets do not overlap")
		_expect(side_b_support_slots >= 2, "1v3 side B support slots surround on z offsets")


func _validate_5v5_slots() -> void:
	var result := _resolve_member_case("slot_five_v_five", 5, 5)
	_validate_slot_contract(result, _member_ids("slot_five_v_five.a", 5) + _member_ids("slot_five_v_five.b", 5), [], "5v5")
	_expect(_slots(result).size() == 10, "5v5 emits ten member slots")
	var group_centers := {}
	for group in _groups(result):
		if group is Dictionary:
			var slot_ids := _string_array((group as Dictionary).get("combat_slot_ids", []))
			_expect(slot_ids.size() == 2, "5v5 each duel group references two slots")
			if (group as Dictionary).get("group_center", null) is Vector3:
				group_centers[_vector_signature((group as Dictionary).get("group_center"))] = true
	_expect(group_centers.size() == 5, "5v5 groups have stable distinct cluster centers")


func _validate_50v50_slots() -> void:
	var excluded_ids := ["slot_fifty_v_fifty.a.dead.001", "slot_fifty_v_fifty.b.dead.001"]
	var first_result := _resolve_member_case("slot_fifty_v_fifty", 50, 50, 1, 1, "slot-50v50-first")
	var second_result := _resolve_member_case("slot_fifty_v_fifty", 50, 50, 1, 1, "slot-50v50-second")
	_validate_slot_contract(first_result, _member_ids("slot_fifty_v_fifty.a", 50) + _member_ids("slot_fifty_v_fifty.b", 50), excluded_ids, "50v50")
	_expect(_slots(first_result).size() == 100, "50v50 emits one slot per living participant")
	_expect(_slot_signature(first_result) == _slot_signature(second_result), "50v50 slot assignment is deterministic independent of BattleSim seed")
	var summary: Dictionary = first_result.get("combat_slotting", {}) if first_result.get("combat_slotting", {}) is Dictionary else {}
	_expect(str(summary.get("complexity", "")) == "O(G + S) assignment", "50v50 slotting declares non-quadratic assignment")


func _validate_squad_fallback_slots() -> void:
	var encounter_id := "encounter:validation:slot_fallback"
	var result: Dictionary = BATTLE_SIM_SCRIPT.resolve_encounter(
		{"encounter_id": encounter_id, "created_tick": 1, "squad_ids": ["slot.fallback.a", "slot.fallback.b"]},
		_squad_fallback_record("slot.fallback.a", 12),
		_squad_fallback_record("slot.fallback.b", 8),
		{"encounter_id": encounter_id, "current_tick": CURRENT_TICK, "rounds": 2, "seed": "slot-fallback"}
	)
	_validate_slot_contract(result, ["slot.fallback.a", "slot.fallback.b"], [], "Fallback")
	_expect(_slots(result).size() == 2, "Fallback emits two squad proxy slots")
	for slot in _slots(result).values():
		if slot is Dictionary:
			_expect(str((slot as Dictionary).get("occupant_kind", "")) == "squad_proxy", "Fallback slot uses squad_proxy occupant kind")
			_expect(str((slot as Dictionary).get("member_id", "")).is_empty(), "Fallback slot does not invent member ID")


func _validate_slot_contract(result: Dictionary, expected_occupant_ids: Array[String], excluded_ids: Array, label: String) -> void:
	_validate_slotting_summary(result, label)
	var slots := _slots(result)
	var expected_ids := {}
	for id in expected_occupant_ids:
		expected_ids[id] = true
	var occupied_ids := {}
	for slot_id_value in slots.keys():
		var slot_id := str(slot_id_value)
		var slot = slots[slot_id_value]
		if not (slot is Dictionary):
			_failures.append("%s slot is not a Dictionary: %s" % [label, slot_id])
			continue
		var slot_record: Dictionary = slot
		_validate_slot_record(slot_id, slot_record, expected_ids, occupied_ids, label)
	_expect(occupied_ids.size() == expected_ids.size(), "%s emits one slot for every expected occupant" % label)
	for expected_id in expected_ids.keys():
		_expect(occupied_ids.has(expected_id), "%s does not lose slot occupant %s" % [label, str(expected_id)])
	for excluded_id in excluded_ids:
		_expect(not occupied_ids.has(str(excluded_id)), "%s excludes non-living occupant %s" % [label, str(excluded_id)])
	_validate_group_slot_refs(result, label)
	_validate_beat_slot_refs(result, label)


func _validate_slot_record(slot_id: String, slot_record: Dictionary, expected_ids: Dictionary, occupied_ids: Dictionary, label: String) -> void:
	_expect(str(slot_record.get("slot_id", "")) == slot_id, "%s slot id matches dictionary key" % label)
	_expect(str(slot_record.get("encounter_id", "")).strip_edges() != "", "%s slot has encounter_id" % label)
	_expect(str(slot_record.get("engagement_group_id", "")).strip_edges() != "", "%s slot has engagement_group_id" % label)
	_expect(["member", "squad_proxy"].has(str(slot_record.get("occupant_kind", ""))), "%s slot has valid occupant kind" % label)
	var occupant_id := str(slot_record.get("occupant_id", "")).strip_edges()
	_expect(expected_ids.has(occupant_id), "%s slot occupant is expected: %s" % [label, occupant_id])
	_expect(not occupied_ids.has(occupant_id), "%s does not duplicate slot occupant: %s" % [label, occupant_id])
	occupied_ids[occupant_id] = true
	_expect(not str(slot_record.get("squad_id", "")).strip_edges().is_empty(), "%s slot has squad_id" % label)
	_expect(["a", "b"].has(str(slot_record.get("side", ""))), "%s slot has side" % label)
	_expect(not str(slot_record.get("formation_role", "")).strip_edges().is_empty(), "%s slot has formation role" % label)
	_expect(bool(slot_record.get("presentation_only", false)), "%s slot is marked presentation_only" % label)
	_expect(slot_record.get("group_center", null) is Vector3, "%s slot has group_center" % label)
	_expect(slot_record.get("local_offset", null) is Vector3, "%s slot has local_offset" % label)
	_expect(slot_record.get("world_position_hint", null) is Vector3, "%s slot has world_position_hint" % label)
	if slot_record.get("group_center", null) is Vector3 and slot_record.get("local_offset", null) is Vector3 and slot_record.get("world_position_hint", null) is Vector3:
		var expected_world_position: Vector3 = slot_record.get("group_center") + slot_record.get("local_offset")
		var world_position: Vector3 = slot_record.get("world_position_hint")
		_expect(world_position.is_equal_approx(expected_world_position), "%s world_position_hint derives from group_center + local_offset" % label)


func _validate_group_slot_refs(result: Dictionary, label: String) -> void:
	var slots := _slots(result)
	for group in _groups(result):
		if not (group is Dictionary):
			continue
		var group_record: Dictionary = group
		var group_id := str(group_record.get("engagement_group_id", "")).strip_edges()
		var slot_ids := _string_array(group_record.get("combat_slot_ids", []))
		_expect(not slot_ids.is_empty(), "%s group references combat slots" % label)
		for slot_id in slot_ids:
			_expect(slots.has(slot_id), "%s group slot id exists in top-level combat_slots" % label)
			if slots.has(slot_id) and slots[slot_id] is Dictionary:
				_expect(str((slots[slot_id] as Dictionary).get("engagement_group_id", "")) == group_id, "%s slot references owning group" % label)


func _validate_beat_slot_refs(result: Dictionary, label: String) -> void:
	var slots := _slots(result)
	for beat in _beats(result):
		if not (beat is Dictionary):
			continue
		var beat_record: Dictionary = beat
		var attacker_slot_id := str(beat_record.get("attacker_slot_id", "")).strip_edges()
		var defender_slot_id := str(beat_record.get("defender_slot_id", "")).strip_edges()
		_expect(slots.has(attacker_slot_id), "%s beat attacker_slot_id exists" % label)
		_expect(slots.has(defender_slot_id), "%s beat defender_slot_id exists" % label)
		if slots.has(attacker_slot_id) and slots[attacker_slot_id] is Dictionary:
			_expect(str((slots[attacker_slot_id] as Dictionary).get("occupant_id", "")) == str(beat_record.get("attacker_id", "")), "%s attacker slot occupant matches beat attacker" % label)
		if slots.has(defender_slot_id) and slots[defender_slot_id] is Dictionary:
			_expect(str((slots[defender_slot_id] as Dictionary).get("occupant_id", "")) == str(beat_record.get("defender_id", "")), "%s defender slot occupant matches beat defender" % label)


func _validate_slotting_summary(result: Dictionary, label: String) -> void:
	var summary: Dictionary = result.get("combat_slotting", {}) if result.get("combat_slotting", {}) is Dictionary else {}
	_expect(str(summary.get("strategy", "")) == "deterministic_group_local_offsets", "%s slotting strategy is deterministic local offsets" % label)
	_expect(str(summary.get("complexity", "")) == "O(G + S) assignment", "%s slotting complexity is non-quadratic" % label)
	_expect(bool(summary.get("presentation_only", false)), "%s slotting is presentation-only" % label)


func _resolve_member_case(label: String, side_a_count: int, side_b_count: int, dead_a_count := 0, dead_b_count := 0, seed := "") -> Dictionary:
	var encounter_id := "encounter:validation:%s" % label
	return BATTLE_SIM_SCRIPT.resolve_encounter(
		{"encounter_id": encounter_id, "created_tick": 1, "location": Vector3(10.0, 0.0, -5.0), "squad_ids": ["%s.a" % label, "%s.b" % label]},
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


func _slots(result: Dictionary) -> Dictionary:
	return result.get("combat_slots", {}) if result.get("combat_slots", {}) is Dictionary else {}


func _groups(result: Dictionary) -> Array:
	return result.get("engagement_groups", []) if result.get("engagement_groups", []) is Array else []


func _beats(result: Dictionary) -> Array:
	return result.get("beats", []) if result.get("beats", []) is Array else []


func _slot_for_occupant(result: Dictionary, occupant_id: String) -> Dictionary:
	for slot in _slots(result).values():
		if slot is Dictionary and str((slot as Dictionary).get("occupant_id", "")) == occupant_id:
			return slot
	return {}


func _slot_local_offset(slot: Dictionary) -> Vector3:
	return slot.get("local_offset", Vector3.ZERO) if slot.get("local_offset", Vector3.ZERO) is Vector3 else Vector3.ZERO


func _slot_signature(result: Dictionary) -> String:
	var slots := _slots(result)
	var slot_ids: Array[String] = []
	for slot_id in slots.keys():
		slot_ids.append(str(slot_id))
	slot_ids.sort()
	var parts: Array[String] = []
	for slot_id in slot_ids:
		var slot: Dictionary = slots.get(slot_id, {}) if slots.get(slot_id, {}) is Dictionary else {}
		parts.append("%s|%s|%s|%s|%s" % [
			slot_id,
			str(slot.get("occupant_id", "")),
			str(slot.get("engagement_group_id", "")),
			_vector_signature(slot.get("group_center", Vector3.ZERO)),
			_vector_signature(slot.get("local_offset", Vector3.ZERO)),
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


func _vector_signature(value) -> String:
	if not (value is Vector3):
		return "<not-vector>"
	return "%.2f,%.2f,%.2f" % [value.x, value.y, value.z]


func _join_strings(parts: Array[String], delimiter: String) -> String:
	var result := ""
	for index in range(parts.size()):
		if index > 0:
			result += delimiter
		result += parts[index]
	return result


func _finish() -> void:
	if _failures.is_empty():
		print("COMBAT_SLOTS_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
