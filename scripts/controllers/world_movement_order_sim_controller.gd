extends Node

class_name WorldMovementOrderSimController

const MOVEMENT_MODE_WALK := 0
const MOVEMENT_MODE_RUN := 1
const MOVEMENT_MODE_SNEAK := 2
const SNEAK_MOVE_SPEED_MIN_MULTIPLIER := 0.45
const SNEAK_MOVE_SPEED_MAX_MULTIPLIER := 1.45
const SNEAK_MOVE_SPEED_MASTER_LEVEL := 80.0
const SNEAK_MOVE_SPEED_CURVE := 0.75
const SKILL_MOVEMENT_RUNNING := "movement.running"
const SKILL_SUBTERFUGE_SNEAKING := "subterfuge.sneaking"

@export_range(0.1, 20.0, 0.1) var base_walk_speed := 4.4
@export_range(0.01, 3.0, 0.01) var arrival_threshold := 0.12
@export_range(0.01, 20.0, 0.01) var vertical_snap_speed := 6.0
@export var performance_logging_enabled := false
@export_range(0.1, 10.0, 0.1) var performance_log_interval_seconds := 1.0
@export_range(0.0, 50000.0, 100.0) var performance_log_threshold_usec := 1000.0

var root_scene: Node
var _last_state: Dictionary = {}
var _perf_log_next_msec_by_label: Dictionary = {}


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root


func _ready() -> void:
	add_to_group("world_movement_order_sim_controller")


func update_sim(fixed_delta: float) -> void:
	var started_at_usec := Time.get_ticks_usec() if performance_logging_enabled else 0
	if fixed_delta <= 0.0:
		return
	var bridge := _get_gecs_world()
	if bridge == null:
		return
	var records := _get_population_records_core(bridge)
	if records.is_empty():
		_last_state = {"active_count": 0, "moved_count": 0, "arrived_count": 0}
		_log_perf_duration("movement.update_sim", started_at_usec, {"records": 0, "active": 0, "moved": 0})
		return
	var active_count := 0
	var moved_count := 0
	var arrived_count := 0
	for actor_id_value in records.keys():
		var record_value = records[actor_id_value]
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var result := _advance_record(record, fixed_delta)
		if result.is_empty():
			continue
		if bool(result.get("was_active", false)):
			active_count += 1
		if bool(result.get("moved", false)):
			moved_count += 1
		if bool(result.get("arrived", false)):
			arrived_count += 1
		_upsert_population_record_core(bridge, result.get("record", {}))
	_last_state = {
		"active_count": active_count,
		"moved_count": moved_count,
		"arrived_count": arrived_count,
	}
	_log_perf_duration("movement.update_sim", started_at_usec, {"records": records.size(), "active": active_count, "moved": moved_count})


func get_sim_state() -> Dictionary:
	return _last_state.duplicate(true)


func _advance_record(source_record: Dictionary, fixed_delta: float) -> Dictionary:
	var move_order: Dictionary = source_record.get("move_order", {}) if source_record.get("move_order", {}) is Dictionary else {}
	var order_active := bool(move_order.get("active", false))
	var locomotion_state: Dictionary = source_record.get("locomotion_state", {}) if source_record.get("locomotion_state", {}) is Dictionary else {}
	var actor_id := str(source_record.get("actor_id", source_record.get("stable_id", ""))).strip_edges()
	if actor_id.is_empty():
		return {}
	if not order_active:
		if bool(locomotion_state.get("moving", false)):
			return {"record": _movement_patch(actor_id, {"locomotion_state": _idle_locomotion_state(source_record, "idle")}), "was_active": false, "moved": false, "arrived": false}
		return {}
	if int(source_record.get("life_state", 0)) != 0:
		move_order = move_order.duplicate(true)
		move_order["active"] = false
		return {"record": _movement_patch(actor_id, {"move_order": move_order, "locomotion_state": _idle_locomotion_state(source_record, "blocked")}), "was_active": true, "moved": false, "arrived": false}
	var target = move_order.get("target_position", null)
	if not (target is Vector3):
		move_order = move_order.duplicate(true)
		move_order["active"] = false
		return {"record": _movement_patch(actor_id, {"move_order": move_order, "locomotion_state": _idle_locomotion_state(source_record, "invalid_target")}), "was_active": true, "moved": false, "arrived": false}
	var target_position: Vector3 = target
	var current_position := _record_position(source_record)
	var horizontal_delta := Vector2(target_position.x - current_position.x, target_position.z - current_position.z)
	var horizontal_distance := horizontal_delta.length()
	if horizontal_distance <= arrival_threshold:
		move_order = move_order.duplicate(true)
		move_order["active"] = false
		return {
			"record": _movement_patch(actor_id, {
				"move_order": move_order,
				"last_world_position": target_position,
				"last_world_position_initialized": true,
				"ledger_activity_state": "player_move_order_complete",
				"locomotion_state": _idle_locomotion_state(source_record, "arrived"),
			}),
			"was_active": true,
			"moved": false,
			"arrived": true,
		}
	var movement_mode := int(move_order.get("movement_mode", source_record.get("movement_mode", MOVEMENT_MODE_WALK)))
	var speed := _move_speed(source_record, movement_mode)
	var step := minf(speed * fixed_delta, horizontal_distance)
	var direction_2d := horizontal_delta / maxf(horizontal_distance, 0.001)
	var direction := Vector3(direction_2d.x, 0.0, direction_2d.y).normalized()
	var next_position := current_position + direction * step
	next_position.y = move_toward(current_position.y, target_position.y, vertical_snap_speed * fixed_delta)
	return {"record": _movement_patch(actor_id, {
		"last_world_position": next_position,
		"last_world_position_initialized": true,
		"realization_state": "projected_commanded",
		"ledger_activity_state": "player_move_order",
		"world_facing_yaw": atan2(direction.x, direction.z),
		"world_facing_yaw_initialized": true,
		"locomotion_state": {
		"active": true,
		"moving": true,
		"source": "move_order",
		"movement_mode": movement_mode,
		"animation_state": _animation_state_for_mode(movement_mode),
		"speed": speed,
		"horizontal_speed": speed,
		"world_direction": direction,
		"target_position": target_position,
		},
	}), "was_active": true, "moved": true, "arrived": false}


