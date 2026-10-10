@tool
extends "res://features/audio/resources/game_sound_cue.gd"

## Spatial controls for the one shared successful-unlock cue.
@export_group("Playback")
@export var bus: StringName = &"Master"
@export_range(1.0, 200.0, 1.0, "suffix:m") var max_distance_m := 45.0
@export_range(0.1, 30.0, 0.1, "suffix:m") var unit_size_m := 6.0
@export_range(1, 32, 1) var max_voices := 8
