@tool
extends Resource

const FireLoopCue = preload("res://features/audio/resources/fire_loop_cue.gd")

@export_group("Fire Recordings")
@export var small_flame: FireLoopCue
@export var campfire: FireLoopCue
@export_group("Spatial Mix")
@export_range(1.0, 30.0, 0.5, "suffix:m") var small_flame_distance_m := 6.0
@export_range(1.0, 60.0, 0.5, "suffix:m") var campfire_distance_m := 33.0
## Campfire inverse-distance reference size. Small flames use their cutoff's linear fade only.
@export_range(0.1, 5.0, 0.1, "suffix:m") var unit_size_m := 1.0
@export var bus: StringName = &"SFX"
@export_group("Voice Budget")
@export_range(1, 32, 1) var max_audible_fires := 8
## Wall-clock cadence, not world-time. Only registered lit furniture is considered.
@export_range(0.1, 1.0, 0.05, "suffix:s") var listener_refresh_seconds := 0.25
## Incumbents are ranked this much nearer, avoiding swaps at an equal-distance boundary.
@export_range(0.5, 1.0, 0.05) var voice_retention_ratio := 0.85


func cue_for_kind(kind: int) -> FireLoopCue:
	match kind:
		1: return small_flame
		2: return campfire
	return null


func distance_for_kind(kind: int) -> float:
	return maxf(1.0, campfire_distance_m if kind == 2 else small_flame_distance_m)