func _movement_patch(actor_id: String, fields: Dictionary) -> Dictionary:
	var patch := {"actor_id": actor_id}
	for key in fields.keys():
		patch[key] = fields[key]
	return patch


func _idle_locomotion_state(record: Dictionary, reason: String) -> Dictionary:
	var movement_mode := int(record.get("movement_mode", MOVEMENT_MODE_WALK))
	return {
		"active": false,
		"moving": false,
		"source": reason,
		"movement_mode": movement_mode,
		"animation_state": "sneak_idle" if movement_mode == MOVEMENT_MODE_SNEAK else "idle",
		"speed": 0.0,
		"horizontal_speed": 0.0,
		"world_direction": Vector3.ZERO,
	}


func _animation_state_for_mode(movement_mode: int) -> String:
	match movement_mode:
		MOVEMENT_MODE_RUN:
			return "run"
		MOVEMENT_MODE_SNEAK:
			return "sneak"
	return "walk"


func _move_speed(record: Dictionary, movement_mode: int) -> float:
	match movement_mode:
		MOVEMENT_MODE_RUN:
			return base_walk_speed * _run_speed_multiplier(record)
		MOVEMENT_MODE_SNEAK:
			return base_walk_speed * _sneak_move_speed_multiplier(record)
	return base_walk_speed


func _run_speed_multiplier(record: Dictionary) -> float:
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	var level := float(skill_levels.get(SKILL_MOVEMENT_RUNNING, SkillRules.DEFAULT_LEVEL))
	return NpcRules.RUN_SPEED_MULTIPLIER + SkillRules.get_diminishing_bonus(level, 0.42, 55.0)


func _sneak_move_speed_multiplier(record: Dictionary) -> float:
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	var sneak_level := float(skill_levels.get(SKILL_SUBTERFUGE_SNEAKING, SkillRules.DEFAULT_LEVEL))
	var ratio := clampf((sneak_level - float(SkillRules.DEFAULT_LEVEL)) / maxf(SNEAK_MOVE_SPEED_MASTER_LEVEL - float(SkillRules.DEFAULT_LEVEL), 0.001), 0.0, 1.0)
	var mastery := pow(ratio, SNEAK_MOVE_SPEED_CURVE)
	return lerpf(SNEAK_MOVE_SPEED_MIN_MULTIPLIER, SNEAK_MOVE_SPEED_MAX_MULTIPLIER, mastery)


func _record_position(record: Dictionary) -> Vector3:
	var position = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return position if position is Vector3 else Vector3.ZERO


func _get_gecs_world() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null


func _get_population_records_core(bridge: Node) -> Dictionary:
	if bridge.has_method("get_population_records_core"):
		var core_records = bridge.call("get_population_records_core")
		return core_records if core_records is Dictionary else {}
	if bridge.has_method("get_population_records"):
		var records = bridge.call("get_population_records")
		return records if records is Dictionary else {}
	return {}


func _upsert_population_record_core(bridge: Node, record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {}
	if bridge.has_method("upsert_population_record_core"):
		var updated = bridge.call("upsert_population_record_core", record)
		return updated if updated is Dictionary else {}
	if bridge.has_method("upsert_population_record"):
		var fallback = bridge.call("upsert_population_record", record)
		return fallback if fallback is Dictionary else {}
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
