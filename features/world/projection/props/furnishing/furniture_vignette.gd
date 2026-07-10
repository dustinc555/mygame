@tool
extends Node3D

class_name FurnitureVignette

## Hand-authored furniture arrangement (a table with its chairs, arranged
## with taste) stamped whole by the furnish pass — the solver never invents
## anything smaller than a room. Footprint is the reserved floor rect in
## meters (X by Z, centered on the root) used for collision-free placement.

@export var footprint_meters := Vector2(4.4, 3.4)
