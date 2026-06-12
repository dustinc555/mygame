extends RefCounted

const COMBAT_ACTOR_GROUP := "combat_actor"
const CHARACTER_GROUP := "npc_character"
const APPROACH_SLOT_COUNT := 8
const DEFAULT_ACTIVE_ATTACK_SLOTS := 5
const WAIT_SLOT_COUNT := 16
const PRESSURE_SCORE_MULTIPLIER := 4.0
const CURRENT_TARGET_STICKINESS := 1.15
const RETARGET_SCORE_MARGIN := 1.25
const SLOT_RADIUS_PADDING := 0.12
const SLOT_MIN_RADIUS := 1.08
const WAIT_RING_EXTRA := 1.45
const TURN_RESERVATION_SECONDS := 0.65
const EXCHANGE_RECOVERY_SECONDS := 0.22
const MIN_EXCHANGE_LOCK_SECONDS := 0.35
const INITIATIVE_LOSS_CREDIT := 0.65
const INITIATIVE_MAX_CREDIT := 8.0
const SLOT_ROLE_NONE := 0
const SLOT_ROLE_ACTIVE := 1
const SLOT_ROLE_WAITING := 2

static var _participant_locks: Dictionary = {}
static var _turn_reservations: Dictionary = {}
static var _slots_by_defender: Dictionary = {}
static var _active_slots_by_defender: Dictionary = {}
static var _waiting_slots_by_defender: Dictionary = {}
static var _slot_dirty_by_defender: Dictionary = {}
static var _initiative_credit: Dictionary = {}
static var _combat_targets_by_actor: Dictionary = {}
static var _pressure_by_target: Dictionary = {}
static var _attackers_by_target: Dictionary = {}
static var _actor_radius_by_id: Dictionary = {}
static var _active_attack_slots_by_id: Dictionary = {}
static var total_pressure_updates := 0
static var total_target_score_calls := 0
static var total_target_score_usec := 0
static var total_target_decision_calls := 0
static var total_target_decision_usec := 0
static var total_crowd_retarget_attempts := 0
static var total_crowd_retarget_switches := 0
static var metrics_enabled := false
static var _last_prune_process_frame := -1
static var _last_prune_physics_frame := -1


static func choose_target(attacker, candidates: Array, scan_radius: float):
	var started_usec := Time.get_ticks_usec() if metrics_enabled else 0
	if metrics_enabled:
		total_target_decision_calls += 1
	_prune_expired_state()
	var best_target = null
	var best_score := INF
	for candidate in candidates:
		var score := get_target_score(attacker, candidate, scan_radius)
		if score < best_score:
			best_score = score
			best_target = candidate
	if metrics_enabled:
		total_target_decision_usec += Time.get_ticks_usec() - started_usec
	return best_target


static func should_switch_target(attacker, current_target, candidate, scan_radius: float) -> bool:
	var started_usec := Time.get_ticks_usec() if metrics_enabled else 0
	if metrics_enabled:
		total_target_decision_calls += 1
	if not _is_valid_combatant(candidate):
		if metrics_enabled:
			total_target_decision_usec += Time.get_ticks_usec() - started_usec
		return false
	if not _is_valid_combatant(current_target):
		if metrics_enabled:
			total_target_decision_usec += Time.get_ticks_usec() - started_usec
		return true
	var current_score := get_target_score(attacker, current_target, scan_radius)
	var candidate_score := get_target_score(attacker, candidate, scan_radius)
	var should_switch := candidate_score + _get_attack_range(attacker) * RETARGET_SCORE_MARGIN < current_score
	if metrics_enabled:
		total_target_decision_usec += Time.get_ticks_usec() - started_usec
	return should_switch


