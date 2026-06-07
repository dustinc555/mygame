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

var root_scene: Node
var _last_state: Dictionary = {}


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root


func _ready() -> void:
	add_to_group("world_movement_order_sim_controller")


func update_sim(fixed_delta: float) -> void:
	if fixed_delta <= 0.0:
		return
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_population_records") or not bridge.has_method("upsert_population_record"):
		return
	var records: Dictionary = bridge.call("get_population_records")
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
		bridge.call("upsert_population_record", result.get("record", {}))
	_last_state = {
		"active_count": active_count,
		"moved_count": moved_count,
		"arrived_count": arrived_count,
	}


func get_sim_state() -> Dictionary:
	return _last_state.duplicate(true)


func _advance_record(source_record: Dictionary, fixed_delta: float) -> Dictionary:
	var move_order: Dictionary = source_record.get("move_order", {}) if source_record.get("move_order", {}) is Dictionary else {}
	var order_active := bool(move_order.get("active", false))
	var locomotion_state: Dictionary = source_record.get("locomotion_state", {}) if source_record.get("locomotion_state", {}) is Dictionary else {}
	if not order_active:
		if bool(locomotion_state.get("moving", false)):
			var idle_record := source_record.duplicate(true)
			idle_record["locomotion_state"] = _idle_locomotion_state(idle_record, "idle")
			return {"record": idle_record, "was_active": false, "moved": false, "arrived": false}
		return {}
	var record := source_record.duplicate(true)
	if int(record.get("life_state", 0)) != 0:
		move_order = move_order.duplicate(true)
		move_order["active"] = false
		record["move_order"] = move_order
		record["locomotion_state"] = _idle_locomotion_state(record, "blocked")
		return {"record": record, "was_active": true, "moved": false, "arrived": false}
	var target = move_order.get("target_position", null)
	if not (target is Vector3):
		move_order = move_order.duplicate(true)
		move_order["active"] = false
		record["move_order"] = move_order
		record["locomotion_state"] = _idle_locomotion_state(record, "invalid_target")
		return {"record": record, "was_active": true, "moved": false, "arrived": false}
	var target_position: Vector3 = target
	var current_position := _record_position(record)
	var horizontal_delta := Vector2(target_position.x - current_position.x, target_position.z - current_position.z)
	var horizontal_distance := horizontal_delta.length()
	if horizontal_distance <= arrival_threshold:
		move_order = move_order.duplicate(true)
		move_order["active"] = false
		record["move_order"] = move_order
		record["last_world_position"] = target_position
		record["last_world_position_initialized"] = true
		record["ledger_activity_state"] = "player_move_order_complete"
		record["locomotion_state"] = _idle_locomotion_state(record, "arrived")
		return {"record": record, "was_active": true, "moved": false, "arrived": true}
	var movement_mode := int(move_order.get("movement_mode", record.get("movement_mode", MOVEMENT_MODE_WALK)))
	var speed := _move_speed(record, movement_mode)
	var step := minf(speed * fixed_delta, horizontal_distance)
	var direction_2d := horizontal_delta / maxf(horizontal_distance, 0.001)
	var direction := Vector3(direction_2d.x, 0.0, direction_2d.y).normalized()
	var next_position := current_position + direction * step
	next_position.y = move_toward(current_position.y, target_position.y, vertical_snap_speed * fixed_delta)
	record["last_world_position"] = next_position
	record["last_world_position_initialized"] = true
	record["realization_state"] = "projected_commanded"
	record["ledger_activity_state"] = "player_move_order"
	record["world_facing_yaw"] = atan2(direction.x, direction.z)
	record["world_facing_yaw_initialized"] = true
	record["locomotion_state"] = {
		"active": true,
		"moving": true,
		"source": "move_order",
		"movement_mode": movement_mode,
		"animation_state": _animation_state_for_mode(movement_mode),
		"speed": speed,
		"horizontal_speed": speed,
		"world_direction": direction,
		"target_position": target_position,
	}
	return {"record": record, "was_active": true, "moved": true, "arrived": false}


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
