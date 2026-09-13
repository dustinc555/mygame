extends Node

## Exact World1 granary regression. Each approach starts independently; a path
## or arrival through the other door is not sufficient. Shared by the headless
## validator and live-editor verification, so both exercise the same cases.
const BUILDING_PATH := NodePath("RustwashBasin/Towns/Canyon/Granary/BuildingSlot/CurrentBuilding")
const MAX_READY_SECONDS := 120.0
const MAX_WALK_FRAMES := 900
const SETTLE_FRAMES := 60
const ARRIVAL_HORIZONTAL := 0.65
const ARRIVAL_VERTICAL := 0.8
const DOOR_PLANE_X := 9.8
const APPROACHES := [
	{"name": "head_on", "outside": Vector3(16.8, 1.0, -1.0)},
	{"name": "side_north", "outside": Vector3(10.9, 1.0, -4.5)},
	{"name": "side_south", "outside": Vector3(10.9, 1.0, 3.5)},
]

signal finished(result: Dictionary)

var completed := false
var report: Dictionary = {}
var active_case := ""
var _failures: Array[String] = []
var _results: Array[Dictionary] = []
var _patched_tiles: Array[String] = []
var _actor: CharacterBody3D
var _building: Node3D
var _navigation: Node
var _case_filter := ""
var _refresh_tiles := true


func start(case_filter := "", refresh_tiles := true) -> void:
	_case_filter = case_filter
	_refresh_tiles = refresh_tiles
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	if not await _wait_ready():
		_finish()
		return
	_building = tree.current_scene.get_node_or_null(BUILDING_PATH) as Node3D
	if _building == null:
		_failures.append("Production granary not found")
		_finish()
		return
	for candidate in tree.get_nodes_in_group("party_member"):
		if candidate is CharacterBody3D and candidate.has_method("set_move_target"):
			if _actor == null or str(candidate.get("member_name")) == "Mira":
				_actor = candidate
	if _actor == null:
		_failures.append("No production party actor")
		_finish()
		return
	var original_transform := _actor.global_transform
	var original_target: Vector3 = _actor.call("get_move_target")
	var had_target: bool = _actor.call("has_move_target")
	var original_velocity: Vector3 = _actor.get("velocity")
	var tile_revisions := {}
	for coord in _navigation._tiles:
		tile_revisions[coord] = _navigation._tiles[coord].requested_revision
	for entrance in ["WestDoorSteps", "EastDoorSteps"]:
		var stairs := _building.get_node("Pieces/" + entrance)
		var barriers := stairs.get_node("NavShapingRails") as StaticBody3D
		var authored := barriers.find_children("*", "CollisionShape3D", true, false).size()
		var registered := PhysicsServer3D.body_get_shape_count(barriers.get_rid())
		if authored == 0 or registered != authored:
			_failures.append("%s barriers: authored=%d registered=%d" % [entrance, authored, registered])
		if _refresh_tiles:
			# The composite stair root is not a collider. Use the real registered
			# bodies' bounds with the public local-change API, not a world rebake.
			for body in stairs.find_children("*", "StaticBody3D", true, false):
				var bounds: AABB = _navigation.call("_static_body_world_bounds", body)
				_navigation.call("notify_geometry_changed", bounds, bounds)
	if _refresh_tiles:
		for coord in tile_revisions:
			if _navigation._tiles[coord].requested_revision != tile_revisions[coord]:
				_patched_tiles.append(str(coord))
		if _patched_tiles.is_empty() or _patched_tiles.size() >= tile_revisions.size():
			_failures.append("Granary refresh must dirty only local tiles, not the entire world")
	if not await _wait_ready():
		_finish()
		return
	var tested := 0
	for side in [-1.0, 1.0]:
		var entrance := "west" if side < 0.0 else "east"
		for approach in APPROACHES:
			var outside: Vector3 = approach["outside"]
			outside.x *= side
			var inside := Vector3(7.5 * side, 0.2, -1.0)
			for direction in ["enter", "exit"]:
				var case_id := "%s_%s_%s" % [entrance, approach["name"], direction]
				if not _case_filter.is_empty() and case_id != _case_filter:
					continue
				var start_position := outside if direction == "enter" else inside + Vector3.UP
				var target := inside if direction == "enter" else outside - Vector3.UP
				await _walk(case_id, start_position, target, side, direction == "enter")
				tested += 1
	if tested == 0:
		_failures.append("Case filter selected no movement cases: %s" % _case_filter)
	if is_instance_valid(_actor):
		_actor.call("stop_movement")
		_actor.global_transform = original_transform
		_actor.set("velocity", original_velocity)
		if had_target:
			_actor.call("set_move_target", original_target)
	_finish()


