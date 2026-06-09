extends Node

class_name WorldActorProjectionController

const WORLD_ACTOR_PROJECTION_SCRIPT := preload("res://scripts/projection/world_actor_projection.gd")
const HUMANOID_BODY_PROJECTION_SCRIPT := preload("res://scripts/projection/humanoid_body_projection.gd")
const PLACEHOLDER_BODY_PROJECTION_SCRIPT := preload("res://scripts/projection/placeholder_body_projection.gd")
const COMBAT_MOVE_IN_DISTANCE := 0.55
const COMBAT_ATTACK_STEP_DISTANCE := 0.18
const COMBAT_REACTION_STEP_DISTANCE := 0.10
const COMBAT_AFTERMATH_HOLD_SECONDS := 1.4
const COMBAT_VISIBLE_ATTACK_RANGE := 1.6
const COMBAT_VISIBLE_APPROACH_STEP_DISTANCE := 0.18
const COMBAT_VISIBLE_APPROACH_STOP_RATIO := 0.82
const VISIBLE_COMBAT_PLAYER_PARTY_ID := "player_party"
const VISIBLE_COMBAT_LIFE_STATE_ALIVE := 0
const VISIBLE_COMBAT_LIFE_STATE_DYING := 5
const VISIBLE_COMBAT_STANCE_PASSIVE := 2
const VISIBLE_COMBAT_ATTACK_ANIMATION_SECONDS := 0.95
const VISIBLE_COMBAT_ATTACK_IMPACT_RATIO := 0.45
const VISIBLE_COMBAT_REACTION_ANIMATION_SECONDS := 0.55
const VISIBLE_COMBAT_DOWNED_ANIMATION_SECONDS := 1.15
const VISIBLE_COMBAT_BODY_RADIUS := 0.55
const VISIBLE_COMBAT_RESERVATION_CELL_SIZE := 1.1

@export var auto_project := true
@export_range(0.05, 5.0, 0.05) var projection_update_interval_seconds := 0.25
@export var projection_root_name := "WorldActorProjections"
@export var max_projected_actor_count := 0
@export var performance_logging_enabled := false
@export_range(0.1, 10.0, 0.1) var performance_log_interval_seconds := 1.0
@export_range(0.0, 50000.0, 100.0) var performance_log_threshold_usec := 1000.0
@export var combat_schedule_projection_enabled := true
@export var combat_schedule_loop_enabled := false
@export_range(0.1, 4.0, 0.05) var combat_schedule_playback_speed := 1.0
@export_range(0.05, 1.0, 0.05) var combat_schedule_scan_interval_seconds := 0.1
@export var visible_combat_runtime_enabled := true
@export_range(1.0, 80.0, 0.5) var visible_combat_detection_range := 30.0
@export_range(0.5, 5.0, 0.1) var visible_combat_attack_range := 1.6
@export_range(1.0, 20.0, 0.5) var visible_combat_assist_radius := 8.0
@export_range(2, 12, 1) var visible_combat_cluster_cap := 6
@export_range(0.75, 8.0, 0.1) var visible_combat_walk_speed := 2.4
@export_range(1.0, 12.0, 0.1) var visible_combat_run_speed := 5.2
@export_range(0.25, 3.0, 0.05) var visible_combat_attack_cooldown := 1.05
@export_range(0.75, 4.0, 0.05) var visible_combat_lane_width := 1.65

var root_scene: Node
var _projection_root: Node3D
var _projection_by_actor_id: Dictionary = {}
var _initialized := false
var _update_elapsed := 0.0
var _unsupported_projection_kinds: Dictionary = {}
var _equipment_slots_cache_by_actor_id: Dictionary = {}
var _equipment_slots_cache_dirty := true
var _equipment_signal_bridge: Node
var _perf_log_next_msec_by_label: Dictionary = {}
var _last_projection_metrics: Dictionary = {}
var _combat_scan_elapsed := 0.0
var _combat_cached_encounter: Dictionary = {}
var _combat_playback_key := ""
var _combat_playback_time := 0.0
var _combat_playback_duration := 0.0
var _combat_battle_result: Dictionary = {}
var _combat_fleeing_squad_id := ""
var _combat_slots: Dictionary = {}
var _combat_slot_by_occupant_id: Dictionary = {}
var _combat_schedule_events: Array[Dictionary] = []
var _combat_casualty_actor_ids: Array[String] = []
var _combat_casualty_actor_lookup: Dictionary = {}
var _combat_projection_metrics: Dictionary = {}
var _combat_actor_presentation_state_by_id: Dictionary = {}
var _latest_population_records_by_actor_id: Dictionary = {}
var _visible_combat_state_by_actor_id: Dictionary = {}
var _visible_combat_controlled_actor_ids: Dictionary = {}
var _visible_combat_metrics: Dictionary = {}
var _visible_combat_elapsed := 0.0


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_initialized = false
	_try_initialize()


func _ready() -> void:
	add_to_group("world_actor_projection_controller")


func _exit_tree() -> void:
	_disconnect_equipment_cache_signal()


func _process(delta: float) -> void:
	if not _try_initialize():
		return
	if auto_project:
		_update_elapsed += delta
		if _update_elapsed >= projection_update_interval_seconds:
			_update_elapsed = 0.0
			sync_projections()
	if visible_combat_runtime_enabled:
		_apply_visible_combat_runtime(delta)
	if combat_schedule_projection_enabled and not _visible_combat_runtime_active():
		_apply_combat_schedule_projection(delta)


func sync_projections() -> void:
	var started_at_usec := Time.get_ticks_usec() if performance_logging_enabled else 0
	if not _try_initialize():
		return
	var bridge := _get_gecs_world()
	if bridge == null:
		return
	var records := _get_population_records_core(bridge)
	_latest_population_records_by_actor_id = records.duplicate(true)
	var equipment_by_actor := _equipment_slots_by_actor(bridge)
	var expected_actor_ids := {}
	var metrics := _projection_metrics_base(records.size())
	for actor_id_value in _projection_record_keys(records):
		var record_value = records[actor_id_value]
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var actor_id := str(record.get("actor_id", actor_id_value)).strip_edges()
		if actor_id.is_empty():
			continue
		var projection_kind := _projection_kind_for_record(record)
		if not can_project_kind(projection_kind):
			_note_unsupported_kind(projection_kind)
			metrics["unsupported_projection_count"] = int(metrics.get("unsupported_projection_count", 0)) + 1
			_remove_projection(actor_id)
			continue
		metrics["eligible_projection_count"] = int(metrics.get("eligible_projection_count", 0)) + 1
		if _projection_cap_reached(expected_actor_ids.size()):
			metrics["skipped_projection_count"] = int(metrics.get("skipped_projection_count", 0)) + 1
			continue
		expected_actor_ids[actor_id] = true
		if _visible_combat_runtime_controls_actor(actor_id) and get_projection_for_actor(actor_id) != null:
			continue
		project_record_snapshot(record, equipment_by_actor.get(actor_id, {}))
	_remove_stale_projections(expected_actor_ids)
	metrics["projected_actor_count"] = _projection_by_actor_id.size()
	metrics["realized_actor_count"] = _projection_by_actor_id.size()
	metrics["visible_actor_count"] = _visible_projection_count()
	metrics["projection_counts_by_kind"] = get_projection_counts_by_kind()
	metrics.merge(_combat_projection_report_metrics(), true)
	metrics.merge(_visible_combat_report_metrics(), true)
	_last_projection_metrics = metrics
	_log_perf_duration("projection.sync_projections", started_at_usec, {"records": records.size(), "projections": _projection_by_actor_id.size(), "skipped": int(metrics.get("skipped_projection_count", 0))})


func project_record_snapshot(record: Dictionary, equipment_slots: Dictionary = {}, combat_state: Dictionary = {}) -> Node:
	if not _try_initialize() or record.is_empty():
		return null
	var actor_id := str(record.get("actor_id", record.get("stable_id", ""))).strip_edges()
	if actor_id.is_empty():
		return null
	var projection_kind := _projection_kind_for_record(record)
	if not can_project_kind(projection_kind):
		_note_unsupported_kind(projection_kind)
		return null
	var projection := _get_or_create_projection(actor_id, projection_kind)
	if projection == null:
		return null
	projection.apply_projection_snapshot(record, equipment_slots, combat_state)
	return projection


func can_project_kind(projection_kind: String) -> bool:
	return _body_script_for_kind(projection_kind) != null


func get_projection_for_actor(actor_id: String) -> Node:
	var projection = _projection_by_actor_id.get(actor_id)
	return projection as Node if projection != null and is_instance_valid(projection) else null


func get_projection_count() -> int:
	return _projection_by_actor_id.size()


func get_projection_counts_by_kind() -> Dictionary:
	var counts := {}
	for projection in _projection_by_actor_id.values():
		if projection == null or not is_instance_valid(projection):
			continue
		var kind := str((projection as Node).get("projection_kind"))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


func get_unsupported_projection_kinds() -> Dictionary:
	return _unsupported_projection_kinds.duplicate()


func get_projection_performance_metrics() -> Dictionary:
	var metrics := _last_projection_metrics.duplicate(true)
	metrics["projected_actor_count"] = _projection_by_actor_id.size()
	metrics["realized_actor_count"] = _projection_by_actor_id.size()
	metrics["visible_actor_count"] = _visible_projection_count()
	metrics["max_projected_actor_count"] = maxi(0, max_projected_actor_count)
	metrics["projection_cap_active"] = max_projected_actor_count > 0
	metrics["projection_counts_by_kind"] = get_projection_counts_by_kind()
	metrics.merge(_combat_projection_report_metrics(), true)
	metrics.merge(_visible_combat_report_metrics(), true)
	return metrics


