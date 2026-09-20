extends "res://tests/validation/law_order_cases.gd"

## Custody contracts and one complete physical arrest-to-release scenario.
func _case_names() -> Array[String]:
	return ["_validate_stolen_metadata_expiry_and_transfer", "_validate_same_settlement_stolen_sale_rules",
		"_validate_cell_authoring_case", "_validate_no_jail_ejection_fallback",
		"_validate_arrest_to_release"]
