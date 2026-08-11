extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_manual_till.gd

const PLACEMENT_BRIDGE = preload("res://features/farming/bridge/farm_placement_bridge.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var placement = PLACEMENT_BRIDGE.new()
	_expect(placement.has_method("manual_till_grid"), "Till Soil exposes click-one and drag-rectangle targeting")
	if placement.has_method("manual_till_grid"):
		var rectangle: Dictionary = placement.call("manual_till_grid", Vector3.ZERO, Vector3(2.5, 0.0, 1.25), 1.25)
		_expect((rectangle.get("positions", []) as Array).size() == 6 and rectangle.get("dimensions", Vector2i.ZERO) == Vector2i(3, 2), "holding click creates a complete rectangle rather than a painted path")
	placement.free()
	var placement_source := FileAccess.get_file_as_string("res://features/farming/bridge/farm_placement_bridge.gd")
	var projection_source := FileAccess.get_file_as_string("res://features/farming/projection/farm_plot_projection.gd")
	var controller_source := FileAccess.get_file_as_string("res://features/farming/sim/farm_controller.gd")
	var work_source := FileAccess.get_file_as_string("res://features/farming/bridge/farm_work_bridge.gd")
	_expect(placement_source.contains("prepare_manual_till"), "dragged till cells become durable farming requests")
	_expect(projection_source.contains("prepare_plot_operation") and projection_source.contains("assign_cell_sequence"), "Shift-click cell actions expand through the selected actor's field-wide command path")
	_expect(controller_source.contains("_request_cell_operations") and controller_source.contains("eligible_targets"), "painted Till publishes durable batched work for every selected square")
	_expect(work_source.contains("assign_cell_sequence") and work_source.contains("command_targets") and not work_source.contains("_manual_queues"), "manual field commands chain normal cell assignments without a separate private queue")
	_finish()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("FARMING_MANUAL_TILL_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARMING_MANUAL_TILL_FAILED count=%d" % failures.size())
	quit(1)
