extends "res://addons/gecs/ecs/component.gd"

class_name CGameJobProvider

@export var provider_id := ""
@export var provider_name := ""
@export var provider_path: NodePath
@export var owner_actor_id := ""
@export var sim_time := 0.0
