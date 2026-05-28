extends "res://addons/gecs/ecs/component.gd"

class_name CGameActorNode

@export var actor_path: NodePath
@export var instance_id := 0

var actor: Node


func get_actor() -> Node:
	if actor != null and is_instance_valid(actor):
		return actor
	return null
