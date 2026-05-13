extends RefCounted

const CHARACTER_GROUP := "npc_character"
const APPROACH_SLOT_COUNT := 8
const PRESSURE_SCORE_MULTIPLIER := 2.75
const CURRENT_TARGET_STICKINESS := 1.15
const RETARGET_SCORE_MARGIN := 1.25
const TURN_RESERVATION_SECONDS := 0.65
const EXCHANGE_RECOVERY_SECONDS := 0.22
const MIN_EXCHANGE_LOCK_SECONDS := 0.35

static var _participant_locks: Dictionary = {}
static var _turn_reservations: Dictionary = {}
static var _slots_by_defender: Dictionary = {}


static func choose_target(attacker, candidates: Array, scan_radius: float):
	_prune_expired_state()
	var best_target = null
	var best_score := INF
	for candidate in candidates:
		var score := get_target_score(attacker, candidate, scan_radius)
		if score < best_score:
			best_score = score
			best_target = candidate
	return best_target


static func should_switch_target(attacker, current_target, candidate, scan_radius: float) -> bool:
	if not _is_valid_combatant(candidate):
		return false
	if not _is_valid_combatant(current_target):
		return true
	var current_score := get_target_score(attacker, current_target, scan_radius)
	var candidate_score := get_target_score(attacker, candidate, scan_radius)
	return candidate_score + _get_attack_range(attacker) * RETARGET_SCORE_MARGIN < current_score


static func get_target_score(attacker, candidate, scan_radius: float) -> float:
	if not _is_valid_combatant(attacker) or not _is_valid_combatant(candidate):
		return INF
	var distance: float = attacker.global_position.distance_to(candidate.global_position)
	if distance > scan_radius:
		return INF
	var attack_range := _get_attack_range(attacker)
	var pressure := get_pressure_on(candidate, attacker)
	var score: float = distance + float(pressure) * attack_range * PRESSURE_SCORE_MULTIPLIER
	if attacker.has_method("get_current_combat_target") and attacker.get_current_combat_target() == candidate:
		score -= attack_range * CURRENT_TARGET_STICKINESS
	if candidate.has_method("get_current_combat_target") and candidate.get_current_combat_target() == attacker:
		score -= attack_range * 0.45
	return score


static func get_pressure_on(defender, excluding = null) -> int:
	if not _is_valid_combatant(defender):
		return 0
	var pressure := 0
	for node in defender.get_tree().get_nodes_in_group(CHARACTER_GROUP):
		if node == defender or node == excluding:
			continue
		if not _is_valid_combatant(node):
			continue
		if not node.has_method("get_current_combat_target"):
			continue
		if node.get_current_combat_target() == defender:
			pressure += 1
	return pressure


static func get_combat_approach_position(defender, attacker, preferred_range: float) -> Vector3:
	if not _is_valid_combatant(defender):
		return Vector3.ZERO
	if not _is_valid_combatant(attacker):
		return defender.global_position
	var slot_index := _get_attacker_slot(defender, attacker)
	var angle := TAU * float(slot_index) / float(APPROACH_SLOT_COUNT)
	var approach_radius := maxf(preferred_range - 0.2, 0.95)
	return defender.global_position + Vector3(cos(angle), 0.0, sin(angle)) * approach_radius


static func try_begin_exchange(attacker, defender, action_seconds: float) -> bool:
	_prune_expired_state()
	if not _is_valid_combatant(attacker) or not _is_valid_combatant(defender):
		return false
	if is_character_locked(attacker) or is_character_locked(defender):
		return false
	var had_reservation := _consume_matching_reservation(defender, attacker)
	if not had_reservation:
		if _has_ready_reservation_for_other_attacker(defender, attacker):
			return false
		if not _wins_pressure_contest(attacker):
			return false
	_lock_exchange(attacker, defender, action_seconds)
	return true


static func is_character_locked(character) -> bool:
	if not _is_valid_combatant(character):
		return false
	_prune_expired_state()
	var character_id: int = character.get_instance_id()
	return float(_participant_locks.get(character_id, 0.0)) > _now_seconds()


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
	_participant_locks.erase(character_id)
	_clear_reservations_involving(character_id)
	_slots_by_defender.erase(character_id)
	for defender_id in _slots_by_defender.keys():
		var slots = _slots_by_defender.get(defender_id, {})
		if slots is Dictionary:
			slots.erase(character_id)


