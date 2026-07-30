extends Node

class_name LawOrderController

const SERVICE_ID := &"law_order"

const MINUTES_PER_DAY := 24 * 60
const STOLEN_PROPERTY_DURATION_MINUTES := 10 * MINUTES_PER_DAY
const THEFT_WARRANT_DURATION_MINUTES := MINUTES_PER_DAY
const TRESPASS_WARRANT_DURATION_MINUTES := 12 * 60
const ASSAULT_WARRANT_DURATION_MINUTES := 3 * MINUTES_PER_DAY
const LOCKPICK_WARRANT_DURATION_MINUTES := 2 * MINUTES_PER_DAY
const MURDER_SENTENCE_MINUTES := 30 * MINUTES_PER_DAY
const THEFT_SENTENCE_MINUTES := 10 * 60
const TRESPASS_SENTENCE_MINUTES := 2 * 60
const ASSAULT_SENTENCE_MINUTES := 24 * 60
const LOCKPICK_SENTENCE_MINUTES := 12 * 60
const DEFAULT_WITNESS_RADIUS := 18.0
const SENTENCE_DECISION_MIN_DELAY_MINUTES := 120
const SENTENCE_DECISION_MAX_DELAY_MINUTES := 180
const FIXED_TICK_SECONDS := 0.25
const MAINTENANCE_INTERVAL_SECONDS := 0.5
const MAX_CATCH_UP_TICKS := 8
const MAX_ACTIVE_COMBAT_AGGRESSIONS_PER_MAINTENANCE := 32
const MAX_AUTHORITY_WITNESS_CANDIDATES := 64

const CRIME_THEFT := "theft"
const CRIME_TRESPASS := "trespass"
const CRIME_ASSAULT := "assault"
const CRIME_MURDER := "murder"
const CRIME_LOCKPICKING := "lockpicking"
const CRIME_ESCAPE := "escape"

var root_scene: Node
var _context: BootstrapContext
var hud_layer: CanvasLayer
var world_time: Node
var warrants: Dictionary = {}
var prisoner_records: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _process_accumulator := 0.0
var _maintenance_accumulator := 0.0
var _building_registry: BuildingRegistry
var _actor_query: ActorQueryController
var _crime_alerts: CrimeAlertController
var _combat_responses: GameCombatResponseSystem
var _occupied_buildings_by_actor: Dictionary = {}
var _active_trespass_by_actor: Dictionary = {}
var _combat_aggression_poll_cursor := 0


func _ready() -> void:
	add_to_group("law_order_controller")
	_rng.randomize()
	_connect_world_time()
	refresh_from_gecs_state()


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	hud_layer = context.hud_layer
	_context = context
	_building_registry = context.require(BuildingRegistry.SERVICE_ID) as BuildingRegistry
	_actor_query = context.require(ActorQueryController.SERVICE_ID) as ActorQueryController
	_crime_alerts = context.require(CrimeAlertController.SERVICE_ID) as CrimeAlertController
	_combat_responses = context.require(GameCombatResponseSystem.SERVICE_ID) as GameCombatResponseSystem
	var combat_started_callable := Callable(self, "_on_root_combat_started")
	if not _combat_responses.root_combat_started.is_connected(combat_started_callable):
		_combat_responses.root_combat_started.connect(combat_started_callable)
	_connect_world_time()
	refresh_from_gecs_state()


func get_current_settlement_id_for(target) -> String:
	var settlement := _find_containing_settlement(target)
	return _settlement_id(settlement)


func make_stolen_item_metadata(actor: WorldActor, source, owner_faction_id := "", settlement_id := "") -> Dictionary:
	if owner_faction_id.is_empty():
		owner_faction_id = _owner_faction_id(source)
	if settlement_id.is_empty():
		settlement_id = get_current_settlement_id_for(source if source != null else actor)
	var now := _now_minute()
	return {
		InventoryData.META_STOLEN: true,
		InventoryData.META_STOLEN_FROM_FACTION_ID: owner_faction_id,
		InventoryData.META_STOLEN_FROM_SETTLEMENT_ID: settlement_id,
		InventoryData.META_STOLEN_BY_ACTOR_ID: _actor_key(actor),
		InventoryData.META_STOLEN_AT_MINUTE: now,
		InventoryData.META_STOLEN_EXPIRES_AT_MINUTE: now + STOLEN_PROPERTY_DURATION_MINUTES,
	}


func report_theft_if_witnessed(actor: WorldActor, item, witnesses: Array = []) -> Dictionary:
	if actor == null or item == null:
		return {}
	var owner_faction := _owner_faction_id(item)
	if owner_faction.is_empty():
		return {}
	if witnesses.is_empty():
		witnesses = _find_witnesses(actor, item, owner_faction)
	if witnesses.is_empty():
		return {}
	var settlement := _find_containing_settlement(item)
	var settlement_id := get_current_settlement_id_for(item)
	var severity: int = max(1, _target_int(item, "get_theft_value", "theft_value", 10))
	# The warrant belongs to whoever polices the ground the theft happened on.
	# Facility owners (a barkeeper's civilian faction) field no soldiers, so a
	# warrant filed under them alerted nobody — the town's jurisdiction faction
	# is the one with guards and a jail. Outside any settlement, the owner
	# faction keeps the warrant (camps enforce their own property).
	var enforcing_faction := _settlement_faction_id(settlement)
	if enforcing_faction.is_empty():
		enforcing_faction = owner_faction
	return report_crime(actor, enforcing_faction, settlement_id, CRIME_THEFT, severity, witnesses[0], item)


func report_player_assault(attacker: HumanoidCharacter, victim: HumanoidCharacter) -> Dictionary:
	if attacker == null or victim == null or not attacker.is_player_party_member():
		return {}
	if victim.is_player_party_member():
		return {}
	var response_context: Dictionary = _combat_responses.get_response_context(_actor_key(attacker), _actor_key(victim)) if _combat_responses != null else {}
	if int(response_context.get("response_depth", 0)) > 0:
		return {}
	var settlement := _find_containing_settlement(victim)
	var faction_id := _settlement_faction_id(settlement)
	if faction_id.is_empty():
		faction_id = victim.faction_name.strip_edges()
	if faction_id.is_empty():
		return {}
	var public_witnesses := _find_local_authority_witnesses(attacker, victim, faction_id, settlement, NpcRules.NPC_ALERT_PROXIMITY_RADIUS)
	var witnesses: Array[WorldActor] = [victim]
	for witness in public_witnesses:
		if witness != null and not witnesses.has(witness):
			witnesses.append(witness)
	var lead_witness: WorldActor = public_witnesses[0] if not public_witnesses.is_empty() else victim
	return report_crime(attacker, faction_id, _settlement_id(settlement), CRIME_ASSAULT, 35, lead_witness, victim, {
		"public": not public_witnesses.is_empty(),
		"witnesses": witnesses,
		"provisional_victim_key": _actor_key(victim),
		"authority_alert_mode": "local",
		"local_alarm_position": victim.global_position,
		"local_alarm_radius": NpcRules.NPC_ALERT_PROXIMITY_RADIUS,
	})


func _on_root_combat_started(attacker_actor_id: String, protected_actor_id: String, origin: Vector3, _encounter_id: String) -> void:
	var attacker := _actor_query.get_actor_by_stable_id(attacker_actor_id) as WorldActor if _actor_query != null else null
	var victim := _actor_query.get_actor_by_stable_id(protected_actor_id) as WorldActor if _actor_query != null else null
	if attacker == null or victim == null:
		return
	var settlement := _find_containing_settlement(victim)
	var enforcing_faction := _settlement_faction_id(settlement)
	var settlement_id := _settlement_id(settlement)
	if enforcing_faction.is_empty() or settlement_id.is_empty():
		return
	if _has_assault_warrant_for_target(attacker, enforcing_faction, victim):
		return
	var witnesses := _find_local_authority_witnesses(attacker, victim, enforcing_faction, settlement, NpcRules.NPC_ALERT_PROXIMITY_RADIUS)
	if _is_law_soldier_responder(victim) and victim.faction_name == enforcing_faction and _is_law_actor_attached_to_settlement(victim, settlement):
		witnesses.append(victim)
	if witnesses.is_empty():
		return
	report_crime(attacker, enforcing_faction, settlement_id, CRIME_ASSAULT, 35, witnesses[0], victim, {
		"public": true,
		"witnesses": witnesses,
		"event_origin": origin,
		"authority_alert_mode": "local",
		"local_alarm_position": origin,
		"local_alarm_radius": NpcRules.NPC_ALERT_PROXIMITY_RADIUS,
	})


func _has_assault_warrant_for_target(attacker: WorldActor, enforcing_faction_id: String, victim: WorldActor) -> bool:
	var record := _get_mutable_warrant_record(attacker, enforcing_faction_id)
	if record.is_empty():
		return false
	var victim_key := _actor_key(victim)
	for crime_value in (record.get("crimes", []) as Array):
		var crime := crime_value as Dictionary
		if str(crime.get("crime_type", "")) == CRIME_ASSAULT and str(crime.get("target_key", "")) == victim_key:
			return true
	return false


func report_assault_if_witnessed(attacker: HumanoidCharacter, victim: HumanoidCharacter) -> Dictionary:
	if attacker == null or victim == null or not attacker.is_player_party_member():
		return {}
	if victim.is_player_party_member() or victim.has_hostility_with(attacker):
		return {}
	var faction_id := victim.faction_name
	if faction_id.is_empty():
		return {}
	var witnesses := _find_witnesses(attacker, victim, faction_id)
	if witnesses.is_empty():
		return {}
	return report_crime(attacker, faction_id, get_current_settlement_id_for(victim), CRIME_ASSAULT, 35, witnesses[0], victim, {
		"public": true,
		"witnesses": witnesses,
	})


