extends Node

class_name PopulationRealizationController

const POLICY_FULL_TOWN := "full_town"
const POLICY_IMPORTANT_PLUS_NEAR := "important_plus_near"
const POLICY_NEAR_PLAYER := "near_player"

@export var default_realization_policy := POLICY_FULL_TOWN
@export var near_player_radius := 55.0
@export var realization_resync_interval_seconds := 1.0

var root_scene: Node
var _resync_remaining := 0.0
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_initialized = true
	refresh_from_gecs_state()
	sync_population_realization_state()


func _ready() -> void:
	add_to_group("population_realization_controller")
	_initialized = true
	refresh_from_gecs_state()
	sync_population_realization_state()


func _process(delta: float) -> void:
	if not _initialized or root_scene == null:
		return
	_resync_remaining -= delta
	if _resync_remaining > 0.0:
		return
	_resync_remaining = maxf(realization_resync_interval_seconds, 0.1)
	_resync_population_spawners()


func should_realize_actor(settlement: Node, actor_record: Dictionary, policy := "") -> bool:
	var effective_policy := policy if not str(policy).is_empty() else _policy_for_settlement(settlement)
	match effective_policy:
		POLICY_FULL_TOWN:
			return true
		POLICY_IMPORTANT_PLUS_NEAR:
			return _is_important_actor(actor_record) or _is_record_near_player(actor_record)
		POLICY_NEAR_PLAYER:
			return _is_record_near_player(actor_record)
		_:
			return true


func serialize_state() -> Dictionary:
	sync_population_realization_state()
	return _current_population_realization_state()


func apply_serialized_state(state: Dictionary) -> void:
	default_realization_policy = str(state.get("default_realization_policy", default_realization_policy))
	near_player_radius = float(state.get("near_player_radius", near_player_radius))
	realization_resync_interval_seconds = float(state.get("realization_resync_interval_seconds", realization_resync_interval_seconds))
	sync_population_realization_state()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_population_realization_state"):
		return
	var state: Dictionary = bridge.call("get_population_realization_state")
	if state.is_empty():
		return
	default_realization_policy = str(state.get("default_realization_policy", default_realization_policy))
	near_player_radius = float(state.get("near_player_radius", near_player_radius))
	realization_resync_interval_seconds = float(state.get("realization_resync_interval_seconds", realization_resync_interval_seconds))


func sync_population_realization_state() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_population_realization_state"):
		bridge.call("upsert_population_realization_state", _current_population_realization_state())


func _current_population_realization_state() -> Dictionary:
	return {
		"state_id": "population_realization",
		"default_realization_policy": default_realization_policy,
		"near_player_radius": near_player_radius,
		"realization_resync_interval_seconds": realization_resync_interval_seconds,
	}


func _resync_population_spawners() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for spawner in tree.get_nodes_in_group("population_spawner"):
		if spawner != null and spawner.has_method("needs_population_realization_resync") and not bool(spawner.call("needs_population_realization_resync")):
			continue
		if spawner != null and spawner.has_method("resync_population_realization"):
			spawner.call("resync_population_realization")


func _policy_for_settlement(settlement: Node) -> String:
	if settlement != null:
		var value = settlement.get("actor_realization_policy")
		if value != null and not str(value).strip_edges().is_empty():
			return str(value).strip_edges()
	return default_realization_policy


func _is_important_actor(actor_record: Dictionary) -> bool:
	if bool(actor_record.get("important", false)):
		return true
	var role_id := str(actor_record.get("role_id", "")).strip_edges().to_lower()
	return ["merchant", "barkeeper", "waiter", "guard", "warden", "ruler", "mayor", "worker", "prisoner"].has(role_id)


func _is_record_near_player(actor_record: Dictionary) -> bool:
	var position: Variant = actor_record.get("last_world_position", Vector3.INF)
	if not (position is Vector3):
		return false
	var reference_position: Vector3 = _realization_reference_position()
	if reference_position is Vector3 and reference_position.distance_to(position) <= near_player_radius:
		return true
	return false


func _realization_reference_position() -> Vector3:
	var camera := _get_player_camera()
	if camera is Camera3D:
		return camera.global_position
	return Vector3.INF


func _get_player_camera() -> Camera3D:
	if root_scene != null:
		var explicit_camera: Camera3D = root_scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
		if explicit_camera != null:
			return explicit_camera
	var viewport := get_viewport()
	if viewport != null:
		var active_camera: Camera3D = viewport.get_camera_3d()
		if active_camera != null:
			return active_camera
	if get_tree() != null:
		var cameras: Array = get_tree().get_nodes_in_group("camera")
		for child in cameras:
			if child is Camera3D:
				return child
	return null


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	var existing := get_tree().get_first_node_in_group("gecs_world_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	return null
