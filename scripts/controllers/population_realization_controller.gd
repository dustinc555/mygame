extends Node

class_name PopulationRealizationController

const POLICY_FULL_TOWN := "full_town"
const POLICY_IMPORTANT_PLUS_NEAR := "important_plus_near"
const POLICY_NEAR_PLAYER := "near_player"

## Off-screen NPCs stay as cheap ledger records (sim layer), NOT live GECS actors. Only
## actors near the player (plus flagged-important ones) become full bodies the per-frame
## GECS systems process — so cost scales with the player's surroundings, not world size.
## This is the LOD reaching the SIM layer, not just hiding/freezing bodies.
@export var default_realization_policy := POLICY_NEAR_PLAYER
@export var near_player_radius := 120.0
@export var realization_resync_interval_seconds := 1.0
@export_range(1, 16, 1) var spawner_budget_per_tick := 2
## A realized actor stays realized until a bit past the radius, so pacing the boundary
## doesn't thrash spawn/despawn (the record is cached either way — same person re-appears).
const REALIZATION_HYSTERESIS := 25.0

var root_scene: Node
var _resync_remaining := 0.0
var _initialized := false
var _spawners: Array[Node] = []
var _spawner_cursor := 0
var _spawner_near_by_id: Dictionary = {}


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_initialized = true
	_collect_spawners_once()
	refresh_from_gecs_state()
	sync_population_realization_state()


func _ready() -> void:
	add_to_group("population_realization_controller")
	_initialized = true
	_collect_spawners_once()
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


func register_spawner(spawner: Node) -> void:
	if spawner == null or not is_instance_valid(spawner):
		return
	if _spawners.has(spawner):
		return
	_spawners.append(spawner)


func unregister_spawner(spawner: Node) -> void:
	var index := _spawners.find(spawner)
	if index >= 0:
		_spawners.remove_at(index)
	if spawner != null:
		_spawner_near_by_id.erase(spawner.get_instance_id())
		_update_settlement_activation_for_spawner(spawner)


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
	if _spawners.is_empty():
		_collect_spawners_once()
	if _spawners.is_empty():
		return
	var reference := _realization_reference_position()
	var budget: int = mini(maxi(1, int(spawner_budget_per_tick)), _spawners.size())
	var processed := 0
	while processed < budget and not _spawners.is_empty():
		var spawner := _next_spawner()
		if spawner == null:
			break
		_update_spawner_lod(spawner, reference)
		processed += 1


func _collect_spawners_once() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for spawner in tree.get_nodes_in_group("population_spawner"):
		register_spawner(spawner as Node)


func _next_spawner() -> Node:
	var checked := 0
	while checked < _spawners.size():
		if _spawner_cursor >= _spawners.size():
			_spawner_cursor = 0
		var spawner := _spawners[_spawner_cursor]
		_spawner_cursor += 1
		checked += 1
		if spawner != null and is_instance_valid(spawner) and spawner.is_inside_tree():
			return spawner
		_spawners.remove_at(_spawner_cursor - 1)
		_spawner_cursor = maxi(0, _spawner_cursor - 1)
	return null


func _update_spawner_lod(spawner: Node, reference: Vector3) -> void:
	var policy := _spawner_policy(spawner)
	var key := spawner.get_instance_id()
	var was_near := bool(_spawner_near_by_id.get(key, false))
	var near := policy == POLICY_FULL_TOWN or _is_spawner_near(spawner, reference, was_near)
	_spawner_near_by_id[key] = near
	_update_settlement_activation_for_spawner(spawner)
	var dirty := bool(spawner.call("needs_population_realization_resync")) if spawner.has_method("needs_population_realization_resync") else true
	if near != was_near or dirty:
		if spawner.has_method("resync_population_realization"):
			spawner.call("resync_population_realization")
		if spawner.has_method("clear_population_realization_dirty"):
			spawner.call("clear_population_realization_dirty")
	# When a town leaves LOD range its staff bodies go back to ledger records too — pure on/off,
	# no live bodies linger off-screen. The ledger assignment (who staffs what) is untouched, so
	# the same staff re-realize on return.
	if was_near and not near and spawner.has_method("get_settlement_id"):
		var settlement_controller := get_tree().get_first_node_in_group("settlement_controller") if get_tree() != null else null
		if settlement_controller != null and settlement_controller.has_method("derealize_settlement_staff"):
			settlement_controller.call("derealize_settlement_staff", str(spawner.call("get_settlement_id")))


func _spawner_policy(spawner: Node) -> String:
	if spawner != null and spawner.has_method("get_effective_realization_policy"):
		return str(spawner.call("get_effective_realization_policy"))
	return default_realization_policy


func _is_spawner_near(spawner: Node, reference: Vector3, was_near: bool) -> bool:
	if reference == Vector3.INF or not (spawner is Node3D):
		return false
	var threshold := near_player_radius + (REALIZATION_HYSTERESIS if was_near else 0.0)
	var origin := (spawner as Node3D).global_position
	if spawner.has_method("get_realization_origin"):
		var value = spawner.call("get_realization_origin")
		if value is Vector3:
			origin = value
	return reference.distance_to(origin) <= threshold


func _update_settlement_activation_for_spawner(spawner: Node) -> void:
	if spawner == null or not spawner.has_method("get_settlement_node"):
		return
	var settlement := spawner.call("get_settlement_node") as Node
	if settlement == null or not is_instance_valid(settlement):
		return
	# LOD may realize/derealize actor bodies, but the settlement tree owns facilities,
	# staff slots, and service points that must keep ticking for towns to bootstrap.
	settlement.process_mode = Node.PROCESS_MODE_INHERIT


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
	return ["merchant", "barkeeper", "waiter", "guard", "barber", "warden", "ruler", "mayor", "worker", "prisoner"].has(role_id)


func _is_record_near_player(actor_record: Dictionary) -> bool:
	var position: Variant = actor_record.get("last_world_position", Vector3.INF)
	if not (position is Vector3):
		return false
	var reference_position: Vector3 = _realization_reference_position()
	if not (reference_position is Vector3):
		return false
	# Hysteresis: already-realized actors hold on a bit past the radius so walking the
	# town edge doesn't churn spawn/despawn.
	var threshold := near_player_radius
	if str(actor_record.get("realization_state", "ledger")) == "realized":
		threshold += REALIZATION_HYSTERESIS
	return reference_position.distance_to(position) <= threshold


func _realization_reference_position() -> Vector3:
	for member in _party_members():
		if member is Node3D:
			return member.global_position
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


func _party_members() -> Array:
	if root_scene == null:
		return []
	var manager := root_scene.get_node_or_null("PartyManager")
	if manager != null and manager.get("party_members") is Array:
		return manager.get("party_members") as Array
	return []


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
