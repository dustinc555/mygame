extends "res://addons/gecs/ecs/component.gd"

class_name CGameBuildingRecord

@export var building_id := ""
@export var settlement_id := ""
@export var facility_id := ""
@export var type_id := "generic"
@export var display_name := "Building"
@export var owner_faction_id := ""
@export var access_state := "public"
@export var abandoned := false
@export var operational_state := "operational"
@export var bed_count := 0
@export var housing_capacity := 0
@export var world_transform := Transform3D.IDENTITY
@export_enum("authored", "constructed") var source := "authored"
@export var catalog_id := ""
@export var foundation_height := 0.0


func apply_record(record: Dictionary) -> void:
	building_id = str(record.get("building_id", building_id)).strip_edges()
	settlement_id = str(record.get("settlement_id", settlement_id)).strip_edges()
	facility_id = str(record.get("facility_id", facility_id)).strip_edges()
	type_id = str(record.get("type_id", type_id)).strip_edges()
	display_name = str(record.get("display_name", display_name))
	owner_faction_id = str(record.get("owner_faction_id", owner_faction_id)).strip_edges()
	access_state = str(record.get("access_state", access_state)).strip_edges()
	abandoned = bool(record.get("abandoned", abandoned))
	operational_state = str(record.get("operational_state", operational_state)).strip_edges()
	bed_count = maxi(0, int(record.get("bed_count", bed_count)))
	housing_capacity = maxi(0, int(record.get("housing_capacity", housing_capacity)))
	world_transform = record.get("world_transform", world_transform) as Transform3D
	source = str(record.get("source", source)).strip_edges()
	catalog_id = str(record.get("catalog_id", catalog_id)).strip_edges()
	foundation_height = float(record.get("foundation_height", foundation_height))


func to_record() -> Dictionary:
	return {
		"building_id": building_id,
		"settlement_id": settlement_id,
		"facility_id": facility_id,
		"type_id": type_id,
		"display_name": display_name,
		"owner_faction_id": owner_faction_id,
		"access_state": access_state,
		"abandoned": abandoned,
		"operational_state": operational_state,
		"bed_count": bed_count,
		"housing_capacity": housing_capacity,
		"world_transform": world_transform,
		"source": source,
		"catalog_id": catalog_id,
		"foundation_height": foundation_height,
	}
