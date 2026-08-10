extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_character_surface.gd

func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://features/actors/projection/humanoid/humanoid_character.gd")
	for required in ["func set_farming_work_visual", "func is_actively_farming", "func get_farming_progress_ratio", "_farming_work_target"]:
		if not source.contains(required):
			push_error("HumanoidCharacter exposes %s" % required)
			print("FARMING_CHARACTER_SURFACE_FAILED")
			quit(1)
			return
	var hud_source := FileAccess.get_file_as_string("res://features/world/bridge/world_interaction_controller.gd")
	if not hud_source.contains("is_actively_farming") or not hud_source.contains("get_farming_progress_ratio"):
		push_error("Party HUD consumes farming work progress")
		print("FARMING_CHARACTER_SURFACE_FAILED")
		quit(1)
		return
	var body_source := FileAccess.get_file_as_string("res://features/actors/projection/humanoid/humanoid_body_projection.gd")
	for clip_name in ["Farm_Harvest", "Farm_PlantSeed", "Farm_Watering"]:
		if not body_source.contains(clip_name):
			push_error("farming animation is copied from UAL2: %s" % clip_name)
			print("FARMING_CHARACTER_SURFACE_FAILED")
			quit(1)
			return
	print("FARMING_CHARACTER_SURFACE_OK")
	quit(0)
