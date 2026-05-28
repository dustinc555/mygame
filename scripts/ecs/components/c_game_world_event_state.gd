extends "res://addons/gecs/ecs/component.gd"

class_name CGameWorldEventState

@export var state_id := "world_events"
@export var active_prompt_event_id := ""
@export var events: Dictionary = {}


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	active_prompt_event_id = str(source.get("active_prompt_event_id", active_prompt_event_id))
	events = (source.get("events", events) as Dictionary).duplicate(true)


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"active_prompt_event_id": active_prompt_event_id,
		"events": events.duplicate(true),
	}
