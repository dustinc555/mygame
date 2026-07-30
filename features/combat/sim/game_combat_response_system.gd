extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatResponseSystem

const SERVICE_ID := &"combat_response"

signal combat_event_emitted(event_id: String, event_type: int)
signal root_combat_started(attacker_actor_id: String, protected_actor_id: String, origin: Vector3, encounter_id: String)

const ENTITY = preload("res://addons/gecs/ecs/entity.gd")
const C_EVENT = preload("res://features/combat/sim/c_game_combat_event.gd")
const C_INTENT = preload("res://features/combat/sim/c_game_combat_response_intent.gd")
const C_ENCOUNTER = preload("res://features/combat/sim/c_game_combat_encounter.gd")
const C_IDENTITY = preload("res://features/actors/sim/c_game_actor_identity.gd")
const C_FACTION = preload("res://features/actors/sim/c_game_actor_faction.gd")
const C_SETTLEMENT = preload("res://features/actors/sim/c_game_actor_settlement.gd")
const C_SPATIAL = preload("res://features/actors/sim/c_game_actor_spatial.gd")
const C_VITALS = preload("res://features/actors/sim/c_game_actor_vitals.gd")
const C_CONFIG = preload("res://features/combat/sim/c_game_combat_config.gd")
const C_STATE = preload("res://features/combat/sim/c_game_combat_state.gd")
const C_FACTION_STATE = preload("res://features/world_sim/sim/c_game_faction_state.gd")

const FIXED_TICK_SECONDS := 1.0 / 20.0
const MAX_FIXED_STEPS_PER_FRAME := 5
const CELL_SIZE := 8.0
const MAX_LOCAL_OCCUPANT_CHECKS := 1024
const MAX_RESPONDERS_PER_EVENT := 256
const MAX_EVENTS_PER_TICK := 1024
const ENCOUNTER_LIFETIME_TICKS := 240
const AUTHORITY_INTENT_TICKS := 400
const SIDE_AGGRESSOR := 1
const SIDE_DEFENDER := 2

var _fixed_accumulator := 0.0
var _next_event_sequence := 1
var _next_intent_sequence := 1
var _next_encounter_sequence := 1
var _intent_entity_by_key: Dictionary = {}
var _encounter_entity_by_id: Dictionary = {}
var _encounter_id_by_actor: Dictionary = {}
var _authorized_response_pairs: Dictionary = {}
var _active_authority_target_keys: Dictionary = {}
var _responder_ids_by_authority: Dictionary = {}
var _law_response_actor_ids: Dictionary = {}
var _available_actor_ids: Dictionary = {}
var _read_indexes_dirty := false
var _diplomatic_states: Dictionary = {}


func _init() -> void:
	process_empty = true


func query() -> QueryBuilder:
	return q.with_all([C_EVENT]).iterate([C_EVENT])


func process(_entities: Array, _components: Array, delta: float) -> void:
	_fixed_accumulator = minf(_fixed_accumulator + maxf(delta, 0.0), FIXED_TICK_SECONDS * MAX_FIXED_STEPS_PER_FRAME)
	var steps := 0
	while _fixed_accumulator >= FIXED_TICK_SECONDS and steps < MAX_FIXED_STEPS_PER_FRAME:
		_process_fixed_tick()
		_fixed_accumulator -= FIXED_TICK_SECONDS
		steps += 1


func emit_attack_started(attacker_actor_id: String, protected_actor_id: String, origin: Vector3, response_depth: int, encounter_id := "", authorized_response := false) -> String:
	return _enqueue_event({
		"type": C_EVENT.Type.ATTACK_STARTED,
		"audience": C_EVENT.Audience.SOCIAL,
		"attacker_actor_id": attacker_actor_id,
		"protected_actor_id": protected_actor_id,
		"target_actor_id": attacker_actor_id,
		"origin": origin,
		"radius": NpcRules.NPC_ALERT_PROXIMITY_RADIUS,
		"response_depth": maxi(response_depth, 0),
		"encounter_id": encounter_id,
		"authorized_response": authorized_response,
	})


