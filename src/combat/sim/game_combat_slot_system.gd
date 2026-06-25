extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatSlotSystem

const C_IDENTITY = preload("res://src/actors/sim/c_game_actor_identity.gd")
const C_SPATIAL = preload("res://src/actors/sim/c_game_actor_spatial.gd")
const C_VITALS = preload("res://src/actors/sim/c_game_actor_vitals.gd")
const C_CONFIG = preload("res://src/combat/sim/c_game_combat_config.gd")
const C_STATE = preload("res://src/combat/sim/c_game_combat_state.gd")
const C_SLOT = preload("res://src/combat/sim/c_game_combat_slot_state.gd")
const C_ACTION = preload("res://src/combat/sim/c_game_combat_action.gd")

const FIGHT_STATE_NONE := 0
const FIGHT_STATE_MOVE_TO_TARGET := 1
const FIGHT_STATE_SEEKING_SLOT := 2
const FIGHT_STATE_FIGHTING := 3
const FIGHT_STATE_WAITING := 4

const FIXED_SLOT_TICK_SECONDS := 0.1
const MAX_FIXED_STEPS_PER_FRAME := 3
const ENTER_RANGE_BUFFER := 0.12
const EXIT_RANGE_BUFFER := 0.48

var _fixed_accumulator := 0.0


func query() -> QueryBuilder:
	return q.with_all([C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_STATE, C_SLOT, C_ACTION]).iterate(
		[C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_STATE, C_SLOT, C_ACTION])


func process(_entities: Array, components: Array, delta: float) -> void:
	_fixed_accumulator = minf(_fixed_accumulator + maxf(delta, 0.0), FIXED_SLOT_TICK_SECONDS * float(MAX_FIXED_STEPS_PER_FRAME))
	var fixed_steps := 0
	while _fixed_accumulator >= FIXED_SLOT_TICK_SECONDS and fixed_steps < MAX_FIXED_STEPS_PER_FRAME:
		_process_pairs(components)
		_fixed_accumulator -= FIXED_SLOT_TICK_SECONDS
		fixed_steps += 1


func _process_pairs(components: Array) -> void:
	var identities: Array = components[0]
	var spatials: Array = components[1]
	var vitals: Array = components[2]
	var configs: Array = components[3]
	var states: Array = components[4]
	var slots: Array = components[5]
	var actions: Array = components[6]
	var count := identities.size()
	if count == 0:
		return
	var index_by_actor_id := {}
	for i in range(count):
		var identity = identities[i]
		if identity != null and not str(identity.actor_id).is_empty():
			index_by_actor_id[str(identity.actor_id)] = i

	for i in range(count):
		_validate_existing_state(i, identities, spatials, vitals, configs, states, slots, actions, index_by_actor_id)

	var active_counts_by_target := {}
	var occupied_slots_by_target := {}
	for i in range(count):
		var slot = slots[i]
		if slot == null or int(slot.slot_state) != FIGHT_STATE_FIGHTING:
			continue
		var target_id := str(slot.slot_target_actor_id)
		if target_id.is_empty():
			continue
		active_counts_by_target[target_id] = int(active_counts_by_target.get(target_id, 0)) + 1
		var occupied: Dictionary = occupied_slots_by_target.get(target_id, {})
		if int(slot.slot_index) >= 0:
			occupied[int(slot.slot_index)] = true
		occupied_slots_by_target[target_id] = occupied

	for i in range(count):
		_assign_or_update_state(i, identities, spatials, vitals, configs, states, slots, index_by_actor_id, active_counts_by_target, occupied_slots_by_target)


