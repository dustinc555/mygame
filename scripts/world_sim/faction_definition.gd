extends Resource

class_name FactionDefinition

@export var faction_id := ""
@export var display_name := "Faction"
@export_multiline var description := ""
@export var default_hostile_faction_ids: PackedStringArray = PackedStringArray()
@export var starting_war_faction_ids: PackedStringArray = PackedStringArray()
@export var open_access := true
@export_range(-100, 100, 1) var accepted_reputation_threshold := 0
@export var permanently_hostile := false
@export var behavior_profile: Resource
@export var personality_profile: Resource
@export var law_profile: Resource
@export var population_name_profile: Resource


func get_id() -> String:
	return faction_id if not faction_id.is_empty() else display_name


func is_hostile_to(other_faction_id: String) -> bool:
	return not other_faction_id.is_empty() and default_hostile_faction_ids.has(other_faction_id)


func get_behavior_profile() -> Resource:
	return behavior_profile


func get_personality_profile() -> Resource:
	return personality_profile


func get_law_profile() -> Resource:
	return law_profile


func get_population_name_profile() -> Resource:
	return population_name_profile
