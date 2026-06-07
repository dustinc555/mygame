extends StaticBody3D

class_name WorldBuilding

@export var display_name := "Building"
@export var building_type := "generic"
@export var access_mode := "public"
@export var owner_faction_name := ""
@export var population_capacity_id := ""
@export_range(0, 1000, 1) var population_capacity := 0
@export var levels: Array[Resource] = []
@export var interior_area_path: NodePath
@export var roof_occluder_paths: Array[NodePath] = []
@export var front_occluder_paths: Array[NodePath] = []
@export var right_occluder_paths: Array[NodePath] = []
@export var back_occluder_paths: Array[NodePath] = []
@export var left_occluder_paths: Array[NodePath] = []


func _ready() -> void:
	add_to_group("world_building")
	if population_capacity > 0:
		add_to_group("population_capacity_source")


func get_population_capacity_id() -> String:
	var clean_id := population_capacity_id.strip_edges()
	if not clean_id.is_empty():
		return clean_id
	return str(get_path()).strip_edges() if is_inside_tree() else str(name)


func get_population_capacity_record(settlement_id := "") -> Dictionary:
	return {
		"capacity_id": get_population_capacity_id(),
		"settlement_id": settlement_id,
		"display_name": display_name if not display_name.is_empty() else get_population_capacity_id().capitalize(),
		"source_type": building_type if not building_type.is_empty() else "building",
		"world_position": global_position,
		"population_capacity": max(0, population_capacity),
	}


func get_building_record(settlement_id := "") -> Dictionary:
	return {
		"building_id": get_population_capacity_id(),
		"settlement_id": settlement_id,
		"display_name": display_name,
		"building_type": building_type,
		"access_mode": access_mode,
		"owner_faction_name": owner_faction_name,
		"population_capacity": max(0, population_capacity),
		"world_position": global_position,
		"level_count": levels.size(),
	}
