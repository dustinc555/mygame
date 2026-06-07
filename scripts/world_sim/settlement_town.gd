extends "res://scripts/world_sim/settlement_anchor.gd"

class_name SettlementTown

@export_range(0, 128, 1) var guard_count := 0
@export_range(0, 128, 1) var guard_post_count := 0
@export var guard_name := "Guard"
@export var staff_stable_id_prefix := ""
@export var staff_squad_name := ""
@export var town_border_radius := 0.0
@export var town_border_debug_color := Color(0.35, 0.78, 1.0, 0.34)
@export var actor_realization_policy := ""


func _ready() -> void:
	super._ready()
	add_to_group("settlement_town")


func get_facility_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	_collect_facility_records(self, get_settlement_id(), records)
	return records


func get_population_capacity_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var seen := {}
	_collect_population_capacity_records(self, get_settlement_id(), records, seen)
	return records


func get_activity_points() -> Array:
	var points: Array = []
	_collect_activity_points(self, points)
	return points


func get_settlement_staff_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	_collect_authored_staff_slots(self, slots)
	if slots.is_empty() and guard_count > 0:
		for index in range(guard_count):
			slots.append(_staff_slot_record("%s.guard.%d" % [get_settlement_id(), index], "guard", index, guard_name, false, null))
	return slots


func get_town_border_record() -> Dictionary:
	return {
		"settlement_id": get_settlement_id(),
		"world_position": global_position,
		"radius": maxf(town_border_radius, 0.0),
		"debug_color": town_border_debug_color,
	}


func get_resident_characters() -> Array:
	return []


func _collect_facility_records(root: Node, settlement_id: String, records: Array[Dictionary]) -> void:
	for child in root.get_children():
		if child.has_method("get_facility_record"):
			var record = child.call("get_facility_record", settlement_id)
			if record is Dictionary:
				records.append((record as Dictionary).duplicate(true))
		_collect_facility_records(child, settlement_id, records)


func _collect_population_capacity_records(root: Node, settlement_id: String, records: Array[Dictionary], seen: Dictionary) -> void:
	for child in root.get_children():
		if child.has_method("get_population_capacity_record"):
			var record = child.call("get_population_capacity_record", settlement_id)
			if record is Dictionary:
				var capacity_id := str((record as Dictionary).get("capacity_id", ""))
				if not capacity_id.is_empty() and not seen.has(capacity_id):
					seen[capacity_id] = true
					records.append((record as Dictionary).duplicate(true))
		_collect_population_capacity_records(child, settlement_id, records, seen)


func _collect_activity_points(root: Node, points: Array) -> void:
	for child in root.get_children():
		if child.has_method("get_activity_record"):
			points.append(child)
		_collect_activity_points(child, points)


func _collect_authored_staff_slots(root: Node, slots: Array[Dictionary]) -> void:
	for child in root.get_children():
		if child.has_meta("settlement_staff_slot_id"):
			var slot_id := str(child.get_meta("settlement_staff_slot_id", "")).strip_edges()
			if not slot_id.is_empty():
				var role_id := str(child.get_meta("settlement_staff_role", "guard")).strip_edges()
				var role_index := int(child.get_meta("settlement_staff_role_index", 0))
				slots.append(_staff_slot_record(slot_id, role_id, role_index, _actor_display_name(child), true, child))
		_collect_authored_staff_slots(child, slots)


func _staff_slot_record(slot_id: String, role_id: String, role_index: int, display: String, filled: bool, actor: Node) -> Dictionary:
	var record := {
		"slot_id": slot_id,
		"role_id": role_id if not role_id.is_empty() else "guard",
		"role_index": role_index,
		"display_name": display if not display.is_empty() else slot_id.capitalize(),
		"population_cost": 1,
		"filled": filled,
	}
	if actor != null:
		record["actor_id"] = _actor_id(actor)
		record["actor_path"] = get_path_to(actor) if actor.is_inside_tree() else NodePath()
	return record


func _actor_display_name(actor: Node) -> String:
	if _has_property(actor, "member_name"):
		var value := str(actor.get("member_name")).strip_edges()
		if not value.is_empty():
			return value
	return str(actor.name)


func _actor_id(actor: Node) -> String:
	if _has_property(actor, "stable_id"):
		var value := str(actor.get("stable_id")).strip_edges()
		if not value.is_empty():
			return value
	return str(actor.get_path()) if actor.is_inside_tree() else str(actor.get_instance_id())


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
