extends "res://addons/gecs/ecs/component.gd"

class_name CGameWorldSquadState

@export var state_id := "world_squads"
@export var squad_index := 0
@export var active_squads: Dictionary = {}
@export var command_log: Array[Dictionary] = []


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	squad_index = int(source.get("squad_index", squad_index))
	active_squads = (source.get("active_squads", active_squads) as Dictionary).duplicate(true)
	command_log = _dictionary_array(source.get("command_log", command_log))


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"squad_index": squad_index,
		"active_squads": active_squads.duplicate(true),
		"command_log": command_log.duplicate(true),
	}


func _dictionary_array(value) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for entry in value:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result
