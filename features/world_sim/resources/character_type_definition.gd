@tool
extends Resource

class_name CharacterTypeDefinition

@export var type_id := ""
@export var display_name := "Character Type"
## Issued once when a permanent GECS character first receives this type.
## Equippable items fill empty slots; existing equipment is never replaced.
@export var starting_equipment: Array[Resource] = []
## skill_id -> Vector2i(minimum, maximum). These ranges apply only when the
## character has no prior type, never when an existing person changes jobs.
@export var starting_skill_ranges: Dictionary = {}


func get_id() -> String:
	return type_id.strip_edges().to_lower()


func get_display_name() -> String:
	return display_name if not display_name.strip_edges().is_empty() else get_id().capitalize()


func get_realization_signature() -> String:
	var equipment_paths: Array[String] = []
	for item in starting_equipment:
		equipment_paths.append(item.resource_path if item != null else "")
	var skill_keys := starting_skill_ranges.keys()
	skill_keys.sort()
	var skills: Array[String] = []
	for skill_id in skill_keys:
		skills.append("%s=%s" % [str(skill_id), str(starting_skill_ranges[skill_id])])
	return "%s|%s|%s" % [resource_path, ",".join(equipment_paths), ",".join(skills)]
