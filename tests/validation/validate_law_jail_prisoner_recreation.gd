extends "res://tests/validation/law_order_cases.gd"

## Destroy and recreate the actual prisoner; retain exact property, party and cell identity.
func _case_names() -> Array[String]:
	return ["_validate_prisoner_recreation", "_validate_pending_sentence_recreation"]