func _apply_visible_combat_runtime(delta: float) -> void:
	var started_usec := Time.get_ticks_usec()
	_visible_combat_elapsed += maxf(delta, 0.0)
	var records := _latest_population_records_by_actor_id
	if records.is_empty():
		var bridge := _get_gecs_world()
		if bridge != null:
			records = _get_population_records_core(bridge)
			_latest_population_records_by_actor_id = records.duplicate(true)
	var actor_update_count := 0
	_visible_combat_controlled_actor_ids.clear()
	var locked_actor_ids := {}
	var reserved_cells := {}
	for state_actor_id_value in _visible_combat_state_by_actor_id.keys():
		var state_actor_id := str(state_actor_id_value).strip_edges()
		if state_actor_id.is_empty():
			continue
		if _visible_combat_tick_existing_action(state_actor_id, records, reserved_cells, delta):
			locked_actor_ids[state_actor_id] = true
			actor_update_count += 1
	var players: Array[String] = []
	var raiders: Array[String] = []
	var player_factions := {}
	for actor_id_value in records.keys():
		var record: Dictionary = records.get(actor_id_value, {}) if records.get(actor_id_value, {}) is Dictionary else {}
		var actor_id := str(record.get("actor_id", actor_id_value)).strip_edges()
		if actor_id.is_empty() or not _visible_combat_record_is_alive(record) or get_projection_for_actor(actor_id) == null:
			continue
		if _visible_combat_record_is_player_party(record):
			players.append(actor_id)
			var faction_id := str(record.get("faction_id", "")).strip_edges()
			if not faction_id.is_empty():
				player_factions[faction_id] = true
	if players.is_empty():
		if actor_update_count > 0:
			_visible_combat_apply_actor_action_metrics(started_usec, players.size(), raiders.size(), actor_update_count)
			return
		_clear_visible_combat_runtime()
		return
	for actor_id_value in records.keys():
		var record: Dictionary = records.get(actor_id_value, {}) if records.get(actor_id_value, {}) is Dictionary else {}
		var actor_id := str(record.get("actor_id", actor_id_value)).strip_edges()
		if actor_id.is_empty() or not _visible_combat_record_is_alive(record) or get_projection_for_actor(actor_id) == null:
			continue
		if _visible_combat_record_is_player_party(record):
			continue
		if _visible_combat_record_is_raider(record, player_factions):
			raiders.append(actor_id)
	if raiders.is_empty():
		if actor_update_count > 0:
			_visible_combat_apply_actor_action_metrics(started_usec, players.size(), raiders.size(), actor_update_count)
			return
		_clear_visible_combat_runtime()
		return
	var players_by_lane := _visible_combat_actor_lanes(players)
	var target_by_raider := {}
	var attack_index_by_target := {}
	var attacker_by_target := {}
	var attacker_by_lane := {}
	for raider_index in range(raiders.size()):
		var raider_id := raiders[raider_index]
		var target_id := _visible_combat_target_for_raider(raider_id, raider_index, players, players_by_lane)
		if target_id.is_empty():
			continue
		target_by_raider[raider_id] = target_id
		if not attacker_by_target.has(target_id):
			attacker_by_target[target_id] = raider_id
		var target_lane := _visible_combat_lane(_visible_combat_actor_position(target_id, records.get(target_id, {})))
		if not attacker_by_lane.has(target_lane):
			attacker_by_lane[target_lane] = raider_id
	var attacked_players := {}
	for raider_id in raiders:
		if locked_actor_ids.has(raider_id):
			continue
		if not target_by_raider.has(raider_id):
			continue
		var target_id := str(target_by_raider.get(raider_id, ""))
		var attack_index := int(attack_index_by_target.get(target_id, 0))
		attack_index_by_target[target_id] = attack_index + 1
		var controls_actor := _visible_combat_update_actor(raider_id, target_id, records, reserved_cells, "raider", attack_index, false, delta)
		if controls_actor:
			actor_update_count += 1
		if bool(_visible_combat_state_by_actor_id.get(target_id, {}).get("under_attack", false)):
			attacked_players[target_id] = true
	var threatened_lanes := {}
	var first_attacker_id := ""
	for raider_id in target_by_raider.keys():
		var target_id := str(target_by_raider.get(raider_id, "")).strip_edges()
		if target_id.is_empty():
			continue
		if first_attacker_id.is_empty():
			first_attacker_id = str(raider_id)
		threatened_lanes[_visible_combat_lane(_visible_combat_actor_position(target_id, records.get(target_id, {})))] = true
	for player_id in attacked_players.keys():
		threatened_lanes[_visible_combat_lane(_visible_combat_actor_position(str(player_id), records.get(player_id, {})))] = true
	var defender_index_by_target := {}
	for player_id in players:
		var player_record: Dictionary = records.get(player_id, {}) if records.get(player_id, {}) is Dictionary else {}
		if locked_actor_ids.has(player_id):
			continue
		if _visible_combat_player_control_override(player_record):
			_visible_combat_reserve_position(player_id, _visible_combat_actor_position(player_id, player_record), reserved_cells)
			continue
		var defender_target := ""
		if attacked_players.has(player_id) and attacker_by_target.has(player_id):
			defender_target = str(attacker_by_target.get(player_id, ""))
		else:
			var player_lane := _visible_combat_lane(_visible_combat_actor_position(player_id, player_record))
			defender_target = _visible_combat_attacker_for_lane(player_lane, attacker_by_lane, threatened_lanes, first_attacker_id)
		if defender_target.is_empty():
			_visible_combat_reserve_position(player_id, _visible_combat_actor_position(player_id, player_record), reserved_cells)
			_visible_combat_apply_idle(player_id, player_record)
			continue
		var defender_index := int(defender_index_by_target.get(defender_target, 0))
		defender_index_by_target[defender_target] = defender_index + 1
		var controls_defender := _visible_combat_update_actor(player_id, defender_target, records, reserved_cells, "defender", defender_index, true, delta)
		if controls_defender:
			actor_update_count += 1
	_visible_combat_metrics = {
		"visible_combat_runtime_enabled": visible_combat_runtime_enabled,
		"visible_combat_runtime_active": true,
		"visible_combat_player_count": players.size(),
		"visible_combat_raider_count": raiders.size(),
		"visible_combat_controlled_actor_count": _visible_combat_controlled_actor_ids.size(),
		"visible_combat_attacked_player_count": attacked_players.size(),
		"visible_combat_actor_update_count": actor_update_count,
		"visible_combat_update_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"visible_combat_complexity": "O(n)",
	}


func _visible_combat_update_actor(actor_id: String, target_id: String, records: Dictionary, reserved_cells: Dictionary, role: String, target_index: int, defensive: bool, delta: float) -> bool:
	var projection := get_projection_for_actor(actor_id)
	var target_projection := get_projection_for_actor(target_id)
	if projection == null or target_projection == null:
		return false
	var actor_record: Dictionary = records.get(actor_id, {}) if records.get(actor_id, {}) is Dictionary else {}
	var target_record: Dictionary = records.get(target_id, {}) if records.get(target_id, {}) is Dictionary else {}
	if _visible_combat_actor_downed(actor_id, actor_record):
		_visible_combat_apply_downed(actor_id, actor_record)
		_visible_combat_reserve_position(actor_id, _projection_world_position(projection, _visible_combat_record_position(actor_record)), reserved_cells)
		return true
	var state := _visible_combat_state(actor_id, actor_record)
	state["role"] = role
	state["target_id"] = target_id
	var actor_position := _projection_world_position(projection, _visible_combat_record_position(actor_record))
	var target_position := _projection_world_position(target_projection, _visible_combat_record_position(target_record))
	if _visible_combat_update_locked_animation(actor_id, projection, state, actor_position, target_position, delta):
		_visible_combat_reserve_position(actor_id, actor_position, reserved_cells)
		return true
	var offset := _visible_combat_target_offset(actor_position, target_position, target_index, defensive)
	var desired_position := target_position + offset
	desired_position.y = actor_position.y
	var distance_to_target := _xz_distance_squared(actor_position, target_position)
	var attack_range := maxf(visible_combat_attack_range, 0.1)
	var in_attack_range := distance_to_target <= attack_range * attack_range
	if not in_attack_range:
		var speed := visible_combat_run_speed if actor_position.distance_to(desired_position) > 4.0 else visible_combat_walk_speed
		var next_position := actor_position.move_toward(desired_position, speed * maxf(delta, 0.0))
		next_position = _visible_combat_reserve_position(actor_id, next_position, reserved_cells)
		_apply_projection_visual(projection, next_position, _combat_facing_yaw(next_position, target_position), {"state": "move", "event_id": "%s:visible_move" % actor_id, "role": role, "target_id": target_id}, 0.0)
		state["attack_cooldown"] = maxf(float(state.get("attack_cooldown", 0.0)) - delta, 0.0)
		state["under_attack"] = _visible_combat_elapsed < float(state.get("under_attack_until", 0.0))
		_visible_combat_state_by_actor_id[actor_id] = state
		_visible_combat_controlled_actor_ids[actor_id] = true
		return true
	var cooldown := maxf(float(state.get("attack_cooldown", 0.0)) - delta, 0.0)
	if cooldown <= 0.0:
		actor_position = _visible_combat_reserve_position(actor_id, actor_position, reserved_cells)
		_visible_combat_begin_attack(actor_id, target_id, projection, state)
		_visible_combat_state_by_actor_id[actor_id] = state
		_visible_combat_update_locked_animation(actor_id, projection, state, actor_position, target_position, 0.0)
	else:
		actor_position = _visible_combat_reserve_position(actor_id, actor_position, reserved_cells)
		_apply_projection_visual(projection, actor_position, _combat_facing_yaw(actor_position, target_position), {"state": "combat_idle", "event_id": "%s:visible_ready" % actor_id, "role": role, "target_id": target_id}, 0.0)
		state["attack_cooldown"] = cooldown
	state["under_attack"] = _visible_combat_elapsed < float(state.get("under_attack_until", 0.0))
	_visible_combat_state_by_actor_id[actor_id] = state
	_visible_combat_controlled_actor_ids[actor_id] = true
	return true


