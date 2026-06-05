extends Node

class_name SettlementActivityController

@export var tick_interval_seconds := 2.0
@export_range(0.25, 30.0, 0.25) var activity_point_cache_seconds := 5.0

var root_scene: Node
var _tick_remaining := 0.0
var _initialized := false
var _activity_points_by_town: Dictionary = {}
var _activity_point_cache_remaining := 0.0
var _town_cursor := 0


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("settlement_activity_controller")
	_try_initialize()


func _process(delta: float) -> void:
	if not _initialized:
		return
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
	_tick_remaining = maxf(tick_interval_seconds, 0.1)
	_initialized = true


func _process_towns() -> void:
	var towns := get_tree().get_nodes_in_group("settlement_town")
	if towns.is_empty():
		return
	_town_cursor = _town_cursor % towns.size()
	for town_offset in range(towns.size()):
		var town := towns[(_town_cursor + town_offset) % towns.size()] as Node
		if town == null or not town.has_method("get_activity_points"):
			continue
		_get_town_activity_points(town)
	_town_cursor = (_town_cursor + 1) % towns.size()


func _get_town_activity_points(town: Node) -> Array:
	var town_key := _town_key(town)
	if _activity_points_by_town.has(town_key):
		return _activity_points_by_town[town_key]
	var points: Array = town.call("get_activity_points") if town != null and town.has_method("get_activity_points") else []
	_sync_activity_points_to_gecs(town, points)
	_activity_points_by_town[town_key] = points
	return points


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
