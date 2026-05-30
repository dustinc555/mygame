extends CharacterBody3D

class_name WorldActor

const ACTOR_SKILL_SET_SCRIPT = preload("res://scripts/skills/actor_skill_set.gd")

const NAVIGATION_MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED := 0.0025

@export var skill_set: ActorSkillSet
@export var starting_skill_levels: Dictionary = {}

@export var member_name := "Character"
@export var stable_id := ""
@export var faction_name := "Player"
@export var squad_name := "Default"
@export var world_squad_id := ""
@export var hostile_factions: PackedStringArray = PackedStringArray()

@export var hunger_enabled := false
@export_range(0, 2, 1) var hunger_stage: int = NpcRules.HungerStage.WELL_NOURISHED
@export var hunger := 100.0
@export var hunger_drain_rate := 0.08
@export var fatigue_enabled := true
@export_range(0, 2, 1) var fatigue_stage: int = NpcRules.FatigueStage.WELL_RESTED
@export var fatigue := 100.0
@export var running := false
@export var sneaking := false
@export var auto_heal_enabled := false
@export_range(0, 2, 1) var combat_stance := NpcRules.CombatStance.DEFENSIVE

@export var max_hp := 100.0
@export var hp := 100.0
@export var max_blood := 100.0
@export var blood := 100.0

@export var aggressive_scan_radius := NpcRules.AGGRO_RANGE
@export var assist_scan_radius := NpcRules.ASSIST_RANGE
@export var combat_witness_radius := NpcRules.COMBAT_WITNESS_RANGE
@export var combat_squad_assist_radius := NpcRules.SQUAD_ASSIST_RANGE
@export var combat_support_target_spread_radius := NpcRules.COMBAT_WITNESS_RANGE
@export var attack_range := 1.15
@export var combat_approach_arrival_distance := 0.3
@export var combat_direct_chase_distance := 3.0
@export var combat_chase_leash_distance := 42.0
@export var combat_active_attack_slots := 5
@export var combat_attack_forgiveness_buffer := 0.15
@export var combat_settle_band_extra := 0.65
@export var combat_settle_speed_multiplier := 0.32
@export var combat_personal_space_padding := 0.16
@export var combat_wait_ring_extra := 1.45
@export var combat_direct_translation_enabled := true
@export var attack_cooldown_seconds := 1.2
@export var base_attack_damage := 18.0
@export var base_dexterity := 10.0
@export_range(0.0, 1.0, 0.01) var attack_cut_ratio := 0.05
@export var base_dodge_chance := 0.08
@export var base_block_chance := 0.06
@export var block_damage_multiplier := 0.4

@export var move_speed := 3.2
@export var acceleration := 10.0
@export var floor_snap_distance := 0.9
@export var max_walkable_slope_degrees := 55.0
@export var move_target_vertical_tolerance := 0.75

@export var use_navigation_pathing := true
@export var navigation_avoidance_enabled := true
@export var navigation_agent_radius := 0.45
@export var navigation_agent_height := 2.0
@export var navigation_path_desired_distance := 0.75
@export var navigation_target_desired_distance := 0.6
@export var navigation_path_height_offset := 0.9
@export var navigation_unreachable_tolerance := 1.4
@export var navigation_neighbor_distance := 2.4
@export var navigation_max_neighbors := 8
@export var navigation_time_horizon_agents := 0.7
@export var stuck_check_seconds := 2.0
@export var stuck_min_progress := 0.12
@export var stuck_repath_attempt_limit := 8

var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var player_party_member := false
var life_state := NpcRules.LifeState.ALIVE
var _move_target := Vector3.ZERO
var _has_move_target := false

var _navigation_agent: NavigationAgent3D
var _navigation_target_synced := false
var _navigation_synced_target := Vector3.ZERO
var _navigation_query_grace_remaining := 0.0
var _avoidance_velocity := Vector3.ZERO
var _has_avoidance_velocity := false
var _stuck_origin := Vector3.ZERO
var _stuck_target_distance := INF
var _stuck_seconds := 0.0
var _stuck_repath_attempts := 0
var _navigation_zero_waypoint_blocked := false
var _starting_skill_levels_applied := false


func _ready() -> void:
	_ensure_skill_set()
	_configure_world_actor_movement()


func get_skill_level(skill_id: String) -> int:
	_ensure_skill_set()
	return skill_set.get_skill_level(skill_id)


func set_skill_level(skill_id: String, level: int, clear_xp := true) -> void:
	_ensure_skill_set()
	skill_set.set_skill_level(skill_id, level, clear_xp)


func add_skill_xp(skill_id: String, amount: float, reason := "") -> int:
	_ensure_skill_set()
	return skill_set.add_skill_xp(skill_id, amount, reason)


func get_skill_xp(skill_id: String) -> float:
	_ensure_skill_set()
	return skill_set.get_skill_xp(skill_id)


