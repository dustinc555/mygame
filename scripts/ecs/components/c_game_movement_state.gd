extends "res://addons/gecs/ecs/component.gd"

class_name CGameMovementState

@export var system_movement_active := false
@export var combat_settled := false
@export var desired_velocity := Vector3.ZERO
@export var move_target_position := Vector3.ZERO
@export var look_target_position := Vector3.ZERO
var collision_focus_instance_id := 0
