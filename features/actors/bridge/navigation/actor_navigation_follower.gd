extends NavigationAgent3D

## The actor's actual NavigationAgent3D, not a second navigation node or config.
## Owns transient target/path, safe-velocity and stuck/repath state. The parent
## CharacterBody3D supplies the existing exported settings and drives this node
## before/after physical movement; no WorldActor dependency or separate tick.
## Keep the direct child name NavigationAgent3D: quadbot downed handling uses it.
signal movement_finished(reached: bool)
signal movement_blocked

const MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED := 0.0025
const TARGET_CHANGE_DISTANCE_SQUARED := 0.0025
const QUERY_GRACE_SECONDS := 0.25
const RECOVERY_WAYPOINT_DISTANCE := 0.15

var move_target := Vector3.ZERO
var has_move_target := false
var safe_velocity := Vector3.ZERO
var has_safe_velocity := false
var arrival_distance_override := -1.0

var _body: CharacterBody3D
var _target_synced := false
var _synced_target := Vector3.ZERO
var _query_grace_remaining := 0.0
var _zero_waypoint_blocked := false
var _stuck_origin := Vector3.ZERO
var _stuck_target_distance := INF
var _stuck_seconds := 0.0
var _stuck_repath_attempts := 0
var _progress_path := PackedVector3Array()
var _remaining_lengths := PackedFloat32Array()
var _recovery_path_index := -1
var _passage_recovery := true
var _movement_route: RefCounted
var _route_owner: WeakRef
var _route_target := Vector3.INF
var _route_retry := 0
var _query_jobs: RefCounted
var _query_ticket := 0
var _query_map: RID
var _query_iteration := -1
var _query_layers := 0
var _query_target := Vector3.INF
var _query_start := Vector3.ZERO
var _path_index := 0
var _async_path := PackedVector3Array()


func _init(body: CharacterBody3D) -> void:
	_body = body
	name = "NavigationAgent3D"
	velocity_computed.connect(_on_velocity_computed)
	path_changed.connect(_cache_progress_path)


func configure() -> void:
	# Called from the actor movement setup, after subclass _ready defaults.
	# Settings remain authored on the actor; there is no copied defaults resource.
	radius = _body.navigation_agent_radius
	height = _body.navigation_agent_height
	path_desired_distance = _body.navigation_path_desired_distance
	target_desired_distance = _body.navigation_target_desired_distance
	path_height_offset = _body.navigation_path_height_offset
	avoidance_enabled = _body.navigation_avoidance_enabled
	neighbor_distance = _body.navigation_neighbor_distance
	max_neighbors = _body.navigation_max_neighbors
	max_speed = _body.move_speed
	time_horizon_agents = _body.navigation_time_horizon_agents
	keep_y_velocity = false
	simplify_path = false


func _enter_tree() -> void:
	_cancel_query()
	# Native map/path state is disposable across tree removal/re-entry.
	_progress_path.clear()
	_remaining_lengths.clear()
	_recovery_path_index = -1
	_target_synced = false
	_query_grace_remaining = QUERY_GRACE_SECONDS if has_move_target else 0.0
	_zero_waypoint_blocked = false
	has_safe_velocity = false
	_reset_stuck_tracking()


func set_move_target(target: Vector3, arrival_distance := -1.0, passage_recovery := true, continue_order := false) -> void:
	var target_changed := not has_move_target or move_target.distance_squared_to(target) > TARGET_CHANGE_DISTANCE_SQUARED or _passage_recovery != passage_recovery
	var continuing := continue_order and has_move_target and _passage_recovery == passage_recovery
	_passage_recovery = passage_recovery
	arrival_distance_override = arrival_distance
	move_target = target
	has_move_target = true
	if not target_changed:
		return
	# Held updates keep useful in-flight work alive. Fresh commands and held
	# reversals cancel it, but retain the last geometrically valid route.
	if not continuing or not _query_agrees_with_target():
		_cancel_pending_query()
	_route_target = Vector3.INF
	_route_retry = 0
	if not continuing:
		_recovery_path_index = -1
	_target_synced = false
	_query_grace_remaining = QUERY_GRACE_SECONDS
	_zero_waypoint_blocked = false
	has_safe_velocity = false
	if continuing:
		# A moving goal is not physical progress by this body. Compare the new
		# goal against the same origin without restarting the recovery deadline.
		_stuck_target_distance = _get_stuck_target_distance(_stuck_origin)
	else:
		_stuck_repath_attempts = 0
		_reset_stuck_tracking()


