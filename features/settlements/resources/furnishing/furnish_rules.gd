@tool
extends Resource

class_name FurnishRules

## Per-facility-type furnishing recipe consumed by FacilityFurnisher. All
## taste dials live here (what to place, how much); placement strategy and
## walkability guarantees live in the solver. One .tres per facility type
## (bar.tres first).

## Counter pool (one is placed against the wall farthest from the door).
@export var counter_scenes: Array[PackedScene] = []
## Counter floor footprint in meters (width along the wall, depth into room).
@export var counter_footprint := Vector2(1.9, 1.0)
## Walk strip reserved between wall and counter for the staff member.
@export var counter_staff_strip_meters := 0.9

## Hand-authored table vignettes (FurnitureVignette roots), stamped whole.
@export var cluster_scenes: Array[PackedScene] = []
## One cluster per this many square meters of free interior floor.
@export var square_meters_per_cluster := 14.0
@export var max_clusters := 3

## Wall shelves, rolled per solid interior wall segment.
@export var shelf_scenes: Array[PackedScene] = []
@export_range(0.0, 1.0, 0.05) var shelf_chance := 0.45
@export var shelf_mount_height := 1.6

## Beds for the upper floors, headboard against a wall.
@export var bed_scenes: Array[PackedScene] = []
@export var max_beds := 4
@export_range(0.0, 1.0, 0.05) var bed_chance := 0.55
## Bed floor footprint (width along wall, length into room).
@export var bed_footprint := Vector2(2.0, 2.6)
