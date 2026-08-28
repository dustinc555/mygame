extends Node

class_name FarmController

const SERVICE_ID := &"farming"
const DEFAULT_CELL_SIZE := 1.25
const MAX_PLOT_DIMENSION := 64
const MAX_PLOT_CELLS := 4096
const SOIL_RECOVERY_MINUTES := 2 * 24 * 60
## Crop policy meaning "plant whatever seed stock is in reach" — a policy, not
## a crop id, resolved per plot through the resolver a bridge installs.
const AUTO_CROP_POLICY := "auto"
const FARM_SIMULATION := preload("res://features/farming/sim/farm_simulation.gd")
const CROP_PATHS := {
	"tomato": "res://features/farming/resources/crops/tomato.tres",
	"french_beans": "res://features/farming/resources/crops/french_beans.tres",
	"bell_pepper": "res://features/farming/resources/crops/bell_pepper.tres",
	"eggplant": "res://features/farming/resources/crops/eggplant.tres",
	"chili_pepper": "res://features/farming/resources/crops/chili_pepper.tres",
	"wheat": "res://features/farming/resources/crops/wheat.tres",
}

signal plot_changed(plot_id: String, state: Dictionary)
signal plot_cells_changed(plot_id: String, changed_cells: Dictionary, settlement_id: String)
signal plot_removed(plot_id: String)
signal work_completed(result: Dictionary)
signal water_source_changed(source_id: String, state: Dictionary)

var _context: BootstrapContext
var _gecs: Node
var _world_time: Node
var _territory: Node
var _crops: Dictionary = {}
var _next_plot_sequence := 1
var _world_reindex_pending := false
var _auto_crop_resolver := Callable()


func initialize(context: BootstrapContext) -> void:
	_context = context
	_gecs = context.get_optional(&"gecs_world")
	_world_time = context.get_optional(&"world_time")
	_territory = context.require(&"territory")
	for crop_id in CROP_PATHS:
		_crops[crop_id] = load(CROP_PATHS[crop_id])
	_recover_sequence()
	if _world_time != null and not _world_time.minute_changed.is_connected(_on_minute_changed):
		_world_time.minute_changed.connect(_on_minute_changed)
	if _gecs != null and not _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.connect(_on_world_reindexed)


func get_crop(crop_id: String) -> CropDefinition:
	return _crops.get(crop_id) as CropDefinition


## Seed stock lives in world containers, which the sim cannot see. A bridge
## that can (FarmWorkBridge) installs a resolver here; the controller never
## scans the scene itself.
func set_auto_crop_resolver(resolver: Callable) -> void:
	_auto_crop_resolver = resolver


## The crop an "auto" field should currently be planting, or "" when nothing is
## available. Resolve this ONCE per plot — never per cell; the per-minute cell
## loop is the hot path.
func _effective_policy_crop_id(state: Dictionary) -> String:
	var policy := str(state.get("crop_policy_id", ""))
	if policy != AUTO_CROP_POLICY:
		return policy
	if not _auto_crop_resolver.is_valid():
		return ""
	var resolved := str(_auto_crop_resolver.call(state))
	return resolved if get_crop(resolved) != null else ""


func get_crops() -> Array[CropDefinition]:
	var crops: Array[CropDefinition] = []
	for crop in _crops.values():
		if crop is CropDefinition:
			crops.append(crop)
	crops.sort_custom(func(a: CropDefinition, b: CropDefinition) -> bool: return a.display_name < b.display_name)
	return crops


## Debug-only exact-cell mutation used by the Debug Farming click tools.
func debug_crop_action_at(world_position: Vector3, full_grow := false) -> Dictionary:
	var found := find_plot_cell_at_world_position(world_position)
	if found.is_empty():
		return {"success": false, "message": "Click a planted crop"}
	var plot: Dictionary = (found.get("plot", {}) as Dictionary).duplicate(true)
	var cell_key := str(found.get("cell_key", ""))
	var cells: Dictionary = plot.get("cells", {}).duplicate(true)
	var cell: Dictionary = (cells.get(cell_key, {}) as Dictionary).duplicate(true)
	var crop_id := str(cell.get("crop_id", ""))
	if crop_id.is_empty() or str(cell.get("state", "")) not in [FARM_SIMULATION.STATE_GROWING, FARM_SIMULATION.STATE_RIPE]:
		return {"success": false, "message": "Click a planted crop"}
	var current_stage := int(cell.get("stage_index", 0))
	if full_grow or current_stage >= FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX - 1:
		cell["growth"] = 1.0
		cell["stage_index"] = FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX
		cell["state"] = FARM_SIMULATION.STATE_RIPE
		cell["ripe_minutes"] = 0.0
	else:
		var next_stage := current_stage + 1
		cell["growth"] = (float(next_stage) + 0.01) / float(FARM_SIMULATION.GROWTH_VISUAL_STAGE_COUNT - 1)
		cell["stage_index"] = next_stage
		cell["state"] = FARM_SIMULATION.STATE_GROWING
	cells[cell_key] = cell
	plot["cells"] = cells
	_save_plot(plot)
	var crop := get_crop(crop_id)
	var crop_name := crop.display_name if crop != null else crop_id.capitalize()
	return {
		"success": true,
		"message": "%s is fully grown" % crop_name if bool(full_grow) or str(cell.get("state", "")) == FARM_SIMULATION.STATE_RIPE else "%s advanced to stage %d" % [crop_name, int(cell.get("stage_index", 0)) + 1],
	}


func create_plot(cell_positions: Array[Vector3], dimensions: Vector2i, crop_id: String, owner_faction_id: String, settlement_id := "", blocked_cells: Dictionary = {}, cell_keys := PackedStringArray()) -> Dictionary:
	var width := maxi(0, dimensions.x)
	var height := maxi(0, dimensions.y)
	var explicit_keys := PackedStringArray(cell_keys)
	if _gecs == null or cell_positions.is_empty() or (not crop_id.is_empty() and get_crop(crop_id) == null) \
			or width <= 0 or height <= 0 \
			or width > MAX_PLOT_DIMENSION or height > MAX_PLOT_DIMENSION \
			or width * height > MAX_PLOT_CELLS \
			or cell_positions.size() > MAX_PLOT_CELLS \
			or (explicit_keys.is_empty() and cell_positions.size() != width * height) \
			or (not explicit_keys.is_empty() and explicit_keys.size() != cell_positions.size()):
		return {}
	if not _all_field_positions_permitted(cell_positions, owner_faction_id):
		return {}
	var reclaimed_by_index: Dictionary = {}
	var reclaimed_cells := _reclaimable_physical_cells_at_world_positions(cell_positions, DEFAULT_CELL_SIZE)
	var occupied_cells := find_plot_cells_at_world_positions(cell_positions, "", DEFAULT_CELL_SIZE)
	for index in cell_positions.size():
		var physical: Dictionary = reclaimed_cells[index]
		if physical.is_empty():
			if not occupied_cells[index].is_empty():
				return {}
			continue
		var source: Dictionary = physical.get("source_state", {})
		var source_owner := str(source.get("owner_faction_id", ""))
		var physical_cell: Dictionary = physical.get("cell", {})
		var is_detached_remnant := str(physical.get("container", "")) == "soil_remnants"
		if (not bool(source.get("field_deleted", false)) and not is_detached_remnant) \
				or (not source_owner.is_empty() and source_owner != owner_faction_id) \
				or _cell_has_pending_work(physical_cell):
			return {}
		reclaimed_by_index[index] = physical
	var plot_id := "farm:%d" % _next_plot_sequence
	_next_plot_sequence += 1
	var cells: Dictionary = {}
	for index in cell_positions.size():
		var grid := _grid_from_key(explicit_keys[index]) if not explicit_keys.is_empty() else Vector2i(index % width, index / width)
		if grid.x < 0 or grid.y < 0 or grid.x >= width or grid.y >= height:
			return {}
		var key := "%d:%d" % [grid.x, grid.y]
		if cells.has(key):
			return {}
		var physical: Dictionary = reclaimed_by_index.get(index, {})
		var cell: Dictionary = (physical.get("cell", {}) as Dictionary).duplicate(true) \
				if not physical.is_empty() else FARM_SIMULATION.new_cell(grid, cell_positions[index])
		cell["grid_position"] = grid
		cell["world_position"] = cell_positions[index]
		cell.erase("soil_recovery_started_minute")
		if blocked_cells.has(key) and physical.is_empty():
			cell = FARM_SIMULATION.block_cell(cell, str(blocked_cells[key]))
		cells[key] = cell
	var state := {
		"plot_id": plot_id,
		"owner_faction_id": owner_faction_id,
		"settlement_id": settlement_id,
		"display_name": "%s Field" % get_crop(crop_id).display_name if not crop_id.is_empty() else "Field",
		"crop_policy_id": crop_id,
		"priority": 0,
		"worker_policy": "default",
		"origin": cell_positions[0],
		"cell_size": DEFAULT_CELL_SIZE,
		"dimensions": dimensions,
		"last_simulated_minute": _absolute_minute(),
		"cells": cells,
		"soil_remnants": {},
		"state_revision": 1,
	}
	state = _gecs.upsert_farm_plot_state(state)
	plot_changed.emit(plot_id, state)
	_release_reclaimed_physical_cells(reclaimed_by_index.values())
	return state


func _reclaimable_physical_cell_at_world_position(world_position: Vector3, candidate_cell_size: float) -> Dictionary:
	var results := _reclaimable_physical_cells_at_world_positions([world_position], candidate_cell_size)
	return results[0] if not results.is_empty() else {}


func _reclaimable_physical_cells_at_world_positions(world_positions: Array, candidate_cell_size: float) -> Array[Dictionary]:
	var results := _empty_cell_query_results(world_positions.size())
	if world_positions.is_empty():
		return results
	var buckets := _candidate_position_buckets(world_positions, candidate_cell_size)
	for plot_value in get_plots().values():
		var plot: Dictionary = plot_value
		var field_deleted := bool(plot.get("field_deleted", false))
		var plot_id := str(plot.get("plot_id", ""))
		var existing_size := float(plot.get("cell_size", DEFAULT_CELL_SIZE))
		var overlap_extent := (existing_size + candidate_cell_size) * 0.47
		for container_name in ["cells", "soil_remnants"]:
			if container_name == "cells" and not field_deleted:
				continue
			var container: Dictionary = plot.get(container_name, {})
			for key_value in container.keys():
				var cell: Dictionary = container[key_value]
				var existing: Vector3 = cell.get("world_position", Vector3.ZERO)
				for candidate_index in _nearby_candidate_indices(existing, overlap_extent, candidate_cell_size, buckets):
					if not results[candidate_index].is_empty():
						continue
					var candidate := world_positions[candidate_index] as Vector3
					if absf(existing.x - candidate.x) < overlap_extent and absf(existing.z - candidate.z) < overlap_extent:
						results[candidate_index] = {
							"plot_id": plot_id,
							"container": container_name,
							"cell_key": str(key_value),
							"cell": cell.duplicate(true),
							"source_state": plot,
						}
	return results