static func get_target_score(attacker, candidate, scan_radius: float) -> float:
	var started_usec := Time.get_ticks_usec() if metrics_enabled else 0
	if metrics_enabled:
		total_target_score_calls += 1
	if not _is_valid_combatant(attacker) or not _is_valid_combatant(candidate):
		if metrics_enabled:
			total_target_score_usec += Time.get_ticks_usec() - started_usec
		return INF
	var distance: float = attacker.global_position.distance_to(candidate.global_position)
	if distance > scan_radius:
		if metrics_enabled:
			total_target_score_usec += Time.get_ticks_usec() - started_usec
		return INF
	var attack_range := _get_attack_range(attacker)
	var pressure := get_pressure_on(candidate, attacker)
	var score: float = distance + float(pressure) * attack_range * PRESSURE_SCORE_MULTIPLIER
	if _get_current_combat_target(attacker) == candidate:
		score -= attack_range * CURRENT_TARGET_STICKINESS
	if _get_current_combat_target(candidate) == attacker:
		score -= attack_range * 0.45
	if metrics_enabled:
		total_target_score_usec += Time.get_ticks_usec() - started_usec
	return score


static func get_pressure_on(defender, excluding = null) -> int:
	if not _is_valid_combatant(defender):
		return 0
	var defender_id: int = defender.get_instance_id()
	var pressure := int(_pressure_by_target.get(defender_id, 0))
	if excluding != null and _is_valid_combatant(excluding):
		var excluding_id: int = excluding.get_instance_id()
		var attackers = _attackers_by_target.get(defender_id, {})
		if attackers is Dictionary and attackers.has(excluding_id):
			pressure -= 1
	return maxi(pressure, 0)


static func register_combat_target(attacker, target) -> void:
	if not _is_valid_combatant(attacker):
		return
	var attacker_id: int = attacker.get_instance_id()
	var previous_target_id := int(_combat_targets_by_actor.get(attacker_id, 0))
	var target_id: int = target.get_instance_id() if _is_valid_combatant(target) else 0
	if previous_target_id == target_id:
		return
	if previous_target_id != 0:
		_decrement_pressure(previous_target_id, attacker_id)
		_slot_dirty_by_defender[previous_target_id] = true
	if target_id == 0:
		_combat_targets_by_actor.erase(attacker_id)
	else:
		_combat_targets_by_actor[attacker_id] = target_id
		_increment_pressure(target_id, attacker_id)
		_slot_dirty_by_defender[target_id] = true
	total_pressure_updates += 1


static func clear_combat_target(attacker) -> void:
	if not _is_valid_combatant(attacker):
		return
	var attacker_id: int = attacker.get_instance_id()
	var previous_target_id := int(_combat_targets_by_actor.get(attacker_id, 0))
	if previous_target_id == 0:
		return
	_decrement_pressure(previous_target_id, attacker_id)
	_slot_dirty_by_defender[previous_target_id] = true
	_combat_targets_by_actor.erase(attacker_id)
	total_pressure_updates += 1


static func get_personal_space_distance(attacker, defender, padding: float = SLOT_RADIUS_PADDING) -> float:
	return _get_actor_radius(attacker) + _get_actor_radius(defender) + maxf(padding, 0.0)


static func get_radial_settle_position(attacker, defender, desired_range: float) -> Vector3:
	if not _is_valid_combatant(attacker) or not _is_valid_combatant(defender):
		return Vector3.ZERO
	var away: Vector3 = attacker.global_position - defender.global_position
	away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = -defender.transform.basis.z
		away.y = 0.0
	if away.length_squared() <= 0.0001:
		away = Vector3.RIGHT
	return defender.global_position + away.normalized() * maxf(desired_range, get_personal_space_distance(attacker, defender, 0.0))


static func get_combat_approach_position(defender, attacker, preferred_range: float) -> Vector3:
	return get_combat_slot_position(defender, attacker, preferred_range)


