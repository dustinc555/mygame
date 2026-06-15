extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatMovementSystem

const C_NODE = preload("res://scripts/ecs/components/c_game_actor_node.gd")
const C_IDENTITY = preload("res://scripts/ecs/components/c_game_actor_identity.gd")
const C_SPATIAL = preload("res://scripts/ecs/components/c_game_actor_spatial.gd")
const C_VITALS = preload("res://scripts/ecs/components/c_game_actor_vitals.gd")
const C_CONFIG = preload("res://scripts/ecs/components/c_game_combat_config.gd")
const C_ACTION = preload("res://scripts/ecs/components/c_game_combat_action.gd")
const C_SLOT = preload("res://scripts/ecs/components/c_game_combat_slot_state.gd")
const C_MOVEMENT = preload("res://scripts/ecs/components/c_game_movement_state.gd")

const ARRIVAL_DISTANCE := 0.25
const FIGHT_STATE_SEEKING_SLOT := 2
const FIGHT_STATE_FIGHTING := 3
const FIGHT_STATE_WAITING := 4
const DIRECT_FOLLOW_RANGE_BUFFER := 0.06
# Cap only against genuine real-frame hitches (e.g. a 100ms+ stall), NOT against game time_scale.
# The scene `delta` is already multiplied by Engine.time_scale, so multiplying the cap by time_scale
# lets fast-forward (>>, >>>) pass through at full game-time while still bounding a real stall.
const MAX_REAL_MOVEMENT_SECONDS := 0.1
const FIXED_COMBAT_TICK_SECONDS := 1.0 / 20.0
const MAX_FIXED_STEPS_PER_FRAME := 5

static var _fixed_accumulator := 0.0


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_ACTION, C_SLOT, C_MOVEMENT]).iterate(
		[C_NODE, C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_ACTION, C_SLOT, C_MOVEMENT])


func process(_entities: Array, components: Array, delta: float) -> void:
	# Move on fixed combat ticks. `delta` already includes Engine.time_scale, so fast-forward still
	# advances game-time while the fixed step keeps movement deterministic enough for simulation.
	var scaled_max_delta := MAX_REAL_MOVEMENT_SECONDS * maxf(Engine.time_scale, 0.0001)
	var movement_delta := minf(maxf(delta, 0.0), scaled_max_delta)
	var nodes: Array = components[0]
	var identities: Array = components[1]
	var spatials: Array = components[2]
	var vitals: Array = components[3]
	var configs: Array = components[4]
	var actions: Array = components[5]
	var slots: Array = components[6]
	var movements: Array = components[7]
	var count := nodes.size()
	var actor_index_by_id := {}
	for i in range(count):
		var identity = identities[i]
		if identity != null and not str(identity.actor_id).is_empty():
			actor_index_by_id[str(identity.actor_id)] = i
	var process_frame := Engine.get_process_frames()
	_fixed_accumulator = minf(_fixed_accumulator + movement_delta, FIXED_COMBAT_TICK_SECONDS * float(MAX_FIXED_STEPS_PER_FRAME))
	var fixed_steps := 0
	while _fixed_accumulator >= FIXED_COMBAT_TICK_SECONDS and fixed_steps < MAX_FIXED_STEPS_PER_FRAME:
		for i in range(count):
			_process_actor_movement(i, process_frame, FIXED_COMBAT_TICK_SECONDS, nodes, spatials, vitals, configs, actions, slots, movements, actor_index_by_id)
		_fixed_accumulator -= FIXED_COMBAT_TICK_SECONDS
		fixed_steps += 1
	if fixed_steps == 0:
		_refresh_node_movement_bridges(process_frame, nodes, movements, count)