func authorize_response(audience: int, target_actor_id: String, protected_actor_id: String, authority_id: String, authority_faction_id: String, settlement_id: String, origin: Vector3, radius: float, response_kind: int, explicit_responder_actor_ids := PackedStringArray()) -> String:
	return _enqueue_event({
		"type": C_EVENT.Type.RESPONSE_AUTHORIZED,
		"audience": audience,
		"target_actor_id": target_actor_id,
		"protected_actor_id": protected_actor_id,
		"authority_id": authority_id,
		"authority_faction_id": authority_faction_id,
		"settlement_id": settlement_id,
		"origin": origin,
		"radius": maxf(radius, 0.0),
		"response_kind": response_kind,
		"explicit_responder_actor_ids": explicit_responder_actor_ids,
	})


func revoke_response(authority_id: String, target_actor_id := "") -> String:
	if authority_id.is_empty():
		return ""
	return _enqueue_event({
		"type": C_EVENT.Type.RESPONSE_REVOKED,
		"authority_id": authority_id,
		"target_actor_id": target_actor_id,
	})


func get_response_depth(responder_actor_id: String, target_actor_id: String) -> int:
	return int(get_response_context(responder_actor_id, target_actor_id).get("response_depth", 0))


func get_response_context(responder_actor_id: String, target_actor_id: String) -> Dictionary:
	var responder_encounter_id := str(_encounter_id_by_actor.get(responder_actor_id, ""))
	var target_encounter_id := str(_encounter_id_by_actor.get(target_actor_id, ""))
	if not responder_encounter_id.is_empty() and responder_encounter_id == target_encounter_id:
		var encounter = _encounter_component(responder_encounter_id)
		if encounter != null and encounter.side_of(responder_actor_id) != 0 and encounter.side_of(responder_actor_id) != encounter.side_of(target_actor_id):
			var lawful_counterattack: bool = encounter.side_of(responder_actor_id) == SIDE_DEFENDER or _authorized_response_pairs.has(_actor_pair_key(target_actor_id, responder_actor_id))
			return {
				"response_depth": 1 if lawful_counterattack else 0,
				"encounter_id": responder_encounter_id,
				"authorized_response": false,
			}
	if _authorized_response_pairs.has(_actor_pair_key(responder_actor_id, target_actor_id)):
		return {"response_depth": 0, "authorized_response": true}
	return {}


func has_active_law_response(actor_id: String) -> bool:
	return bool(_law_response_actor_ids.get(actor_id, false))


func has_active_authority_response(authority_id: String, target_actor_id := "") -> bool:
	if authority_id.is_empty():
		return false
	if target_actor_id.is_empty():
		return _responder_ids_by_authority.has(authority_id)
	return bool(_active_authority_target_keys.get(_authority_target_key(authority_id, target_actor_id), false))


func get_active_responder_ids(authority_id: String) -> PackedStringArray:
	var ids := PackedStringArray(_responder_ids_by_authority.get(authority_id, PackedStringArray()))
	ids.sort()
	return ids


func get_active_intents() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity in _world.query.with_all([C_INTENT]).execute():
		var intent = entity.get_component(C_INTENT)
		if intent != null:
			result.append({
				"intent_id": str(intent.intent_id),
				"sequence": int(intent.sequence),
				"kind": int(intent.kind),
				"responder_actor_id": str(intent.responder_actor_id),
				"target_actor_id": str(intent.target_actor_id),
				"authority_id": str(intent.authority_id),
				"remaining_ticks": int(intent.remaining_ticks),
			})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left["sequence"]) < int(right["sequence"]))
	return result


func get_active_encounters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity in _world.query.with_all([C_ENCOUNTER]).execute():
		var encounter = entity.get_component(C_ENCOUNTER)
		if encounter != null:
			result.append(_encounter_record(encounter))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left["sequence"]) < int(right["sequence"]))
	return result


func get_active_root_aggressions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entity in _world.query.with_all([C_ENCOUNTER]).execute():
		var encounter = entity.get_component(C_ENCOUNTER)
		if encounter == null:
			continue
		for attacker_value in encounter.aggression_target_by_actor.keys():
			var attacker_actor_id := str(attacker_value)
			result.append({
				"pair_key": _unordered_actor_pair_key(attacker_actor_id, str(encounter.aggression_target_by_actor[attacker_value])),
				"attacker_actor_id": attacker_actor_id,
				"protected_actor_id": str(encounter.aggression_target_by_actor[attacker_value]),
				"origin": encounter.origin,
				"encounter_id": str(encounter.encounter_id),
			})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left["pair_key"]) < str(right["pair_key"]))
	return result


