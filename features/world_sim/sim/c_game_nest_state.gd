extends "res://addons/gecs/ecs/component.gd"

class_name CGameNestState

@export var state_id := "nests"
@export var nest_index := 0
@export var nest_states: Dictionary = {}


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	nest_index = int(source.get("nest_index", nest_index))
	nest_states = (source.get("nest_states", nest_states) as Dictionary).duplicate(true)


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"nest_index": nest_index,
		"nest_states": nest_states.duplicate(true),
	}
