extends Resource

class_name ModularBuildingPieceDefinition

@export var piece_id := ""
@export var display_name := ""
@export_enum("floor", "wall", "wall_door", "wall_window", "window", "door", "corner", "roof", "roof_front", "stairs", "door_frame") var category := "wall"
@export var scene: PackedScene
@export var source_scene: PackedScene
@export var grid_cell_size_meters := 2.0
@export var grid_size_cells := Vector3i.ONE
@export var bounds_size_meters := Vector3.ZERO
@export var tags: PackedStringArray = PackedStringArray()
@export var snap_points: Array = []


func get_piece_id() -> String:
	return piece_id


func get_display_name() -> String:
	return display_name if not display_name.is_empty() else piece_id.capitalize()


func get_snap_point(snap_id: String) -> Resource:
	for snap_point in snap_points:
		if snap_point != null and snap_point.snap_id == snap_id:
			return snap_point
	return null
