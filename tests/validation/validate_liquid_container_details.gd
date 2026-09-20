extends SceneTree
## Assigned content drives the selected tank's title and truthful liter gauge.
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var tank = load("res://features/world/projection/props/furniture/tank.tscn").instantiate()
	tank.assigned_liquid_id = "water"
	tank.capacity_liters = 100.0
	tank.current_liters = 25.0
	_expect(tank.has_method("get_details_panel_data_at"), "tank exposes player-facing liquid details")
	if tank.has_method("get_details_panel_data_at"):
		var details: Dictionary = tank.get_details_panel_data_at(Vector3.ZERO)
		_expect(details.get("title") == "Water Tank" and details.get("resource_label") == "Water", "water assignment names the vessel and its contents")
		_expect(details.get("show_resource_bar", false) and is_equal_approx(float(details.get("resource_ratio", -1.0)), 0.25), "selected tank displays its current finite level")
		_expect(str(details.get("resource_value_text", "")).contains("L"), "tank quantities have liter units")
		tank.current_liters = 0.0
		details = tank.get_details_panel_data_at(Vector3.ZERO)
		_expect(details.get("state") == "Empty" and details.get("show_resource_bar", false) and float(details.get("resource_ratio", -1.0)) == 0.0, "empty assigned tanks retain the zero-level gauge")
		tank.assigned_liquid_id = "beer"
		details = tank.get_details_panel_data_at(Vector3.ZERO)
		_expect(details.get("title") == "Beer Tank" and details.get("resource_label") == "Beer", "generic tank details follow non-water assignment")
		tank.current_liters = 100.0
		details = tank.get_details_panel_data_at(Vector3.ZERO)
		_expect(float(details.get("resource_ratio", -1.0)) == 1.0, "full tank reports a full gauge")
		tank.current_liters = 150.0
		details = tank.get_details_panel_data_at(Vector3.ZERO)
		_expect(float(details.get("resource_ratio", -1.0)) == 1.0, "over-capacity hydration cannot overfill the selected gauge")
		tank.current_liters = 0.0
		tank.assigned_liquid_id = ""
		details = tank.get_details_panel_data_at(Vector3.ZERO)
		_expect(details.get("title") == "Tank" and details.get("state") == "Unassigned", "unassigned tank does not imply water")
	tank.free()
	for failure in failures: push_error(failure)
	print("LIQUID_CONTAINER_DETAILS_OK" if failures.is_empty() else "LIQUID_CONTAINER_DETAILS_FAILED")
	quit(0 if failures.is_empty() else 1)
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
