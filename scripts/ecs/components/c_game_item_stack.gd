extends "res://addons/gecs/ecs/component.gd"

class_name CGameItemStack

@export var stack_id := ""
@export var container_id := ""
@export var owner_actor_id := ""
@export var item_id := ""
@export var item_definition_path := ""
@export var count := 1
@export var grid_position := Vector2i.ZERO
@export var contained_item_counts: Dictionary = {}
@export var metadata: Dictionary = {}
@export var world_position := Vector3.ZERO
@export var world_position_initialized := false