func report_murder_if_witnessed(attacker: HumanoidCharacter, victim: HumanoidCharacter) -> Dictionary:
	if attacker == null or victim == null or not attacker.is_player_party_member():
		return {}
	if victim.is_player_party_member():
		return {}
	var faction_id := victim.faction_name
	if faction_id.is_empty():
		return {}
	var witnesses := _find_witnesses(attacker, victim, faction_id)
	var public_witnesses := _witnesses_excluding_actor(witnesses, victim)
	var has_public_case := _has_public_warrant_for_target(attacker, faction_id, victim)
	if witnesses.is_empty() and not has_public_case:
		return {}
	var lead_witness: WorldActor = public_witnesses[0] if not public_witnesses.is_empty() else victim
	var crime_context := {
		"public": not public_witnesses.is_empty() or has_public_case,
		"witnesses": witnesses,
		"provisional_victim_key": _actor_key(victim),
	}
	if public_witnesses.is_empty() and not has_public_case:
		crime_context["authority_alert_mode"] = "local"
		crime_context["local_alarm_position"] = victim.global_position
		crime_context["local_alarm_radius"] = NpcRules.NPC_ALERT_PROXIMITY_RADIUS
	crime_context.merge(_existing_local_alert_context(attacker, faction_id), true)
	return report_crime(attacker, faction_id, get_current_settlement_id_for(victim), CRIME_MURDER, 1000, lead_witness, victim, crime_context)


func report_lockpicking_if_witnessed(actor: HumanoidCharacter, target) -> Dictionary:
	if actor == null or target == null:
		return {}
	var faction_id := _owner_faction_id(target)
	if faction_id.is_empty():
		faction_id = _settlement_faction_id(_find_containing_settlement(target))
	if faction_id.is_empty():
		return {}
	var witnesses := _find_witnesses(actor, target, faction_id)
	if witnesses.is_empty():
		return {}
	return report_crime(actor, faction_id, get_current_settlement_id_for(target), CRIME_LOCKPICKING, 20, witnesses[0], target)


func report_crime(actor: WorldActor, faction_id: String, settlement_id: String, crime_type: String, severity: int, witness: WorldActor = null, target = null, crime_context: Dictionary = {}) -> Dictionary:
	if actor == null or faction_id.strip_edges().is_empty():
		return {}
	var actor_key := _actor_key(actor)
	var faction_key := faction_id.strip_edges()
	if not _crime_alerts.crime_is_illegal_for_faction(crime_type, faction_key):
		return {}
	var by_faction: Dictionary = warrants.get(actor_key, {})
	var is_new_record := not by_faction.has(faction_key)
	var record: Dictionary = by_faction.get(faction_key, _new_warrant(actor, faction_key, settlement_id))
	var witness_keys := _actor_keys_from_witnesses(crime_context.get("witnesses", []))
	if witness_keys.is_empty() and witness != null:
		witness_keys.append(_actor_key(witness))
	var is_public := bool(crime_context.get("public", true))
	var crime_record := {
		"crime_type": crime_type,
		"severity": max(1, severity),
		"settlement_id": settlement_id,
		"witness_key": _actor_key(witness),
		"witness_keys": witness_keys,
		"target_key": str(crime_context.get("target_key", _target_key(target))).strip_edges(),
		"public": is_public,
		"provisional_victim_key": str(crime_context.get("provisional_victim_key", "")),
		"absolute_minute": _now_minute(),
	}
	record["crimes"].append(crime_record)
	record["public_known"] = bool(record.get("public_known", false)) or is_public
	record["bad_person_points"] = int(record.get("bad_person_points", 0)) + int(crime_record["severity"])
	record["sentence_minutes"] = int(record.get("sentence_minutes", 0)) + _sentence_minutes_for(crime_type, int(crime_record["severity"]))
	record["warrant_expires_at_minute"] = _merged_warrant_expiry(record, crime_type)
	if settlement_id.strip_edges() != "":
		record["settlement_id"] = settlement_id
	record["state"] = "wanted"
	_configure_authority_alert_context(record, crime_context, is_new_record)
	var crime_event := _crime_alerts.create_event(actor, faction_key, settlement_id, crime_type, int(crime_record["severity"]), witness, crime_context)
	record["latest_event_id"] = str(crime_event.get("event_id", ""))
	record["latest_witness_actor_id"] = str(crime_event.get("witness_actor_id", ""))
	record["latest_alert_origin"] = crime_event.get("origin", actor.global_position)
	record["latest_alert_radius"] = float(crime_event.get("radius", NpcRules.NPC_ALERT_PROXIMITY_RADIUS))
	by_faction[faction_key] = record
	warrants[actor_key] = by_faction
	_apply_actor_law_meta(actor, record)
	_save_law_order_state_to_gecs()
	if witness != null and witness.has_method("show_world_speech"):
		witness.show_world_speech(_crime_alarm_line(crime_type), 4.0)
	_alert_authority_guards(actor, record)
	var brain := _get_gecs_world()
	if brain != null and brain.has_method("log_world_event"):
		brain.log_world_event("law", "%s: %s sev=%d @ %s" % [actor_key, crime_type, int(crime_record["severity"]), settlement_id], record)
	return record


func handle_actor_death(actor: WorldActor) -> void:
	if actor == null:
		return
	_prune_victim_only_crimes_for_dead_actor(actor)
	_save_law_order_state_to_gecs()


func actor_has_active_warrant(actor: WorldActor, faction_id := "") -> bool:
	if actor == null:
		return false
	var by_faction: Dictionary = warrants.get(_actor_key(actor), {})
	if faction_id.is_empty():
		return not by_faction.is_empty()
	return by_faction.has(faction_id)


func can_sell_entry_to_merchant(seller: HumanoidCharacter, merchant_owner, entry) -> bool:
	if entry == null or not bool(entry.metadata.get(InventoryData.META_STOLEN, false)):
		return true
	var stolen_settlement := str(entry.metadata.get(InventoryData.META_STOLEN_FROM_SETTLEMENT_ID, ""))
	if stolen_settlement.is_empty():
		return true
	var merchant_settlement := get_current_settlement_id_for(merchant_owner)
	if merchant_settlement != stolen_settlement:
		return true
	var faction_id := str(entry.metadata.get(InventoryData.META_STOLEN_FROM_FACTION_ID, ""))
	if not faction_id.is_empty():
		report_crime(seller, faction_id, stolen_settlement, CRIME_THEFT, 10, _find_nearest_authority_witness(seller, faction_id), merchant_owner)
	return false


func get_warrant_record(actor: WorldActor, faction_id: String) -> Dictionary:
	if actor == null:
		return {}
	return (warrants.get(_actor_key(actor), {}) as Dictionary).get(faction_id, {}).duplicate(true)


func serialize_state() -> Dictionary:
	_save_law_order_state_to_gecs()
	return _current_law_order_state()


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty():
		refresh_from_gecs_state()
		return
	warrants = (state.get("warrants", {}) as Dictionary).duplicate(true)
	prisoner_records = (state.get("prisoner_records", {}) as Dictionary).duplicate(true)
	_apply_loaded_law_meta()
	_save_law_order_state_to_gecs()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_law_order_state"):
		return
	var state: Dictionary = bridge.call("get_law_order_state")
	if state.is_empty():
		return
	warrants = (state.get("warrants", {}) as Dictionary).duplicate(true)
	prisoner_records = (state.get("prisoner_records", {}) as Dictionary).duplicate(true)
	_apply_loaded_law_meta()


func sync_law_order_state() -> void:
	_save_law_order_state_to_gecs()


func _get_mutable_warrant_record(actor: WorldActor, faction_id: String) -> Dictionary:
	if actor == null:
		return {}
	return (warrants.get(_actor_key(actor), {}) as Dictionary).get(faction_id, {})


func complete_custody_if_placed(actor: WorldActor) -> bool:
	if actor == null:
		return false
	var actor_key := _actor_key(actor)
	var by_faction: Dictionary = warrants.get(actor_key, {})
	for faction_id in by_faction.keys():
		var record: Dictionary = by_faction[faction_id]
		if str(record.get("state", "wanted")) != "custody":
			continue
		var jail := _find_jail_by_id(str(record.get("custody_jail_id", "")))
		if jail == null:
			jail = _find_jail_for_settlement(_find_settlement_for_warrant(actor, record))
		if jail != null and jail.has_method("admit_prisoner") and bool(jail.call("admit_prisoner", actor, record, self)):
			_complete_jailing(actor, record, jail)
			by_faction[faction_id] = record
			warrants[actor_key] = by_faction
			_save_law_order_state_to_gecs()
			return true
	return false


func _process(delta: float) -> void:
	_process_accumulator = minf(_process_accumulator + delta, FIXED_TICK_SECONDS * MAX_CATCH_UP_TICKS)
	var ticks := 0
	while _process_accumulator >= FIXED_TICK_SECONDS and ticks < MAX_CATCH_UP_TICKS:
		_process_accumulator -= FIXED_TICK_SECONDS
		_process_fixed_tick()
		ticks += 1


func update_actor_building_occupancy(actor_id: String, building_ids: Array[String]) -> void:
	var clean_actor_id := actor_id.strip_edges()
	if clean_actor_id.is_empty():
		return
	var previous: Dictionary = _occupied_buildings_by_actor.get(clean_actor_id, {})
	var current: Dictionary = {}
	for building_id in building_ids:
		var clean_building_id := building_id.strip_edges()
		if not clean_building_id.is_empty():
			current[clean_building_id] = true
	for building_id in previous:
		if not current.has(building_id):
			_remove_trespass_pair(clean_actor_id, str(building_id))
	for building_id in current:
		if not previous.has(building_id):
			_get_or_create_trespass_pair(clean_actor_id, str(building_id))
	if current.is_empty():
		_occupied_buildings_by_actor.erase(clean_actor_id)
	else:
		_occupied_buildings_by_actor[clean_actor_id] = current


