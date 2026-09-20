extends "res://tests/validation/law_order_cases.gd"

## Real payment and same-prisoner repeat custody, each in its own world.
func _case_names() -> Array[String]:
	return ["_validate_bail_release", "_validate_repeat_custody"]
