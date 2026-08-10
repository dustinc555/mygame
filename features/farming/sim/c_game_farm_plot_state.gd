extends "res://addons/gecs/ecs/component.gd"

class_name CGameFarmPlotState

## Authoritative durable record for one player-created field. Cell dictionaries
## intentionally live on the component so they continue to simulate while the
## plot's Node3D projection is unloaded. Crop choices and work requests are
## cell-owned; legacy plot-wide crop/request fields are intentionally discarded.

@export var plot_id := ""
@export var owner_faction_id := ""
@export var settlement_id := ""
@export var display_name := "Field"
@export var crop_policy_id := ""
@export var field_deleted := false
@export var priority := 0
@export var worker_policy := "default"
@export var origin := Vector3.ZERO
@export var cell_size := 1.25
@export var dimensions := Vector2i.ONE
@export var last_simulated_minute := 0
@export var cells: Dictionary = {}
@export var soil_remnants: Dictionary = {}
@export var state_revision := 0


func apply_state(source: Dictionary) -> void:
	plot_id = str(source.get("plot_id", plot_id))
	owner_faction_id = str(source.get("owner_faction_id", owner_faction_id))
	settlement_id = str(source.get("settlement_id", settlement_id))
	display_name = str(source.get("display_name", display_name))
	crop_policy_id = str(source.get("crop_policy_id", crop_policy_id))
	field_deleted = bool(source.get("field_deleted", field_deleted))
	priority = int(source.get("priority", priority))
	worker_policy = str(source.get("worker_policy", worker_policy))
	origin = source.get("origin", origin)
	cell_size = maxf(0.25, float(source.get("cell_size", cell_size)))
	dimensions = source.get("dimensions", dimensions)
	last_simulated_minute = int(source.get("last_simulated_minute", last_simulated_minute))
	cells = (source.get("cells", cells) as Dictionary).duplicate(true)
	soil_remnants = (source.get("soil_remnants", soil_remnants) as Dictionary).duplicate(true)
	state_revision = int(source.get("state_revision", state_revision))


func to_state() -> Dictionary:
	return {
		"plot_id": plot_id,
		"owner_faction_id": owner_faction_id,
		"settlement_id": settlement_id,
		"display_name": display_name,
		"crop_policy_id": crop_policy_id,
		"field_deleted": field_deleted,
		"priority": priority,
		"worker_policy": worker_policy,
		"origin": origin,
		"cell_size": cell_size,
		"dimensions": dimensions,
		"last_simulated_minute": last_simulated_minute,
		"cells": cells.duplicate(true),
		"soil_remnants": soil_remnants.duplicate(true),
		"state_revision": state_revision,
	}
