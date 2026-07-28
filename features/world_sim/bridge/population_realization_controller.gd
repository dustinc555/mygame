extends Node

class_name PopulationRealizationController

const SERVICE_ID := &"population_realization"

const POLICY_FULL_TOWN := "full_town"
const POLICY_IMPORTANT_PLUS_NEAR := "important_plus_near"
const POLICY_NEAR_PLAYER := "near_player"

## Off-screen NPCs stay as cheap ledger records (sim layer), NOT live GECS actors. Only
## actors near the camera (plus flagged-important ones) become full bodies the per-frame
## GECS systems process — so cost scales with the player's surroundings, not world size.
## This is the LOD reaching the SIM layer, not just hiding/freezing bodies.
@export var default_realization_policy := POLICY_NEAR_PLAYER
@export var near_player_radius := 120.0
## 30m / 5.5m/s = 5.45s of lead time. At the current 1s cadence and four-body
## budget this prepares a typical 20-person town before it reaches visibility.
@export var realization_preload_margin := 30.0
@export var realization_resync_interval_seconds := 1.0
@export var realization_retention_seconds := 900.0
@export_range(1, 16, 1) var spawner_budget_per_tick := 2
@export_range(1, 32, 1) var assignment_slot_budget_per_tick := 4
@export_range(1, 32, 1) var corpse_budget_per_tick := 4
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
var _settlement_by_stable_id: Dictionary = {}
var _assignment_slot_cursor := 0
var _assignment_maintenance_cursor := 0
var _retention_expiry_by_key: Dictionary = {}
var _realized_corpse_ids: Dictionary = {}
var _corpse_transform_restore_pending: Dictionary = {}
var _failed_corpse_realization_ids: Dictionary = {}
var _corpse_realization_cursor := 0
var _corpse_projection_root: Node3D
var _resync_anchors: Array[Vector3] = []
var _mandatory_work_pending := 0
var _last_resync_camera_position := Vector3.INF

const LOADING_SERVICE := &"navigation_loading_overlay"
const LOADING_OWNER_ID := "population_realization"
const MAX_ASSIGNMENT_REALIZATION_FAILURES := 20
const MAX_CORPSE_REALIZATION_FAILURES := 20

var _failed_assignment_realization_attempts: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	_initialized = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_collect_spawners_once()
	_collect_settlements_once()
	_connect_population_deaths()
	_connect_party_lifecycle()
	refresh_from_gecs_state()
	sync_population_realization_state()


func _ready() -> void:
	add_to_group("population_realization_controller")
	_initialized = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_collect_spawners_once()
	_collect_settlements_once()
	_connect_population_deaths()
	_connect_party_lifecycle()
	refresh_from_gecs_state()
	sync_population_realization_state()


func _process(delta: float) -> void:
	if not _initialized or root_scene == null:
		return
	if get_tree().paused and not is_realization_loading_active():
		return
	var camera := _get_player_camera()
	if camera != null and _last_resync_camera_position != Vector3.INF:
		var camera_offset := camera.global_position - _last_resync_camera_position
		camera_offset.y = 0.0
		if camera_offset.length_squared() >= pow(maxf(realization_preload_margin, 1.0), 2.0):
			_resync_remaining = 0.0
	_resync_remaining -= delta
	if _resync_remaining > 0.0:
		return
	_resync_remaining = 0.05 if get_tree().paused else maxf(realization_resync_interval_seconds, 0.1)
	_resync_anchors = get_realization_anchor_positions()
	_last_resync_camera_position = _resync_anchors[0] if not _resync_anchors.is_empty() else Vector3.INF
	_mandatory_work_pending = 0
	_resync_population_spawners(_resync_anchors)
	_resync_settlement_assignments(_resync_anchors)
	_resync_corpses(_resync_anchors)
	_update_loading_request()
	_resync_anchors.clear()


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
	_settlement_by_stable_id[settlement_id] = settlement
	_settlements.append(settlement)


func unregister_settlement(settlement: Node) -> void:
	var settlement_id := str(settlement.call("get_settlement_id")) if settlement != null and settlement.has_method("get_settlement_id") else ""
	var index := _settlements.find(settlement)
	if index >= 0:
		_settlements.remove_at(index)
	if not settlement_id.is_empty() and _settlement_by_stable_id.get(settlement_id) == settlement:
		_settlement_by_stable_id.erase(settlement_id)


