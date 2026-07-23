@tool
extends Resource

class_name CharacterTypeSet

@export var set_id := ""
@export var display_name := "Character Types"
@export var default_character_type: Resource
@export var character_types: Array[Resource] = []
## role_id -> type_id. Role-to-type policy is authored here, never switched in
## facility gameplay code.
@export var role_character_type_ids: Dictionary = {}


func resolve_character_type(requested_type_id: String, role_id: String) -> Resource:
	var type_id := requested_type_id.strip_edges().to_lower()
	if type_id.is_empty() or type_id == "default":
		type_id = str(role_character_type_ids.get(role_id.strip_edges().to_lower(), "")).strip_edges().to_lower()
	if type_id.is_empty() and default_character_type != null:
		return default_character_type
	for character_type in character_types:
		if character_type != null and str(character_type.get("type_id")).strip_edges().to_lower() == type_id:
			return character_type
	if default_character_type != null and str(default_character_type.get("type_id")).strip_edges().to_lower() == type_id:
		return default_character_type
	return null


func get_character_types() -> Array[Resource]:
	var result: Array[Resource] = []
	if default_character_type != null:
		result.append(default_character_type)
	for character_type in character_types:
		if character_type != null and not result.has(character_type):
			result.append(character_type)
	return result
