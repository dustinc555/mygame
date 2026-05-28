extends Node

class_name LawOrderController

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
const LOCAL_COMBAT_ALARM_RADIUS := 25.0
const SENTENCE_DECISION_MIN_DELAY_MINUTES := 120
const SENTENCE_DECISION_MAX_DELAY_MINUTES := 180

const CRIME_THEFT := "theft"
const CRIME_TRESPASS := "trespass"
const CRIME_ASSAULT := "assault"
const CRIME_MURDER := "murder"
const CRIME_LOCKPICKING := "lockpicking"
const CRIME_ESCAPE := "escape"
const GECS_WORLD_CONTROLLER_SCRIPT := preload("res://scripts/controllers/gecs_world_controller.gd")

var root_scene: Node
var hud_layer: CanvasLayer
var world_time: Node
var warrants: Dictionary = {}
var prisoner_records: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _process_accumulator := 0.0


func _ready() -> void:
	add_to_group("law_order_controller")
	_rng.randomize()
	_connect_world_time()
	refresh_from_gecs_state()


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	_connect_world_time()
	refresh_from_gecs_state()


func get_current_settlement_id_for(target) -> String:
	var settlement := _find_containing_settlement(target)
	return _settlement_id(settlement)


func make_stolen_item_metadata(actor: HumanoidCharacter, source, owner_faction_id := "", settlement_id := "") -> Dictionary:
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


func report_theft_if_witnessed(actor: HumanoidCharacter, item, witnesses: Array = []) -> Dictionary:
	if actor == null or item == null:
		return {}
	var owner_faction := _owner_faction_id(item)
	if owner_faction.is_empty():
		return {}
	if witnesses.is_empty():
		witnesses = _find_witnesses(actor, item, owner_faction)
	if witnesses.is_empty():
		return {}
	var settlement_id := get_current_settlement_id_for(item)
	var severity: int = max(1, _target_int(item, "get_theft_value", "theft_value", 10))
	return report_crime(actor, owner_faction, settlement_id, CRIME_THEFT, severity, witnesses[0], item)


func report_trespass(actor: HumanoidCharacter, building, witness: HumanoidCharacter = null) -> Dictionary:
	if actor == null or building == null:
		return {}
	var faction_id := ""
	if building.has_method("get_jurisdiction_faction_name"):
		faction_id = str(building.call("get_jurisdiction_faction_name"))
	if faction_id.is_empty() and building.has_method("get_owner_faction_name"):
		faction_id = str(building.call("get_owner_faction_name"))
	if faction_id.is_empty():
		return {}
	var witnesses: Array = [witness] if witness != null else _find_witnesses(actor, building, faction_id)
	if witnesses.is_empty():
		return {}
	return report_crime(actor, faction_id, get_current_settlement_id_for(building), CRIME_TRESPASS, 5, witnesses[0], building)


func report_player_assault(attacker: HumanoidCharacter, victim: HumanoidCharacter) -> Dictionary:
	if attacker == null or victim == null or not attacker.is_player_party_member():
		return {}
	if victim.is_player_party_member() or victim.has_hostility_with(attacker):
		return {}
	var faction_id := victim.faction_name.strip_edges()
	if faction_id.is_empty():
		return {}
	var settlement := _find_containing_settlement(victim)
	var public_witnesses := _find_local_assault_witnesses(attacker, victim, faction_id, settlement, LOCAL_COMBAT_ALARM_RADIUS)
	var witnesses: Array[HumanoidCharacter] = [victim]
	for witness in public_witnesses:
		if witness != null and not witnesses.has(witness):
			witnesses.append(witness)
	return report_crime(attacker, faction_id, _settlement_id(settlement), CRIME_ASSAULT, 35, victim, victim, {
		"public": not public_witnesses.is_empty(),
		"witnesses": witnesses,
		"provisional_victim_key": _actor_key(victim),
		"authority_alert_mode": "local",
		"local_alarm_position": victim.global_position,
		"local_alarm_radius": LOCAL_COMBAT_ALARM_RADIUS,
	})


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
	var lead_witness: HumanoidCharacter = public_witnesses[0] if not public_witnesses.is_empty() else victim
	var crime_context := {
		"public": not public_witnesses.is_empty() or has_public_case,
		"witnesses": witnesses,
		"provisional_victim_key": _actor_key(victim),
	}
	if public_witnesses.is_empty() and not has_public_case:
		crime_context["authority_alert_mode"] = "local"
		crime_context["local_alarm_position"] = victim.global_position
		crime_context["local_alarm_radius"] = LOCAL_COMBAT_ALARM_RADIUS
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