func _process_fixed_tick() -> void:
	_refresh_available_actor_ids()
	_tick_and_reindex_encounters()
	_tick_and_reindex_intents()
	var event_entities: Array = _world.query.with_all([C_EVENT]).execute().duplicate()
	event_entities.sort_custom(func(left, right) -> bool:
		var left_event = left.get_component(C_EVENT)
		var right_event = right.get_component(C_EVENT)
		return int(left_event.sequence) < int(right_event.sequence)
	)
	if event_entities.is_empty():
		return
	var actor_cache := _build_actor_cache()
	var spatial_buckets := _build_spatial_buckets(actor_cache)
	_refresh_diplomacy()
	for event_index in range(mini(event_entities.size(), MAX_EVENTS_PER_TICK)):
		var entity = event_entities[event_index]
		var event = entity.get_component(C_EVENT)
		if event != null:
			_consume_event(event, actor_cache, spatial_buckets)
		_world.remove_entity(entity)
	if _read_indexes_dirty:
		_rebuild_authority_read_indexes()


func _consume_event(event, actor_cache: Dictionary, spatial_buckets: Dictionary) -> void:
	match int(event.type):
		C_EVENT.Type.ATTACK_STARTED:
			_handle_attack_event(event, actor_cache, spatial_buckets)
		C_EVENT.Type.RESPONSE_AUTHORIZED:
			_authorize_declared_responses(event, actor_cache, spatial_buckets)
		C_EVENT.Type.RESPONSE_REVOKED:
			_remove_authority_intents(str(event.authority_id), str(event.target_actor_id))


func _handle_attack_event(event, actor_cache: Dictionary, spatial_buckets: Dictionary) -> void:
	var attacker_id := str(event.attacker_actor_id)
	var protected_id := str(event.protected_actor_id)
	var attacker_entry: Dictionary = actor_cache.get(attacker_id, {})
	var protected_entry: Dictionary = actor_cache.get(protected_id, {})
	if attacker_entry.is_empty() or protected_entry.is_empty():
		return
	var attacker_encounter = _encounter_for_actor(attacker_id)
	var protected_encounter = _encounter_for_actor(protected_id)
	var encounter = null
	if attacker_encounter != null and protected_encounter != null:
		if str(attacker_encounter.encounter_id) != str(protected_encounter.encounter_id):
			_record_external_aggression(attacker_encounter, attacker_id, protected_id, event.origin, bool(event.authorized_response))
			return
		encounter = attacker_encounter
	elif attacker_encounter != null:
		_record_external_aggression(attacker_encounter, attacker_id, protected_id, event.origin, bool(event.authorized_response))
		return
	elif protected_encounter != null:
		encounter = protected_encounter
		var protected_side := int(encounter.side_of(protected_id))
		var attacker_side := SIDE_DEFENDER if protected_side == SIDE_AGGRESSOR else SIDE_AGGRESSOR
		encounter.add_to_side(attacker_id, attacker_side)
		_index_encounter_actor(str(encounter.encounter_id), attacker_id)
	else:
		encounter = _create_encounter(attacker_id, protected_id, event.origin, str(event.encounter_id), bool(event.authorized_response))
	if encounter == null:
		return
	encounter.origin = event.origin
	encounter.remaining_ticks = ENCOUNTER_LIFETIME_TICKS
	_commit_attack(encounter, attacker_id, protected_id, event.origin, bool(event.authorized_response))
	_recruit_social_allies(encounter, attacker_id, protected_id, attacker_entry, protected_entry, event.origin, float(event.radius), actor_cache, spatial_buckets)


