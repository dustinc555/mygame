extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_test_level.gd

func _initialize() -> void:
	var scene = load("res://scenes/test_levels/farming_test.tscn")
	if scene == null:
		push_error("farming test scene loads")
		print("FARMING_TEST_LEVEL_FAILED")
		quit(1)
		return
	var source := FileAccess.get_file_as_string("res://scenes/test_levels/farming_test.tscn")
	for required in ["GameBootstrap", "PartyManager", "FarmWaterSource", "FarmSeedProcessor", "AdvanceTime", "groups=[\"terrain\"]"]:
		if not source.contains(required):
			push_error("farming test level contains %s" % required)
			print("FARMING_TEST_LEVEL_FAILED")
			quit(1)
			return
	for removed in ["FARMING TEST:", "node name=\"PlanField\"", "node name=\"Panel\"", "node name=\"Instructions\"", "node name=\"Status\""]:
		if source.contains(removed):
			push_error("farming test level no longer contains %s" % removed)
			print("FARMING_TEST_LEVEL_FAILED")
			quit(1)
			return
	print("FARMING_TEST_LEVEL_OK")
	quit(0)