func report_crime(actor: HumanoidCharacter, faction_id: String, settlement_id: String, crime_type: String, severity: int, witness: HumanoidCharacter = null, target = null, crime_context: Dictionary = {}) -> Dictionary:
	if actor == null or faction_id.strip_edges().is_empty():
		return {}
	var actor_key := _actor_key(actor)
	var faction_key := faction_id.strip_edges()
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
		"target_key": _target_key(target),
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
	by_faction[faction_key] = record
	warrants[actor_key] = by_faction
	_apply_actor_law_meta(actor, record)
	_save_law_order_state_to_gecs()
	if witness != null and witness.has_method("show_world_speech"):
		witness.show_world_speech(_crime_alarm_line(crime_type), 4.0)
	_alert_authority_guards(actor, record)
	return record


func handle_actor_death(actor: HumanoidCharacter) -> void:
	if actor == null:
		return
	_prune_victim_only_crimes_for_dead_actor(actor)
	_save_law_order_state_to_gecs()


func actor_has_active_warrant(actor: HumanoidCharacter, faction_id := "") -> bool:
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


func get_warrant_record(actor: HumanoidCharacter, faction_id: String) -> Dictionary:
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


func _get_mutable_warrant_record(actor: HumanoidCharacter, faction_id: String) -> Dictionary:
	if actor == null:
		return {}
	return (warrants.get(_actor_key(actor), {}) as Dictionary).get(faction_id, {})


func complete_custody_if_placed(actor: HumanoidCharacter) -> bool:
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
	_process_accumulator += delta
	if _process_accumulator < 0.35:
		return
	_process_accumulator = 0.0
	_process_warrants()
	_process_prisoners()
	_save_law_order_state_to_gecs()


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
			if actor.life_state == NpcRules.LifeState.UNCONSCIOUS:
				_arrest_or_eject(actor, record)
				by_faction[faction_id] = record
				continue
			if actor.life_state != NpcRules.LifeState.ALIVE:
				continue
			var settlement := _find_settlement_for_warrant(actor, record)
			if _should_alert_authority_guards(actor, record, settlement):
				_alert_authority_guards(actor, record)
			elif _has_active_authority_arrest_response(actor, record, settlement):
				_alert_authority_guards(actor, record)
			else:
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
		var release_at := int(record.get("release_at_minute", -1))
		if release_at >= 0 and now >= release_at:
			_release_prisoner(actor, record, jail)


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


func _process_custody(actor: HumanoidCharacter, warrant: Dictionary) -> void:
	if actor == null or actor.life_state == NpcRules.LifeState.DEAD:
		return
	var settlement := _find_settlement_for_warrant(actor, warrant)
	var jail := _find_jail_by_id(str(warrant.get("custody_jail_id", "")))
	if jail == null:
		jail = _find_jail_for_settlement(settlement)
	if jail == null:
		return
	if jail.has_method("admit_prisoner") and bool(jail.call("admit_prisoner", actor, warrant, self)):
		_complete_jailing(actor, warrant, jail)
		return
	if actor.life_state == NpcRules.LifeState.ALIVE:
		warrant["state"] = "wanted"
		_alert_authority_guards(actor, warrant)
		return
	if actor.life_state != NpcRules.LifeState.UNCONSCIOUS:
		return
	var guard := _find_custody_guard(actor, warrant, settlement)
	if guard == null:
		return
	var cell_reference: Node = guard if guard.get_carried_character() == actor else actor
	var cell = jail.call("get_available_cell", actor, cell_reference) if jail.has_method("get_available_cell") else null
	if cell == null:
		return
	warrant["custody_guard_key"] = _actor_key(guard)
	_disengage_authority_guards(actor, warrant)
	if guard.get_carried_character() == actor:
		guard.assign_place_carried_in_cell_target(cell, false)
		return
	if not actor.is_carried() and guard.get_carried_character() == null:
		guard.assign_carry_target(actor, false)