func _visible_combat_tick_existing_action(actor_id: String, records: Dictionary, reserved_cells: Dictionary, delta: float) -> bool:
	var state: Dictionary = _visible_combat_state_by_actor_id.get(actor_id, {}) if _visible_combat_state_by_actor_id.get(actor_id, {}) is Dictionary else {}
	var action := str(state.get("action", "")).strip_edges()
	var record: Dictionary = records.get(actor_id, {}) if records.get(actor_id, {}) is Dictionary else {}
	if action.is_empty() and not bool(state.get("downed", false)) and _visible_combat_record_is_alive(record):
		return false
	var projection := get_projection_for_actor(actor_id)
	if projection == null:
		return false
	if action.is_empty():
		_visible_combat_apply_downed(actor_id, record)
		_visible_combat_reserve_position(actor_id, _projection_world_position(projection, _visible_combat_record_position(record)), reserved_cells)
		return true
	var actor_position := _projection_world_position(projection, _visible_combat_record_position(record))
	var target_position := actor_position + Vector3.FORWARD
	var look_actor_id := str(state.get("target_id", state.get("attacker_id", ""))).strip_edges()
	if action == "reaction":
		look_actor_id = str(state.get("attacker_id", look_actor_id)).strip_edges()
	if not look_actor_id.is_empty():
		var target_projection := get_projection_for_actor(look_actor_id)
		var target_record: Dictionary = records.get(look_actor_id, {}) if records.get(look_actor_id, {}) is Dictionary else {}
		if target_projection != null:
			target_position = _projection_world_position(target_projection, _visible_combat_record_position(target_record))
	var controlled := _visible_combat_update_locked_animation(actor_id, projection, state, actor_position, target_position, delta)
	if controlled:
		_visible_combat_reserve_position(actor_id, actor_position, reserved_cells)
	return controlled


func _visible_combat_apply_actor_action_metrics(started_usec: int, player_count: int, raider_count: int, actor_update_count: int) -> void:
	_visible_combat_metrics = {
		"visible_combat_runtime_enabled": visible_combat_runtime_enabled,
		"visible_combat_runtime_active": true,
		"visible_combat_player_count": player_count,
		"visible_combat_raider_count": raider_count,
		"visible_combat_controlled_actor_count": _visible_combat_controlled_actor_ids.size(),
		"visible_combat_attacked_player_count": 0,
		"visible_combat_actor_update_count": actor_update_count,
		"visible_combat_update_ms": float(Time.get_ticks_usec() - started_usec) / 1000.0,
		"visible_combat_complexity": "O(n)",
	}


func _visible_combat_update_locked_animation(actor_id: String, projection: Node, state: Dictionary, actor_position: Vector3, target_position: Vector3, delta: float) -> bool:
	var action := str(state.get("action", "")).strip_edges()
	if action.is_empty():
		return false
	var event_id := str(state.get("action_event_id", "%s:%s" % [actor_id, action])).strip_edges()
	var elapsed := maxf(float(state.get("action_elapsed", 0.0)) + maxf(delta, 0.0), 0.0)
	var duration := maxf(float(state.get("action_duration", 0.0)), 0.001)
	state["action_elapsed"] = elapsed
	var just_started := not bool(state.get("action_started", false))
	state["action_started"] = true
	match action:
		"attack":
			var target_id := str(state.get("target_id", "")).strip_edges()
			var impact_ratio := clampf(float(state.get("impact_ratio", VISIBLE_COMBAT_ATTACK_IMPACT_RATIO)), 0.0, 1.0)
			if not bool(state.get("impact_applied", false)) and elapsed >= duration * impact_ratio:
				_visible_combat_apply_hit(actor_id, target_id, _latest_population_records_by_actor_id)
				state["impact_applied"] = true
			var presentation_state := "attack_start" if just_started else "attack_hold"
			_apply_projection_visual(projection, actor_position, _combat_facing_yaw(actor_position, target_position), {"state": presentation_state, "event_id": event_id, "role": str(state.get("role", "")), "target_id": target_id}, 0.0)
		"reaction":
			var reaction_state := "reaction_start" if just_started else "reaction_hold"
			_apply_projection_visual(projection, actor_position, _combat_facing_yaw(actor_position, target_position), {"state": reaction_state, "event_id": event_id, "attacker_id": str(state.get("attacker_id", ""))}, 0.0)
		"downed":
			var downed_state := "downed_start" if just_started else "downed_hold"
			_apply_projection_visual(projection, actor_position, _projection_facing_yaw(projection, 0.0), {"state": downed_state, "event_id": event_id}, 0.0)
			_visible_combat_controlled_actor_ids[actor_id] = true
			_visible_combat_state_by_actor_id[actor_id] = state
			return true
		_:
			state.erase("action")
			return false
	if elapsed >= duration:
		state.erase("action")
		state.erase("action_event_id")
		state.erase("action_elapsed")
		state.erase("action_duration")
		state.erase("action_started")
		state.erase("impact_applied")
		if action == "attack":
			state["attack_cooldown"] = visible_combat_attack_cooldown + _visible_combat_cooldown_stagger(actor_id)
	_visible_combat_controlled_actor_ids[actor_id] = true
	_visible_combat_state_by_actor_id[actor_id] = state
	return true


func _visible_combat_attacker_for_lane(player_lane: int, attacker_by_lane: Dictionary, threatened_lanes: Dictionary, fallback_actor_id: String) -> String:
	for offset in [0, -1, 1, -2, 2]:
		var lane := player_lane + int(offset)
		if not threatened_lanes.has(lane):
			continue
		var attacker_id := str(attacker_by_lane.get(lane, "")).strip_edges()
		if not attacker_id.is_empty():
			return attacker_id
	return fallback_actor_id


func _visible_combat_reserve_position(actor_id: String, desired_position: Vector3, reserved_cells: Dictionary) -> Vector3:
	var cell_key := _visible_combat_reservation_cell_key(desired_position)
	var slot_index := int(reserved_cells.get(cell_key, 0))
	reserved_cells[cell_key] = slot_index + 1
	if slot_index <= 0:
		return desired_position
	var ring := int(slot_index / 6) + 1
	var angle_index := slot_index % 6
	var angle := TAU * float(angle_index) / 6.0 + float(_stable_id_hash(actor_id) % 17) * 0.017
	var radius := VISIBLE_COMBAT_BODY_RADIUS * 1.85 * float(ring)
	return desired_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


func _visible_combat_reservation_cell_key(position: Vector3) -> String:
	var cell_size := maxf(VISIBLE_COMBAT_RESERVATION_CELL_SIZE, VISIBLE_COMBAT_BODY_RADIUS * 2.0)
	return "%d:%d" % [floori(position.x / cell_size), floori(position.z / cell_size)]


func _visible_combat_begin_attack(actor_id: String, target_id: String, projection: Node, state: Dictionary) -> void:
	var serial := int(state.get("attack_serial", 0)) + 1
	var event_id := "%s:visible_attack:%d" % [actor_id, serial]
	state["attack_serial"] = serial
	state["action"] = "attack"
	state["action_event_id"] = event_id
	state["action_elapsed"] = 0.0
	state["action_duration"] = _combat_presentation_duration(projection, "attack_start", event_id, VISIBLE_COMBAT_ATTACK_ANIMATION_SECONDS)
	state["impact_ratio"] = _combat_impact_ratio(projection, "attack_start", event_id, VISIBLE_COMBAT_ATTACK_IMPACT_RATIO)
	state["action_started"] = false
	state["impact_applied"] = false
	state["target_id"] = target_id


