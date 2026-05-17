extends CharacterBody3D

class_name WorldActor

@export var move_speed := 3.2
@export var acceleration := 10.0
@export var floor_snap_distance := 0.9
@export var max_walkable_slope_degrees := 55.0
@export var move_target_vertical_tolerance := 0.75

@export var use_navigation_pathing := true
@export var navigation_avoidance_enabled := true
@export var navigation_agent_radius := 0.45
@export var navigation_agent_height := 2.0
@export var navigation_path_desired_distance := 0.9
@export var navigation_target_desired_distance := 0.6
@export var navigation_path_height_offset := 0.9
@export var navigation_unreachable_tolerance := 1.4
@export var navigation_vertical_link_search_radius := 10.0
@export var navigation_neighbor_distance := 2.4
@export var navigation_max_neighbors := 8
@export var navigation_time_horizon_agents := 0.7
@export var stuck_check_seconds := 2.0
@export var stuck_min_progress := 0.12
@export var navigation_recovery_detour_distance := 1.25
@export var navigation_recovery_candidate_count := 8
@export var navigation_link_recovery_backoff_multiplier := 1.35

var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _move_target := Vector3.ZERO
var _has_move_target := false

var _navigation_agent: NavigationAgent3D
var _navigation_target_synced := false
var _navigation_synced_target := Vector3.ZERO
var _navigation_intermediate_targets: Array[Vector3] = []
var _navigation_intermediate_target_data: Array[Dictionary] = []
var _navigation_intermediate_targets_built := false
var _navigation_query_grace_remaining := 0.0
var _avoidance_velocity := Vector3.ZERO
var _has_avoidance_velocity := false
var _navigation_vertical_speed := 0.0
var _stuck_origin := Vector3.ZERO
var _stuck_flat_origin := Vector2.ZERO
var _stuck_target_distance := INF
var _stuck_seconds := 0.0
var _stuck_repath_attempts := 0
var _navigation_zero_waypoint_blocked := false
var _navigation_recovery_target := Vector3.ZERO
var _has_navigation_recovery_target := false


func _ready() -> void:
	_configure_world_actor_movement()


func set_move_target(target: Vector3, _issued_by_player: bool = true) -> void:
	_set_actor_move_target(target)


func process_world_actor_movement(delta: float) -> void:
	_ensure_navigation_agent()
	_apply_floor_motion(delta)
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var desired_direction := Vector3.ZERO
	_navigation_vertical_speed = 0.0
	if _has_move_target:
		desired_direction = _get_move_direction(delta)
		if desired_direction.length_squared() > 0.0001:
			var target_speed := _get_actor_move_speed()
			horizontal_velocity = horizontal_velocity.lerp(desired_direction * target_speed, minf(1.0, acceleration * delta))
			if desired_direction.length_squared() > 0.0001:
				look_at(global_position + desired_direction, Vector3.UP)
		else:
			horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, acceleration * delta))
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, minf(1.0, acceleration * delta))
	if _should_apply_avoidance(desired_direction):
		_navigation_agent.max_speed = maxf(_get_actor_move_speed(), 0.0)
		_navigation_agent.velocity = horizontal_velocity
		if _has_avoidance_velocity:
			horizontal_velocity.x = _avoidance_velocity.x
			horizontal_velocity.z = _avoidance_velocity.z
	if _navigation_vertical_speed > 0.0:
		velocity.y = maxf(velocity.y, _navigation_vertical_speed)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()
	rotation.x = lerp_angle(rotation.x, 0.0, minf(1.0, 10.0 * delta))
	rotation.z = lerp_angle(rotation.z, 0.0, minf(1.0, 10.0 * delta))
	_update_stuck_state(delta, desired_direction)


func _configure_world_actor_movement() -> void:
	floor_snap_length = floor_snap_distance
	floor_max_angle = deg_to_rad(max_walkable_slope_degrees)
	add_to_group("world_actor")
	_ensure_navigation_agent()


func _ensure_navigation_agent() -> void:
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		_configure_navigation_agent()
		return
	_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "NavigationAgent3D"
		add_child(_navigation_agent)
	_configure_navigation_agent()


