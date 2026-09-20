extends "res://tests/validation/law_order_cases.gd"

## Ordinary delivery and elevated-post return each start from independent real custody.
func _case_names() -> Array[String]:
	return ["_validate_sentence_case", "_validate_elevated_warden_post"]
