extends "res://scripts/world_sim/settlement_anchor.gd"

class_name SettlementTown

const SETTLEMENT_STAFF_SLOT_UTILS := preload("res://scripts/world_sim/settlement_staff_slot_utils.gd")

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
	SETTLEMENT_STAFF_SLOT_UTILS.collect_authored_staff_slots(self, self, slots)
	if slots.is_empty() and guard_count > 0:
		for index in range(guard_count):
			slots.append(SETTLEMENT_STAFF_SLOT_UTILS.staff_slot_record(self, "%s.guard.%d" % [get_settlement_id(), index], "guard", index, guard_name, false, null))
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