func _visible_combat_apply_hit(attacker_id: String, target_id: String, records: Dictionary) -> void:
	var attacker_record: Dictionary = records.get(attacker_id, {}) if records.get(attacker_id, {}) is Dictionary else {}
	var target_record: Dictionary = records.get(target_id, {}) if records.get(target_id, {}) is Dictionary else {}
	var target_state := _visible_combat_state(target_id, target_record)
	if bool(target_state.get("downed", false)):
		return
	var damage := maxf(float(attacker_record.get("base_attack_damage", 10.0)) * 0.45, 4.0)
	var hp := maxf(float(target_state.get("hp", target_record.get("hp", 100.0))) - damage, 0.0)
	target_state["hp"] = hp
	target_state["under_attack"] = true
	target_state["under_attack_until"] = _visible_combat_elapsed + 3.0
	var target_projection := get_projection_for_actor(target_id)
	if hp <= 0.0:
		var downed_event_id := "%s:visible_downed:%d" % [target_id, int(target_state.get("downed_serial", 0)) + 1]
		target_state["downed"] = true
		target_state["action"] = "downed"
		target_state["action_event_id"] = downed_event_id
		target_state["downed_serial"] = int(target_state.get("downed_serial", 0)) + 1
		target_state["action_elapsed"] = 0.0
		target_state["action_duration"] = _combat_presentation_duration(target_projection, "downed_start", downed_event_id, VISIBLE_COMBAT_DOWNED_ANIMATION_SECONDS)
		target_state["action_started"] = false
		_visible_combat_commit_actor_patch(target_id, {"hp": 0.0, "life_state": VISIBLE_COMBAT_LIFE_STATE_DYING, "ledger_activity_state": "visible_combat_downed"})
	else:
		var reaction_event_id := "%s:visible_reaction:%d" % [target_id, int(target_state.get("reaction_serial", 0)) + 1]
		target_state["action"] = "reaction"
		target_state["action_event_id"] = reaction_event_id
		target_state["reaction_serial"] = int(target_state.get("reaction_serial", 0)) + 1
		target_state["action_elapsed"] = 0.0
		target_state["action_duration"] = _combat_presentation_duration(target_projection, "reaction_start", reaction_event_id, VISIBLE_COMBAT_REACTION_ANIMATION_SECONDS)
		target_state["action_started"] = false
		target_state["attacker_id"] = attacker_id
		_visible_combat_commit_actor_patch(target_id, {"hp": hp, "ledger_activity_state": "visible_combat_hit"})
	_visible_combat_state_by_actor_id[target_id] = target_state
	_visible_combat_controlled_actor_ids[target_id] = true


func _visible_combat_apply_idle(actor_id: String, record: Dictionary) -> void:
	if _visible_combat_runtime_controls_actor(actor_id):
		return
	var projection := get_projection_for_actor(actor_id)
	if projection == null:
		return
	var state := _visible_combat_state(actor_id, record)
	if bool(state.get("downed", false)):
		_visible_combat_apply_downed(actor_id, record)


func _visible_combat_apply_downed(actor_id: String, record: Dictionary) -> void:
	var projection := get_projection_for_actor(actor_id)
	if projection == null:
		return
	var position := _projection_world_position(projection, _visible_combat_record_position(record))
	var state := _visible_combat_state(actor_id, record)
	if str(state.get("action", "")) != "downed":
		var downed_event_id := "%s:visible_downed:%d" % [actor_id, int(state.get("downed_serial", 0)) + 1]
		state["action"] = "downed"
		state["action_event_id"] = downed_event_id
		state["downed_serial"] = int(state.get("downed_serial", 0)) + 1
		state["action_elapsed"] = 0.0
		state["action_duration"] = _combat_presentation_duration(projection, "downed_start", downed_event_id, VISIBLE_COMBAT_DOWNED_ANIMATION_SECONDS)
		state["action_started"] = false
		_visible_combat_state_by_actor_id[actor_id] = state
	_visible_combat_update_locked_animation(actor_id, projection, state, position, position + Vector3.FORWARD, 0.0)
	_visible_combat_controlled_actor_ids[actor_id] = true


func _visible_combat_state(actor_id: String, record: Dictionary) -> Dictionary:
	var state: Dictionary = _visible_combat_state_by_actor_id.get(actor_id, {}) if _visible_combat_state_by_actor_id.get(actor_id, {}) is Dictionary else {}
	if state.is_empty():
		state = {
			"hp": float(record.get("hp", record.get("max_hp", 100.0))),
			"attack_cooldown": _visible_combat_cooldown_stagger(actor_id),
			"under_attack": false,
			"under_attack_until": 0.0,
			"downed": int(record.get("life_state", VISIBLE_COMBAT_LIFE_STATE_ALIVE)) != VISIBLE_COMBAT_LIFE_STATE_ALIVE,
		}
		_visible_combat_state_by_actor_id[actor_id] = state
	return state


func _visible_combat_actor_lanes(actor_ids: Array[String]) -> Dictionary:
	var lanes := {}
	for actor_id in actor_ids:
		var record: Dictionary = _latest_population_records_by_actor_id.get(actor_id, {}) if _latest_population_records_by_actor_id.get(actor_id, {}) is Dictionary else {}
		var lane := _visible_combat_lane(_visible_combat_actor_position(actor_id, record))
		var lane_players: Array = lanes.get(lane, []) if lanes.get(lane, []) is Array else []
		lane_players.append(actor_id)
		lanes[lane] = lane_players
	return lanes


func _visible_combat_target_for_raider(raider_id: String, raider_index: int, players: Array[String], players_by_lane: Dictionary) -> String:
	if players.is_empty():
		return ""
	var raider_record: Dictionary = _latest_population_records_by_actor_id.get(raider_id, {}) if _latest_population_records_by_actor_id.get(raider_id, {}) is Dictionary else {}
	var lane := _visible_combat_lane(_visible_combat_actor_position(raider_id, raider_record))
	for offset in [0, -1, 1, -2, 2]:
		var candidate_lane := lane + int(offset)
		if not players_by_lane.has(candidate_lane):
			continue
		var lane_players: Array = players_by_lane.get(candidate_lane, [])
		if lane_players.is_empty():
			continue
		return str(lane_players[raider_index % lane_players.size()])
	return players[raider_index % players.size()]


func _visible_combat_target_offset(actor_position: Vector3, target_position: Vector3, target_index: int, defensive: bool) -> Vector3:
	var away := actor_position - target_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = Vector3.RIGHT if not defensive else Vector3.LEFT
	away = away.normalized()
	var side := Vector3(-away.z, 0.0, away.x).normalized()
	var ring := target_index / maxi(visible_combat_cluster_cap, 1)
	var lane_index := target_index % maxi(visible_combat_cluster_cap, 1)
	var side_offset := (float(lane_index) - float(maxi(visible_combat_cluster_cap, 1) - 1) * 0.5) * 0.42
	var range_offset := visible_combat_attack_range * (0.82 + float(ring) * 0.45)
	return away * range_offset + side * side_offset


func _visible_combat_record_is_player_party(record: Dictionary) -> bool:
	return bool(record.get("player_party_member", false)) or bool(record.get("player_controllable", false)) or str(record.get("party_id", "")).strip_edges() == VISIBLE_COMBAT_PLAYER_PARTY_ID


func _visible_combat_record_is_raider(record: Dictionary, player_factions: Dictionary) -> bool:
	var control_intent: Dictionary = record.get("control_intent", {}) if record.get("control_intent", {}) is Dictionary else {}
	var intent_source := str(control_intent.get("source", "")).strip_edges()
	if intent_source == "ai_raiding" or str(record.get("ledger_activity_state", "")).find("raiding") >= 0:
		return true
	var hostile_ids := _string_array(record.get("hostile_faction_ids", []))
	for faction_id in hostile_ids:
		if player_factions.has(faction_id):
			return true
	return false


func _visible_combat_record_is_alive(record: Dictionary) -> bool:
	if int(record.get("life_state", VISIBLE_COMBAT_LIFE_STATE_ALIVE)) != VISIBLE_COMBAT_LIFE_STATE_ALIVE:
		return false
	var max_hp := float(record.get("max_hp", 0.0))
	return max_hp <= 0.0 or float(record.get("hp", max_hp)) > 0.0


func _visible_combat_actor_downed(actor_id: String, record: Dictionary) -> bool:
	var state: Dictionary = _visible_combat_state_by_actor_id.get(actor_id, {}) if _visible_combat_state_by_actor_id.get(actor_id, {}) is Dictionary else {}
	return bool(state.get("downed", false)) or not _visible_combat_record_is_alive(record)


func _visible_combat_player_control_override(record: Dictionary) -> bool:
	if not bool(record.get("player_controllable", false)):
		return false
	if int(record.get("combat_stance", 1)) == VISIBLE_COMBAT_STANCE_PASSIVE:
		return true
	var move_order: Dictionary = record.get("move_order", {}) if record.get("move_order", {}) is Dictionary else {}
	if bool(move_order.get("active", false)) and str(move_order.get("source", "")).strip_edges() == "player":
		return true
	return false


func _visible_combat_actor_position(actor_id: String, record: Dictionary) -> Vector3:
	var projection := get_projection_for_actor(actor_id)
	return _projection_world_position(projection, _visible_combat_record_position(record)) if projection != null else _visible_combat_record_position(record)


func _visible_combat_record_position(record: Dictionary) -> Vector3:
	var value = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return value if value is Vector3 else Vector3.ZERO


func _visible_combat_lane(position: Vector3) -> int:
	return roundi(position.z / maxf(visible_combat_lane_width, 0.1))


func _visible_combat_cooldown_stagger(actor_id: String) -> float:
	return float(_stable_id_hash(actor_id) % 37) / 37.0 * 0.35


func _combat_presentation_duration(projection: Node, presentation_state: String, event_id: String, fallback: float) -> float:
	if projection != null and projection.has_method("get_combat_presentation_duration"):
		return maxf(float(projection.call("get_combat_presentation_duration", presentation_state, event_id, fallback)), 0.001)
	return fallback


func _combat_impact_ratio(projection: Node, presentation_state: String, event_id: String, fallback: float) -> float:
	if projection != null and projection.has_method("get_combat_impact_ratio"):
		return clampf(float(projection.call("get_combat_impact_ratio", presentation_state, event_id, fallback)), 0.0, 1.0)
	return fallback