func clear_move_target() -> void:
	_cancel_query()
	_recovery_path_index = -1
	has_move_target = false
	arrival_distance_override = -1.0
	_target_synced = false
	_query_grace_remaining = 0.0
	_zero_waypoint_blocked = false
	has_safe_velocity = false
	_reset_stuck_tracking()


func get_move_direction(delta: float) -> Vector3:
	if _is_close_to_move_target():
		_finish_movement(true)
		return Vector3.ZERO
	if _body.use_navigation_pathing and _use_threaded_path():
		return _get_threaded_move_direction()
	if _query_jobs != null:
		_cancel_query()
		# Native navigation has not seen worker-owned destinations.
		_target_synced = false
	if _body.use_navigation_pathing:
		_refresh_movement_route()
	if _body.use_navigation_pathing and NavigationServer3D.map_get_iteration_id(get_navigation_map()) > 0:
		return _get_navigation_move_direction(delta)
	_query_grace_remaining = maxf(0.0, _query_grace_remaining - delta)
	if _query_grace_remaining <= 0.0:
		_finish_movement(false)
	return Vector3.ZERO


func _get_navigation_move_direction(delta: float) -> Vector3:
	_zero_waypoint_blocked = false
	_sync_target_if_needed()
	if _recovery_path_index >= 0:
		# Keep the native query current, but advance recovery waypoints in XZ.
		# A smaller native 3D tolerance can never be reached when the path's
		# height offset differs from the physical body's origin on a ramp.
		get_next_path_position()
		if _is_final_position_close_enough():
			return _get_recovery_move_direction()
	if is_navigation_finished():
		if _is_close_to_move_target():
			_finish_movement(true)
		elif _is_final_position_close_enough():
			return _get_point_move_direction(get_final_position())
		else:
			if _expand_movement_route():
				return Vector3.ZERO
			_finish_movement(false)
		return Vector3.ZERO
	var next_path_position := get_next_path_position()
	if not _is_final_position_close_enough():
		if _expand_movement_route():
			return Vector3.ZERO
		_query_grace_remaining = maxf(0.0, _query_grace_remaining - delta)
		if _query_grace_remaining <= 0.0:
			_finish_movement(false)
		return Vector3.ZERO
	return _get_path_move_direction(next_path_position)


func _exit_tree() -> void:
	_cancel_query()
	_release_movement_route()
	_route_owner = null
	_route_target = Vector3.INF


func _release_movement_route() -> void:
	if _movement_route == null:
		return
	# Change the native reference before releasing the last RID owner.
	if get_navigation_map() == _movement_route.map:
		set_navigation_map(_body.get_world_3d().navigation_map)
	_movement_route = null
	_target_synced = false


func _refresh_movement_route() -> void:
	var source := _body.get_world_3d().navigation_map
	var owner = _route_owner.get_ref() if _route_owner != null else null
	var changed := _route_target != move_target
	if _movement_route != null:
		if get_navigation_map() != _movement_route.map:
			# An explicit external override wins; do not silently take it back.
			_release_movement_route()
			_route_target = move_target
			return
		if not is_instance_valid(owner) or not owner.is_inside_tree():
			_release_movement_route()
			changed = true
		elif _movement_route.source_map != source or _movement_route.iteration != NavigationServer3D.map_get_iteration_id(source):
			changed = true
			_route_retry = 0
	if not changed:
		return
	_route_target = move_target
	if not is_instance_valid(owner):
		owner = get_tree().get_first_node_in_group("world_navigation_controller")
		_route_owner = weakref(owner) if owner != null else null
	# Authored/foreign maps keep their original native behavior.
	if owner == null or (_movement_route == null and get_navigation_map() != source):
		return
	if owner.settings != null and owner.get_viewport().find_world_3d().navigation_map == source:
		path_search_max_polygons = maxi(1, owner.settings.movement_path_max_polygons)
	var route = owner.get_movement_route(source, _body.global_position, move_target, _route_retry)
	if route == null:
		_release_movement_route()
		return
	if route == _movement_route:
		return
	set_navigation_map(route.map)
	# RVO is world-wide even though pathfinding uses a shared local view.
	# Otherwise actors using different routes would not avoid one another.
	NavigationServer3D.agent_set_map(get_rid(), source)
	_movement_route = route
	_target_synced = false