func _complete_jailing(actor: HumanoidCharacter, warrant: Dictionary, jail: Node) -> void:
	var prisoner_key := _actor_key(actor)
	var prisoner_record := warrant.duplicate(true)
	prisoner_record["state"] = "jailed"
	prisoner_record["actor_key"] = prisoner_key
	prisoner_record["jail_id"] = str(jail.call("get_facility_id")) if jail.has_method("get_facility_id") else str(jail.name)
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
	var custody_guard := _find_actor_by_key(str(warrant.get("custody_guard_key", "")))
	_disengage_authority_guards(actor, warrant)
	_disengage_authority_guards_from_each_other(warrant)
	_clear_custody_actor_hostility(actor, warrant)
	_assign_custody_guard_return(custody_guard, jail)


func register_prisoner_locker_transfer(actor: HumanoidCharacter, _locker, warrant: Dictionary) -> Dictionary:
	return {
		"prisoner_key": _actor_key(actor),
		"case_id": str(warrant.get("case_id", "%s:%d" % [_actor_key(actor), _now_minute()])),
		"absolute_minute": _now_minute(),
	}


func complete_prisoner_sentence_delivery(actor: HumanoidCharacter) -> bool:
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


func has_pending_prisoner_sentence_notification(actor: HumanoidCharacter) -> bool:
	if actor == null:
		return false
	var prisoner_key := _actor_key(actor)
	if not prisoner_records.has(prisoner_key):
		return false
	var record: Dictionary = prisoner_records[prisoner_key]
	return str(record.get("state", "")) == "jailed" and bool(record.get("sentence_notification_pending", false)) and not bool(record.get("sentence_notification_given", false))


func _decide_prisoner_sentence(actor: HumanoidCharacter, record: Dictionary, now: int) -> Dictionary:
	record["sentence_decision_given"] = true
	record["sentence_started_at_minute"] = now
	record["release_at_minute"] = now + max(1, int(record.get("sentence_minutes", THEFT_SENTENCE_MINUTES)))
	record["sentence_notification_pending"] = true
	record["sentence_notification_requested"] = false
	record["sentence_notification_given"] = false
	_apply_actor_law_meta(actor, record)
	return record


func _request_prisoner_sentence_notification(actor: HumanoidCharacter, record: Dictionary, jail: Node) -> Dictionary:
	if jail == null or not jail.has_method("tell_prisoner_sentence"):
		record["sentence_notification_requested"] = false
		return record
	record["sentence_notification_requested"] = bool(jail.call("tell_prisoner_sentence", actor, record))
	return record


func _release_prisoner(actor: HumanoidCharacter, record: Dictionary, jail) -> void:
	if jail != null and jail.has_method("release_prisoner"):
		jail.call("release_prisoner", actor, record, false)
	_clear_warrant_for_actor(actor, str(record.get("faction_id", "")))
	prisoner_records.erase(_actor_key(actor))
	actor.remove_meta("law_sentence_summary")
	actor.remove_meta("law_warrant_summary")
	_save_law_order_state_to_gecs()


func _alert_authority_guards(actor: HumanoidCharacter, warrant: Dictionary) -> void:
	if actor == null or actor.life_state != NpcRules.LifeState.ALIVE:
		return
	for guard in _find_authority_guards(str(warrant.get("faction_id", "")), _find_settlement_for_warrant(actor, warrant)):
		if guard != null and guard != actor and guard.life_state == NpcRules.LifeState.ALIVE:
			if not _is_guard_in_authority_alert_scope(guard, warrant, actor):
				continue
			if guard.has_method("assign_law_arrest_target"):
				guard.call("assign_law_arrest_target", actor, true, false)
			else:
				guard.assign_attack_target(actor, false, true, false)


