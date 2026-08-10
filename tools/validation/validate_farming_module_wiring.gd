extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_module_wiring.gd

func _initialize() -> void:
	var module_path := "res://features/farming/farming_module.gd"
	var bootstrap_source := FileAccess.get_file_as_string("res://features/core/game_bootstrap.gd")
	if not bootstrap_source.contains(module_path):
		push_error("GameBootstrap registers FarmingModule")
		print("FARMING_MODULE_WIRING_FAILED")
		quit(1)
		return
	var module_script = load(module_path)
	if module_script == null or not module_script.can_instantiate():
		push_error("FarmingModule loads")
		print("FARMING_MODULE_WIRING_FAILED")
		quit(1)
		return
	var module_source := FileAccess.get_file_as_string(module_path)
	for service_id in ["FarmController", "FarmPlacementBridge", "FarmWorkBridge", "FarmProjectionBridge"]:
		if not module_source.contains(service_id):
			push_error("FarmingModule exposes %s" % service_id)
			print("FARMING_MODULE_WIRING_FAILED")
			quit(1)
			return
	print("FARMING_MODULE_WIRING_OK")
	quit(0)
