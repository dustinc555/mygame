extends Resource

class_name FactionLawProfile

enum Offense { THEFT = 1, TRESPASS = 2, ASSAULT = 4, MURDER = 8, LOCKPICKING = 16, ESCAPE = 32, RESISTING_ARREST = 64 }
const OFFENSE_FLAGS := {"theft": Offense.THEFT, "trespass": Offense.TRESPASS, "assault": Offense.ASSAULT, "murder": Offense.MURDER, "lockpicking": Offense.LOCKPICKING, "escape": Offense.ESCAPE, "resisting_arrest": Offense.RESISTING_ARREST}

@export var profile_id := ""
@export var display_name := "Faction Law"
## Unchecked offenses produce no warrants. Personal defense still operates.
## Read for each new action; changing this does not erase existing sentences.
@export_flags("Theft", "Trespass", "Assault", "Murder", "Lockpicking", "Escape", "Resisting Arrest") var enabled_offenses: int = Offense.THEFT | Offense.TRESPASS | Offense.ASSAULT | Offense.MURDER | Offense.LOCKPICKING | Offense.ESCAPE | Offense.RESISTING_ARREST
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


func crime_is_illegal(crime_type: String) -> bool:
	if (enabled_offenses & int(OFFENSE_FLAGS.get(crime_type, 0))) == 0:
		return false
	if crime_type == "theft":
		return theft_response != "ignored"
	if crime_type == "trespass":
		return trespass_escalation != "warning_only"
	return true


func uses_public_enforcement(crime_type: String) -> bool:
	match crime_type:
		"theft": return theft_response == "settlement_alarm"
		"assault": return assault_response == "settlement_alarm"
		"murder": return murder_response == "settlement_alarm"
		"trespass": return trespass_escalation == "settlement_alarm"
	return true
