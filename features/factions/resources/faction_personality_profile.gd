extends Resource

class_name FactionPersonalityProfile

@export var profile_id := ""
@export var display_name := "Faction Personality"
@export_range(0.0, 1.0, 0.01) var aggression := 0.25
@export_range(0.0, 1.0, 0.01) var risk_tolerance := 0.35
@export_range(0.0, 1.0, 0.01) var mercy := 0.5
@export_range(0.0, 1.0, 0.01) var greed := 0.35
@export_range(0.0, 1.0, 0.01) var openness_to_outsiders := 0.5
@export_range(0.0, 1.0, 0.01) var honor := 0.5
@export_range(0.0, 1.0, 0.01) var negotiation_patience := 0.5
@export_multiline var operator_notes := ""


func get_id() -> String:
	return profile_id if not profile_id.is_empty() else display_name