func _stable_id_hash(text: String) -> int:
	var hash_value := 0
	for index in range(text.length()):
		hash_value = int((hash_value * 31 + text.unicode_at(index)) & 0x7fffffff)
	return hash_value


func _visible_combat_commit_actor_patch(actor_id: String, fields: Dictionary) -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("upsert_population_record_core"):
		return
	var patch := {"actor_id": actor_id}
	for key in fields.keys():
		patch[key] = fields[key]
	bridge.call("upsert_population_record_core", patch)


func _visible_combat_runtime_active() -> bool:
	return not _visible_combat_controlled_actor_ids.is_empty()


func _visible_combat_runtime_controls_actor(actor_id: String) -> bool:
	return _visible_combat_controlled_actor_ids.has(actor_id)


func _clear_visible_combat_runtime() -> void:
	_visible_combat_controlled_actor_ids.clear()
	_visible_combat_metrics = _visible_combat_inactive_metrics()


func _visible_combat_report_metrics() -> Dictionary:
	return _visible_combat_metrics.duplicate(true) if not _visible_combat_metrics.is_empty() else _visible_combat_inactive_metrics()


func _visible_combat_inactive_metrics() -> Dictionary:
	return {
		"visible_combat_runtime_enabled": visible_combat_runtime_enabled,
		"visible_combat_runtime_active": false,
		"visible_combat_player_count": 0,
		"visible_combat_raider_count": 0,
		"visible_combat_controlled_actor_count": 0,
		"visible_combat_attacked_player_count": 0,
		"visible_combat_actor_update_count": 0,
		"visible_combat_update_ms": 0.0,
		"visible_combat_complexity": "O(n)",
	}


func _apply_combat_schedule_projection(delta: float) -> void:
	var started_usec := Time.get_ticks_usec()
	_combat_scan_elapsed += delta
	if _combat_scan_elapsed >= combat_schedule_scan_interval_seconds or _combat_playback_key.is_empty():
		_combat_scan_elapsed = 0.0
		_combat_cached_encounter = _latest_visible_combat_schedule_encounter()
	if _combat_cached_encounter.is_empty():
		_clear_combat_schedule_projection()
		return
	var encounter_key := _combat_encounter_playback_key(_combat_cached_encounter)
	if encounter_key != _combat_playback_key:
		_begin_combat_schedule_projection(_combat_cached_encounter, encounter_key)
	if _combat_schedule_events.is_empty() or _combat_slots.is_empty():
		return
	_combat_playback_time += maxf(delta, 0.0) * maxf(combat_schedule_playback_speed, 0.0)
	if _combat_playback_duration > 0.0:
		if combat_schedule_loop_enabled:
			_combat_playback_time = fposmod(_combat_playback_time, _combat_playback_duration)
		else:
			_combat_playback_time = minf(_combat_playback_time, _combat_playback_duration)
	var active_events := _active_combat_events(_combat_playback_time)
	var active_animation_actor_ids := {}
	_reset_combat_projections_to_slots(active_animation_actor_ids)
	for event in active_events:
		_apply_combat_schedule_event_visual(event, _combat_playback_time, active_animation_actor_ids)
	if _combat_playback_time >= _combat_schedule_duration():
		_apply_combat_flee_aftermath_visuals(active_animation_actor_ids)
		_apply_combat_aftermath_visuals(active_animation_actor_ids)
	var update_usec := Time.get_ticks_usec() - started_usec
	var schedule: Dictionary = _combat_battle_result.get("combat_schedule", {}) if _combat_battle_result.get("combat_schedule", {}) is Dictionary else {}
	_combat_projection_metrics = {
		"combat_projection_enabled": true,
		"combat_projection_active": true,
		"combat_projection_encounter_id": str(_combat_cached_encounter.get("encounter_id", "")),
		"combat_projection_playback_time": _combat_playback_time,
		"combat_projection_duration": _combat_playback_duration,
		"combat_projection_update_ms": float(update_usec) / 1000.0,
		"combat_projection_visible_actor_count": _combat_slot_by_occupant_id.size(),
		"combat_projection_engagement_group_count": int(schedule.get("engagement_group_count", 0)),
		"combat_projection_active_event_count": active_events.size(),
		"combat_projection_scheduled_event_count": _combat_schedule_events.size(),
		"combat_projection_loop_enabled": combat_schedule_loop_enabled,
		"combat_projection_playback_complete": _combat_playback_duration > 0.0 and _combat_playback_time >= _combat_playback_duration,
		"combat_projection_skipped_beat_count": int(schedule.get("skipped_beat_count", 0)),
		"combat_projection_summarized_beat_count": int(schedule.get("summarized_beat_count", 0)),
		"combat_projection_slot_change_count": _combat_slot_by_occupant_id.size(),
		"combat_projection_active_animation_count": active_animation_actor_ids.size(),
		"combat_projection_downed_count": _combat_casualty_actor_ids.size(),
		"combat_projection_active_ragdoll_downed_count": _active_ragdoll_downed_count(),
		"combat_projection_presentation_only": true,
	}


func _begin_combat_schedule_projection(encounter: Dictionary, encounter_key: String) -> void:
	_combat_playback_key = encounter_key
	_combat_playback_time = 0.0
	_combat_battle_result = (encounter.get("battle_result", {}) as Dictionary).duplicate(true) if encounter.get("battle_result", {}) is Dictionary else {}
	_combat_fleeing_squad_id = str(_combat_battle_result.get("fleeing_squad_id", "")).strip_edges()
	_combat_slots = (_combat_battle_result.get("combat_slots", {}) as Dictionary).duplicate(true) if _combat_battle_result.get("combat_slots", {}) is Dictionary else {}
	var schedule: Dictionary = _combat_battle_result.get("combat_schedule", {}) if _combat_battle_result.get("combat_schedule", {}) is Dictionary else {}
	_combat_schedule_events = _dictionary_array(schedule.get("events", []))
	_build_combat_slot_lookup()
	_combat_casualty_actor_ids = _combat_casualty_ids(_combat_battle_result)
	_combat_casualty_actor_lookup = _id_lookup(_combat_casualty_actor_ids)
	_combat_playback_duration = _combat_schedule_duration() + COMBAT_AFTERMATH_HOLD_SECONDS
	_combat_actor_presentation_state_by_id.clear()


func _clear_combat_schedule_projection() -> void:
	if _combat_playback_key.is_empty():
		_combat_projection_metrics = _combat_projection_inactive_metrics()
		return
	_combat_cached_encounter.clear()
	_combat_playback_key = ""
	_combat_playback_time = 0.0
	_combat_playback_duration = 0.0
	_combat_battle_result.clear()
	_combat_fleeing_squad_id = ""
	_combat_slots.clear()
	_combat_slot_by_occupant_id.clear()
	_combat_schedule_events.clear()
	_combat_casualty_actor_ids.clear()
	_combat_casualty_actor_lookup.clear()
	_combat_actor_presentation_state_by_id.clear()
	_combat_projection_metrics = _combat_projection_inactive_metrics()


func _build_combat_slot_lookup() -> void:
	_combat_slot_by_occupant_id.clear()
	for slot_id in _combat_slots.keys():
		var slot = _combat_slots.get(slot_id)
		if not (slot is Dictionary):
			continue
		var occupant_id := str((slot as Dictionary).get("occupant_id", "")).strip_edges()
		if not occupant_id.is_empty():
			_combat_slot_by_occupant_id[occupant_id] = (slot as Dictionary).duplicate(true)


func _reset_combat_projections_to_slots(active_animation_actor_ids: Dictionary) -> void:
	if _combat_uses_live_positions():
		_reset_live_combat_projections_to_current_positions(active_animation_actor_ids)
		return
	var in_aftermath := _combat_playback_time >= _combat_schedule_duration()
	for occupant_id_value in _projection_by_actor_id.keys():
		var occupant_id := str(occupant_id_value)
		if not _combat_slot_by_occupant_id.has(occupant_id):
			continue
		if in_aftermath and _combat_casualty_actor_lookup.has(occupant_id):
			continue
		var slot: Dictionary = _combat_slot_by_occupant_id.get(occupant_id, {})
		if in_aftermath and not _combat_fleeing_squad_id.is_empty() and str(slot.get("squad_id", "")).strip_edges() == _combat_fleeing_squad_id:
			continue
		var projection := get_projection_for_actor(occupant_id)
		if projection == null:
			continue
		var state_key := str(_combat_actor_presentation_state_by_id.get(occupant_id, ""))
		if state_key != "idle":
			_apply_projection_visual(projection, _combat_slot_position(slot), float(slot.get("facing_yaw", 0.0)), {"state": "combat_idle", "event_id": "%s:idle" % occupant_id}, 0.0)
			_combat_actor_presentation_state_by_id[occupant_id] = "idle"
		else:
			_apply_projection_transform_only(projection, _combat_slot_position(slot), float(slot.get("facing_yaw", 0.0)), 0.0)