func get_skill_xp_to_next(skill_id: String) -> float:
	_ensure_skill_set()
	return skill_set.get_skill_xp_to_next(skill_id)


func get_skill_progress_ratio(skill_id: String) -> float:
	_ensure_skill_set()
	return skill_set.get_skill_progress_ratio(skill_id)


func get_skill_entry_snapshot(skill_id: String) -> Dictionary:
	_ensure_skill_set()
	return skill_set.get_entry_snapshot(skill_id)


func _ensure_skill_set() -> void:
	if skill_set != null:
		_apply_starting_skill_levels_if_needed()
		return
	skill_set = ACTOR_SKILL_SET_SCRIPT.new() as ActorSkillSet
	_apply_starting_skill_levels_if_needed()


func _apply_starting_skill_levels_if_needed() -> void:
	if _starting_skill_levels_applied or skill_set == null:
		return
	_starting_skill_levels_applied = true
	for skill_id_value in starting_skill_levels.keys():
		var skill_id := str(skill_id_value)
		if skill_id.is_empty():
			continue
		skill_set.set_skill_level(skill_id, int(starting_skill_levels[skill_id_value]))


func set_move_target(target: Vector3, _issued_by_player: bool = true) -> void:
	_set_actor_move_target(target)


func is_alive() -> bool:
	return life_state == NpcRules.LifeState.ALIVE


func is_player_party_member() -> bool:
	return player_party_member


func set_player_party_member(value: bool) -> void:
	player_party_member = value
	_sync_party_membership_group()


func get_actor_display_name() -> String:
	var display_name := member_name.strip_edges()
	return display_name if not display_name.is_empty() else str(name)


func get_actor_squad_id() -> String:
	var actor_squad_id := world_squad_id.strip_edges()
	return actor_squad_id if not actor_squad_id.is_empty() else squad_name.strip_edges()


func assign_attack_target(_target_actor: Node, _issued_by_player: bool = true, _notify_target: bool = true, _notify_allies: bool = true) -> bool:
	return false


func process_world_actor_movement(delta: float) -> void:
	_ensure_navigation_agent()
	_apply_floor_motion(delta)
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var desired_direction := Vector3.ZERO
	if _has_move_target:
		desired_direction = _get_move_direction(delta)
		if desired_direction.length_squared() > 0.0001:
			var target_speed := _get_actor_move_speed()
			horizontal_velocity = horizontal_velocity.lerp(desired_direction * target_speed, minf(1.0, acceleration * delta))
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
	_sync_party_membership_group()


func _ensure_navigation_agent() -> void:
	if _navigation_agent != null and is_instance_valid(_navigation_agent):
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
	_navigation_agent.keep_y_velocity = false
	_navigation_agent.simplify_path = false
	_navigation_agent.simplify_epsilon = 0.0
	if not _navigation_agent.velocity_computed.is_connected(_on_navigation_velocity_computed):
		_navigation_agent.velocity_computed.connect(_on_navigation_velocity_computed)


func _set_actor_move_target(target: Vector3) -> void:
	var target_changed := not _has_move_target or _move_target.distance_squared_to(target) > 0.0025
	_move_target = target
	_has_move_target = true
	if not target_changed:
		return
	_navigation_target_synced = false
	_navigation_query_grace_remaining = 0.25
	_navigation_zero_waypoint_blocked = false
	_has_avoidance_velocity = false
	_stuck_repath_attempts = 0
	_reset_stuck_tracking()


func _clear_actor_move_target() -> void:
	_has_move_target = false
	_navigation_target_synced = false
	_navigation_query_grace_remaining = 0.0
	_navigation_zero_waypoint_blocked = false
	_has_avoidance_velocity = false
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
		_fail_actor_move_target()
	return Vector3.ZERO


func _get_navigation_move_direction(delta: float) -> Vector3:
	_navigation_zero_waypoint_blocked = false
	_sync_navigation_target_if_needed()
	if _navigation_agent.is_navigation_finished():
		if _is_close_to_move_target():
			_finish_actor_move_target()
		elif _is_navigation_final_position_close_enough():
			return _get_navigation_point_move_direction(_navigation_agent.get_final_position())
		else:
			_fail_actor_move_target()
		return Vector3.ZERO
	var next_path_position := _navigation_agent.get_next_path_position()
	if not _is_navigation_final_position_close_enough():
		_navigation_query_grace_remaining = maxf(0.0, _navigation_query_grace_remaining - delta)
		if _navigation_query_grace_remaining <= 0.0:
			_fail_actor_move_target()
		return Vector3.ZERO
	return _get_navigation_path_move_direction(next_path_position)