func _configure_navigation_agent() -> void:
	_navigation_agent.radius = navigation_agent_radius
	_navigation_agent.height = navigation_agent_height
	_navigation_agent.path_desired_distance = navigation_path_desired_distance
	_navigation_agent.target_desired_distance = _get_move_target_arrival_distance()
	_navigation_agent.path_height_offset = navigation_path_height_offset
	_navigation_agent.avoidance_enabled = navigation_avoidance_enabled
	_navigation_agent.neighbor_distance = navigation_neighbor_distance
	_navigation_agent.max_neighbors = navigation_max_neighbors
	_navigation_agent.max_speed = move_speed
	_navigation_agent.time_horizon_agents = navigation_time_horizon_agents
	_navigation_agent.keep_y_velocity = true
	_navigation_agent.simplify_path = true
	_navigation_agent.simplify_epsilon = 0.15
	if not _navigation_agent.velocity_computed.is_connected(_on_navigation_velocity_computed):
		_navigation_agent.velocity_computed.connect(_on_navigation_velocity_computed)


func _set_actor_move_target(target: Vector3) -> void:
	var target_changed := not _has_move_target or _move_target.distance_squared_to(target) > 0.0025
	var should_keep_intermediate_targets := target_changed and _should_keep_navigation_intermediate_targets(target)
	_move_target = target
	_has_move_target = true
	if not target_changed:
		return
	if not should_keep_intermediate_targets:
		_clear_navigation_recovery_target()
	if not should_keep_intermediate_targets:
		_navigation_target_synced = false
		_clear_navigation_intermediate_targets()
		_navigation_intermediate_targets_built = false
	_navigation_query_grace_remaining = 0.25
	_has_avoidance_velocity = false
	_reset_stuck_tracking()
	_stuck_repath_attempts = 0


func _clear_actor_move_target() -> void:
	_has_move_target = false
	_navigation_target_synced = false
	_clear_navigation_intermediate_targets()
	_navigation_intermediate_targets_built = false
	_has_avoidance_velocity = false
	_navigation_vertical_speed = 0.0
	_navigation_zero_waypoint_blocked = false
	_clear_navigation_recovery_target()
	_reset_stuck_tracking()
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
		_navigation_agent.velocity = Vector3.ZERO


