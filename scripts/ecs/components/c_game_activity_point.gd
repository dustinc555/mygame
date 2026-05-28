extends "res://addons/gecs/ecs/component.gd"

class_name CGameActivityPoint

@export var activity_id := ""
@export var settlement_id := ""
@export var point_path: NodePath
@export var weight := 1.0
@export var assignment_min_seconds := 12.0
@export var assignment_max_seconds := 28.0
@export var active := true
