extends "res://tests/validation/test_case.gd"
## Real actor progress surface; clip/HUD playback is checked by water runtime.
var failures: Array[String] = []
func _initialize() -> void:
	var actor := HumanoidCharacter.new()
	var transitions: Array[bool] = []
	actor.state_changed.connect(func(): transitions.append(actor.is_actively_farming()))
	actor.set_farming_work_visual(true, "plant", Vector3(1, 0, 3), 0.25)
	_expect(actor.is_actively_farming() and actor.get_farming_progress_ratio() == 0.25 and actor._farming_work_action == "plant", "starting work exposes real action and quarter progress")
	actor.set_farming_work_visual(true, "plant", Vector3(1, 0, 3), 2.0)
	_expect(actor.get_farming_progress_ratio() == 1.0, "progress clamps to completion")
	actor.set_farming_work_visual(true, "water", Vector3.ZERO, -1.0)
	_expect(actor.get_farming_progress_ratio() == 0.0 and actor._farming_work_action == "water", "action replacement updates identity and clamps negative progress")
	actor.set_farming_work_visual(false, "water", Vector3.ZERO, 0.75)
	_expect(not actor.is_actively_farming() and actor.get_farming_progress_ratio() == 0.0 and actor._farming_work_action.is_empty() and transitions == [true, true, false], "interruption immediately clears action/progress and publishes state transition")
	actor.free()
	# This remaining assertion intentionally protects authored clip names only.
	var body_source := FileAccess.get_file_as_string("res://features/actors/projection/humanoid/humanoid_body_projection.gd")
	for clip in ["Farm_Harvest", "Farm_PlantSeed", "Farm_Watering"]:
		_expect(body_source.contains(clip), "body declares required farming clip: " + clip)
	for failure in failures: push_error(failure)
	print("FARMING_CHARACTER_SURFACE_OK" if failures.is_empty() else "FARMING_CHARACTER_SURFACE_FAILED")
	quit(0 if failures.is_empty() else 1)
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
