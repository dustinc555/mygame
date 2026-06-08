extends SceneTree

const BATTLE_SIM_SCRIPT := preload("res://scripts/sim/battle/battle_sim.gd")
const COMBAT_BEAT_LOG_VIEWER_SCRIPT := preload("res://scripts/ui/world_map_combat_beat_log_viewer.gd")
const ENCOUNTER_ID := "encounter:validation:combat_beat_contract"
const CURRENT_TICK := 42
const MEMBER_LIFE_STATE_ALIVE := 0

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	_validate_member_level_beats()
	_validate_squad_fallback_beats()
	_validate_legacy_beat_log_graceful_path()
	_finish()


func _validate_member_level_beats() -> void:
	var encounter_record := {
		"encounter_id": ENCOUNTER_ID,
		"created_tick": 7,
		"squad_ids": ["validation.alpha", "validation.beta"],
	}
	var result: Dictionary = BATTLE_SIM_SCRIPT.resolve_encounter(
		encounter_record,
		_squad_record("validation.alpha", [_member_record("validation.alpha.01"), _member_record("validation.alpha.02")]),
		_squad_record("validation.beta", [_member_record("validation.beta.01"), _member_record("validation.beta.02")]),
		{
			"encounter_id": ENCOUNTER_ID,
			"current_tick": CURRENT_TICK,
			"rounds": 3,
			"seed": "combat-beat-contract-member",
		}
	)
	_validate_beats(result, 3, true, "Member-level")


func _validate_squad_fallback_beats() -> void:
	var fallback_encounter_id := "%s:fallback" % ENCOUNTER_ID
	var encounter_record := {
		"encounter_id": fallback_encounter_id,
		"created_tick": 11,
		"squad_ids": ["fallback.alpha", "fallback.beta"],
	}
	var result: Dictionary = BATTLE_SIM_SCRIPT.resolve_encounter(
		encounter_record,
		_squad_fallback_record("fallback.alpha", 4),
		_squad_fallback_record("fallback.beta", 4),
		{
			"encounter_id": fallback_encounter_id,
			"current_tick": CURRENT_TICK,
			"rounds": 2,
			"seed": "combat-beat-contract-fallback",
		}
	)
	_validate_beats(result, 2, false, "Squad-fallback")


func _validate_beats(result: Dictionary, expected_count: int, expects_member_ids: bool, label: String) -> void:
	var beats: Array = result.get("beats", []) if result.get("beats", []) is Array else []
	_expect(beats.size() == expected_count, "%s BattleSim emits expected beat count" % label)
	for index in range(beats.size()):
		var beat: Dictionary = beats[index] if beats[index] is Dictionary else {}
		var beat_index := index + 1
		_validate_required_beat_fields(beat, beat_index, label)
		_validate_beat_member_fields(beat, expects_member_ids, label)


func _validate_required_beat_fields(beat: Dictionary, beat_index: int, label: String) -> void:
	var encounter_id := str(beat.get("encounter_id", "")).strip_edges()
	_expect(not encounter_id.is_empty(), "%s beat has encounter_id" % label)
	_expect(int(beat.get("beat_index", 0)) == beat_index, "%s beat_index is stable and ordered" % label)
	_expect(str(beat.get("beat_id", "")) == "%s:beat:%03d" % [encounter_id, beat_index], "%s beat_id is stable" % label)
	_expect(str(beat.get("engagement_group_id", "")) == "%s:group:main" % encounter_id, "%s beat has #87 fallback engagement group" % label)
	_expect(int(beat.get("tick", -1)) == CURRENT_TICK, "%s beat keeps source tick" % label)
	_expect(int(beat.get("presentation_tick", -1)) == CURRENT_TICK + beat_index - 1, "%s beat has stable presentation_tick" % label)
	_expect(int(beat.get("round", 0)) > 0, "%s beat has round" % label)
	_expect(not str(beat.get("attacker_squad_id", "")).strip_edges().is_empty(), "%s beat has attacker_squad_id" % label)
	_expect(not str(beat.get("defender_squad_id", "")).strip_edges().is_empty(), "%s beat has defender_squad_id" % label)
	_expect(not str(beat.get("attacker_id", "")).strip_edges().is_empty(), "%s beat has attacker_id" % label)
	_expect(not str(beat.get("defender_id", "")).strip_edges().is_empty(), "%s beat has defender_id" % label)
	_expect(not str(beat.get("action", "")).strip_edges().is_empty(), "%s beat has action" % label)
	_expect(not str(beat.get("result", "")).strip_edges().is_empty(), "%s beat has result" % label)
	_expect(float(beat.get("damage", -1.0)) >= 0.0, "%s beat has damage" % label)
	_expect(not str(beat.get("importance", "")).strip_edges().is_empty(), "%s beat has importance" % label)
	_expect(not str(beat.get("summary", "")).strip_edges().is_empty(), "%s beat has summary" % label)