func _process_fixed_tick() -> void:
	_process_active_trespass_pairs()
	_crime_alerts.advance(FIXED_TICK_SECONDS)
	_maintenance_accumulator += FIXED_TICK_SECONDS
	if _maintenance_accumulator < MAINTENANCE_INTERVAL_SECONDS:
		return
	_maintenance_accumulator -= MAINTENANCE_INTERVAL_SECONDS
	_process_active_combat_aggressions()
	_process_warrants()
	_process_prisoners()
	_save_law_order_state_to_gecs()


func _process_active_combat_aggressions() -> void:
	if _combat_responses == null:
		return
	var aggressions := _combat_responses.get_active_root_aggressions()
	if aggressions.is_empty():
		_combat_aggression_poll_cursor = 0
		return
	var poll_count := mini(aggressions.size(), MAX_ACTIVE_COMBAT_AGGRESSIONS_PER_MAINTENANCE)
	var start_index := _combat_aggression_poll_cursor % aggressions.size()
	for offset in range(poll_count):
		var aggression: Dictionary = aggressions[(start_index + offset) % aggressions.size()]
		_on_root_combat_started(str(aggression.get("attacker_actor_id", "")), str(aggression.get("protected_actor_id", "")), aggression.get("origin", Vector3.ZERO), str(aggression.get("encounter_id", "")))
	_combat_aggression_poll_cursor = (start_index + poll_count) % aggressions.size()


func _process_active_trespass_pairs() -> void:
	if _building_registry == null or _actor_query == null:
		return
	for actor_id in _active_trespass_by_actor.keys():
		var actor := _actor_query.get_actor_by_stable_id(str(actor_id)) as WorldActor
		if actor == null:
			continue
		var pairs: Dictionary = _active_trespass_by_actor.get(actor_id, {})
		for building_id in pairs.keys():
			var record := _building_registry.get_building(str(building_id))
			if record.is_empty() or not _is_actor_trespassing_in_record(actor, record):
				_reset_trespass_pair(actor, str(building_id), pairs)
				continue
			_clear_active_trespass_display(actor, str(building_id))
			var state: Dictionary = pairs[building_id]
			if bool(state.get("escalated", false)):
				continue
			var remaining := float(state.get("seconds_until_warning", 0.0)) - FIXED_TICK_SECONDS
			if remaining <= 0.0:
				_issue_trespass_response(actor, record, state)
			else:
				state["seconds_until_warning"] = remaining
			pairs[building_id] = state
		_active_trespass_by_actor[actor_id] = pairs


func _is_actor_trespassing_in_record(actor: WorldActor, record: Dictionary) -> bool:
	if actor == null or actor.life_state != NpcRules.LifeState.ALIVE or not actor.is_player_party_member():
		return false
	if bool(record.get("abandoned", false)):
		return false
	var access_state := str(record.get("access_state", "public")).strip_edges().to_lower()
	var private_now := access_state in ["private", "occupied"]
	if access_state == "scheduled" and bool(record.get("public_schedule_enabled", true)):
		private_now = not _is_building_schedule_open(record)
	if not private_now:
		return false
	if str(record.get("type_id", "")).strip_edges() == "housing" or int(record.get("housing_capacity", 0)) > 0:
		return not _residence_actor_ids_for_building(record).has(_actor_key(actor))
	var actor_faction := actor.faction_name.strip_edges()
	var owner_faction := str(record.get("owner_faction_id", "")).strip_edges()
	if not owner_faction.is_empty():
		return actor_faction != owner_faction
	var jurisdiction_faction := str(record.get("jurisdiction_faction_id", "")).strip_edges()
	return jurisdiction_faction.is_empty() or actor_faction != jurisdiction_faction


func _is_building_schedule_open(record: Dictionary) -> bool:
	var open_hour := clampi(int(record.get("public_open_hour", 8)), 0, 23)
	var close_hour := clampi(int(record.get("public_close_hour", 21)), 0, 23)
	if open_hour == close_hour:
		return true
	var hour := _world_hour()
	if open_hour < close_hour:
		return hour >= open_hour and hour < close_hour
	return hour >= open_hour or hour < close_hour


func _world_hour() -> int:
	if world_time != null and world_time.has_method("get_hour"):
		return int(world_time.call("get_hour"))
	return int(floor(fposmod(float(_now_minute()), float(MINUTES_PER_DAY)) / 60.0))


func _issue_trespass_response(actor: WorldActor, record: Dictionary, state: Dictionary) -> void:
	var witness := _find_trespass_witness(actor, record)
	if witness == null:
		state["seconds_until_warning"] = maxf(0.0, float(record.get("trespass_warning_interval_seconds", 3.0)))
		return
	var warning_count := int(state.get("warning_count", 0))
	var warnings_before_alarm := maxi(0, int(record.get("trespass_warnings_before_alarm", 2)))
	if warning_count < warnings_before_alarm:
		_face_witness_toward_actor(witness, actor)
		var warning_line := "Leave my home." if str(record.get("type_id", "")) == "housing" else "Leave this property."
		witness.show_world_speech(warning_line, 3.0)
		state["warning_count"] = warning_count + 1
		state["seconds_until_warning"] = maxf(0.0, float(record.get("trespass_warning_interval_seconds", 3.0)))
		return
	state["escalated"] = true
	state["seconds_until_warning"] = maxf(0.0, float(record.get("trespass_warning_interval_seconds", 3.0)))
	var escalation := str(record.get("trespass_escalation", "settlement_alarm")).strip_edges().to_lower()
	_start_home_defense(witness, actor, state, str(record.get("building_id", "")))
	if escalation == "warning_only":
		return
	if escalation == "victim_only":
		if witness != null and witness != actor:
			witness.show_world_speech(_crime_alarm_line(CRIME_TRESPASS), 4.0)
		return
	_report_stable_id_trespass(actor, record, witness)


func _find_trespass_witness(actor: WorldActor, record: Dictionary) -> WorldActor:
	if actor == null or _actor_query == null:
		return null
	var resident_actor_ids := _residence_actor_ids_for_building(record)
	if not resident_actor_ids.is_empty():
		return _nearest_detecting_trespass_witness(actor, record, resident_actor_ids)
	var owner_faction := str(record.get("owner_faction_id", "")).strip_edges()
	var jurisdiction_faction := str(record.get("jurisdiction_faction_id", "")).strip_edges()
	if owner_faction.is_empty() and jurisdiction_faction.is_empty():
		return null
	var radius := maxf(0.0, float(record.get("trespass_notice_radius", 18.0)))
	var perception := _get_perception_controller()
	var candidate_actor_ids := PackedStringArray()
	for nearby in _actor_query.get_nearby_actors(actor.global_position, radius, true):
		var witness := nearby as WorldActor
		if witness == null or witness == actor or witness.life_state != NpcRules.LifeState.ALIVE or witness.is_player_party_member():
			continue
		if witness.faction_name != owner_faction and witness.faction_name != jurisdiction_faction:
			continue
		candidate_actor_ids.append(_actor_key(witness))
	return _nearest_detecting_trespass_witness(actor, record, candidate_actor_ids, perception)


func _residence_actor_ids_for_building(record: Dictionary) -> PackedStringArray:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_assignment_slots"):
		return PackedStringArray()
	var building_id := str(record.get("building_id", ""))
	var actor_ids := PackedStringArray()
	for slot_value in bridge.call("get_assignment_slots", str(record.get("settlement_id", "")), "residence"):
		var slot: Dictionary = slot_value
		if str(slot.get("building_id", "")) != building_id:
			continue
		var actor_id := str(slot.get("occupant_actor_id", "")).strip_edges()
		if not actor_id.is_empty():
			actor_ids.append(actor_id)
	return actor_ids


func _nearest_detecting_trespass_witness(actor: WorldActor, record: Dictionary, actor_ids: PackedStringArray, perception: Node = null) -> WorldActor:
	if perception == null:
		perception = _get_perception_controller()
	var radius_squared := pow(maxf(0.0, float(record.get("trespass_notice_radius", 18.0))), 2.0)
	var nearest: WorldActor
	var nearest_distance := INF
	for actor_id in actor_ids:
		var witness := _actor_query.get_actor_by_stable_id(actor_id) as WorldActor
		if witness == null or witness == actor or witness.life_state != NpcRules.LifeState.ALIVE or witness.is_player_party_member():
			continue
		var distance := witness.global_position.distance_squared_to(actor.global_position)
		if distance > radius_squared:
			continue
		if perception != null and perception.has_method("evaluate_observer"):
			var result := perception.call("evaluate_observer", witness, actor) as Dictionary
			var detected := bool(result.get("clearly_seen", false))
			if not actor.sneaking:
				detected = float(result.get("line_of_sight_fraction", 0.0)) > 0.0
			if not detected:
				continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = witness
	return nearest


func _face_witness_toward_actor(witness: WorldActor, actor: WorldActor) -> void:
	var target_position := Vector3(actor.global_position.x, witness.global_position.y, actor.global_position.z)
	if witness.global_position.distance_squared_to(target_position) <= 0.001:
		return
	witness.look_at(target_position, Vector3.UP)
	witness.rotation.x = 0.0
	witness.rotation.z = 0.0


func _report_stable_id_trespass(actor: WorldActor, record: Dictionary, witness: WorldActor) -> Dictionary:
	if actor == null or witness == null:
		return {}
	var faction_id := str(record.get("jurisdiction_faction_id", "")).strip_edges()
	if faction_id.is_empty():
		faction_id = str(record.get("owner_faction_id", "")).strip_edges()
	if faction_id.is_empty():
		return {}
	return report_crime(actor, faction_id, str(record.get("settlement_id", "")), CRIME_TRESPASS, 5, witness, null, {
		"target_key": str(record.get("building_id", "")),
		"event_origin": actor.global_position,
	})


