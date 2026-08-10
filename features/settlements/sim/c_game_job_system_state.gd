extends "res://addons/gecs/ecs/component.gd"

class_name CGameJobSystemState

@export var state_id := "job_system"
@export var sim_time := 0.0
@export var actor_policies: Dictionary = {}


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	sim_time = float(source.get("sim_time", sim_time))
	actor_policies = (source.get("actor_policies", actor_policies) as Dictionary).duplicate(true)


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"sim_time": sim_time,
		"actor_policies": actor_policies.duplicate(true),
	}
