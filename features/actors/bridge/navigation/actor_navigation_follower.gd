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
	# Native map/path state is disposable across tree removal/re-entry.
	_progress_path.clear()
	_remaining_lengths.clear()
	_recovery_path_index = -1
	_target_synced = false
	_query_grace_remaining = QUERY_GRACE_SECONDS if has_move_target else 0.0
	_zero_waypoint_blocked = false
	has_safe_velocity = false
	_reset_stuck_tracking()


func set_move_target(target: Vector3, arrival_distance := -1.0, passage_recovery := true) -> void:
	var target_changed := not has_move_target or move_target.distance_squared_to(target) > TARGET_CHANGE_DISTANCE_SQUARED or _passage_recovery != passage_recovery
	_passage_recovery = passage_recovery
	arrival_distance_override = arrival_distance
	move_target = target
	has_move_target = true
	if not target_changed:
		return
	_recovery_path_index = -1
	_target_synced = false
	_query_grace_remaining = QUERY_GRACE_SECONDS
	_zero_waypoint_blocked = false
	has_safe_velocity = false
	_stuck_repath_attempts = 0
	_reset_stuck_tracking()


func clear_move_target() -> void:
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
			_finish_movement(false)
		return Vector3.ZERO
	var next_path_position := get_next_path_position()
	if not _is_final_position_close_enough():
		_query_grace_remaining = maxf(0.0, _query_grace_remaining - delta)
		if _query_grace_remaining <= 0.0:
			_finish_movement(false)
		return Vector3.ZERO
	return _get_path_move_direction(next_path_position)


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
	_reset_stuck_tracking()


func _is_close_to_move_target() -> bool:
	var to_target := move_target - _body.global_position
	return Vector2(to_target.x, to_target.z).length() <= _arrival_distance() and absf(to_target.y) <= _body.move_target_vertical_tolerance


func _arrival_distance() -> float:
	return arrival_distance_override if arrival_distance_override >= 0.0 else _body.navigation_target_desired_distance


func _is_final_position_close_enough() -> bool:
	var to_target := move_target - get_final_position()
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
	if not _passage_recovery:
		return
	_progress_path = get_current_navigation_path()
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
	# Retain the retry count; just establish a comparable distance baseline.
	_reset_stuck_tracking()


func _get_stuck_target_distance(from: Vector3) -> float:
	if not has_move_target:
		return INF
	# Remaining route length, not displacement: lateral oscillation is not
	# advancement, and legitimate detours may lead away from the final target.
	var index := get_current_navigation_path_index()
	if _recovery_path_index >= 0:
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
	if _is_final_position_close_enough() and _stuck_repath_attempts < _body.stuck_repath_attempt_limit:
		# Crowd avoidance may push the body beside a jamb. Ordinary waypoint
		# tolerance can then skip the corner on every retry and hit the wall again.
		_recovery_path_index = 0 if _passage_recovery else -1
		_target_synced = false
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