static func get_combat_slot_position(defender, attacker, preferred_range: float, wait_ring_extra: float = WAIT_RING_EXTRA) -> Vector3:
	if not _is_valid_combatant(defender):
		return Vector3.ZERO
	if not _is_valid_combatant(attacker):
		return defender.global_position
	_ensure_combat_slots(defender)
	var defender_id: int = defender.get_instance_id()
	var attacker_id: int = attacker.get_instance_id()
	var role := SLOT_ROLE_NONE
	var slot_count := APPROACH_SLOT_COUNT
	var slot_index := 0
	var active_slots = _active_slots_by_defender.get(defender_id, {})
	if active_slots is Dictionary and active_slots.has(attacker_id):
		role = SLOT_ROLE_ACTIVE
		slot_count = _get_active_attack_slots(defender)
		slot_index = int(active_slots[attacker_id])
	else:
		var waiting_slots = _waiting_slots_by_defender.get(defender_id, {})
		if waiting_slots is Dictionary and waiting_slots.has(attacker_id):
			role = SLOT_ROLE_WAITING
			slot_count = WAIT_SLOT_COUNT
			slot_index = int(waiting_slots[attacker_id])
		else:
			slot_index = _get_attacker_slot(defender, attacker)
	var angle := TAU * float(slot_index) / float(maxi(1, slot_count))
	var range_extra := wait_ring_extra if role == SLOT_ROLE_WAITING else 0.0
	var approach_radius := maxf(maxf(preferred_range - SLOT_RADIUS_PADDING + range_extra, get_personal_space_distance(attacker, defender, SLOT_RADIUS_PADDING) + range_extra), SLOT_MIN_RADIUS + range_extra)
	return defender.global_position + Vector3(cos(angle), 0.0, sin(angle)) * approach_radius


static func get_combat_slot_role(attacker, defender) -> int:
	if not _is_valid_combatant(attacker) or not _is_valid_combatant(defender):
		return SLOT_ROLE_NONE
	_ensure_combat_slots(defender)
	var defender_id: int = defender.get_instance_id()
	var attacker_id: int = attacker.get_instance_id()
	var active_slots = _active_slots_by_defender.get(defender_id, {})
	if active_slots is Dictionary and active_slots.has(attacker_id):
		return SLOT_ROLE_ACTIVE
	var waiting_slots = _waiting_slots_by_defender.get(defender_id, {})
	if waiting_slots is Dictionary and waiting_slots.has(attacker_id):
		return SLOT_ROLE_WAITING
	return SLOT_ROLE_NONE


static func is_active_attack_slot(attacker, defender) -> bool:
	return get_combat_slot_role(attacker, defender) == SLOT_ROLE_ACTIVE


static func get_active_attack_slot_limit(defender) -> int:
	return _get_active_attack_slots(defender)


static func has_open_attack_slot(defender, excluding = null) -> bool:
	if not _is_valid_combatant(defender):
		return false
	_ensure_combat_slots(defender)
	var pressure := get_pressure_on(defender, excluding)
	return pressure < _get_active_attack_slots(defender)


static func try_begin_exchange(attacker, defender, action_seconds: float) -> bool:
	_prune_expired_state()
	if not _is_valid_combatant(attacker) or not _is_valid_combatant(defender):
		return false
	if is_character_locked(attacker):
		return false
	_lock_exchange(attacker, defender, action_seconds)
	return true


static func choose_initiative_winner_for_validation(contestants: Array):
	return _choose_initiative_winner(contestants)


static func is_character_locked(character) -> bool:
	if not _is_valid_combatant(character):
		return false
	var character_id: int = character.get_instance_id()
	var lock_until := float(_participant_locks.get(character_id, 0.0))
	if lock_until <= _now_seconds():
		_participant_locks.erase(character_id)
		return false
	return true


static func extend_character_lock(character, seconds: float) -> void:
	if not _is_valid_combatant(character):
		return
	_prune_expired_state()
	var character_id: int = character.get_instance_id()
	var lock_until := _now_seconds() + maxf(seconds, 0.0)
	_participant_locks[character_id] = maxf(float(_participant_locks.get(character_id, 0.0)), lock_until)


