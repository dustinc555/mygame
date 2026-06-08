extends RefCounted

class_name CombatProjectionContinuityBuilder

const DEFAULT_RECENT_REPLAY_EVENT_LIMIT := 16
const LIFE_STATE_ALIVE := 0


static func build_continuity(encounter_record: Dictionary, battle_result: Dictionary, current_records: Dictionary = {}, config: Dictionary = {}) -> Dictionary:
	var encounter_id := str(encounter_record.get("encounter_id", battle_result.get("encounter_id", ""))).strip_edges()
	if encounter_id.is_empty():
		encounter_id = "encounter:untracked"
	var status := str(encounter_record.get("status", "")).strip_edges()
	if status.is_empty() and not battle_result.is_empty():
		status = "resolved"
	var projection_state := _projection_state_for_status(status)
	var member_states := _member_states(current_records, battle_result)
	var aftermath_member_ids := _aftermath_member_ids(member_states, battle_result)
	var engagement_groups := _dictionary_array(battle_result.get("engagement_groups", []))
	var combat_slots: Dictionary = battle_result.get("combat_slots", {}) if battle_result.get("combat_slots", {}) is Dictionary else {}
	var schedule: Dictionary = battle_result.get("combat_schedule", {}) if battle_result.get("combat_schedule", {}) is Dictionary else {}
	var recent_replay_event_limit := maxi(0, int(config.get("recent_replay_event_limit", DEFAULT_RECENT_REPLAY_EVENT_LIMIT)))
	var replay_event_ids := _replay_event_ids(schedule, status, recent_replay_event_limit)
	var summarized_event_ids := _summarized_event_ids(schedule, replay_event_ids)
	return {
		"encounter_id": encounter_id,
		"status": status,
		"projection_state": projection_state,
		"member_states": member_states,
		"active_group_ids": _active_group_ids(engagement_groups, projection_state),
		"active_slot_ids": _active_slot_ids(combat_slots, projection_state),
		"replay_event_ids": replay_event_ids,
		"summarized_event_ids": summarized_event_ids,
		"aftermath_member_ids": aftermath_member_ids,
		"recent_replay_event_limit": recent_replay_event_limit,
		"source_event_count": _schedule_events(schedule).size(),
		"presentation_only": true,
	}


static func _projection_state_for_status(status: String) -> String:
	match status:
		"resolved":
			return "aftermath"
		"engaged", "resolving":
			return "active"
		_:
			return "inactive"


static func _member_states(current_records: Dictionary, battle_result: Dictionary) -> Dictionary:
	var states := {}
	for record in _current_member_records(current_records):
		var member_state := _member_state_from_record(record)
		var member_id := str(member_state.get("member_id", "")).strip_edges()
		if not member_id.is_empty():
			states[member_id] = member_state
	for casualty in _battle_member_casualties(battle_result):
		var casualty_state := _member_state_from_casualty(casualty)
		var casualty_member_id := str(casualty_state.get("member_id", "")).strip_edges()
		if casualty_member_id.is_empty() or states.has(casualty_member_id):
			continue
		states[casualty_member_id] = casualty_state
	return states


static func _current_member_records(current_records: Dictionary) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for record in _dictionary_array(current_records.get("member_records", [])):
		records.append(record)
	for squad_record in _dictionary_array(current_records.get("squad_records", [])):
		for member_record in _dictionary_array(squad_record.get("member_records", [])):
			var record := member_record.duplicate(true)
			if str(record.get("squad_id", "")).strip_edges().is_empty():
				record["squad_id"] = str(squad_record.get("squad_id", "")).strip_edges()
			records.append(record)
	return records


static func _member_state_from_record(record: Dictionary) -> Dictionary:
	var member_id := _stable_member_id(record)
	var life_state := int(record.get("life_state", LIFE_STATE_ALIVE))
	var max_hp := float(record.get("max_hp", 0.0))
	var hp := float(record.get("hp", max_hp))
	var max_blood := float(record.get("max_blood", 0.0))
	var blood := float(record.get("blood", max_blood))
	return {
		"member_id": member_id,
		"actor_id": str(record.get("actor_id", "")).strip_edges(),
		"stable_id": str(record.get("stable_id", member_id)).strip_edges(),
		"squad_id": str(record.get("squad_id", "")).strip_edges(),
		"life_state": life_state,
		"hp": hp,
		"max_hp": max_hp,
		"blood": blood,
		"max_blood": max_blood,
		"projection_life_state": _projection_life_state(life_state, hp, blood),
		"presentation_only": true,
	}


static func _member_state_from_casualty(casualty: Dictionary) -> Dictionary:
	var member_id := _stable_member_id(casualty)
	var life_state := int(casualty.get("life_state", 5))
	return {
		"member_id": member_id,
		"actor_id": str(casualty.get("actor_id", "")).strip_edges(),
		"stable_id": str(casualty.get("stable_id", member_id)).strip_edges(),
		"squad_id": str(casualty.get("squad_id", "")).strip_edges(),
		"life_state": life_state,
		"hp": 0.0,
		"max_hp": 0.0,
		"blood": 0.0,
		"max_blood": 0.0,
		"projection_life_state": "aftermath",
		"casualty_state": str(casualty.get("casualty_state", "casualty")),
		"presentation_only": true,
	}


