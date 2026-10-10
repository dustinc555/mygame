@icon("res://addons/world_authoring/icons/zone.svg")
extends Node3D

class_name Zone

## Zone concept root: one authored region of the open world (its own scene,
## typically containing a Terrain3D, towns, POIs, roads). Zones compose into
## a WorldRoot by plain child-node instancing — a zone is NOT married to its
## terrain or any specific child structure. Authored/edited through the
## world_authoring plugin.

const AMBIENT_MUSIC_PROFILE := preload("res://features/audio/resources/ambient_music_profile.gd")
signal ambient_music_changed

## Stable identifier for save/load, world-sim records, and cross-zone
## references. Defaults to the node name when left empty.
@export var zone_id := ""

@export_group("Music")
## Optional background music selections; this zone does not start playback.
@export var ambient_music: AMBIENT_MUSIC_PROFILE:
	set(value):
		if ambient_music == value:
			return
		ambient_music = value
		ambient_music_changed.emit()


func get_zone_id() -> String:
	return zone_id if not zone_id.is_empty() else String(name)