func _create_encounter(attacker_actor_id: String, protected_actor_id: String, origin: Vector3, requested_encounter_id: String, authorized_response: bool):
	var sequence := _next_encounter_sequence
	_next_encounter_sequence += 1
	var encounter_id := requested_encounter_id
	if encounter_id.is_empty() or _world.get_entity_by_id(encounter_id) != null:
		encounter_id = "combat_encounter:%d" % sequence
	while _world.get_entity_by_id(encounter_id) != null:
		sequence = _next_encounter_sequence
		_next_encounter_sequence += 1
		encounter_id = "combat_encounter:%d" % sequence
	var entity = ENTITY.new()
	entity.name = "CombatEncounter_%d" % sequence
	entity.id = encounter_id
	var encounter = C_ENCOUNTER.new()
	encounter.encounter_id = encounter_id
	encounter.sequence = sequence
	encounter.origin = origin
	encounter.remaining_ticks = ENCOUNTER_LIFETIME_TICKS
	if authorized_response:
		encounter.root_aggressor_actor_id = protected_actor_id
		encounter.root_defender_actor_id = attacker_actor_id
		encounter.add_to_side(protected_actor_id, SIDE_AGGRESSOR)
		encounter.add_to_side(attacker_actor_id, SIDE_DEFENDER)
	else:
		encounter.root_aggressor_actor_id = attacker_actor_id
		encounter.root_defender_actor_id = protected_actor_id
		encounter.add_to_side(attacker_actor_id, SIDE_AGGRESSOR)
		encounter.add_to_side(protected_actor_id, SIDE_DEFENDER)
	_world.add_entity(entity, [encounter])
	var registered_encounter = entity.get_component(C_ENCOUNTER)
	_index_encounter(entity, registered_encounter)
	return registered_encounter


func _commit_attack(encounter, attacker_actor_id: String, target_actor_id: String, origin: Vector3, authorized_response: bool) -> void:
	encounter.mark_committed(attacker_actor_id)
	if authorized_response:
		return
	var attacker_side := int(encounter.side_of(attacker_actor_id))
	var target_side := int(encounter.side_of(target_actor_id))
	var is_unlawful := attacker_side == SIDE_AGGRESSOR and target_side == SIDE_DEFENDER
	if attacker_side != 0 and attacker_side == target_side:
		is_unlawful = str(encounter.aggression_target_by_actor.get(target_actor_id, "")) != attacker_actor_id
	if is_unlawful and encounter.mark_aggression(attacker_actor_id, target_actor_id):
		root_combat_started.emit(attacker_actor_id, target_actor_id, origin, str(encounter.encounter_id))


func _record_external_aggression(encounter, attacker_actor_id: String, target_actor_id: String, origin: Vector3, authorized_response: bool) -> void:
	encounter.origin = origin
	encounter.remaining_ticks = ENCOUNTER_LIFETIME_TICKS
	encounter.mark_committed(attacker_actor_id)
	if not authorized_response and encounter.mark_aggression(attacker_actor_id, target_actor_id):
		root_combat_started.emit(attacker_actor_id, target_actor_id, origin, str(encounter.encounter_id))


func _recruit_social_allies(encounter, attacker_actor_id: String, protected_actor_id: String, attacker_entry: Dictionary, protected_entry: Dictionary, origin: Vector3, radius: float, actor_cache: Dictionary, spatial_buckets: Dictionary) -> void:
	var attacker_side := int(encounter.side_of(attacker_actor_id))
	var protected_side := int(encounter.side_of(protected_actor_id))
	if attacker_side == 0 or protected_side == 0 or attacker_side == protected_side:
		return
	var accepted := 0
	for entry in _nearby_entries(origin, radius, spatial_buckets):
		var actor_id := str(entry.get("actor_id", ""))
		if actor_id == attacker_actor_id or actor_id == protected_actor_id or _encounter_id_by_actor.has(actor_id):
			continue
		if not _available_for_response(entry):
			continue
		var attacker_allegiance := _social_allegiance_strength(entry, attacker_entry)
		var protected_allegiance := _social_allegiance_strength(entry, protected_entry)
		if attacker_allegiance == 0 and protected_allegiance == 0:
			continue
		var side := attacker_side if attacker_allegiance > protected_allegiance else protected_side
		encounter.add_to_side(actor_id, side)
		_index_encounter_actor(str(encounter.encounter_id), actor_id)
		accepted += 1
		if accepted >= MAX_RESPONDERS_PER_EVENT:
			break


