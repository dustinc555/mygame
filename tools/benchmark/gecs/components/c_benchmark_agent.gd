extends "res://addons/gecs/ecs/component.gd"

class_name CBenchmarkAgent

@export var faction_id := ""
@export var team := 0
@export var speed := 3.2
@export var attack_range := 1.45
@export var attack_cooldown_seconds := 1.15
@export var target_position := Vector3.ZERO
@export var retarget_remaining := 0.0
@export var cooldown_remaining := 0.0
@export var engagement_count := 0

var target_entity
