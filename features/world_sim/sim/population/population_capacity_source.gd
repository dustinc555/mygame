@tool
extends Node3D

class_name PopulationCapacitySource

@export var capacity_id := ""
@export var display_name := "Population Capacity"
@export_enum("bedroll", "tent", "camp", "other") var source_type := "bedroll"
@export_range(0, 1000, 1) var population_capacity := 1
@export var enabled := true


func _ready() -> void:
	add_to_group("population_capacity_source")


func get_population_capacity_id() -> String:
	return capacity_id if not capacity_id.is_empty() else name


func get_population_capacity_record(settlement_id := "") -> Dictionary:
	return {
		"capacity_id": get_population_capacity_id(),
		"settlement_id": settlement_id,
		"display_name": display_name if not display_name.is_empty() else get_population_capacity_id().capitalize(),
		"source_type": source_type,
		"world_position": global_position,
		"population_capacity": max(0, population_capacity) if enabled else 0,
	}