static func release_character(character) -> void:
	if character == null:
		return
	var character_id: int = character.get_instance_id()
	clear_combat_target(character)
	_pressure_by_target.erase(character_id)
	_attackers_by_target.erase(character_id)
	for attacker_id in _combat_targets_by_actor.keys():
		if int(_combat_targets_by_actor.get(attacker_id, 0)) == character_id:
			_combat_targets_by_actor.erase(attacker_id)
	_participant_locks.erase(character_id)
	_initiative_credit.erase(character_id)
	_clear_reservations_involving(character_id)
	_slots_by_defender.erase(character_id)
	_active_slots_by_defender.erase(character_id)
	_waiting_slots_by_defender.erase(character_id)
	_slot_dirty_by_defender.erase(character_id)
	_actor_radius_by_id.erase(character_id)
	_active_attack_slots_by_id.erase(character_id)
	for defender_id in _slots_by_defender.keys():
		var slots = _slots_by_defender.get(defender_id, {})
		if slots is Dictionary:
			slots.erase(character_id)
	for defender_id in _active_slots_by_defender.keys():
		var active_slots = _active_slots_by_defender.get(defender_id, {})
		if active_slots is Dictionary:
			active_slots.erase(character_id)
	for defender_id in _waiting_slots_by_defender.keys():
		var waiting_slots = _waiting_slots_by_defender.get(defender_id, {})
		if waiting_slots is Dictionary:
			waiting_slots.erase(character_id)


static func record_crowd_retarget_attempt(switched: bool) -> void:
	total_crowd_retarget_attempts += 1
	if switched:
		total_crowd_retarget_switches += 1


static func set_metrics_enabled(enabled: bool) -> void:
	metrics_enabled = enabled


static func get_metrics() -> Dictionary:
	return {
		"pressure_updates": total_pressure_updates,
		"target_score_calls": total_target_score_calls,
		"target_score_usec": total_target_score_usec,
		"target_decision_calls": total_target_decision_calls,
		"target_decision_usec": total_target_decision_usec,
		"crowd_retarget_attempts": total_crowd_retarget_attempts,
		"crowd_retarget_switches": total_crowd_retarget_switches,
	}


static func reset_metrics() -> void:
	total_pressure_updates = 0
	total_target_score_calls = 0
	total_target_score_usec = 0
	total_target_decision_calls = 0
	total_target_decision_usec = 0
	total_crowd_retarget_attempts = 0
	total_crowd_retarget_switches = 0


static func reset_all_state() -> void:
	_participant_locks.clear()
	_turn_reservations.clear()
	_slots_by_defender.clear()
	_active_slots_by_defender.clear()
	_waiting_slots_by_defender.clear()
	_slot_dirty_by_defender.clear()
	_initiative_credit.clear()
	_combat_targets_by_actor.clear()
	_pressure_by_target.clear()
	_attackers_by_target.clear()
	_actor_radius_by_id.clear()
	_active_attack_slots_by_id.clear()
	_last_prune_process_frame = -1
	_last_prune_physics_frame = -1
	reset_metrics()


static func _wins_pressure_contest(attacker) -> bool:
	var pressure_attackers := _get_ready_attackers_against(attacker)
	if pressure_attackers.is_empty():
		return true
	var contestants: Array = [attacker]
	contestants.append_array(pressure_attackers)
	var winner = _choose_initiative_winner(contestants)
	if winner == attacker or winner == null:
		return true
	_reserve_turn(attacker, winner)
	return false


static func _get_ready_attackers_against(defender) -> Array:
	var result: Array = []
	if not _is_valid_combatant(defender):
		return result
	var defender_id: int = defender.get_instance_id()
	var attacker_ids = _attackers_by_target.get(defender_id, {})
	if not (attacker_ids is Dictionary):
		return result
	for attacker_id_value in attacker_ids.keys():
		var attacker_id := int(attacker_id_value)
		var node = instance_from_id(attacker_id)
		if node == defender:
			continue
		if not _is_valid_combatant(node):
			_decrement_pressure(defender_id, attacker_id)
			continue
		var attacker_actor := node as WorldActor
		if attacker_actor == null:
			if _get_current_combat_target(node) != defender:
				continue
		elif attacker_actor.get_shared_combat_target() != defender:
			continue
		if is_character_locked(node):
			continue
		if attacker_actor != null and attacker_actor.is_ranged_combatant():
			continue
		if attacker_actor == null and _is_ranged_combatant(node):
			continue
		if attacker_actor != null and attacker_actor.is_ready_for_combat_exchange(defender):
			result.append(node)
		elif attacker_actor == null and _is_ready_for_combat_exchange(node, defender):
			result.append(node)
	return result


