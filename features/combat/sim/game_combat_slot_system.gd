extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatSlotSystem

const C_IDENTITY = preload("res://features/actors/sim/c_game_actor_identity.gd")
const C_SPATIAL = preload("res://features/actors/sim/c_game_actor_spatial.gd")
const C_VITALS = preload("res://features/actors/sim/c_game_actor_vitals.gd")
const C_CONFIG = preload("res://features/combat/sim/c_game_combat_config.gd")
const C_STATE = preload("res://features/combat/sim/c_game_combat_state.gd")
const C_SLOT = preload("res://features/combat/sim/c_game_combat_slot_state.gd")
const C_ACTION = preload("res://features/combat/sim/c_game_combat_action.gd")
const C_NODE = preload("res://features/actors/bridge/c_game_actor_node.gd")
const COMBAT_NAVIGATION = preload("res://features/combat/bridge/combat_navigation.gd")

const FIGHT_STATE_NONE := 0
const FIGHT_STATE_MOVE_TO_TARGET := 1
const FIGHT_STATE_SEEKING_SLOT := 2
const FIGHT_STATE_FIGHTING := 3
const FIGHT_STATE_WAITING := 4

const FIXED_SLOT_TICK_SECONDS := 0.1
const MAX_FIXED_STEPS_PER_FRAME := 3
const ENTER_RANGE_BUFFER := 0.12
const EXIT_RANGE_BUFFER := 0.48
# Bounded tactical work, independent of per-frame navigation following.
const MAX_POSITION_QUERIES_PER_FRAME := 12
const POSITION_RECHECK_SECONDS := 0.65
const TARGET_REPOSITION_DISTANCE := 0.45
const POSITION_ARRIVAL_DISTANCE := 0.3
const PERSONAL_SPACE_PADDING := 0.05
const WAIT_RING_EXTRA := 1.1
const OCCUPANCY_CELL_SIZE := 3.0
const APPROACH_ANGLES := [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, 3.0 * PI / 4.0, -3.0 * PI / 4.0, PI]

var _fixed_accumulator := 0.0
var _position_queries_left := 0
var _decision_cursor := 0
var _position_requests: Dictionary = {}
var _navigation_owner: WeakRef



func query() -> QueryBuilder:
	return q.with_all([C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_STATE, C_SLOT, C_ACTION, C_NODE]).iterate(
		[C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_STATE, C_SLOT, C_ACTION, C_NODE])