static func _projection_life_state(life_state: int, hp: float, blood: float) -> String:
	if life_state != LIFE_STATE_ALIVE:
		return "aftermath"
	if hp <= 0.0 or blood <= 0.0:
		return "downed"
	return "active"


static func _aftermath_member_ids(member_states: Dictionary, battle_result: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for member_id_value in member_states.keys():
		var member_id := str(member_id_value).strip_edges()
		var state: Dictionary = member_states.get(member_id, {}) if member_states.get(member_id, {}) is Dictionary else {}
		if str(state.get("projection_life_state", "")) == "aftermath" or str(state.get("projection_life_state", "")) == "downed":
			ids.append(member_id)
	for casualty in _battle_member_casualties(battle_result):
		var casualty_member_id := _stable_member_id(casualty)
		if not casualty_member_id.is_empty() and not ids.has(casualty_member_id):
			ids.append(casualty_member_id)
	ids.sort()
	return ids


static func _battle_member_casualties(battle_result: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var member_casualties = battle_result.get("member_casualties", {})
	if not (member_casualties is Dictionary):
		return result
	for squad_id in (member_casualties as Dictionary).keys():
		var entries = (member_casualties as Dictionary).get(squad_id, [])
		if not (entries is Array):
			continue
		for entry in entries:
			if entry is Dictionary:
				var casualty: Dictionary = (entry as Dictionary).duplicate(true)
				if str(casualty.get("squad_id", "")).strip_edges().is_empty():
					casualty["squad_id"] = str(squad_id)
				result.append(casualty)
	return result


static func _active_group_ids(engagement_groups: Array[Dictionary], projection_state: String) -> Array[String]:
	var ids: Array[String] = []
	if projection_state != "active":
		return ids
	for group in engagement_groups:
		var group_id := str(group.get("engagement_group_id", "")).strip_edges()
		if not group_id.is_empty():
			ids.append(group_id)
	return ids


static func _active_slot_ids(combat_slots: Dictionary, projection_state: String) -> Array[String]:
	var ids: Array[String] = []
	if projection_state != "active":
		return ids
	for slot_id_value in combat_slots.keys():
		var slot_id := str(slot_id_value).strip_edges()
		if not slot_id.is_empty():
			ids.append(slot_id)
	ids.sort()
	return ids


static func _replay_event_ids(schedule: Dictionary, status: String, recent_replay_event_limit: int) -> Array[String]:
	var ids: Array[String] = []
	if recent_replay_event_limit <= 0:
		return ids
	var events := _schedule_events(schedule)
	var candidates: Array[Dictionary] = []
	for event in events:
		if status == "resolved" and not _event_is_important(event):
			continue
		candidates.append(event)
	candidates.sort_custom(_event_replay_sort_less)
	for event in candidates:
		if ids.size() >= recent_replay_event_limit:
			break
		var event_id := str(event.get("event_id", "")).strip_edges()
		if not event_id.is_empty():
			ids.append(event_id)
	ids.sort()
	return ids


static func _summarized_event_ids(schedule: Dictionary, replay_event_ids: Array[String]) -> Array[String]:
	var replay_lookup := {}
	for replay_event_id in replay_event_ids:
		replay_lookup[replay_event_id] = true
	var ids: Array[String] = []
	for event in _schedule_events(schedule):
		var event_id := str(event.get("event_id", "")).strip_edges()
		if event_id.is_empty() or replay_lookup.has(event_id):
			continue
		ids.append(event_id)
	ids.sort()
	return ids


static func _schedule_events(schedule: Dictionary) -> Array[Dictionary]:
	return _dictionary_array(schedule.get("events", []))


static func _event_is_important(event: Dictionary) -> bool:
	match str(event.get("importance", "normal")):
		"high", "critical", "important":
			return true
		_:
			return false


static func _event_replay_sort_less(first: Dictionary, second: Dictionary) -> bool:
	var first_rank := _event_importance_rank(first)
	var second_rank := _event_importance_rank(second)
	if first_rank != second_rank:
		return first_rank > second_rank
	var first_result_rank := _event_result_rank(first)
	var second_result_rank := _event_result_rank(second)
	if first_result_rank != second_result_rank:
		return first_result_rank > second_result_rank
	var first_start := float(first.get("start_time", 0.0))
	var second_start := float(second.get("start_time", 0.0))
	if not is_equal_approx(first_start, second_start):
		return first_start > second_start
	return str(first.get("event_id", "")) < str(second.get("event_id", ""))


static func _event_importance_rank(event: Dictionary) -> int:
	match str(event.get("importance", "normal")):
		"critical":
			return 3
		"high", "important":
			return 2
		_:
			return 1


static func _event_result_rank(event: Dictionary) -> int:
	var event_type := str(event.get("event_type", ""))
	if event_type == "reaction":
		return 2
	return 1


static func _stable_member_id(record: Dictionary) -> String:
	for key in ["member_id", "actor_id", "stable_id"]:
		var value := str(record.get(key, "")).strip_edges()
		if not value.is_empty():
			return value
	return ""


static func _dictionary_array(value) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for entry in value:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result