static func _wins_pressure_contest(attacker) -> bool:
	var pressure_attackers := _get_ready_attackers_against(attacker)
	if pressure_attackers.is_empty():
		return true
	var attacker_roll := _roll_initiative(attacker)
	var winning_attacker = null
	var winning_roll := -INF
	for pressure_attacker in pressure_attackers:
		var pressure_roll := _roll_initiative(pressure_attacker)
		if pressure_roll >= attacker_roll and pressure_roll > winning_roll:
			winning_roll = pressure_roll
			winning_attacker = pressure_attacker
	if winning_attacker == null:
		return true
	_reserve_turn(attacker, winning_attacker)
	return false


static func _get_ready_attackers_against(defender) -> Array:
	var result: Array = []
	if not _is_valid_combatant(defender):
		return result
	for node in defender.get_tree().get_nodes_in_group(CHARACTER_GROUP):
		if node == defender:
			continue
		if not _is_valid_combatant(node):
			continue
		if not node.has_method("get_current_combat_target") or node.get_current_combat_target() != defender:
			continue
		if is_character_locked(node):
			continue
		if node.has_method("is_ready_for_combat_exchange") and node.is_ready_for_combat_exchange(defender):
			result.append(node)
	return result


static func _roll_initiative(character) -> float:
	var dexterity := 10.0
	if character != null and character.has_method("get_stat_value"):
		dexterity = maxf(float(character.get_stat_value("dexterity")), 0.01)
	return randf() * dexterity


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
	if _is_valid_combatant(reserved_attacker) and reserved_attacker.has_method("is_ready_for_combat_exchange") and reserved_attacker.is_ready_for_combat_exchange(defender):
		return true
	_turn_reservations.erase(defender_id)
	return false


static func _lock_exchange(attacker, defender, action_seconds: float) -> void:
	var lock_until := _now_seconds() + maxf(action_seconds + EXCHANGE_RECOVERY_SECONDS, MIN_EXCHANGE_LOCK_SECONDS)
	_participant_locks[attacker.get_instance_id()] = lock_until
	_participant_locks[defender.get_instance_id()] = lock_until
	_clear_reservations_involving(attacker.get_instance_id())
	_clear_reservations_involving(defender.get_instance_id())


static func _get_attacker_slot(defender, attacker) -> int:
	var defender_id: int = defender.get_instance_id()
	var attacker_id: int = attacker.get_instance_id()
	var slots = _slots_by_defender.get(defender_id, {})
	if not (slots is Dictionary):
		slots = {}
	_prune_slots(defender, slots)
	if slots.has(attacker_id):
		return int(slots[attacker_id])
	var desired_slot := _slot_index_for_direction(defender, attacker)
	var slot_index := _nearest_free_slot(slots, desired_slot)
	slots[attacker_id] = slot_index
	_slots_by_defender[defender_id] = slots
	return slot_index


static func _slot_index_for_direction(defender, attacker) -> int:
	var direction: Vector3 = attacker.global_position - defender.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		var seed := float(attacker.get_instance_id() % APPROACH_SLOT_COUNT) / float(APPROACH_SLOT_COUNT)
		return int(seed * APPROACH_SLOT_COUNT) % APPROACH_SLOT_COUNT
	var angle := atan2(direction.z, direction.x)
	if angle < 0.0:
		angle += TAU
	return int(round(angle / TAU * float(APPROACH_SLOT_COUNT))) % APPROACH_SLOT_COUNT


static func _nearest_free_slot(slots: Dictionary, desired_slot: int) -> int:
	var used_slots := slots.values()
	if not used_slots.has(desired_slot):
		return desired_slot
	for offset in range(1, APPROACH_SLOT_COUNT):
		var right_slot := (desired_slot + offset) % APPROACH_SLOT_COUNT
		if not used_slots.has(right_slot):
			return right_slot
		var left_slot := (desired_slot - offset + APPROACH_SLOT_COUNT) % APPROACH_SLOT_COUNT
		if not used_slots.has(left_slot):
			return left_slot
	return desired_slot


static func _prune_slots(defender, slots: Dictionary) -> void:
	for attacker_id in slots.keys():
		var attacker = instance_from_id(int(attacker_id))
		if not _is_valid_combatant(attacker):
			slots.erase(attacker_id)
			continue
		if not attacker.has_method("get_current_combat_target") or attacker.get_current_combat_target() != defender:
			slots.erase(attacker_id)


static func _clear_reservations_involving(character_id: int) -> void:
	for defender_id in _turn_reservations.keys():
		var reservation = _turn_reservations.get(defender_id)
		if int(defender_id) == character_id:
			_turn_reservations.erase(defender_id)
		elif reservation is Dictionary and int(reservation.get("attacker_id", 0)) == character_id:
			_turn_reservations.erase(defender_id)


static func _prune_expired_state() -> void:
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
	if character.has_method("get_attack_range"):
		return maxf(float(character.get_attack_range()), 1.0)
	return maxf(float(character.get("attack_range")), 1.0)


static func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) * 0.001
