extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatMovementSystem

const C_NODE = preload("res://scripts/ecs/components/c_game_actor_node.gd")
const C_IDENTITY = preload("res://scripts/ecs/components/c_game_actor_identity.gd")
const C_SPATIAL = preload("res://scripts/ecs/components/c_game_actor_spatial.gd")
const C_VITALS = preload("res://scripts/ecs/components/c_game_actor_vitals.gd")
const C_CONFIG = preload("res://scripts/ecs/components/c_game_combat_config.gd")
const C_STATE = preload("res://scripts/ecs/components/c_game_combat_state.gd")
const C_ACTION = preload("res://scripts/ecs/components/c_game_combat_action.gd")
const C_MOVEMENT = preload("res://scripts/ecs/components/c_game_movement_state.gd")

const COMBAT_RANGE_HYSTERESIS := 0.18
const ARRIVAL_DISTANCE := 0.25
# Cap only against genuine real-frame hitches (e.g. a 100ms+ stall), NOT against game time_scale.
# The scene `delta` is already multiplied by Engine.time_scale, so multiplying the cap by time_scale
# lets fast-forward (>>, >>>) pass through at full game-time while still bounding a real stall.
const MAX_REAL_MOVEMENT_SECONDS := 0.1
const FIXED_COMBAT_TICK_SECONDS := 1.0 / 20.0
const MAX_FIXED_STEPS_PER_FRAME := 5

static var enabled := not OS.get_cmdline_args().has("--combat-movement-system-off")
static var _fixed_accumulator := 0.0


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_STATE, C_ACTION, C_MOVEMENT]).iterate(
		[C_NODE, C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_STATE, C_ACTION, C_MOVEMENT])


func process(_entities: Array, components: Array, delta: float) -> void:
	if not enabled:
		return
	# Move on fixed combat ticks. `delta` already includes Engine.time_scale, so fast-forward still
	# advances game-time while the fixed step keeps movement deterministic enough for simulation.
	var scaled_max_delta := MAX_REAL_MOVEMENT_SECONDS * maxf(Engine.time_scale, 0.0001)
	var movement_delta := minf(maxf(delta, 0.0), scaled_max_delta)
	var nodes: Array = components[0]
	var identities: Array = components[1]
	var spatials: Array = components[2]
	var vitals: Array = components[3]
	var configs: Array = components[4]
	var states: Array = components[5]
	var actions: Array = components[6]
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
			_process_actor_movement(i, process_frame, FIXED_COMBAT_TICK_SECONDS, nodes, spatials, vitals, configs, states, actions, movements, actor_index_by_id)
		_fixed_accumulator -= FIXED_COMBAT_TICK_SECONDS
		fixed_steps += 1
	if fixed_steps == 0:
		_refresh_node_movement_bridges(process_frame, nodes, movements, count)