func _validate_existing_state(index: int, identities: Array, spatials: Array, vitals: Array, configs: Array, states: Array, slots: Array, _actions: Array, index_by_actor_id: Dictionary) -> void:
	var slot = slots[index]
	if slot == null or int(slot.slot_state) == FIGHT_STATE_NONE:
		return
	_tick_clock(slot)
	var actor_id := _actor_id_at(index, identities)
	var target_id := str(slot.slot_target_actor_id)
	var desired := _desired_target_actor_id(states[index])
	if actor_id.is_empty() or desired.is_empty() or desired == actor_id:
		slot.clear()
		return
	if target_id.is_empty() or target_id != desired or not index_by_actor_id.has(target_id):
		_set_move_to_target(slot, desired)
		return
	var target_index: int = index_by_actor_id[target_id]
	if not _can_use_pair(index, target_index, spatials, vitals, configs):
		slot.clear()
		return
	var actor_pos: Vector3 = spatials[index].world_position
	var target_pos: Vector3 = spatials[target_index].world_position
	_update_geometry_cache(slot, actor_pos, target_pos, configs[index], configs[target_index])
	var distance := _horizontal_distance(actor_pos, target_pos)
	if distance > _exit_range(configs[index], configs[target_index]):
		_set_move_to_target(slot, target_id)
		return
	if int(slot.slot_state) == FIGHT_STATE_MOVE_TO_TARGET and distance <= _enter_range(configs[index], configs[target_index]):
		_set_state(slot, FIGHT_STATE_SEEKING_SLOT)


func _assign_or_update_state(index: int, identities: Array, spatials: Array, vitals: Array, configs: Array, states: Array, slots: Array, index_by_actor_id: Dictionary, active_counts_by_target: Dictionary, occupied_slots_by_target: Dictionary) -> void:
	var slot = slots[index]
	if slot == null:
		return
	var actor_id := _actor_id_at(index, identities)
	var desired := _desired_target_actor_id(states[index])
	if actor_id.is_empty() or desired.is_empty() or desired == actor_id or not index_by_actor_id.has(desired):
		slot.clear()
		return
	var target_index: int = index_by_actor_id[desired]
	if not _can_use_pair(index, target_index, spatials, vitals, configs):
		slot.clear()
		return
	var actor_pos: Vector3 = spatials[index].world_position
	var target_pos: Vector3 = spatials[target_index].world_position
	_update_geometry_cache(slot, actor_pos, target_pos, configs[index], configs[target_index])
	var distance := _horizontal_distance(actor_pos, target_pos)
	if distance > _enter_range(configs[index], configs[target_index]):
		_set_move_to_target(slot, desired)
		return
	if int(slot.slot_state) == FIGHT_STATE_FIGHTING and str(slot.slot_target_actor_id) == desired:
		return
	_set_state(slot, FIGHT_STATE_SEEKING_SLOT)
	var target_cfg = configs[target_index]
	var target_slot_count := maxi(int(target_cfg.active_attack_slots), 1)
	var occupied: Dictionary = occupied_slots_by_target.get(desired, {})
	var active_count := int(active_counts_by_target.get(desired, 0))
	if active_count >= target_slot_count:
		_set_waiting(slot, desired)
		return
	var desired_slot := _slot_index_for_direction_count(actor_pos, target_pos, target_slot_count)
	var slot_index := _nearest_free_slot_for_count(occupied, desired_slot, target_slot_count)
	if slot_index < 0:
		_set_waiting(slot, desired)
		return
	slot.slot_target_actor_id = desired
	slot.slot_index = slot_index
	slot.wait_index = -1
	slot.slot_angle = _angle_for_slot_index(slot_index, target_slot_count)
	slot.pair_axis = _axis_for_angle(float(slot.slot_angle))
	# The turn token (tempo_*) is owned by the resolution system on a canonical per-pair slot;
	# do not seed it here, or each fighter's own slot ends up holding a separate, crossed token.
	_set_state(slot, FIGHT_STATE_FIGHTING)
	occupied[slot_index] = true
	occupied_slots_by_target[desired] = occupied
	active_counts_by_target[desired] = active_count + 1


func _set_move_to_target(slot, target_id: String) -> void:
	slot.slot_target_actor_id = target_id
	slot.slot_index = -1
	slot.wait_index = -1
	_set_state(slot, FIGHT_STATE_MOVE_TO_TARGET)


func _set_waiting(slot, target_id: String) -> void:
	slot.slot_target_actor_id = target_id
	slot.slot_index = -1
	_set_state(slot, FIGHT_STATE_WAITING)