func _disengage_authority_guards(actor: HumanoidCharacter, warrant: Dictionary) -> void:
	if actor == null:
		return
	for guard in _find_authority_guards(str(warrant.get("faction_id", "")), _find_settlement_for_warrant(actor, warrant)):
		if guard == null:
			continue
		if guard.has_method("disengage_combat_with"):
			guard.call("disengage_combat_with", actor)
		else:
			guard.clear_personal_hostility(actor)
		if actor.has_method("disengage_combat_with"):
			actor.call("disengage_combat_with", guard)
		else:
			actor.clear_personal_hostility(guard)


func _should_alert_authority_guards(actor: HumanoidCharacter, _warrant: Dictionary, settlement: Node) -> bool:
	if actor == null or settlement == null:
		return false
	if settlement.has_method("contains_town_border_position"):
		return bool(settlement.call("contains_town_border_position", actor.global_position))
	return true


func _has_active_authority_arrest_response(actor: HumanoidCharacter, warrant: Dictionary, settlement: Node) -> bool:
	if actor == null or settlement == null:
		return false
	for guard in _find_authority_guards(str(warrant.get("faction_id", "")), settlement):
		if guard != null and guard.has_method("is_law_arresting") and bool(guard.call("is_law_arresting", actor)):
			return true
	return false


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
			left.disengage_combat_with(right)
			right.disengage_combat_with(left)


func _clear_custody_actor_hostility(actor: HumanoidCharacter, warrant: Dictionary) -> void:
	if actor == null:
		return
	for guard in _find_authority_guards(str(warrant.get("faction_id", "")), _find_settlement_for_warrant(actor, warrant), true):
		if guard == null:
			continue
		guard.clear_personal_hostility(actor)
		actor.clear_personal_hostility(guard)
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


func _find_authority_guards(faction_id: String, settlement: Node, include_jail_staff := true) -> Array[HumanoidCharacter]:
	var guards: Array[HumanoidCharacter] = []
	if root_scene == null or not root_scene.is_inside_tree():
		return guards
	for node in root_scene.get_tree().get_nodes_in_group("npc_character"):
		var guard := node as HumanoidCharacter
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


func _is_law_soldier_responder(actor: HumanoidCharacter) -> bool:
	if actor == null:
		return false
	return actor.has_method("is_faction_soldier") and bool(actor.call("is_faction_soldier"))


func _is_law_actor_attached_to_settlement(actor: HumanoidCharacter, settlement: Node) -> bool:
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
			record["local_alarm_radius"] = maxf(0.0, float(crime_context.get("local_alarm_radius", LOCAL_COMBAT_ALARM_RADIUS)))
		return
	record["authority_alert_mode"] = "settlement"
	record.erase("local_alarm_position")
	record.erase("local_alarm_radius")


func _is_guard_in_authority_alert_scope(guard: HumanoidCharacter, warrant: Dictionary, actor: HumanoidCharacter) -> bool:
	if guard == null:
		return false
	if str(warrant.get("authority_alert_mode", "settlement")) != "local":
		return true
	if actor != null and guard.get_current_combat_target() == actor:
		return true
	var alarm_position = warrant.get("local_alarm_position", Vector3.INF)
	if not (alarm_position is Vector3):
		return false
	var radius := maxf(0.0, float(warrant.get("local_alarm_radius", LOCAL_COMBAT_ALARM_RADIUS)))
	return guard.global_position.distance_to(alarm_position) <= radius


func _existing_local_alert_context(actor: HumanoidCharacter, faction_id: String) -> Dictionary:
	var record := _get_mutable_warrant_record(actor, faction_id)
	if record.is_empty() or str(record.get("authority_alert_mode", "settlement")) != "local":
		return {}
	var context := {
		"authority_alert_mode": "local",
		"local_alarm_radius": float(record.get("local_alarm_radius", LOCAL_COMBAT_ALARM_RADIUS)),
	}
	var alarm_position = record.get("local_alarm_position", Vector3.INF)
	if alarm_position is Vector3:
		context["local_alarm_position"] = alarm_position
	return context