func _start_home_defense(witness: WorldActor, actor: WorldActor, state: Dictionary, building_id: String) -> void:
	if witness == null or actor == null:
		return
	var interaction = witness.get_interaction() if witness.has_method("get_interaction") else null
	if interaction != null:
		interaction.stop_seat_assignment()
		interaction.stop_sleep_assignment()
	var witness_id := _actor_key(witness)
	var target_id := _actor_key(actor)
	var authority_id := "home|%s|%s" % [building_id, witness_id]
	state["witness_actor_id"] = witness_id
	state["target_actor_id"] = target_id
	state["response_authority_id"] = authority_id
	if _combat_responses != null:
		_combat_responses.authorize_response(CGameCombatEvent.Audience.EXPLICIT_ACTORS, target_id, witness_id, authority_id, "", "", actor.global_position, NpcRules.NPC_ALERT_PROXIMITY_RADIUS, CGameCombatResponseIntent.Kind.PRIVATE_DEFENSE, PackedStringArray([witness_id]))


func _clear_home_defense(state: Dictionary, actor: WorldActor) -> void:
	var witness_id := str(state.get("witness_actor_id", ""))
	var target_id := str(state.get("target_actor_id", _actor_key(actor)))
	var authority_id := str(state.get("response_authority_id", ""))
	if _combat_responses != null and not authority_id.is_empty():
		_combat_responses.revoke_response(authority_id, target_id)
	var witness := _actor_query.get_actor_by_stable_id(witness_id) as WorldActor if _actor_query != null and not witness_id.is_empty() else null
	if witness != null and actor != null:
		witness.clear_personal_hostility(actor)


func _get_or_create_trespass_pair(actor_id: String, building_id: String) -> Dictionary:
	var pairs: Dictionary = _active_trespass_by_actor.get(actor_id, {})
	if not pairs.has(building_id):
		pairs[building_id] = _new_trespass_pair_state()
		_active_trespass_by_actor[actor_id] = pairs
	return pairs[building_id]


func _new_trespass_pair_state() -> Dictionary:
	return {
		"warning_count": 0,
		"seconds_until_warning": 0.0,
		"escalated": false,
		"witness_actor_id": "",
	}


func _reset_trespass_pair(actor: WorldActor, building_id: String, pairs: Dictionary) -> void:
	_clear_home_defense(pairs.get(building_id, {}) as Dictionary, actor)
	pairs[building_id] = _new_trespass_pair_state()
	_clear_active_trespass_display(actor, building_id)


func _remove_trespass_pair(actor_id: String, building_id: String) -> void:
	var pairs: Dictionary = _active_trespass_by_actor.get(actor_id, {})
	var actor := _actor_query.get_actor_by_stable_id(actor_id) as WorldActor if _actor_query != null else null
	_clear_home_defense(pairs.get(building_id, {}) as Dictionary, actor)
	pairs.erase(building_id)
	if pairs.is_empty():
		_active_trespass_by_actor.erase(actor_id)
	else:
		_active_trespass_by_actor[actor_id] = pairs
	_clear_active_trespass_display(actor, building_id)


func _clear_active_trespass_display(actor: WorldActor, building_id: String) -> void:
	if actor == null:
		return
	var status := actor.get_legal_status()
	if status.active_crime_source_key == building_id:
		status.clear_active_crime()


func _on_minute_changed(absolute_minute: int, _day_index: int, _hour: int, _minute: int) -> void:
	_clear_expired_warrants(absolute_minute)
	_clear_expired_stolen_items(absolute_minute)
	_process_prisoners()
	_save_law_order_state_to_gecs()


func _process_warrants() -> void:
	for actor_key in warrants.keys():
		var actor := _find_actor_by_key(str(actor_key))
		if actor == null:
			continue
		var by_faction: Dictionary = warrants.get(actor_key, {})
		for faction_id in by_faction.keys():
			var record: Dictionary = by_faction[faction_id]
			if str(record.get("state", "wanted")) == "jailed":
				continue
			if str(record.get("state", "wanted")) == "custody":
				_process_custody(actor, record)
				by_faction[faction_id] = record
				continue
			if _actor_is_downed(actor):
				var downed_humanoid := actor as HumanoidCharacter
				if downed_humanoid != null:
					_arrest_or_eject(downed_humanoid, record)
				else:
					_disengage_authority_guards(actor, record)
				by_faction[faction_id] = record
				continue
			if actor.life_state != NpcRules.LifeState.ALIVE:
				continue
			var settlement := _find_settlement_for_warrant(actor, record)
			var in_authority_scope := _should_alert_authority_guards(actor, record, settlement)
			var response_active := _has_active_authority_arrest_response(actor, record, settlement)
			if in_authority_scope and not response_active:
				_alert_authority_guards(actor, record)
			elif not in_authority_scope and response_active:
				_disengage_authority_guards(actor, record)


func _process_prisoners() -> void:
	var now := _now_minute()
	for prisoner_key in prisoner_records.keys():
		var record: Dictionary = prisoner_records[prisoner_key]
		var actor := _find_actor_by_key(str(prisoner_key))
		if actor == null:
			continue
		var jail := _find_jail_by_id(str(record.get("jail_id", "")))
		if jail == null:
			jail = _find_jail_for_settlement(_find_settlement_for_warrant(actor, record))
		if str(record.get("state", "")) == "jailed" and not bool(record.get("sentence_decision_given", false)) and now >= int(record.get("sentence_decision_at_minute", now)):
			record = _decide_prisoner_sentence(actor, record, now)
			prisoner_records[prisoner_key] = record
		if str(record.get("state", "")) == "jailed" and bool(record.get("sentence_notification_pending", false)) and actor.life_state == NpcRules.LifeState.ALIVE:
			record = _request_prisoner_sentence_notification(actor, record, jail)
			prisoner_records[prisoner_key] = record
		if str(record.get("state", "")) == "jailed":
			_apply_actor_law_meta(actor, record)
			# After an actor LOD-realizes, its fresh node is not in cell custody;
			# re-seat it into the cell recorded in GECS truth (prisoner_records).
			if jail != null and jail.has_method("restore_prisoner_to_cell") and not actor.is_in_cell_custody():
				jail.call("restore_prisoner_to_cell", actor, record)
		var release_at := int(record.get("release_at_minute", -1))
		if release_at >= 0 and now >= release_at:
			_release_prisoner(actor, record, jail)


func register_offscreen_prisoner(actor_id: String, settlement_id: String, faction_id: String) -> void:
	if actor_id.is_empty() or settlement_id.is_empty() or prisoner_records.has(actor_id):
		return
	prisoner_records[actor_id] = {
		"state": "jailed",
		"actor_key": actor_id,
		"settlement_id": settlement_id,
		"faction_id": faction_id,
		"jail_id": "",
		"cell_id": "",
		"release_at_minute": -1,
		"sentence_decision_at_minute": _now_minute() + _sentence_decision_delay_minutes(),
		"sentence_decision_given": false,
		"sentence_notification_given": false,
		"sentence_notification_pending": false,
		"sentence_notification_requested": false,
		"crimes": [{"crime_type": "war_capture", "severity": 0}],
	}
	_save_law_order_state_to_gecs()


func _arrest_or_eject(actor: HumanoidCharacter, warrant: Dictionary) -> void:
	var settlement := _find_settlement_for_warrant(actor, warrant)
	var jail := _find_jail_for_settlement(settlement)
	if jail != null:
		warrant["state"] = "custody"
		warrant["custody_jail_id"] = str(jail.call("get_facility_id")) if jail.has_method("get_facility_id") else str(jail.name)
		_process_custody(actor, warrant)
		return
	_eject_actor_from_town(actor, settlement)
	_clear_warrant_for_actor(actor, str(warrant.get("faction_id", "")))


func _process_custody(actor: WorldActor, warrant: Dictionary) -> void:
	if actor == null:
		return
	var settlement := _find_settlement_for_warrant(actor, warrant)
	var jail := _find_jail_by_id(str(warrant.get("custody_jail_id", "")))
	if jail == null:
		jail = _find_jail_for_settlement(settlement)
	if jail == null:
		return
	if actor.life_state == NpcRules.LifeState.DEAD:
		if jail.has_method("release_cell_reservation"):
			jail.call("release_cell_reservation", actor)
		return
	if jail.has_method("admit_prisoner") and bool(jail.call("admit_prisoner", actor, warrant, self)):
		_complete_jailing(actor, warrant, jail)
		return
	if actor.life_state == NpcRules.LifeState.ALIVE:
		if jail.has_method("release_cell_reservation"):
			jail.call("release_cell_reservation", actor)
		warrant["state"] = "wanted"
		_alert_authority_guards(actor, warrant)
		return
	if not actor.is_downed_state() or not (actor is HumanoidCharacter):
		return
	var humanoid_actor := actor as HumanoidCharacter
	var guard := _find_custody_guard(actor, warrant, settlement)
	if guard == null:
		return
	var cell_reference: Node = guard if guard.get_carried_character() == humanoid_actor else actor
	var cell = jail.call("get_reserved_or_available_cell", actor, cell_reference) if jail.has_method("get_reserved_or_available_cell") else (jail.call("get_available_cell", actor, cell_reference) if jail.has_method("get_available_cell") else null)
	if cell == null:
		return
	warrant["custody_guard_key"] = _actor_key(guard)
	_disengage_authority_guards(actor, warrant)
	if guard.get_carried_character() == humanoid_actor:
		# Don't re-issue while a placement is already running: get_available_cell
		# picks the cell nearest the MOVING guard, so re-assigning every tick
		# flip-flops the target cell and the hauler oscillates at the jail door.
		var guard_interaction := guard.get_interaction()
		if guard_interaction != null and guard_interaction.current_order_type == InteractionCapability.ORDER_TYPE_PLACE_IN_CELL 				and guard_interaction.current_place_cell_target != null and is_instance_valid(guard_interaction.current_place_cell_target):
			return
		guard.assign_place_carried_in_cell_target(cell, false)
		return
	if not humanoid_actor.is_carried() and guard.get_carried_character() == null:
		guard.assign_carry_target(humanoid_actor, false)


