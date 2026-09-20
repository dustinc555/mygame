extends Node

## Controlled hall regression. Each approach starts independently; a path or
## arrival through the other door is not sufficient. Fixture markers own the
## uneven ground targets; production owns geometry, baking and locomotion.
const BUILDING_PATH := NodePath("Hall")
const ACTOR_PATH := NodePath("PartyMembers/NavigationActor")
const MAX_READY_SECONDS := 120.0
const MAX_WALK_FRAMES := 900
const SETTLE_FRAMES := 60
const ARRIVAL_HORIZONTAL := 0.65
const ARRIVAL_VERTICAL := 0.8
const DOOR_HALF_WIDTH := 1.4
const STOPPED_HORIZONTAL_SPEED := 0.05
const APPROACHES := [
	{"name": "head_on", "marker": "HeadOn"},
	{"name": "side_north", "marker": "SideNorth"},
	{"name": "side_south", "marker": "SideSouth"},
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
var _running := false
var _actor_snapshot: Dictionary = {}


func start(case_filter := "", refresh_tiles := true) -> void:
	if _running:
		push_error("Granary cases are already running")
		return
	_running = true
	completed = false
	report = {}
	_failures.clear()
	_results.clear()
	_patched_tiles.clear()
	_actor = null
	_building = null
	_navigation = null
	_actor_snapshot.clear()
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
		_failures.append("Fixture hall not found")
		_finish()
		return
	_actor = tree.current_scene.get_node_or_null(ACTOR_PATH) as CharacterBody3D
	if _actor == null or not _actor.has_method("set_move_target"):
		_failures.append("Explicit fixture navigation actor not found")
		_finish()
		return
	var interaction = _actor.call("get_interaction")
	var order: int = _actor.call("get_current_order_type")
	if _actor.life_state != NpcRules.LifeState.ALIVE or _actor.is_carried() or (order != interaction.ORDER_TYPE_NONE and order != interaction.ORDER_TYPE_MOVE):
		_failures.append("Fixture navigation actor must be alive, uncarried and idle/moving")
		_finish()
		return
	_actor_snapshot = {"transform": _actor.global_transform,
		"target": _actor.call("get_move_target"), "had_target": _actor.call("has_move_target"),
		"velocity": _actor.velocity, "player_order": _actor.call("has_active_player_order")}
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
	for coord in tile_revisions:
		var tile = _navigation._tiles[coord]
		if tile.installed_revision != tile.requested_revision:
			_failures.append("Local tile refresh did not install its requested revision: %s" % coord)
	var tested := 0
	for side in [-1.0, 1.0]:
		var entrance := "west" if side < 0.0 else "east"
		var markers := _building.get_node("Approaches/" + ("West" if side < 0.0 else "East"))
		var door_plane := _building.to_local(markers.get_node("DoorPlane").global_position)
		for approach in APPROACHES:
			var outside := _building.to_local(markers.get_node(approach["marker"]).global_position)
			var inside := _building.to_local(markers.get_node("Inside").global_position)
			for direction in ["enter", "exit"]:
				var case_id := "%s_%s_%s" % [entrance, approach["name"], direction]
				if not _case_filter.is_empty() and case_id != _case_filter:
					continue
				var start_position := (outside if direction == "enter" else inside) + Vector3.UP
				var target := inside if direction == "enter" else outside
				await _walk(case_id, start_position, target, side, direction == "enter", door_plane)
				tested += 1
	if tested == 0:
		_failures.append("Case filter selected no movement cases: %s" % _case_filter)
	if tested != (12 if _case_filter.is_empty() else 1):
		_failures.append("Not all selected cases completed")
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


func _walk(case_id: String, local_start: Vector3, local_target: Vector3, side: float, entering: bool, door_plane: Vector3) -> void:
	active_case = case_id
	_actor.call("stop_movement")
	_actor.global_position = _building.to_global(local_start)
	_actor.set("velocity", Vector3.ZERO)
	for frame in range(SETTLE_FRAMES):
		await get_tree().physics_frame
	var target := _building.to_global(local_target)
	var previous := _building.to_local(_actor.global_position)
	var settled_start := previous
	var started_on_floor := _actor.is_on_floor()
	var crossed_entrance := false
	_actor.call("set_move_target", target)
	var frames := 0
	while frames < MAX_WALK_FRAMES:
		await get_tree().physics_frame
		frames += 1
		var current := _building.to_local(_actor.global_position)
		var old_outside := (previous.x - door_plane.x) * side > 0.0
		var new_outside := (current.x - door_plane.x) * side > 0.0
		if old_outside != new_outside and new_outside != entering and absf(current.z - door_plane.z) < DOOR_HALF_WIDTH:
			crossed_entrance = true
		previous = current
		# Door interaction may temporarily clear a movement target. Only the
		# final physical arrival and stopped actuator can finish a route.
		var delta := _actor.global_position - target
		if not bool(_actor.call("has_move_target")) and Vector2(delta.x, delta.z).length() <= ARRIVAL_HORIZONTAL and absf(delta.y) <= ARRIVAL_VERTICAL and Vector2(_actor.velocity.x, _actor.velocity.z).length() <= STOPPED_HORIZONTAL_SPEED:
			break
	var end := _actor.global_position
	var horizontal := Vector2(end.x - target.x, end.z - target.z).length()
	var vertical := absf(end.y - target.y)
	var still_moving: bool = _actor.call("has_move_target")
	var horizontal_speed := Vector2(_actor.velocity.x, _actor.velocity.z).length()
	var passed := started_on_floor and horizontal <= ARRIVAL_HORIZONTAL and vertical <= ARRIVAL_VERTICAL and crossed_entrance and not still_moving and horizontal_speed <= STOPPED_HORIZONTAL_SPEED
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
		"still_moving": still_moving, "horizontal_speed": horizontal_speed, "started_on_floor": started_on_floor, "contacts": contacts,
		"velocity": str(_actor.velocity), "path_finished": agent.is_navigation_finished(),
		"path_end_local": str(_building.to_local(agent.get_final_position())),
		"waypoint_local": waypoint}
	_results.append(result)
	print("GRANARY_WALK ", JSON.stringify(result))
	if not passed:
		_failures.append("%s failed: %s" % [case_id, JSON.stringify(result)])


