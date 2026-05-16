extends Node

class_name SettlementActivityController

@export var tick_interval_seconds := 2.0
@export var min_assignment_seconds := 12.0
@export var max_assignment_seconds := 28.0

var root_scene: Node
var world_time: Node
var _tick_remaining := 0.0
var _sim_time := 0.0
var _assignments: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("settlement_activity_controller")
	_rng.seed = 31001
	_try_initialize()


func _process(delta: float) -> void:
	if not _initialized:
		return
	_sim_time += delta
	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return
	_tick_remaining = tick_interval_seconds
	_process_towns()


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	world_time = get_parent().get_node_or_null("WorldTimeController")
	_initialized = true


func _process_towns() -> void:
	for town in get_tree().get_nodes_in_group("settlement_town"):
		if town == null or not town.has_method("get_resident_characters") or not town.has_method("get_activity_points"):
			continue
		var residents: Array = town.call("get_resident_characters")
		var points: Array = town.call("get_activity_points")
		if residents.is_empty() or points.is_empty():
			continue
		for resident in residents:
			_process_resident(resident, points)


func _process_resident(resident: Node, points: Array) -> void:
	if not _can_assign_resident(resident):
		_release_assignment(resident)
		return
	var key := _actor_key(resident)
	var existing: Dictionary = _assignments.get(key, {})
	if not existing.is_empty() and float(existing.get("until", 0.0)) > _sim_time:
		var existing_point = existing.get("point")
		if existing_point != null and is_instance_valid(existing_point):
			return
		_assignments.erase(key)
	var point = _choose_activity_point(resident, points)
	if point == null:
		return
	_release_assignment(resident)
	if point.has_method("assign_actor") and bool(point.call("assign_actor", resident)):
		_assignments[key] = {
			"point": point,
			"until": _sim_time + _rng.randf_range(min_assignment_seconds, max_assignment_seconds),
		}


func _choose_activity_point(resident: Node, points: Array):
	var hour := _get_current_hour()
	var candidates: Array = []
	var total_weight := 0.0
	for point in points:
		if point == null or not is_instance_valid(point):
			continue
		if point.has_method("is_active_for_hour") and not bool(point.call("is_active_for_hour", hour)):
			continue
		if point.has_method("is_available_for") and not bool(point.call("is_available_for", resident)):
			continue
		var weight := maxf(float(point.get("weight")), 0.1)
		candidates.append({"point": point, "weight": weight})
		total_weight += weight
	if candidates.is_empty():
		return null
	var roll := _rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	for candidate in candidates:
		cursor += float(candidate["weight"])
		if roll <= cursor:
			return candidate["point"]
	return candidates.back()["point"]


func _can_assign_resident(resident: Node) -> bool:
	if resident == null or not is_instance_valid(resident):
		return false
	if resident.has_method("is_player_party_member") and bool(resident.call("is_player_party_member")):
		return false
	var life_state = resident.get("life_state")
	if life_state != null and int(life_state) != NpcRules.LifeState.ALIVE:
		return false
	if resident.has_method("is_in_combat") and bool(resident.call("is_in_combat")):
		return false
	if resident.has_method("get_active_job_provider") and resident.call("get_active_job_provider") != null:
		return false
	return resident.has_method("set_move_target")


func _release_assignment(resident: Node) -> void:
	var key := _actor_key(resident)
	var existing: Dictionary = _assignments.get(key, {})
	if existing.is_empty():
		return
	var point = existing.get("point")
	if point != null and is_instance_valid(point) and point.has_method("release_actor"):
		point.call("release_actor", resident)
	_assignments.erase(key)


func _get_current_hour() -> int:
	if world_time != null and world_time.has_method("get_hour"):
		return int(world_time.call("get_hour"))
	return 12


func _actor_key(actor: Node) -> String:
	if actor == null:
		return ""
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).is_empty():
		return str(stable_id)
	return str(actor.get_instance_id())
