class_name CGameLiquidContainerState
extends "res://addons/gecs/ecs/component.gd"
## Durable scalar-liquid storage. Runtime tank nodes are projections.

@export var liquid_container_id := ""
@export var settlement_id := ""
@export var facility_id := ""
@export var owner_faction_name := ""
@export var public_water_access := false
@export var world_position := Vector3.ZERO
@export var assigned_liquid_id := ""
@export var capacity_liters := 1000.0
@export var current_liters := 0.0
@export var reserved_incoming_liters := 0.0
@export var reserved_outgoing_liters := 0.0


func to_state() -> Dictionary:
	return {
		"liquid_container_id": liquid_container_id,
		"settlement_id": settlement_id,
		"facility_id": facility_id,
		"owner_faction_name": owner_faction_name,
		"public_water_access": public_water_access,
		"world_position": world_position,
		"assigned_liquid_id": assigned_liquid_id,
		"capacity_liters": capacity_liters,
		"current_liters": current_liters,
		"reserved_incoming_liters": reserved_incoming_liters,
		"reserved_outgoing_liters": reserved_outgoing_liters,
	}


func apply_state(state: Dictionary) -> void:
	liquid_container_id = str(state.get("liquid_container_id", liquid_container_id)).strip_edges()
	settlement_id = str(state.get("settlement_id", settlement_id)).strip_edges()
	facility_id = str(state.get("facility_id", facility_id)).strip_edges()
	owner_faction_name = str(state.get("owner_faction_name", owner_faction_name)).strip_edges()
	public_water_access = bool(state.get("public_water_access", public_water_access))
	world_position = state.get("world_position", world_position)
	assigned_liquid_id = str(state.get("assigned_liquid_id", assigned_liquid_id)).strip_edges().to_lower()
	capacity_liters = maxf(0.0, float(state.get("capacity_liters", capacity_liters)))
	current_liters = clampf(float(state.get("current_liters", current_liters)), 0.0, capacity_liters)
	reserved_incoming_liters = clampf(float(state.get("reserved_incoming_liters", reserved_incoming_liters)), 0.0, maxf(0.0, capacity_liters - current_liters))
	reserved_outgoing_liters = clampf(float(state.get("reserved_outgoing_liters", reserved_outgoing_liters)), 0.0, current_liters)