func _complete_jailing(actor: WorldActor, warrant: Dictionary, jail: Node) -> void:
	var prisoner_key := _actor_key(actor)
	var prisoner_record := warrant.duplicate(true)
	prisoner_record["state"] = "jailed"
	prisoner_record["actor_key"] = prisoner_key
	prisoner_record["jail_id"] = str(jail.call("get_facility_id")) if jail.has_method("get_facility_id") else str(jail.name)
	prisoner_record["cell_id"] = str(actor.get_legal_status().cell_id)
	prisoner_record["release_at_minute"] = -1
	prisoner_record["sentence_decision_at_minute"] = _now_minute() + _sentence_decision_delay_minutes()
	prisoner_record["sentence_decision_given"] = false
	prisoner_record["sentence_notification_given"] = false
	prisoner_record["sentence_notification_pending"] = false
	prisoner_record["sentence_notification_requested"] = false
	prisoner_records[prisoner_key] = prisoner_record
	warrant["state"] = "jailed"
	_apply_actor_law_meta(actor, prisoner_record)
	_save_law_order_state_to_gecs()
	var custody_guard := _find_actor_by_key(str(warrant.get("custody_guard_key", ""))) as HumanoidCharacter
	_disengage_authority_guards(actor, warrant)
	_disengage_authority_guards_from_each_other(warrant)
	_clear_custody_actor_hostility(actor, warrant)
	_assign_custody_guard_return(custody_guard, jail)


func register_prisoner_locker_transfer(actor: WorldActor, _locker, warrant: Dictionary) -> Dictionary:
	return {
		"prisoner_key": _actor_key(actor),
		"case_id": str(warrant.get("case_id", "%s:%d" % [_actor_key(actor), _now_minute()])),
		"absolute_minute": _now_minute(),
	}


func complete_prisoner_sentence_delivery(actor: WorldActor) -> bool:
	if actor == null:
		return false
	var prisoner_key := _actor_key(actor)
	if not prisoner_records.has(prisoner_key):
		return false
	var record: Dictionary = prisoner_records[prisoner_key]
	if str(record.get("state", "")) != "jailed":
		return false
	if bool(record.get("sentence_notification_given", false)):
		return true
	record["sentence_notification_requested"] = false
	record["sentence_notification_pending"] = false
	record["sentence_notification_given"] = true
	prisoner_records[prisoner_key] = record
	_apply_actor_law_meta(actor, record)
	_save_law_order_state_to_gecs()
	return true


func has_pending_prisoner_sentence_notification(actor: WorldActor) -> bool:
	if actor == null:
		return false
	var prisoner_key := _actor_key(actor)
	if not prisoner_records.has(prisoner_key):
		return false
	var record: Dictionary = prisoner_records[prisoner_key]
	return str(record.get("state", "")) == "jailed" and bool(record.get("sentence_notification_pending", false)) and not bool(record.get("sentence_notification_given", false))


func _decide_prisoner_sentence(actor: WorldActor, record: Dictionary, now: int) -> Dictionary:
	record["sentence_decision_given"] = true
	record["sentence_started_at_minute"] = now
	record["release_at_minute"] = now + max(1, int(record.get("sentence_minutes", THEFT_SENTENCE_MINUTES)))
	record["sentence_notification_pending"] = true
	record["sentence_notification_requested"] = false
	record["sentence_notification_given"] = false
	_apply_actor_law_meta(actor, record)
	return record


func _request_prisoner_sentence_notification(actor: WorldActor, record: Dictionary, jail: Node) -> Dictionary:
	if not (actor is HumanoidCharacter):
		record["sentence_notification_pending"] = false
		record["sentence_notification_requested"] = false
		record["sentence_notification_given"] = true
		return record
	if jail == null or not jail.has_method("tell_prisoner_sentence"):
		record["sentence_notification_requested"] = false
		return record
	record["sentence_notification_requested"] = bool(jail.call("tell_prisoner_sentence", actor, record))
	return record


## Bail: a party member buys jailed companions out at the warden. Cost
## scales with each prisoner's crime severity; paying releases every jailed
## player-party member held in that jail through the standard release flow
## (locker items restored, warrant cleared).
const BAIL_SILVER_ITEM = preload("res://features/inventory/resources/items/silver.tres")
const BAIL_BASE_COST := 10
const BAIL_COST_PER_SEVERITY := 2


func get_bailable_prisoners(payer: WorldActor, jail: Node) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if payer == null or jail == null or not jail.has_method("get_facility_id"):
		return results
	if not payer.is_player_party_member():
		return results
	var jail_id := str(jail.call("get_facility_id"))
	for prisoner_key in prisoner_records.keys():
		var record: Dictionary = prisoner_records[prisoner_key]
		if str(record.get("state", "")) != "jailed" or str(record.get("jail_id", "")) != jail_id:
			continue
		var prisoner := _find_actor_by_key(str(prisoner_key))
		if prisoner == null or prisoner == payer:
			continue
		if not (prisoner.has_method("is_player_party_member") and bool(prisoner.call("is_player_party_member"))):
			continue
		results.append({"actor": prisoner, "record": record})
	return results


func get_bail_cost(payer: WorldActor, jail: Node) -> int:
	var total := 0
	for entry in get_bailable_prisoners(payer, jail):
		total += BAIL_BASE_COST + BAIL_COST_PER_SEVERITY * int((entry["record"] as Dictionary).get("severity", 1))
	return total


func can_pay_bail(payer: WorldActor, jail: Node) -> bool:
	var cost := get_bail_cost(payer, jail)
	return cost > 0 and payer != null and payer.inventory != null and payer.inventory.count_item(BAIL_SILVER_ITEM) >= cost


func pay_bail(payer: WorldActor, jail: Node) -> bool:
	var bailable := get_bailable_prisoners(payer, jail)
	if bailable.is_empty():
		return false
	var cost := get_bail_cost(payer, jail)
	if payer == null or payer.inventory == null or not payer.inventory.remove_item_count(BAIL_SILVER_ITEM, cost):
		return false
	for entry in bailable:
		_release_prisoner(entry["actor"] as WorldActor, entry["record"] as Dictionary, jail)
	return true


func _release_prisoner(actor: WorldActor, record: Dictionary, jail) -> void:
	if jail != null and jail.has_method("release_prisoner"):
		jail.call("release_prisoner", actor, record, false)
	_clear_warrant_for_actor(actor, str(record.get("faction_id", "")))
	prisoner_records.erase(_actor_key(actor))
	var status := actor.get_legal_status()
	status.clear_prisoner()
	status.clear_warrant_display()
	_save_law_order_state_to_gecs()


func _alert_authority_guards(actor: WorldActor, warrant: Dictionary) -> void:
	if actor == null or actor.life_state != NpcRules.LifeState.ALIVE:
		return
	if _combat_responses == null:
		return
	var authority_id := _warrant_response_authority_id(actor, warrant)
	warrant["response_authority_id"] = authority_id
	var origin: Vector3 = warrant.get("latest_alert_origin", warrant.get("local_alarm_position", actor.global_position))
	var radius := float(warrant.get("latest_alert_radius", NpcRules.NPC_ALERT_PROXIMITY_RADIUS))
	warrant["latest_response_event_id"] = _combat_responses.authorize_response(CGameCombatEvent.Audience.SETTLEMENT_AUTHORITY, _actor_key(actor), str(warrant.get("latest_witness_actor_id", "")), authority_id, str(warrant.get("faction_id", "")), str(warrant.get("settlement_id", "")), origin, radius, CGameCombatResponseIntent.Kind.LAW_ENFORCEMENT)


func _disengage_authority_guards(actor: WorldActor, warrant: Dictionary) -> void:
	if actor == null:
		return
	var authority_id := str(warrant.get("response_authority_id", _warrant_response_authority_id(actor, warrant)))
	var responder_ids: PackedStringArray = _combat_responses.get_active_responder_ids(authority_id) if _combat_responses != null else PackedStringArray()
	if _combat_responses != null:
		_combat_responses.revoke_response(authority_id, _actor_key(actor))
	for guard_id in responder_ids:
		var guard := _actor_query.get_actor_by_stable_id(guard_id) as WorldActor if _actor_query != null else null
		if guard == null:
			continue
		if guard.has_method("disengage_combat_with"):
			guard.call("disengage_combat_with", actor)
		elif guard.has_method("clear_personal_hostility"):
			guard.clear_personal_hostility(actor)
		if actor.has_method("disengage_combat_with"):
			actor.call("disengage_combat_with", guard)
		elif actor.has_method("clear_personal_hostility"):
			actor.clear_personal_hostility(guard)


func _should_alert_authority_guards(actor: WorldActor, _warrant: Dictionary, settlement: Node) -> bool:
	if actor == null or settlement == null:
		return false
	if settlement.has_method("contains_town_border_position"):
		return bool(settlement.call("contains_town_border_position", actor.global_position))
	return true


func _has_active_authority_arrest_response(actor: WorldActor, warrant: Dictionary, settlement: Node) -> bool:
	if actor == null or settlement == null:
		return false
	var authority_id := str(warrant.get("response_authority_id", _warrant_response_authority_id(actor, warrant)))
	return _combat_responses != null and _combat_responses.has_active_authority_response(authority_id, _actor_key(actor))


