extends Resource

class_name ModularBuildingSnapPoint

@export var snap_id := ""
@export var display_name := ""
@export var connector_type := ""
@export var accepts_types: PackedStringArray = PackedStringArray()
@export var local_transform := Transform3D.IDENTITY


func accepts(connector: String) -> bool:
	return not connector.is_empty() and accepts_types.has(connector)
