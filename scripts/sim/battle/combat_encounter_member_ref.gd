extends RefCounted

class_name CombatEncounterMemberRef

var member_id := ""
var actor_id := ""
var squad_id := ""
var party_id := ""
var role_markers: Array[String] = []


func apply_dictionary(source: Dictionary, default_squad_id := "", default_party_id := "") -> void:
	member_id = str(source.get("member_id", source.get("actor_id", ""))).strip_edges()
	actor_id = str(source.get("actor_id", member_id)).strip_edges()
	squad_id = str(source.get("squad_id", default_squad_id)).strip_edges()
	party_id = str(source.get("party_id", default_party_id)).strip_edges()
	role_markers = _string_array(source.get("role_markers", []))


func to_dictionary() -> Dictionary:
	return {
		"member_id": member_id,
		"actor_id": actor_id,
		"squad_id": squad_id,
		"party_id": party_id,
		"role_markers": role_markers.duplicate(),
	}


func validation_errors(path := "member_ref") -> Array[String]:
	var errors: Array[String] = []
	if member_id.strip_edges().is_empty():
		errors.append("%s.member_id is required" % path)
	return errors


static func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result