func should_realize_actor(settlement: Node, actor_record: Dictionary, policy := "") -> bool:
	var effective_policy := policy if not str(policy).is_empty() else _policy_for_settlement(settlement)
	match effective_policy:
		POLICY_FULL_TOWN:
			return true
		POLICY_IMPORTANT_PLUS_NEAR:
			return _is_important_actor(actor_record) or _is_record_near_player(actor_record, _settlement_id(settlement))
		POLICY_NEAR_PLAYER:
			return _is_record_near_player(actor_record, _settlement_id(settlement))
		_:
			return true


func serialize_state() -> Dictionary:
	sync_population_realization_state()
	return _current_population_realization_state()


func apply_serialized_state(state: Dictionary) -> void:
	_retention_expiry_by_key.clear()
	default_realization_policy = str(state.get("default_realization_policy", default_realization_policy))
	near_player_radius = float(state.get("near_player_radius", near_player_radius))
	realization_preload_margin = float(state.get("realization_preload_margin", realization_preload_margin))
	realization_resync_interval_seconds = float(state.get("realization_resync_interval_seconds", realization_resync_interval_seconds))
	realization_retention_seconds = float(state.get("realization_retention_seconds", realization_retention_seconds))
	sync_population_realization_state()


func refresh_from_gecs_state() -> void:
	_retention_expiry_by_key.clear()
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_population_realization_state"):
		return
	var state: Dictionary = bridge.call("get_population_realization_state")
	if state.is_empty():
		return
	default_realization_policy = str(state.get("default_realization_policy", default_realization_policy))
	near_player_radius = float(state.get("near_player_radius", near_player_radius))
	realization_preload_margin = float(state.get("realization_preload_margin", realization_preload_margin))
	realization_resync_interval_seconds = float(state.get("realization_resync_interval_seconds", realization_resync_interval_seconds))
	realization_retention_seconds = float(state.get("realization_retention_seconds", realization_retention_seconds))


func sync_population_realization_state() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_population_realization_state"):
		bridge.call("upsert_population_realization_state", _current_population_realization_state())


func _current_population_realization_state() -> Dictionary:
	return {
		"state_id": "population_realization",
		"default_realization_policy": default_realization_policy,
		"near_player_radius": near_player_radius,
		"realization_preload_margin": realization_preload_margin,
		"realization_resync_interval_seconds": realization_resync_interval_seconds,
		"realization_retention_seconds": realization_retention_seconds,
	}


func _resync_population_spawners(anchors: Array[Vector3]) -> void:
	if _spawners.is_empty():
		_collect_spawners_once()
	if _spawners.is_empty():
		return
	var urgent: Array[Node] = []
	var maintenance: Array[Node] = []
	_spawner_cursor %= _spawners.size()
	for offset in range(_spawners.size()):
		var spawner := _spawners[(_spawner_cursor + offset) % _spawners.size()]
		if spawner == null or not is_instance_valid(spawner) or not spawner.is_inside_tree():
			continue
		var priority := int(spawner.call("get_population_realization_priority", anchors, get_visible_radius(), get_entry_radius())) if spawner.has_method("get_population_realization_priority") else 2
		if priority < 2:
			urgent.append(spawner)
		else:
			maintenance.append(spawner)
	var ordered: Array[Node] = urgent + maintenance
	var budget: int = mini(maxi(1, int(spawner_budget_per_tick)), ordered.size())
	var processed := 0
	var processed_spawner_ids := {}
	for spawner in ordered:
		if processed >= budget:
			break
		_update_spawner_lod(spawner, anchors, urgent.has(spawner))
		processed_spawner_ids[spawner.get_instance_id()] = true
		processed += 1
	_spawner_cursor = (_spawner_cursor + maxi(processed, 1)) % _spawners.size()
	for spawner in _spawners:
		if spawner != null and is_instance_valid(spawner) and spawner.has_method("count_missing_population_projections"):
			var was_deferred := not processed_spawner_ids.has(spawner.get_instance_id())
			var has_backlog := bool(spawner.call("has_population_realization_backlog")) if spawner.has_method("has_population_realization_backlog") else false
			if was_deferred or has_backlog:
				_mandatory_work_pending += int(spawner.call("count_missing_population_projections", anchors, get_visible_radius()))


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