func _expand_movement_route() -> bool:
	if _movement_route == null or _route_retry >= 2:
		return false
	_route_retry += 1
	_route_target = Vector3.INF
	_refresh_movement_route()
	return true


func _get_recovery_move_direction() -> Vector3:
	while _recovery_path_index < _progress_path.size():
		var point := _progress_path[_recovery_path_index]
		var offset := Vector2(point.x - _body.global_position.x, point.z - _body.global_position.z)
		if offset.length() > RECOVERY_WAYPOINT_DISTANCE:
			return _get_point_move_direction(point)
		_recovery_path_index += 1
	return _get_point_move_direction(move_target)


func _get_path_move_direction(next_path_position: Vector3) -> Vector3:
	var direct_direction := _get_point_move_direction(next_path_position)
	if direct_direction.length_squared() > 0.0001:
		return direct_direction
	var path := get_current_navigation_path()
	var path_index := maxi(0, get_current_navigation_path_index())
	for index in range(path_index, path.size()):
		var to_point := path[index] - _body.global_position
		to_point.y = 0.0
		if to_point.length_squared() > MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED:
			return to_point.normalized()
	_zero_waypoint_blocked = true
	return Vector3.ZERO


func _get_point_move_direction(point: Vector3) -> Vector3:
	var to_point := point - _body.global_position
	to_point.y = 0.0
	if to_point.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_point.normalized()


func _sync_target_if_needed() -> void:
	target_desired_distance = _arrival_distance()
	if _target_synced and _synced_target.distance_squared_to(move_target) <= TARGET_CHANGE_DISTANCE_SQUARED:
		return
	target_position = move_target
	_synced_target = move_target
	_target_synced = true
	_query_grace_remaining = QUERY_GRACE_SECONDS
	_stuck_target_distance = _get_stuck_target_distance(_stuck_origin)


func _is_close_to_move_target() -> bool:
	var to_target := move_target - _body.global_position
	return Vector2(to_target.x, to_target.z).length() <= _arrival_distance() and absf(to_target.y) <= _body.move_target_vertical_tolerance


func _arrival_distance() -> float:
	return arrival_distance_override if arrival_distance_override >= 0.0 else _body.navigation_target_desired_distance


func _is_final_position_close_enough() -> bool:
	var final := _async_path[-1] if _query_jobs != null and not _async_path.is_empty() else get_final_position()
	return _is_endpoint_close_enough(final)


func _is_endpoint_close_enough(endpoint: Vector3) -> bool:
	return _endpoint_reaches_target(endpoint, move_target)


func _endpoint_reaches_target(endpoint: Vector3, target: Vector3) -> bool:
	var to_target := target - endpoint
	return Vector2(to_target.x, to_target.z).length() <= _body.navigation_unreachable_tolerance and absf(to_target.y) <= _body.navigation_reachable_vertical_tolerance


func update_stuck_state(delta: float, desired_direction: Vector3) -> void:
	if not has_move_target or desired_direction.length_squared() <= 0.0001:
		if _zero_waypoint_blocked:
			_stuck_seconds += delta
			if _stuck_seconds >= _body.stuck_check_seconds:
				_handle_stuck()
			return
		_reset_stuck_tracking()
		return
	if _has_made_stuck_progress():
		_reset_stuck_tracking()
		_stuck_repath_attempts = 0
		return
	_stuck_seconds += delta
	if _stuck_seconds < _body.stuck_check_seconds:
		return
	_handle_stuck()


func _reset_stuck_tracking() -> void:
	# Commands can be assigned before the actor is mounted in a scene.
	_stuck_origin = _body.global_position if _body.is_inside_tree() else _body.position
	_stuck_target_distance = _get_stuck_target_distance(_stuck_origin)
	_stuck_seconds = 0.0


func _cache_progress_path() -> void:
	if _query_jobs != null:
		return
	_set_progress_path(get_current_navigation_path())