func _actor_is_downed(actor: WorldActor) -> bool:
	return actor != null and actor.has_method("is_downed_state") and bool(actor.call("is_downed_state"))


func _disengage_authority_guards_from_each_other(warrant: Dictionary) -> void:
	var guards := _find_authority_guards(str(warrant.get("faction_id", "")), _find_settlement_by_id(str(warrant.get("settlement_id", ""))), true)
	for left_index in range(guards.size()):
		var left := guards[left_index]
		if left == null:
			continue
		for right_index in range(left_index + 1, guards.size()):
			var right := guards[right_index]
			if right == null:
				continue
			if left.has_method("disengage_combat_with"):
				left.call("disengage_combat_with", right)
			if right.has_method("disengage_combat_with"):
				right.call("disengage_combat_with", left)


func _clear_custody_actor_hostility(actor: WorldActor, warrant: Dictionary) -> void:
	if actor == null:
		return
	for guard in _find_authority_guards(str(warrant.get("faction_id", "")), _find_settlement_for_warrant(actor, warrant), true):
		if guard == null:
			continue
		if guard.has_method("clear_personal_hostility"):
			guard.call("clear_personal_hostility", actor)
		if actor.has_method("clear_personal_hostility"):
			actor.call("clear_personal_hostility", guard)
	if actor.has_method("clear_all_personal_hostility"):
		actor.call("clear_all_personal_hostility")


func _assign_custody_guard_return(guard: HumanoidCharacter, jail: Node) -> void:
	if guard == null or guard.life_state != NpcRules.LifeState.ALIVE or not guard.has_method("assign_law_custody_return_target"):
		return
	guard.call("assign_law_custody_return_target", _get_jail_exit_position(jail, guard))


func _get_jail_exit_position(jail: Node, actor: Node = null) -> Vector3:
	if jail == null:
		return Vector3.ZERO
	if jail.has_method("get_exit_position"):
		var exit_position: Variant = jail.call("get_exit_position", actor)
		return exit_position if exit_position is Vector3 else Vector3.ZERO
	if jail.has_method("get_entry_position"):
		var entry_value: Variant = jail.call("get_entry_position", actor)
		var entry_position: Vector3 = entry_value if entry_value is Vector3 else Vector3.ZERO
		if jail is Node3D:
			var direction := entry_position - (jail as Node3D).global_position
			direction.y = 0.0
			if direction.length_squared() > 0.001:
				return entry_position + direction.normalized() * 1.5
		return entry_position
	return (jail as Node3D).global_position if jail is Node3D else Vector3.ZERO


func _find_authority_guards(faction_id: String, settlement: Node, include_jail_staff := true) -> Array[WorldActor]:
	var guards: Array[WorldActor] = []
	if root_scene == null or not root_scene.is_inside_tree():
		return guards
	for node in root_scene.get_tree().get_nodes_in_group("world_actor"):
		var guard := node as WorldActor
		if guard == null or guard.life_state != NpcRules.LifeState.ALIVE or guard.player_party_member:
			continue
		if not _is_law_soldier_responder(guard):
			continue
		if not faction_id.is_empty() and guard.faction_name != faction_id:
			continue
		if settlement != null and not _is_law_actor_attached_to_settlement(guard, settlement):
			continue
		if not include_jail_staff and _is_node_descendant_of_group(guard, "settlement_jail"):
			continue
		guards.append(guard)
	return guards


func _is_law_soldier_responder(actor: WorldActor) -> bool:
	if actor == null:
		return false
	return actor.has_method("is_faction_soldier") and bool(actor.call("is_faction_soldier"))


func _is_law_actor_attached_to_settlement(actor: WorldActor, settlement: Node) -> bool:
	if actor == null or settlement == null:
		return false
	if _is_node_descendant_of(actor, settlement):
		return true
	return _find_containing_settlement(actor) == settlement


func _configure_authority_alert_context(record: Dictionary, crime_context: Dictionary, is_new_record: bool) -> void:
	var alert_mode := str(crime_context.get("authority_alert_mode", "settlement")).strip_edges().to_lower()
	if alert_mode == "local":
		if is_new_record or str(record.get("authority_alert_mode", "settlement")) == "local":
			record["authority_alert_mode"] = "local"
			var alarm_position = crime_context.get("local_alarm_position", Vector3.INF)
			if alarm_position is Vector3:
				record["local_alarm_position"] = alarm_position
			record["local_alarm_radius"] = maxf(0.0, float(crime_context.get("local_alarm_radius", NpcRules.NPC_ALERT_PROXIMITY_RADIUS)))
		return
	record["authority_alert_mode"] = "settlement"
	record.erase("local_alarm_position")
	record.erase("local_alarm_radius")


func _is_guard_in_authority_alert_scope(guard: WorldActor, warrant: Dictionary, actor: WorldActor) -> bool:
	if guard == null:
		return false
	if str(warrant.get("authority_alert_mode", "settlement")) != "local":
		return true
	if actor != null and guard.has_method("get_current_combat_target") and guard.call("get_current_combat_target") == actor:
		return true
	var alarm_position = warrant.get("local_alarm_position", Vector3.INF)
	if not (alarm_position is Vector3):
		return false
	var radius := maxf(0.0, float(warrant.get("local_alarm_radius", NpcRules.NPC_ALERT_PROXIMITY_RADIUS)))
	return guard.global_position.distance_to(alarm_position) <= radius


func _existing_local_alert_context(actor: WorldActor, faction_id: String) -> Dictionary:
	var record := _get_mutable_warrant_record(actor, faction_id)
	if record.is_empty() or str(record.get("authority_alert_mode", "settlement")) != "local":
		return {}
	var context := {
		"authority_alert_mode": "local",
		"local_alarm_radius": float(record.get("local_alarm_radius", NpcRules.NPC_ALERT_PROXIMITY_RADIUS)),
	}
	var alarm_position = record.get("local_alarm_position", Vector3.INF)
	if alarm_position is Vector3:
		context["local_alarm_position"] = alarm_position
	return context


func _find_custody_guard(actor: WorldActor, warrant: Dictionary, settlement: Node) -> HumanoidCharacter:
	var faction_id := str(warrant.get("faction_id", ""))
	var assigned_guard := _find_actor_by_key(str(warrant.get("custody_guard_key", ""))) as HumanoidCharacter
	# Sticky assignment only while the guard actually has the body: a previously
	# chosen guard that cannot path to the prisoner would otherwise hold the
	# custody forever while a closer guard idles next to the body.
	if _is_valid_custody_guard(assigned_guard, actor, faction_id, settlement) and assigned_guard.get_carried_character() == actor:
		return assigned_guard
	for guard in _find_authority_guards(faction_id, settlement):
		var humanoid_guard := guard as HumanoidCharacter
		if _is_valid_custody_guard(humanoid_guard, actor, faction_id, settlement) and humanoid_guard.has_method("is_law_arresting") and bool(humanoid_guard.call("is_law_arresting", actor)):
			return humanoid_guard
	var best: HumanoidCharacter = null
	var best_distance := INF
	for guard in _find_authority_guards(faction_id, settlement):
		var humanoid_guard := guard as HumanoidCharacter
		if not _is_valid_custody_guard(humanoid_guard, actor, faction_id, settlement):
			continue
		if humanoid_guard.get_carried_character() == actor:
			return humanoid_guard
		var distance := humanoid_guard.global_position.distance_squared_to(actor.global_position)
		if distance < best_distance:
			best_distance = distance
			best = humanoid_guard
	return best


func _is_valid_custody_guard(guard: HumanoidCharacter, actor: WorldActor, faction_id: String, settlement: Node) -> bool:
	if guard == null or guard == actor or guard.life_state != NpcRules.LifeState.ALIVE or guard.player_party_member:
		return false
	if not _is_law_soldier_responder(guard):
		return false
	if not faction_id.is_empty() and guard.faction_name != faction_id:
		return false
	if settlement != null and not _is_law_actor_attached_to_settlement(guard, settlement):
		return false
	return guard.get_carried_character() == null or guard.get_carried_character() == actor


func _find_local_authority_witnesses(attacker: WorldActor, victim: WorldActor, enforcing_faction_id: String, settlement: Node, radius: float) -> Array[WorldActor]:
	var witnesses: Array[WorldActor] = []
	if attacker == null or victim == null or settlement == null or _actor_query == null:
		return witnesses
	var perception := _get_perception_controller()
	for node in _actor_query.get_nearby_humanoids_limited(victim.global_position, radius, MAX_AUTHORITY_WITNESS_CANDIDATES, false):
		var authority := node as WorldActor
		if authority == null or authority == attacker or authority == victim:
			continue
		if authority.life_state != NpcRules.LifeState.ALIVE or authority.player_party_member:
			continue
		if not _is_law_soldier_responder(authority) or authority.faction_name != enforcing_faction_id:
			continue
		if not _is_law_actor_attached_to_settlement(authority, settlement):
			continue
		if perception != null and perception.has_method("evaluate_observer"):
			var result := perception.call("evaluate_observer", authority, attacker) as Dictionary
			if not bool(result.get("clearly_seen", false)):
				continue
		witnesses.append(authority)
	witnesses.sort_custom(func(left: WorldActor, right: WorldActor) -> bool: return _actor_key(left) < _actor_key(right))
	return witnesses