func _get_navigation_path_move_direction(next_path_position: Vector3) -> Vector3:
	var direct_direction := _get_navigation_point_move_direction(next_path_position)
	if direct_direction.length_squared() > 0.0001:
		return direct_direction
	var path := _navigation_agent.get_current_navigation_path()
	var path_index := maxi(0, _navigation_agent.get_current_navigation_path_index())
	for index in range(path_index, path.size()):
		var to_point := path[index] - global_position
		to_point.y = 0.0
		if to_point.length_squared() > NAVIGATION_MIN_HORIZONTAL_WAYPOINT_DISTANCE_SQUARED:
			return to_point.normalized()
	_navigation_zero_waypoint_blocked = true
	return Vector3.ZERO


func _get_navigation_point_move_direction(point: Vector3) -> Vector3:
	var to_point := point - global_position
	to_point.y = 0.0
	if to_point.length_squared() <= 0.0001:
		return Vector3.ZERO
	return to_point.normalized()


func _sync_navigation_target_if_needed() -> void:
	_navigation_agent.target_desired_distance = _get_move_target_arrival_distance()
	if _navigation_target_synced and _navigation_synced_target.distance_squared_to(_move_target) <= 0.0025:
		return
	_navigation_agent.target_position = _move_target
	_navigation_synced_target = _move_target
	_navigation_target_synced = true
	_navigation_query_grace_remaining = 0.25
	_reset_stuck_tracking()


func _reset_stuck_tracking() -> void:
	_stuck_origin = global_position
	_stuck_target_distance = _get_stuck_target_distance()
	_stuck_seconds = 0.0


func _get_stuck_target_distance() -> float:
	if not _has_move_target:
		return INF
	return _horizontal_distance(global_position, _move_target)


func _has_made_stuck_progress() -> bool:
	if _horizontal_distance(global_position, _stuck_origin) >= stuck_min_progress:
		return true
	var target_distance := _get_stuck_target_distance()
	if _stuck_target_distance < INF and target_distance <= _stuck_target_distance - stuck_min_progress:
		return true
	return false


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _is_close_to_navigation_point(point: Vector3, vertical_tolerance: float, horizontal_tolerance: float) -> bool:
	return _is_close_to_navigation_point_from(global_position, point, vertical_tolerance, horizontal_tolerance)


func _is_close_to_navigation_point_from(from: Vector3, point: Vector3, vertical_tolerance: float, horizontal_tolerance: float = -1.0) -> bool:
	var effective_horizontal_tolerance := _get_move_target_arrival_distance() if horizontal_tolerance < 0.0 else horizontal_tolerance
	return _horizontal_distance(from, point) <= effective_horizontal_tolerance and absf(from.y - point.y) <= vertical_tolerance


func _get_move_target_arrival_distance() -> float:
	return navigation_target_desired_distance


func _get_navigation_stuck_arrival_distance() -> float:
	return _get_move_target_arrival_distance()


func _has_navigation_data() -> bool:
	return NavigationServer3D.map_get_iteration_id(_navigation_agent.get_navigation_map()) > 0


func _is_close_to_move_target() -> bool:
	var to_target := _move_target - global_position
	return _horizontal_distance(global_position, _move_target) <= _get_move_target_arrival_distance() and absf(to_target.y) <= move_target_vertical_tolerance


func _is_navigation_final_position_close_enough() -> bool:
	if _navigation_agent == null:
		return false
	var final_position := _navigation_agent.get_final_position()
	return _is_close_to_navigation_point_from(final_position, _move_target, move_target_vertical_tolerance, navigation_unreachable_tolerance)


func _finish_actor_move_target() -> void:
	_clear_actor_move_target()
	_on_actor_move_target_reached()


func _fail_actor_move_target() -> void:
	_clear_actor_move_target()
	_on_actor_move_target_unreachable()


func _should_apply_avoidance(desired_direction: Vector3) -> bool:
	return _navigation_agent != null and _navigation_agent.avoidance_enabled and _has_move_target and desired_direction.length_squared() > 0.0001


func _update_stuck_state(delta: float, desired_direction: Vector3) -> void:
	if not _has_move_target or desired_direction.length_squared() <= 0.0001:
		if _navigation_zero_waypoint_blocked:
			_stuck_seconds += delta
			if _stuck_seconds >= stuck_check_seconds:
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
	if _is_close_to_navigation_point(_move_target, move_target_vertical_tolerance, _get_navigation_stuck_arrival_distance()):
		_finish_actor_move_target()
		return
	if _is_navigation_final_position_close_enough() and _stuck_repath_attempts < stuck_repath_attempt_limit:
		_navigation_target_synced = false
		_stuck_repath_attempts += 1
		_reset_stuck_tracking()
		return
	_fail_actor_move_target()


func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	_avoidance_velocity = safe_velocity
	_has_avoidance_velocity = true


func _get_actor_move_speed() -> float:
	return move_speed


func _sync_party_membership_group() -> void:
	if player_party_member:
		add_to_group("party_member")
	else:
		remove_from_group("party_member")


func _on_actor_move_target_reached() -> void:
	pass


func _on_actor_move_target_unreachable() -> void:
	pass
