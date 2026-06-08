extends RefCounted

class_name CombatEncounterSide

const MEMBER_REF_SCRIPT := preload("res://scripts/sim/battle/combat_encounter_member_ref.gd")

var side_id := ""
var faction_id := ""
var party_id := ""
var squad_id := ""
var player_owned := false
var role_markers: Array[String] = []
var member_refs: Array = []
var starting_position := Vector3.ZERO
var has_starting_position := false
var projection_importance := ""


func apply_dictionary(source: Dictionary, default_side_id := "") -> void:
	side_id = str(source.get("side_id", default_side_id)).strip_edges()
	faction_id = str(source.get("faction_id", "")).strip_edges()
	party_id = str(source.get("party_id", "")).strip_edges()
	squad_id = str(source.get("squad_id", "")).strip_edges()
	player_owned = bool(source.get("player_owned", false))
	role_markers = _string_array(source.get("role_markers", []))
	member_refs = _member_refs(source.get("member_refs", source.get("members", [])), squad_id, party_id)
	if source.get("starting_position", null) is Vector3:
		starting_position = source.get("starting_position")
		has_starting_position = true
	projection_importance = str(source.get("projection_importance", "")).strip_edges()


func to_dictionary() -> Dictionary:
	var members: Array[Dictionary] = []
	for member_ref in member_refs:
		if _is_member_ref(member_ref):
			var member_record = member_ref.call("to_dictionary")
			if member_record is Dictionary:
				members.append(member_record)
	var result := {
		"side_id": side_id,
		"faction_id": faction_id,
		"party_id": party_id,
		"squad_id": squad_id,
		"player_owned": player_owned,
		"role_markers": role_markers.duplicate(),
		"member_refs": members,
		"projection_importance": projection_importance,
	}
	if has_starting_position:
		result["starting_position"] = starting_position
	return result


func validation_errors(path := "side") -> Array[String]:
	var errors: Array[String] = []
	if side_id.strip_edges().is_empty():
		errors.append("%s.side_id is required" % path)
	if squad_id.strip_edges().is_empty() and party_id.strip_edges().is_empty() and member_refs.is_empty():
		errors.append("%s needs a squad_id, party_id, or member_refs" % path)
	for index in range(member_refs.size()):
		var member_ref = member_refs[index]
		if _is_member_ref(member_ref):
			errors.append_array(member_ref.call("validation_errors", "%s.member_refs[%d]" % [path, index]))
		else:
			errors.append("%s.member_refs[%d] is not a CombatEncounterMemberRef" % [path, index])
	return errors


static func _is_member_ref(value) -> bool:
	return value is RefCounted and value.get_script() == MEMBER_REF_SCRIPT


static func _member_refs(value, default_squad_id: String, default_party_id: String) -> Array:
	var result: Array = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		if entry is Dictionary:
			var ref = MEMBER_REF_SCRIPT.new()
			ref.call("apply_dictionary", entry, default_squad_id, default_party_id)
			result.append(ref)
		else:
			var member_id := str(entry).strip_edges()
			if not member_id.is_empty():
				var string_ref = MEMBER_REF_SCRIPT.new()
				string_ref.call("apply_dictionary", {"member_id": member_id}, default_squad_id, default_party_id)
				result.append(string_ref)
	return result


static func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result
