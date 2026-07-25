extends Node

class_name PopulationRealizationController

const SERVICE_ID := &"population_realization"

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
var _context: BootstrapContext
var _resync_remaining := 0.0
var _initialized := false
var _spawners: Array[Node] = []
var _spawner_cursor := 0
var _spawner_near_by_id: Dictionary = {}
var _settlements: Array[Node] = []
var _settlement_near_by_id: Dictionary = {}
var _settlement_by_stable_id: Dictionary = {}
var _realized_corpse_ids: Dictionary = {}
var _corpse_transform_restore_pending: Dictionary = {}
var _corpse_projection_root: Node3D


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	_initialized = true
	_collect_spawners_once()
	_collect_settlements_once()
	_connect_population_deaths()
	refresh_from_gecs_state()
	sync_population_realization_state()


func _ready() -> void:
	add_to_group("population_realization_controller")
	_initialized = true
	_collect_spawners_once()
	_collect_settlements_once()
	_connect_population_deaths()
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
	_resync_settlement_staff()
	_resync_corpses()


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


func register_settlement(settlement: Node) -> void:
	if settlement == null or not is_instance_valid(settlement) or not settlement.has_method("get_settlement_id"):
		return
	var settlement_id := str(settlement.call("get_settlement_id"))
	if settlement_id.is_empty():
		return
	var previous: Node = _settlement_by_stable_id.get(settlement_id)
	if previous == settlement:
		return
	if previous != null and is_instance_valid(previous):
		_settlements.erase(previous)
		_settlement_near_by_id.erase(previous.get_instance_id())
	_settlement_by_stable_id[settlement_id] = settlement
	_settlements.append(settlement)


func unregister_settlement(settlement: Node) -> void:
	var settlement_id := str(settlement.call("get_settlement_id")) if settlement != null and settlement.has_method("get_settlement_id") else ""
	var index := _settlements.find(settlement)
	if index >= 0:
		_settlements.remove_at(index)
	if settlement != null:
		_settlement_near_by_id.erase(settlement.get_instance_id())
	if not settlement_id.is_empty() and _settlement_by_stable_id.get(settlement_id) == settlement:
		_settlement_by_stable_id.erase(settlement_id)


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


func _collect_settlements_once() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for settlement in tree.get_nodes_in_group("settlement_town"):
		register_settlement(settlement as Node)


func _resync_settlement_staff() -> void:
	if _settlements.is_empty():
		_collect_settlements_once()
	if _settlements.is_empty():
		return
	var reference := _realization_reference_position()
	var settlement_controller := get_tree().get_first_node_in_group("settlement_controller") if get_tree() != null else null
	if settlement_controller == null or not settlement_controller.has_method("set_settlement_staff_lod_active"):
		return
	for index in range(_settlements.size() - 1, -1, -1):
		var settlement := _settlements[index]
		if settlement == null or not is_instance_valid(settlement) or not settlement.is_inside_tree():
			_settlements.remove_at(index)
			continue
		if not (settlement is Node3D) or not settlement.has_method("get_settlement_id"):
			continue
		var key := settlement.get_instance_id()
		var had_lod_state := _settlement_near_by_id.has(key)
		var was_near := bool(_settlement_near_by_id.get(key, false))
		var threshold := near_player_radius + (REALIZATION_HYSTERESIS if was_near else 0.0)
		var near := reference != Vector3.INF and reference.distance_to((settlement as Node3D).global_position) <= threshold
		_settlement_near_by_id[key] = near
		if not had_lod_state or near != was_near:
			settlement_controller.call("set_settlement_staff_lod_active", str(settlement.call("get_settlement_id")), near)


func _connect_population_deaths() -> void:
	var population := _get_population_controller()
	if population != null and population.has_signal("person_died") and not population.person_died.is_connected(_on_person_died):
		population.person_died.connect(_on_person_died)
	if population != null and population.has_signal("dead_projection_registered") and not population.dead_projection_registered.is_connected(_on_dead_projection_registered):
		population.dead_projection_registered.connect(_on_dead_projection_registered)


func _on_person_died(actor_id: String) -> void:
	if not actor_id.is_empty():
		_realized_corpse_ids[actor_id] = true
	_remove_dead_person_from_active_party(actor_id)


func _on_dead_projection_registered(actor_id: String) -> void:
	if actor_id.is_empty():
		return
	_realized_corpse_ids[actor_id] = true
	_corpse_transform_restore_pending[actor_id] = true
	_remove_dead_person_from_active_party(actor_id)