func _resync_settlement_assignments(anchors: Array[Vector3]) -> void:
	if _settlements.is_empty():
		_collect_settlements_once()
	if _settlements.is_empty():
		return
	var settlement_controller := _context.get_optional(SettlementController.SERVICE_ID) if _context != null else null
	if settlement_controller == null or not settlement_controller.has_method("get_assignment_slots_for_realization"):
		return
	var population := _get_population_controller()
	var urgent: Array[Dictionary] = []
	var maintenance: Array[Dictionary] = []
	var active_retention_keys := {}
	for index in range(_settlements.size() - 1, -1, -1):
		var settlement := _settlements[index]
		if settlement == null or not is_instance_valid(settlement) or not settlement.is_inside_tree():
			_settlements.remove_at(index)
			continue
		if not settlement.has_method("get_settlement_id"):
			continue
		var settlement_id := str(settlement.call("get_settlement_id"))
		for slot_value in settlement_controller.call("get_assignment_slots_for_realization", settlement_id):
			if slot_value is Dictionary:
				var slot: Dictionary = slot_value
				var slot_id := str(slot.get("slot_id", ""))
				var domain := str(slot.get("assignment_domain", ""))
				var occupied := bool(slot.get("filled", false)) and not str(slot.get("occupant_actor_id", "")).is_empty()
				if not occupied:
					continue
				var actor_id := str(slot.get("occupant_actor_id", ""))
				if domain == "residence" and population != null and population.has_method("get_actor_record"):
					var record: Dictionary = population.call("get_actor_record", actor_id)
					if not str((record.get("assignments", {}) as Dictionary).get("employment", "")).is_empty():
						continue
				var realized := bool(settlement_controller.call("is_assignment_slot_realized", settlement_id, domain, slot_id))
				var position = slot.get("world_position", Vector3.INF)
				var within_entry := position is Vector3 and _is_near_any_anchor(position, anchors, get_entry_radius())
				var retention_key := _assignment_retention_key(settlement_id, domain, slot_id)
				if not within_entry and not realized:
					_failed_assignment_realization_attempts.erase(retention_key)
				if within_entry and not realized and int(_failed_assignment_realization_attempts.get(retention_key, 0)) < MAX_ASSIGNMENT_REALIZATION_FAILURES:
					urgent.append(slot)
				elif realized:
					maintenance.append(slot)
				active_retention_keys[retention_key] = true
	prune_realization_retention("assignment:", active_retention_keys)
	for failure_key in _failed_assignment_realization_attempts.keys():
		if not active_retention_keys.has(failure_key):
			_failed_assignment_realization_attempts.erase(failure_key)
	if urgent.is_empty() and maintenance.is_empty():
		_assignment_slot_cursor = 0
		_assignment_maintenance_cursor = 0
		return
	var budget := maxi(assignment_slot_budget_per_tick, 1)
	var attempted_assignment_keys := {}
	_assignment_slot_cursor = _process_assignment_candidates(urgent, _assignment_slot_cursor, budget, settlement_controller, anchors, attempted_assignment_keys)
	var urgent_processed := mini(budget, urgent.size())
	if urgent_processed < budget:
		_assignment_maintenance_cursor = _process_assignment_candidates(maintenance, _assignment_maintenance_cursor, budget - urgent_processed, settlement_controller, anchors, attempted_assignment_keys)
	for slot in urgent:
		var position = slot.get("world_position", Vector3.INF)
		var settlement_id := str(slot.get("settlement_id", ""))
		var slot_id := str(slot.get("slot_id", ""))
		var domain := str(slot.get("assignment_domain", "employment"))
		var slot_key := "%s:%s:%s" % [settlement_id, domain, slot_id]
		var retention_key := _assignment_retention_key(settlement_id, domain, slot_id)
		if not attempted_assignment_keys.has(slot_key) and int(_failed_assignment_realization_attempts.get(retention_key, 0)) < MAX_ASSIGNMENT_REALIZATION_FAILURES and position is Vector3 and _is_near_any_anchor(position, anchors, get_visible_radius()) and not bool(settlement_controller.call("is_assignment_slot_realized", settlement_id, domain, slot_id)):
			_mandatory_work_pending += 1