func _reset_live_combat_projections_to_current_positions(_active_animation_actor_ids: Dictionary) -> void:
	var in_aftermath := _combat_playback_time >= _combat_schedule_duration()
	for occupant_id_value in _projection_by_actor_id.keys():
		var occupant_id := str(occupant_id_value)
		if not _combat_slot_by_occupant_id.has(occupant_id):
			continue
		if in_aftermath and _combat_casualty_actor_lookup.has(occupant_id):
			continue
		var projection := get_projection_for_actor(occupant_id)
		if projection == null:
			continue
		var slot: Dictionary = _combat_slot_by_occupant_id.get(occupant_id, {}) if _combat_slot_by_occupant_id.get(occupant_id, {}) is Dictionary else {}
		var position := _projection_world_position(projection, _combat_slot_position(slot))
		var facing_yaw := _projection_facing_yaw(projection, float(slot.get("facing_yaw", 0.0)))
		if str(_combat_actor_presentation_state_by_id.get(occupant_id, "")) != "idle":
			_apply_projection_visual(projection, position, facing_yaw, {"state": "combat_idle", "event_id": "%s:live_idle" % occupant_id}, 0.0)
			_combat_actor_presentation_state_by_id[occupant_id] = "idle"


func _apply_combat_schedule_event_visual(event: Dictionary, playback_time: float, active_animation_actor_ids: Dictionary) -> void:
	var event_type := str(event.get("event_type", ""))
	var progress := _combat_event_progress(event, playback_time)
	var attacker_slot := _combat_slot_for_id(str(event.get("attacker_slot_id", "")))
	var defender_slot := _combat_slot_for_id(str(event.get("defender_slot_id", "")))
	var attacker_id := str(attacker_slot.get("occupant_id", ""))
	var defender_id := str(defender_slot.get("occupant_id", ""))
	var attacker_projection := get_projection_for_actor(attacker_id)
	var defender_projection := get_projection_for_actor(defender_id)
	match event_type:
		"move_to_slot":
			_apply_combat_move_visual(attacker_projection, attacker_id, attacker_slot, defender_slot, event, progress, active_animation_actor_ids)
			_apply_combat_move_visual(defender_projection, defender_id, defender_slot, attacker_slot, event, progress, active_animation_actor_ids)
		"face_target":
			_face_combat_projection(attacker_projection, attacker_slot, defender_slot)
			_face_combat_projection(defender_projection, defender_slot, attacker_slot)
		"attack":
			_apply_combat_attack_visual(attacker_projection, attacker_id, attacker_slot, defender_slot, event, progress, active_animation_actor_ids)
		"reaction":
			_apply_combat_reaction_visual(defender_projection, defender_id, defender_slot, attacker_slot, event, progress, active_animation_actor_ids)
		"flee":
			_apply_combat_flee_visual(event, progress, active_animation_actor_ids)


func _apply_combat_move_visual(projection: Node, actor_id: String, slot: Dictionary, opposing_slot: Dictionary, event: Dictionary, progress: float, active_animation_actor_ids: Dictionary) -> void:
	if projection == null:
		return
	if _combat_uses_live_positions():
		_apply_live_combat_approach_visual(projection, actor_id, _combat_slot_position(opposing_slot), event, progress, active_animation_actor_ids)
		return
	var slot_position := _combat_slot_position(slot)
	var opposing_position := _combat_slot_position(opposing_slot)
	var away := slot_position - opposing_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = Vector3.FORWARD
	var position := slot_position + away.normalized() * (COMBAT_MOVE_IN_DISTANCE * (1.0 - progress))
	_apply_projection_visual(projection, position, _combat_facing_yaw(position, opposing_position), {"state": "move", "event_id": str(event.get("event_id", "")), "progress": progress}, 0.0)
	_combat_actor_presentation_state_by_id[actor_id] = str(event.get("event_id", ""))
	active_animation_actor_ids[actor_id] = true


func _apply_combat_attack_visual(projection: Node, actor_id: String, attacker_slot: Dictionary, defender_slot: Dictionary, event: Dictionary, progress: float, active_animation_actor_ids: Dictionary) -> void:
	if projection == null:
		return
	var defender_projection := get_projection_for_actor(str(defender_slot.get("occupant_id", "")))
	var attacker_position := _projection_world_position(projection, _combat_slot_position(attacker_slot)) if _combat_uses_live_positions() else _combat_slot_position(attacker_slot)
	var defender_position := _projection_world_position(defender_projection, _combat_slot_position(defender_slot)) if _combat_uses_live_positions() else _combat_slot_position(defender_slot)
	var direction := defender_position - attacker_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	if _combat_uses_live_positions() and _xz_distance_squared(attacker_position, defender_position) > COMBAT_VISIBLE_ATTACK_RANGE * COMBAT_VISIBLE_ATTACK_RANGE:
		_apply_live_combat_approach_visual(projection, actor_id, defender_position, event, progress, active_animation_actor_ids)
		return
	var position := attacker_position + direction.normalized() * sin(progress * PI) * COMBAT_ATTACK_STEP_DISTANCE
	_apply_projection_visual(projection, position, _combat_facing_yaw(attacker_position, defender_position), {"state": "attack", "event_id": str(event.get("event_id", "")), "progress": progress, "result": str(event.get("result", ""))}, 0.0)
	_combat_actor_presentation_state_by_id[actor_id] = str(event.get("event_id", ""))
	active_animation_actor_ids[actor_id] = true


func _apply_combat_reaction_visual(projection: Node, actor_id: String, defender_slot: Dictionary, attacker_slot: Dictionary, event: Dictionary, progress: float, active_animation_actor_ids: Dictionary) -> void:
	if projection == null:
		return
	var attacker_projection := get_projection_for_actor(str(attacker_slot.get("occupant_id", "")))
	var defender_position := _projection_world_position(projection, _combat_slot_position(defender_slot)) if _combat_uses_live_positions() else _combat_slot_position(defender_slot)
	var attacker_position := _projection_world_position(attacker_projection, _combat_slot_position(attacker_slot)) if _combat_uses_live_positions() else _combat_slot_position(attacker_slot)
	var away := defender_position - attacker_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = Vector3.FORWARD
	var result := str(event.get("result", "hit"))
	var state := "block" if result == "block" else "reaction"
	var rotation_x := 0.0
	if result == "downed" and progress >= 0.45:
		state = "downed"
		rotation_x = 0.0
	var reaction_distance := 0.0 if _combat_uses_live_positions() and _xz_distance_squared(defender_position, attacker_position) > COMBAT_VISIBLE_ATTACK_RANGE * COMBAT_VISIBLE_ATTACK_RANGE else COMBAT_REACTION_STEP_DISTANCE
	var position := defender_position + away.normalized() * sin(progress * PI) * reaction_distance
	_apply_projection_visual(projection, position, _combat_facing_yaw(defender_position, attacker_position), {"state": state, "event_id": str(event.get("event_id", "")), "progress": progress, "result": result}, rotation_x)
	_combat_actor_presentation_state_by_id[actor_id] = str(event.get("event_id", ""))
	active_animation_actor_ids[actor_id] = true


func _apply_combat_flee_visual(event: Dictionary, progress: float, active_animation_actor_ids: Dictionary) -> void:
	var fleeing_squad_id := str(event.get("fleeing_squad_id", _combat_fleeing_squad_id)).strip_edges()
	if fleeing_squad_id.is_empty():
		return
	for actor_id_value in _projection_by_actor_id.keys():
		var actor_id := str(actor_id_value)
		var slot: Dictionary = _combat_slot_by_occupant_id.get(actor_id, {})
		if str(slot.get("squad_id", "")).strip_edges() != fleeing_squad_id:
			continue
		var projection := get_projection_for_actor(actor_id)
		if projection == null:
			continue
		var base_position := _projection_world_position(projection, _combat_slot_position(slot)) if _combat_uses_live_positions() else _combat_slot_position(slot)
		var direction := _combat_flee_direction(slot)
		var position := base_position + direction * lerpf(0.2, 5.0, progress)
		_apply_projection_visual(projection, position, atan2(direction.x, direction.z), {"state": "move", "event_id": str(event.get("event_id", "")), "progress": progress, "result": "fled"}, 0.0)
		_combat_actor_presentation_state_by_id[actor_id] = str(event.get("event_id", ""))
		active_animation_actor_ids[actor_id] = true


func _apply_combat_flee_aftermath_visuals(active_animation_actor_ids: Dictionary) -> void:
	if _combat_fleeing_squad_id.is_empty():
		return
	for actor_id_value in _projection_by_actor_id.keys():
		var actor_id := str(actor_id_value)
		var slot: Dictionary = _combat_slot_by_occupant_id.get(actor_id, {})
		if str(slot.get("squad_id", "")).strip_edges() != _combat_fleeing_squad_id:
			continue
		var projection := get_projection_for_actor(actor_id)
		if projection == null:
			continue
		var direction := _combat_flee_direction(slot)
		var base_position := _projection_world_position(projection, _combat_slot_position(slot)) if _combat_uses_live_positions() else _combat_slot_position(slot)
		var position := base_position + direction * 5.0
		_apply_projection_visual(projection, position, atan2(direction.x, direction.z), {"state": "move", "event_id": "%s:fled" % actor_id, "progress": 1.0, "result": "fled"}, 0.0)
		_combat_actor_presentation_state_by_id[actor_id] = "fled"
		active_animation_actor_ids[actor_id] = true


func _apply_combat_aftermath_visuals(active_animation_actor_ids: Dictionary) -> void:
	for actor_id_value in _projection_by_actor_id.keys():
		var actor_id := str(actor_id_value)
		if not _combat_casualty_actor_lookup.has(actor_id):
			continue
		var projection := get_projection_for_actor(actor_id)
		if projection == null:
			continue
		var slot: Dictionary = _combat_slot_by_occupant_id.get(actor_id, {})
		var position := _projection_world_position(projection, _combat_slot_position(slot)) if _combat_uses_live_positions() else _combat_slot_position(slot)
		if str(_combat_actor_presentation_state_by_id.get(actor_id, "")) != "downed":
			_apply_projection_visual(projection, position, float(slot.get("facing_yaw", 0.0)), {"state": "downed", "event_id": "%s:aftermath" % actor_id, "progress": 1.0}, 0.0)
			_combat_actor_presentation_state_by_id[actor_id] = "downed"
		else:
			_apply_projection_transform_only(projection, position, float(slot.get("facing_yaw", 0.0)), 0.0)
		active_animation_actor_ids[actor_id] = true


