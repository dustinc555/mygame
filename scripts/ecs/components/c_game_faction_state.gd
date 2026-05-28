extends "res://addons/gecs/ecs/component.gd"

class_name CGameFactionState

@export var state_id := "factions"
@export var reputations: Dictionary = {}
@export var favor_points: Dictionary = {}
@export var diplomatic_states: Dictionary = {}
@export var help_allies := false


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	reputations = (source.get("reputations", reputations) as Dictionary).duplicate(true)
	favor_points = (source.get("favor_points", favor_points) as Dictionary).duplicate(true)
	diplomatic_states = (source.get("diplomatic_states", diplomatic_states) as Dictionary).duplicate(true)
	help_allies = bool(source.get("help_allies", help_allies))


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"reputations": reputations.duplicate(true),
		"favor_points": favor_points.duplicate(true),
		"diplomatic_states": diplomatic_states.duplicate(true),
		"help_allies": help_allies,
	}
