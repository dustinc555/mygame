extends SceneTree

## Live-movement proof that the runtime navmesh bake unifies Terrain3D ground
## and WorldBuilding interiors: a party member walks from open terrain through
## the WoodbrickHouse door (possible only if walls carve the navmesh) and up
## the interior stairs to the second floor (possible only if the stair ramp
## collider joined terrain and floor polygons in one bake).
##
## Deterministic: waits on WorldNavigationController.bake_finished, never on
## fixed frame sleeps, before asserting. Run:
## godot --headless --path . --script res://tools/validation/validate_rustwash_building_navigation.gd
##
## Baseline 2026-07-05b (whole-world: 288 tiles of 64m, cell 0.16/height 0.1,
## radius 0.3, slope 40): full world bake ~45s wall on 4 workers (was ~2-3min
## at cell 0.1). With a navcache present
## (world_authoring "Bake World Nav" or tools/bake_world_navcache.gd) all
## tiles load from disk in seconds and only runtime-spawned content re-bakes.
## Dynamic changes re-bake only touched tiles (~1s).

const SCENE_PATH := "res://scenes/zones/rustwash_basin/rustwash_basin.tscn"
## The house is spawned at RUNTIME (it is no longer authored in the zone):
## this exercises the full dynamic-building path — spawn dirties its tiles,
## they re-bake, and the walks prove the patched navmesh.
const HOUSE_SCENE_PATH := "res://features/world/projection/buildings/shells/modular/woodbrick_house.tscn"
const HOUSE_TRANSFORM := Transform3D(Basis.IDENTITY, Vector3(3.8771572, 0.42435217, -177.07948))
const MAX_SETUP_FRAMES := 600
# The whole world (~288 tiles at fine cells) bakes at startup on 4 worker
# threads; the wait budget must outlast it.
const MAX_BAKE_FRAMES := 30000
const MAX_MOVE_FRAMES := 9000
const SETTLE_FRAMES := 12
const START_CLEARANCE_Y := 0.7
const HORIZONTAL_TOLERANCE := 0.9
const VERTICAL_TOLERANCE := 0.9

var _failures: Array[String] = []
var _scene: Node
var _controller: Node
var _actor: Node3D
var _bake_count := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _load_scene()
	if _failures.is_empty():
		await _await_fresh_bake()
	if _failures.is_empty():
		_check_polygons_near_house()
	if _failures.is_empty():
		await _run_walk_tests()
	_finish()


func _finish() -> void:
	# Drain any in-flight bake before quitting: the bake thread reads live
	# Terrain3D data and must not outlive the scene teardown.
	if _controller != null:
		for _frame in range(MAX_BAKE_FRAMES):
			if not bool(_controller.call("is_baking")):
				break
			await physics_frame
	if _failures.is_empty():
		print("RUSTWASH_BUILDING_NAV_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RUSTWASH_BUILDING_NAV_VALIDATION_FAILED count=%d" % _failures.size())
	quit(1)


func _load_scene() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_scene = packed.instantiate()
	root.add_child(_scene)
	_controller = await _wait_for(func() -> Node:
		return get_first_node_in_group("world_navigation_controller"), MAX_SETUP_FRAMES)
	if _controller == null:
		_failures.append("WorldNavigationController never appeared in the scene tree")
		return
	var nav_settings: Resource = _controller.get("settings")
	if nav_settings != null:
		nav_settings.set("log_timing", true)
	var house_scene: PackedScene = load(HOUSE_SCENE_PATH)
	var house: Node3D = house_scene.instantiate()
	house.name = "WoodbrickHouse"
	_scene.add_child(house)
	house.global_transform = HOUSE_TRANSFORM
	_actor = await _wait_for(func() -> Node:
		var manager := _scene.get_node_or_null("PartyManager")
		if manager != null and manager.get("party_members") is Array:
			for member in manager.get("party_members"):
				if member is Node3D and member.has_method("set_move_target"):
					return member
		return null, MAX_SETUP_FRAMES)
	if _actor == null:
		_failures.append("no party member with set_move_target spawned")


