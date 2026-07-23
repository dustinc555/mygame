extends Resource

class_name PlaceableBuildingDefinition

## One construction assignment for a neutral shell. Gameplay type, access,
## and capacity here seed the building record; they are deliberately not
## authored into the reusable shell scene. Records reference entries by stable
## `building_id`, so scenes can move on disk without breaking saves.

@export var building_id := ""
@export var display_name := ""
@export var type_id := "generic"
@export var housing_capacity := 0
@export var access_state := "private"
@export var scene: PackedScene
## Ground footprint (meters) used for slope sampling and border sizing.
@export var footprint_size := Vector2(14.0, 8.0)


func get_id() -> String:
	return building_id if not building_id.is_empty() else display_name
