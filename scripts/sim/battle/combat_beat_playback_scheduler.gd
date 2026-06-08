extends RefCounted

class_name CombatBeatPlaybackScheduler

const DEFAULT_DETAILED_BEAT_LIMIT := 32
const MOVE_TO_SLOT_DURATION := 0.35
const FACE_TARGET_DURATION := 0.15
const ATTACK_DURATION := 0.40
const REACTION_DURATION := 0.30
const EVENTS_PER_DETAILED_BEAT := 4


static func build_schedule(beats: Array, engagement_groups: Array, combat_slots: Dictionary, config: Dictionary = {}) -> Dictionary:
	var source_beats := _dictionary_array(beats)
	var detailed_beat_limit := maxi(0, int(config.get("detailed_beat_limit", DEFAULT_DETAILED_BEAT_LIMIT)))
	var detailed_beat_ids := _selected_detailed_beat_ids(source_beats, detailed_beat_limit)
	var detailed_beat_lookup := _id_lookup(detailed_beat_ids)
	var events: Array[Dictionary] = []
	var summarized_beats: Array[Dictionary] = []
	var group_next_time := {}
	for beat in source_beats:
		var beat_id := str(beat.get("beat_id", "")).strip_edges()
		if not detailed_beat_lookup.has(beat_id):
			summarized_beats.append(_summarized_beat_record(beat))
			continue
		var group_id := str(beat.get("engagement_group_id", "")).strip_edges()
		var start_time := float(group_next_time.get(group_id, 0.0))
		group_next_time[group_id] = _append_detailed_beat_events(events, beat, start_time)
	events.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_start := float(first.get("start_time", 0.0))
		var second_start := float(second.get("start_time", 0.0))
		if not is_equal_approx(first_start, second_start):
			return first_start < second_start
		return str(first.get("event_id", "")) < str(second.get("event_id", ""))
	)
	return {
		"events": events,
		"summarized_beats": summarized_beats,
		"detailed_beat_ids": detailed_beat_ids,
		"summarized_beat_ids": _summarized_beat_ids(summarized_beats),
		"detailed_beat_limit": detailed_beat_limit,
		"total_beat_count": source_beats.size(),
		"source_beat_count": source_beats.size(),
		"detailed_beat_count": detailed_beat_ids.size(),
		"skipped_beat_count": summarized_beats.size(),
		"summarized_beat_count": summarized_beats.size(),
		"summarized_event_count": summarized_beats.size(),
		"event_count": events.size(),
		"scheduled_event_count": events.size(),
		"detailed_event_count": events.size(),
		"skipped_event_count": summarized_beats.size() * EVENTS_PER_DETAILED_BEAT,
		"max_detailed_event_count": detailed_beat_limit * EVENTS_PER_DETAILED_BEAT,
		"engagement_group_count": engagement_groups.size(),
		"combat_slot_count": combat_slots.size(),
		"strategy": "prioritize_important_then_earliest",
		"complexity": "O(B log B + E)",
		"presentation_only": true,
	}


static func _selected_detailed_beat_ids(beats: Array[Dictionary], detailed_beat_limit: int) -> Array[String]:
	var selected_ids: Array[String] = []
	if detailed_beat_limit <= 0:
		return selected_ids
	var important_beats: Array[Dictionary] = []
	var normal_beats: Array[Dictionary] = []
	for beat in beats:
		if _beat_is_important(beat):
			important_beats.append(beat)
		else:
			normal_beats.append(beat)
	important_beats.sort_custom(_beat_sort_less)
	normal_beats.sort_custom(_beat_sort_less)
	_append_selected_beat_ids(selected_ids, important_beats, detailed_beat_limit)
	_append_selected_beat_ids(selected_ids, normal_beats, detailed_beat_limit)
	return selected_ids


