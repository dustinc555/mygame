extends "res://addons/gecs/ecs/component.gd"

class_name CGamePopulationRealizationState

@export var state_id := "population_realization"
@export var default_realization_policy := "full_town"
@export var near_player_radius := 55.0
@export var realization_resync_interval_seconds := 1.0


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	default_realization_policy = str(source.get("default_realization_policy", default_realization_policy))
	near_player_radius = float(source.get("near_player_radius", near_player_radius))
	realization_resync_interval_seconds = float(source.get("realization_resync_interval_seconds", realization_resync_interval_seconds))


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"default_realization_policy": default_realization_policy,
		"near_player_radius": near_player_radius,
		"realization_resync_interval_seconds": realization_resync_interval_seconds,
	}