func _finish() -> void:
	# One cleanup boundary, including timeout after the local tile refresh.
	var cleanup := {"actor_restored": false}
	if is_instance_valid(_actor) and not _actor_snapshot.is_empty():
		_actor.call("stop_movement")
		_actor.global_transform = _actor_snapshot["transform"]
		_actor.velocity = _actor_snapshot["velocity"]
		if _actor_snapshot["had_target"]:
			_actor.call("set_move_target", _actor_snapshot["target"], _actor_snapshot["player_order"])
		cleanup["actor_restored"] = _actor.global_transform == _actor_snapshot["transform"] and _actor.velocity == _actor_snapshot["velocity"] and _actor.call("has_move_target") == _actor_snapshot["had_target"] and _actor.call("has_active_player_order") == _actor_snapshot["player_order"]
		if _actor_snapshot["had_target"]:
			cleanup["actor_restored"] = cleanup["actor_restored"] and _actor.call("get_move_target") == _actor_snapshot["target"]
		if not cleanup["actor_restored"]:
			_failures.append("Helper cleanup must restore actor transform, velocity and prior movement order")
	_actor_snapshot.clear()
	_running = false
	active_case = ""
	report = {"passed": _failures.is_empty(), "cases": _results, "failures": _failures, "patched_tiles": _patched_tiles,
		"total_tiles": _navigation._tiles.size() if is_instance_valid(_navigation) else 0, "cleanup": cleanup}.duplicate(true)
	completed = true
	finished.emit(report)