static func _append_selected_beat_ids(selected_ids: Array[String], beats: Array[Dictionary], detailed_beat_limit: int) -> void:
	for beat in beats:
		if selected_ids.size() >= detailed_beat_limit:
			return
		var beat_id := str(beat.get("beat_id", "")).strip_edges()
		if not beat_id.is_empty() and not selected_ids.has(beat_id):
			selected_ids.append(beat_id)


static func _append_detailed_beat_events(events: Array[Dictionary], beat: Dictionary, start_time: float) -> float:
	var cursor := start_time
	cursor = _append_event(events, beat, "move_to_slot", cursor, MOVE_TO_SLOT_DURATION)
	cursor = _append_event(events, beat, "face_target", cursor, FACE_TARGET_DURATION)
	cursor = _append_event(events, beat, "attack", cursor, ATTACK_DURATION)
	cursor = _append_event(events, beat, "reaction", cursor, REACTION_DURATION)
	return cursor


static func _append_event(events: Array[Dictionary], beat: Dictionary, event_type: String, start_time: float, duration: float) -> float:
	var beat_id := str(beat.get("beat_id", "")).strip_edges()
	events.append({
		"event_id": "%s:event:%s" % [beat_id, event_type],
		"beat_id": beat_id,
		"beat_index": int(beat.get("beat_index", 0)),
		"tick": int(beat.get("tick", 0)),
		"presentation_tick": int(beat.get("presentation_tick", 0)),
		"encounter_id": str(beat.get("encounter_id", "")),
		"engagement_group_id": str(beat.get("engagement_group_id", "")),
		"event_type": event_type,
		"attacker_member_id": str(beat.get("attacker_member_id", "")),
		"defender_member_id": str(beat.get("defender_member_id", "")),
		"attacker_squad_id": str(beat.get("attacker_squad_id", "")),
		"defender_squad_id": str(beat.get("defender_squad_id", "")),
		"attacker_slot_id": str(beat.get("attacker_slot_id", "")),
		"defender_slot_id": str(beat.get("defender_slot_id", "")),
		"start_time": start_time,
		"duration": duration,
		"importance": str(beat.get("importance", "normal")),
		"action": str(beat.get("action", "")),
		"result": str(beat.get("result", "")),
		"damage": float(beat.get("damage", 0.0)),
		"presentation_only": true,
	})
	return start_time + duration


static func _summarized_beat_record(beat: Dictionary) -> Dictionary:
	return {
		"beat_id": str(beat.get("beat_id", "")),
		"beat_index": int(beat.get("beat_index", 0)),
		"tick": int(beat.get("tick", 0)),
		"presentation_tick": int(beat.get("presentation_tick", 0)),
		"encounter_id": str(beat.get("encounter_id", "")),
		"engagement_group_id": str(beat.get("engagement_group_id", "")),
		"importance": str(beat.get("importance", "normal")),
		"summary_reason": "detailed_beat_limit",
		"presentation_only": true,
	}


static func _summarized_beat_ids(summarized_beats: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for record in summarized_beats:
		var beat_id := str(record.get("beat_id", "")).strip_edges()
		if not beat_id.is_empty():
			ids.append(beat_id)
	return ids


static func _id_lookup(ids: Array[String]) -> Dictionary:
	var lookup := {}
	for id in ids:
		lookup[id] = true
	return lookup


static func _beat_is_important(beat: Dictionary) -> bool:
	match str(beat.get("importance", "normal")):
		"high", "critical", "important":
			return true
		_:
			return false


static func _beat_sort_less(first: Dictionary, second: Dictionary) -> bool:
	var first_tick := int(first.get("presentation_tick", first.get("tick", 0)))
	var second_tick := int(second.get("presentation_tick", second.get("tick", 0)))
	if first_tick != second_tick:
		return first_tick < second_tick
	var first_index := int(first.get("beat_index", 0))
	var second_index := int(second.get("beat_index", 0))
	if first_index != second_index:
		return first_index < second_index
	return str(first.get("beat_id", "")) < str(second.get("beat_id", ""))


static func _dictionary_array(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in value:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result