func _process_assignment_candidates(candidates: Array[Dictionary], cursor: int, budget: int, settlement_controller: Node, anchors: Array[Vector3], attempted_keys: Dictionary) -> int:
	if candidates.is_empty() or budget <= 0:
		return 0
	cursor %= candidates.size()
	var processed := 0
	while processed < mini(budget, candidates.size()):
		var slot: Dictionary = candidates[cursor]
		cursor = (cursor + 1) % candidates.size()
		processed += 1
		var slot_id := str(slot.get("slot_id", ""))
		var settlement_id := str(slot.get("settlement_id", ""))
		var assignment_domain := str(slot.get("assignment_domain", "employment"))
		var actor_id := str(slot.get("occupant_actor_id", ""))
		attempted_keys["%s:%s:%s" % [settlement_id, assignment_domain, slot_id]] = true
		if slot_id.is_empty() or settlement_id.is_empty() or actor_id.is_empty() or not bool(slot.get("filled", false)):
			continue
		var position = slot.get("world_position", Vector3.INF)
		var realized := bool(settlement_controller.call("is_assignment_slot_realized", settlement_id, assignment_domain, slot_id))
		var threshold := get_exit_radius() if realized else get_entry_radius()
		var near := position is Vector3 and _is_near_any_anchor(position, anchors, threshold)
		var retention_key := _assignment_retention_key(settlement_id, assignment_domain, slot_id)
		var keep := should_keep_realized(retention_key, near, realized)
		if keep and not realized:
			if int(_failed_assignment_realization_attempts.get(retention_key, 0)) >= MAX_ASSIGNMENT_REALIZATION_FAILURES:
				continue
			var succeeded := bool(settlement_controller.call("realize_assignment_slot", settlement_id, assignment_domain, slot_id))
			if succeeded:
				_failed_assignment_realization_attempts.erase(retention_key)
			elif position is Vector3 and _is_near_any_anchor(position, anchors, get_visible_radius()):
				var failures := int(_failed_assignment_realization_attempts.get(retention_key, 0)) + 1
				_failed_assignment_realization_attempts[retention_key] = failures
				if failures < MAX_ASSIGNMENT_REALIZATION_FAILURES:
					_mandatory_work_pending += 1
				elif failures == MAX_ASSIGNMENT_REALIZATION_FAILURES:
					push_error("Visible assignment realization failed after %d attempts: %s/%s/%s" % [MAX_ASSIGNMENT_REALIZATION_FAILURES, settlement_id, assignment_domain, slot_id])
		elif keep and realized:
			settlement_controller.call("refresh_assignment_slot_projection", settlement_id, assignment_domain, slot_id)
		elif not keep and realized:
			settlement_controller.call("derealize_assignment_slot", settlement_id, assignment_domain, slot_id)
			_failed_assignment_realization_attempts.erase(retention_key)
	return cursor


func _assignment_retention_key(settlement_id: String, assignment_domain: String, slot_id: String) -> String:
	return "assignment:%s:%s:%s" % [settlement_id, assignment_domain, slot_id]


func _connect_population_deaths() -> void:
	var population := _get_population_controller()
	if population != null and population.has_signal("person_died") and not population.person_died.is_connected(_on_person_died):
		population.person_died.connect(_on_person_died)
	if population != null and population.has_signal("dead_projection_registered") and not population.dead_projection_registered.is_connected(_on_dead_projection_registered):
		population.dead_projection_registered.connect(_on_dead_projection_registered)


func _connect_party_lifecycle() -> void:
	if _context == null:
		return
	var party_manager := _context.get_optional(&"party_manager")
	if party_manager != null and party_manager.has_signal("party_member_added") and not party_manager.party_member_added.is_connected(_on_party_member_added):
		party_manager.party_member_added.connect(_on_party_member_added)


