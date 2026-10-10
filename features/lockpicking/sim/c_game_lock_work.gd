extends "res://addons/gecs/ecs/component.gd"

## Door lock truth remains CGameDoorState. object_locked is used only for
## containers/cells. Work survives interruption, saves and projection unloading.
@export var lock_id := ""
@export var door_id := ""
@export var object_locked := true
@export var difficulty := 10.0
@export var minimum_skill := 0.0
@export var door_revision := -1
@export var progress := 0.0
@export var beat_elapsed := 0.0
@export var check_sequence := 0