func process(_entities: Array, components: Array, delta: float) -> void:
	for key in _position_requests.keys():
		var request: Dictionary = _position_requests[key]
		var actor = request.actor.get_ref()
		var target = request.target.get_ref()
		if not is_instance_valid(actor) or not is_instance_valid(target) or not actor.is_inside_tree() or not target.is_inside_tree() or actor.is_queued_for_deletion() or target.is_queued_for_deletion():
			_cancel_position_request(key)
	_position_queries_left = MAX_POSITION_QUERIES_PER_FRAME
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
	var nodes: Array = components[7]
	var count := identities.size()
	if count == 0:
		return
	var index_by_actor_id := {}
	for i in range(count):
		var identity = identities[i]
		if identity != null and not str(identity.actor_id).is_empty():
			index_by_actor_id[str(identity.actor_id)] = i

	var active_indices: Array[int] = []
	var active_counts := {}
	var occupancy := {}
	for i in range(count):
		var slot = slots[i]
		var desired := _desired_target_actor_id(states[i])
		var target_index := int(index_by_actor_id.get(desired, -1))
		if target_index < 0 or target_index == i or not _can_use_pair(i, target_index, spatials, vitals, configs) or _actor(nodes[i]) == null or _actor(nodes[target_index]) == null:
			var inactive_actor := _actor(nodes[i])
			if inactive_actor != null:
				_cancel_position_request(inactive_actor.get_instance_id())
			slot.clear()
			continue
		if str(slot.slot_target_actor_id) != desired:
			slot.clear()
			slot.slot_target_actor_id = desired
		_tick_clock(slot)
		slot.position_recheck_remaining = maxf(0.0, float(slot.position_recheck_remaining) - FIXED_SLOT_TICK_SECONDS)
		_update_geometry_cache(slot, spatials[i].world_position, spatials[target_index].world_position, configs[i], configs[target_index])
		var actor := _actor(nodes[i])
		var path_failed := actor != null and actor.has_method("has_combat_navigation_failed") and bool(actor.call("has_combat_navigation_failed"))
		if path_failed or (slot.position_valid and slot.position_target_origin.distance_to(spatials[target_index].world_position) > TARGET_REPOSITION_DISTANCE):
			slot.position_valid = false
			slot.position_recheck_remaining = 0.0
			if path_failed:
				slot.position_search_cursor = (int(slot.position_search_cursor) + 1) % APPROACH_ANGLES.size()
		if slot.position_valid and int(slot.slot_index) >= 0:
			active_counts[desired] = int(active_counts.get(desired, 0)) + 1
		active_indices.append(i)
	# One local spatial index for actual settled bodies and reserved destinations.
	# Approaching actors yield locally through RVO; they must not evict a front
	# fighter merely because they arrived already overlapping it.
	for i in range(count):
		if vitals[i].life_state != NpcRules.LifeState.ALIVE or _actor(nodes[i]) == null:
			continue
		var slot = slots[i]
		if _desired_target_actor_id(states[i]).is_empty() or int(slot.slot_state) == FIGHT_STATE_FIGHTING:
			_add_occupant(occupancy, i, spatials[i].world_position, false)
		if slot.position_valid:
			_add_occupant(occupancy, i, slot.slot_position, true)
	# Preserve settled assignments; among new arrivals, give the near fighter
	# first choice so the rear one goes around instead of displacing the front.
	active_indices.sort_custom(func(a: int, b: int) -> bool:
		var ta: int = index_by_actor_id[str(slots[a].slot_target_actor_id)]
		var tb: int = index_by_actor_id[str(slots[b].slot_target_actor_id)]
		return spatials[a].world_position.distance_squared_to(spatials[ta].world_position) < spatials[b].world_position.distance_squared_to(spatials[tb].world_position)
	)
	if active_indices.is_empty():
		return
	var start := _decision_cursor % active_indices.size()
	for offset in active_indices.size():
		var ordinal := (start + offset) % active_indices.size()
		var i := active_indices[ordinal]
		var slot = slots[i]
		var target_index: int = index_by_actor_id[str(slot.slot_target_actor_id)]
		var wants_active: bool = (slot.position_valid and int(slot.slot_index) >= 0) or int(active_counts.get(str(slot.slot_target_actor_id), 0)) < maxi(1, int(configs[target_index].active_attack_slots))
		# WARNING [ANTI-ORBIT]: settle on entering a valid stance, within the query budget.
		# Waiting for the periodic recheck lets moving duelists pass and chase again.
		var can_settle_now: bool = wants_active and _can_hold_stance(i, target_index, spatials, configs, slots) and (not slot.position_valid or _horizontal_distance(spatials[i].world_position, slot.slot_position) > WorldActor.COMBAT_ARRIVAL_DISTANCE) and _position_is_free(i, spatials[i].world_position, configs, slots, occupancy)
		if (slot.position_recheck_remaining <= 0.0 or can_settle_now) and _position_queries_left > 0 and not actions[i].action_active:
			var had_active: bool = slot.position_valid and int(slot.slot_index) >= 0
			if had_active:
				active_counts[str(slot.slot_target_actor_id)] = int(active_counts.get(str(slot.slot_target_actor_id), 0)) - 1
			var completed := _choose_position(i, target_index, wants_active, nodes, spatials, configs, slots, occupancy)
			if completed and wants_active and not slot.position_valid and _position_queries_left > 0:
				_choose_position(i, target_index, false, nodes, spatials, configs, slots, occupancy)
			if slot.position_valid and int(slot.slot_index) >= 0:
				active_counts[str(slot.slot_target_actor_id)] = int(active_counts.get(str(slot.slot_target_actor_id), 0)) + 1
			_decision_cursor = (ordinal + 1) % active_indices.size()
		_update_arrival(i, target_index, nodes, spatials, configs, slots)