func _on_party_member_added(actor: Node) -> void:
	var population := _get_population_controller()
	if population == null or not population.has_method("release_all_actor_assignments"):
		return
	var actor_id := str(actor.get_meta("actor_record_id", actor.get("stable_id") if actor != null else "")) if actor != null else ""
	if not actor_id.is_empty():
		population.call("release_all_actor_assignments", actor_id)
		var settlement := _context.get_optional(SettlementController.SERVICE_ID) if _context != null else null
		if settlement != null and settlement.has_method("release_actor_facility_assignments"):
			settlement.call("release_actor_facility_assignments", actor_id)


func _on_person_died(actor_id: String) -> void:
	if actor_id.is_empty():
		return
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


func _resync_corpses(anchors: Array[Vector3]) -> void:
	if anchors.is_empty():
		return
	var bridge := _get_gecs_world()
	var population := _get_population_controller()
	if bridge == null or population == null or not bridge.has_method("get_corpse_population_records_near"):
		return
	var nearby_records: Array = []
	var nearby_record_ids := {}
	for anchor in anchors:
		for record_value in bridge.call("get_corpse_population_records_near", anchor, get_entry_radius()):
			if not (record_value is Dictionary):
				continue
			var record_id := str(record_value.get("actor_id", ""))
			if record_id.is_empty() or nearby_record_ids.has(record_id):
				continue
			nearby_record_ids[record_id] = true
			nearby_records.append(record_value)
	for actor_id_value in _failed_corpse_realization_ids.keys():
		if not nearby_record_ids.has(str(actor_id_value)):
			_failed_corpse_realization_ids.erase(actor_id_value)
	if nearby_records.is_empty():
		_corpse_realization_cursor = 0
	else:
		_corpse_realization_cursor %= nearby_records.size()
		nearby_records = nearby_records.slice(_corpse_realization_cursor) + nearby_records.slice(0, _corpse_realization_cursor)
	var nearby_ids := {}
	var attempts_this_tick := 0
	for record_value in nearby_records:
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var actor_id := str(record.get("actor_id", ""))
		if actor_id.is_empty():
			continue
		nearby_ids[actor_id] = true
		var actor = population.call("get_live_actor", actor_id) if population.has_method("get_live_actor") else null
		var deferred_by_budget := false
		if actor == null or not is_instance_valid(actor):
			var failures := int(_failed_corpse_realization_ids.get(actor_id, 0))
			if failures >= MAX_CORPSE_REALIZATION_FAILURES:
				continue
			if attempts_this_tick >= maxi(corpse_budget_per_tick, 1):
				deferred_by_budget = true
				actor = null
			else:
				actor = _realize_corpse(actor_id, record)
				attempts_this_tick += 1
				if actor == null or not is_instance_valid(actor):
					failures += 1
					_failed_corpse_realization_ids[actor_id] = failures
					if _is_near_any_anchor(record.get("last_world_position", Vector3.INF), anchors, get_visible_radius()):
						if failures < MAX_CORPSE_REALIZATION_FAILURES:
							_mandatory_work_pending += 1
						elif failures == MAX_CORPSE_REALIZATION_FAILURES:
							push_error("Visible corpse realization failed after %d attempts: %s" % [MAX_CORPSE_REALIZATION_FAILURES, actor_id])
				else:
					_failed_corpse_realization_ids.erase(actor_id)
		if deferred_by_budget and int(_failed_corpse_realization_ids.get(actor_id, 0)) < MAX_CORPSE_REALIZATION_FAILURES and _is_near_any_anchor(record.get("last_world_position", Vector3.INF), anchors, get_visible_radius()):
			_mandatory_work_pending += 1
		if actor != null and is_instance_valid(actor):
			_restore_corpse_transform_if_pending(actor_id, actor, record)
			_realized_corpse_ids[actor_id] = true
	if not nearby_records.is_empty():
		_corpse_realization_cursor = (_corpse_realization_cursor + maxi(attempts_this_tick, 1)) % nearby_records.size()
	for actor_id_value in _realized_corpse_ids.keys():
		var actor_id := str(actor_id_value)
		var actor = population.call("get_live_actor", actor_id) if population.has_method("get_live_actor") else null
		if actor == null or not is_instance_valid(actor):
			_realized_corpse_ids.erase(actor_id)
			forget_realization_retention("corpse:%s" % actor_id)
			continue
		if int(actor.get("life_state")) != NpcRules.LifeState.DEAD:
			_realized_corpse_ids.erase(actor_id)
			forget_realization_retention("corpse:%s" % actor_id)
			continue
		if _corpse_transform_restore_pending.has(actor_id):
			var record: Dictionary = population.call("get_actor_record", actor_id) if population.has_method("get_actor_record") else {}
			_restore_corpse_transform_if_pending(actor_id, actor, record)
		if bridge.has_method("update_population_corpse_transform") and actor is Node3D:
			bridge.call("update_population_corpse_transform", actor_id, (actor as Node3D).global_transform)
		var near := nearby_ids.has(actor_id) or (actor is Node3D and _is_near_any_anchor((actor as Node3D).global_position, anchors, get_exit_radius(), true))
		if should_keep_realized("corpse:%s" % actor_id, near, true):
			continue
		if population.has_method("unregister_actor"):
			population.call("unregister_actor", actor)
		actor.queue_free()
		_realized_corpse_ids.erase(actor_id)
		forget_realization_retention("corpse:%s" % actor_id)


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


