extends "res://addons/gecs/ecs/component.gd"

class_name CGameActorSpatial

@export var world_position := Vector3.ZERO
@export var last_world_position := Vector3.ZERO
@export var spatial_cell := Vector2i.ZERO
@export var position_initialized := false
