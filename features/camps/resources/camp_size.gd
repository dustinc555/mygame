@tool
extends Resource

## Shared by the marker UI and durable camp generation. Distances are metres.
@export var display_name := "Medium"
@export_range(4, 100, 1) var population := 16
@export_range(3.0, 20.0, 0.5) var footprint_radius := 8.0
@export_range(0.1, 3.0, 0.05) var furnishing_multiplier := 1.0