func _apply_floor_motion(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		apply_floor_snap()


func _get_move_direction(delta: float) -> Vector3:
	if _is_close_to_move_target():
		_finish_actor_move_target()
		return Vector3.ZERO
	if use_navigation_pathing and _navigation_agent != null and _has_navigation_data():
		return _get_navigation_move_direction(delta)
	_navigation_query_grace_remaining = maxf(0.0, _navigation_query_grace_remaining - delta)
	if _navigation_query_grace_remaining <= 0.0:
		_handle_navigation_unreachable()
	return Vector3.ZERO


func _get_navigation_move_direction(delta: float) -> Vector3:
	_navigation_zero_waypoint_blocked = false
	if _has_navigation_recovery_target and _is_close_to_navigation_point(_navigation_recovery_target, maxf(move_target_vertical_tolerance, 1.0), _get_move_target_arrival_distance()):
		_clear_navigation_recovery_target()
		_navigation_target_synced = false
		_clear_navigation_intermediate_targets()
		_navigation_intermediate_targets_built = false
		return Vector3.ZERO
	_sync_navigation_target_if_needed()
	if not _navigation_intermediate_targets.is_empty() and _is_close_to_current_navigation_intermediate_target():
		_advance_navigation_intermediate_target()
		return Vector3.ZERO
	if _is_traversing_navigation_link():
		return _get_navigation_link_exit_move_direction(_get_current_navigation_target())
	var next_path_position := _navigation_agent.get_next_path_position()
	_navigation_query_grace_remaining = maxf(0.0, _navigation_query_grace_remaining - delta)
	if _navigation_agent.is_navigation_finished():
		if not _navigation_intermediate_targets.is_empty():
			return _get_navigation_intermediate_move_direction()
		if _is_close_to_move_target():
			_finish_actor_move_target()
		elif _is_navigation_final_position_close_enough():
			return _get_navigation_final_move_direction()
		else:
			_handle_navigation_unreachable()
		return Vector3.ZERO
	var to_next := next_path_position - global_position
	_navigation_vertical_speed = _get_navigation_vertical_speed(to_next)
	to_next.y = 0.0
	if to_next.length_squared() <= 0.0001:
		_navigation_zero_waypoint_blocked = true
		return Vector3.ZERO
	return to_next.normalized()


func _get_navigation_intermediate_move_direction() -> Vector3:
	if _is_close_to_current_navigation_intermediate_target():
		_advance_navigation_intermediate_target()
		return Vector3.ZERO
	if _is_traversing_navigation_link():
		return _get_navigation_link_exit_move_direction(_get_current_navigation_target())
	return _get_navigation_point_move_direction(_navigation_agent.get_final_position())


func _get_navigation_final_move_direction() -> Vector3:
	var final_position := _navigation_agent.get_final_position()
	if _is_close_to_navigation_point(final_position, maxf(move_target_vertical_tolerance, 1.2), _get_move_target_arrival_distance()):
		_finish_actor_move_target()
		return Vector3.ZERO
	return _get_navigation_point_move_direction(final_position)


func _get_navigation_point_move_direction(point: Vector3) -> Vector3:
	var to_point := point - global_position
	_navigation_vertical_speed = _get_navigation_vertical_speed(to_point)
	to_point.y = 0.0
	if to_point.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_point.normalized()


func _get_navigation_link_exit_move_direction(point: Vector3) -> Vector3:
	var link_data := _get_current_navigation_intermediate_data()
	if not link_data.is_empty():
		return _get_navigation_link_segment_move_direction(link_data)
	var to_point := point - global_position
	if to_point.y > move_target_vertical_tolerance:
		_navigation_vertical_speed = minf(_get_actor_move_speed(), maxf(0.75, to_point.y * 1.35))
	else:
		_navigation_vertical_speed = _get_navigation_vertical_speed(to_point)
	to_point.y = 0.0
	if to_point.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_point.normalized()


func _get_navigation_link_segment_move_direction(link_data: Dictionary) -> Vector3:
	var entry: Vector3 = link_data.get("entry", global_position)
	var exit: Vector3 = link_data.get("exit", _get_current_navigation_target())
	var segment := exit - entry
	var horizontal_segment := Vector2(segment.x, segment.z)
	var segment_length := horizontal_segment.length()
	if segment_length <= 0.0001:
		return _get_navigation_point_move_direction(exit)
	var closest := _closest_horizontal_point_on_segment(global_position, entry, exit)
	var along := entry.distance_to(closest) / maxf(entry.distance_to(exit), 0.001)
	var lookahead := clampf(maxf(navigation_agent_radius * 2.0, navigation_path_desired_distance) / segment_length, 0.08, 0.28)
	var target_along := clampf(along + lookahead, 0.0, 1.0)
	if _horizontal_distance(global_position, exit) <= maxf(navigation_agent_radius * 2.0, _get_move_target_arrival_distance()):
		target_along = 1.0
	var target_point := entry.lerp(exit, target_along)
	var to_point := target_point - global_position
	_navigation_vertical_speed = _get_navigation_vertical_speed(to_point)
	to_point.y = 0.0
	if to_point.length_squared() <= 0.0001:
		var fallback := exit - global_position
		_navigation_vertical_speed = _get_navigation_vertical_speed(fallback)
		fallback.y = 0.0
		return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector3.ZERO
	return to_point.normalized()


func _get_navigation_vertical_speed(to_next: Vector3) -> float:
	if to_next.y <= move_target_vertical_tolerance:
		return 0.0
	var horizontal_distance := Vector2(to_next.x, to_next.z).length()
	var vertical_follow_distance := maxf(navigation_path_desired_distance * 1.5, navigation_agent_radius * 2.0)
	if horizontal_distance > vertical_follow_distance:
		return 0.0
	return minf(_get_actor_move_speed(), maxf(0.5, to_next.y * 2.0))


func _sync_navigation_target_if_needed() -> void:
	if not _has_navigation_recovery_target and not _navigation_intermediate_targets_built:
		_build_navigation_intermediate_targets()
	_navigation_agent.target_desired_distance = _get_move_target_arrival_distance()
	var navigation_target := _get_current_navigation_target()
	if _navigation_target_synced and _navigation_synced_target.distance_squared_to(navigation_target) <= 0.0025:
		return
	_navigation_agent.target_position = navigation_target
	_navigation_synced_target = navigation_target
	_navigation_target_synced = true
	_navigation_query_grace_remaining = 0.25
	_reset_stuck_tracking()


func _get_current_navigation_target() -> Vector3:
	if _has_navigation_recovery_target:
		return _navigation_recovery_target
	if not _navigation_intermediate_targets.is_empty():
		return _navigation_intermediate_targets[0]
	return _move_target


func _get_current_navigation_intermediate_data() -> Dictionary:
	if _has_navigation_recovery_target or _navigation_intermediate_target_data.is_empty():
		return {}
	return _navigation_intermediate_target_data[0]


func _advance_navigation_intermediate_target() -> bool:
	if _navigation_intermediate_targets.is_empty():
		return false
	_navigation_intermediate_targets.remove_at(0)
	if not _navigation_intermediate_target_data.is_empty():
		_navigation_intermediate_target_data.remove_at(0)
	_navigation_target_synced = false
	_reset_stuck_tracking()
	_stuck_repath_attempts = 0
	return true


func _clear_navigation_intermediate_targets() -> void:
	_navigation_intermediate_targets.clear()
	_navigation_intermediate_target_data.clear()


func _append_navigation_intermediate_target(target: Vector3, data: Dictionary = {}) -> void:
	_navigation_intermediate_targets.append(target)
	_navigation_intermediate_target_data.append(data)


func _get_navigation_intermediate_horizontal_tolerance() -> float:
	if _navigation_intermediate_targets.is_empty():
		return _get_move_target_arrival_distance()
	if _is_current_navigation_intermediate_entry():
		return navigation_unreachable_tolerance
	return maxf(_get_move_target_arrival_distance(), navigation_agent_radius * 2.0)


func _get_current_navigation_intermediate_horizontal_tolerance() -> float:
	if _navigation_intermediate_targets.is_empty():
		return _get_move_target_arrival_distance()
	return _get_navigation_intermediate_horizontal_tolerance()


func _is_close_to_current_navigation_intermediate_target() -> bool:
	return _is_close_to_navigation_point(_get_current_navigation_target(), maxf(move_target_vertical_tolerance, 1.4), _get_current_navigation_intermediate_horizontal_tolerance())


func _is_current_navigation_intermediate_entry() -> bool:
	var data := _get_current_navigation_intermediate_data()
	if not data.is_empty():
		return bool(data.get("is_link_entry", false))
	return _navigation_intermediate_targets.size() % 2 == 0


func _build_navigation_intermediate_targets() -> void:
	_navigation_intermediate_targets_built = true
	_clear_navigation_intermediate_targets()
	var vertical_delta := _move_target.y - global_position.y
	if absf(vertical_delta) <= move_target_vertical_tolerance:
		return
	if not is_inside_tree():
		return
	var upward := vertical_delta > 0.0
	var links: Array[NavigationLink3D] = []
	_collect_navigation_links(get_tree().root, links)
	var current_position := global_position
	var used_links: Dictionary = {}
	for _step in range(links.size()):
		if absf(_move_target.y - current_position.y) <= move_target_vertical_tolerance:
			return
		var candidate := _find_navigation_link_step(links, current_position, upward, used_links)
		if candidate.is_empty():
			return
		var entry := candidate["entry"] as Vector3
		var exit := candidate["exit"] as Vector3
		if not bool(candidate.get("skip_entry", false)):
			_append_navigation_intermediate_target(entry, {"is_link_entry": true, "entry": entry, "exit": exit})
		_append_navigation_intermediate_target(exit, {"is_link_exit": true, "entry": entry, "exit": exit})
		used_links[int(candidate["link_id"])] = true
		current_position = exit


func _find_navigation_link_step(links: Array[NavigationLink3D], current_position: Vector3, upward: bool, used_links: Dictionary) -> Dictionary:
	var best_candidate: Dictionary = {}
	var best_score := INF
	var level_tolerance := maxf(move_target_vertical_tolerance, 1.4)
	for link in links:
		if link == null or not link.enabled:
			continue
		var link_id := link.get_instance_id()
		if used_links.has(link_id):
			continue
		var start := link.to_global(link.start_position)
		var end := link.to_global(link.end_position)
		var start_is_entry := start.y <= end.y if upward else start.y >= end.y
		if not start_is_entry and not link.bidirectional:
			continue
		var entry := start if start_is_entry else end
		var exit := end if start_is_entry else start
		var on_link_segment := _is_position_on_navigation_link_segment(current_position, entry, exit)
		if not on_link_segment and absf(entry.y - current_position.y) > level_tolerance:
			continue
		if not on_link_segment and _horizontal_distance(current_position, entry) > navigation_vertical_link_search_radius:
			continue
		if upward:
			if exit.y <= current_position.y + move_target_vertical_tolerance:
				continue
			if exit.y > _move_target.y + level_tolerance:
				continue
		else:
			if exit.y >= current_position.y - move_target_vertical_tolerance:
				continue
			if exit.y < _move_target.y - level_tolerance:
				continue
		var entry_distance := 0.0 if on_link_segment else _horizontal_distance(current_position, entry)
		var entry_tolerance := maxf(navigation_unreachable_tolerance, navigation_agent_radius * 3.0)
		if not on_link_segment and not _can_reach_navigation_point(current_position, entry, entry_tolerance, level_tolerance) and entry_distance > entry_tolerance:
			continue
		var score := entry_distance + absf(exit.y - _move_target.y) * 0.05
		if not _can_reach_move_target_from(exit):
			score += navigation_vertical_link_search_radius
		if score < best_score:
			best_score = score
			best_candidate = {"entry": entry, "exit": exit, "link_id": link_id, "skip_entry": on_link_segment}
	return best_candidate


func _collect_navigation_links(node: Node, links: Array[NavigationLink3D]) -> void:
	if node == null:
		return
	if node is NavigationLink3D:
		links.append(node)
	for child in node.get_children():
		_collect_navigation_links(child, links)


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _horizontal_distance_to_segment(point: Vector3, start: Vector3, end: Vector3) -> float:
	var closest := _closest_horizontal_point_on_segment(point, start, end)
	return _flat_position(point).distance_to(_flat_position(closest))


func _closest_horizontal_point_on_segment(point: Vector3, start: Vector3, end: Vector3) -> Vector3:
	var point_2d := Vector2(point.x, point.z)
	var start_2d := Vector2(start.x, start.z)
	var end_2d := Vector2(end.x, end.z)
	var segment := end_2d - start_2d
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.0001:
		return start
	var along := clampf((point_2d - start_2d).dot(segment) / segment_length_squared, 0.0, 1.0)
	return start.lerp(end, along)


func _is_position_on_navigation_link_segment(point: Vector3, entry: Vector3, exit: Vector3) -> bool:
	var min_y := minf(entry.y, exit.y) - maxf(move_target_vertical_tolerance, 0.5)
	var max_y := maxf(entry.y, exit.y) + maxf(move_target_vertical_tolerance, 0.5)
	if point.y < min_y or point.y > max_y:
		return false
	var segment_tolerance := maxf(navigation_agent_radius * 2.0, _get_move_target_arrival_distance())
	var closest := _closest_horizontal_point_on_segment(point, entry, exit)
	return _horizontal_distance(point, closest) <= segment_tolerance and absf(point.y - closest.y) <= maxf(move_target_vertical_tolerance, 0.75)


func _flat_position(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


func _is_traversing_navigation_link() -> bool:
	var data := _get_current_navigation_intermediate_data()
	if not data.is_empty():
		return bool(data.get("is_link_exit", false))
	return not _has_navigation_recovery_target and not _navigation_intermediate_targets.is_empty() and not _is_current_navigation_intermediate_entry()


func _clear_navigation_recovery_target() -> void:
	_has_navigation_recovery_target = false
	_navigation_recovery_target = Vector3.ZERO


func _reset_stuck_tracking() -> void:
	_stuck_origin = global_position
	_stuck_flat_origin = _flat_position(global_position)
	_stuck_target_distance = _get_stuck_target_distance()
	_stuck_seconds = 0.0


func _get_stuck_target_distance() -> float:
	if not _has_move_target:
		return INF
	return _horizontal_distance(global_position, _get_current_navigation_target())


func _has_made_stuck_progress() -> bool:
	if _flat_position(global_position).distance_to(_stuck_flat_origin) >= stuck_min_progress:
		return true
	var target_distance := _get_stuck_target_distance()
	if _stuck_target_distance < INF and target_distance <= _stuck_target_distance - stuck_min_progress:
		return true
	return false


func _should_keep_navigation_intermediate_targets(target: Vector3) -> bool:
	if _navigation_intermediate_targets.is_empty():
		return false
	var old_delta := _move_target.y - global_position.y
	var new_delta := target.y - global_position.y
	if absf(old_delta) <= move_target_vertical_tolerance or absf(new_delta) <= move_target_vertical_tolerance:
		return false
	return signf(old_delta) == signf(new_delta)


func _can_reach_move_target_from(from: Vector3) -> bool:
	return _can_reach_navigation_point(from, _move_target, maxf(navigation_unreachable_tolerance, _get_move_target_arrival_distance()), move_target_vertical_tolerance)


func _can_reach_navigation_point(from: Vector3, to: Vector3, horizontal_tolerance: float = -1.0, vertical_tolerance: float = -1.0) -> bool:
	if _navigation_agent == null:
		return false
	var path := NavigationServer3D.map_get_path(_navigation_agent.get_navigation_map(), from, to, true)
	if path.size() < 2:
		return false
	var final_position := path[path.size() - 1]
	var effective_vertical_tolerance := move_target_vertical_tolerance if vertical_tolerance < 0.0 else vertical_tolerance
	return _is_close_to_navigation_point_from(final_position, to, effective_vertical_tolerance, horizontal_tolerance)


func _is_close_to_navigation_point(point: Vector3, vertical_tolerance: float, horizontal_tolerance: float) -> bool:
	return _is_close_to_navigation_point_from(global_position, point, vertical_tolerance, horizontal_tolerance)


func _is_close_to_navigation_point_from(from: Vector3, point: Vector3, vertical_tolerance: float, horizontal_tolerance: float = -1.0) -> bool:
	var effective_horizontal_tolerance := _get_move_target_arrival_distance() if horizontal_tolerance < 0.0 else horizontal_tolerance
	return _horizontal_distance(from, point) <= effective_horizontal_tolerance and absf(from.y - point.y) <= vertical_tolerance


func _get_move_target_arrival_distance() -> float:
	return navigation_target_desired_distance


func _has_navigation_data() -> bool:
	return NavigationServer3D.map_get_iteration_id(_navigation_agent.get_navigation_map()) > 0


func _is_close_to_move_target() -> bool:
	var to_target := _move_target - global_position
	var horizontal_to_target := Vector3(to_target.x, 0.0, to_target.z)
	return horizontal_to_target.length() <= _get_move_target_arrival_distance() and absf(to_target.y) <= move_target_vertical_tolerance


func _is_navigation_final_position_close_enough() -> bool:
	if _navigation_agent == null:
		return false
	var final_position := _navigation_agent.get_final_position()
	var to_target := _move_target - final_position
	var horizontal_to_target := Vector3(to_target.x, 0.0, to_target.z)
	return horizontal_to_target.length() <= navigation_unreachable_tolerance and absf(to_target.y) <= move_target_vertical_tolerance


func _finish_actor_move_target() -> void:
	_clear_actor_move_target()
	_on_actor_move_target_reached()


func _fail_actor_move_target() -> void:
	_clear_actor_move_target()
	_on_actor_move_target_unreachable()


func _handle_navigation_unreachable() -> void:
	if _should_persist_move_target_navigation():
		_recover_actor_move_target_navigation()
		return
	_fail_actor_move_target()


func _recover_actor_move_target_navigation() -> void:
	var blocked_target := _get_current_navigation_target()
	_navigation_target_synced = false
	_clear_navigation_intermediate_targets()
	_navigation_intermediate_targets_built = false
	_navigation_query_grace_remaining = 0.5
	_has_avoidance_velocity = false
	_navigation_zero_waypoint_blocked = false
	_try_set_navigation_recovery_target(blocked_target)
	_reset_stuck_tracking()
	_stuck_repath_attempts += 1


func _should_persist_move_target_navigation() -> bool:
	return true


func _is_using_navigation_link() -> bool:
	return _is_traversing_navigation_link()


func _recover_navigation_link_stuck() -> void:
	var blocked_target := _get_current_navigation_target()
	_navigation_target_synced = false
	_clear_navigation_intermediate_targets()
	_navigation_intermediate_targets_built = false
	_navigation_query_grace_remaining = 0.5
	_has_avoidance_velocity = false
	_navigation_zero_waypoint_blocked = false
	_clear_navigation_recovery_target()
	if not _try_set_navigation_link_backoff_target(blocked_target):
		_try_set_navigation_recovery_target(blocked_target)
	_reset_stuck_tracking()
	_stuck_repath_attempts += 1


func _try_set_navigation_link_backoff_target(blocked_target: Vector3) -> bool:
	if _navigation_agent == null or not _has_navigation_data():
		return false
	var map := _navigation_agent.get_navigation_map()
	var away := global_position - blocked_target
	away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = -global_transform.basis.z
		away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = Vector3.FORWARD
	away = away.normalized()
	for distance_scale in [navigation_link_recovery_backoff_multiplier, 1.0]:
		var backoff_distance := maxf(navigation_recovery_detour_distance * float(distance_scale), navigation_agent_radius * 2.0)
		var desired := global_position + away * backoff_distance
		var closest := NavigationServer3D.map_get_closest_point(map, desired)
		if closest.distance_to(global_position) <= maxf(navigation_agent_radius, 0.25):
			continue
		if closest.distance_to(desired) > backoff_distance:
			continue
		if absf(closest.y - global_position.y) > maxf(move_target_vertical_tolerance, 1.0):
			continue
		_navigation_recovery_target = closest
		_has_navigation_recovery_target = true
		return true
	return false


func _try_set_navigation_recovery_target(blocked_target: Vector3) -> bool:
	_clear_navigation_recovery_target()
	if _navigation_agent == null or not _has_navigation_data():
		return false
	var map := _navigation_agent.get_navigation_map()
	var away := global_position - blocked_target
	away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = -global_transform.basis.z
		away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = Vector3.FORWARD
	away = away.normalized()
	var side := Vector3(-away.z, 0.0, away.x).normalized()
	var candidates: Array[Vector3] = [
		away,
		side,
		-side,
		(away + side).normalized(),
		(away - side).normalized(),
		-away,
		(-away + side).normalized(),
		(-away - side).normalized(),
	]
	var candidate_count := mini(maxi(navigation_recovery_candidate_count, 0), candidates.size())
	if candidate_count <= 0:
		return false
	var start_index := _stuck_repath_attempts % candidate_count
	for offset in range(candidate_count):
		var direction := candidates[(start_index + offset) % candidate_count]
		if direction.length_squared() <= 0.0001:
			continue
		var desired := global_position + direction * navigation_recovery_detour_distance
		var closest := NavigationServer3D.map_get_closest_point(map, desired)
		if closest.distance_to(global_position) <= maxf(navigation_agent_radius, 0.25):
			continue
		if closest.distance_to(desired) > navigation_recovery_detour_distance:
			continue
		if absf(closest.y - global_position.y) > maxf(move_target_vertical_tolerance, 1.0):
			continue
		_navigation_recovery_target = closest
		_has_navigation_recovery_target = true
		return true
	return false


func _should_apply_avoidance(desired_direction: Vector3) -> bool:
	return navigation_avoidance_enabled and _navigation_agent != null and _has_move_target and not _is_traversing_navigation_link() and desired_direction.length_squared() > 0.0001


func _update_stuck_state(delta: float, desired_direction: Vector3) -> void:
	if not _has_move_target or desired_direction.length_squared() <= 0.0001:
		if _navigation_zero_waypoint_blocked:
			_stuck_seconds += delta
			if _stuck_seconds >= stuck_check_seconds:
				_navigation_zero_waypoint_blocked = false
				_handle_navigation_stuck()
			return
		_reset_stuck_tracking()
		return
	if _has_made_stuck_progress():
		_reset_stuck_tracking()
		_stuck_repath_attempts = 0
		return
	_stuck_seconds += delta
	if _stuck_seconds < stuck_check_seconds:
		return
	_handle_navigation_stuck()


func _handle_navigation_stuck() -> void:
	if use_navigation_pathing and _navigation_agent != null and _has_navigation_data() and _stuck_repath_attempts < 2:
		if _is_using_navigation_link():
			_recover_navigation_link_stuck()
			return
		_navigation_target_synced = false
		_reset_stuck_tracking()
		_stuck_repath_attempts += 1
		return
	_handle_navigation_unreachable()


func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	_avoidance_velocity = safe_velocity
	_has_avoidance_velocity = true


func _get_actor_move_speed() -> float:
	return move_speed


func _on_actor_move_target_reached() -> void:
	pass


func _on_actor_move_target_unreachable() -> void:
	pass