func _choose_position(index: int, target_index: int, engaging: bool, nodes: Array, spatials: Array, configs: Array, slots: Array, occupancy: Dictionary) -> bool:
	var slot = slots[index]
	var actor := _actor(nodes[index])

	var target := _actor(nodes[target_index])
	var center: Vector3 = spatials[target_index].world_position
	var origin: Vector3 = spatials[index].world_position
	var offset := origin - center
	var base_angle := atan2(offset.z, offset.x)
	var radius := maxf(float(slot.engage_distance), float(configs[index].navigation_agent_radius) + float(configs[target_index].navigation_agent_radius) + PERSONAL_SPACE_PADDING)
	if not engaging:
		radius += WAIT_RING_EXTRA
	# WARNING [ANTI-ORBIT]: prefer a valid current stance, then the retained world point.
	# Finishing an obsolete flank can sustain mutual circling instead of fighting.
	# It must pass the same occupancy, standing and strike checks as any point;
	# an overlapping rear attacker cannot use this to avoid going around.
	var candidates: Array[Vector3] = []
	# Already standing here: validate physical support/clearance now instead of
	# waiting for a travel batch that becomes obsolete as both fighters move.
	if engaging and _can_hold_stance(index, target_index, spatials, configs, slots) and _position_is_free(index, origin, configs, slots, occupancy):
		_position_queries_left -= 1
		var current := _resolve_position(actor, target, origin, true)
		if current.is_finite():
			_cancel_position_request(actor.get_instance_id())
			_reserve_position(slot, current, center, 0, true)
			_add_occupant(occupancy, index, current, true)
			return true
	candidates.append(Vector3.INF)
	# Otherwise keep the existing world point before seeking a new approach.
	if slot.position_valid and engaging == (int(slot.slot_index) >= 0):
		candidates.append(slot.slot_position)
	else:
		candidates.append(Vector3.INF)
	for step in APPROACH_ANGLES.size():
		var angle := base_angle + float(APPROACH_ANGLES[(step + int(slot.position_search_cursor)) % APPROACH_ANGLES.size()])
		candidates.append(center + Vector3(cos(angle), 0.0, sin(angle)) * radius)
	var route_batch := _candidate_paths(actor, target, candidates, engaging, float(configs[index].move_target_vertical_tolerance))
	if route_batch.get("pending", false):
		# Keep an existing reservation while its replacement is being searched.
		# A pending active search is not a failure requiring a waiting-ring search.
		return false
	if route_batch.has("candidates"):
		candidates = route_batch.candidates
	slot.position_valid = false
	for candidate_index in candidates.size():
		var candidate := candidates[candidate_index]
		if not candidate.is_finite() or not _position_is_free(index, candidate, configs, slots, occupancy):
			continue
		if _position_queries_left <= 0:
			break
		_position_queries_left -= 1
		var resolved := COMBAT_NAVIGATION.accept_path(actor, target, candidate, route_batch.paths[candidate_index], engaging) if route_batch.has("paths") else _resolve_position(actor, target, candidate, engaging)

		if not resolved.is_finite() or not _position_is_free(index, resolved, configs, slots, occupancy):
			continue
		if engaging and _horizontal_distance(resolved, center) > _enter_range(configs[index], configs[target_index]) - WorldActor.COMBAT_ARRIVAL_DISTANCE:
			continue
		_reserve_position(slot, resolved, center, candidate_index, engaging)
		_add_occupant(occupancy, index, resolved, true)
		return true
	slot.slot_index = -1
	slot.position_search_cursor = (int(slot.position_search_cursor) + 1) % APPROACH_ANGLES.size()
	slot.position_recheck_remaining = POSITION_RECHECK_SECONDS
	return true


func _reserve_position(slot, position: Vector3, center: Vector3, candidate_index: int, engaging: bool) -> void:
	slot.position_valid = true
	slot.slot_position = position
	slot.wait_position = position
	slot.position_target_origin = center
	var direction := position - center
	direction.y = 0.0
	slot.pair_axis = direction.normalized()
	slot.slot_angle = atan2(direction.z, direction.x)
	if candidate_index >= 2:
		var chosen_index := (candidate_index - 2 + int(slot.position_search_cursor)) % APPROACH_ANGLES.size()
		slot.slot_index = chosen_index if engaging else -1
		slot.wait_index = -1 if engaging else chosen_index
	elif candidate_index == 0:
		slot.slot_index = maxi(0, int(slot.slot_index))
		slot.wait_index = -1
	# WARNING [ANTI-ORBIT]: retain the WORLD POINT, not a rotating flank angle.
	slot.position_search_cursor = 0
	slot.position_recheck_remaining = POSITION_RECHECK_SECONDS


