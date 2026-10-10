extends "res://addons/gecs/ecs/component.gd"

## Campaign start receipt and explicitly created player squads. Membership itself
## remains on the canonical population/actor faction records.
@export var start_applied := false
@export var scenario_id := ""
@export var squad_names := PackedStringArray()
