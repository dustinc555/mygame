extends "res://addons/gecs/ecs/component.gd"

class_name CGameJobWorkerRecord

@export var record_id := ""
@export var provider_id := ""
@export var worker_actor_id := ""
@export var total_worked_seconds := 0.0
@export var owed_currency := 0
@export var break_until_time := 0.0
