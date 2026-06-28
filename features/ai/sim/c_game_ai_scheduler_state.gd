extends "res://addons/gecs/ecs/component.gd"

class_name CGameAiSchedulerState

@export var state_id := "ai_scheduler"
@export var sim_time := 0.0
@export var default_tick_interval_seconds := 0.45
@export var default_tick_jitter_seconds := 0.15


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	sim_time = float(source.get("sim_time", sim_time))
	default_tick_interval_seconds = float(source.get("default_tick_interval_seconds", default_tick_interval_seconds))
	default_tick_jitter_seconds = float(source.get("default_tick_jitter_seconds", default_tick_jitter_seconds))


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"sim_time": sim_time,
		"default_tick_interval_seconds": default_tick_interval_seconds,
		"default_tick_jitter_seconds": default_tick_jitter_seconds,
	}