func _authorize_declared_responses(event, actor_cache: Dictionary, spatial_buckets: Dictionary) -> void:
	var candidates: Array[Dictionary] = []
	if int(event.audience) == C_EVENT.Audience.EXPLICIT_ACTORS:
		for actor_id in event.explicit_responder_actor_ids:
			var entry: Dictionary = actor_cache.get(str(actor_id), {})
			if not entry.is_empty():
				candidates.append(entry)
	else:
		candidates = _nearby_entries(event.origin, float(event.radius), spatial_buckets)
	var accepted := 0
	for entry in candidates:
		var actor_id := str(entry.get("actor_id", ""))
		if actor_id == str(event.target_actor_id) or not _available_for_response(entry):
			continue
		if int(event.audience) == C_EVENT.Audience.SETTLEMENT_AUTHORITY and not _has_public_duty(entry, str(event.settlement_id), str(event.authority_faction_id)):
			continue
		_upsert_intent(int(event.response_kind), actor_id, str(event.target_actor_id), str(event.authority_id), AUTHORITY_INTENT_TICKS)
		accepted += 1
		if accepted >= MAX_RESPONDERS_PER_EVENT:
			break


func _upsert_intent(kind: int, responder_actor_id: String, target_actor_id: String, authority_id: String, remaining_ticks: int) -> void:
	if responder_actor_id.is_empty() or target_actor_id.is_empty():
		return
	var key := _intent_key(kind, responder_actor_id, target_actor_id, authority_id)
	var existing = _intent_entity_by_key.get(key)
	if existing != null and is_instance_valid(existing):
		var existing_intent = existing.get_component(C_INTENT)
		if existing_intent != null:
			existing_intent.remaining_ticks = maxi(int(existing_intent.remaining_ticks), remaining_ticks)
		return
	var entity = ENTITY.new()
	while _world.get_entity_by_id("combat_response:%d" % _next_intent_sequence) != null:
		_next_intent_sequence += 1
	entity.name = "CombatResponse_%d" % _next_intent_sequence
	entity.id = "combat_response:%d" % _next_intent_sequence
	var intent = C_INTENT.new()
	intent.intent_id = entity.id
	intent.sequence = _next_intent_sequence
	intent.kind = kind
	intent.responder_actor_id = responder_actor_id
	intent.target_actor_id = target_actor_id
	intent.authority_id = authority_id
	intent.remaining_ticks = remaining_ticks
	_next_intent_sequence += 1
	_world.add_entity(entity, [intent])
	_index_intent(entity, intent)


func _enqueue_event(values: Dictionary) -> String:
	if _world == null:
		return ""
	var sequence := _next_event_sequence
	while _world.get_entity_by_id("combat_event:%d" % sequence) != null:
		sequence += 1
	_next_event_sequence = sequence + 1
	var event_id := "combat_event:%d" % sequence
	var entity = ENTITY.new()
	entity.name = "CombatEvent_%d" % sequence
	entity.id = event_id
	var event = C_EVENT.new()
	event.event_id = event_id
	event.sequence = sequence
	event.type = int(values.get("type", C_EVENT.Type.ATTACK_STARTED))
	event.audience = int(values.get("audience", C_EVENT.Audience.SOCIAL))
	event.attacker_actor_id = str(values.get("attacker_actor_id", ""))
	event.protected_actor_id = str(values.get("protected_actor_id", ""))
	event.target_actor_id = str(values.get("target_actor_id", ""))
	event.encounter_id = str(values.get("encounter_id", ""))
	if event.type == C_EVENT.Type.ATTACK_STARTED and event.encounter_id.is_empty():
		event.encounter_id = "combat_encounter:%d" % sequence
	event.authority_id = str(values.get("authority_id", ""))
	event.authority_faction_id = str(values.get("authority_faction_id", ""))
	event.settlement_id = str(values.get("settlement_id", ""))
	event.origin = values.get("origin", Vector3.ZERO)
	event.radius = float(values.get("radius", 0.0))
	event.response_depth = int(values.get("response_depth", 0))
	event.response_kind = int(values.get("response_kind", C_INTENT.Kind.LAW_ENFORCEMENT))
	event.authorized_response = bool(values.get("authorized_response", false))
	event.explicit_responder_actor_ids = PackedStringArray(values.get("explicit_responder_actor_ids", []))
	_world.add_entity(entity, [event])
	combat_event_emitted.emit(event_id, event.type)
	return event_id