static func _choose_initiative_winner(contestants: Array):
	if contestants.is_empty():
		return null
	var weights: Array[Dictionary] = []
	var total_weight := 0.0
	for contestant in contestants:
		if not _is_valid_combatant(contestant):
			continue
		var character_id: int = contestant.get_instance_id()
		var dexterity := _get_initiative_dexterity(contestant)
		var credit := clampf(float(_initiative_credit.get(character_id, 0.0)), 0.0, maxf(INITIATIVE_MAX_CREDIT, dexterity * 2.0))
		var weight := maxf(0.01, dexterity + credit)
		weights.append({"character": contestant, "weight": weight, "dexterity": dexterity})
		total_weight += weight
	if weights.is_empty() or total_weight <= 0.0:
		return null
	var roll := randf() * total_weight
	var cumulative := 0.0
	var winner = weights[weights.size() - 1]["character"]
	for entry in weights:
		cumulative += float(entry["weight"])
		if roll <= cumulative:
			winner = entry["character"]
			break
	_update_initiative_credit(weights, winner)
	return winner


static func _update_initiative_credit(weights: Array[Dictionary], winner) -> void:
	for entry in weights:
		var character = entry["character"]
		if not _is_valid_combatant(character):
			continue
		var character_id: int = character.get_instance_id()
		if character == winner:
			_initiative_credit[character_id] = 0.0
			continue
		var dexterity := float(entry.get("dexterity", 1.0))
		var current_credit := float(_initiative_credit.get(character_id, 0.0))
		_initiative_credit[character_id] = minf(current_credit + INITIATIVE_LOSS_CREDIT, maxf(INITIATIVE_MAX_CREDIT, dexterity * 2.0))


static func _get_initiative_dexterity(character) -> float:
	var dexterity := 1.0
	if character is WorldActor:
		dexterity = float((character as WorldActor).get_stat_value("dexterity"))
	elif character != null and character.has_method("get_stat_value"):
		dexterity = float(character.get_stat_value("dexterity"))
	return maxf(dexterity, 0.01)


static func _reserve_turn(defender, attacker) -> void:
	if not _is_valid_combatant(defender) or not _is_valid_combatant(attacker):
		return
	_turn_reservations[defender.get_instance_id()] = {
		"attacker_id": attacker.get_instance_id(),
		"expires": _now_seconds() + TURN_RESERVATION_SECONDS,
	}


static func _consume_matching_reservation(defender, attacker) -> bool:
	var defender_id: int = defender.get_instance_id()
	var reservation = _turn_reservations.get(defender_id)
	if not (reservation is Dictionary):
		return false
	if int(reservation.get("attacker_id", 0)) != attacker.get_instance_id():
		return false
	_turn_reservations.erase(defender_id)
	return true


static func _has_ready_reservation_for_other_attacker(defender, attacker) -> bool:
	var defender_id: int = defender.get_instance_id()
	var reservation = _turn_reservations.get(defender_id)
	if not (reservation is Dictionary):
		return false
	var reserved_attacker_id := int(reservation.get("attacker_id", 0))
	if reserved_attacker_id == attacker.get_instance_id():
		return false
	var reserved_attacker = instance_from_id(reserved_attacker_id)
	if reserved_attacker is WorldActor and (reserved_attacker as WorldActor).is_ready_for_combat_exchange(defender):
		return true
	if _is_valid_combatant(reserved_attacker) and _is_ready_for_combat_exchange(reserved_attacker, defender):
		return true
	_turn_reservations.erase(defender_id)
	return false


