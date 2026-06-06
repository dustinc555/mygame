extends "res://addons/gecs/ecs/component.gd"

class_name CGameDemoSimState

@export var state_id := "demo_sim"
@export var world_id := ""
@export var world_definition_path := ""


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	world_id = str(source.get("world_id", world_id))
	world_definition_path = str(source.get("world_definition_path", world_definition_path))


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"world_id": world_id,
		"world_definition_path": world_definition_path,
	}
