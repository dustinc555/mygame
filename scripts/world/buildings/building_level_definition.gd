extends Resource

class_name BuildingLevelDefinition

@export var display_name := "Level"
@export var occupancy_area_path: NodePath
@export var min_local_y := -INF
@export var max_local_y := INF
@export var click_local_y := 0.0
@export var content_paths: Array[NodePath] = []
@export var front_occluder_paths: Array[NodePath] = []
@export var right_occluder_paths: Array[NodePath] = []
@export var back_occluder_paths: Array[NodePath] = []
@export var left_occluder_paths: Array[NodePath] = []
@export var is_roof := false