func _process_actor_movement(index: int, process_frame: int, delta: float, nodes: Array, spatials: Array, vitals: Array, configs: Array, actions: Array, slots: Array, movements: Array, actor_index_by_id: Dictionary) -> void:
	var movement = movements[index]
	if movement == null:
		return
	# Keep last frame's velocity so the acceleration lerp ramps up to move_speed instead of restarting
	# from zero every frame (which would cap movement well below base speed).
	var previous_velocity: Vector3 = movement.desired_velocity
	movement.system_movement_active = false
	movement.combat_settled = false
	movement.collision_focus_instance_id = 0
	movement.desired_velocity = Vector3.ZERO
	var actor := _actor_from_node_component(nodes[index])
	if actor == null:
		return
	var vit = vitals[index]
	var cfg = configs[index]
	var action = actions[index]
	var slot = slots[index]
	if vit == null or cfg == null or action == null or slot == null or vit.life_state != NpcRules.LifeState.ALIVE:
		_write_node_movement(actor, process_frame, false)
		return
	var target_actor_id := str(slot.slot_target_actor_id)
	if int(slot.slot_state) == 0:
		_write_node_movement(actor, process_frame, false)
		return
	if target_actor_id.is_empty() or not actor_index_by_id.has(target_actor_id):
		_write_node_movement(actor, process_frame, false)
		return
	var target_index: int = actor_index_by_id[target_actor_id]
	var target_vit = vitals[target_index]
	var target_cfg = configs[target_index]
	if target_vit == null or target_cfg == null or target_vit.life_state != NpcRules.LifeState.ALIVE:
		_write_node_movement(actor, process_frame, false)
		return
	movement.system_movement_active = true
	var pos: Vector3 = spatials[index].world_position
	var target_center: Vector3 = spatials[target_index].world_position
	var fight_state := int(slot.slot_state)
	var move_pos := target_center
	var target_actor := _actor_from_node_component(nodes[target_index])
	var focus_id := target_actor.get_instance_id() if target_actor != null else 0
	movement.move_target_position = move_pos
	movement.look_target_position = target_center
	movement.collision_focus_instance_id = focus_id
	if action.action_active or action.reaction_remaining > 0.0 or absf(target_center.y - pos.y) > cfg.move_target_vertical_tolerance or _should_settle_state(fight_state):
		movement.combat_settled = true
		movement.desired_velocity = Vector3.ZERO
		_write_node_movement(actor, process_frame, true, move_pos, Vector3.ZERO, target_center, true, focus_id)
		return
	var stop_distance := _follow_stop_distance(cfg, target_cfg)
	var move_offset := target_center - pos
	move_offset.y = 0.0
	var move_distance := move_offset.length()
	if move_distance <= stop_distance:
		movement.combat_settled = true
		movement.desired_velocity = Vector3.ZERO
		_write_node_movement(actor, process_frame, true, move_pos, Vector3.ZERO, target_center, true, focus_id)
		return
	var direction := move_offset / maxf(move_distance, 0.001)
	var speed := maxf(float(cfg.move_speed), 0.0)
	var target_velocity := direction * speed
	var current_velocity: Vector3 = previous_velocity
	var next_velocity := current_velocity.lerp(target_velocity, minf(1.0, maxf(float(cfg.movement_acceleration), 0.0) * delta))
	var max_velocity_length := maxf(0.0, (move_distance - stop_distance) / maxf(delta, 0.0001))
	movement.desired_velocity = direction * minf(next_velocity.length(), max_velocity_length)
	_write_node_movement(actor, process_frame, true, move_pos, movement.desired_velocity, target_center, false, focus_id)


func _should_settle_state(fight_state: int) -> bool:
	return fight_state == FIGHT_STATE_SEEKING_SLOT or fight_state == FIGHT_STATE_FIGHTING or fight_state == FIGHT_STATE_WAITING


func _follow_stop_distance(cfg, target_cfg) -> float:
	return maxf(minf(float(cfg.attack_range), float(target_cfg.attack_range)) - DIRECT_FOLLOW_RANGE_BUFFER, 0.55)


func _write_node_movement(actor: Node, process_frame: int, is_active: bool, move_target := Vector3.ZERO, desired_velocity := Vector3.ZERO, look_target := Vector3.ZERO, settled := false, collision_focus_id := 0) -> void:
	var world_actor := actor as WorldActor
	if world_actor != null:
		world_actor.set_system_movement_bridge(process_frame, is_active, move_target, desired_velocity, look_target, settled, collision_focus_id)
	elif actor.has_method("set"):
		actor.set("_system_movement_active", is_active)
		actor.set("_system_movement_target_position", move_target)
		actor.set("_system_movement_desired_velocity", desired_velocity)
		actor.set("_system_movement_look_target", look_target)
		actor.set("_system_movement_settled", settled)
		actor.set("_system_movement_collision_focus_id", collision_focus_id)


func _refresh_node_movement_bridges(process_frame: int, nodes: Array, movements: Array, count: int) -> void:
	for i in range(count):
		var actor := _actor_from_node_component(nodes[i])
		var movement = movements[i]
		if actor != null and movement != null:
			_write_node_movement(actor, process_frame, bool(movement.system_movement_active), movement.move_target_position, movement.desired_velocity, movement.look_target_position, bool(movement.combat_settled), int(movement.collision_focus_instance_id))


func _actor_from_node_component(node_component) -> Node:
	if node_component == null:
		return null
	var actor = node_component.get_actor() if node_component.has_method("get_actor") else node_component.actor
	return actor as Node if actor != null and is_instance_valid(actor) else null