func _cell_has_pending_work(cell: Dictionary) -> bool:
	return not str(cell.get("requested_operation", "")).is_empty() \
			or not str(cell.get("claimed_by", "")).is_empty() \
			or float(cell.get("work_progress", 0.0)) > 0.0


func _release_reclaimed_physical_cells(reclaimed_values: Array) -> void:
	var changed_plots: Dictionary = {}
	for reclaimed_value in reclaimed_values:
		var reclaimed: Dictionary = reclaimed_value
		var source_id := str(reclaimed.get("plot_id", ""))
		if source_id.is_empty():
			continue
		var source: Dictionary
		if changed_plots.has(source_id):
			source = changed_plots[source_id]
		else:
			source = (reclaimed.get("source_state", {}) as Dictionary).duplicate(true)
			if source.is_empty():
				continue
		var container_name := str(reclaimed.get("container", "cells"))
		var container: Dictionary = source.get(container_name, {}).duplicate(true)
		container.erase(str(reclaimed.get("cell_key", "")))
		source[container_name] = container
		changed_plots[source_id] = source
	for source_id_value in changed_plots.keys():
		var source_id := str(source_id_value)
		var source: Dictionary = changed_plots[source_id]
		if (source.get("cells", {}) as Dictionary).is_empty() \
				and (source.get("soil_remnants", {}) as Dictionary).is_empty():
			remove_plot(source_id)
			continue
		_refresh_plot_dimensions(source)
		_save_plot(source)


func _grid_from_key(key: String) -> Vector2i:
	var parts := key.split(":", false, 1)
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func remove_plot(plot_id: String) -> void:
	if _gecs == null:
		return
	_gecs.remove_farm_plot_state(plot_id)
	plot_removed.emit(plot_id)


func is_active_field(value) -> bool:
	var state: Dictionary = value if value is Dictionary else get_plot(str(value))
	return not state.is_empty() and not bool(state.get("field_deleted", false)) \
			and not (state.get("cells", {}) as Dictionary).is_empty()


func get_plot(plot_id: String) -> Dictionary:
	if _gecs == null:
		return {}
	if _gecs.has_method("get_farm_plot_state"):
		return (_gecs.call("get_farm_plot_state", plot_id) as Dictionary).duplicate(true)
	return (_gecs.get_farm_plot_states().get(plot_id, {}) as Dictionary).duplicate(true)


func get_plots() -> Dictionary:
	return _gecs.get_farm_plot_states() if _gecs != null else {}


func get_cell(plot_id: String, cell_key: String) -> Dictionary:
	if _gecs != null and _gecs.has_method("get_farm_plot_cell_record"):
		return ((_gecs.call("get_farm_plot_cell_record", plot_id, cell_key) as Dictionary).get("cell", {}) as Dictionary).duplicate(true)
	var cells: Dictionary = get_plot(plot_id).get("cells", {})
	return (cells.get(cell_key, {}) as Dictionary).duplicate(true)


## Durable field occupancy authority. This deliberately uses saved sparse cell
## positions rather than projection collision, so untilled and unloaded-looking
## fields still own their ground.
func find_plot_cell_at_world_position(world_position: Vector3, excluded_plot_id := "", candidate_cell_size := DEFAULT_CELL_SIZE) -> Dictionary:
	var results := find_plot_cells_at_world_positions([world_position], excluded_plot_id, candidate_cell_size)
	return results[0] if not results.is_empty() else {}


func find_plot_cells_at_world_positions(world_positions: Array, excluded_plot_id := "", candidate_cell_size := DEFAULT_CELL_SIZE) -> Array[Dictionary]:
	var results := _empty_cell_query_results(world_positions.size())
	if world_positions.is_empty():
		return results
	var buckets := _candidate_position_buckets(world_positions, candidate_cell_size)
	for plot_value in get_plots().values():
		var plot: Dictionary = plot_value
		var plot_id := str(plot.get("plot_id", ""))
		if plot_id == excluded_plot_id:
			continue
		var existing_size := float(plot.get("cell_size", DEFAULT_CELL_SIZE))
		var overlap_extent := (existing_size + candidate_cell_size) * 0.47
		for key_value in (plot.get("cells", {}) as Dictionary).keys():
			var cell: Dictionary = (plot.get("cells", {}) as Dictionary)[key_value]
			var existing: Vector3 = cell.get("world_position", Vector3.ZERO)
			for candidate_index in _nearby_candidate_indices(existing, overlap_extent, candidate_cell_size, buckets):
				if not results[candidate_index].is_empty():
					continue
				var candidate := world_positions[candidate_index] as Vector3
				if absf(existing.x - candidate.x) < overlap_extent and absf(existing.z - candidate.z) < overlap_extent:
					results[candidate_index] = {"plot_id": plot_id, "cell_key": str(key_value), "world_position": existing, "cell": cell, "plot": plot}
	return results


