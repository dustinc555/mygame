extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_gecs_state.gd

var _ecs_placeholder: Node


func _init() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var farm_state_script = load("res://features/farming/sim/c_game_farm_plot_state.gd")
	var component = farm_state_script.new()
	component.apply_state({
		"plot_id": "farm:7",
		"owner_faction_id": "player",
		"settlement_id": "settlement:test",
		"origin": Vector3(3.0, 1.0, 4.0),
		"cell_size": 1.25,
		"crop_policy_id": "tomato",
		"field_deleted": true,
		"priority": 3,
		"worker_policy": "settlement",
		"crop_id": "tomato",
		"current_crop_id": "tomato",
		"next_crop_id": "bell_pepper",
		"requested_operations": PackedStringArray(["till"]),
		"continuous": true,
		"last_simulated_minute": 42,
		"cells": {"0:0": {"status": "planted", "growth": 0.25, "water": 9.0}},
		"soil_remnants": {"1:0": {"soil_created": true, "soil_recovery_started_minute": 42}},
	})
	var output: Dictionary = component.to_state()
	var failures: Array[String] = []
	_expect(failures, "plot id round trips", output.get("plot_id") == "farm:7")
	_expect(failures, "ownership round trips", output.get("owner_faction_id") == "player")
	_expect(failures, "settlement round trips", output.get("settlement_id") == "settlement:test")
	_expect(failures, "obsolete field-level continuous mode is discarded", not output.has("continuous"))
	_expect(failures, "obsolete plot-wide crop and request state is discarded", not output.has("crop_id") and not output.has("current_crop_id") and not output.has("next_crop_id") and not output.has("requested_operations"))
	_expect(failures, "field management policy round trips", output.get("crop_policy_id") == "tomato" and int(output.get("priority", 0)) == 3 and output.get("worker_policy") == "settlement")
	_expect(failures, "deleted field remnant identity round trips", bool(output.get("field_deleted", false)))
	_expect(failures, "simulation clock round trips", int(output.get("last_simulated_minute")) == 42)
	var cells: Dictionary = output.get("cells", {})
	_expect(failures, "cell state is durable", is_equal_approx(float((cells.get("0:0", {}) as Dictionary).get("growth", 0.0)), 0.25))
	_expect(failures, "removed physical soil remains durable outside logical cells", bool((((output.get("soil_remnants", {}) as Dictionary).get("1:0", {}) as Dictionary).get("soil_created", false))))
	component.apply_state({"cells": {"0:0": {"growth": 0.9}}})
	_expect(failures, "apply duplicates nested input", is_equal_approx(float(((component.to_state().get("cells", {}) as Dictionary).get("0:0", {}) as Dictionary).get("growth", 0.0)), 0.9))
	_finish(failures)


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("FARMING_GECS_STATE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARMING_GECS_STATE_FAILED count=%d" % failures.size())
	quit(1)
