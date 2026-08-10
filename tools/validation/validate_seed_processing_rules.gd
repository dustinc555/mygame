extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_seed_processing_rules.gd

const RULES = preload("res://features/farming/sim/seed_processing_rules.gd")

func _initialize() -> void:
	var result: Dictionary = RULES.process_counts(3, 2, 4, 20)
	if int(result.get("produce_remaining", -1)) != 1 or int(result.get("seeds", -1)) != 8:
		push_error("two produce become eight seeds without consuming unrelated produce")
		print("SEED_PROCESSING_RULES_FAILED")
		quit(1)
		return
	var limited: Dictionary = RULES.process_counts(3, 3, 4, 5)
	if int(limited.get("produce_remaining", -1)) != 2 or int(limited.get("seeds", -1)) != 4:
		push_error("storage capacity limits seed processing atomically")
		print("SEED_PROCESSING_RULES_FAILED")
		quit(1)
		return
	print("SEED_PROCESSING_RULES_OK")
	quit(0)