static func _lock_exchange(attacker, _defender, action_seconds: float) -> void:
	var lock_until := _now_seconds() + maxf(action_seconds + EXCHANGE_RECOVERY_SECONDS, MIN_EXCHANGE_LOCK_SECONDS)
	_participant_locks[attacker.get_instance_id()] = lock_until
	_clear_reservations_involving(attacker.get_instance_id())


static func _ensure_combat_slots(defender) -> void:
	if not _is_valid_combatant(defender):
		return
	var defender_id: int = defender.get_instance_id()
	var has_cached_slots := _active_slots_by_defender.has(defender_id) or _waiting_slots_by_defender.has(defender_id)
	if has_cached_slots and not bool(_slot_dirty_by_defender.get(defender_id, false)):
		return
	var active_slots = _active_slots_by_defender.get(defender_id, {})
	if not (active_slots is Dictionary):
		active_slots = {}
	var waiting_slots = _waiting_slots_by_defender.get(defender_id, {})
	if not (waiting_slots is Dictionary):
		waiting_slots = {}
	_prune_combat_slot_map(defender, active_slots)
	_prune_combat_slot_map(defender, waiting_slots)
	var active_limit := _get_active_attack_slots(defender)
	for attacker_id_value in active_slots.keys():
		if int(active_slots[attacker_id_value]) >= active_limit:
			active_slots.erase(attacker_id_value)
	var attacker_ids := _get_current_attacker_ids(defender)
	var active_candidates := _ordered_slot_candidates(attacker_ids, active_slots, waiting_slots, true)
	for attacker_id_value in active_candidates:
		if active_slots.size() >= active_limit:
			break
		var attacker = instance_from_id(int(attacker_id_value))
		if not _is_valid_combatant(attacker):
			continue
		var desired_slot := _slot_index_for_direction_count(defender, attacker, active_limit)
		active_slots[int(attacker_id_value)] = _nearest_free_slot_for_count(active_slots, desired_slot, active_limit)
		waiting_slots.erase(attacker_id_value)
	for attacker_id_value in attacker_ids:
		var attacker_id := int(attacker_id_value)
		if active_slots.has(attacker_id) or waiting_slots.has(attacker_id):
			continue
		var attacker = instance_from_id(attacker_id)
		if not _is_valid_combatant(attacker):
			continue
		var desired_wait_slot := _slot_index_for_direction_count(defender, attacker, WAIT_SLOT_COUNT)
		waiting_slots[attacker_id] = _nearest_free_slot_for_count(waiting_slots, desired_wait_slot, WAIT_SLOT_COUNT)
	_active_slots_by_defender[defender_id] = active_slots
	_waiting_slots_by_defender[defender_id] = waiting_slots
	_slot_dirty_by_defender.erase(defender_id)


static func _get_current_attacker_ids(defender) -> Array:
	var result: Array = []
	if not _is_valid_combatant(defender):
		return result
	var defender_id: int = defender.get_instance_id()
	var attacker_ids = _attackers_by_target.get(defender_id, {})
	if not (attacker_ids is Dictionary):
		return result
	for attacker_id_value in attacker_ids.keys():
		var attacker_id := int(attacker_id_value)
		var attacker = instance_from_id(attacker_id)
		if not _is_valid_combatant(attacker):
			_decrement_pressure(defender_id, attacker_id)
			continue
		if not _attacker_targets_defender(attacker, attacker_id, defender):
			continue
		result.append(attacker_id)
	result.sort()
	return result


static func _ordered_slot_candidates(attacker_ids: Array, active_slots: Dictionary, waiting_slots: Dictionary, waiting_first: bool) -> Array:
	var result: Array = []
	if waiting_first:
		for attacker_id_value in attacker_ids:
			var attacker_id := int(attacker_id_value)
			if waiting_slots.has(attacker_id) and not active_slots.has(attacker_id):
				result.append(attacker_id)
	for attacker_id_value in attacker_ids:
		var attacker_id := int(attacker_id_value)
		if active_slots.has(attacker_id) or result.has(attacker_id):
			continue
		result.append(attacker_id)
	return result


