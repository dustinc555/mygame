class_name CanonCharacters
extends RefCounted

## Canonical authored characters. The disk records under
## features/actors/resources/characters/ ARE the definition: any actor bearing a
## canon name takes appearance and skills from its record — never randomized,
## never scene-styled. Scenes may still author equipment/position/faction.
const RECORDS := {
	"Mira": preload("res://features/actors/resources/characters/mira.tres"),
	"Tomas": preload("res://features/actors/resources/characters/tomas.tres"),
	"Sable": preload("res://features/actors/resources/characters/sable.tres"),
	"Nika": preload("res://features/actors/resources/characters/nika.tres"),
	"Bram": preload("res://features/actors/resources/characters/bram.tres"),
}


static func record_for_name(member_name: String) -> CharacterRecordDefinition:
	return RECORDS.get(member_name.strip_edges(), null) as CharacterRecordDefinition