func _find_witnesses(actor: WorldActor, target, faction_id: String) -> Array:
	var witnesses: Array = []
	if actor == null or root_scene == null or not root_scene.is_inside_tree():
		return witnesses
	var target_position := actor.global_position
	if target is Node3D:
		target_position = (target as Node3D).global_position
	var perception := _get_perception_controller()
	for node in root_scene.get_tree().get_nodes_in_group("world_actor"):
		var witness := node as WorldActor
		if witness == null or witness == actor or witness.life_state != NpcRules.LifeState.ALIVE or witness.player_party_member:
			continue
		if not faction_id.is_empty() and witness.faction_name != faction_id:
			continue
		if witness.global_position.distance_to(target_position) > DEFAULT_WITNESS_RADIUS:
			continue
		if perception != null and perception.has_method("evaluate_observer"):
			var result := perception.call("evaluate_observer", witness, actor) as Dictionary
			if not bool(result.get("clearly_seen", false)):
				continue
		witnesses.append(witness)
	return witnesses


func _witnesses_excluding_actor(witnesses: Array, excluded: WorldActor) -> Array[WorldActor]:
	var filtered: Array[WorldActor] = []
	for witness in witnesses:
		var world_actor := witness as WorldActor
		if world_actor != null and world_actor != excluded:
			filtered.append(world_actor)
	return filtered


func _actor_keys_from_witnesses(witnesses: Variant) -> Array[String]:
	var keys: Array[String] = []
	if not (witnesses is Array):
		return keys
	for witness in witnesses:
		var world_actor := witness as WorldActor
		if world_actor == null:
			continue
		var key := _actor_key(world_actor)
		if not key.is_empty() and not keys.has(key):
			keys.append(key)
	return keys


func _has_public_warrant_for_target(actor: HumanoidCharacter, faction_id: String, target: HumanoidCharacter) -> bool:
	if actor == null or target == null:
		return false
	var target_key := _actor_key(target)
	var record := _get_mutable_warrant_record(actor, faction_id)
	var crimes: Array = record.get("crimes", [])
	for crime in crimes:
		if not (crime is Dictionary):
			continue
		if str(crime.get("target_key", "")) == target_key and bool(crime.get("public", true)):
			return true
	return false


func _find_nearest_authority_witness(actor: WorldActor, faction_id: String) -> WorldActor:
	var best: WorldActor = null
	var best_distance := INF
	for witness in _find_witnesses(actor, actor, faction_id):
		if not (witness is WorldActor):
			continue
		var world_witness := witness as WorldActor
		var distance := world_witness.global_position.distance_squared_to(actor.global_position)
		if distance < best_distance:
			best_distance = distance
			best = world_witness
	return best


func _clear_expired_warrants(absolute_minute: int) -> void:
	for actor_key in warrants.keys():
		var actor := _find_actor_by_key(str(actor_key))
		var by_faction: Dictionary = warrants.get(actor_key, {})
		var expired_any := false
		for faction_id in by_faction.keys():
			var record: Dictionary = by_faction[faction_id]
			var expires_at := int(record.get("warrant_expires_at_minute", -1))
			if expires_at >= 0 and absolute_minute >= expires_at and str(record.get("state", "wanted")) != "jailed":
				if actor != null:
					_disengage_authority_guards(actor, record)
				by_faction.erase(faction_id)
				expired_any = true
		if by_faction.is_empty():
			warrants.erase(actor_key)
			if actor != null:
				_clear_actor_law_meta(actor)
		else:
			warrants[actor_key] = by_faction
			if expired_any and actor != null:
				_apply_actor_law_meta(actor, by_faction.values()[0])


func _clear_expired_stolen_items(absolute_minute: int) -> void:
	if root_scene == null or not root_scene.is_inside_tree():
		return
	for node in root_scene.get_tree().get_nodes_in_group("npc_character"):
		if node != null and node.get("inventory") != null:
			node.get("inventory").clear_expired_stolen_metadata(absolute_minute)
	for node in root_scene.get_tree().get_nodes_in_group("world_container"):
		if node != null and node.get("inventory") != null:
			node.get("inventory").clear_expired_stolen_metadata(absolute_minute)


func _clear_warrant_for_actor(actor: WorldActor, faction_id: String) -> void:
	if actor == null:
		return
	var actor_key := _actor_key(actor)
	var by_faction: Dictionary = warrants.get(actor_key, {})
	if faction_id.is_empty():
		by_faction.clear()
	else:
		by_faction.erase(faction_id)
	if by_faction.is_empty():
		warrants.erase(actor_key)
		_clear_actor_law_meta(actor)
	else:
		warrants[actor_key] = by_faction
	_save_law_order_state_to_gecs()


func _clear_actor_law_meta(actor: WorldActor) -> void:
	if actor == null:
		return
	actor.get_legal_status().clear_warrant_display()


func _prune_victim_only_crimes_for_dead_actor(victim: WorldActor) -> void:
	var victim_key := _actor_key(victim)
	if victim_key.is_empty():
		return
	for actor_key in warrants.keys():
		var offender := _find_actor_by_key(str(actor_key))
		var by_faction: Dictionary = warrants.get(actor_key, {})
		for faction_id in by_faction.keys():
			var record: Dictionary = by_faction[faction_id]
			var kept_crimes: Array = []
			var removed_any := false
			var crimes: Array = record.get("crimes", [])
			for crime in crimes:
				if crime is Dictionary and _should_prune_victim_only_crime(crime, victim_key):
					removed_any = true
					continue
				kept_crimes.append(crime)
			if not removed_any:
				continue
			if offender != null:
				_disengage_authority_guards(offender, record)
			if kept_crimes.is_empty():
				by_faction.erase(faction_id)
				continue
			record["crimes"] = kept_crimes
			_recalculate_warrant_from_crimes(record)
			by_faction[faction_id] = record
			if offender != null:
				_apply_actor_law_meta(offender, record)
		if by_faction.is_empty():
			warrants.erase(actor_key)
			if offender != null:
				_clear_actor_law_meta(offender)
		else:
			warrants[actor_key] = by_faction


func _should_prune_victim_only_crime(crime: Dictionary, victim_key: String) -> bool:
	if str(crime.get("target_key", "")) != victim_key:
		return false
	if str(crime.get("provisional_victim_key", "")) != victim_key:
		return false
	if bool(crime.get("public", true)):
		return false
	var witness_keys: Array = crime.get("witness_keys", [])
	for witness_key in witness_keys:
		var key := str(witness_key)
		if not key.is_empty() and key != victim_key:
			return false
	return true


func _recalculate_warrant_from_crimes(record: Dictionary) -> void:
	var crimes: Array = record.get("crimes", [])
	var total_points := 0
	var total_sentence := 0
	var has_murder := false
	var longest_duration := THEFT_WARRANT_DURATION_MINUTES
	var any_public := false
	for crime in crimes:
		if not (crime is Dictionary):
			continue
		var crime_type := str(crime.get("crime_type", ""))
		var severity: int = maxi(1, int(crime.get("severity", 1)))
		total_points += severity
		total_sentence += _sentence_minutes_for(crime_type, severity)
		if crime_type == CRIME_MURDER:
			has_murder = true
		else:
			longest_duration = maxi(longest_duration, _warrant_duration_for(crime_type))
		any_public = any_public or bool(crime.get("public", true))
	record["bad_person_points"] = total_points
	record["sentence_minutes"] = total_sentence
	record["warrant_expires_at_minute"] = -1 if has_murder else _now_minute() + longest_duration + total_points
	record["public_known"] = any_public


func _warrant_duration_for(crime_type: String) -> int:
	match crime_type:
		CRIME_TRESPASS:
			return TRESPASS_WARRANT_DURATION_MINUTES
		CRIME_ASSAULT:
			return ASSAULT_WARRANT_DURATION_MINUTES
		CRIME_LOCKPICKING, CRIME_ESCAPE:
			return LOCKPICK_WARRANT_DURATION_MINUTES
		_:
			return THEFT_WARRANT_DURATION_MINUTES


func _new_warrant(actor: WorldActor, faction_id: String, settlement_id: String) -> Dictionary:
	var actor_key := _actor_key(actor)
	return {
		"case_id": "%s:%s:%d" % [actor_key, faction_id, _now_minute()],
		"actor_key": actor_key,
		"faction_id": faction_id,
		"settlement_id": settlement_id,
		"state": "wanted",
		"crimes": [],
		"public_known": false,
		"authority_alert_mode": "settlement",
		"bad_person_points": 0,
		"sentence_minutes": 0,
		"warrant_expires_at_minute": _now_minute() + THEFT_WARRANT_DURATION_MINUTES,
	}


func _sentence_minutes_for(crime_type: String, severity: int) -> int:
	match crime_type:
		CRIME_MURDER:
			return MURDER_SENTENCE_MINUTES
		CRIME_ASSAULT:
			return ASSAULT_SENTENCE_MINUTES
		CRIME_TRESPASS:
			return TRESPASS_SENTENCE_MINUTES
		CRIME_LOCKPICKING, CRIME_ESCAPE:
			return LOCKPICK_SENTENCE_MINUTES
		_:
			return THEFT_SENTENCE_MINUTES + max(0, severity - 10) * 6


func _sentence_decision_delay_minutes() -> int:
	return _rng.randi_range(SENTENCE_DECISION_MIN_DELAY_MINUTES, SENTENCE_DECISION_MAX_DELAY_MINUTES)


func _merged_warrant_expiry(record: Dictionary, crime_type: String) -> int:
	if crime_type == CRIME_MURDER:
		return -1
	var current := int(record.get("warrant_expires_at_minute", -1))
	if current < 0:
		return -1
	var duration := THEFT_WARRANT_DURATION_MINUTES
	match crime_type:
		CRIME_TRESPASS:
			duration = TRESPASS_WARRANT_DURATION_MINUTES
		CRIME_ASSAULT:
			duration = ASSAULT_WARRANT_DURATION_MINUTES
		CRIME_LOCKPICKING, CRIME_ESCAPE:
			duration = LOCKPICK_WARRANT_DURATION_MINUTES
	return maxi(current, _now_minute() + duration + int(record.get("bad_person_points", 0)))