func _set_progress_path(path: PackedVector3Array) -> void:
	if not _passage_recovery:
		return
	_progress_path = path
	if _recovery_path_index >= 0:
		_recovery_path_index = 0
	_remaining_lengths.resize(_progress_path.size())
	var remaining := 0.0
	for index in range(_progress_path.size() - 1, -1, -1):
		_remaining_lengths[index] = remaining
		if index > 0:
			var segment := _progress_path[index] - _progress_path[index - 1]
			remaining += Vector2(segment.x, segment.z).length()
	# Repath changes the route length, not whether the actor actually advanced.
	# Rebase from the last physical progress, keeping its clock and retry count.
	_stuck_target_distance = _get_stuck_target_distance(_stuck_origin)


func _get_stuck_target_distance(from: Vector3) -> float:
	if not has_move_target:
		return INF
	# Remaining route length, not displacement: lateral oscillation is not
	# advancement, and legitimate detours may lead away from the final target.
	var index := _path_index if _query_jobs != null else get_current_navigation_path_index()
	if _query_jobs == null and _recovery_path_index >= 0:
		index = _recovery_path_index
	if _passage_recovery and _target_synced and index >= 0 and index < _progress_path.size():
		return Vector2(from.x - _progress_path[index].x, from.z - _progress_path[index].z).length() + _remaining_lengths[index]
	return Vector2(from.x - move_target.x, from.z - move_target.z).length()


func _has_made_stuck_progress() -> bool:
	var position := _body.global_position
	# Tactical repositioning deliberately circles a moving opponent. Preserve
	# its displacement-based recovery; passage recovery is for travel orders.
	if not _passage_recovery and Vector2(position.x - _stuck_origin.x, position.z - _stuck_origin.z).length() >= _body.stuck_min_progress:
		return true
	var target_distance := _get_stuck_target_distance(position)
	return _stuck_target_distance < INF and target_distance <= _stuck_target_distance - _body.stuck_min_progress


func _handle_stuck() -> void:
	if _is_close_to_move_target():
		_finish_movement(true)
		return
	if _passage_recovery:
		movement_blocked.emit()
	if _query_jobs != null and not _target_synced:
		# Give a fresh command's replacement a chance, even with retries disabled.
		# Continued goals share the retry budget: a moving opponent can keep
		# every accepted path slightly behind without the body ever advancing.
		if _stuck_repath_attempts >= maxi(1, _body.stuck_repath_attempt_limit):
			_finish_movement(false)
			return
		_async_path.clear()
		_path_index = 0
		_stuck_repath_attempts += 1
		_reset_stuck_tracking()
		return
	if _is_final_position_close_enough() and _stuck_repath_attempts < _body.stuck_repath_attempt_limit:
		# Crowd avoidance may push the body beside a jamb. Ordinary waypoint
		# tolerance can then skip the corner on every retry and hit the wall again.
		_recovery_path_index = 0 if _passage_recovery else -1
		_target_synced = false
		if _query_jobs != null:
			_cancel_query()
		_stuck_repath_attempts += 1
		_reset_stuck_tracking()
		return
	_finish_movement(false)


func _finish_movement(reached: bool) -> void:
	clear_move_target()
	# WorldActor observes completion to release order authority and submit an RVO
	# stop. This component never calls back into its parent's gameplay methods.
	movement_finished.emit(reached)


func _on_velocity_computed(value: Vector3) -> void:
	safe_velocity = value
	has_safe_velocity = true


func _cancel_query() -> void:
	_cancel_pending_query()
	_query_jobs = null
	_async_path.clear()
	_path_index = 0
	_query_iteration = -1


func _cancel_pending_query() -> void:
	if _query_jobs != null:
		_query_jobs.cancel(str(get_instance_id()))
	_query_ticket = 0
	_query_target = Vector3.INF


func _query_agrees_with_target() -> bool:
	if _query_ticket <= 0:
		return true
	var old_direction := _query_target - _body.global_position
	var new_direction := move_target - _body.global_position
	return Vector2(old_direction.x, old_direction.z).dot(Vector2(new_direction.x, new_direction.z)) > 0.0 and absf(_query_target.y - move_target.y) <= _body.move_target_vertical_tolerance


