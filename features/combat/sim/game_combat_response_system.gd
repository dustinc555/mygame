extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatResponseSystem

const SERVICE_ID := &"combat_response"

signal combat_event_emitted(event_id: String, event_type: int)

const ENTITY = preload("res://addons/gecs/ecs/entity.gd")
const C_EVENT = preload("res://features/combat/sim/c_game_combat_event.gd")
const C_INTENT = preload("res://features/combat/sim/c_game_combat_response_intent.gd")
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
const SOCIAL_INTENT_TICKS := 240
const AUTHORITY_INTENT_TICKS := 400

var _fixed_accumulator := 0.0
var _next_event_sequence := 1
var _next_intent_sequence := 1
var _intent_entity_by_key: Dictionary = {}
var _response_depth_by_pair: Dictionary = {}
var _active_authority_target_keys: Dictionary = {}
var _responder_ids_by_authority: Dictionary = {}
var _law_response_actor_ids: Dictionary = {}
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


func emit_attack_started(attacker_actor_id: String, protected_actor_id: String, origin: Vector3, response_depth: int) -> String:
	return _enqueue_event({
		"type": C_EVENT.Type.ATTACK_STARTED,
		"audience": C_EVENT.Audience.SOCIAL,
		"attacker_actor_id": attacker_actor_id,
		"protected_actor_id": protected_actor_id,
		"target_actor_id": attacker_actor_id,
		"origin": origin,
		"radius": NpcRules.NPC_ALERT_PROXIMITY_RADIUS,
		"response_depth": maxi(response_depth, 0),
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
	return int(_response_depth_by_pair.get(_actor_pair_key(responder_actor_id, target_actor_id), 0))


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
				"response_depth": int(intent.response_depth),
				"remaining_ticks": int(intent.remaining_ticks),
			})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left["sequence"]) < int(right["sequence"]))
	return result


func _process_fixed_tick() -> void:
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
			if int(event.response_depth) == 0:
				_authorize_social_responses(event, actor_cache, spatial_buckets)
		C_EVENT.Type.RESPONSE_AUTHORIZED:
			_authorize_declared_responses(event, actor_cache, spatial_buckets)
		C_EVENT.Type.RESPONSE_REVOKED:
			_remove_authority_intents(str(event.authority_id), str(event.target_actor_id))


func _authorize_social_responses(event, actor_cache: Dictionary, spatial_buckets: Dictionary) -> void:
	var protected_entry: Dictionary = actor_cache.get(str(event.protected_actor_id), {})
	if protected_entry.is_empty():
		return
	var candidates := _nearby_entries(event.origin, float(event.radius), spatial_buckets)
	var accepted := 0
	for entry in candidates:
		var actor_id := str(entry.get("actor_id", ""))
		if actor_id == str(event.protected_actor_id) or actor_id == str(event.attacker_actor_id):
			continue
		if not _available_for_response(entry, true) or not _has_social_obligation(entry, protected_entry):
			continue
		var state = entry.get("state")
		if state != null and (str(state.current_target_actor_id) == str(event.attacker_actor_id) or str(state.system_target_actor_id) == str(event.attacker_actor_id)):
			continue
		_upsert_intent(C_INTENT.Kind.SOCIAL_DEFENSE, actor_id, str(event.attacker_actor_id), "", 1, SOCIAL_INTENT_TICKS)
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
		if actor_id == str(event.target_actor_id) or not _available_for_response(entry, false):
			continue
		if int(event.audience) == C_EVENT.Audience.SETTLEMENT_AUTHORITY and not _has_public_duty(entry, str(event.settlement_id), str(event.authority_faction_id)):
			continue
		_upsert_intent(int(event.response_kind), actor_id, str(event.target_actor_id), str(event.authority_id), 0, AUTHORITY_INTENT_TICKS)
		accepted += 1
		if accepted >= MAX_RESPONDERS_PER_EVENT:
			break


