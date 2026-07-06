@icon("res://addons/world_authoring/icons/zone.svg")
extends Node3D

class_name Zone

## Zone concept root: one authored region of the open world (its own scene,
## typically containing a Terrain3D, towns, POIs, roads). Zones compose into
## a WorldRoot by plain child-node instancing — a zone is NOT married to its
## terrain or any specific child structure. Authored/edited through the
## world_authoring plugin.

## Stable identifier for save/load, world-sim records, and cross-zone
## references. Defaults to the node name when left empty.
@export var zone_id := ""


func get_zone_id() -> String:
	return zone_id if not zone_id.is_empty() else name
