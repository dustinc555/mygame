extends Node

class_name SettlementActivityController

const AI_JOB_SCRIPT = preload("res://scripts/ai/ai_job.gd")
const AI_START_ACTIVITY_STEP_SCRIPT = preload("res://scripts/ai/steps/ai_start_activity_step.gd")
const AI_WAIT_STEP_SCRIPT = preload("res://scripts/ai/steps/ai_wait_step.gd")
const AI_RELEASE_ACTIVITY_STEP_SCRIPT = preload("res://scripts/ai/steps/ai_release_activity_step.gd")
const SOURCE_ID := "settlement_activity"

@export var tick_interval_seconds := 2.0
@export var initial_assignment_delay_seconds := 10.0
@export var min_assignment_seconds := 12.0
@export var max_assignment_seconds := 28.0
@export_range(1, 128, 1) var resident_budget_per_tick := 8
@export_range(0.25, 30.0, 0.25) var activity_point_cache_seconds := 5.0

var root_scene: Node
var world_time: Node
var actor_query_controller: Node
var _tick_remaining := 0.0
var _sim_time := 0.0
var _rng := RandomNumberGenerator.new()
var _initialized := false
var _resident_cursor_by_town: Dictionary = {}
var _activity_points_by_town: Dictionary = {}
var _activity_point_cache_remaining := 0.0
var _town_cursor := 0


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
	_activity_point_cache_remaining -= delta
	if _activity_point_cache_remaining <= 0.0:
		_activity_points_by_town.clear()
		_activity_point_cache_remaining = maxf(activity_point_cache_seconds, 0.25)
	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return
	_tick_remaining = tick_interval_seconds
	_process_towns()


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	world_time = get_parent().get_node_or_null("WorldTimeController")
	actor_query_controller = get_parent().get_node_or_null("ActorQueryController")
	_tick_remaining = maxf(tick_interval_seconds, initial_assignment_delay_seconds)
	_initialized = true


func _process_towns() -> void:
	var remaining_budget: int = max(1, int(resident_budget_per_tick))
	var towns := get_tree().get_nodes_in_group("settlement_town")
	if towns.is_empty():
		return
	_town_cursor = _town_cursor % towns.size()
	for town_offset in range(towns.size()):
		if remaining_budget <= 0:
			break
		var town := towns[(_town_cursor + town_offset) % towns.size()] as Node
		if town == null or not town.has_method("get_resident_characters") or not town.has_method("get_activity_points"):
			continue
		var towns_left: int = maxi(1, towns.size() - town_offset)
		var town_budget: int = maxi(1, int(ceil(float(remaining_budget) / float(towns_left))))
		remaining_budget -= _process_town(town, town_budget)
	_town_cursor = (_town_cursor + 1) % towns.size()


func _process_town(town: Node, town_budget: int) -> int:
	var residents: Array = _get_town_residents(town)
	var points: Array = _get_town_activity_points(town)
	if residents.is_empty() or points.is_empty():
		return 0
	var town_key: String = _town_key(town)
	var start_index: int = int(_resident_cursor_by_town.get(town_key, 0)) % residents.size()
	var processed: int = 0
	for offset in range(residents.size()):
		if processed >= town_budget:
			_resident_cursor_by_town[town_key] = (start_index + processed) % residents.size()
			return processed
		var resident: Node = residents[(start_index + offset) % residents.size()] as Node
		_process_resident(resident, points)
		processed += 1
	_resident_cursor_by_town[town_key] = (start_index + processed) % residents.size()
	return processed


func _get_town_activity_points(town: Node) -> Array:
	var town_key := _town_key(town)
	if _activity_points_by_town.has(town_key):
		return _activity_points_by_town[town_key]
	var points: Array = town.call("get_activity_points") if town != null and town.has_method("get_activity_points") else []
	_sync_activity_points_to_gecs(town, points)
	_activity_points_by_town[town_key] = points
	return points


func _get_town_residents(town: Node) -> Array:
	if town != null and actor_query_controller != null and actor_query_controller.has_method("get_alive_humanoids_for_settlement") and town.has_method("get_settlement_id"):
		var indexed: Array = actor_query_controller.call("get_alive_humanoids_for_settlement", str(town.call("get_settlement_id")), false)
		if not indexed.is_empty():
			return indexed
	return town.call("get_resident_characters") if town != null and town.has_method("get_resident_characters") else []


