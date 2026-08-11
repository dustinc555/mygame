extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farm_placement_solver.gd

const SOLVER = preload("res://features/farming/bridge/farm_placement_solver.gd")
const PLACEMENT_BRIDGE = preload("res://features/farming/bridge/farm_placement_bridge.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var grid: Dictionary = SOLVER.build_grid(Vector3.ZERO, Vector3(2.6, 0, 1.3), 1.25)
	_expect(Vector2i(grid.get("dimensions", Vector2i.ZERO)) == Vector2i(3, 2), "drag rectangle rounds up to complete cells")
	_expect((grid.get("positions", []) as Array).size() == 6, "drag rectangle creates every cell")
	var bounded: Dictionary = SOLVER.build_grid(Vector3.ZERO, Vector3(10000.0, 0.0, 10000.0), 1.25)
	var bounded_dimensions: Vector2i = bounded.get("dimensions", Vector2i.ZERO)
	_expect(bounded_dimensions.x <= 24 and bounded_dimensions.y <= 24, "drag dimensions are bounded")
	_expect((bounded.get("positions", []) as Array).size() <= 256, "drag cell count is bounded")
	_expect(SOLVER.MAX_CELL_OVERLAP_RESULTS >= 128, "crowded ignored overlaps cannot exhaust a low obstacle-query cap")
	var samples := [
		{"position": Vector3.ZERO, "normal": Vector3.UP, "blocked_reason": ""},
		{"position": Vector3(1.25, 0.1, 0), "normal": Vector3(0.1, 0.99, 0).normalized(), "blocked_reason": "rock"},
	]
	var result: Dictionary = SOLVER.validate_samples(samples, 18.0)
	_expect(bool(result.get("valid", false)), "one blocked cell does not invalidate an otherwise valid field")
	_expect(str((result.get("blocked_cells", {}) as Dictionary).get("1:0", "")) == "rock", "blocked cell keeps a recoverable reason")
	var steep := [{"position": Vector3.ZERO, "normal": Vector3(0.8, 0.2, 0).normalized(), "blocked_reason": ""}]
	_expect(not bool(SOLVER.validate_samples(steep, 18.0).get("valid", true)), "building-grade slope tolerance rejects steep terrain")
	var preview_root := Node3D.new()
	get_root().add_child(preview_root)
	var preview := Node3D.new()
	preview_root.add_child(preview)
	var bridge := PLACEMENT_BRIDGE.new()
	preview_root.add_child(bridge)
	bridge.set("_preview", preview)
	bridge.call("_draw_mixed_preview", [Vector3.ZERO], [Vector3(1.25, 0.0, 0.0)])
	_expect(preview.get_child_count() == 2, "preview draws valid and invalid cells instead of dropping invalid cells")
	if preview.get_child_count() == 2:
		var invalid_material := (preview.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		var valid_material := (preview.get_child(1) as MeshInstance3D).material_override as StandardMaterial3D
		_expect(invalid_material != null and invalid_material.albedo_color == PLACEMENT_BRIDGE.PREVIEW_INVALID_COLOR, "invalid cell keeps clear invalid feedback")
		_expect(valid_material != null and valid_material.albedo_color == PLACEMENT_BRIDGE.PREVIEW_ADD_COLOR, "valid cell keeps add feedback")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FARM_PLACEMENT_SOLVER_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARM_PLACEMENT_SOLVER_FAILED count=%d" % failures.size())
	quit(1)