func _apply_projection_visual(projection: Node, position: Vector3, facing_yaw: float, presentation: Dictionary, rotation_x: float) -> void:
	var visual_state := {
		"global_position": position,
		"facing_yaw": facing_yaw,
		"rotation_x": rotation_x,
		"presentation": presentation,
	}
	if projection.has_method("apply_combat_projection_visual"):
		projection.call("apply_combat_projection_visual", visual_state)
	elif projection is Node3D:
		(projection as Node3D).global_position = position
		(projection as Node3D).rotation.y = facing_yaw
		(projection as Node3D).rotation.x = rotation_x


func _apply_projection_transform_only(projection: Node, position: Vector3, facing_yaw: float, rotation_x: float) -> void:
	if not (projection is Node3D):
		return
	(projection as Node3D).global_position = position
	(projection as Node3D).rotation.y = facing_yaw
	(projection as Node3D).rotation.x = rotation_x
	(projection as Node3D).scale = Vector3.ONE


func _face_combat_projection(projection: Node, slot: Dictionary, opposing_slot: Dictionary) -> void:
	if projection == null or not (projection is Node3D):
		return
	var from_position := _projection_world_position(projection, _combat_slot_position(slot)) if _combat_uses_live_positions() else _combat_slot_position(slot)
	var opposing_projection := get_projection_for_actor(str(opposing_slot.get("occupant_id", "")))
	var target_position := _projection_world_position(opposing_projection, _combat_slot_position(opposing_slot)) if _combat_uses_live_positions() else _combat_slot_position(opposing_slot)
	(projection as Node3D).rotation.y = _combat_facing_yaw(from_position, target_position)


func _apply_live_combat_approach_visual(projection: Node, actor_id: String, target_position: Vector3, event: Dictionary, progress: float, active_animation_actor_ids: Dictionary) -> void:
	if projection == null:
		return
	var current_position := _projection_world_position(projection, target_position)
	var away := current_position - target_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		away = Vector3.FORWARD
	var desired_position := target_position + away.normalized() * (COMBAT_VISIBLE_ATTACK_RANGE * COMBAT_VISIBLE_APPROACH_STOP_RATIO)
	desired_position.y = current_position.y
	var next_position := current_position.move_toward(desired_position, COMBAT_VISIBLE_APPROACH_STEP_DISTANCE)
	_apply_projection_visual(projection, next_position, _combat_facing_yaw(next_position, target_position), {"state": "move", "event_id": str(event.get("event_id", "")), "progress": progress, "reason": "closing_to_attack_range"}, 0.0)
	_combat_actor_presentation_state_by_id[actor_id] = str(event.get("event_id", ""))
	active_animation_actor_ids[actor_id] = true


func _combat_uses_live_positions() -> bool:
	return false


func _projection_world_position(projection: Node, fallback: Vector3) -> Vector3:
	return (projection as Node3D).global_position if projection != null and projection is Node3D else fallback


func _projection_facing_yaw(projection: Node, fallback: float) -> float:
	return (projection as Node3D).rotation.y if projection != null and projection is Node3D else fallback


func _xz_distance_squared(first: Vector3, second: Vector3) -> float:
	var x_delta := first.x - second.x
	var z_delta := first.z - second.z
	return x_delta * x_delta + z_delta * z_delta


