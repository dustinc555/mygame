extends RefCounted

class_name FarmSimulation

## Pure durable farming rules. Callers own persistence and projection.
## Every cell is self-contained so fields can advance while unrealized.

const STATE_UNTILLED := "untilled"
const STATE_TILLED := "tilled"
const STATE_GROWING := "growing"
const STATE_RIPE := "ripe"
const STATE_WITHERED := "withered"
const STATE_BLOCKED := "blocked"

const VISUAL_STAGE_COUNT := 9
## Source stages 1-7 are the living growth sequence. Stage 8 is visibly
## senescent and stage 9 is the dead remains in every imported crop family.
const GROWTH_VISUAL_STAGE_COUNT := 7
const RIPE_VISUAL_STAGE_INDEX := 6
const WITHERED_VISUAL_STAGE_INDEX := 8


static func new_cell(grid_position: Vector2i, world_position: Vector3) -> Dictionary:
	return {
		"grid_position": grid_position,
		"world_position": world_position,
		"state": STATE_UNTILLED,
		"soil_created": false,
		"soil_recovery_started_minute": -1,
		"crop_id": "",
		"growth": 0.0,
		"water": 0.0,
		"dry_minutes": 0.0,
		"ripe_minutes": 0.0,
		"stage_index": 0,
		"work_progress": 0.0,
		"claimed_by": "",
		"blocked_reason": "",
	}


static func block_cell(cell: Dictionary, reason: String) -> Dictionary:
	var next := cell.duplicate(true)
	if str(next.get("state", "")) != STATE_BLOCKED:
		var displaced := next.duplicate(true)
		displaced.erase("displaced_state")
		next["displaced_state"] = displaced
	next["state"] = STATE_BLOCKED
	next["blocked_reason"] = reason
	next["work_progress"] = 0.0
	next["claimed_by"] = ""
	return next


static func clear_blockage(cell: Dictionary) -> Dictionary:
	var displaced = cell.get("displaced_state")
	if displaced is Dictionary and not (displaced as Dictionary).is_empty():
		var restored := (displaced as Dictionary).duplicate(true)
		restored.erase("displaced_state")
		restored["blocked_reason"] = ""
		return restored
	return new_cell(cell.get("grid_position", Vector2i.ZERO), cell.get("world_position", Vector3.ZERO))


static func apply_rain(cell: Dictionary, amount: float, water_capacity := 100.0) -> Dictionary:
	var next := cell.duplicate(true)
	if str(next.get("state", "")) != STATE_GROWING or amount <= 0.0:
		return next
	next["water"] = clampf(float(next.get("water", 0.0)) + amount, 0.0, maxf(0.0, water_capacity))
	next["dry_minutes"] = 0.0
	return next


static func complete_tilling(cell: Dictionary, current_minute := -1) -> Dictionary:
	var next := cell.duplicate(true)
	next["state"] = STATE_TILLED
	next["soil_created"] = true
	next["soil_recovery_started_minute"] = current_minute
	next["work_progress"] = 0.0
	next["claimed_by"] = ""
	return next


static func complete_planting(cell: Dictionary, crop_id: String, starting_water := 0.0) -> Dictionary:
	var next := cell.duplicate(true)
	next["state"] = STATE_GROWING
	next["crop_id"] = crop_id
	next["soil_recovery_started_minute"] = -1
	next["growth"] = 0.0
	next["water"] = maxf(0.0, starting_water)
	next["dry_minutes"] = 0.0
	next["ripe_minutes"] = 0.0
	next["stage_index"] = 0
	next["work_progress"] = 0.0
	next["claimed_by"] = ""
	return next