func _wait_ready() -> bool:
	var deadline := Time.get_ticks_msec() + int(MAX_READY_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		_navigation = get_tree().get_first_node_in_group("world_navigation_controller")
		if _navigation == null or get_tree().paused:
			continue
		if _navigation.call("is_initial_navigation_pending") or not _navigation.call("is_idle"):
			continue
		var map: RID = get_viewport().find_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			# Tile installation and NavigationServer synchronization are separate.
			await get_tree().physics_frame
			await get_tree().physics_frame
			return true
	_failures.append("Navigation did not become ready within the time budget")
	return false


func _walk(case_id: String, local_start: Vector3, local_target: Vector3, side: float, entering: bool) -> void:
	active_case = case_id
	_actor.call("stop_movement")
	_actor.global_position = _building.to_global(local_start)
	_actor.set("velocity", Vector3.ZERO)
	for frame in range(SETTLE_FRAMES):
		await get_tree().physics_frame
	var target := _building.to_global(local_target)
	if not entering:
		# Outside terrain height differs between the two entrances. Aim at its
		# real floor rather than the building's local Y=0 plane in midair.
		var map := get_viewport().find_world_3d().navigation_map
		target = NavigationServer3D.map_get_closest_point(map, target)
	var previous := _building.to_local(_actor.global_position)
	var settled_start := previous
	var crossed_entrance := false
	_actor.call("set_move_target", target)
	var frames := 0
	while frames < MAX_WALK_FRAMES:
		await get_tree().physics_frame
		frames += 1
		var current := _building.to_local(_actor.global_position)
		var old_outside := previous.x * side > DOOR_PLANE_X
		var new_outside := current.x * side > DOOR_PLANE_X
		if old_outside != new_outside and new_outside != entering and absf(current.z + 1.0) < 1.4:
			crossed_entrance = true
		previous = current
		if not bool(_actor.call("has_move_target")):
			break
	var end := _actor.global_position
	var horizontal := Vector2(end.x - target.x, end.z - target.z).length()
	var vertical := absf(end.y - target.y)
	var still_moving: bool = _actor.call("has_move_target")
	var passed := horizontal <= ARRIVAL_HORIZONTAL and vertical <= ARRIVAL_VERTICAL and crossed_entrance and not still_moving
	var agent := _actor.get_node("NavigationAgent3D") as NavigationAgent3D
	var path := agent.get_current_navigation_path()
	var path_index := agent.get_current_navigation_path_index()
	var waypoint := "none"
	if path_index >= 0 and path_index < path.size():
		waypoint = str(_building.to_local(path[path_index]))
	var contacts: Array[Dictionary] = []
	for index in _actor.get_slide_collision_count():
		var collision: KinematicCollision3D = _actor.get_slide_collision(index)
		var collider := collision.get_collider() as Node
		contacts.append({"collider": str(collider.get_path()) if is_instance_valid(collider) else "freed", "normal": str(collision.get_normal())})
	var result := {"case": case_id, "passed": passed, "actor": str(_actor.name), "frames": frames,
		"start_local": str(settled_start), "target_local": str(_building.to_local(target)),
		"end_local": str(_building.to_local(end)), "horizontal_error": horizontal,
		"vertical_error": vertical, "crossed_requested_entrance": crossed_entrance,
		"still_moving": still_moving, "contacts": contacts,
		"velocity": str(_actor.velocity), "path_finished": agent.is_navigation_finished(),
		"path_end_local": str(_building.to_local(agent.get_final_position())),
		"waypoint_local": waypoint}
	_results.append(result)
	print("GRANARY_WALK ", JSON.stringify(result))
	if not passed:
		_failures.append("%s failed: %s" % [case_id, JSON.stringify(result)])


func _finish() -> void:
	active_case = ""
	report = {"passed": _failures.is_empty(), "cases": _results, "failures": _failures, "patched_tiles": _patched_tiles}
	completed = true
	finished.emit(report)
