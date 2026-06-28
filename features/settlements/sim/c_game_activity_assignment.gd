extends "res://addons/gecs/ecs/component.gd"

class_name CGameActivityAssignment

@export var actor_id := ""
@export var activity_id := ""
@export var settlement_id := ""
@export var source_id := "settlement_activity"
@export var assigned_at := 0.0
@export var assignment_until := 0.0
@export var point_path: NodePath
@export var active := false

var point: Node