func _tick_and_reindex_encounters() -> void:
	_encounter_entity_by_id.clear()
	_encounter_id_by_actor.clear()
	var removals: Array = []
	for entity in _world.query.with_all([C_ENCOUNTER]).execute():
		var encounter = entity.get_component(C_ENCOUNTER)
		if encounter == null:
			removals.append(entity)
			continue
		encounter.remaining_ticks = maxi(0, int(encounter.remaining_ticks) - 1)
		_prune_encounter(encounter)
		if encounter.remaining_ticks == 0 or encounter.aggressor_side_actor_ids.is_empty() or encounter.defender_side_actor_ids.is_empty():
			removals.append(entity)
			continue
		_index_encounter(entity, encounter)
	for entity in removals:
		_world.remove_entity(entity)


func _prune_encounter(encounter) -> void:
	for actor_id in encounter.aggressor_side_actor_ids.duplicate():
		if not _actor_is_available(actor_id):
			encounter.remove_actor(actor_id)
	for actor_id in encounter.defender_side_actor_ids.duplicate():
		if not _actor_is_available(actor_id):
			encounter.remove_actor(actor_id)
	for attacker_value in encounter.aggression_target_by_actor.keys():
		var attacker_id := str(attacker_value)
		var target_id := str(encounter.aggression_target_by_actor[attacker_value])
		if not _actor_is_available(attacker_id) or not _actor_is_available(target_id):
			encounter.aggression_target_by_actor.erase(attacker_value)


func _actor_is_available(actor_id: String) -> bool:
	return bool(_available_actor_ids.get(actor_id, false))


func _refresh_available_actor_ids() -> void:
	_available_actor_ids.clear()
	for entity in _world.query.with_all([C_IDENTITY, C_VITALS, C_CONFIG]).execute():
		var identity = entity.get_component(C_IDENTITY)
		var vitals = entity.get_component(C_VITALS)
		var config = entity.get_component(C_CONFIG)
		if identity != null and vitals != null and config != null and int(vitals.life_state) == NpcRules.LifeState.ALIVE and not bool(config.protected_from_combat):
			_available_actor_ids[str(identity.actor_id)] = true


func _tick_and_reindex_intents() -> void:
	_intent_entity_by_key.clear()
	_authorized_response_pairs.clear()
	_active_authority_target_keys.clear()
	_responder_ids_by_authority.clear()
	_law_response_actor_ids.clear()
	var removals: Array = []
	for entity in _world.query.with_all([C_INTENT]).execute():
		var intent = entity.get_component(C_INTENT)
		if intent == null:
			removals.append(entity)
			continue
		intent.remaining_ticks = maxi(0, int(intent.remaining_ticks) - 1)
		if intent.remaining_ticks == 0 or not _actor_is_available(str(intent.responder_actor_id)):
			removals.append(entity)
			continue
		_index_intent(entity, intent)
	for entity in removals:
		_remove_intent_entity(entity)
	_read_indexes_dirty = false


func _remove_authority_intents(authority_id: String, target_actor_id: String) -> void:
	if authority_id.is_empty():
		return
	var removals: Array = []
	for entity in _world.query.with_all([C_INTENT]).execute():
		var intent = entity.get_component(C_INTENT)
		if intent != null and str(intent.authority_id) == authority_id and (target_actor_id.is_empty() or str(intent.target_actor_id) == target_actor_id):
			removals.append(entity)
	for entity in removals:
		_remove_intent_entity(entity)


func _index_encounter(entity, encounter) -> void:
	var encounter_id := str(encounter.encounter_id)
	_encounter_entity_by_id[encounter_id] = entity
	for actor_id in encounter.aggressor_side_actor_ids:
		_index_encounter_actor(encounter_id, actor_id)
	for actor_id in encounter.defender_side_actor_ids:
		_index_encounter_actor(encounter_id, actor_id)


func _index_encounter_actor(encounter_id: String, actor_id: String) -> void:
	if not actor_id.is_empty() and not _encounter_id_by_actor.has(actor_id):
		_encounter_id_by_actor[actor_id] = encounter_id


func _index_intent(entity, intent) -> void:
	_intent_entity_by_key[_intent_key(int(intent.kind), str(intent.responder_actor_id), str(intent.target_actor_id), str(intent.authority_id))] = entity
	_authorized_response_pairs[_actor_pair_key(str(intent.responder_actor_id), str(intent.target_actor_id))] = true
	_index_authority_read(intent)


