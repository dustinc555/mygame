extends "res://addons/gecs/ecs/component.gd"

## One persistent camp, including dead-member history and rolled furnishings.
@export var camp_id := ""
@export var state: Dictionary = {}

func apply_state(source: Dictionary) -> void:
	camp_id = str(source.get("camp_id", camp_id))
	state = source.duplicate(true)

func to_state() -> Dictionary:
	return state.duplicate(true)
