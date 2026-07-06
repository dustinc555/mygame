extends SceneTree

## Validates ground snap-on-realize: BuildingPlacementSolver.snap_to_terrain
## re-solves Y/tilt while preserving XZ, yaw, and foundation raise, and
## SettlementTown snaps its grounded children and markers at runtime load.
## A plain StaticBody3D floor stands in for terrain (the solver treats any
## non-building collider as ground). Uses load() at runtime, not preload:
## --script mode cannot compile GECS preload chains at parse time.

const TOWN_TEMPLATE_PATH := "res://features/settlements/bridge/settlement_town.tscn"
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
	await _validate_town_snap_pass()
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
	if absf(result.origin.y - (FLOOR_TOP_Y + 0.75)) > Y_TOLERANCE:
		_fail("snap_to_terrain Y should be floor top + foundation, got %.3f" % result.origin.y)
	if absf(result.origin.x - 3.0) > 0.001 or absf(result.origin.z - 4.0) > 0.001:
		_fail("snap_to_terrain should preserve authored XZ")
	var result_yaw := atan2(result.basis.z.x, result.basis.z.z)
	if absf(result_yaw - yaw) > 0.01:
		_fail("snap_to_terrain should preserve authored yaw, got %.3f" % result_yaw)
	if not bool(snapped["slope_ok"]):
		_fail("snap_to_terrain on a flat floor should be slope_ok")


func _validate_town_snap_pass() -> void:
	var template := load(TOWN_TEMPLATE_PATH) as PackedScene
	if template == null:
		_fail("Missing settlement_town.tscn template")
		return
	var town := template.instantiate()
	var facilities := town.get_node_or_null("Facilities")
	if facilities == null:
		_fail("Town template lost its Facilities root")
		town.free()
		return
	var building := Node3D.new()
	building.name = "SnapTestHouse"
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6.0, 3.0, 4.0)
	visual.mesh = box
	visual.position = Vector3(0.0, 1.5, 0.0)
	building.add_child(visual)
	facilities.add_child(building)
	building.position = Vector3(10.0, 17.0, -8.0)
	var road_spawn := town.get_node_or_null("RoadSpawn") as Node3D
	if road_spawn != null:
		road_spawn.position = Vector3(20.0, 9.0, 5.0)
	root.add_child(town)
	for _frame in range(8):
		await physics_frame
	var building_y := (building as Node3D).global_position.y
	if absf(building_y - FLOOR_TOP_Y) > Y_TOLERANCE:
		_fail("Town snap should ground the housing child at floor top, got %.3f" % building_y)
	if absf((building as Node3D).global_position.x - 10.0) > 0.001:
		_fail("Town snap should preserve building XZ")
	if road_spawn != null and absf(road_spawn.global_position.y - FLOOR_TOP_Y) > Y_TOLERANCE:
		_fail("Town snap should ground RoadSpawn marker, got %.3f" % road_spawn.global_position.y)
	town.queue_free()


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