func _use_threaded_path() -> bool:
	var source := _body.get_world_3d().navigation_map
	# Explicit foreign-map overrides retain native semantics.
	if _movement_route == null and get_navigation_map() != source:
		return false
	var owner = _route_owner.get_ref() if _route_owner != null else null
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		owner = get_tree().get_first_node_in_group("world_navigation_controller")
		_route_owner = weakref(owner) if owner != null else null
	if owner == null or not owner.supports_threaded_queries(source):
		return false
	if _movement_route != null:
		_release_movement_route()
	var iteration := NavigationServer3D.map_get_iteration_id(source)
	if iteration == 0:
		_cancel_query()
		return true # Waiting for synchronization is not a failed command.
	if _query_jobs == null or _query_map != source or _query_iteration != iteration or _query_layers != navigation_layers:
		_cancel_query()
		_query_map = source
		_query_iteration = iteration
		_query_layers = navigation_layers
	# Consume before submitting the next held update, including results published
	# between idle input and this physics tick. New explicit commands cancel first.
	if not _consume_query_result():
		return true
	if _query_ticket == 0 and (_query_jobs == null or _query_target.distance_squared_to(move_target) > TARGET_CHANGE_DISTANCE_SQUARED):
		var player_order := _body.has_method("has_active_player_order") and bool(_body.call("has_active_player_order"))
		var ticket: int = owner.request_paths(str(get_instance_id()), _body.get_world_3d(), source, _body.global_position, PackedVector3Array([move_target]), navigation_layers, player_order, true)
		if ticket > 0:
			_query_ticket = ticket
			_query_jobs = owner.query_jobs
			_query_target = move_target
			_query_start = _body.global_position
	return true


func _consume_query_result() -> bool:
	if _query_jobs == null:
		return true
	if _query_ticket > 0:
		var result: Dictionary = _query_jobs.take(str(get_instance_id()), _query_ticket)
		if not result.is_empty():
			_query_ticket = 0
			if result.map != _query_map or result.iteration != NavigationServer3D.map_get_iteration_id(_query_map):
				_cancel_query()
				return false
			var path: PackedVector3Array = result.paths[0]
			var latest := _query_target.distance_squared_to(move_target) <= TARGET_CHANGE_DISTANCE_SQUARED
			if path.is_empty() or not _endpoint_reaches_target(path[-1], _query_target):
				if latest:
					_finish_movement(false)
					return false
				# An earlier held destination failing does not fail the newest one.
				_query_target = Vector3.INF
				return true
			var start_index := _replacement_path_index(path)
			if start_index < 0:
				# Brake before retrying from here. Continuing the old route can
				# outrun every replacement; joining it directly can cut a corner.
				_async_path.clear()
				_path_index = 0
				_target_synced = false
				_query_target = Vector3.INF
			else:
				_async_path = path
				_path_index = start_index
				_target_synced = latest
				_set_progress_path(_async_path)
	return true


func _get_threaded_move_direction() -> Vector3:
	_zero_waypoint_blocked = false
	if _query_jobs == null:
		return Vector3.ZERO
	if _async_path.is_empty():
		return Vector3.ZERO
	var tolerance := RECOVERY_WAYPOINT_DISTANCE if _recovery_path_index >= 0 else path_desired_distance
	while _path_index < _async_path.size():
		var point := _async_path[_path_index]
		var offset := point - _body.global_position
		# Native paths lie on the floor; physical body origin and ramp support
		# need not share their Y. Collision, not waypoints, owns vertical motion.
		if Vector2(offset.x, offset.z).length() > tolerance:
			return _get_point_move_direction(point)
		_path_index += 1
	# A retained route is safe only up to its own end, not toward the new goal.
	if not _target_synced:
		return Vector3.ZERO
	return _get_point_move_direction(move_target)


func _replacement_path_index(path: PackedVector3Array) -> int:
	var tolerance := RECOVERY_WAYPOINT_DISTANCE if _recovery_path_index >= 0 else path_desired_distance
	var travelled := _body.global_position - _query_start
	if Vector2(travelled.x, travelled.z).length() <= tolerance and absf(travelled.y) <= _body.move_target_vertical_tolerance:
		return 0
	if path.size() < 2:
		return -1
	# The actor may have travelled along the first segment while the worker ran.
	# Skip its old start, never a later corner or a nearby segment on another floor.
	var floor_position := _body.global_position
	floor_position.y -= _query_start.y - path[0].y
	var closest := Geometry3D.get_closest_point_to_segment(floor_position, path[0], path[1])
	var offset := floor_position - closest
	if Vector2(offset.x, offset.z).length() <= tolerance and absf(offset.y) <= _body.move_target_vertical_tolerance:
		return 1
	return -1