func _remove_dead_person_from_active_party(actor_id: String) -> void:
	var population := _get_population_controller()
	var actor = population.call("get_live_actor", actor_id) if population != null and population.has_method("get_live_actor") else null
	if actor == null or not is_instance_valid(actor) or not (actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member"))):
		return
	var managers: Array = get_tree().get_nodes_in_group("party_manager") if get_tree() != null else []
	for manager in managers:
		if manager.has_method("unregister_party_member"):
			manager.call("unregister_party_member", actor)


func _resync_corpses() -> void:
	var reference := _realization_reference_position()
	if reference == Vector3.INF:
		return
	var bridge := _get_gecs_world()
	var population := _get_population_controller()
	if bridge == null or population == null or not bridge.has_method("get_corpse_population_records_near"):
		return
	var nearby_records: Array = bridge.call("get_corpse_population_records_near", reference, near_player_radius)
	var nearby_ids := {}
	for record_value in nearby_records:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var actor_id := str(record.get("actor_id", ""))
		if actor_id.is_empty():
			continue
		nearby_ids[actor_id] = true
		var actor = population.call("get_live_actor", actor_id) if population.has_method("get_live_actor") else null
		if actor == null or not is_instance_valid(actor):
			actor = _realize_corpse(actor_id, record)
		if actor != null and is_instance_valid(actor):
			_restore_corpse_transform_if_pending(actor_id, actor, record)
			_adopt_corpse_projection(actor)
			_realized_corpse_ids[actor_id] = true
	for actor_id_value in _realized_corpse_ids.keys():
		var actor_id := str(actor_id_value)
		var actor = population.call("get_live_actor", actor_id) if population.has_method("get_live_actor") else null
		if actor == null or not is_instance_valid(actor):
			_realized_corpse_ids.erase(actor_id)
			continue
		if int(actor.get("life_state")) != NpcRules.LifeState.DEAD:
			_realized_corpse_ids.erase(actor_id)
			continue
		if _corpse_transform_restore_pending.has(actor_id):
			var record: Dictionary = population.call("get_actor_record", actor_id) if population.has_method("get_actor_record") else {}
			_restore_corpse_transform_if_pending(actor_id, actor, record)
		if bridge.has_method("update_population_corpse_transform") and actor is Node3D:
			bridge.call("update_population_corpse_transform", actor_id, (actor as Node3D).global_transform)
		var offset := (actor as Node3D).global_position - reference if actor is Node3D else Vector3.ZERO
		offset.y = 0.0
		if nearby_ids.has(actor_id) or offset.length() <= near_player_radius + REALIZATION_HYSTERESIS:
			continue
		if population.has_method("unregister_actor"):
			population.call("unregister_actor", actor)
		actor.queue_free()
		_realized_corpse_ids.erase(actor_id)


func _restore_corpse_transform_if_pending(actor_id: String, actor: Node, record: Dictionary) -> void:
	if not _corpse_transform_restore_pending.has(actor_id) or not (actor is Node3D):
		return
	if bool(record.get("last_world_transform_initialized", false)):
		(actor as Node3D).global_transform = record.get("last_world_transform", Transform3D.IDENTITY)
	elif bool(record.get("last_world_position_initialized", false)):
		(actor as Node3D).global_position = record.get("last_world_position", Vector3.ZERO)
	_corpse_transform_restore_pending.erase(actor_id)


func _realize_corpse(actor_id: String, record: Dictionary) -> Node:
	var realizer := _context.get_optional(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer if _context != null else null
	var root := _get_corpse_projection_root()
	if realizer == null or root == null:
		return null
	var actor := realizer.realize_record_actor(actor_id, root, "Corpse_%s" % actor_id.replace(".", "_"))
	if actor is Node3D:
		if bool(record.get("last_world_transform_initialized", false)):
			(actor as Node3D).global_transform = record.get("last_world_transform", Transform3D.IDENTITY)
		elif bool(record.get("last_world_position_initialized", false)):
			(actor as Node3D).global_position = record.get("last_world_position", Vector3.ZERO)
	return actor


func _adopt_corpse_projection(actor: Node) -> void:
	if not (actor is Node3D) or (actor.has_method("is_carried") and bool(actor.call("is_carried"))):
		return
	var root := _get_corpse_projection_root()
	if root == null or actor.get_parent() == root:
		return
	var transform := (actor as Node3D).global_transform
	actor.reparent(root)
	(actor as Node3D).global_transform = transform


func _get_corpse_projection_root() -> Node3D:
	if _corpse_projection_root != null and is_instance_valid(_corpse_projection_root):
		return _corpse_projection_root
	if root_scene == null:
		return null
	_corpse_projection_root = root_scene.get_node_or_null("CorpseProjections") as Node3D
	if _corpse_projection_root == null:
		_corpse_projection_root = Node3D.new()
		_corpse_projection_root.name = "CorpseProjections"
		root_scene.add_child(_corpse_projection_root)
	return _corpse_projection_root


func _get_population_controller() -> Node:
	if _context != null:
		var population := _context.get_optional(PopulationController.SERVICE_ID)
		if population != null:
			return population
	return get_tree().get_first_node_in_group("population_controller") if get_tree() != null else null


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
	var had_lod_state := _spawner_near_by_id.has(key)
	var was_near := bool(_spawner_near_by_id.get(key, false))
	var near := policy == POLICY_FULL_TOWN or _is_spawner_near(spawner, reference, was_near)
	_spawner_near_by_id[key] = near
	_update_settlement_activation_for_spawner(spawner)
	var dirty := bool(spawner.call("needs_population_realization_resync")) if spawner.has_method("needs_population_realization_resync") else true
	if not had_lod_state or near != was_near or dirty:
		if spawner.has_method("resync_population_realization"):
			spawner.call("resync_population_realization")
		if spawner.has_method("clear_population_realization_dirty"):
			spawner.call("clear_population_realization_dirty")


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
	var dead_fallback := Vector3.INF
	for member in _party_members():
		if member is Node3D:
			if dead_fallback == Vector3.INF:
				dead_fallback = member.global_position
			var life_state = member.get("life_state")
			if life_state == null or int(life_state) != NpcRules.LifeState.DEAD:
				return member.global_position
	var camera := _get_player_camera()
	if camera is Camera3D:
		return camera.global_position
	return dead_fallback


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
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null
