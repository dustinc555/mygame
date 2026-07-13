@tool
@icon("res://addons/world_authoring/icons/factions_root.svg")
extends Node

class_name Factions

## Authoring root for the faction database: lives in the world scene with one
## Faction child per faction. Nodes are the editor affordance (select the
## root for the roster + New Faction, select a child to edit it); the
## FactionDefinition .tres files stay the on-disk truth the game ships with.
##
## At runtime the root joins the world_sim_registry group and exposes the
## collected definitions, so FactionController registers every authored
## faction with no extra wiring. Optional faction-pair relation resources
## (FactionRelationDefinition) are authored here too.

@export var relation_definitions: Array[Resource] = []

var faction_definitions: Array[Resource]:
	get:
		return get_faction_definitions()


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("world_sim_registry")


func get_faction_definitions() -> Array[Resource]:
	var definitions: Array[Resource] = []
	for child in get_children():
		var definition: Resource = child.get("definition") as Resource if child is Faction else null
		if definition != null:
			definitions.append(definition)
	return definitions


func get_faction_nodes() -> Array[Faction]:
	var nodes: Array[Faction] = []
	for child in get_children():
		if child is Faction:
			nodes.append(child)
	return nodes
