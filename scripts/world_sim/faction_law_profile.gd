extends Resource

class_name FactionLawProfile

@export var profile_id := ""
@export var display_name := "Faction Law"
@export_range(1.0, 30.0, 0.5) var trespass_warning_interval_seconds := 3.0
@export_range(0, 6, 1) var trespass_warnings_before_alarm := 2
@export var trespass_notice_radius := 18.0
@export_enum("settlement_alarm", "victim_only", "warning_only") var trespass_escalation := "settlement_alarm"
@export_range(0, 1000, 1) var petty_theft_value_threshold := 0
@export_enum("settlement_alarm", "victim_only", "ignored") var theft_response := "settlement_alarm"
@export_enum("settlement_alarm", "victim_only") var assault_response := "settlement_alarm"
@export_enum("settlement_alarm", "blood_feud") var murder_response := "settlement_alarm"
@export_enum("outlawed", "tolerated", "legal") var slavery_policy := "outlawed"
@export_multiline var operator_notes := ""


func get_id() -> String:
	return profile_id if not profile_id.is_empty() else display_name