func _process_resident(resident: Node, points: Array) -> void:
	if not _can_assign_resident(resident):
		_release_assignment(resident)
		return
	if _has_active_activity_job(resident):
		return
	var point = _choose_activity_point(resident, points)
	if point == null:
		return
	_request_activity_job(resident, point)


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
	if not _is_normal_activity_resident(resident):
		return false
	var life_state = resident.get("life_state")
	if life_state != null and int(life_state) != NpcRules.LifeState.ALIVE:
		return false
	if resident.has_method("is_in_combat") and bool(resident.call("is_in_combat")):
		return false
	if resident.has_method("get_active_job_provider") and resident.call("get_active_job_provider") != null:
		return false
	return resident.has_method("set_move_target") and resident.has_method("request_ai_job")


func _is_normal_activity_resident(resident: Node) -> bool:
	if resident == null:
		return false
	if resident.has_meta("settlement_staff_role") or resident.has_meta("settlement_staff_slot_id"):
		return false
	var category := str(resident.get_meta("settlement_actor_category", "")).strip_edges().to_lower()
	if not category.is_empty() and category != "resident" and category != "townie":
		return false
	var role_id := str(resident.get_meta("actor_role_id", "")).strip_edges().to_lower()
	if ["barkeeper", "waiter", "guard", "barber", "warden", "ruler", "mayor", "merchant", "prisoner"].has(role_id):
		return false
	return true


func _release_assignment(resident: Node) -> void:
	if resident != null and resident.has_method("cancel_ai_job"):
		resident.call("cancel_ai_job", SOURCE_ID)
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("clear_activity_assignment"):
		bridge.call("clear_activity_assignment", resident)


func _has_active_activity_job(resident: Node) -> bool:
	return resident != null and resident.has_method("has_active_ai_job_from_source") and bool(resident.call("has_active_ai_job_from_source", SOURCE_ID))


func _request_activity_job(resident: Node, point: Node) -> void:
	if resident == null or point == null or not resident.has_method("request_ai_job"):
		return
	var duration := _assignment_duration_for_point(point)
	var job = AI_JOB_SCRIPT.new()
	job.job_type = AI_JOB_SCRIPT.JobType.AMBIENT_ACTIVITY
	job.job_id = "%s.%s.%s" % [SOURCE_ID, _actor_key(resident), _point_key(point)]
	job.package_id = "ambient_activity"
	job.source_id = SOURCE_ID
	job.target_id = _point_key(point)
	job.target = point
	job.priority = AI_JOB_SCRIPT.priority_for_type(job.job_type)
	job.debug_label = "Ambient Activity"
	job.debug_reason = "SettlementActivityController assigned %s" % _point_key(point)
	var wait_step = AI_WAIT_STEP_SCRIPT.new()
	wait_step.setup(duration, "Hold Activity")
	job.steps = [
		AI_START_ACTIVITY_STEP_SCRIPT.new(),
		wait_step,
		AI_RELEASE_ACTIVITY_STEP_SCRIPT.new(),
	]
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("set_activity_assignment"):
		bridge.call("set_activity_assignment", resident, point, duration, _sim_time)
	resident.call("request_ai_job", job)


func _get_current_hour() -> int:
	if world_time != null and world_time.has_method("get_hour"):
		return int(world_time.call("get_hour"))
	return 12


func _assignment_duration_for_point(point: Node) -> float:
	var minimum := min_assignment_seconds
	var maximum := max_assignment_seconds
	if point != null:
		var point_min = point.get("assignment_min_seconds")
		var point_max = point.get("assignment_max_seconds")
		if point_min != null and float(point_min) > 0.0:
			minimum = float(point_min)
		if point_max != null and float(point_max) > 0.0:
			maximum = float(point_max)
	maximum = maxf(maximum, minimum)
	return _rng.randf_range(minimum, maximum)


func _actor_key(actor: Node) -> String:
	if actor == null:
		return ""
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).is_empty():
		return str(stable_id)
	return str(actor.get_instance_id())


func _point_key(point: Node) -> String:
	if point == null:
		return ""
	if point.has_method("get_activity_id"):
		return str(point.call("get_activity_id"))
	return str(point.name)


func _town_key(town: Node) -> String:
	if town == null:
		return ""
	if town.has_method("get_settlement_id"):
		return str(town.call("get_settlement_id"))
	return str(town.get_instance_id())


func _sync_activity_points_to_gecs(town: Node, points: Array) -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("upsert_activity_point"):
		return
	var settlement_id := _town_key(town)
	for point in points:
		if point is Node:
			bridge.call("upsert_activity_point", settlement_id, point)


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller")