func _tick_clock(slot) -> void:
	slot.state_seconds = maxf(0.0, float(slot.state_seconds) + FIXED_SLOT_TICK_SECONDS)
	# tempo_wait_remaining is owned and ticked by the resolution system (the shared turn token).


func _set_state(slot, next_state: int) -> void:
	if int(slot.slot_state) == next_state:
		return
	slot.slot_state = next_state
	slot.state_seconds = 0.0


func _update_geometry_cache(slot, actor_pos: Vector3, target_pos: Vector3, cfg, target_cfg) -> void:
	var direction := actor_pos - target_pos
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		slot.pair_axis = direction.normalized()
	var ideal := maxf(minf(float(cfg.attack_range), float(target_cfg.attack_range)), 0.55)
	slot.engage_distance = ideal
	slot.min_pair_distance = maxf(0.35, ideal - ENTER_RANGE_BUFFER)
	slot.max_pair_distance = _enter_range(cfg, target_cfg)
	slot.leash_distance = _exit_range(cfg, target_cfg)
	slot.slot_position = target_pos
	slot.wait_position = actor_pos
	slot.pair_anchor_position = (actor_pos + target_pos) * 0.5


func _enter_range(cfg, target_cfg) -> float:
	return maxf(minf(float(cfg.attack_range), float(target_cfg.attack_range)) + ENTER_RANGE_BUFFER, 0.55)


func _exit_range(cfg, target_cfg) -> float:
	return _enter_range(cfg, target_cfg) + EXIT_RANGE_BUFFER


func _can_use_pair(index: int, target_index: int, spatials: Array, vitals: Array, configs: Array) -> bool:
	var vit = vitals[index]
	var target_vit = vitals[target_index]
	var cfg = configs[index]
	var target_cfg = configs[target_index]
	if vit == null or target_vit == null or cfg == null or target_cfg == null:
		return false
	if vit.life_state != NpcRules.LifeState.ALIVE or target_vit.life_state != NpcRules.LifeState.ALIVE:
		return false
	if absf(spatials[index].world_position.y - spatials[target_index].world_position.y) > float(cfg.move_target_vertical_tolerance):
		return false
	return not bool(cfg.protected_from_combat) and not bool(target_cfg.protected_from_combat)


func _desired_target_actor_id(state) -> String:
	if state == null:
		return ""
	var system_target := str(state.system_target_actor_id)
	return system_target if not system_target.is_empty() else str(state.current_target_actor_id)


func _actor_id_at(index: int, identities: Array) -> String:
	var identity = identities[index]
	return str(identity.actor_id) if identity != null else ""


func _slot_index_for_direction_count(actor_pos: Vector3, target_pos: Vector3, slot_count: int) -> int:
	slot_count = maxi(slot_count, 1)
	var direction := actor_pos - target_pos
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return 0
	var angle := atan2(direction.z, direction.x)
	if angle < 0.0:
		angle += TAU
	return int(round(angle / TAU * float(slot_count))) % slot_count


func _nearest_free_slot_for_count(occupied_slots: Dictionary, desired_slot: int, slot_count: int) -> int:
	slot_count = maxi(slot_count, 1)
	desired_slot = posmod(desired_slot, slot_count)
	if not bool(occupied_slots.get(desired_slot, false)):
		return desired_slot
	for offset in range(1, slot_count):
		var right_slot := (desired_slot + offset) % slot_count
		if not bool(occupied_slots.get(right_slot, false)):
			return right_slot
		var left_slot := posmod(desired_slot - offset, slot_count)
		if not bool(occupied_slots.get(left_slot, false)):
			return left_slot
	return -1


func _angle_for_slot_index(slot_index: int, slot_count: int) -> float:
	return TAU * float(posmod(slot_index, maxi(slot_count, 1))) / float(maxi(slot_count, 1))


func _axis_for_angle(angle: float) -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle)).normalized()


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset := b - a
	offset.y = 0.0
	return offset.length()
