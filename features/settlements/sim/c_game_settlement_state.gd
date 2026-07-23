extends "res://addons/gecs/ecs/component.gd"

class_name CGameSettlementState

@export var settlement_id := ""
@export var faction_id := ""
@export var display_name := ""
@export var population := 0
@export var population_target := 0
@export var population_assigned := 0
@export var population_available := 0
@export var population_required_staff := 0
@export var population_bootstrap_unassigned := 0
@export var population_shortfall := 0
@export var population_initialized := false
@export var max_occupancy := 0
@export var occupancy_state := "populated"
@export var occupancy_label := "Populated"
@export var occupancy_multiplier := 1.0
@export var occupancy_ratio := 1.0
@export var morale := 1.0
@export var last_action_absolute_hour := -999999
@export var last_action := "Idle"
@export var world_position := Vector3.ZERO
@export var radius := 0.0
@export var constructed := false
@export var facilities: Dictionary = {}
@export var facility_totals: Dictionary = {}
@export var staff_slots: Dictionary = {}
@export var staff_vacancies: Dictionary = {}
@export var population_death_records: Dictionary = {}

var state: Dictionary = {}


func apply_state(source: Dictionary) -> void:
	settlement_id = str(source.get("settlement_id", settlement_id))
	faction_id = str(source.get("faction_id", faction_id))
	display_name = str(source.get("display_name", display_name))
	population = int(source.get("population", population))
	population_target = int(source.get("population_target", population_target))
	population_assigned = int(source.get("population_assigned", population_assigned))
	population_available = int(source.get("population_available", population_available))
	population_required_staff = int(source.get("population_required_staff", population_required_staff))
	population_bootstrap_unassigned = int(source.get("population_bootstrap_unassigned", population_bootstrap_unassigned))
	population_shortfall = int(source.get("population_shortfall", population_shortfall))
	population_initialized = bool(source.get("population_initialized", population_initialized))
	max_occupancy = int(source.get("max_occupancy", max_occupancy))
	occupancy_state = str(source.get("occupancy_state", occupancy_state))
	occupancy_label = str(source.get("occupancy_label", occupancy_label))
	occupancy_multiplier = float(source.get("occupancy_multiplier", occupancy_multiplier))
	occupancy_ratio = float(source.get("occupancy_ratio", occupancy_ratio))
	morale = float(source.get("morale", morale))
	last_action_absolute_hour = int(source.get("last_action_absolute_hour", last_action_absolute_hour))
	last_action = str(source.get("last_action", last_action))
	world_position = source.get("world_position", world_position)
	radius = float(source.get("radius", radius))
	constructed = bool(source.get("constructed", constructed))
	facilities = (source.get("facilities", facilities) as Dictionary).duplicate(true)
	facility_totals = (source.get("facility_totals", facility_totals) as Dictionary).duplicate(true)
	staff_slots = (source.get("staff_slots", staff_slots) as Dictionary).duplicate(true)
	staff_vacancies = (source.get("staff_vacancies", staff_vacancies) as Dictionary).duplicate(true)
	population_death_records = (source.get("population_death_records", population_death_records) as Dictionary).duplicate(true)
	state = to_state()


func to_state() -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"faction_id": faction_id,
		"display_name": display_name,
		"population": population,
		"population_target": population_target,
		"population_assigned": population_assigned,
		"population_available": population_available,
		"population_required_staff": population_required_staff,
		"population_bootstrap_unassigned": population_bootstrap_unassigned,
		"population_shortfall": population_shortfall,
		"population_initialized": population_initialized,
		"max_occupancy": max_occupancy,
		"occupancy_state": occupancy_state,
		"occupancy_label": occupancy_label,
		"occupancy_multiplier": occupancy_multiplier,
		"occupancy_ratio": occupancy_ratio,
		"morale": morale,
		"last_action_absolute_hour": last_action_absolute_hour,
		"last_action": last_action,
		"world_position": world_position,
		"radius": radius,
		"constructed": constructed,
		"facilities": facilities.duplicate(true),
		"facility_totals": facility_totals.duplicate(true),
		"staff_slots": staff_slots.duplicate(true),
		"staff_vacancies": staff_vacancies.duplicate(true),
		"population_death_records": population_death_records.duplicate(true),
	}
