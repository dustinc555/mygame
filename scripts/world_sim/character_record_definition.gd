extends Resource

class_name CharacterRecordDefinition

## Editor-configurable authored character (party member) record. Replaces the old
## JSON character files so character data is editor-friendly and type-checked, in
## line with factions/nests/races. to_record() yields the same Dictionary the
## population/GECS layer already consumes.

@export var actor_id := ""
@export var member_name := ""
@export var appearance: Dictionary = {}
@export var skill_levels: Dictionary = {}
@export var equipment_slots: Dictionary = {}
@export var inventory_entries: Array = []
@export var traits: Dictionary = {}
@export var personality: Dictionary = {}


func to_record() -> Dictionary:
	return {
		"actor_id": actor_id,
		"member_name": member_name,
		"appearance": appearance.duplicate(true),
		"skill_levels": skill_levels.duplicate(true),
		"equipment_slots": equipment_slots.duplicate(true),
		"inventory_entries": inventory_entries.duplicate(true),
		"traits": traits.duplicate(true),
		"personality": personality.duplicate(true),
	}