func _validate_beat_member_fields(beat: Dictionary, expects_member_ids: bool, label: String) -> void:
	_expect(beat.has("attacker_member_id"), "%s beat includes attacker_member_id field" % label)
	_expect(beat.has("defender_member_id"), "%s beat includes defender_member_id field" % label)
	var attacker_member_id := str(beat.get("attacker_member_id", "")).strip_edges()
	var defender_member_id := str(beat.get("defender_member_id", "")).strip_edges()
	if expects_member_ids:
		_expect(not attacker_member_id.is_empty(), "%s beat has attacker member ID when member data exists" % label)
		_expect(not defender_member_id.is_empty(), "%s beat has defender member ID when member data exists" % label)
		_expect(str(beat.get("attacker_id", "")) == attacker_member_id, "%s attacker_id uses member ID when available" % label)
		_expect(str(beat.get("defender_id", "")) == defender_member_id, "%s defender_id uses member ID when available" % label)
	else:
		_expect(attacker_member_id.is_empty(), "%s beat leaves attacker_member_id empty for squad fallback" % label)
		_expect(defender_member_id.is_empty(), "%s beat leaves defender_member_id empty for squad fallback" % label)
		_expect(str(beat.get("attacker_id", "")) == str(beat.get("attacker_squad_id", "")), "%s attacker_id falls back to squad ID" % label)
		_expect(str(beat.get("defender_id", "")) == str(beat.get("defender_squad_id", "")), "%s defender_id falls back to squad ID" % label)


func _validate_legacy_beat_log_graceful_path() -> void:
	var viewer := COMBAT_BEAT_LOG_VIEWER_SCRIPT.new() as Node
	var text := str(viewer.call("_beat_text", {}))
	_expect(not text.is_empty(), "Legacy empty beat renders fallback log text")
	viewer.free()


func _squad_record(squad_id: String, members: Array[Dictionary]) -> Dictionary:
	return {
		"squad_id": squad_id,
		"member_count": members.size(),
		"member_records": members,
		"member_records_are_canonical": true,
		"strength": 40.0,
		"base_strength": 10.0,
		"base_attack_damage": 14.0,
		"max_hp": 100.0,
		"combat_stance": 1,
		"morale": 1.0,
		"supplies": 20.0,
	}


func _squad_fallback_record(squad_id: String, member_count: int) -> Dictionary:
	return {
		"squad_id": squad_id,
		"member_count": member_count,
		"strength": 50.0,
		"base_strength": 10.0,
		"base_attack_damage": 12.0,
		"max_hp": 100.0,
		"combat_stance": 1,
		"morale": 1.0,
		"supplies": 20.0,
	}


func _member_record(member_id: String) -> Dictionary:
	return {
		"actor_id": member_id,
		"stable_id": member_id,
		"member_id": member_id,
		"member_name": member_id,
		"life_state": MEMBER_LIFE_STATE_ALIVE,
		"hp": 100.0,
		"max_hp": 100.0,
		"blood": 5.0,
		"max_blood": 5.0,
		"base_attack_damage": 15.0,
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


func _finish() -> void:
	if _failures.is_empty():
		print("COMBAT_BEAT_CONTRACT_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
