extends "res://addons/gecs/ecs/component.gd"

class_name CGameWorldSquadState

@export var state_id := "world_squads"
@export var squad_index := 0
@export var active_squads: Dictionary = {}


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	squad_index = int(source.get("squad_index", squad_index))
	active_squads = (source.get("active_squads", active_squads) as Dictionary).duplicate(true)


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"squad_index": squad_index,
		"active_squads": active_squads.duplicate(true),
	}