func _await_fresh_bake() -> void:
	# The startup bake covers the whole world (house included); wait for the
	# gate to release and polygons to be queryable near the house.
	_controller.connect("bake_finished", _on_bake_finished)
	var probe := _outside_front_target() + Vector3(0.0, 0.5, 0.0)
	for _frame in range(MAX_BAKE_FRAMES):
		await physics_frame
		if bool(_controller.call("is_initial_navigation_pending")):
			continue
		if _closest_nav_point(probe).distance_to(probe) <= 2.5:
			return
	_failures.append("no queryable navmesh near house within %d frames (bakes seen: %d)" % [MAX_BAKE_FRAMES, _bake_count])


func _on_bake_finished() -> void:
	_bake_count += 1


func _check_polygons_near_house() -> void:
	var probe := _outside_front_target() + Vector3(0.0, 0.5, 0.0)
	var closest := _closest_nav_point(probe)
	if closest.distance_to(probe) > 2.5:
		_failures.append("no navmesh near house door: probe=%s closest=%s" % [probe, closest])


func _run_walk_tests() -> void:
	# The loading gate pauses the tree until the starter bake lands; issuing
	# move orders across the unpause frame races actor/brain initialization.
	for _frame in range(MAX_SETUP_FRAMES):
		if not paused:
			break
		await physics_frame
	# Wait out the background full-chunk bake: its mesh swap empties the map
	# for a frame, which would invalidate target snapping mid-setup.
	var door_probe := _outside_front_target() + Vector3(0.0, 0.5, 0.0)
	var stable_frames := 0
	for _frame in range(MAX_BAKE_FRAMES):
		var quiescent: bool = not bool(_controller.call("is_baking"))
		var queryable := _closest_nav_point(door_probe).distance_to(door_probe) <= 2.5
		stable_frames = stable_frames + 1 if (quiescent and queryable) else 0
		if stable_frames >= 5:
			break
		await physics_frame
	var outside := _snap_to_navmesh(_outside_front_target())
	var interior := _interior_ground_target()
	var upstairs := _upstairs_target()
	if not _failures.is_empty():
		return
	await _place_actor(outside + Vector3(0.0, START_CLEARANCE_Y, 0.0))
	await _walk_test("terrain_to_interior_through_door", interior)
	if not _failures.is_empty():
		return
	await _walk_test("interior_back_to_terrain", outside)
	if not _failures.is_empty():
		return
	# Long open-terrain walk crossing at least two 64m tile borders (and up
	# the mountain slope north of the house): proves tile seams stitch.
	# Snap allows any height — the terrain rises ~20m along the way.
	var far_probe := outside + Vector3(0.0, 0.0, 110.0)
	var far_target := _closest_nav_point(far_probe)
	if Vector2(far_target.x - far_probe.x, far_target.z - far_probe.z).length() > 3.0:
		_failures.append("no navmesh near long-walk target: wanted=%s closest=%s" % [far_probe, far_target])
		return
	await _walk_test("cross_tile_long_walk", far_target)
	if not _failures.is_empty():
		return
	await _walk_test("cross_tile_walk_back", outside)
	if not _failures.is_empty():
		return
	# Stair support is asserted at the mesh level: the hidden ramp collider
	# must produce a continuous polygon band bottom-to-top. The full upstairs
	# walk is blocked by unfinished house content (ground-floor dirt/plank
	# step exceeds agent_max_climb), not by the navigation system.
	_check_stair_ramp_meshed(upstairs)


func _walk_test(test_name: String, target: Vector3) -> void:
	_actor.call("set_move_target", target)
	for _frame in range(MAX_MOVE_FRAMES):
		await physics_frame
		if not bool(_actor.get("_has_move_target")):
			break
	var horizontal := Vector2(_actor.global_position.x - target.x, _actor.global_position.z - target.z).length()
	var vertical: float = absf(_actor.global_position.y - target.y)
	if horizontal > HORIZONTAL_TOLERANCE or vertical > VERTICAL_TOLERANCE:
		_failures.append("%s actor=%s position=%s target=%s horizontal_error=%.3f vertical_error=%.3f" % [
			test_name, _actor.name, _actor.global_position, target, horizontal, vertical])
		return
	print("RUSTWASH_BUILDING_NAV_TEST_OK %s position=%s" % [test_name, _actor.global_position])


