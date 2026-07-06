extends Resource

class_name PlaceableBuildingDefinition

## One building the construction system can place. The record stored in the
## construction controller references buildings by stable `building_id`, so
## scenes can move on disk without breaking saves.

@export var building_id := ""
@export var display_name := ""
@export var scene: PackedScene
## Ground footprint (meters) used for slope sampling and border sizing.
@export var footprint_size := Vector2(14.0, 8.0)


func get_id() -> String:
	return building_id if not building_id.is_empty() else display_name
