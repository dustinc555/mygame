class_name CGameFarmWaterSourceState
extends "res://addons/gecs/ecs/component.gd"
## Durable finite/renewable water source state. Runtime source nodes are projections.

@export var source_id := ""
@export var settlement_id := ""
@export_enum("well", "storage") var source_kind := "storage"
@export var world_position := Vector3.ZERO
@export var owner_faction_name := ""
@export var public_water_access := false
@export var capacity := 100.0
@export var current_water := 100.0
@export var reserved_incoming_water := 0.0
@export var reserved_outgoing_water := 0.0
@export var renewable := false
@export var recharge_per_world_minute := 0.0
## Float preserves sub-minute recharge across GECS writes and old integer saves.
@export var last_processed_minute := 0.0


func to_state() -> Dictionary:
	return {
		"source_id": source_id,
		"settlement_id": settlement_id,
		"source_kind": source_kind,
		"world_position": world_position,
		"owner_faction_name": owner_faction_name,
		"public_water_access": public_water_access,
		"capacity": capacity,
		"current_water": current_water,
		"reserved_incoming_water": reserved_incoming_water,
		"reserved_outgoing_water": reserved_outgoing_water,
		"renewable": renewable,
		"recharge_per_world_minute": recharge_per_world_minute,
		"last_processed_minute": last_processed_minute,
	}


func apply_state(state: Dictionary) -> void:
	source_id = str(state.get("source_id", source_id))
	settlement_id = str(state.get("settlement_id", settlement_id))
	source_kind = str(state.get("source_kind", source_kind))
	world_position = state.get("world_position", world_position)
	owner_faction_name = str(state.get("owner_faction_name", owner_faction_name))
	public_water_access = bool(state.get("public_water_access", public_water_access))
	capacity = maxf(0.0, float(state.get("capacity", capacity)))
	current_water = clampf(float(state.get("current_water", current_water)), 0.0, capacity)
	reserved_incoming_water = clampf(float(state.get("reserved_incoming_water", reserved_incoming_water)), 0.0, maxf(0.0, capacity - current_water))
	reserved_outgoing_water = clampf(float(state.get("reserved_outgoing_water", reserved_outgoing_water)), 0.0, current_water)
	renewable = bool(state.get("renewable", renewable))
	recharge_per_world_minute = maxf(0.0, float(state.get("recharge_per_world_minute", recharge_per_world_minute)))
	last_processed_minute = maxf(0.0, float(state.get("last_processed_minute", last_processed_minute)))