func _candidate_paths(actor: Node3D, target: Node3D, candidates: Array[Vector3], engaging: bool, vertical_tolerance: float) -> Dictionary:
	var key := actor.get_instance_id()
	var owner = _navigation_owner.get_ref() if _navigation_owner != null else null
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		owner = actor.get_tree().get_first_node_in_group("world_navigation_controller")
		_navigation_owner = weakref(owner) if owner != null else null
	var map := actor.get_world_3d().navigation_map
	if owner == null or not owner.supports_threaded_queries(map):
		_cancel_position_request(key)
		return {"candidates": _ground_candidates(actor, candidates, vertical_tolerance)}
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	if iteration == 0:
		_cancel_position_request(key)
		return {"pending": true}
	var request: Dictionary = _position_requests.get(key, {})
	# Moving within the same pursuit must not cancel even completed work. Every
	# result still passes current range, standing, occupancy and strike checks.
	if not request.is_empty() and (request.target.get_ref() != target or request.map != map or request.iteration != iteration or request.engaging != engaging):
		_cancel_position_request(key)
		request = {}
	if request.is_empty():
		# Ground once per submitted batch, never again while waiting for workers.
		candidates = _ground_candidates(actor, candidates, vertical_tolerance)
		var origin_offset := COMBAT_NAVIGATION.floor_origin_offset(actor)
		var floors := PackedVector3Array()
		for candidate in candidates:
			# Disabled preference entries retain their indices without sending INF
			# to native navigation. Their results are never considered for a slot.
			floors.append(candidate - origin_offset if candidate.is_finite() else actor.global_position - origin_offset)
		var ticket: int = owner.request_paths("combat:%d" % key, actor.get_world_3d(), map, actor.global_position - origin_offset, floors)
		if ticket > 0:
			_position_requests[key] = {"jobs": owner.query_jobs, "ticket": ticket, "actor": weakref(actor), "target": weakref(target), "map": map, "iteration": iteration, "origin": actor.global_position, "center": target.global_position, "engaging": engaging, "candidates": candidates}
		return {"pending": true}
	var result: Dictionary = request.jobs.take("combat:%d" % key, request.ticket)
	if result.is_empty():
		return {"pending": true}
	_position_requests.erase(key)
	if result.map != map or result.iteration != iteration:
		return {"pending": true}
	return {"candidates": request.candidates, "paths": result.paths}


func _ground_candidates(actor: Node3D, candidates: Array[Vector3], vertical_tolerance: float) -> Array[Vector3]:
	# Current stance and retained reservation are already exact origins. Only
	# the new ring hints inherit target Y and need local physical grounding.
	for index in range(2, candidates.size()):
		candidates[index] = COMBAT_NAVIGATION.ground_position_hint(actor, candidates[index], vertical_tolerance)
	return candidates


func _cancel_position_request(key: int) -> void:
	if _position_requests.has(key):
		_position_requests[key].jobs.cancel("combat:%d" % key)
		_position_requests.erase(key)


func _exit_tree() -> void:
	for key in _position_requests.keys():
		_cancel_position_request(key)


func _can_hold_stance(index: int, target_index: int, spatials: Array, configs: Array, slots: Array) -> bool:
	var origin: Vector3 = spatials[index].world_position
	var center: Vector3 = spatials[target_index].world_position
	var distance := _horizontal_distance(origin, center)
	var clearance := float(configs[index].navigation_agent_radius) + float(configs[target_index].navigation_agent_radius) + PERSONAL_SPACE_PADDING
	return distance >= maxf(float(slots[index].min_pair_distance), clearance) and distance <= _enter_range(configs[index], configs[target_index]) - WorldActor.COMBAT_ARRIVAL_DISTANCE and absf(origin.y - center.y) <= float(configs[index].move_target_vertical_tolerance)