static func _prune_combat_slot_map(defender, slots: Dictionary) -> void:
	for attacker_id in slots.keys():
		var attacker = instance_from_id(int(attacker_id))
		if not _is_valid_combatant(attacker):
			slots.erase(attacker_id)
			continue
		if not _attacker_targets_defender(attacker, int(attacker_id), defender):
			slots.erase(attacker_id)


static func _attacker_targets_defender(attacker, attacker_id: int, defender) -> bool:
	if not _is_valid_combatant(attacker) or not _is_valid_combatant(defender):
		return false
	if int(_combat_targets_by_actor.get(attacker_id, 0)) == defender.get_instance_id():
		return true
	return _get_current_combat_target(attacker) == defender


static func _get_current_combat_target(actor):
	if actor is WorldActor:
		return (actor as WorldActor).get_shared_combat_target()
	if actor != null and actor.has_method("get_current_combat_target"):
		return actor.get_current_combat_target()
	return null


static func _is_ready_for_combat_exchange(actor, defender) -> bool:
	return actor != null and actor.has_method("is_ready_for_combat_exchange") and actor.is_ready_for_combat_exchange(defender)


static func _is_ranged_combatant(actor) -> bool:
	return actor != null and actor.has_method("is_ranged_combatant") and actor.is_ranged_combatant()


static func _get_attacker_slot(defender, attacker) -> int:
	var defender_id: int = defender.get_instance_id()
	var attacker_id: int = attacker.get_instance_id()
	var slots = _slots_by_defender.get(defender_id, {})
	if not (slots is Dictionary):
		slots = {}
	_prune_slots(defender, slots)
	if slots.has(attacker_id):
		return int(slots[attacker_id])
	var desired_slot := _slot_index_for_direction_count(defender, attacker, APPROACH_SLOT_COUNT)
	var slot_index := _nearest_free_slot_for_count(slots, desired_slot, APPROACH_SLOT_COUNT)
	slots[attacker_id] = slot_index
	_slots_by_defender[defender_id] = slots
	return slot_index


static func _slot_index_for_direction_count(defender, attacker, slot_count: int) -> int:
	slot_count = maxi(1, slot_count)
	var direction: Vector3 = attacker.global_position - defender.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		var slot_seed := float(attacker.get_instance_id() % slot_count) / float(slot_count)
		return int(slot_seed * slot_count) % slot_count
	var angle := atan2(direction.z, direction.x)
	if angle < 0.0:
		angle += TAU
	return int(round(angle / TAU * float(slot_count))) % slot_count


static func _nearest_free_slot_for_count(slots: Dictionary, desired_slot: int, slot_count: int) -> int:
	slot_count = maxi(1, slot_count)
	var used_slots := slots.values()
	if not used_slots.has(desired_slot):
		return desired_slot
	for offset in range(1, slot_count):
		var right_slot := (desired_slot + offset) % slot_count
		if not used_slots.has(right_slot):
			return right_slot
		var left_slot := (desired_slot - offset + slot_count) % slot_count
		if not used_slots.has(left_slot):
			return left_slot
	return desired_slot


static func _prune_slots(defender, slots: Dictionary) -> void:
	for attacker_id in slots.keys():
		var attacker = instance_from_id(int(attacker_id))
		if not _is_valid_combatant(attacker):
			slots.erase(attacker_id)
			continue
		if not _attacker_targets_defender(attacker, int(attacker_id), defender):
			slots.erase(attacker_id)


static func _clear_reservations_involving(character_id: int) -> void:
	for defender_id in _turn_reservations.keys():
		var reservation = _turn_reservations.get(defender_id)
		if int(defender_id) == character_id:
			_turn_reservations.erase(defender_id)
		elif reservation is Dictionary and int(reservation.get("attacker_id", 0)) == character_id:
			_turn_reservations.erase(defender_id)


