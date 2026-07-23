@tool
extends Node3D

class_name FurnitureVignette

## Furnisher-only layout stencil. Its children are saved as individual,
## directly editable furniture nodes; this container never enters a facility.
## Footprint is the reserved floor rect in meters (X by Z, centered on root).

@export var footprint_meters := Vector2(4.4, 3.4)