func _crime_alarm_line(crime_type: String) -> String:
	match crime_type:
		CRIME_TRESPASS:
			return "Guards! Trespasser!"
		CRIME_ASSAULT:
			return "Guards! Assault!"
		CRIME_MURDER:
			return "Murder! Guards!"
		CRIME_LOCKPICKING, CRIME_ESCAPE:
			return "Guards! Lockpick!"
		_:
			return "Thief! Guards!"


func _apply_actor_law_meta(actor: WorldActor, record: Dictionary) -> void:
	if actor == null:
		return
	var status := actor.get_legal_status()
	status.warrant_summary = "%s warrant: %d pts" % [str(record.get("faction_id", "Faction")), int(record.get("bad_person_points", 0))]
	var state := str(record.get("state", ""))
	if state == "jailed":
		status.is_prisoner = true
		status.jail_id = str(record.get("jail_id", status.jail_id))
		status.cell_id = str(record.get("cell_id", status.cell_id))
		status.status_label = "Jailed"
		status.status_kind = "jailed"
		var release_at := int(record.get("release_at_minute", -1))
		if release_at < 0:
			status.sentence_summary = "Awaiting sentence"
		else:
			status.sentence_summary = "Sentence: %s remaining" % _minutes_label(max(0, release_at - _now_minute()))
		return
	status.status_label = _caught_crime_status_label(_latest_crime_type(record))
	status.status_kind = "caught"
	status.sentence_summary = ""


func _latest_crime_type(record: Dictionary) -> String:
	var crimes: Array = record.get("crimes", [])
	if crimes.is_empty():
		return ""
	var crime = crimes[crimes.size() - 1]
	return str(crime.get("crime_type", "")) if crime is Dictionary else ""


func _caught_crime_status_label(crime_type: String) -> String:
	match crime_type:
		CRIME_THEFT:
			return "CAUGHT STEALING"
		CRIME_TRESPASS:
			return "CAUGHT TRESPASSING"
		CRIME_ASSAULT:
			return "CAUGHT ASSAULTING"
		CRIME_MURDER:
			return "CAUGHT MURDERING"
		CRIME_LOCKPICKING:
			return "CAUGHT LOCKPICKING"
		CRIME_ESCAPE:
			return "CAUGHT ESCAPING"
		_:
			return "CAUGHT COMMITTING CRIME"


func _minutes_label(minutes: int) -> String:
	if minutes >= MINUTES_PER_DAY:
		return "%d days" % int(ceil(float(minutes) / float(MINUTES_PER_DAY)))
	if minutes >= 60:
		return "%d hours" % int(ceil(float(minutes) / 60.0))
	return "%d minutes" % minutes


func _eject_actor_from_town(actor: HumanoidCharacter, settlement: Node) -> void:
	if actor == null:
		return
	var eject_position := actor.global_position + Vector3(8.0, 0.0, 0.0)
	if settlement is Node3D:
		var center := (settlement as Node3D).global_position
		var direction := (actor.global_position - center)
		direction.y = 0.0
		if direction.length_squared() <= 0.001:
			direction = Vector3.RIGHT
		eject_position = center + direction.normalized() * 34.0
		eject_position.y = actor.global_position.y
	actor.global_position = eject_position
	actor.velocity = Vector3.ZERO


func _find_jail_for_settlement(settlement: Node) -> Node:
	if settlement == null:
		return null
	for child in settlement.find_children("*", "SettlementJail", true, false):
		return child
	for child in settlement.find_children("*", "Node3D", true, false):
		if child is SettlementJail:
			return child
	return null


func _find_jail_by_id(jail_id: String) -> Node:
	if jail_id.is_empty() or root_scene == null or not root_scene.is_inside_tree():
		return null
	for node in root_scene.get_tree().get_nodes_in_group("settlement_jail"):
		if node != null and node.has_method("get_facility_id") and str(node.call("get_facility_id")) == jail_id:
			return node
	return null


func _find_settlement_for_warrant(actor: WorldActor, warrant: Dictionary) -> Node:
	var settlement_id := str(warrant.get("settlement_id", ""))
	if not settlement_id.is_empty():
		var settlement := _find_settlement_by_id(settlement_id)
		if settlement != null:
			return settlement
	return _find_containing_settlement(actor)


func _find_containing_settlement(target) -> Node:
	if root_scene == null or not root_scene.is_inside_tree():
		return null
	var position := Vector3.ZERO
	var has_position := false
	if target is Node3D:
		position = (target as Node3D).global_position
		has_position = true
	var ancestor := _ancestor_settlement(target as Node if target is Node else null)
	if ancestor != null:
		return ancestor
	if not has_position:
		return null
	for node in root_scene.get_tree().get_nodes_in_group("settlement_town"):
		if node != null and node.has_method("contains_town_border_position") and bool(node.call("contains_town_border_position", position)):
			return node
	return null


func _find_settlement_by_id(settlement_id: String) -> Node:
	if root_scene == null or not root_scene.is_inside_tree():
		return null
	for group_name in ["settlement_town", "settlement_anchor"]:
		for node in root_scene.get_tree().get_nodes_in_group(group_name):
			if node != null and _settlement_id(node) == settlement_id:
				return node
	return null


func _ancestor_settlement(node: Node) -> Node:
	var current := node
	while current != null:
		if current is SettlementAnchor:
			return current
		current = current.get_parent()
	return null


func _settlement_id(settlement: Node) -> String:
	if settlement == null:
		return ""
	if settlement.has_method("get_settlement_id"):
		return str(settlement.call("get_settlement_id"))
	return str(settlement.name)


func _settlement_faction_id(settlement: Node) -> String:
	if settlement == null or not _has_property(settlement, "settlement_definition"):
		return ""
	var definition = settlement.get("settlement_definition")
	if definition != null and definition.has_method("get_faction_id"):
		return str(definition.call("get_faction_id"))
	if definition != null and _has_property(definition, "faction_definition"):
		var faction = definition.get("faction_definition")
		if faction != null and _has_property(faction, "faction_id"):
			return str(faction.get("faction_id"))
	return ""


func _owner_faction_id(target) -> String:
	if target == null:
		return ""
	if target.has_method("get_owner_faction_name"):
		return str(target.call("get_owner_faction_name"))
	if _has_property(target, "owner_faction_name"):
		return str(target.get("owner_faction_name"))
	return ""


func _target_int(target, method_name: String, property_name: String, fallback: int) -> int:
	if target != null and target.has_method(method_name):
		return int(target.call(method_name))
	if target != null and _has_property(target, property_name):
		return int(target.get(property_name))
	return fallback


func _target_key(target) -> String:
	if target is WorldActor:
		return _actor_key(target as WorldActor)
	if target is Node:
		return str((target as Node).get_path()) if (target as Node).is_inside_tree() else str((target as Node).name)
	return ""


func _warrant_response_authority_id(actor: WorldActor, warrant: Dictionary) -> String:
	return "warrant|%s|%s" % [str(warrant.get("faction_id", "")), _actor_key(actor)]


func _actor_key(actor: WorldActor) -> String:
	if actor == null:
		return ""
	return actor.stable_id if not actor.stable_id.strip_edges().is_empty() else str(actor.get_instance_id())


func _find_actor_by_key(actor_key: String) -> WorldActor:
	if actor_key.is_empty() or root_scene == null or not root_scene.is_inside_tree():
		return null
	var query_controller := _get_actor_query_controller()
	if query_controller != null and query_controller.has_method("get_actor_by_stable_id"):
		var indexed_actor := query_controller.call("get_actor_by_stable_id", actor_key) as WorldActor
		if indexed_actor != null:
			return indexed_actor
	for node in root_scene.get_tree().get_nodes_in_group("world_actor"):
		var actor := node as WorldActor
		if actor != null and _actor_key(actor) == actor_key:
			return actor
	return null


func _get_actor_query_controller() -> Node:
	return _context.get_optional(ActorQueryController.SERVICE_ID) if _context != null else null


func _get_perception_controller() -> Node:
	return _context.get_optional(PerceptionController.SERVICE_ID) if _context != null else null


func _connect_world_time() -> void:
	if world_time == null and _context != null:
		world_time = _context.get_optional(WorldTimeController.SERVICE_ID)
	if world_time == null:
		return
	var callable := Callable(self, "_on_minute_changed")
	if world_time.has_signal("minute_changed") and not world_time.is_connected("minute_changed", callable):
		world_time.connect("minute_changed", callable)


func _current_law_order_state() -> Dictionary:
	return {
		"state_id": "law_order",
		"warrants": warrants.duplicate(true),
		"prisoner_records": prisoner_records.duplicate(true),
	}


func _save_law_order_state_to_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_law_order_state"):
		bridge.call("upsert_law_order_state", _current_law_order_state())


func _apply_loaded_law_meta() -> void:
	for actor_key in warrants.keys():
		var actor := _find_actor_by_key(str(actor_key))
		if actor == null:
			continue
		var by_faction: Dictionary = warrants.get(actor_key, {})
		if not by_faction.is_empty():
			_apply_actor_law_meta(actor, by_faction.values()[0])
	for prisoner_key in prisoner_records.keys():
		var prisoner := _find_actor_by_key(str(prisoner_key))
		if prisoner != null:
			_apply_actor_law_meta(prisoner, prisoner_records[prisoner_key])


func _get_gecs_world() -> Node:
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null


func _now_minute() -> int:
	if world_time != null and world_time.has_method("get_absolute_minute"):
		return int(world_time.call("get_absolute_minute"))
	return 0


func _is_node_descendant_of(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _is_node_descendant_of_group(node: Node, group_name: String) -> bool:
	var current := node
	while current != null:
		if current.is_in_group(group_name):
			return true
		current = current.get_parent()
	return false


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
