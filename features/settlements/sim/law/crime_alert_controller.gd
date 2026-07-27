extends Node

class_name CrimeAlertController

const SERVICE_ID := &"crime_alert"
const EVENT_LIFETIME_SECONDS := 15.0

signal crime_event_emitted(event_record: Dictionary)

var _factions: FactionController
var _events: Dictionary = {}
var _next_event_sequence := 1


func initialize(context: BootstrapContext) -> void:
	_factions = context.get_optional(FactionController.SERVICE_ID) as FactionController


func create_event(actor: WorldActor, faction_id: String, settlement_id: String, crime_type: String, severity: int, witness: WorldActor, context: Dictionary) -> Dictionary:
	var origin = context.get("event_origin", actor.global_position if actor != null else Vector3.ZERO)
	if not (origin is Vector3):
		origin = actor.global_position if actor != null else Vector3.ZERO
	var event_id := "crime_event:%d" % _next_event_sequence
	_next_event_sequence += 1
	var event_record := {
		"event_id": event_id,
		"crime_type": crime_type,
		"offender_actor_id": _actor_id(actor),
		"witness_actor_id": _actor_id(witness),
		"reporter_faction_id": witness.faction_name if witness != null else faction_id,
		"faction_id": faction_id,
		"settlement_id": settlement_id,
		"origin": origin,
		"radius": NpcRules.NPC_ALERT_PROXIMITY_RADIUS,
		"severity": severity,
		"remaining_seconds": EVENT_LIFETIME_SECONDS,
	}
	_events[event_id] = event_record
	crime_event_emitted.emit(event_record.duplicate(true))
	return event_record


func advance(delta: float) -> void:
	for event_id_value in _events.keys():
		var event_id := str(event_id_value)
		var event_record: Dictionary = _events[event_id]
		var remaining := float(event_record.get("remaining_seconds", 0.0)) - maxf(delta, 0.0)
		if remaining <= 0.0:
			_events.erase(event_id)
			continue
		event_record["remaining_seconds"] = remaining
		_events[event_id] = event_record


func get_active_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event_record in _events.values():
		result.append((event_record as Dictionary).duplicate(true))
	return result


func get_alert_radius() -> float:
	return NpcRules.NPC_ALERT_PROXIMITY_RADIUS


func crime_is_illegal_for_faction(crime_type: String, faction_id: String) -> bool:
	var profile := _law_profile(faction_id)
	if profile == null:
		return true
	match crime_type:
		"theft":
			return str(profile.get("theft_response")) != "ignored"
		"trespass":
			return str(profile.get("trespass_escalation")) != "warning_only"
		_:
			return true


func _law_profile(faction_id: String) -> Resource:
	if _factions == null:
		return null
	var definition := _factions.get_faction_definition(faction_id)
	return definition.get_law_profile() if definition != null and definition.has_method("get_law_profile") else null


func _actor_id(actor: Node) -> String:
	if actor == null:
		return ""
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).strip_edges().is_empty():
		return str(stable_id).strip_edges()
	return str(actor.get_meta("actor_record_id", "")).strip_edges()
