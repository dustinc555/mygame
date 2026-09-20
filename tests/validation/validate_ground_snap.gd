extends "res://tests/validation/test_case.gd"

## Solver contract only: preserve XZ/yaw and foundation raise when grounding.
## Town realization does not automatically reposition authored children.

const FLOOR_TOP_Y := 2.5
const Y_TOLERANCE := 0.1

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_floor()
	await physics_frame
	await physics_frame
	_validate_solver_snap()
	_finish()


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "GroundFloor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	root.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, FLOOR_TOP_Y - 0.5, 0.0)


func _validate_solver_snap() -> void:
	var space := root.get_world_3d().direct_space_state
	var yaw := 1.2
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var authored := Transform3D(Basis(Vector3.UP.cross(forward), Vector3.UP, forward), Vector3(3.0, 10.0, 4.0))
	var snapped := BuildingPlacementSolver.snap_to_terrain(space, authored, Vector2(6.0, 4.0), 0.75)
	if snapped.is_empty():
		_fail("snap_to_terrain found no ground above the floor")
		return
	var result: Transform3D = snapped["transform"]
	if not result.origin.is_finite() or not result.basis.x.is_finite() or not result.basis.y.is_finite() or not result.basis.z.is_finite():
		_fail("Ground-snap transform must be finite")
	if not (absf(result.origin.y - (FLOOR_TOP_Y + 0.75)) <= Y_TOLERANCE):
		_fail("snap_to_terrain Y should be floor top + foundation, got %.3f" % result.origin.y)
	if absf(result.origin.x - 3.0) > 0.001 or absf(result.origin.z - 4.0) > 0.001:
		_fail("snap_to_terrain should preserve authored XZ")
	var result_yaw := atan2(result.basis.z.x, result.basis.z.z)
	if not (absf(result_yaw - yaw) <= 0.01):
		_fail("snap_to_terrain should preserve authored yaw, got %.3f" % result_yaw)
	if not bool(snapped["slope_ok"]):
		_fail("snap_to_terrain on a flat floor should be slope_ok")


func _finish() -> void:
	if _failures.is_empty():
		print("GROUND_SNAP_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("GROUND_SNAP_FAILED count=%d" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
