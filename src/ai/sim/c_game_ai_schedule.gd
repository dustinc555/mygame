extends "res://addons/gecs/ecs/component.gd"

class_name CGameAiSchedule

@export var next_decision_tick := -1.0
@export var decision_interval_seconds := 0.45
@export var decision_jitter_seconds := 0.15
@export var next_job_tick := -1.0
