@tool
@icon("res://addons/world_authoring/icons/world.svg")
extends Node3D

class_name WorldRoot

## World concept root: the top of the authoring ladder. A world composes Zone
## scenes (positioned relative to each other), and is what the world_authoring
## plugin operates on for world-level workflows such as navmesh baking.
## (Named WorldRoot because GECS reserves the class name `World`.)

const ZONE_SCRIPT := preload("res://features/world/projection/zone_root.gd")
const MAP_SETTINGS := preload("res://features/world_map/resources/world_map_settings.gd")
const START_SCENARIO := preload("res://features/world_sim/resources/start_scenario_definition.gd")

## Stable identifier for save/load and tooling. Defaults to the node name.
@export var world_id := ""

## Session spawn options (edited in the World dock). Applied by
## WorldTimeController on a fresh game start; loaded saves override them.
@export_range(0, 23, 1) var start_hour := 6
@export_range(0, 59, 1) var start_minute := 0

@export_group("Game Start")
## New-game default. Expand this resource to edit the squad, members and spawn.
@export var default_start_scenario: START_SCENARIO
## Launch inputs, set before adding the world to the tree. A future start menu
## uses these same inputs; neither changes the world's authored default.
var selected_start_scenario: START_SCENARIO
var saved_game_path := ""

## Select the World root in the Inspector to tune discovery, zoom and map ink.
## Make Unique before customizing a world instead of editing shared defaults.
@export_group("World Map")
@export var map_settings: MAP_SETTINGS = preload("res://features/world_map/resources/default_world_map_settings.tres")


func get_world_id() -> String:
	return world_id if not world_id.is_empty() else String(name)


func get_start_scenario() -> START_SCENARIO:
	return selected_start_scenario if selected_start_scenario != null else default_start_scenario


func get_zones() -> Array[Node3D]:
	var zones: Array[Node3D] = []
	for child in get_children():
		if child is ZONE_SCRIPT:
			zones.append(child)
	return zones
