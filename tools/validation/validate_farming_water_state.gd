extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_water_state.gd

var _ecs_placeholder: Node


func _init() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var script = load("res://features/farming/sim/c_game_farm_water_source_state.gd")
	if script == null:
		push_error("farm water source GECS component loads")
		_finish(false)
		return
	var component = script.new()
	component.apply_state({"source_id": "river_barrel", "capacity": 100.0, "current_water": 42.5, "renewable": false})
	var restored: Dictionary = component.to_state()
	var passed := str(restored.get("source_id", "")) == "river_barrel" and is_equal_approx(float(restored.get("current_water", 0.0)), 42.5) and not bool(restored.get("renewable", true))
	if not passed:
		push_error("finite water capacity round-trips through GECS")
	component = null
	_finish(passed)


func _finish(passed: bool) -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
	print("FARMING_WATER_STATE_OK" if passed else "FARMING_WATER_STATE_FAILED")
	quit(0 if passed else 1)