func _active_combat_events(playback_time: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in _combat_schedule_events:
		var start_time := float(event.get("start_time", 0.0))
		var duration := maxf(float(event.get("duration", 0.0)), 0.001)
		if playback_time >= start_time and playback_time <= start_time + duration:
			result.append(event)
	return result


func _combat_event_progress(event: Dictionary, playback_time: float) -> float:
	var start_time := float(event.get("start_time", 0.0))
	var duration := maxf(float(event.get("duration", 0.0)), 0.001)
	return clampf((playback_time - start_time) / duration, 0.0, 1.0)


func _combat_schedule_duration() -> float:
	var duration := 0.0
	for event in _combat_schedule_events:
		duration = maxf(duration, float(event.get("start_time", 0.0)) + float(event.get("duration", 0.0)))
	return duration


func _combat_slot_for_id(slot_id: String) -> Dictionary:
	var slot = _combat_slots.get(slot_id, {})
	return (slot as Dictionary).duplicate(true) if slot is Dictionary else {}


func _combat_slot_position(slot: Dictionary) -> Vector3:
	var value = slot.get("world_position_hint", Vector3.ZERO)
	return value if value is Vector3 else Vector3.ZERO


func _combat_casualty_ids(battle_result: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var casualties = battle_result.get("member_casualties", {})
	if not (casualties is Dictionary):
		return result
	for squad_id in (casualties as Dictionary).keys():
		var entries = (casualties as Dictionary).get(squad_id, [])
		if not (entries is Array):
			continue
		for entry in entries:
			if entry is Dictionary:
				var actor_id := str((entry as Dictionary).get("actor_id", (entry as Dictionary).get("member_id", ""))).strip_edges()
				if not actor_id.is_empty() and not result.has(actor_id):
					result.append(actor_id)
	return result


func _id_lookup(ids: Array[String]) -> Dictionary:
	var result := {}
	for id in ids:
		result[id] = true
	return result


func _latest_visible_combat_schedule_encounter() -> Dictionary:
	var combat := _get_combat_controller()
	if combat == null or not combat.has_method("get_world_encounter_state"):
		return {}
	var state = combat.call("get_world_encounter_state")
	if not (state is Dictionary):
		return {}
	var encounters = (state as Dictionary).get("encounters_by_id", {})
	if not (encounters is Dictionary):
		return {}
	var latest: Dictionary = {}
	var latest_tick := -1
	for encounter_id in (encounters as Dictionary).keys():
		var encounter = (encounters as Dictionary).get(encounter_id)
		if not (encounter is Dictionary):
			continue
		var record: Dictionary = encounter
		if str(record.get("status", "")) != "resolved" or not _combat_encounter_is_projection_visible(record):
			continue
		var battle_result: Dictionary = record.get("battle_result", {}) if record.get("battle_result", {}) is Dictionary else {}
		var schedule: Dictionary = battle_result.get("combat_schedule", {}) if battle_result.get("combat_schedule", {}) is Dictionary else {}
		var events = schedule.get("events", [])
		if not (events is Array) or (events as Array).is_empty():
			continue
		var resolved_tick := int(record.get("resolved_tick", record.get("created_tick", 0)))
		if resolved_tick > latest_tick:
			latest_tick = resolved_tick
			latest = record.duplicate(true)
	return latest


func _combat_encounter_is_projection_visible(record: Dictionary) -> bool:
	var visibility_flags: Dictionary = record.get("visibility_flags", {}) if record.get("visibility_flags", {}) is Dictionary else {}
	var projection_flags: Dictionary = record.get("projection_flags", {}) if record.get("projection_flags", {}) is Dictionary else {}
	if bool(visibility_flags.get("force_visible", false)) or bool(projection_flags.get("important", false)):
		return true
	var importance := str(record.get("projection_importance", "")).strip_edges()
	if importance == "important" or importance == "high" or importance == "critical":
		return true
	var start_request: Dictionary = record.get("start_request", {}) if record.get("start_request", {}) is Dictionary else {}
	var request_flags: Dictionary = start_request.get("projection_flags", {}) if start_request.get("projection_flags", {}) is Dictionary else {}
	var request_visibility: Dictionary = start_request.get("visibility_flags", {}) if start_request.get("visibility_flags", {}) is Dictionary else {}
	return bool(request_flags.get("important", false)) or bool(request_visibility.get("force_visible", false))


func _combat_encounter_playback_key(record: Dictionary) -> String:
	return "%s:%s" % [str(record.get("encounter_id", "")), str(record.get("resolved_tick", record.get("created_tick", 0)))]


func _get_combat_controller() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldMapCombatSimController")
		if local != null:
			return local
	var existing := get_tree().get_first_node_in_group("world_map_combat_sim_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	return null


func _combat_facing_yaw(from_position: Vector3, target_position: Vector3) -> float:
	var delta := target_position - from_position
	if absf(delta.x) < 0.001 and absf(delta.z) < 0.001:
		return 0.0
	return atan2(delta.x, delta.z)


func _combat_flee_direction(slot: Dictionary) -> Vector3:
	var side := str(slot.get("side", "")).strip_edges()
	if side == "a":
		return Vector3.LEFT
	if side == "b":
		return Vector3.RIGHT
	var slot_position := _combat_slot_position(slot)
	var group_center = slot.get("group_center", Vector3.ZERO)
	var group_center_position := Vector3.ZERO
	if group_center is Vector3:
		group_center_position = group_center
	var direction := slot_position - group_center_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return Vector3.FORWARD
	return direction.normalized()


func _active_ragdoll_downed_count() -> int:
	var count := 0
	for actor_id in _combat_casualty_actor_ids:
		var projection := get_projection_for_actor(actor_id)
		if projection == null or not projection.has_method("get_projection_debug_state"):
			continue
		var debug_value = projection.call("get_projection_debug_state")
		var debug_state: Dictionary = debug_value if debug_value is Dictionary else {}
		var body_state: Dictionary = debug_state.get("body_state", {}) if debug_state.get("body_state", {}) is Dictionary else {}
		if bool(body_state.get("ragdoll_active", false)):
			count += 1
	return count


func _combat_projection_report_metrics() -> Dictionary:
	if _combat_projection_metrics.is_empty():
		return _combat_projection_inactive_metrics()
	return _combat_projection_metrics.duplicate(true)


func _combat_projection_inactive_metrics() -> Dictionary:
	return {
		"combat_projection_enabled": combat_schedule_projection_enabled,
		"combat_projection_active": false,
		"combat_projection_encounter_id": "",
		"combat_projection_playback_time": 0.0,
		"combat_projection_duration": 0.0,
		"combat_projection_update_ms": 0.0,
		"combat_projection_visible_actor_count": 0,
		"combat_projection_engagement_group_count": 0,
		"combat_projection_active_event_count": 0,
		"combat_projection_scheduled_event_count": 0,
		"combat_projection_loop_enabled": combat_schedule_loop_enabled,
		"combat_projection_playback_complete": false,
		"combat_projection_skipped_beat_count": 0,
		"combat_projection_summarized_beat_count": 0,
		"combat_projection_slot_change_count": 0,
		"combat_projection_active_animation_count": 0,
		"combat_projection_downed_count": 0,
		"combat_projection_active_ragdoll_downed_count": 0,
		"combat_projection_presentation_only": true,
	}


func _dictionary_array(value) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for entry in value:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _try_initialize() -> bool:
	if _initialized:
		return true
	if root_scene == null:
		root_scene = get_parent()
	if root_scene == null or not is_inside_tree():
		return false
	_projection_root = root_scene.get_node_or_null(projection_root_name) as Node3D
	if _projection_root == null:
		_projection_root = Node3D.new()
		_projection_root.name = projection_root_name
		root_scene.add_child(_projection_root)
	_initialized = true
	return true


func _get_or_create_projection(actor_id: String, projection_kind: String) -> Node:
	var existing := get_projection_for_actor(actor_id)
	if existing != null and str(existing.get("projection_kind")) == projection_kind:
		return existing
	_remove_projection(actor_id)
	var body_script := _body_script_for_kind(projection_kind)
	if body_script == null:
		return null
	var projection := WORLD_ACTOR_PROJECTION_SCRIPT.new() as Node
	_projection_root.add_child(projection)
	projection.setup(actor_id, projection_kind, body_script)
	_projection_by_actor_id[actor_id] = projection
	return projection


func _remove_stale_projections(expected_actor_ids: Dictionary) -> void:
	var existing_ids := _projection_by_actor_id.keys()
	for actor_id_value in existing_ids:
		var actor_id := str(actor_id_value)
		if not expected_actor_ids.has(actor_id):
			_remove_projection(actor_id)


func _remove_projection(actor_id: String) -> void:
	var projection = _projection_by_actor_id.get(actor_id)
	if projection != null and is_instance_valid(projection):
		(projection as Node).queue_free()
	_projection_by_actor_id.erase(actor_id)


func _equipment_slots_by_actor(bridge: Node) -> Dictionary:
	_bind_equipment_cache_signal(bridge)
	if _equipment_slots_cache_dirty:
		_equipment_slots_cache_by_actor_id = _load_equipment_slots_by_actor(bridge)
		_equipment_slots_cache_dirty = false
	return _equipment_slots_cache_by_actor_id


func _load_equipment_slots_by_actor(bridge: Node) -> Dictionary:
	var result := {}
	if bridge == null or not bridge.has_method("get_equipment_slots"):
		return result
	for slot in bridge.call("get_equipment_slots"):
		if not (slot is Dictionary):
			continue
		var actor_id := str((slot as Dictionary).get("actor_id", "")).strip_edges()
		var slot_name := str((slot as Dictionary).get("slot_name", "")).strip_edges()
		var item_path := str((slot as Dictionary).get("item_definition_path", "")).strip_edges()
		if actor_id.is_empty() or slot_name.is_empty() or item_path.is_empty():
			continue
		var actor_slots: Dictionary = result.get(actor_id, {})
		actor_slots[slot_name] = item_path
		result[actor_id] = actor_slots
	return result


func _bind_equipment_cache_signal(bridge: Node) -> void:
	if bridge == _equipment_signal_bridge:
		return
	_disconnect_equipment_cache_signal()
	if bridge == null or not bridge.has_signal("inventory_state_changed"):
		return
	var callable := Callable(self, "_on_equipment_cache_changed")
	if bridge.is_connected("inventory_state_changed", callable):
		_equipment_signal_bridge = bridge
		return
	bridge.connect("inventory_state_changed", callable)
	_equipment_signal_bridge = bridge


func _disconnect_equipment_cache_signal() -> void:
	if _equipment_signal_bridge == null or not is_instance_valid(_equipment_signal_bridge):
		_equipment_signal_bridge = null
		return
	var callable := Callable(self, "_on_equipment_cache_changed")
	if _equipment_signal_bridge.has_signal("inventory_state_changed") and _equipment_signal_bridge.is_connected("inventory_state_changed", callable):
		_equipment_signal_bridge.disconnect("inventory_state_changed", callable)
	_equipment_signal_bridge = null


func _on_equipment_cache_changed(_result: Dictionary = {}) -> void:
	_equipment_slots_cache_dirty = true


func _projection_kind_for_record(record: Dictionary) -> String:
	var explicit_kind := str(record.get("projection_kind", "")).strip_edges()
	if not explicit_kind.is_empty():
		return explicit_kind
	var appearance = record.get("appearance", {})
	if appearance is Dictionary and (not str((appearance as Dictionary).get("body_archetype", "")).is_empty() or int((appearance as Dictionary).get("visual_body_type", 0)) > 0):
		return "humanoid"
	return ""


func _body_script_for_kind(projection_kind: String) -> Script:
	match projection_kind:
		"humanoid":
			return HUMANOID_BODY_PROJECTION_SCRIPT
		"animal_placeholder", "robot_placeholder":
			return PLACEHOLDER_BODY_PROJECTION_SCRIPT
	return null


func _projection_metrics_base(source_record_count: int) -> Dictionary:
	return {
		"source_record_count": source_record_count,
		"eligible_projection_count": 0,
		"projected_actor_count": _projection_by_actor_id.size(),
		"realized_actor_count": _projection_by_actor_id.size(),
		"visible_actor_count": _visible_projection_count(),
		"max_projected_actor_count": maxi(0, max_projected_actor_count),
		"projection_cap_active": max_projected_actor_count > 0,
		"skipped_projection_count": 0,
		"unsupported_projection_count": 0,
		"projection_counts_by_kind": get_projection_counts_by_kind(),
	}


func _projection_cap_reached(current_expected_count: int) -> bool:
	return max_projected_actor_count > 0 and current_expected_count >= max_projected_actor_count


func _projection_record_keys(records: Dictionary) -> Array:
	if max_projected_actor_count <= 0:
		return records.keys()
	return _sorted_record_keys(records)


func _sorted_record_keys(records: Dictionary) -> Array:
	var keys := records.keys()
	keys.sort_custom(func(first, second) -> bool:
		return _record_sort_actor_id(records, first) < _record_sort_actor_id(records, second)
	)
	return keys


func _record_sort_actor_id(records: Dictionary, key) -> String:
	var record_value = records.get(key)
	if record_value is Dictionary:
		var sort_key := str((record_value as Dictionary).get("projection_sort_key", "")).strip_edges()
		if not sort_key.is_empty():
			return sort_key
		return str((record_value as Dictionary).get("actor_id", key)).strip_edges()
	return str(key).strip_edges()


func _visible_projection_count() -> int:
	var count := 0
	for projection in _projection_by_actor_id.values():
		if projection != null and is_instance_valid(projection) and bool((projection as Node).get("visible")):
			count += 1
	return count


func _note_unsupported_kind(projection_kind: String) -> void:
	var key := projection_kind if not projection_kind.is_empty() else "<empty>"
	_unsupported_projection_kinds[key] = int(_unsupported_projection_kinds.get(key, 0)) + 1


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


func _get_population_records_core(bridge: Node) -> Dictionary:
	if bridge.has_method("get_population_records_core"):
		var core_records = bridge.call("get_population_records_core")
		return core_records if core_records is Dictionary else {}
	if bridge.has_method("get_population_records"):
		var records = bridge.call("get_population_records")
		return records if records is Dictionary else {}
	return {}


func _log_perf_duration(label: String, started_at_usec: int, metadata: Dictionary = {}) -> void:
	if not performance_logging_enabled or started_at_usec <= 0:
		return
	var elapsed_usec := int(Time.get_ticks_usec() - started_at_usec)
	if float(elapsed_usec) < performance_log_threshold_usec:
		return
	var now_msec := Time.get_ticks_msec()
	var next_msec := int(_perf_log_next_msec_by_label.get(label, 0))
	if now_msec < next_msec:
		return
	_perf_log_next_msec_by_label[label] = now_msec + int(performance_log_interval_seconds * 1000.0)
	var suffix := ""
	for key in metadata.keys():
		suffix += " %s=%s" % [str(key), str(metadata[key])]
	print("PERF %s %.3fms%s" % [label, float(elapsed_usec) / 1000.0, suffix])