func _empty_cell_query_results(count: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for _index in count:
		results.append({})
	return results


func _candidate_position_buckets(world_positions: Array, bucket_size: float) -> Dictionary:
	var buckets: Dictionary = {}
	var safe_bucket_size := maxf(0.01, bucket_size)
	for index in world_positions.size():
		var position := world_positions[index] as Vector3
		var key := Vector2i(floori(position.x / safe_bucket_size), floori(position.z / safe_bucket_size))
		var indices: Array = buckets.get(key, [])
		indices.append(index)
		buckets[key] = indices
	return buckets


func _nearby_candidate_indices(existing: Vector3, overlap_extent: float, bucket_size: float, buckets: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var safe_bucket_size := maxf(0.01, bucket_size)
	var center := Vector2i(floori(existing.x / safe_bucket_size), floori(existing.z / safe_bucket_size))
	var radius := ceili(overlap_extent / safe_bucket_size) + 1
	for offset_y in range(-radius, radius + 1):
		for offset_x in range(-radius, radius + 1):
			for candidate_index in (buckets.get(center + Vector2i(offset_x, offset_y), []) as Array):
				result.append(int(candidate_index))
	return result


func can_actor_command_plot(actor: Node, plot_id: String) -> bool:
	if _gecs != null and _gecs.has_method("get_farm_plot_header_state"):
		return can_actor_command_plot_state(actor, _gecs.call("get_farm_plot_header_state", plot_id))
	return can_actor_command_plot_state(actor, get_plot(plot_id))


func can_actor_command_plot_state(actor: Node, state: Dictionary) -> bool:
	if state.is_empty() or actor == null:
		return false
	var owner := str(state.get("owner_faction_id", ""))
	if owner.is_empty():
		return true
	var actor_faction := str(actor.get("faction_name"))
	if actor_faction.is_empty():
		actor_faction = str(actor.get("faction_id"))
	return actor_faction == owner


## System-side policy assignment for authored fields: no commanding actor, and
## AUTO_CROP_POLICY is accepted alongside real crop ids and "" for manual.
func set_plot_crop_policy_unchecked(plot_id: String, crop_id: String) -> Dictionary:
	var state := get_plot(plot_id)
	if not is_active_field(state):
		return {}
	if not crop_id.is_empty() and crop_id != AUTO_CROP_POLICY and get_crop(crop_id) == null:
		return {}
	return _apply_crop_policy_to_state(state, crop_id)


func set_plot_crop_policy(plot_id: String, crop_id: String, actor: Node) -> Dictionary:
	var state := get_plot(plot_id)
	if not is_active_field(state) or not can_actor_command_plot(actor, plot_id) \
			or (not crop_id.is_empty() and get_crop(crop_id) == null):
		return {}
	return _apply_crop_policy_to_state(state, crop_id)


func _apply_crop_policy_to_state(state: Dictionary, crop_id: String) -> Dictionary:
	state["crop_policy_id"] = crop_id
	var crop := get_crop(crop_id)
	state["display_name"] = "%s Field" % crop.display_name if crop != null else "Field"
	var policy_crop_id := _effective_policy_crop_id(state)
	var cells: Dictionary = state.get("cells", {}).duplicate(true)
	for key in cells:
		cells[key] = _with_field_policy_request(cells[key], policy_crop_id)
	state["cells"] = cells
	return _save_plot(state)


## One manual hoe gesture is one durable intent transaction. Existing eligible
## cells keep their plot identity; new ground joins the field selected by the
## first square, or starts a No Crop field when no compatible field is there.
func prepare_manual_till(cell_positions: Array[Vector3], actor: Node, anchor_position := Vector3.ZERO) -> Dictionary:
	if _gecs == null or actor == null or not is_instance_valid(actor) or cell_positions.is_empty():
		return {}
	var owner_faction_id := _actor_faction_id(actor)
	if owner_faction_id.is_empty():
		return {}
	var unique_positions: Array[Vector3] = []
	var uniqueness_buckets: Dictionary = {}
	var uniqueness_size := DEFAULT_CELL_SIZE * 0.2
	for position in cell_positions:
		var bucket := Vector2i(floori(position.x / uniqueness_size), floori(position.z / uniqueness_size))
		var duplicate := false
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				for existing_value in (uniqueness_buckets.get(bucket + Vector2i(offset_x, offset_y), []) as Array):
					var existing := existing_value as Vector3
					if Vector2(existing.x, existing.z).distance_to(Vector2(position.x, position.z)) < uniqueness_size:
						duplicate = true
						break
				if duplicate:
					break
			if duplicate:
				break
		if not duplicate:
			unique_positions.append(position)
			var bucket_positions: Array = uniqueness_buckets.get(bucket, [])
			bucket_positions.append(position)
			uniqueness_buckets[bucket] = bucket_positions
	unique_positions = _permitted_field_positions(unique_positions, owner_faction_id)
	if unique_positions.is_empty():
		return {}
	var target_plot_id := ""
	var anchor_cell := find_plot_cell_at_world_position(anchor_position)
	if not anchor_cell.is_empty() \
			and is_active_field(str(anchor_cell.get("plot_id", ""))) \
			and can_actor_command_plot(actor, str(anchor_cell.get("plot_id", ""))):
		target_plot_id = str(anchor_cell.get("plot_id", ""))
	if target_plot_id.is_empty():
		target_plot_id = _adjacent_compatible_plot(anchor_position, owner_faction_id, "")
	var new_positions: Array = []
	var targets: Array[Dictionary] = []
	var occupied_cells := find_plot_cells_at_world_positions(unique_positions)
	for index in unique_positions.size():
		var position := unique_positions[index]
		var occupant: Dictionary = occupied_cells[index]
		if occupant.is_empty():
			new_positions.append(position)
			continue
		var occupant_plot_id := str(occupant.get("plot_id", ""))
		var occupant_cell_key := str(occupant.get("cell_key", ""))
		var occupant_plot: Dictionary = occupant.get("plot", {})
		if is_active_field(occupant_plot) and can_actor_command_plot_state(actor, occupant_plot) \
				and str((occupant.get("cell", {}) as Dictionary).get("state", "")) == FARM_SIMULATION.STATE_UNTILLED:
			targets.append({"plot_id": occupant_plot_id, "cell_key": occupant_cell_key})
	if not new_positions.is_empty():
		var changed: Dictionary
		if target_plot_id.is_empty():
			var keyed := _keyed_world_positions(new_positions)
			changed = create_plot(
				keyed.get("positions", []),
				keyed.get("dimensions", Vector2i.ONE),
				"",
				owner_faction_id,
				_actor_settlement_id(actor),
				{},
				keyed.get("cell_keys", PackedStringArray())
			)
			target_plot_id = str(changed.get("plot_id", ""))
		else:
			changed = expand_plot(target_plot_id, new_positions, actor)
		if changed.is_empty():
			return {}
		var added_cells := find_plot_cells_at_world_positions(new_positions)
		for index in new_positions.size():
			var added: Dictionary = added_cells[index]
			if str(added.get("plot_id", "")) == target_plot_id:
				targets.append({"plot_id": target_plot_id, "cell_key": str(added.get("cell_key", ""))})
	if not target_plot_id.is_empty():
		target_plot_id = _auto_merge_matching_adjacent(target_plot_id, actor)
	# A merge can change the owning plot/key for cells already collected above.
	# Resolve every exact world square again from authoritative state.
	targets.clear()
	var target_plot_states: Dictionary = {}
	var current_cells := find_plot_cells_at_world_positions(unique_positions)
	for index in unique_positions.size():
		var current: Dictionary = current_cells[index]
		var current_plot_id := str(current.get("plot_id", ""))
		var current_cell_key := str(current.get("cell_key", ""))
		var current_plot: Dictionary = current.get("plot", {})
		if not current.is_empty() and is_active_field(current_plot) and can_actor_command_plot_state(actor, current_plot) \
				and str((current.get("cell", {}) as Dictionary).get("state", "")) == FARM_SIMULATION.STATE_UNTILLED:
			targets.append({"plot_id": current_plot_id, "cell_key": current_cell_key})
			target_plot_states[current_plot_id] = current_plot
	var allowed_actor_ids := PackedStringArray([_actor_work_id(actor)])
	var requested := _request_cell_operations(targets, "till", "", allowed_actor_ids, target_plot_states)
	if requested.is_empty():
		return {}
	var primary_plot_id := str(requested[0].get("plot_id", ""))
	var primary_keys := PackedStringArray()
	for target in requested:
		if str(target.get("plot_id", "")) == primary_plot_id:
			primary_keys.append(str(target.get("cell_key", "")))
	return {"plot_id": primary_plot_id, "cell_keys": primary_keys, "targets": requested}


## Designate every currently eligible exact cell in one field.
func prepare_plot_till(plot_id: String, actor: Node, allowed_actor_ids := PackedStringArray()) -> Dictionary:
	var state := get_plot(plot_id)
	if not is_active_field(state) or not can_actor_command_plot_state(actor, state):
		return {}
	var keys: Array = (state.get("cells", {}) as Dictionary).keys()
	keys.sort_custom(func(a, b) -> bool:
		var grid_a := _grid_from_key(str(a))
		var grid_b := _grid_from_key(str(b))
		return grid_a.y < grid_b.y or (grid_a.y == grid_b.y and grid_a.x < grid_b.x)
	)
	var eligible_targets: Array[Dictionary] = []
	for key_value in keys:
		var key := str(key_value)
		var cell: Dictionary = (state.get("cells", {}) as Dictionary).get(key, {})
		if str(cell.get("state", "")) != FARM_SIMULATION.STATE_UNTILLED:
			continue
		eligible_targets.append({"plot_id": plot_id, "cell_key": key})
	var targets := _request_cell_operations(eligible_targets, "till", "", allowed_actor_ids, {plot_id: state})
	return {"plot_id": plot_id, "targets": targets} if not targets.is_empty() else {}


## Expand one exact manual cell action to every cell where that same action is
## currently valid. The clicked cell stays first so the command responds there.
func prepare_plot_operation(plot_id: String, operation: String, crop_id: String, allowed_actor_ids: PackedStringArray, preferred_cell_key := "", actor: Node = null) -> Dictionary:
	var state := get_plot(plot_id)
	if not is_active_field(state):
		return {}
	var cells: Dictionary = state.get("cells", {})
	if preferred_cell_key.is_empty() or not cells.has(preferred_cell_key) \
			or not _cell_matches_plot_operation(cells[preferred_cell_key], operation, actor):
		return {}
	var keys: Array = cells.keys()
	keys.sort_custom(func(a, b) -> bool:
		var key_a := str(a)
		var key_b := str(b)
		if key_a == preferred_cell_key:
			return true
		if key_b == preferred_cell_key:
			return false
		var grid_a := _grid_from_key(key_a)
		var grid_b := _grid_from_key(key_b)
		return grid_a.y < grid_b.y or (grid_a.y == grid_b.y and grid_a.x < grid_b.x)
	)
	var eligible_targets: Array[Dictionary] = []
	for key_value in keys:
		var key := str(key_value)
		var cell: Dictionary = cells.get(key_value, {})
		if not _cell_matches_plot_operation(cell, operation, actor):
			continue
		eligible_targets.append({"plot_id": plot_id, "cell_key": key})
	var targets := _request_cell_operations(eligible_targets, operation, crop_id, allowed_actor_ids, {plot_id: state})
	return {"plot_id": plot_id, "targets": targets} if not targets.is_empty() else {}


func _cell_matches_plot_operation(cell: Dictionary, operation: String, actor: Node) -> bool:
	if operation != _action_for_status(str(cell.get("state", ""))):
		return false
	if operation == "water" and not _cell_needs_water_state(cell):
		return false
	return _actor_can_use_operation_tool(actor, operation, cell)


func _actor_can_use_operation_tool(actor: Node, operation: String, cell: Dictionary) -> bool:
	var crop := get_crop(str(cell.get("crop_id", "")))
	var required_tag := _required_tool(crop, operation)
	if required_tag.is_empty():
		return true
	if actor == null or not is_instance_valid(actor):
		return false
	var equipment = actor.call("get_equipment") if actor.has_method("get_equipment") else null
	if equipment == null:
		return false
	var equipped = equipment.call("get_equipped_item", "weapon") if equipment.has_method("get_equipped_item") else null
	if equipped != null and equipped.has_method("has_tool_tag") and bool(equipped.call("has_tool_tag", required_tag)):
		return true
	var inventory = actor.get("inventory") if _has_object_property(actor, "inventory") else null
	if inventory == null and actor.has_method("get_inventory"):
		inventory = actor.call("get_inventory")
	if inventory != null and inventory.has_method("get_inventory_for_display"):
		inventory = inventory.call("get_inventory_for_display")
	elif inventory != null and _has_object_property(inventory, "inventory"):
		inventory = inventory.get("inventory")
	if inventory == null or not _has_object_property(inventory, "entries") \
			or not equipment.has_method("can_equip_item_to_slot"):
		return false
	for entry in inventory.entries:
		if entry != null and entry.definition != null and entry.definition.has_method("has_tool_tag") \
				and entry.definition.has_tool_tag(required_tag) \
				and bool(equipment.call("can_equip_item_to_slot", entry.definition, "weapon")):
			return true
	return false


func _has_object_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _actor_faction_id(actor: Node) -> String:
	var faction := str(actor.get("faction_name"))
	if faction.is_empty():
		faction = str(actor.get("faction_id"))
	return faction


func _actor_settlement_id(actor: Node) -> String:
	if actor == null:
		return ""
	for key in ["assigned_settlement_id", "settlement_id"]:
		if actor.has_meta(key):
			var metadata_value := str(actor.get_meta(key, ""))
			if not metadata_value.is_empty():
				return metadata_value
		for property in actor.get_property_list():
			if str(property.get("name", "")) == key:
				var property_value := str(actor.get(key))
				if not property_value.is_empty():
					return property_value
	return ""


func _actor_work_id(actor: Node) -> String:
	var stable_id := str(actor.get("stable_id"))
	if stable_id.is_empty():
		stable_id = str(actor.get_meta("stable_id", ""))
	return stable_id if not stable_id.is_empty() else "instance:%d" % actor.get_instance_id()


func _adjacent_compatible_plot(world_position: Vector3, owner_faction_id: String, crop_policy_id: String) -> String:
	for plot_value in get_plots().values():
		var plot: Dictionary = plot_value
		if not is_active_field(plot) \
				or str(plot.get("owner_faction_id", "")) != owner_faction_id \
				or str(plot.get("crop_policy_id", "")) != crop_policy_id:
			continue
		var spacing := float(plot.get("cell_size", DEFAULT_CELL_SIZE))
		for cell_value in (plot.get("cells", {}) as Dictionary).values():
			var position: Vector3 = (cell_value as Dictionary).get("world_position", Vector3.ZERO)
			var delta := Vector2(absf(position.x - world_position.x), absf(position.z - world_position.z))
			if (absf(delta.x - spacing) < spacing * 0.2 and delta.y < spacing * 0.2) \
					or (absf(delta.y - spacing) < spacing * 0.2 and delta.x < spacing * 0.2):
				return str(plot.get("plot_id", ""))
	return ""


func _keyed_world_positions(cell_positions: Array) -> Dictionary:
	var minimum_x := INF
	var minimum_z := INF
	for position_value in cell_positions:
		var position := position_value as Vector3
		minimum_x = minf(minimum_x, position.x)
		minimum_z = minf(minimum_z, position.z)
	var keyed: Dictionary = {}
	var maximum := Vector2i.ZERO
	for position_value in cell_positions:
		var position := position_value as Vector3
		var grid := Vector2i(roundi((position.x - minimum_x) / DEFAULT_CELL_SIZE), roundi((position.z - minimum_z) / DEFAULT_CELL_SIZE))
		keyed["%d:%d" % [grid.x, grid.y]] = {"grid": grid, "position": position}
		maximum = maximum.max(grid)
	var keys: Array = keyed.keys()
	keys.sort_custom(func(a, b) -> bool:
		var grid_a: Vector2i = keyed[a].get("grid", Vector2i.ZERO)
		var grid_b: Vector2i = keyed[b].get("grid", Vector2i.ZERO)
		return grid_a.y < grid_b.y or (grid_a.y == grid_b.y and grid_a.x < grid_b.x)
	)
	var positions: Array[Vector3] = []
	var cell_keys := PackedStringArray()
	for key in keys:
		positions.append(keyed[key].get("position", Vector3.ZERO))
		cell_keys.append(str(key))
	return {"positions": positions, "cell_keys": cell_keys, "dimensions": maximum + Vector2i.ONE}


func expand_plot(plot_id: String, cell_positions: Array, actor: Node) -> Dictionary:
	var state := get_plot(plot_id)
	if not is_active_field(state) or not can_actor_command_plot(actor, plot_id):
		return {}
	var cells: Dictionary = state.get("cells", {})
	if cells.is_empty() or cell_positions.is_empty():
		return {}
	var additions: Dictionary = {}
	var remnants: Dictionary = state.get("soil_remnants", {}).duplicate(true)
	var pending_additions: Array[Dictionary] = []
	var pending_keys: Dictionary = {}
	for position_value in cell_positions:
		var snapped := _snap_position_to_plot_grid(state, position_value as Vector3)
		if snapped.is_empty():
			return {}
		var key := str(snapped.get("cell_key", ""))
		if cells.has(key) or pending_keys.has(key):
			continue
		var position: Vector3 = snapped.get("world_position", Vector3.ZERO)
		pending_additions.append({"key": key, "position": position, "grid_position": snapped.get("grid_position", Vector2i.ZERO)})
		pending_keys[key] = true
	var pending_positions: Array[Vector3] = []
	for pending in pending_additions:
		pending_positions.append(pending.get("position", Vector3.ZERO))
	if pending_positions.is_empty() or not _all_field_positions_permitted(pending_positions, _actor_faction_id(actor)):
		return {}
	var occupied_cells := find_plot_cells_at_world_positions(pending_positions, plot_id, float(state.get("cell_size", DEFAULT_CELL_SIZE)))
	for occupied in occupied_cells:
		if not occupied.is_empty():
			return {}
	for pending in pending_additions:
		var key := str(pending.get("key", ""))
		var position: Vector3 = pending.get("position", Vector3.ZERO)
		if remnants.has(key):
			var restored: Dictionary = remnants[key].duplicate(true)
			restored["grid_position"] = pending.get("grid_position", Vector2i.ZERO)
			restored["world_position"] = position
			additions[key] = restored
			remnants.erase(key)
		else:
			additions[key] = FARM_SIMULATION.new_cell(pending.get("grid_position", Vector2i.ZERO), position)
	if additions.is_empty():
		return {}
	var expanded_cells := cells.duplicate(true)
	for key in additions:
		expanded_cells[key] = additions[key]
	if not _cells_are_contiguous(expanded_cells):
		return {}
	state["cells"] = expanded_cells
	state["soil_remnants"] = remnants
	_refresh_plot_dimensions(state)
	return _save_plot(state)


func _can_create_field_at(world_position: Vector3, owner_faction_id: String) -> bool:
	if _territory == null or not _territory.has_method("get_build_permission"):
		return false
	var permission: Dictionary = _territory.call("get_build_permission", world_position, owner_faction_id)
	return bool(permission.get("can_build", false))


func _all_field_positions_permitted(world_positions: Array, owner_faction_id: String) -> bool:
	if world_positions.is_empty() or _territory == null or not _territory.has_method("get_build_permissions"):
		return false
	var permissions: Array = _territory.call("get_build_permissions", world_positions, owner_faction_id)
	if permissions.size() != world_positions.size():
		return false
	for permission_value in permissions:
		var permission := permission_value as Dictionary
		if not bool(permission.get("can_build", false)):
			return false
	return true


func _permitted_field_positions(world_positions: Array[Vector3], owner_faction_id: String) -> Array[Vector3]:
	var permitted: Array[Vector3] = []
	if world_positions.is_empty() or _territory == null or not _territory.has_method("get_build_permissions"):
		return permitted
	var permissions: Array = _territory.call("get_build_permissions", world_positions, owner_faction_id)
	if permissions.size() != world_positions.size():
		return permitted
	for index in world_positions.size():
		var permission: Dictionary = permissions[index]
		if bool(permission.get("can_build", false)):
			permitted.append(world_positions[index])
	return permitted


func shrink_plot(plot_id: String, cell_keys: PackedStringArray, actor: Node) -> Dictionary:
	var state := get_plot(plot_id)
	if not is_active_field(state) or not can_actor_command_plot(actor, plot_id) or cell_keys.is_empty() \
			or _plot_has_active_work(state):
		return {}
	var cells: Dictionary = state.get("cells", {}).duplicate(true)
	var removed_cells: Dictionary = {}
	var removed := false
	for key in cell_keys:
		if cells.has(key):
			removed_cells[key] = (cells[key] as Dictionary).duplicate(true)
			cells.erase(key)
			removed = true
	if not removed:
		return {}
	if cells.is_empty():
		return delete_field(plot_id, actor)
	var remnants: Dictionary = state.get("soil_remnants", {}).duplicate(true)
	var detached_crop_cells: Dictionary = {}
	for key in removed_cells:
		var removed_cell: Dictionary = removed_cells[key]
		if not bool(removed_cell.get("soil_created", false)):
			continue
		removed_cell.erase("work")
		removed_cell.erase("requested_operation")
		removed_cell.erase("requested_crop_id")
		removed_cell.erase("requested_actor_ids")
		removed_cell.erase("request_source")
		removed_cell["claimed_by"] = ""
		removed_cell["work_progress"] = 0.0
		removed_cell["soil_recovery_started_minute"] = _absolute_minute()
		if str(removed_cell.get("crop_id", "")).is_empty():
			remnants[key] = removed_cell
		else:
			detached_crop_cells[key] = removed_cell
	state["cells"] = cells
	state["soil_remnants"] = remnants
	var components := _cell_components(cells)
	if components.is_empty():
		return {}
	state["cells"] = components[0]
	_refresh_plot_dimensions(state)
	var saved := _save_plot(state)
	for component_index in range(1, components.size()):
		var split_state := state.duplicate(true)
		split_state["plot_id"] = "farm:%d" % _next_plot_sequence
		_next_plot_sequence += 1
		split_state["cells"] = components[component_index]
		split_state["soil_remnants"] = {}
		split_state["state_revision"] = 0
		_refresh_plot_dimensions(split_state)
		_save_plot(split_state)
	if not detached_crop_cells.is_empty():
		var detached_state := state.duplicate(true)
		detached_state["plot_id"] = "farm:%d" % _next_plot_sequence
		_next_plot_sequence += 1
		detached_state["display_name"] = ""
		detached_state["crop_policy_id"] = ""
		detached_state["field_deleted"] = true
		detached_state["cells"] = detached_crop_cells
		detached_state["soil_remnants"] = {}
		detached_state["state_revision"] = 0
		_refresh_plot_dimensions(detached_state)
		_save_plot(detached_state)
	return saved


func plot_cell_keys_in_rectangle(plot_id: String, start: Vector3, finish: Vector3) -> PackedStringArray:
	var state := get_plot(plot_id)
	var result := PackedStringArray()
	if not is_active_field(state):
		return result
	var minimum := Vector2(minf(start.x, finish.x), minf(start.z, finish.z))
	var maximum := Vector2(maxf(start.x, finish.x), maxf(start.z, finish.z))
	var tolerance := float(state.get("cell_size", DEFAULT_CELL_SIZE)) * 0.25
	for key_value in (state.get("cells", {}) as Dictionary).keys():
		var cell: Dictionary = (state.get("cells", {}) as Dictionary)[key_value]
		var position: Vector3 = cell.get("world_position", Vector3.ZERO)
		if position.x >= minimum.x - tolerance and position.x <= maximum.x + tolerance \
				and position.z >= minimum.y - tolerance and position.z <= maximum.y + tolerance:
			result.append(str(key_value))
	return result


func plot_rectangle_positions(plot_id: String, start: Vector3, finish: Vector3) -> Array[Vector3]:
	var state := get_plot(plot_id)
	var positions: Array[Vector3] = []
	if not is_active_field(state):
		return positions
	var snapped_start := _snap_position_to_plot_grid(state, start)
	var snapped_finish := _snap_position_to_plot_grid(state, finish)
	if snapped_start.is_empty() or snapped_finish.is_empty():
		return positions
	var start_grid: Vector2i = snapped_start.get("grid_position", Vector2i.ZERO)
	var finish_grid: Vector2i = snapped_finish.get("grid_position", Vector2i.ZERO)
	var minimum := start_grid.min(finish_grid)
	var maximum := start_grid.max(finish_grid)
	var spacing := float(state.get("cell_size", DEFAULT_CELL_SIZE))
	var start_position: Vector3 = snapped_start.get("world_position", Vector3.ZERO)
	for z in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			positions.append(start_position + Vector3(float(x - start_grid.x) * spacing, 0.0, float(z - start_grid.y) * spacing))
	return positions


## Logical deletion retires policy and boundaries while retaining a hidden
## durable remnant container for crops, dead plants, and cultivated ground.
func delete_field(plot_id: String, actor: Node) -> Dictionary:
	var state := get_plot(plot_id)
	if not is_active_field(state) or not can_actor_command_plot(actor, plot_id):
		return {}
	var active_keys := PackedStringArray()
	var farm_work = _context.get_optional(&"farm_work") if _context != null else null
	if farm_work != null and farm_work.has_method("retire_plot_work"):
		active_keys = PackedStringArray(farm_work.call("retire_plot_work", plot_id))
	# Queue retirement persists cancellation revisions; never overwrite those
	# saves with the snapshot taken before retire_plot_work().
	state = get_plot(plot_id)
	var retained_cells: Dictionary = {}
	for key_value in (state.get("cells", {}) as Dictionary).keys():
		var key := str(key_value)
		var cell: Dictionary = (state.get("cells", {}) as Dictionary)[key_value].duplicate(true)
		var physically_present := bool(cell.get("soil_created", false)) \
				or not str(cell.get("crop_id", "")).is_empty() or active_keys.has(key)
		if not active_keys.has(key):
			cell.erase("requested_operation")
			cell.erase("requested_crop_id")
			cell.erase("requested_actor_ids")
			cell.erase("request_source")
			cell["work_progress"] = 0.0
			cell["claimed_by"] = ""
		if physically_present:
			retained_cells[key] = cell
	state["field_deleted"] = true
	state["crop_policy_id"] = ""
	state["display_name"] = ""
	state["cells"] = retained_cells
	_refresh_plot_dimensions(state)
	if retained_cells.is_empty() and (state.get("soil_remnants", {}) as Dictionary).is_empty():
		remove_plot(plot_id)
		return {"plot_id": plot_id, "field_deleted": true, "cells": {}, "soil_remnants": {}}
	return _save_plot(state)


func merge_adjacent_plots(source_plot_id: String, absorbed_plot_id: String, actor: Node) -> Dictionary:
	if source_plot_id.is_empty() or absorbed_plot_id.is_empty() or source_plot_id == absorbed_plot_id:
		return {}
	var plots := get_plots()
	var source: Dictionary = (plots.get(source_plot_id, {}) as Dictionary).duplicate(true)
	var absorbed: Dictionary = (plots.get(absorbed_plot_id, {}) as Dictionary).duplicate(true)
	return _merge_plot_states(source, absorbed, actor)


func _merge_plot_states(source: Dictionary, absorbed: Dictionary, actor: Node) -> Dictionary:
	var source_plot_id := str(source.get("plot_id", ""))
	var absorbed_plot_id := str(absorbed.get("plot_id", ""))
	if not is_active_field(source) or not is_active_field(absorbed) \
			or not can_actor_command_plot_state(actor, source) \
			or not can_actor_command_plot_state(actor, absorbed) \
			or _plot_has_active_work(source) \
			or _plot_has_active_work(absorbed) \
			or not _plots_touch(source, absorbed):
		return {}
	var merged_cells: Dictionary = (source.get("cells", {}) as Dictionary).duplicate(true)
	for cell_value in (absorbed.get("cells", {}) as Dictionary).values():
		var cell: Dictionary = cell_value
		var snapped := _snap_position_to_plot_grid(source, cell.get("world_position", Vector3.ZERO))
		if snapped.is_empty():
			return {}
		var key := str(snapped.get("cell_key", ""))
		if merged_cells.has(key):
			return {}
		var copied := cell.duplicate(true)
		copied["grid_position"] = snapped.get("grid_position", Vector2i.ZERO)
		copied["world_position"] = snapped.get("world_position", Vector3.ZERO)
		merged_cells[key] = copied
	if not _cells_are_contiguous(merged_cells):
		return {}
	var merged_remnants: Dictionary = (source.get("soil_remnants", {}) as Dictionary).duplicate(true)
	for remnant_value in (absorbed.get("soil_remnants", {}) as Dictionary).values():
		var remnant: Dictionary = remnant_value
		var snapped_remnant := _snap_position_to_plot_grid(source, remnant.get("world_position", Vector3.ZERO))
		if snapped_remnant.is_empty():
			continue
		var remnant_key := str(snapped_remnant.get("cell_key", ""))
		if merged_cells.has(remnant_key):
			continue
		var copied_remnant := remnant.duplicate(true)
		copied_remnant["grid_position"] = snapped_remnant.get("grid_position", Vector2i.ZERO)
		copied_remnant["world_position"] = snapped_remnant.get("world_position", Vector3.ZERO)
		merged_remnants[remnant_key] = copied_remnant
	for member_key in merged_cells:
		merged_remnants.erase(member_key)
	source["cells"] = merged_cells
	source["soil_remnants"] = merged_remnants
	_refresh_plot_dimensions(source)
	var saved := _save_plot(source)
	remove_plot(absorbed_plot_id)
	return saved


func get_mergeable_adjacent_plot_ids(source_plot_id: String, actor: Node) -> PackedStringArray:
	var result := PackedStringArray()
	if actor == null:
		return result
	var plots := get_plots()
	var source: Dictionary = plots.get(source_plot_id, {})
	if not is_active_field(source) or _plot_has_active_work(source) \
			or not can_actor_command_plot_state(actor, source):
		return result
	for candidate_value in plots.values():
		var candidate: Dictionary = candidate_value
		var candidate_id := str(candidate.get("plot_id", ""))
		if candidate_id == source_plot_id or not is_active_field(candidate) \
				or _plot_has_active_work(candidate) or not _plots_touch(source, candidate) \
				or not can_actor_command_plot_state(actor, candidate):
			continue
		result.append(candidate_id)
	return result


func has_mergeable_adjacent_plot(source_plot_id: String, actor: Node) -> bool:
	return not get_mergeable_adjacent_plot_ids(source_plot_id, actor).is_empty()


func _auto_merge_matching_adjacent(source_plot_id: String, actor: Node) -> String:
	var plots := get_plots()
	var source: Dictionary = (plots.get(source_plot_id, {}) as Dictionary).duplicate(true)
	if source.is_empty() or _plot_has_active_work(source):
		return source_plot_id
	var changed := true
	while changed:
		changed = false
		for candidate_value in plots.values():
			var candidate: Dictionary = candidate_value
			var candidate_id := str(candidate.get("plot_id", ""))
			if candidate_id == source_plot_id \
					or _plot_has_active_work(candidate) \
					or not _field_behavior_matches(source, candidate) \
					or not _plots_touch(source, candidate):
				continue
			var merged := _merge_plot_states(source, candidate, actor)
			if not merged.is_empty():
				source = merged
				plots[source_plot_id] = merged
				plots.erase(candidate_id)
				changed = true
				break
	return source_plot_id


func _field_behavior_matches(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("owner_faction_id", "")) == str(b.get("owner_faction_id", "")) \
			and str(a.get("settlement_id", "")) == str(b.get("settlement_id", "")) \
			and str(a.get("crop_policy_id", "")) == str(b.get("crop_policy_id", "")) \
			and int(a.get("priority", 0)) == int(b.get("priority", 0)) \
			and str(a.get("worker_policy", "default")) == str(b.get("worker_policy", "default"))


func _plot_has_active_work(plot: Dictionary) -> bool:
	var farm_work = _context.get_optional(&"farm_work") if _context != null else null
	if farm_work != null and farm_work.has_method("has_active_work_for_plot") \
			and bool(farm_work.call("has_active_work_for_plot", str(plot.get("plot_id", "")))):
		return true
	for cell_value in (plot.get("cells", {}) as Dictionary).values():
		var cell: Dictionary = cell_value
		if not str(cell.get("work", {}).get("action", "")).is_empty() \
				or not str(cell.get("claimed_by", "")).is_empty() \
				or float(cell.get("work_progress", 0.0)) > 0.0:
			return true
	return false


func _plots_touch(a: Dictionary, b: Dictionary) -> bool:
	var spacing := float(a.get("cell_size", DEFAULT_CELL_SIZE))
	var a_positions: Array[Vector3] = []
	for a_value in (a.get("cells", {}) as Dictionary).values():
		a_positions.append((a_value as Dictionary).get("world_position", Vector3.ZERO))
	var buckets := _candidate_position_buckets(a_positions, spacing)
	for b_value in (b.get("cells", {}) as Dictionary).values():
		var b_position: Vector3 = (b_value as Dictionary).get("world_position", Vector3.ZERO)
		for a_index in _nearby_candidate_indices(b_position, spacing * 1.2, spacing, buckets):
			var a_position := a_positions[a_index]
			var delta := Vector2(absf(a_position.x - b_position.x), absf(a_position.z - b_position.z))
			if (absf(delta.x - spacing) < spacing * 0.2 and delta.y < spacing * 0.2) \
					or (absf(delta.y - spacing) < spacing * 0.2 and delta.x < spacing * 0.2):
				return true
	return false


func _snap_position_to_plot_grid(state: Dictionary, position: Vector3) -> Dictionary:
	var cells: Dictionary = state.get("cells", {})
	if cells.is_empty():
		return {}
	var base: Dictionary = cells.values()[0]
	var base_grid: Vector2i = base.get("grid_position", Vector2i.ZERO)
	var base_position: Vector3 = base.get("world_position", Vector3.ZERO)
	var spacing := float(state.get("cell_size", DEFAULT_CELL_SIZE))
	var offset := Vector2i(
		roundi((position.x - base_position.x) / spacing),
		roundi((position.z - base_position.z) / spacing)
	)
	var grid := base_grid + offset
	var snapped := Vector3(
		base_position.x + float(offset.x) * spacing,
		position.y,
		base_position.z + float(offset.y) * spacing
	)
	if Vector2(snapped.x, snapped.z).distance_to(Vector2(position.x, position.z)) > spacing * 0.3:
		return {}
	return {
		"cell_key": "%d:%d" % [grid.x, grid.y],
		"grid_position": grid,
		"world_position": snapped,
	}


func _cells_are_contiguous(cells: Dictionary) -> bool:
	if cells.is_empty():
		return false
	var by_grid: Dictionary = {}
	for cell_value in cells.values():
		var cell: Dictionary = cell_value
		var grid: Vector2i = cell.get("grid_position", Vector2i.ZERO)
		by_grid["%d:%d" % [grid.x, grid.y]] = true
	var first_key := str(by_grid.keys()[0])
	var open := [first_key]
	var visited := {first_key: true}
	while not open.is_empty():
		var current_key := str(open.pop_back())
		var current := _grid_from_key(current_key)
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = current + (direction as Vector2i)
			var neighbor_key := "%d:%d" % [neighbor.x, neighbor.y]
			if by_grid.has(neighbor_key) and not visited.has(neighbor_key):
				visited[neighbor_key] = true
				open.append(neighbor_key)
	return visited.size() == by_grid.size()


func _cell_components(cells: Dictionary) -> Array[Dictionary]:
	var remaining := cells.duplicate(true)
	var components: Array[Dictionary] = []
	while not remaining.is_empty():
		var open := [str(remaining.keys()[0])]
		var component: Dictionary = {}
		while not open.is_empty():
			var key := str(open.pop_back())
			if not remaining.has(key):
				continue
			component[key] = remaining[key]
			remaining.erase(key)
			var grid := _grid_from_key(key)
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var neighbor: Vector2i = grid + (direction as Vector2i)
				var neighbor_key := "%d:%d" % [neighbor.x, neighbor.y]
				if remaining.has(neighbor_key):
					open.append(neighbor_key)
		components.append(component)
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_keys: Array = a.keys()
		var b_keys: Array = b.keys()
		a_keys.sort()
		b_keys.sort()
		return str(a_keys[0]) < str(b_keys[0])
	)
	return components


func _refresh_plot_dimensions(state: Dictionary) -> void:
	var cells: Dictionary = state.get("cells", {})
	if cells.is_empty():
		state["dimensions"] = Vector2i.ZERO
		return
	var minimum := Vector2i(2147483647, 2147483647)
	var maximum := Vector2i(-2147483648, -2147483648)
	for cell_value in cells.values():
		var grid: Vector2i = (cell_value as Dictionary).get("grid_position", Vector2i.ZERO)
		minimum = minimum.min(grid)
		maximum = maximum.max(grid)
	state["dimensions"] = maximum - minimum + Vector2i.ONE


func _request_cell_operations(targets: Array[Dictionary], operation: String, crop_id: String, allowed_actor_ids: PackedStringArray, known_states := {}) -> Array[Dictionary]:
	var grouped: Dictionary = {}
	for target in targets:
		var plot_id := str(target.get("plot_id", ""))
		var cell_key := str(target.get("cell_key", ""))
		if plot_id.is_empty() or cell_key.is_empty():
			continue
		var keys: Array = grouped.get(plot_id, [])
		if not keys.has(cell_key):
			keys.append(cell_key)
			grouped[plot_id] = keys
	var requested: Array[Dictionary] = []
	for plot_id_value in grouped.keys():
		var plot_id := str(plot_id_value)
		var state: Dictionary = (known_states.get(plot_id, {}) as Dictionary).duplicate(true)
		if state.is_empty():
			state = get_plot(plot_id)
		var cells: Dictionary = state.get("cells", {})
		var direct_retired_action := bool(state.get("field_deleted", false)) and not allowed_actor_ids.is_empty()
		if (not is_active_field(state) and not direct_retired_action) or (operation == "plant" and get_crop(crop_id) == null):
			continue
		var changed := false
		for cell_key_value in grouped[plot_id]:
			var cell_key := str(cell_key_value)
			if not cells.has(cell_key):
				continue
			var cell: Dictionary = (cells[cell_key] as Dictionary).duplicate(true)
			if operation != _action_for_status(str(cell.get("state", ""))):
				continue
			cell["requested_operation"] = operation
			cell["requested_crop_id"] = crop_id if operation == "plant" else str(cell.get("crop_id", ""))
			cell["requested_actor_ids"] = allowed_actor_ids.duplicate()
			if allowed_actor_ids.is_empty():
				cell.erase("request_source")
			else:
				cell["request_source"] = "manual"
			cell["request_revision"] = int(cell.get("request_revision", 0)) + 1
			cells[cell_key] = cell
			requested.append({"plot_id": plot_id, "cell_key": cell_key, "request_revision": int(cell["request_revision"])})
			changed = true
		if changed:
			state["cells"] = cells
			_save_plot(state)
	return requested


func request_cell_operation(plot_id: String, cell_key: String, operation: String, crop_id := "", allowed_actor_ids := PackedStringArray()) -> Dictionary:
	var state := get_plot(plot_id)
	var cells: Dictionary = state.get("cells", {})
	var direct_retired_action := bool(state.get("field_deleted", false)) and not allowed_actor_ids.is_empty()
	if (not is_active_field(state) and not direct_retired_action) or not cells.has(cell_key):
		return {}
	var cell: Dictionary = (cells[cell_key] as Dictionary).duplicate(true)
	if operation != _action_for_status(str(cell.get("state", ""))):
		return {}
	if operation == "plant" and get_crop(crop_id) == null:
		return {}
	cell["requested_operation"] = operation
	cell["requested_crop_id"] = crop_id if operation == "plant" else str(cell.get("crop_id", ""))
	cell["requested_actor_ids"] = allowed_actor_ids.duplicate()
	if allowed_actor_ids.is_empty():
		cell.erase("request_source")
	else:
		cell["request_source"] = "manual"
	cell["request_revision"] = int(cell.get("request_revision", 0)) + 1
	cells[cell_key] = cell
	state["cells"] = cells
	return _save_plot(state)


## Withdraw one exact manual request only if it is still the same transaction.
## A field policy may immediately republish ordinary settlement work afterward.
func cancel_cell_operation(plot_id: String, cell_key: String, expected_request_revision: int, actor_id: String) -> Dictionary:
	var state := get_plot(plot_id)
	var cells: Dictionary = state.get("cells", {})
	if state.is_empty() or not cells.has(cell_key):
		return {}
	var cell: Dictionary = (cells[cell_key] as Dictionary).duplicate(true)
	if str(cell.get("requested_operation", "")).is_empty() \
			or int(cell.get("request_revision", 0)) != expected_request_revision:
		return {}
	var allowed_actor_ids := PackedStringArray(cell.get("requested_actor_ids", PackedStringArray()))
	if actor_id.is_empty() or not allowed_actor_ids.has(actor_id):
		return {}
	cell.erase("requested_operation")
	cell.erase("requested_crop_id")
	cell.erase("requested_actor_ids")
	cell.erase("request_source")
	cell["work_progress"] = 0.0
	cell["claimed_by"] = ""
	cell["request_revision"] = expected_request_revision + 1
	cell = _with_field_policy_request(cell, _effective_policy_crop_id(state), is_active_field(state))
	cells[cell_key] = cell
	state["cells"] = cells
	return _save_plot(state)


func get_cell_work(plot_id: String, cell_key: String) -> Dictionary:
	if _gecs != null and _gecs.has_method("get_farm_plot_cell_record"):
		var record: Dictionary = _gecs.call("get_farm_plot_cell_record", plot_id, cell_key)
		var indexed_cell: Dictionary = record.get("cell", {})
		if record.is_empty() or indexed_cell.is_empty():
			return {}
		var indexed_action := str(indexed_cell.get("requested_operation", ""))
		if indexed_action.is_empty() or indexed_action != _action_for_status(str(indexed_cell.get("state", ""))):
			return {}
		if indexed_action == "water" and not _cell_needs_water_state(indexed_cell):
			return {}
		return _work_record(record, cell_key, indexed_cell, indexed_action)
	var state := get_plot(plot_id)
	var cells: Dictionary = state.get("cells", {})
	if state.is_empty() or not cells.has(cell_key):
		return {}
	var cell: Dictionary = cells[cell_key]
	var action := str(cell.get("requested_operation", ""))
	if action.is_empty() or action != _action_for_status(str(cell.get("state", ""))):
		return {}
	if action == "water" and not cell_needs_water(plot_id, cell_key):
		return {}
	return _work_record(state, cell_key, cell, action)


## One-snapshot Jobs read. The work bridge caches this result until a plot
## mutation invalidates it; never call get_plot() once per cell here.
func get_available_work_records(settlement_id := "") -> Array:
	var records: Array = []
	for state_value in get_plots().values():
		var state: Dictionary = state_value
		if not is_active_field(state):
			continue
		var plot_settlement_id := str(state.get("settlement_id", ""))
		if not settlement_id.is_empty() and plot_settlement_id != settlement_id:
			continue
		for cell_key_value in (state.get("cells", {}) as Dictionary).keys():
			var cell_key := str(cell_key_value)
			var cell: Dictionary = (state.get("cells", {}) as Dictionary).get(cell_key_value, {})
			var action := str(cell.get("requested_operation", ""))
			if action.is_empty() or action != _action_for_status(str(cell.get("state", ""))):
				continue
			if action == "water" and not _cell_needs_water_state(cell):
				continue
			var work := _work_record(state, cell_key, cell, action)
			work["settlement_id"] = plot_settlement_id
			work["owner_faction_id"] = str(state.get("owner_faction_id", ""))
			records.append(work)
	return records


func cell_needs_water(plot_id: String, cell_key: String) -> bool:
	return _cell_needs_water_state(get_cell(plot_id, cell_key))


func _cell_needs_water_state(cell: Dictionary) -> bool:
	return not cell.is_empty() and str(cell.get("state", "")) == FARM_SIMULATION.STATE_GROWING \
			and float(cell.get("water", 0.0)) < _watering_threshold(cell)


func get_next_work(plot_id: String, excluded_keys := PackedStringArray()) -> Dictionary:
	var state := get_plot(plot_id)
	if not is_active_field(state):
		return {}
	var cells: Dictionary = state.get("cells", {})
	for key_value in cells.keys():
		var key := str(key_value)
		if excluded_keys.has(key):
			continue
		var work := get_cell_work(plot_id, key)
		if not work.is_empty():
			return work
	return {}


func apply_work(plot_id: String, cell_key: String, action: String, seconds: float, farming_level := 0.0, expected_request_revision := -1) -> Dictionary:
	var results := apply_work_batch([{
		"plot_id": plot_id,
		"cell_key": cell_key,
		"action": action,
		"seconds": seconds,
		"farming_level": farming_level,
		"expected_request_revision": expected_request_revision,
	}])
	return results[0] as Dictionary if not results.is_empty() else {}


## Apply every due projected work delta with one authoritative save per plot.
## Results stay request-ordered so inventory rollback/completion behavior remains
## identical to apply_work().
func apply_work_batch(requests: Array) -> Array:
	var results: Array = []
	var indices_by_plot: Dictionary = {}
	for index in requests.size():
		results.append({})
		var request: Dictionary = requests[index] if requests[index] is Dictionary else {}
		var plot_id := str(request.get("plot_id", ""))
		if plot_id.is_empty():
			continue
		var indices: Array = indices_by_plot.get(plot_id, [])
		indices.append(index)
		indices_by_plot[plot_id] = indices
	for plot_id_value in indices_by_plot.keys():
		var plot_id := str(plot_id_value)
		var indexed_cell_io := _gecs != null \
				and _gecs.has_method("get_farm_plot_header_state") \
				and _gecs.has_method("get_farm_plot_cell_record") \
				and _gecs.has_method("upsert_farm_plot_cells")
		var state: Dictionary = _gecs.call("get_farm_plot_header_state", plot_id) if indexed_cell_io else get_plot(plot_id)
		if state.is_empty():
			continue
		if indexed_cell_io:
			var requested_cells: Dictionary = {}
			for index_value in (indices_by_plot[plot_id_value] as Array):
				var request: Dictionary = requests[int(index_value)]
				var cell_key := str(request.get("cell_key", ""))
				var record: Dictionary = _gecs.call("get_farm_plot_cell_record", plot_id, cell_key)
				if not record.is_empty():
					requested_cells[cell_key] = (record.get("cell", {}) as Dictionary).duplicate(true)
			state["cells"] = requested_cells
		var state_changed := false
		var completed_results: Array[Dictionary] = []
		for index_value in (indices_by_plot[plot_id_value] as Array):
			var index := int(index_value)
			var request: Dictionary = requests[index]
			var result := _apply_work_to_state(
				state,
				str(request.get("cell_key", "")),
				str(request.get("action", "")),
				float(request.get("seconds", 0.0)),
				float(request.get("farming_level", 0.0)),
				int(request.get("expected_request_revision", -1))
			)
			results[index] = result
			if result.is_empty():
				continue
			state_changed = true
			if bool(result.get("completed", false)):
				completed_results.append(result)
		if not state_changed:
			continue
		# Partial work changes only durable progress. The live worker owns the
		# progress presentation, so avoid rebuilding field offers and projection
		# until a cell actually transitions state.
		var changed_cell_records: Dictionary = {}
		for index_value in (indices_by_plot[plot_id_value] as Array):
			var changed_index := int(index_value)
			if (results[changed_index] as Dictionary).is_empty():
				continue
			var changed_key := str((requests[changed_index] as Dictionary).get("cell_key", ""))
			if (state.get("cells", {}) as Dictionary).has(changed_key):
				changed_cell_records[changed_key] = ((state.get("cells", {}) as Dictionary)[changed_key] as Dictionary).duplicate(true)
		var saved: Dictionary = _gecs.call("upsert_farm_plot_cells", plot_id, changed_cell_records) if indexed_cell_io else _save_plot(state, false)
		if saved.is_empty():
			continue
		var changed_cells: Dictionary = {}
		for result in completed_results:
			var completed_cell_key := str(result.get("cell_key", ""))
			var saved_cells: Dictionary = saved.get("cells", {})
			if saved_cells.has(completed_cell_key):
				changed_cells[completed_cell_key] = (saved_cells[completed_cell_key] as Dictionary).duplicate(true)
			work_completed.emit(result)
		if not changed_cells.is_empty():
			plot_cells_changed.emit(plot_id, changed_cells, str(saved.get("settlement_id", "")))
	return results


func _apply_work_to_state(state: Dictionary, cell_key: String, action: String, seconds: float, farming_level: float, expected_request_revision: int) -> Dictionary:
	var plot_id := str(state.get("plot_id", ""))
	var cells: Dictionary = state.get("cells", {})
	if plot_id.is_empty() or not cells.has(cell_key):
		return {}
	var cell: Dictionary = (cells[cell_key] as Dictionary).duplicate(true)
	if action != _action_for_status(str(cell.get("state", ""))):
		return {}
	if str(cell.get("requested_operation", "")) != action:
		return {}
	if expected_request_revision >= 0 and int(cell.get("request_revision", 0)) != expected_request_revision:
		return {}
	var crop_id := str(cell.get("requested_crop_id", "")) if action == "plant" else str(cell.get("crop_id", ""))
	if crop_id.is_empty() and action == "till":
		crop_id = "tomato"
	var crop := get_crop(crop_id)
	if crop == null:
		return {}
	var required := _seconds_for_action(crop, action)
	var progress := minf(required, float(cell.get("work_progress", 0.0)) + maxf(0.0, seconds))
	cell["work_progress"] = progress
	var result := {"completed": false, "plot_id": plot_id, "cell_key": cell_key, "action": action, "required_seconds": required, "progress_seconds": progress}
	if progress >= required:
		result["completed"] = true
		cell["work_progress"] = 0.0
		match action:
			"till":
				cell = FARM_SIMULATION.complete_tilling(cell, _absolute_minute())
			"plant":
				cell = FARM_SIMULATION.complete_planting(cell, crop_id, crop.water_capacity * 0.2)
			"water":
				cell["water"] = crop.water_capacity
			"harvest":
				var harvest := FARM_SIMULATION.complete_harvest(cell, crop.to_sim_profile(), farming_level, _absolute_minute())
				cell = harvest.get("cell", cell)
				result["yield"] = int(harvest.get("yield", 0))
				result["produce_item"] = crop.produce_item
				result["crop_id"] = crop.crop_id
			"clear":
				cell = FARM_SIMULATION.clear_withered(cell, _absolute_minute())
		cell.erase("requested_operation")
		cell.erase("requested_crop_id")
		cell.erase("requested_actor_ids")
		cell.erase("request_source")
		cell = _with_field_policy_request(cell, _effective_policy_crop_id(state), is_active_field(state))
	cells[cell_key] = cell
	state["cells"] = cells
	return result


func get_expected_harvest_yield(plot_id: String, cell_key: String, farming_level := 0.0) -> int:
	var state := get_plot(plot_id)
	var cells: Dictionary = state.get("cells", {})
	if not cells.has(cell_key):
		return 0
	var cell: Dictionary = cells[cell_key]
	var crop := get_crop(str(cell.get("crop_id", "")))
	if crop == null:
		return 0
	return int(FARM_SIMULATION.complete_harvest(cell, crop.to_sim_profile(), farming_level).get("yield", 0))


func refresh_obstacle(plot_id: String, cell_key: String, blocked: bool, reason := "obstacle") -> Dictionary:
	var state := get_plot(plot_id)
	var cells: Dictionary = state.get("cells", {})
	if not cells.has(cell_key):
		return {}
	var cell: Dictionary = cells[cell_key]
	if blocked:
		cell = FARM_SIMULATION.block_cell(cell, reason)
	elif str(cell.get("state", "")) == FARM_SIMULATION.STATE_BLOCKED:
		cell = FARM_SIMULATION.clear_blockage(cell)
	cells[cell_key] = cell
	state["cells"] = cells
	return _save_plot(state)


func apply_rain(water_amount: float) -> void:
	if water_amount <= 0.0:
		return
	for plot_id in get_plots().keys():
		_advance_plot(str(plot_id), _absolute_minute(), water_amount)


func register_water_source(authored_state: Dictionary) -> Dictionary:
	if _gecs == null:
		return {}
	var source_id := str(authored_state.get("source_id", "")).strip_edges()
	if source_id.is_empty():
		return {}
	var saved := get_water_source(source_id)
	if saved.is_empty():
		saved = _gecs.upsert_farm_water_source_state(authored_state)
	else:
		_advance_water_sources(_absolute_minute())
		saved = get_water_source(source_id)
		if str(saved.get("owner_faction_name", "")).is_empty() and not str(authored_state.get("owner_faction_name", "")).is_empty():
			saved["owner_faction_name"] = str(authored_state.get("owner_faction_name", ""))
			saved = _gecs.upsert_farm_water_source_state(saved)
	water_source_changed.emit(source_id, saved)
	return saved


func get_water_source(source_id: String) -> Dictionary:
	if _gecs == null or source_id.strip_edges().is_empty():
		return {}
	return (_gecs.get_farm_water_source_states().get(source_id, {}) as Dictionary).duplicate(true)


func draw_water_source(source_id: String, requested: float, authorization: Dictionary) -> float:
	var state := get_water_source(source_id)
	var amount := maxf(0.0, requested)
	if state.is_empty() or amount <= 0.0:
		return 0.0
	var owner_faction_name := str(state.get("owner_faction_name", "")).strip_edges()
	if owner_faction_name.is_empty():
		return 0.0
	if str(authorization.get("source_id", "")) != source_id:
		return 0.0
	if str(authorization.get("owner_faction_name", "")) != owner_faction_name:
		return 0.0
	var actor_faction_name := str(authorization.get("actor_faction_name", ""))
	var owner_access_approved := bool(authorization.get("owner_access_approved", false))
	var theft_approved := bool(authorization.get("theft_approved", false))
	if actor_faction_name != owner_faction_name and not owner_access_approved and not theft_approved:
		return 0.0
	if bool(state.get("renewable", false)):
		return amount
	var drawn := minf(amount, maxf(0.0, float(state.get("current_water", 0.0))))
	if drawn <= 0.0:
		return 0.0
	state["current_water"] = float(state.get("current_water", 0.0)) - drawn
	var saved: Dictionary = _gecs.upsert_farm_water_source_state(state)
	water_source_changed.emit(source_id, saved)
	return drawn


func _on_minute_changed(absolute_minute: int, _day: int, _hour: int, _minute: int) -> void:
	for plot_id in get_plots().keys():
		_advance_plot(str(plot_id), absolute_minute)
	_advance_water_sources(absolute_minute)


func _advance_plot(plot_id: String, target_minute: int, rain_water := 0.0) -> void:
	var state := get_plot(plot_id)
	if state.is_empty():
		return
	state = _reconcile_deleted_requests(state)
	var from_minute := int(state.get("last_simulated_minute", target_minute))
	var elapsed := maxf(0.0, float(target_minute - from_minute))
	if elapsed <= 0.0 and rain_water <= 0.0:
		return
	var cells: Dictionary = state.get("cells", {})
	# "auto" counts as HAVING a policy for soil recovery: a managed field that
	# has simply run out of seed does not quietly revert to wild ground.
	var no_crop_policy := str(state.get("crop_policy_id", "")).is_empty()
	# Both of these are plot-wide facts. Resolving them per cell is what makes
	# this loop quadratic on big fields.
	var policy_crop_id := _effective_policy_crop_id(state)
	var field_active := is_active_field(state)
	var changed_cells: Dictionary = {}
	for key in cells.keys():
		var cell: Dictionary = cells[key]
		var previous_signature := _cell_delta_signature(cell)
		var crop := get_crop(str(cell.get("crop_id", "")))
		if crop != null:
			if elapsed > 0.0:
				cell = FARM_SIMULATION.advance_cell(cell, crop.to_sim_profile(), elapsed)
			if rain_water > 0.0:
				cell = FARM_SIMULATION.apply_rain(cell, rain_water, crop.water_capacity)
		var recovery_eligible := no_crop_policy \
			and str(cell.get("state", "")) == FARM_SIMULATION.STATE_TILLED \
			and str(cell.get("crop_id", "")).is_empty() \
			and str(cell.get("requested_operation", "")).is_empty()
		cell = FARM_SIMULATION.advance_soil_recovery(cell, from_minute, target_minute, recovery_eligible, SOIL_RECOVERY_MINUTES)
		cell = _with_field_policy_request(cell, policy_crop_id, field_active)
		cells[key] = cell
		if _cell_delta_signature(cell) != previous_signature:
			changed_cells[str(key)] = cell.duplicate(true)
	state["cells"] = cells
	var remnants: Dictionary = state.get("soil_remnants", {})
	var initial_remnant_count := remnants.size()
	for remnant_key in remnants.keys().duplicate():
		var remnant: Dictionary = remnants[remnant_key]
		remnant = FARM_SIMULATION.advance_soil_recovery(remnant, from_minute, target_minute, true, SOIL_RECOVERY_MINUTES)
		if bool(remnant.get("soil_created", false)):
			remnants[remnant_key] = remnant
		else:
			remnants.erase(remnant_key)
	state["soil_remnants"] = remnants
	state["last_simulated_minute"] = target_minute
	var initial_cell_count := cells.size()
	if bool(state.get("field_deleted", false)):
		for key in cells.keys().duplicate():
			var remnant_cell: Dictionary = cells[key]
			if not bool(remnant_cell.get("soil_created", false)) \
					and str(remnant_cell.get("crop_id", "")).is_empty() \
					and str(remnant_cell.get("requested_operation", "")).is_empty():
				cells.erase(key)
		state["cells"] = cells
		if cells.is_empty() and remnants.is_empty():
			remove_plot(plot_id)
			return
	var saved := _save_plot(state, false)
	if cells.size() != initial_cell_count or remnants.size() != initial_remnant_count:
		plot_changed.emit(plot_id, saved)
	elif not changed_cells.is_empty():
		plot_cells_changed.emit(plot_id, changed_cells, str(saved.get("settlement_id", "")))


func _cell_delta_signature(cell: Dictionary) -> String:
	return "%s|%s|%d|%s|%s|%s|%d" % [
		str(cell.get("state", "")),
		str(cell.get("crop_id", "")),
		int(cell.get("stage_index", 0)),
		str(cell.get("soil_created", false)),
		str(cell.get("requested_operation", "")),
		str(cell.get("requested_crop_id", "")),
		int(cell.get("request_revision", 0)),
	]


func _work_record(state: Dictionary, key: String, cell: Dictionary, action: String) -> Dictionary:
	var crop_id := str(cell.get("requested_crop_id", "")) if action == "plant" else str(cell.get("crop_id", ""))
	if crop_id.is_empty() and action == "till":
		crop_id = "tomato"
	var crop := get_crop(crop_id)
	return {
		"plot_id": str(state.get("plot_id", "")), "cell_key": key, "action": action,
		"settlement_id": str(state.get("settlement_id", "")), "owner_faction_id": str(state.get("owner_faction_id", "")),
		"world_position": cell.get("world_position", Vector3.ZERO), "crop_id": crop_id,
		"required_tool_tag": _required_tool(crop, action), "required_tool_label": _required_tool_label(crop, action),
		"required_seconds": _seconds_for_action(crop, action), "progress_seconds": float(cell.get("work_progress", 0.0)),
		"seed_item": crop.seed_item if crop != null and action == "plant" else null,
		"produce_item": crop.produce_item if crop != null and action == "harvest" else null,
		"allowed_actor_ids": PackedStringArray(cell.get("requested_actor_ids", PackedStringArray())).duplicate(),
		"request_revision": int(cell.get("request_revision", 0)),
	}


func _with_field_policy_request(cell: Dictionary, crop_policy_id: String, field_active := true) -> Dictionary:
	var next := cell.duplicate(true)
	if not field_active:
		if str(next.get("request_source", "")) == "field_policy":
			next.erase("requested_operation")
			next.erase("requested_crop_id")
			next.erase("requested_actor_ids")
			next.erase("request_source")
		return next
	var desired_action := ""
	var desired_crop_id := ""
	match str(next.get("state", "")):
		FARM_SIMULATION.STATE_UNTILLED:
			if not crop_policy_id.is_empty():
				desired_action = "till"
		FARM_SIMULATION.STATE_TILLED:
			if not crop_policy_id.is_empty():
				desired_action = "plant"
				desired_crop_id = crop_policy_id
		FARM_SIMULATION.STATE_GROWING:
			if float(next.get("water", 0.0)) < _watering_threshold(next):
				desired_action = "water"
		FARM_SIMULATION.STATE_RIPE:
			desired_action = "harvest"
		FARM_SIMULATION.STATE_WITHERED:
			desired_action = "clear"
	var current_action := str(next.get("requested_operation", ""))
	var current_source := str(next.get("request_source", ""))
	if not current_action.is_empty() and current_source != "field_policy":
		return next
	if desired_action.is_empty():
		if current_source == "field_policy":
			next.erase("requested_operation")
			next.erase("requested_crop_id")
			next.erase("requested_actor_ids")
			next.erase("request_source")
		return next
	if current_action == desired_action \
			and (desired_action != "plant" or str(next.get("requested_crop_id", "")) == desired_crop_id):
		return next
	next["requested_operation"] = desired_action
	next["requested_crop_id"] = desired_crop_id if desired_action == "plant" else str(next.get("crop_id", ""))
	next["requested_actor_ids"] = PackedStringArray()
	next["request_source"] = "field_policy"
	next["request_revision"] = int(next.get("request_revision", 0)) + 1
	return next


func _required_tool(crop: CropDefinition, action: String) -> String:
	if action == "till": return "tool.hoe"
	if action == "water": return "tool.water_container"
	if action == "harvest" and crop != null: return crop.required_harvest_tool_tag
	return ""


func _required_tool_label(crop: CropDefinition, action: String) -> String:
	if action == "till": return "hoe"
	if action == "water": return "bucket or watering can"
	if action == "harvest" and crop != null: return crop.required_harvest_tool_label
	return ""


func _seconds_for_action(crop: CropDefinition, action: String) -> float:
	if crop == null: return 1.0
	match action:
		"till": return crop.till_seconds
		"plant": return crop.plant_seconds
		"water": return crop.water_seconds
		"harvest": return crop.harvest_seconds
		"clear": return crop.clear_seconds
	return 1.0


func _action_for_status(status: String) -> String:
	match status:
		FARM_SIMULATION.STATE_UNTILLED: return "till"
		FARM_SIMULATION.STATE_TILLED: return "plant"
		FARM_SIMULATION.STATE_GROWING: return "water"
		FARM_SIMULATION.STATE_RIPE: return "harvest"
		FARM_SIMULATION.STATE_WITHERED: return "clear"
	return ""


func _watering_threshold(cell: Dictionary) -> float:
	var crop := get_crop(str(cell.get("crop_id", "")))
	return crop.water_capacity * 0.45 if crop != null else 1.0


func _save_plot(state: Dictionary, emit_changed := true) -> Dictionary:
	state["state_revision"] = int(state.get("state_revision", 0)) + 1
	var saved: Dictionary = _gecs.upsert_farm_plot_state(state) if _gecs != null else state
	if emit_changed:
		plot_changed.emit(str(saved.get("plot_id", "")), saved)
	return saved


func _absolute_minute() -> int:
	return _world_time.get_absolute_minute() if _world_time != null else 0


func _reconcile_deleted_requests(state: Dictionary) -> Dictionary:
	if not bool(state.get("field_deleted", false)):
		return state
	var active_keys := PackedStringArray()
	var farm_work = _context.get_optional(&"farm_work") if _context != null else null
	if farm_work != null and farm_work.has_method("get_active_cell_keys_for_plot"):
		active_keys = PackedStringArray(farm_work.call("get_active_cell_keys_for_plot", str(state.get("plot_id", ""))))
	var cells: Dictionary = state.get("cells", {}).duplicate(true)
	var changed := false
	for key_value in cells.keys():
		var key := str(key_value)
		var cell: Dictionary = (cells[key_value] as Dictionary).duplicate(true)
		if active_keys.has(key) or str(cell.get("requested_operation", "")).is_empty():
			continue
		cell.erase("requested_operation")
		cell.erase("requested_crop_id")
		cell.erase("requested_actor_ids")
		cell.erase("request_source")
		cell["work_progress"] = 0.0
		cell["claimed_by"] = ""
		cell["request_revision"] = int(cell.get("request_revision", 0)) + 1
		cells[key] = cell
		changed = true
	if not changed:
		return state
	state["cells"] = cells
	return _save_plot(state)


func _on_world_reindexed() -> void:
	if _world_reindex_pending:
		return
	_world_reindex_pending = true
	call_deferred("_reconcile_after_world_reindex")


func _reconcile_after_world_reindex() -> void:
	_world_reindex_pending = false
	_recover_sequence()
	var target_minute := _absolute_minute()
	for plot_id in get_plots().keys():
		var state := get_plot(str(plot_id))
		state = _reconcile_deleted_requests(state)
		if target_minute > int(state.get("last_simulated_minute", target_minute)):
			_advance_plot(str(plot_id), target_minute)
		else:
			plot_changed.emit(str(plot_id), state)
	_advance_water_sources(target_minute)


func _advance_water_sources(target_minute: int) -> void:
	if _gecs == null or not _gecs.has_method("get_farm_water_source_states"):
		return
	for state_value in _gecs.get_farm_water_source_states().values():
		var state: Dictionary = state_value
		var last_minute := int(state.get("last_processed_minute", target_minute))
		var elapsed := maxi(0, target_minute - last_minute)
		if elapsed <= 0:
			water_source_changed.emit(str(state.get("source_id", "")), state)
			continue
		if not bool(state.get("renewable", false)):
			var capacity := maxf(0.0, float(state.get("capacity", 0.0)))
			var recharge_per_minute := maxf(0.0, float(state.get("recharge_per_world_minute", float(state.get("recharge_per_world_hour", 0.0)) / 60.0)))
			state["current_water"] = minf(capacity, maxf(0.0, float(state.get("current_water", 0.0))) + recharge_per_minute * float(elapsed))
		state["last_processed_minute"] = target_minute
		var saved: Dictionary = _gecs.upsert_farm_water_source_state(state)
		water_source_changed.emit(str(saved.get("source_id", "")), saved)


func _recover_sequence() -> void:
	_next_plot_sequence = 1
	for plot_id in get_plots().keys() if _gecs != null else []:
		if str(plot_id).begins_with("farm:"):
			_next_plot_sequence = maxi(_next_plot_sequence, int(str(plot_id).trim_prefix("farm:")) + 1)