static func advance_cell(cell: Dictionary, crop: Dictionary, elapsed_minutes: float, rain_water := 0.0) -> Dictionary:
	var next := cell.duplicate(true)
	if elapsed_minutes <= 0.0:
		return next
	var state := str(next.get("state", STATE_UNTILLED))
	if state == STATE_RIPE:
		next["ripe_minutes"] = float(next.get("ripe_minutes", 0.0)) + elapsed_minutes
		if float(next["ripe_minutes"]) > maxf(0.0, float(crop.get("ripe_window_minutes", 0.0))):
			return wither_cell(next)
		return next
	if state != STATE_GROWING:
		return next

	var water_capacity := maxf(0.0, float(crop.get("water_capacity", 0.0)))
	var water := clampf(float(next.get("water", 0.0)) + maxf(0.0, rain_water), 0.0, water_capacity)
	var use_per_minute := maxf(0.0, float(crop.get("water_per_growth_minute", 0.0)))
	var wet_minutes := elapsed_minutes
	if use_per_minute > 0.0:
		wet_minutes = minf(elapsed_minutes, water / use_per_minute)
		water = maxf(0.0, water - wet_minutes * use_per_minute)
	var dry_minutes := elapsed_minutes - wet_minutes
	if wet_minutes > 0.0:
		next["dry_minutes"] = 0.0
	if dry_minutes > 0.0:
		next["dry_minutes"] = float(next.get("dry_minutes", 0.0)) + dry_minutes
	next["water"] = water
	if float(next.get("dry_minutes", 0.0)) >= maxf(0.0, float(crop.get("dry_grace_minutes", 0.0))):
		return wither_cell(next)

	var growth_minutes := maxf(0.001, float(crop.get("growth_minutes", 1.0)))
	var old_growth := clampf(float(next.get("growth", 0.0)), 0.0, 1.0)
	var growth_added := wet_minutes / growth_minutes
	var new_growth := clampf(old_growth + growth_added, 0.0, 1.0)
	next["growth"] = new_growth
	next["stage_index"] = stage_index_for_growth(new_growth)
	if new_growth >= 1.0:
		next["state"] = STATE_RIPE
		var minutes_to_mature := maxf(0.0, (1.0 - old_growth) * growth_minutes)
		next["ripe_minutes"] = maxf(0.0, wet_minutes - minutes_to_mature)
	return next


static func stage_index_for_growth(growth: float) -> int:
	return clampi(
		int(floor(clampf(growth, 0.0, 1.0) * float(GROWTH_VISUAL_STAGE_COUNT - 1) + 0.00001)),
		0,
		RIPE_VISUAL_STAGE_INDEX
	)


static func wither_cell(cell: Dictionary) -> Dictionary:
	var next := cell.duplicate(true)
	next["state"] = STATE_WITHERED
	next["stage_index"] = WITHERED_VISUAL_STAGE_INDEX
	next["soil_recovery_started_minute"] = -1
	next["water"] = 0.0
	next["claimed_by"] = ""
	next["work_progress"] = 0.0
	return next


static func clear_withered(cell: Dictionary, current_minute := -1) -> Dictionary:
	var grid_position: Vector2i = cell.get("grid_position", Vector2i.ZERO)
	var world_position: Vector3 = cell.get("world_position", Vector3.ZERO)
	var cleared := new_cell(grid_position, world_position)
	cleared["soil_created"] = true
	cleared["state"] = STATE_TILLED
	cleared["soil_recovery_started_minute"] = current_minute
	return cleared


static func complete_harvest(cell: Dictionary, crop: Dictionary, farming_level: float, current_minute := -1) -> Dictionary:
	if str(cell.get("state", "")) != STATE_RIPE:
		return {"cell": cell.duplicate(true), "yield": 0}
	var base_yield := maxi(0, int(crop.get("base_yield", 0)))
	var per_level := maxf(0.0, float(crop.get("yield_per_farming_level", 0.0)))
	var output := maxi(1, int(round(float(base_yield) * (1.0 + maxf(0.0, farming_level) * per_level)))) if base_yield > 0 else 0
	var reset := new_cell(cell.get("grid_position", Vector2i.ZERO), cell.get("world_position", Vector3.ZERO))
	reset["soil_created"] = true
	reset["state"] = STATE_TILLED
	reset["soil_recovery_started_minute"] = current_minute
	return {"cell": reset, "yield": output}


static func advance_soil_recovery(cell: Dictionary, from_minute: int, target_minute: int, eligible: bool, recovery_minutes: int) -> Dictionary:
	var next := cell.duplicate(true)
	if not bool(next.get("soil_created", false)):
		next["soil_recovery_started_minute"] = -1
		return next
	if not eligible:
		next["soil_recovery_started_minute"] = -1
		return next
	var started := int(next.get("soil_recovery_started_minute", -1))
	if started < 0:
		started = from_minute
		next["soil_recovery_started_minute"] = started
	if target_minute - started < maxi(1, recovery_minutes):
		return next
	var recovered := new_cell(
		next.get("grid_position", Vector2i.ZERO),
		next.get("world_position", Vector3.ZERO)
	)
	recovered["soil_recovered_minute"] = target_minute
	return recovered
