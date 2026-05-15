extends Node

class_name WorldSimRegistry

@export var faction_definitions: Array[Resource] = []
@export var settlement_definitions: Array[Resource] = []
@export var squad_templates: Array[Resource] = []


func _ready() -> void:
	add_to_group("world_sim_registry")