func _update_spawner_lod(spawner: Node, anchors: Array[Vector3], force_resync := false) -> void:
	var policy := _spawner_policy(spawner)
	var key := spawner.get_instance_id()
	var had_lod_state := _spawner_near_by_id.has(key)
	var was_near := bool(_spawner_near_by_id.get(key, false))
	var near := policy == POLICY_FULL_TOWN or _is_spawner_near(spawner, anchors, was_near)
	_spawner_near_by_id[key] = near
	_update_settlement_activation_for_spawner(spawner)
	var dirty := bool(spawner.call("needs_population_realization_resync")) if spawner.has_method("needs_population_realization_resync") else true
	var settlement_id := str(spawner.call("get_settlement_id")) if spawner.has_method("get_settlement_id") else ""
	var has_realized_population := bool(spawner.call("has_realized_population")) if spawner.has_method("has_realized_population") else false
	if force_resync or not had_lod_state or near != was_near or dirty or has_realized_population or _has_pending_retention("actor:%s:" % settlement_id):
		if spawner.has_method("resync_population_realization"):
			spawner.call("resync_population_realization")
		if spawner.has_method("clear_population_realization_dirty"):
			spawner.call("clear_population_realization_dirty")
		_prune_expired_retention("actor:%s:" % settlement_id)


func _spawner_policy(spawner: Node) -> String:
	if spawner != null and spawner.has_method("get_effective_realization_policy"):
		return str(spawner.call("get_effective_realization_policy"))
	return default_realization_policy


func _is_spawner_near(spawner: Node, anchors: Array[Vector3], was_near: bool) -> bool:
	if anchors.is_empty() or not (spawner is Node3D):
		return false
	var threshold := get_exit_radius() if was_near else get_entry_radius()
	var origin := (spawner as Node3D).global_position
	if spawner.has_method("get_realization_origin"):
		var value = spawner.call("get_realization_origin")
		if value is Vector3:
			origin = value
	return _is_near_any_anchor(origin, anchors, threshold)


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


func _is_record_near_player(actor_record: Dictionary, settlement_id: String) -> bool:
	if not bool(actor_record.get("last_world_position_initialized", false)):
		return false
	var position: Variant = actor_record.get("last_world_position", Vector3.INF)
	if not (position is Vector3):
		return false
	var anchors := _resync_anchors if not _resync_anchors.is_empty() else get_realization_anchor_positions()
	# Hysteresis: already-realized actors hold on a bit past the radius so walking the
	# town edge doesn't churn spawn/despawn.
	var threshold := get_entry_radius()
	if str(actor_record.get("realization_state", "ledger")) == "realized":
		threshold = get_exit_radius()
	var near := _is_near_any_anchor(position, anchors, threshold)
	var actor_id := str(actor_record.get("actor_id", ""))
	return should_keep_realized("actor:%s:%s" % [settlement_id, actor_id], near, str(actor_record.get("realization_state", "ledger")) == "realized")