func _find_custody_guard(actor: HumanoidCharacter, warrant: Dictionary, settlement: Node) -> HumanoidCharacter:
	var faction_id := str(warrant.get("faction_id", ""))
	var assigned_guard := _find_actor_by_key(str(warrant.get("custody_guard_key", "")))
	if _is_valid_custody_guard(assigned_guard, actor, faction_id, settlement):
		return assigned_guard
	for guard in _find_authority_guards(faction_id, settlement):
		if _is_valid_custody_guard(guard, actor, faction_id, settlement) and guard.has_method("is_law_arresting") and bool(guard.call("is_law_arresting", actor)):
			return guard
	var best: HumanoidCharacter = null
	var best_distance := INF
	for guard in _find_authority_guards(faction_id, settlement):
		if not _is_valid_custody_guard(guard, actor, faction_id, settlement):
			continue
		if guard.get_carried_character() == actor:
			return guard
		var distance := guard.global_position.distance_squared_to(actor.global_position)
		if distance < best_distance:
			best_distance = distance
			best = guard
	return best


func _is_valid_custody_guard(guard: HumanoidCharacter, actor: HumanoidCharacter, faction_id: String, settlement: Node) -> bool:
	if guard == null or guard == actor or guard.life_state != NpcRules.LifeState.ALIVE or guard.player_party_member:
		return false
	if not _is_law_soldier_responder(guard):
		return false
	if not faction_id.is_empty() and guard.faction_name != faction_id:
		return false
	if settlement != null and not _is_law_actor_attached_to_settlement(guard, settlement):
		return false
	return guard.get_carried_character() == null or guard.get_carried_character() == actor


func _find_local_assault_witnesses(attacker: HumanoidCharacter, victim: HumanoidCharacter, faction_id: String, settlement: Node, radius: float) -> Array[HumanoidCharacter]:
	var witnesses: Array[HumanoidCharacter] = []
	if attacker == null or victim == null or root_scene == null or not root_scene.is_inside_tree():
		return witnesses
	for node in root_scene.get_tree().get_nodes_in_group("npc_character"):
		var humanoid := node as HumanoidCharacter
		if humanoid == null or humanoid == attacker or humanoid == victim:
			continue
		if humanoid.life_state != NpcRules.LifeState.ALIVE or humanoid.player_party_member:
			continue
		if not faction_id.is_empty() and humanoid.faction_name != faction_id:
			continue
		if settlement != null and not _is_node_descendant_of(humanoid, settlement) and _find_containing_settlement(humanoid) != settlement:
			continue
		if humanoid.global_position.distance_to(victim.global_position) > radius:
			continue
		witnesses.append(humanoid)
	return witnesses


func _find_witnesses(actor: HumanoidCharacter, target, faction_id: String) -> Array:
	var witnesses: Array = []
	if actor == null or root_scene == null or not root_scene.is_inside_tree():
		return witnesses
	var target_position := actor.global_position
	if target is Node3D:
		target_position = (target as Node3D).global_position
	var perception := _get_perception_controller()
	for node in root_scene.get_tree().get_nodes_in_group("npc_character"):
		var humanoid := node as HumanoidCharacter
		if humanoid == null or humanoid == actor or humanoid.life_state != NpcRules.LifeState.ALIVE or humanoid.player_party_member:
			continue
		if not faction_id.is_empty() and humanoid.faction_name != faction_id:
			continue
		if humanoid.global_position.distance_to(target_position) > DEFAULT_WITNESS_RADIUS:
			continue
		if perception != null and perception.has_method("evaluate_observer"):
			var result := perception.call("evaluate_observer", humanoid, actor) as Dictionary
			if not bool(result.get("clearly_seen", false)):
				continue
		witnesses.append(humanoid)
	return witnesses


func _witnesses_excluding_actor(witnesses: Array, excluded: HumanoidCharacter) -> Array[HumanoidCharacter]:
	var filtered: Array[HumanoidCharacter] = []
	for witness in witnesses:
		var humanoid := witness as HumanoidCharacter
		if humanoid != null and humanoid != excluded:
			filtered.append(humanoid)
	return filtered