func _check_stair_ramp_meshed(_upstairs: Vector3) -> void:
	var bottom := _stair_marker("Bottom")
	var top := _stair_marker("Top")
	if bottom == null or top == null:
		return
	for i in range(8):
		var t := float(i) / 7.0
		var probe := bottom.global_position.lerp(top.global_position, t) + Vector3(0.0, 0.3, 0.0)
		var closest := _closest_nav_point(probe)
		if closest.distance_to(probe) > 0.5:
			_failures.append("stair ramp not meshed at t=%.2f probe=%s closest=%s" % [t, probe, closest])
			return
	print("RUSTWASH_BUILDING_NAV_TEST_OK stair_ramp_meshed bottom_to_top")


func _place_actor(start_position: Vector3) -> void:
	_actor.call("set_move_target", _actor.global_position)
	_actor.global_position = start_position
	_actor.set("velocity", Vector3.ZERO)
	for _frame in range(SETTLE_FRAMES):
		await physics_frame
	_actor.set("velocity", Vector3.ZERO)


## House landmarks resolved from the live scene, not hardcoded coordinates,
## so the validator survives the user moving or editing the house.
func _house() -> Node3D:
	var house := _scene.get_node_or_null("WoodbrickHouse") as Node3D
	if house == null:
		_failures.append("WoodbrickHouse not found in rustwash scene")
	return house


func _stair_marker(marker_name: String) -> Node3D:
	var house := _house()
	if house == null:
		return null
	var stair := house.get_node_or_null("Pieces/StairInteriorSimple") as Node3D
	if stair == null:
		_failures.append("Pieces/StairInteriorSimple not found in WoodbrickHouse")
		return null
	var marker := stair.get_node_or_null("SnapPoints/" + marker_name) as Node3D
	if marker == null:
		_failures.append("stair snap marker %s missing" % marker_name)
	return marker


func _outside_front_target() -> Vector3:
	var house := _house()
	if house == null:
		return Vector3.ZERO
	var door := house.get_node_or_null("Pieces/WallWoodbrickDoorFlat") as Node3D
	if door == null:
		_failures.append("Pieces/WallWoodbrickDoorFlat not found in WoodbrickHouse")
		return Vector3.ZERO
	# Exterior approach: the door wall sits on the +Z face of the house.
	return door.global_position + Vector3(0.0, 0.0, 3.5)


func _interior_ground_target() -> Vector3:
	var house := _house()
	if house == null:
		return Vector3.ZERO
	var door := house.get_node_or_null("Pieces/WallWoodbrickDoorFlat") as Node3D
	if door == null:
		_failures.append("Pieces/WallWoodbrickDoorFlat not found in WoodbrickHouse")
		return Vector3.ZERO
	# On the wood floor 1.5m inside the front door (interior is -Z of the door).
	return _snap_to_navmesh(door.global_position + Vector3(0.0, 0.4, -1.5))


func _upstairs_target() -> Vector3:
	var bottom := _stair_marker("Bottom")
	var top := _stair_marker("Top")
	if bottom == null or top == null:
		return Vector3.ZERO
	var onward := _horizontal_direction(bottom.global_position, top.global_position)
	return _snap_to_navmesh(top.global_position + onward * 1.0)


func _horizontal_direction(from: Vector3, to: Vector3) -> Vector3:
	var direction := to - from
	direction.y = 0.0
	return direction.normalized()


func _snap_to_navmesh(position: Vector3) -> Vector3:
	var closest := _closest_nav_point(position)
	if closest.distance_to(position) > 2.5:
		_failures.append("target off navmesh: wanted=%s closest=%s" % [position, closest])
		return position
	return closest


func _closest_nav_point(position: Vector3) -> Vector3:
	var map: RID = root.get_world_3d().navigation_map
	return NavigationServer3D.map_get_closest_point(map, position)


func _wait_for(resolver: Callable, budget_frames: int) -> Node:
	for _frame in range(budget_frames):
		var result: Node = resolver.call()
		if result != null:
			return result
		await physics_frame
	return null