static func _prune_expired_state() -> void:
	var process_frame := Engine.get_process_frames()
	var physics_frame := Engine.get_physics_frames()
	if _last_prune_process_frame == process_frame and _last_prune_physics_frame == physics_frame:
		return
	_last_prune_process_frame = process_frame
	_last_prune_physics_frame = physics_frame
	var now := _now_seconds()
	for character_id in _participant_locks.keys():
		if float(_participant_locks.get(character_id, 0.0)) <= now:
			_participant_locks.erase(character_id)
	for defender_id in _turn_reservations.keys():
		var reservation = _turn_reservations.get(defender_id)
		if not (reservation is Dictionary) or float(reservation.get("expires", 0.0)) <= now:
			_turn_reservations.erase(defender_id)


static func _is_valid_combatant(character) -> bool:
	return character != null and is_instance_valid(character) and character is Node3D


static func _get_attack_range(character) -> float:
	if character == null:
		return 1.0
	if character is WorldActor:
		return maxf(float((character as WorldActor).get_attack_range()), 1.0)
	if character.has_method("get_attack_range"):
		return maxf(float(character.get_attack_range()), 1.0)
	var attack_range_value = character.get("attack_range")
	if attack_range_value != null:
		return maxf(float(attack_range_value), 1.0)
	return 1.0


static func _get_active_attack_slots(defender) -> int:
	if defender == null:
		return DEFAULT_ACTIVE_ATTACK_SLOTS
	var defender_id: int = defender.get_instance_id()
	if _active_attack_slots_by_id.has(defender_id):
		return int(_active_attack_slots_by_id[defender_id])
	if defender is WorldActor:
		var actor_active_slots := maxi(1, int((defender as WorldActor).combat_active_attack_slots))
		_active_attack_slots_by_id[defender_id] = actor_active_slots
		return actor_active_slots
	var slot_value = defender.get("combat_active_attack_slots")
	if slot_value != null:
		var active_slots := maxi(1, int(slot_value))
		_active_attack_slots_by_id[defender_id] = active_slots
		return active_slots
	_active_attack_slots_by_id[defender_id] = DEFAULT_ACTIVE_ATTACK_SLOTS
	return DEFAULT_ACTIVE_ATTACK_SLOTS


static func _get_actor_radius(actor) -> float:
	if actor == null:
		return 0.45
	var actor_id: int = actor.get_instance_id()
	if _actor_radius_by_id.has(actor_id):
		return float(_actor_radius_by_id[actor_id])
	if actor is WorldActor:
		var actor_radius := maxf(float((actor as WorldActor).navigation_agent_radius), 0.05)
		_actor_radius_by_id[actor_id] = actor_radius
		return actor_radius
	var radius = actor.get("navigation_agent_radius")
	if radius != null:
		var clamped_radius := maxf(float(radius), 0.05)
		_actor_radius_by_id[actor_id] = clamped_radius
		return clamped_radius
	_actor_radius_by_id[actor_id] = 0.45
	return 0.45


static func _increment_pressure(target_id: int, attacker_id: int) -> void:
	var attackers = _attackers_by_target.get(target_id, {})
	if not (attackers is Dictionary):
		attackers = {}
	if attackers.has(attacker_id):
		return
	attackers[attacker_id] = true
	_attackers_by_target[target_id] = attackers
	_pressure_by_target[target_id] = int(_pressure_by_target.get(target_id, 0)) + 1


static func _decrement_pressure(target_id: int, attacker_id: int) -> void:
	var attackers = _attackers_by_target.get(target_id, {})
	if attackers is Dictionary and attackers.has(attacker_id):
		attackers.erase(attacker_id)
		if attackers.is_empty():
			_attackers_by_target.erase(target_id)
		else:
			_attackers_by_target[target_id] = attackers
	_pressure_by_target[target_id] = maxi(0, int(_pressure_by_target.get(target_id, 0)) - 1)
	if int(_pressure_by_target.get(target_id, 0)) <= 0:
		_pressure_by_target.erase(target_id)


static func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) * 0.001
