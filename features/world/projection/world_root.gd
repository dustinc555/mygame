@icon("res://addons/world_authoring/icons/world.svg")
extends Node3D

class_name WorldRoot

## World concept root: the top of the authoring ladder. A world composes Zone
## scenes (positioned relative to each other), and is what the world_authoring
## plugin operates on for world-level workflows such as navmesh baking.
## (Named WorldRoot because GECS reserves the class name `World`.)

const ZONE_SCRIPT := preload("res://features/world/projection/zone_root.gd")

## Stable identifier for save/load and tooling. Defaults to the node name.
@export var world_id := ""


func get_world_id() -> String:
	return world_id if not world_id.is_empty() else name


func get_zones() -> Array[Node3D]:
	var zones: Array[Node3D] = []
	for child in get_children():
		if child is ZONE_SCRIPT:
			zones.append(child)
	return zones
