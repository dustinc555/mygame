class_name CGameFarmWaterSourceState
extends "res://addons/gecs/ecs/component.gd"
## Durable finite/renewable water source state. Runtime source nodes are projections.

@export var source_id := ""
@export var world_position := Vector3.ZERO
@export var capacity := 100.0
@export var current_water := 100.0
@export var renewable := false
@export var recharge_per_world_minute := 0.0
@export var last_processed_minute := 0


func to_state() -> Dictionary:
	return {
		"source_id": source_id,
		"world_position": world_position,
		"capacity": capacity,
		"current_water": current_water,
		"renewable": renewable,
		"recharge_per_world_minute": recharge_per_world_minute,
		"last_processed_minute": last_processed_minute,
	}


func apply_state(state: Dictionary) -> void:
	source_id = str(state.get("source_id", source_id))
	world_position = state.get("world_position", world_position)
	capacity = maxf(0.0, float(state.get("capacity", capacity)))
	current_water = clampf(float(state.get("current_water", current_water)), 0.0, capacity)
	renewable = bool(state.get("renewable", renewable))
	recharge_per_world_minute = maxf(0.0, float(state.get("recharge_per_world_minute", recharge_per_world_minute)))
	last_processed_minute = maxi(0, int(state.get("last_processed_minute", last_processed_minute)))
