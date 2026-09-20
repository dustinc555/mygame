extends "res://tests/validation/law_order_cases.gd"

## Command, audience and warrant policy. Each starts with fresh actors/wounds.
func _case_names() -> Array[String]:
	return ["_validate_guard_command_priority", "_validate_player_assault_local_law_response",
		"_validate_victim_only_case", "_validate_expired_warrant_cleanup",
		"_validate_context_attack_on_guard", "_validate_context_attack_on_warden"]