func _settlement_id(settlement: Node) -> String:
	return str(settlement.call("get_settlement_id")) if settlement != null and settlement.has_method("get_settlement_id") else ""


func get_realization_anchor_positions() -> Array[Vector3]:
	var anchors: Array[Vector3] = []
	var camera := _get_player_camera()
	if camera != null:
		anchors.append(camera.global_position)
	return anchors


func get_primary_realization_anchor() -> Vector3:
	var anchors := get_realization_anchor_positions()
	return anchors[0] if not anchors.is_empty() else Vector3.INF


func is_position_within_realization_range(position: Vector3, include_hysteresis := false) -> bool:
	var anchors := get_realization_anchor_positions()
	if anchors.is_empty():
		return DisplayServer.get_name() == "headless"
	var radius := get_exit_radius() if include_hysteresis else get_visible_radius()
	return _is_near_any_anchor(position, anchors, radius)


func get_visible_radius() -> float:
	return maxf(near_player_radius, 0.0)


func get_entry_radius() -> float:
	return get_visible_radius() + maxf(realization_preload_margin, 0.0)


func get_exit_radius() -> float:
	return get_entry_radius() + REALIZATION_HYSTERESIS


func _update_loading_request() -> void:
	var loading := _loading_overlay()
	if loading != null and loading.has_method("set_loading_request"):
		loading.call("set_loading_request", LOADING_OWNER_ID, _mandatory_work_pending > 0)


func _loading_overlay() -> Node:
	return _context.get_optional(LOADING_SERVICE) if _context != null else null


func is_realization_loading_active() -> bool:
	var loading := _loading_overlay()
	return bool(loading.call("is_loading_gate_active", LOADING_OWNER_ID)) if loading != null and loading.has_method("is_loading_gate_active") else false


func set_realization_retention_seconds(value: float) -> void:
	var previous_duration := maxf(realization_retention_seconds, 0.0)
	realization_retention_seconds = maxf(value, 0.0)
	var now := Time.get_ticks_msec() * 0.001
	for key in _retention_expiry_by_key.keys():
		var previous_remaining := float(_retention_expiry_by_key[key]) - now
		var elapsed := maxf(previous_duration - previous_remaining, 0.0)
		_retention_expiry_by_key[key] = now + maxf(realization_retention_seconds - elapsed, 0.0)
	sync_population_realization_state()


func should_keep_realized(cache_key: String, near: bool, realized: bool) -> bool:
	if cache_key.is_empty():
		return near
	if near:
		_retention_expiry_by_key.erase(cache_key)
		return true
	if not realized:
		_retention_expiry_by_key.erase(cache_key)
		return false
	var now := Time.get_ticks_msec() * 0.001
	if not _retention_expiry_by_key.has(cache_key):
		_retention_expiry_by_key[cache_key] = now + maxf(realization_retention_seconds, 0.0)
	if now < float(_retention_expiry_by_key[cache_key]):
		return true
	_retention_expiry_by_key.erase(cache_key)
	return false


func forget_realization_retention(cache_key: String) -> void:
	_retention_expiry_by_key.erase(cache_key)


func prune_realization_retention(prefix: String, active_keys: Dictionary) -> void:
	for key_value in _retention_expiry_by_key.keys():
		var key := str(key_value)
		if key.begins_with(prefix) and not active_keys.has(key):
			_retention_expiry_by_key.erase(key_value)


func _prune_expired_retention(prefix: String) -> void:
	var now := Time.get_ticks_msec() * 0.001
	for key_value in _retention_expiry_by_key.keys():
		var key := str(key_value)
		if key.begins_with(prefix) and now >= float(_retention_expiry_by_key[key_value]):
			_retention_expiry_by_key.erase(key_value)


func _has_pending_retention(prefix: String) -> bool:
	for key_value in _retention_expiry_by_key.keys():
		if str(key_value).begins_with(prefix):
			return true
	return false


func _is_near_any_anchor(position: Vector3, anchors: Array[Vector3], radius: float, _flat := true) -> bool:
	var radius_squared := radius * radius
	for anchor in anchors:
		var offset := position - anchor
		offset.y = 0.0
		if offset.length_squared() <= radius_squared:
			return true
	return false


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
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null