func _actor_keys_from_witnesses(witnesses: Variant) -> Array[String]:
	var keys: Array[String] = []
	if not (witnesses is Array):
		return keys
	for witness in witnesses:
		var humanoid := witness as HumanoidCharacter
		if humanoid == null:
			continue
		var key := _actor_key(humanoid)
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


func _find_nearest_authority_witness(actor: HumanoidCharacter, faction_id: String) -> HumanoidCharacter:
	var best: HumanoidCharacter = null
	var best_distance := INF
	for witness in _find_witnesses(actor, actor, faction_id):
		if not (witness is HumanoidCharacter):
			continue
		var distance := (witness as HumanoidCharacter).global_position.distance_squared_to(actor.global_position)
		if distance < best_distance:
			best_distance = distance
			best = witness
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


func _clear_warrant_for_actor(actor: HumanoidCharacter, faction_id: String) -> void:
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


func _clear_actor_law_meta(actor: HumanoidCharacter) -> void:
	if actor == null:
		return
	actor.remove_meta("law_status_label")
	actor.remove_meta("law_status_kind")
	actor.remove_meta("law_warrant_summary")
	actor.remove_meta("law_sentence_summary")


func _prune_victim_only_crimes_for_dead_actor(victim: HumanoidCharacter) -> void:
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


func _new_warrant(actor: HumanoidCharacter, faction_id: String, settlement_id: String) -> Dictionary:
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


func _apply_actor_law_meta(actor: HumanoidCharacter, record: Dictionary) -> void:
	if actor == null:
		return
	var summary := "%s warrant: %d pts" % [str(record.get("faction_id", "Faction")), int(record.get("bad_person_points", 0))]
	actor.set_meta("law_warrant_summary", summary)
	var state := str(record.get("state", ""))
	if state == "jailed":
		actor.set_meta("law_status_label", "Jailed")
		actor.set_meta("law_status_kind", "jailed")
		var release_at := int(record.get("release_at_minute", -1))
		if release_at < 0:
			actor.set_meta("law_sentence_summary", "Awaiting sentence")
		else:
			actor.set_meta("law_sentence_summary", "Sentence: %s remaining" % _minutes_label(max(0, release_at - _now_minute())))
		return
	actor.set_meta("law_status_label", _caught_crime_status_label(_latest_crime_type(record)))
	actor.set_meta("law_status_kind", "caught")
	actor.remove_meta("law_sentence_summary")


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


func _find_settlement_for_warrant(actor: HumanoidCharacter, warrant: Dictionary) -> Node:
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
	if target is HumanoidCharacter:
		return _actor_key(target as HumanoidCharacter)
	if target is Node:
		return str((target as Node).get_path()) if (target as Node).is_inside_tree() else str((target as Node).name)
	return ""


func _actor_key(actor: HumanoidCharacter) -> String:
	if actor == null:
		return ""
	return actor.stable_id if not actor.stable_id.strip_edges().is_empty() else str(actor.get_instance_id())


func _find_actor_by_key(actor_key: String) -> HumanoidCharacter:
	if actor_key.is_empty() or root_scene == null or not root_scene.is_inside_tree():
		return null
	for node in root_scene.get_tree().get_nodes_in_group("humanoid_character"):
		var actor := node as HumanoidCharacter
		if actor != null and _actor_key(actor) == actor_key:
			return actor
	return null


func _get_perception_controller() -> Node:
	if root_scene == null:
		return null
	var bootstrap := root_scene.get_node_or_null("GameBootstrap")
	return bootstrap.get_node_or_null("PerceptionController") if bootstrap != null else null


func _connect_world_time() -> void:
	if world_time == null and get_parent() != null:
		world_time = get_parent().get_node_or_null("WorldTimeController")
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
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	var existing := get_tree().get_first_node_in_group("gecs_world_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	if parent_node == null:
		return null
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	parent_node.add_child(bridge)
	bridge.call("initialize", root_scene if root_scene != null else parent_node)
	return bridge


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