func _index_authority_read(intent) -> void:
	var authority_id := str(intent.authority_id)
	if not authority_id.is_empty():
		_active_authority_target_keys[_authority_target_key(authority_id, str(intent.target_actor_id))] = true
		var responder_ids: PackedStringArray = _responder_ids_by_authority.get(authority_id, PackedStringArray())
		if not responder_ids.has(str(intent.responder_actor_id)):
			responder_ids.append(str(intent.responder_actor_id))
		_responder_ids_by_authority[authority_id] = responder_ids
	if int(intent.kind) == C_INTENT.Kind.LAW_ENFORCEMENT:
		_law_response_actor_ids[str(intent.responder_actor_id)] = true


func _rebuild_authority_read_indexes() -> void:
	_active_authority_target_keys.clear()
	_responder_ids_by_authority.clear()
	_law_response_actor_ids.clear()
	for entity in _world.query.with_all([C_INTENT]).execute():
		var intent = entity.get_component(C_INTENT)
		if intent != null and int(intent.remaining_ticks) > 0:
			_index_authority_read(intent)
	_read_indexes_dirty = false


func _remove_intent_entity(entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var intent = entity.get_component(C_INTENT)
	if intent != null:
		_intent_entity_by_key.erase(_intent_key(int(intent.kind), str(intent.responder_actor_id), str(intent.target_actor_id), str(intent.authority_id)))
		if not str(intent.authority_id).is_empty():
			_read_indexes_dirty = true
	_world.remove_entity(entity)


func _encounter_for_actor(actor_id: String):
	return _encounter_component(str(_encounter_id_by_actor.get(actor_id, "")))


func _encounter_component(encounter_id: String):
	var entity = _encounter_entity_by_id.get(encounter_id)
	return entity.get_component(C_ENCOUNTER) if entity != null and is_instance_valid(entity) else null


func _encounter_record(encounter) -> Dictionary:
	return {
		"encounter_id": str(encounter.encounter_id),
		"sequence": int(encounter.sequence),
		"origin": encounter.origin,
		"remaining_ticks": int(encounter.remaining_ticks),
		"root_aggressor_actor_id": str(encounter.root_aggressor_actor_id),
		"root_defender_actor_id": str(encounter.root_defender_actor_id),
		"aggressor_side_actor_ids": encounter.aggressor_side_actor_ids.duplicate(),
		"defender_side_actor_ids": encounter.defender_side_actor_ids.duplicate(),
		"committed_actor_ids": encounter.committed_actor_ids.duplicate(),
		"aggression_target_by_actor": encounter.aggression_target_by_actor.duplicate(true),
	}


func _build_actor_cache() -> Dictionary:
	var result := {}
	for entity in _world.query.with_all([C_IDENTITY, C_FACTION, C_SETTLEMENT, C_SPATIAL, C_VITALS, C_CONFIG, C_STATE]).execute():
		var identity = entity.get_component(C_IDENTITY)
		if identity == null or str(identity.actor_id).is_empty():
			continue
		var actor_id := str(identity.actor_id)
		result[actor_id] = {
			"actor_id": actor_id,
			"identity": identity,
			"faction": entity.get_component(C_FACTION),
			"settlement": entity.get_component(C_SETTLEMENT),
			"spatial": entity.get_component(C_SPATIAL),
			"vitals": entity.get_component(C_VITALS),
			"config": entity.get_component(C_CONFIG),
			"state": entity.get_component(C_STATE),
		}
	return result


func _build_spatial_buckets(actor_cache: Dictionary) -> Dictionary:
	var buckets := {}
	var actor_ids: Array = actor_cache.keys()
	actor_ids.sort()
	for actor_id in actor_ids:
		var entry := actor_cache[actor_id] as Dictionary
		var spatial = entry.get("spatial")
		if spatial == null:
			continue
		var cell := _cell(spatial.world_position)
		var bucket: Array = buckets.get(cell, [])
		bucket.append(entry)
		buckets[cell] = bucket
	return buckets


func _nearby_entries(origin: Vector3, radius: float, buckets: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var center := _cell(origin)
	var cell_radius := int(ceil(radius / CELL_SIZE))
	var radius_sq := radius * radius
	var checks := 0
	for x in range(center.x - cell_radius, center.x + cell_radius + 1):
		for z in range(center.y - cell_radius, center.y + cell_radius + 1):
			for entry_value in (buckets.get(Vector2i(x, z), []) as Array):
				checks += 1
				if checks > MAX_LOCAL_OCCUPANT_CHECKS:
					break
				var entry := entry_value as Dictionary
				var spatial = entry.get("spatial")
				if spatial != null and spatial.world_position.distance_squared_to(origin) <= radius_sq:
					candidates.append(entry)
			if checks > MAX_LOCAL_OCCUPANT_CHECKS:
				break
		if checks > MAX_LOCAL_OCCUPANT_CHECKS:
			break
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.get("actor_id", "")) < str(right.get("actor_id", "")))
	return candidates


