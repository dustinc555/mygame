extends RefCounted

class_name CombatEncounterStartRequest

const SIDE_SCRIPT := preload("res://scripts/sim/battle/combat_encounter_side.gd")

const INTENT_ATTACK := "attack"
const INTENT_DEFEND := "defend"
const INTENT_FLEE := "flee"
const INTENT_GUARD := "guard"
const INTENT_RAID := "raid"
const INTENT_DEBUG := "debug"
const VALID_INITIAL_INTENTS := [INTENT_ATTACK, INTENT_DEFEND, INTENT_FLEE, INTENT_GUARD, INTENT_RAID, INTENT_DEBUG]
const RESOLUTION_POLICY_AUTO := "auto"
const RESOLUTION_POLICY_HOLD_ENGAGED := "hold_engaged"
const VALID_RESOLUTION_POLICIES := [RESOLUTION_POLICY_AUTO, RESOLUTION_POLICY_HOLD_ENGAGED]

var encounter_id := ""
var initial_intent := INTENT_ATTACK
var resolution_policy := RESOLUTION_POLICY_AUTO
var sides: Array = []
var encounter_center := Vector3.ZERO
var source_type := ""
var projection_importance := ""
var visibility_flags: Dictionary = {}
var projection_flags: Dictionary = {}
var leash_context: Dictionary = {}
var raid_context: Dictionary = {}
var guard_context: Dictionary = {}
var battle_sim_config: Dictionary = {}
var source_live_ref_errors: Array[String] = []


func apply_dictionary(source: Dictionary) -> void:
	source_live_ref_errors = _live_ref_error_list(source, "start_request_source")
	encounter_id = str(source.get("encounter_id", "")).strip_edges()
	initial_intent = str(source.get("initial_intent", INTENT_ATTACK)).strip_edges()
	resolution_policy = str(source.get("resolution_policy", RESOLUTION_POLICY_AUTO)).strip_edges()
	if resolution_policy.is_empty():
		resolution_policy = RESOLUTION_POLICY_AUTO
	sides = _sides(source.get("sides", []))
	if source.get("encounter_center", null) is Vector3:
		encounter_center = source.get("encounter_center")
	elif source.get("location", null) is Vector3:
		encounter_center = source.get("location")
	source_type = str(source.get("source_type", "")).strip_edges()
	projection_importance = str(source.get("projection_importance", "")).strip_edges()
	visibility_flags = _dictionary(source.get("visibility_flags", {}))
	projection_flags = _dictionary(source.get("projection_flags", {}))
	leash_context = _dictionary(source.get("leash_context", {}))
	raid_context = _dictionary(source.get("raid_context", {}))
	guard_context = _dictionary(source.get("guard_context", {}))
	battle_sim_config = _dictionary(source.get("battle_sim_config", {}))


static func intent_values() -> Array[String]:
	var values: Array[String] = []
	for intent in VALID_INITIAL_INTENTS:
		values.append(str(intent))
	return values


static func is_valid_intent(intent: String) -> bool:
	return VALID_INITIAL_INTENTS.has(intent.strip_edges())


static func is_valid_resolution_policy(policy: String) -> bool:
	return VALID_RESOLUTION_POLICIES.has(policy.strip_edges())


func to_dictionary() -> Dictionary:
	var side_records: Array[Dictionary] = []
	for side in sides:
		if _is_side(side):
			var side_record = side.call("to_dictionary")
			if side_record is Dictionary:
				side_records.append(side_record)
	var result := {
		"encounter_id": encounter_id,
		"initial_intent": initial_intent,
		"resolution_policy": resolution_policy,
		"encounter_center": encounter_center,
		"source_type": source_type,
		"projection_importance": projection_importance,
		"visibility_flags": visibility_flags.duplicate(true),
		"projection_flags": projection_flags.duplicate(true),
		"sides": side_records,
	}
	if not leash_context.is_empty():
		result["leash_context"] = leash_context.duplicate(true)
	if not raid_context.is_empty():
		result["raid_context"] = raid_context.duplicate(true)
	if not guard_context.is_empty():
		result["guard_context"] = guard_context.duplicate(true)
	if not battle_sim_config.is_empty():
		result["battle_sim_config"] = battle_sim_config.duplicate(true)
	return result


func validation_errors(path := "start_request") -> Array[String]:
	var errors: Array[String] = []
	if encounter_id.strip_edges().is_empty():
		errors.append("%s.encounter_id is required" % path)
	if not is_valid_intent(initial_intent):
		errors.append("%s.initial_intent must be one of %s" % [path, ", ".join(intent_values())])
	if not is_valid_resolution_policy(resolution_policy):
		errors.append("%s.resolution_policy must be one of %s" % [path, ", ".join(VALID_RESOLUTION_POLICIES)])
	if sides.size() < 2:
		errors.append("%s needs at least two sides" % path)
	var side_ids := {}
	var player_owned_side_count := 0
	for index in range(sides.size()):
		var side = sides[index]
		if not _is_side(side):
			errors.append("%s.sides[%d] is not a CombatEncounterSide" % [path, index])
			continue
		errors.append_array(side.call("validation_errors", "%s.sides[%d]" % [path, index]))
		var side_id := str(side.get("side_id")).strip_edges()
		if not side_id.is_empty():
			if side_ids.has(side_id):
				errors.append("%s.sides[%d].side_id duplicates %s" % [path, index, side_id])
			side_ids[side_id] = true
		if bool(side.get("player_owned")):
			player_owned_side_count += 1
	if player_owned_side_count > 1:
		errors.append("%s supports at most one player-owned side" % path)
	errors.append_array(source_live_ref_errors)
	_append_live_ref_errors(errors, to_dictionary(), path)
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()


static func _sides(value) -> Array:
	var result: Array = []
	if not (value is Array):
		return result
	for index in range((value as Array).size()):
		var entry = (value as Array)[index]
		if entry is Dictionary:
			var side = SIDE_SCRIPT.new()
			side.call("apply_dictionary", entry, "side_%d" % index)
			result.append(side)
	return result


static func _is_side(value) -> bool:
	return value is RefCounted and value.get_script() == SIDE_SCRIPT


static func _dictionary(value) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else {}


static func _live_ref_error_list(value, path: String) -> Array[String]:
	var errors: Array[String] = []
	_append_live_ref_errors(errors, value, path)
	return errors


static func _append_live_ref_errors(errors: Array[String], value, path: String) -> void:
	if value is Node:
		errors.append("%s stores live Node" % path)
		return
	if value is NodePath:
		errors.append("%s stores NodePath" % path)
		return
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			_append_live_ref_errors(errors, (value as Dictionary).get(key), "%s.%s" % [path, str(key)])
	elif value is Array:
		for index in range((value as Array).size()):
			_append_live_ref_errors(errors, (value as Array)[index], "%s[%d]" % [path, index])
