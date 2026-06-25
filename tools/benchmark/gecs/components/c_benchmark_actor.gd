extends "res://addons/gecs/ecs/component.gd"

class_name CBenchmarkActor

@export var actor_path: NodePath
@export var stable_id := ""
@export var display_name := ""

var actor: Node3D