func _available_for_response(entry: Dictionary) -> bool:
	var vitals = entry.get("vitals")
	var config = entry.get("config")
	var faction = entry.get("faction")
	return vitals != null and config != null and faction != null and int(vitals.life_state) == NpcRules.LifeState.ALIVE and not bool(config.protected_from_combat) and int(faction.combat_stance) != NpcRules.CombatStance.PASSIVE


func _social_allegiance_strength(responder: Dictionary, protected_entry: Dictionary) -> int:
	var responder_faction = responder.get("faction")
	var protected_faction = protected_entry.get("faction")
	if responder_faction == null or protected_faction == null:
		return 0
	var responder_party := str(responder_faction.party_id)
	var protected_party := str(protected_faction.party_id)
	if not responder_party.is_empty() and responder_party == protected_party:
		return 4
	var responder_squad := str(responder_faction.squad_name)
	var protected_squad := str(protected_faction.squad_name)
	if not responder_squad.is_empty() and responder_squad == protected_squad:
		return 3
	var responder_faction_id := str(responder_faction.faction_id)
	var protected_faction_id := str(protected_faction.faction_id)
	if not responder_faction_id.is_empty() and responder_faction_id == protected_faction_id:
		return 2
	return 1 if _factions_are_allied_or_protected(responder_faction_id, protected_faction_id) else 0


func _has_public_duty(entry: Dictionary, settlement_id: String, authority_faction_id: String) -> bool:
	var identity = entry.get("identity")
	var faction = entry.get("faction")
	var settlement = entry.get("settlement")
	return not settlement_id.is_empty() and not authority_faction_id.is_empty() and identity != null and faction != null and settlement != null and str(settlement.settlement_id) == settlement_id and str(faction.faction_id) == authority_faction_id and identity.authority_scopes.has("settlement_authority")


func _refresh_diplomacy() -> void:
	_diplomatic_states = {}
	for entity in _world.query.with_all([C_FACTION_STATE]).execute():
		var state = entity.get_component(C_FACTION_STATE)
		if state != null:
			_diplomatic_states = state.diplomatic_states.duplicate(true)
		break


func _factions_are_allied_or_protected(responder_faction_id: String, protected_faction_id: String) -> bool:
	if responder_faction_id.is_empty() or protected_faction_id.is_empty():
		return false
	var record: Dictionary = _diplomatic_states.get(_relation_key(responder_faction_id, protected_faction_id), {})
	var relation := str(record.get("state", "neutral"))
	return relation == "alliance" or (relation == "protectorate" and str(record.get("primary_faction_id", "")) == protected_faction_id and str(record.get("secondary_faction_id", "")) == responder_faction_id)


func _intent_key(kind: int, responder_actor_id: String, target_actor_id: String, authority_id: String) -> String:
	return "%d|%s|%s|%s" % [kind, responder_actor_id, target_actor_id, authority_id]


func _actor_pair_key(responder_actor_id: String, target_actor_id: String) -> String:
	return "%s|%s" % [responder_actor_id, target_actor_id]


func _unordered_actor_pair_key(left_actor_id: String, right_actor_id: String) -> String:
	return "%s|%s" % [left_actor_id, right_actor_id] if left_actor_id < right_actor_id else "%s|%s" % [right_actor_id, left_actor_id]


func _authority_target_key(authority_id: String, target_actor_id: String) -> String:
	return "%s|%s" % [authority_id, target_actor_id]


func _relation_key(left: String, right: String) -> String:
	var ids := [left, right]
	ids.sort()
	return "%s:%s" % [ids[0], ids[1]]


func _cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.z / CELL_SIZE))