func _upsert_intent(kind: int, responder_actor_id: String, target_actor_id: String, authority_id: String, response_depth: int, remaining_ticks: int) -> void:
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
	intent.response_depth = response_depth
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
	_next_event_sequence = sequence
	_next_event_sequence += 1
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
	event.authority_id = str(values.get("authority_id", ""))
	event.authority_faction_id = str(values.get("authority_faction_id", ""))
	event.settlement_id = str(values.get("settlement_id", ""))
	event.origin = values.get("origin", Vector3.ZERO)
	event.radius = float(values.get("radius", 0.0))
	event.response_depth = int(values.get("response_depth", 0))
	event.response_kind = int(values.get("response_kind", C_INTENT.Kind.SOCIAL_DEFENSE))
	event.explicit_responder_actor_ids = PackedStringArray(values.get("explicit_responder_actor_ids", []))
	_world.add_entity(entity, [event])
	combat_event_emitted.emit(event_id, event.type)
	return event_id


func _tick_and_reindex_intents() -> void:
	_intent_entity_by_key.clear()
	_response_depth_by_pair.clear()
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
		var responder_entity = _world.get_entity_by_id("actor:%s" % str(intent.responder_actor_id))
		var responder_vitals = responder_entity.get_component(C_VITALS) if responder_entity != null else null
		var responder_config = responder_entity.get_component(C_CONFIG) if responder_entity != null else null
		if intent.remaining_ticks == 0 or responder_vitals == null or responder_config == null or int(responder_vitals.life_state) != NpcRules.LifeState.ALIVE or bool(responder_config.protected_from_combat):
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


func _index_intent(entity, intent) -> void:
	_intent_entity_by_key[_intent_key(int(intent.kind), str(intent.responder_actor_id), str(intent.target_actor_id), str(intent.authority_id))] = entity
	if int(intent.kind) == C_INTENT.Kind.SOCIAL_DEFENSE:
		_response_depth_by_pair[_actor_pair_key(str(intent.responder_actor_id), str(intent.target_actor_id))] = int(intent.response_depth)
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
		if int(intent.kind) == C_INTENT.Kind.SOCIAL_DEFENSE:
			_response_depth_by_pair.erase(_actor_pair_key(str(intent.responder_actor_id), str(intent.target_actor_id)))
		if not str(intent.authority_id).is_empty():
			_read_indexes_dirty = true
	_world.remove_entity(entity)


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


func _available_for_response(entry: Dictionary, reject_player_orders: bool) -> bool:
	var vitals = entry.get("vitals")
	var config = entry.get("config")
	var faction = entry.get("faction")
	if vitals == null or config == null or faction == null:
		return false
	if int(vitals.life_state) != NpcRules.LifeState.ALIVE or bool(config.protected_from_combat) or int(faction.combat_stance) == NpcRules.CombatStance.PASSIVE:
		return false
	return not reject_player_orders or not bool(faction.player_order_active)


func _has_social_obligation(responder: Dictionary, protected_entry: Dictionary) -> bool:
	var responder_faction = responder.get("faction")
	var protected_faction = protected_entry.get("faction")
	if responder_faction == null or protected_faction == null:
		return false
	var responder_party := str(responder_faction.party_id)
	var protected_party := str(protected_faction.party_id)
	if not responder_party.is_empty() and responder_party == protected_party:
		return true
	var responder_squad := str(responder_faction.squad_name)
	var protected_squad := str(protected_faction.squad_name)
	if not responder_squad.is_empty() and responder_squad == protected_squad:
		return true
	var responder_faction_id := str(responder_faction.faction_id)
	var protected_faction_id := str(protected_faction.faction_id)
	if not responder_faction_id.is_empty() and responder_faction_id == protected_faction_id:
		return true
	return _factions_are_allied_or_protected(responder_faction_id, protected_faction_id)


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


func _authority_target_key(authority_id: String, target_actor_id: String) -> String:
	return "%s|%s" % [authority_id, target_actor_id]


func _relation_key(left: String, right: String) -> String:
	var ids := [left, right]
	ids.sort()
	return "%s:%s" % [ids[0], ids[1]]


func _cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.z / CELL_SIZE))