func _update_arrival(index: int, target_index: int, nodes: Array, spatials: Array, configs: Array, slots: Array) -> void:
	var slot = slots[index]
	if not slot.position_valid:
		_set_state(slot, FIGHT_STATE_MOVE_TO_TARGET)
		return
	if int(slot.slot_index) < 0:
		_set_state(slot, FIGHT_STATE_WAITING)
		return
	var origin: Vector3 = spatials[index].world_position
	var target_position: Vector3 = spatials[target_index].world_position
	var arrived := _horizontal_distance(origin, slot.slot_position) <= POSITION_ARRIVAL_DISTANCE and absf(origin.y - target_position.y) <= float(configs[index].move_target_vertical_tolerance)
	var in_range := _horizontal_distance(origin, target_position) <= _enter_range(configs[index], configs[target_index])
	_set_state(slot, FIGHT_STATE_FIGHTING if arrived and in_range and _can_strike(_actor(nodes[index]), _actor(nodes[target_index])) else FIGHT_STATE_SEEKING_SLOT)


func _add_occupant(occupancy: Dictionary, index: int, position: Vector3, reserved: bool) -> void:
	var cell := Vector2i(floori(position.x / OCCUPANCY_CELL_SIZE), floori(position.z / OCCUPANCY_CELL_SIZE))
	if not occupancy.has(cell):
		occupancy[cell] = []
	occupancy[cell].append({"index": index, "position": position, "reserved": reserved})


func _position_is_free(index: int, position: Vector3, configs: Array, slots: Array, occupancy: Dictionary) -> bool:
	var cell := Vector2i(floori(position.x / OCCUPANCY_CELL_SIZE), floori(position.z / OCCUPANCY_CELL_SIZE))
	for x in range(cell.x - 1, cell.x + 2):
		for z in range(cell.y - 1, cell.y + 2):
			for entry in occupancy.get(Vector2i(x, z), []):
				var other := int(entry.index)
				if other == index or absf(position.y - (entry.position as Vector3).y) > float(configs[index].move_target_vertical_tolerance):
					continue
				if entry.reserved and (not slots[other].position_valid or slots[other].slot_position != entry.position):
					continue
				var clearance := float(configs[index].navigation_agent_radius) + float(configs[other].navigation_agent_radius) + PERSONAL_SPACE_PADDING
				if _horizontal_distance(position, entry.position) < clearance:
					return false
	return true


func _actor(component) -> Node3D:
	var actor: Node = component.get_actor() if component != null else null
	return actor as Node3D if actor != null and actor.is_inside_tree() and not actor.is_queued_for_deletion() else null


func _resolve_position(actor: Node3D, target: Node3D, candidate: Vector3, require_strike: bool) -> Vector3:
	return COMBAT_NAVIGATION.find_reachable_position(actor, target, candidate, require_strike)


func _can_strike(actor: Node3D, target: Node3D) -> bool:
	return COMBAT_NAVIGATION.can_strike(actor, target)


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
	if not slot.position_valid and direction.length_squared() > 0.0001:
		slot.pair_axis = direction.normalized()
	var ideal := maxf(minf(float(cfg.attack_range), float(target_cfg.attack_range)), 0.55)
	slot.engage_distance = ideal
	slot.min_pair_distance = maxf(0.35, ideal - ENTER_RANGE_BUFFER)
	slot.max_pair_distance = _enter_range(cfg, target_cfg)
	slot.leash_distance = _exit_range(cfg, target_cfg)
	slot.pair_anchor_position = (actor_pos + target_pos) * 0.5


func _enter_range(cfg, target_cfg) -> float:
	return maxf(minf(float(cfg.attack_range), float(target_cfg.attack_range)) + ENTER_RANGE_BUFFER, 0.55)


func _exit_range(cfg, target_cfg) -> float:
	return _enter_range(cfg, target_cfg) + EXIT_RANGE_BUFFER


func _can_use_pair(index: int, target_index: int, _spatials: Array, vitals: Array, configs: Array) -> bool:
	var vit = vitals[index]
	var target_vit = vitals[target_index]
	var cfg = configs[index]
	var target_cfg = configs[target_index]
	if vit == null or target_vit == null or cfg == null or target_cfg == null:
		return false
	if vit.life_state != NpcRules.LifeState.ALIVE or target_vit.life_state != NpcRules.LifeState.ALIVE:
		return false
	# Vertical strike tolerance must not prevent navigation to another floor.
	return not bool(cfg.protected_from_combat) and not bool(target_cfg.protected_from_combat)


func _desired_target_actor_id(state) -> String:
	if state == null:
		return ""
	var system_target := str(state.system_target_actor_id)
	return system_target if not system_target.is_empty() else str(state.current_target_actor_id)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset := b - a
	offset.y = 0.0
	return offset.length()
