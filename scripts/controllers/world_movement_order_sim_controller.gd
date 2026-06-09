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
const INTERACTION_PICKUP_STACK := "pickup_stack"
const INTERACTION_MINE_RESOURCE := "mine_resource"
const MINING_ORE_WORTH_FOR_FIRST_LEVEL := 4.0
const MINING_STRENGTH_XP_FACTOR := 0.08
const MINING_STRENGTH_SPEED_BONUS_CAP := 0.12
const MINING_STRENGTH_SPEED_BONUS_CURVE := 45.0

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
		_stop_projection_runtime_move(actor_id)
		var work_action: Dictionary = source_record.get("work_action", {}) if source_record.get("work_action", {}) is Dictionary else {}
		var work_result := _advance_work_action(source_record, work_action, fixed_delta)
		if not work_result.is_empty():
			return work_result
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
	var projection_result := _advance_projected_move_order(actor_id, source_record, fixed_delta)
	if not projection_result.is_empty():
		return projection_result
	var target_position: Vector3 = target
	var current_position := _record_position(source_record)
	var horizontal_delta := Vector2(target_position.x - current_position.x, target_position.z - current_position.z)
	var horizontal_distance := horizontal_delta.length()
	if horizontal_distance <= arrival_threshold:
		move_order = move_order.duplicate(true)
		move_order["active"] = false
		var arrival_patch := {
			"move_order": move_order,
			"last_world_position": target_position,
			"last_world_position_initialized": true,
			"ledger_activity_state": "player_move_order_complete",
			"locomotion_state": _idle_locomotion_state(source_record, "arrived"),
		}
		_apply_arrival_interaction(actor_id, move_order, arrival_patch)
		return {
			"record": _movement_patch(actor_id, arrival_patch),
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


func _advance_projected_move_order(actor_id: String, source_record: Dictionary, fixed_delta: float) -> Dictionary:
	var projection := _projection_for_actor(actor_id)
	if projection == null or not projection.has_method("advance_move_order"):
		return {}
	var result = projection.call("advance_move_order", source_record, fixed_delta)
	if not (result is Dictionary):
		return {}
	var move_result: Dictionary = result
	var move_order: Dictionary = source_record.get("move_order", {}) if source_record.get("move_order", {}) is Dictionary else {}
	if bool(move_result.get("arrived", false)):
		move_order = move_order.duplicate(true)
		move_order["active"] = false
		var arrival_position: Vector3 = move_result.get("position", _record_position(source_record))
		var arrival_patch := {
			"move_order": move_order,
			"last_world_position": arrival_position,
			"last_world_position_initialized": true,
			"world_facing_yaw": float(move_result.get("facing_yaw", source_record.get("world_facing_yaw", 0.0))),
			"world_facing_yaw_initialized": true,
			"ledger_activity_state": "player_move_order_complete",
			"locomotion_state": _idle_locomotion_state(source_record, "arrived"),
		}
		_apply_arrival_interaction(actor_id, move_order, arrival_patch)
		return {"record": _movement_patch(actor_id, arrival_patch), "was_active": true, "moved": true, "arrived": true}
	if bool(move_result.get("blocked", false)):
		move_order = move_order.duplicate(true)
		move_order["active"] = false
		return {"record": _movement_patch(actor_id, {"move_order": move_order, "locomotion_state": _idle_locomotion_state(source_record, str(move_result.get("reason", "blocked")))}), "was_active": true, "moved": false, "arrived": false}
	var movement_mode := int(move_result.get("movement_mode", move_order.get("movement_mode", source_record.get("movement_mode", MOVEMENT_MODE_WALK))))
	var moving := bool(move_result.get("moving", false))
	var locomotion_patch := {
		"active": moving,
		"moving": moving,
		"source": "move_order",
		"movement_mode": movement_mode,
		"animation_state": _animation_state_for_mode(movement_mode) if moving else ("sneak_idle" if movement_mode == MOVEMENT_MODE_SNEAK else "idle"),
		"speed": float(move_result.get("speed", 0.0)),
		"horizontal_speed": float(move_result.get("horizontal_speed", 0.0)),
		"world_direction": move_result.get("direction", Vector3.ZERO),
		"target_position": move_order.get("target_position", Vector3.ZERO),
	}
	return {"record": _movement_patch(actor_id, {
		"realization_state": "projected_commanded",
		"ledger_activity_state": "player_move_order",
		"world_facing_yaw": float(move_result.get("facing_yaw", source_record.get("world_facing_yaw", 0.0))),
		"world_facing_yaw_initialized": true,
		"locomotion_state": locomotion_patch,
	}), "was_active": true, "moved": moving, "arrived": false}


func _apply_arrival_interaction(actor_id: String, move_order: Dictionary, arrival_patch: Dictionary) -> void:
	var interaction_action: Dictionary = move_order.get("interaction_action", {}) if move_order.get("interaction_action", {}) is Dictionary else {}
	if interaction_action.is_empty():
		arrival_patch["work_action"] = {"active": false}
		return
	match str(interaction_action.get("type", "")).strip_edges():
		INTERACTION_PICKUP_STACK:
			var result := _apply_inventory_command({"action": "pickup_stack", "actor_id": actor_id, "stack_id": str(interaction_action.get("stack_id", ""))})
			arrival_patch["ledger_activity_state"] = "pickup_complete" if bool(result.get("ok", false)) else "pickup_failed"
			arrival_patch["last_interaction_result"] = result
			arrival_patch["work_action"] = {"active": false}
		INTERACTION_MINE_RESOURCE:
			var work_action := interaction_action.duplicate(true)
			work_action["active"] = true
			work_action["progress_seconds"] = 0.0
			arrival_patch["ledger_activity_state"] = "mining_resource"
			arrival_patch["work_action"] = work_action
		_:
			arrival_patch["work_action"] = {"active": false}


func _advance_work_action(source_record: Dictionary, work_action: Dictionary, fixed_delta: float) -> Dictionary:
	if not bool(work_action.get("active", false)):
		return {}
	var actor_id := str(source_record.get("actor_id", source_record.get("stable_id", ""))).strip_edges()
	if actor_id.is_empty():
		return {}
	if int(source_record.get("life_state", 0)) != 0:
		work_action = work_action.duplicate(true)
		work_action["active"] = false
		return {"record": _movement_patch(actor_id, {"work_action": work_action, "locomotion_state": _idle_locomotion_state(source_record, "blocked")}), "was_active": true, "moved": false, "arrived": false}
	match str(work_action.get("type", "")).strip_edges():
		INTERACTION_MINE_RESOURCE:
			return _advance_mining_action(source_record, work_action, fixed_delta)
		_:
			work_action = work_action.duplicate(true)
			work_action["active"] = false
			return {"record": _movement_patch(actor_id, {"work_action": work_action}), "was_active": true, "moved": false, "arrived": false}


func _advance_mining_action(source_record: Dictionary, work_action: Dictionary, fixed_delta: float) -> Dictionary:
	var actor_id := str(source_record.get("actor_id", source_record.get("stable_id", ""))).strip_edges()
	var next_action := work_action.duplicate(true)
	var full_record := _population_record_full(actor_id)
	var actor_record := full_record if not full_record.is_empty() else source_record
	var required_tool_tag := str(next_action.get("required_tool_tag", "")).strip_edges()
	if not required_tool_tag.is_empty():
		var tool_result := _apply_inventory_command({
			"action": "ensure_equipped_tool",
			"actor_id": actor_id,
			"required_tool_tag": required_tool_tag,
			"required_tool_label": str(next_action.get("required_tool_label", "Tool")),
		})
		if not bool(tool_result.get("ok", false)):
			next_action["active"] = false
			next_action["last_result"] = tool_result
			return {"record": _movement_patch(actor_id, {"work_action": next_action, "last_interaction_result": tool_result, "ledger_activity_state": "mining_failed", "locomotion_state": _idle_locomotion_state(source_record, "missing_tool")}), "was_active": true, "moved": false, "arrived": false}
	var mining_position = next_action.get("mining_position", next_action.get("resource_position", null))
	if mining_position is Vector3:
		var current_position := _record_position(actor_record)
		var interaction_radius := maxf(float(next_action.get("interaction_radius", 1.8)), 0.05)
		if current_position.distance_to(mining_position) > interaction_radius:
			next_action["active"] = false
			var range_result := {"ok": false, "message": "Out of mining range"}
			next_action["last_result"] = range_result
			return {"record": _movement_patch(actor_id, {"work_action": next_action, "last_interaction_result": range_result, "ledger_activity_state": "mining_failed", "locomotion_state": _idle_locomotion_state(source_record, "out_of_range")}), "was_active": true, "moved": false, "arrived": false}
	var duration := _effective_mine_duration_for_action(next_action, actor_record)
	var progress_before := clampf(float(next_action.get("progress_ratio", 0.0)), 0.0, 1.0)
	var item_path := str(next_action.get("item_definition_path", "")).strip_edges()
	if item_path.is_empty():
		next_action["active"] = false
		var missing_item_result := {"ok": false, "message": "Missing mined item"}
		next_action["last_result"] = missing_item_result
		return {"record": _movement_patch(actor_id, {"work_action": next_action, "last_interaction_result": missing_item_result, "ledger_activity_state": "mining_failed", "locomotion_state": _idle_locomotion_state(source_record, "missing_item")}), "was_active": true, "moved": false, "arrived": false}
	var can_produce_ore := _can_mining_action_produce_ore(next_action, actor_record)
	var patch := {}
	_apply_mining_facing_patch(next_action, actor_record, patch)
	if progress_before >= 1.0:
		if can_produce_ore:
			var stored_result := _apply_inventory_command({"action": "grant_item", "actor_id": actor_id, "item_definition_path": item_path, "count": 1})
			if bool(stored_result.get("ok", false)):
				progress_before = 0.0
			else:
				next_action["progress_ratio"] = 1.0
				next_action["progress_seconds"] = duration
				next_action["last_result"] = stored_result
				patch["work_action"] = next_action
				patch["last_interaction_result"] = stored_result
				patch["ledger_activity_state"] = "mining_inventory_full"
				patch["locomotion_state"] = _idle_locomotion_state(source_record, "mining_inventory_full")
				return {"record": _movement_patch(actor_id, patch), "was_active": true, "moved": false, "arrived": false}
		else:
			progress_before = 0.0
	var progress_delta := minf(fixed_delta / duration, maxf(1.0 - progress_before, 0.0))
	_award_mining_progress_xp(actor_record, patch, progress_delta, float(next_action.get("locked_attempt_xp_multiplier", 1.0)))
	var progress := progress_before + progress_delta
	var last_result := {"ok": true, "message": "Mining"}
	if progress >= 1.0:
		if can_produce_ore:
			last_result = _apply_inventory_command({"action": "grant_item", "actor_id": actor_id, "item_definition_path": item_path, "count": 1})
			if bool(last_result.get("ok", false)):
				progress = 0.0
			else:
				progress = 1.0
		else:
			last_result = {"ok": false, "message": "Mining %d required" % int(next_action.get("required_mining_level", 0))}
			progress = 0.0
	next_action["active"] = true
	next_action["progress_ratio"] = clampf(progress, 0.0, 1.0)
	next_action["progress_seconds"] = next_action["progress_ratio"] * duration
	next_action["duration_seconds"] = duration
	next_action["last_result"] = last_result
	patch["work_action"] = next_action
	patch["last_interaction_result"] = last_result
	patch["ledger_activity_state"] = "mining_resource" if progress < 1.0 else "mining_inventory_full"
	patch["locomotion_state"] = _work_locomotion_state(source_record, "mining") if progress < 1.0 else _idle_locomotion_state(source_record, "mining_inventory_full")
	return {"record": _movement_patch(actor_id, patch), "was_active": true, "moved": false, "arrived": false}


func _apply_mining_facing_patch(action: Dictionary, record: Dictionary, patch: Dictionary) -> void:
	var resource_position = action.get("resource_position", null)
	if not (resource_position is Vector3):
		return
	var current_position := _record_position(record)
	var direction: Vector3 = resource_position - current_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return
	patch["world_facing_yaw"] = atan2(direction.x, direction.z)
	patch["world_facing_yaw_initialized"] = true


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


func _work_locomotion_state(record: Dictionary, animation_state: String) -> Dictionary:
	var movement_mode := int(record.get("movement_mode", MOVEMENT_MODE_WALK))
	return {
		"active": true,
		"moving": false,
		"source": animation_state,
		"movement_mode": movement_mode,
		"animation_state": animation_state,
		"speed": 0.0,
		"horizontal_speed": 0.0,
		"world_direction": Vector3.ZERO,
	}


func _effective_mine_duration_for_action(action: Dictionary, record: Dictionary) -> float:
	if action.has("duration_seconds"):
		return maxf(float(action.get("duration_seconds", 0.0)), 0.1)
	var required_level := int(action.get("required_mining_level", 0))
	var slow_seconds := maxf(float(action.get("slow_mine_seconds", action.get("duration_seconds", 15.0))), 0.1)
	var fast_seconds := maxf(float(action.get("fast_mine_seconds", action.get("duration_seconds", 7.0))), 0.1)
	var levels_to_fast := int(action.get("levels_to_fast_speed", 30))
	var relative_level := maxf(float(_skill_level(record, SkillRules.LABOR_MINING) - required_level), 0.0)
	var speed_ratio := 1.0 if levels_to_fast <= 0 else clampf(relative_level / float(levels_to_fast), 0.0, 1.0)
	var skill_seconds := lerpf(slow_seconds, fast_seconds, speed_ratio)
	var strength_level := maxf(float(_skill_level(record, SkillRules.ATTRIBUTE_STRENGTH) - SkillRules.DEFAULT_LEVEL), 0.0)
	var strength_bonus := SkillRules.get_diminishing_bonus(strength_level, MINING_STRENGTH_SPEED_BONUS_CAP, MINING_STRENGTH_SPEED_BONUS_CURVE)
	return maxf(skill_seconds / (1.0 + strength_bonus), 0.1)


func _can_mining_action_produce_ore(action: Dictionary, record: Dictionary) -> bool:
	return _skill_level(record, SkillRules.LABOR_MINING) >= int(action.get("required_mining_level", 0))


func _award_mining_progress_xp(record: Dictionary, patch: Dictionary, progress_delta: float, xp_multiplier: float) -> void:
	if progress_delta <= 0.0 or xp_multiplier <= 0.0:
		return
	var mining_xp := SkillRules.get_xp_to_next_level(SkillRules.DEFAULT_LEVEL) / MINING_ORE_WORTH_FOR_FIRST_LEVEL * progress_delta * xp_multiplier
	_add_skill_xp_to_patch(record, patch, SkillRules.LABOR_MINING, mining_xp)
	_add_skill_xp_to_patch(record, patch, SkillRules.ATTRIBUTE_STRENGTH, mining_xp * MINING_STRENGTH_XP_FACTOR)


func _add_skill_xp_to_patch(record: Dictionary, patch: Dictionary, skill_id: String, amount: float) -> void:
	if skill_id.strip_edges().is_empty() or amount <= 0.0:
		return
	var skill_levels: Dictionary = (patch.get("skill_levels", record.get("skill_levels", {})) as Dictionary).duplicate(true)
	var skill_xp: Dictionary = (patch.get("skill_xp", record.get("skill_xp", {})) as Dictionary).duplicate(true)
	var level := int(skill_levels.get(skill_id, SkillRules.get_default_level(skill_id)))
	var xp := float(skill_xp.get(skill_id, 0.0)) + amount
	var xp_to_next := SkillRules.get_xp_to_next_level(level)
	while xp >= xp_to_next and xp_to_next > 0.0:
		xp -= xp_to_next
		level += 1
		xp_to_next = SkillRules.get_xp_to_next_level(level)
	skill_levels[skill_id] = level
	skill_xp[skill_id] = xp
	patch["skill_levels"] = skill_levels
	patch["skill_xp"] = skill_xp


func _skill_level(record: Dictionary, skill_id: String) -> int:
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	return int(skill_levels.get(skill_id, SkillRules.get_default_level(skill_id)))


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


func _projection_for_actor(actor_id: String) -> Node:
	var projection_controller := _get_projection_controller()
	if projection_controller != null and projection_controller.has_method("get_projection_for_actor"):
		var projection = projection_controller.call("get_projection_for_actor", actor_id)
		return projection as Node if projection is Node else null
	return null


func _stop_projection_runtime_move(actor_id: String) -> void:
	var projection := _projection_for_actor(actor_id)
	if projection != null and projection.has_method("stop_runtime_move_order"):
		projection.call("stop_runtime_move_order")


func _get_projection_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldActorProjectionController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_actor_projection_controller") if is_inside_tree() else null


func _get_population_records_core(bridge: Node) -> Dictionary:
	if bridge.has_method("get_population_records_core"):
		var core_records = bridge.call("get_population_records_core")
		return core_records if core_records is Dictionary else {}
	if bridge.has_method("get_population_records"):
		var records = bridge.call("get_population_records")
		return records if records is Dictionary else {}
	return {}


func _population_record_full(actor_id: String) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge == null or actor_id.strip_edges().is_empty():
		return {}
	var record = bridge.call("get_population_record", actor_id) if bridge.has_method("get_population_record") else (bridge.call("get_population_record_core", actor_id) if bridge.has_method("get_population_record_core") else {})
	return record if record is Dictionary else {}


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


func _apply_inventory_command(command: Dictionary) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("apply_inventory_command"):
		return {"ok": false, "message": "Missing GECS inventory"}
	var result = bridge.call("apply_inventory_command", command)
	return result if result is Dictionary else {"ok": false, "message": "Invalid inventory result"}


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