func _process_actor_movement(index: int, process_frame: int, delta: float, nodes: Array, spatials: Array, vitals: Array, configs: Array, states: Array, actions: Array, movements: Array, actor_index_by_id: Dictionary) -> void:
	var movement = movements[index]
	if movement == null:
		return
	# Keep last frame's velocity so the acceleration lerp ramps up to move_speed instead of restarting
	# from zero every frame (which would cap movement well below base speed).
	var previous_velocity: Vector3 = movement.desired_velocity
	movement.system_movement_active = false
	movement.desired_velocity = Vector3.ZERO
	var actor := _actor_from_node_component(nodes[index])
	if actor == null:
		return
	var vit = vitals[index]
	var cfg = configs[index]
	var state = states[index]
	var action = actions[index]
	if vit == null or cfg == null or state == null or action == null or vit.life_state != NpcRules.LifeState.ALIVE:
		_write_node_movement(actor, process_frame, false)
		return
	var target_actor_id := str(state.current_target_actor_id)
	if target_actor_id.is_empty() or not actor_index_by_id.has(target_actor_id):
		_write_node_movement(actor, process_frame, false)
		return
	var target_index: int = actor_index_by_id[target_actor_id]
	var target_vit = vitals[target_index]
	if target_vit == null or target_vit.life_state != NpcRules.LifeState.ALIVE:
		_write_node_movement(actor, process_frame, false)
		return
	movement.system_movement_active = true
	var pos: Vector3 = spatials[index].world_position
	var target_center: Vector3 = spatials[target_index].world_position
	var target_actor := _actor_from_node_component(nodes[target_index])
	var move_pos := _combat_move_position(actor, target_actor, target_center)
	movement.move_target_position = move_pos
	if action.action_active or action.reaction_remaining > 0.0 or absf(target_center.y - pos.y) > cfg.move_target_vertical_tolerance:
		movement.desired_velocity = Vector3.ZERO
		_apply_node_position(actor, pos, Vector3.ZERO, target_center)
		_write_node_movement(actor, process_frame, true)
		return
	var target_offset := target_center - pos
	target_offset.y = 0.0
	var target_distance := target_offset.length()
	var desired_range := maxf(float(cfg.attack_range) + COMBAT_RANGE_HYSTERESIS, 0.1)
	if target_distance <= desired_range:
		movement.desired_velocity = Vector3.ZERO
		_apply_node_position(actor, pos, Vector3.ZERO, target_center)
		_write_node_movement(actor, process_frame, true)
		return
	var move_offset := move_pos - pos
	move_offset.y = 0.0
	var move_distance := move_offset.length()
	if move_distance <= ARRIVAL_DISTANCE:
		movement.desired_velocity = Vector3.ZERO
		_apply_node_position(actor, pos, Vector3.ZERO, target_center)
		_write_node_movement(actor, process_frame, true)
		return
	var direction := move_offset / maxf(move_distance, 0.001)
	var speed := maxf(float(cfg.move_speed), 0.0)
	var target_velocity := direction * speed
	var current_velocity: Vector3 = previous_velocity
	var next_velocity := current_velocity.lerp(target_velocity, minf(1.0, maxf(float(cfg.movement_acceleration), 0.0) * delta))
	var step := minf(next_velocity.length() * delta, maxf(0.0, move_distance - ARRIVAL_DISTANCE))
	var new_pos := pos + direction * step
	spatials[index].last_world_position = pos
	spatials[index].world_position = new_pos
	movement.desired_velocity = direction * (step / maxf(delta, 0.0001))
	_apply_node_position(actor, new_pos, movement.desired_velocity, target_center)
	_write_node_movement(actor, process_frame, true)


func _combat_move_position(actor: Node, target_actor: Node, target_center: Vector3) -> Vector3:
	if target_actor != null and target_actor.has_method("get_combat_move_position"):
		var move_position = target_actor.call("get_combat_move_position", actor)
		if move_position is Vector3:
			return move_position
	return target_center


func _apply_node_position(actor: Node, position: Vector3, desired_velocity: Vector3, look_target: Vector3) -> void:
	var actor_3d := actor as Node3D
	if actor_3d == null:
		return
	actor_3d.global_position = position
	if actor is CharacterBody3D:
		(actor as CharacterBody3D).velocity.x = desired_velocity.x
		(actor as CharacterBody3D).velocity.z = desired_velocity.z
	var look_position := look_target
	look_position.y = actor_3d.global_position.y
	if actor_3d.global_position.distance_squared_to(look_position) > 0.0001:
		actor_3d.look_at(look_position, Vector3.UP)


func _write_node_movement(actor: Node, process_frame: int, active: bool) -> void:
	var world_actor := actor as WorldActor
	if world_actor != null:
		world_actor.set_system_movement_bridge(process_frame, active)
		return
	actor.set("_system_movement_frame", process_frame)
	actor.set("_system_movement_active", active)


func _refresh_node_movement_bridges(process_frame: int, nodes: Array, movements: Array, count: int) -> void:
	for i in range(count):
		var actor := _actor_from_node_component(nodes[i])
		var movement = movements[i]
		if actor != null and movement != null:
			_write_node_movement(actor, process_frame, bool(movement.system_movement_active))


func _actor_from_node_component(node_component) -> Node:
	if node_component == null:
		return null
	var actor = node_component.get_actor() if node_component.has_method("get_actor") else node_component.actor
	return actor as Node if actor != null and is_instance_valid(actor) else null
