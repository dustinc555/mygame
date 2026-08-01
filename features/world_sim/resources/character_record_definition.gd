extends Resource

class_name CharacterRecordDefinition

## Editor-configurable authored character (party member) record. Replaces the old
## JSON character files so character data is editor-friendly and type-checked, in
## line with factions/nests/races. to_record() yields the same Dictionary the
## population/GECS layer already consumes.

@export var actor_id := ""
@export var member_name := ""
@export_range(13, 95, 1) var age_years := CharacterAgeRules.DEFAULT_ADULT_AGE
@export var appearance: Dictionary = {}
@export var skill_levels: Dictionary = {}
@export var equipment_slots: Dictionary = {}
@export var inventory_entries: Array = []
@export var traits: Dictionary = {}
@export var personality: Dictionary = {}


func to_record() -> Dictionary:
	var clean_actor_id := actor_id.strip_edges()
	if clean_actor_id.is_empty():
		push_error("CharacterRecordDefinition requires a non-empty actor_id")
		return {}
	return {
		"actor_id": clean_actor_id,
		"member_name": member_name,
		"birth_day_index": CharacterAgeRules.birth_day_for_age(age_years, 0),
		"appearance": appearance.duplicate(true),
		"skill_levels": skill_levels.duplicate(true),
		"equipment_slots": equipment_slots.duplicate(true),
		"inventory_entries": inventory_entries.duplicate(true),
		"traits": traits.duplicate(true),
		"personality": personality.duplicate(true),
	}
