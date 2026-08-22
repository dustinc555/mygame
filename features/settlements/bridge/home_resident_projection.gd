extends RefCounted

class_name HomeResidentProjection

const FACILITY_DUTY_CONTRACT = preload("res://features/settlements/sim/facility_duty_contract.gd")

var _facility: Node
var _seats: Array[Node] = []
var _beds: Array[Node] = []
var _furniture_cached := false


func setup(facility: Node) -> void:
	_facility = facility


func refresh(actor: Node, slot_record: Dictionary) -> void:
	if _facility == null or not is_instance_valid(_facility) or str(slot_record.get("assignment_domain", "")) != "residence":
		return
	if actor == null or not actor.has_method("get_interaction") or int(actor.get("life_state")) == NpcRules.LifeState.DEAD:
		return
	if actor.has_method("has_active_player_order") and bool(actor.call("has_active_player_order")):
		return
	if actor.has_meta(&"active_settlement_work") or FACILITY_DUTY_CONTRACT.is_active(actor):
		return
	if actor.has_method("is_in_combat") and bool(actor.call("is_in_combat")):
		return
	var interaction = actor.call("get_interaction")
	if interaction == null:
		return
	_cache_furniture()
	var routine_activity := str(slot_record.get("routine_activity_state", "home_day"))
	if routine_activity == "home_sleep":
		_refresh_sleep(actor, interaction)
	elif routine_activity == "home_day":
		_refresh_day_idle(actor, interaction)


func _refresh_sleep(actor: Node, interaction) -> void:
	if int(actor.get("life_state")) == NpcRules.LifeState.ASLEEP:
		return
	for bed in _beds:
		if bed == null or not is_instance_valid(bed) or not bool(bed.call("claim_sleeper", actor)):
			continue
		interaction.stop_seat_assignment()
		interaction.assign_sleep_target(bed, false)
		if interaction.current_sleep_target == bed:
			return
		bed.call("release_sleeper", actor)


func _refresh_day_idle(actor: Node, interaction) -> void:
	if int(actor.get("life_state")) == NpcRules.LifeState.ASLEEP:
		interaction.stop_sleep_assignment()
		return
	if interaction.current_sleep_target != null:
		interaction.release_sleep_target_without_waking()
	for seat in _seats:
		if seat == null or not is_instance_valid(seat) or not bool(seat.call("claim_sitter", actor)):
			continue
		interaction.assign_seat_target(seat, false)
		if interaction.current_seat_target == seat:
			return
		seat.call("release_sitter", actor)


func _cache_furniture() -> void:
	if _furniture_cached:
		return
	_furniture_cached = true
	_collect_furniture(_facility.get_node_or_null("Furniture"))
	_seats.sort_custom(func(a: Node, b: Node) -> bool: return str(a.get_path()) < str(b.get_path()))
	_beds.sort_custom(func(a: Node, b: Node) -> bool: return str(a.get_path()) < str(b.get_path()))


func _collect_furniture(node: Node) -> void:
	if node == null:
		return
	if node.has_method("claim_sitter") and node.has_method("get_seat_position") and node.has_method("get_interaction_position"):
		_seats.append(node)
	elif node.has_method("claim_sleeper") and node.has_method("get_sleep_position") and node.has_method("get_interaction_position"):
		_beds.append(node)
	for child in node.get_children():
		_collect_furniture(child)
