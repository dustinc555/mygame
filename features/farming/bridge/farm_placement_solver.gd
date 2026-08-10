class_name FarmPlacementSolver
extends RefCounted

const BUILDING_SOLVER := preload("res://features/settlements/bridge/building_placement_solver.gd")
const MAX_SLOPE_DEG := BUILDING_SOLVER.MAX_SLOPE_DEG
const RAY_HEIGHT := 40.0
const RAY_RETRIES := 12
const MAX_DIMENSION := 24
const MAX_CELL_COUNT := 256


static func build_grid(anchor: Vector3, drag_end: Vector3, cell_size := 1.25) -> Dictionary:
	var spacing := maxf(0.25, cell_size)
	var dimensions := Vector2i(
		clampi(int(floor(absf(drag_end.x - anchor.x) / spacing)) + 1, 1, MAX_DIMENSION),
		clampi(int(floor(absf(drag_end.z - anchor.z) / spacing)) + 1, 1, MAX_DIMENSION)
	)
	while dimensions.x * dimensions.y > MAX_CELL_COUNT:
		if dimensions.x >= dimensions.y and dimensions.x > 1:
			dimensions.x -= 1
		elif dimensions.y > 1:
			dimensions.y -= 1
		else:
			break
	var minimum := anchor
	if drag_end.x < anchor.x:
		minimum.x -= float(dimensions.x - 1) * spacing
	if drag_end.z < anchor.z:
		minimum.z -= float(dimensions.y - 1) * spacing
	var positions: Array[Vector3] = []
	for z in dimensions.y:
		for x in dimensions.x:
			positions.append(minimum + Vector3(float(x) * spacing, 0.0, float(z) * spacing))
	return {"dimensions": dimensions, "positions": positions, "origin": minimum, "cell_size": spacing}


static func raster_line(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x := from_cell.x
	var y := from_cell.y
	var dx := absi(to_cell.x - from_cell.x)
	var dy := -absi(to_cell.y - from_cell.y)
	var step_x := 1 if from_cell.x < to_cell.x else -1
	var step_y := 1 if from_cell.y < to_cell.y else -1
	var error := dx + dy
	while true:
		cells.append(Vector2i(x, y))
		if x == to_cell.x and y == to_cell.y:
			break
		var doubled := error * 2
		if doubled >= dy:
			error += dy
			x += step_x
		if doubled <= dx:
			error += dx
			y += step_y
	return cells


static func build_painted_grid(anchor: Vector3, painted_cells: Array, cell_size := 1.25) -> Dictionary:
	if painted_cells.is_empty():
		return {}
	var spacing := maxf(0.25, cell_size)
	var unique: Dictionary = {}
	for value in painted_cells:
		var cell := value as Vector2i
		unique["%d:%d" % [cell.x, cell.y]] = cell
	var ordered: Array[Vector2i] = []
	for value in unique.values():
		ordered.append(value as Vector2i)
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	if ordered.size() > MAX_CELL_COUNT:
		ordered.resize(MAX_CELL_COUNT)
	var minimum := ordered[0]
	var maximum := ordered[0]
	for cell in ordered:
		minimum = minimum.min(cell)
		maximum = maximum.max(cell)
	var dimensions := maximum - minimum + Vector2i.ONE
	if dimensions.x > MAX_DIMENSION or dimensions.y > MAX_DIMENSION:
		return {}
	var origin := anchor + Vector3(float(minimum.x) * spacing, 0.0, float(minimum.y) * spacing)
	var positions: Array[Vector3] = []
	var cell_keys := PackedStringArray()
	for cell in ordered:
		var normalized := cell - minimum
		positions.append(origin + Vector3(float(normalized.x) * spacing, 0.0, float(normalized.y) * spacing))
		cell_keys.append("%d:%d" % [normalized.x, normalized.y])
	return {
		"dimensions": dimensions,
		"positions": positions,
		"cell_keys": cell_keys,
		"origin": origin,
		"cell_size": spacing,
	}


static func validate_samples(samples: Array, max_slope_degrees := MAX_SLOPE_DEG) -> Dictionary:
	var blocked: Dictionary = {}
	var projected: Array[Vector3] = []
	var terrain_cells := 0
	var valid_unblocked_cells := 0
	for index in samples.size():
		var sample: Dictionary = samples[index]
		var grid: Vector2i = sample.get("grid_position", Vector2i(index, 0))
		var key := "%d:%d" % [grid.x, grid.y]
		var position: Vector3 = sample.get("position", Vector3.ZERO)
		projected.append(position)
		if not bool(sample.get("has_ground", true)):
			blocked[key] = "no ground"
			continue
		var normal: Vector3 = sample.get("normal", Vector3.UP)
		if normal.angle_to(Vector3.UP) > deg_to_rad(max_slope_degrees):
			blocked[key] = "slope too steep"
			continue
		terrain_cells += 1
		var reason := str(sample.get("blocked_reason", ""))
		if not reason.is_empty():
			blocked[key] = reason
		else:
			valid_unblocked_cells += 1
	return {
		"valid": terrain_cells > 0 and valid_unblocked_cells > 0,
		"positions": projected,
		"blocked_cells": blocked,
		"valid_cell_count": valid_unblocked_cells,
		"terrain_cell_count": terrain_cells,
	}


static func sample_grid(space: PhysicsDirectSpaceState3D, grid: Dictionary) -> Dictionary:
	var dimensions: Vector2i = grid.get("dimensions", Vector2i.ONE)
	var positions: Array = grid.get("positions", [])
	var cell_keys := PackedStringArray(grid.get("cell_keys", PackedStringArray()))
	var ignore_groups: PackedStringArray = grid.get("ignore_groups", PackedStringArray())
	var ignore_characters := bool(grid.get("ignore_characters", false))
	var cell_size := float(grid.get("cell_size", 1.25))
	var samples: Array = []
	for index in positions.size():
		var raw: Vector3 = positions[index]
		var ray := _ground_ray(space, raw, ignore_groups)
		var grid_position := _grid_position_from_key(cell_keys[index]) if index < cell_keys.size() else Vector2i(index % dimensions.x, index / dimensions.x)
		if ray.is_empty():
			samples.append({"grid_position": grid_position, "position": raw, "has_ground": false, "normal": Vector3.UP, "blocked_reason": "no ground"})
			continue
		var ground: Vector3 = ray.get("position", raw)
		var reason := _obstacle_reason(space, ground, ray.get("rid", RID()), ignore_groups, ignore_characters, cell_size)
		samples.append({"grid_position": grid_position, "position": ground, "has_ground": true, "normal": ray.get("normal", Vector3.UP), "blocked_reason": reason})
	var result := validate_samples(samples, MAX_SLOPE_DEG)
	result["dimensions"] = dimensions
	result["cell_size"] = cell_size
	result["cell_keys"] = cell_keys
	result["samples"] = samples
	return result


static func _ground_ray(space: PhysicsDirectSpaceState3D, position: Vector3, ignore_groups := PackedStringArray()) -> Dictionary:
	var from := position + Vector3.UP * RAY_HEIGHT
	var to := position - Vector3.UP * RAY_HEIGHT
	var excluded: Array[RID] = []
	for _attempt in RAY_RETRIES:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = excluded
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		if _collider_in_any_group(hit.get("collider"), ignore_groups):
			var ignored_rid: RID = hit.get("rid", RID())
			if not ignored_rid.is_valid():
				return {}
			excluded.append(ignored_rid)
			continue
		if _is_ground_collider(hit.get("collider")):
			return hit
		var rid: RID = hit.get("rid", RID())
		if not rid.is_valid():
			return {}
		excluded.append(rid)
	return {}


static func _is_ground_collider(collider) -> bool:
	if collider == null:
		return true
	var node := collider as Node
	while node != null:
		if node.is_in_group("terrain") or node.is_in_group("farmable_ground"):
			return true
		if node is CharacterBody3D or node.is_in_group("world_building") or node.is_in_group("farm_obstacle") or node.is_in_group("deep_water"):
			return false
		node = node.get_parent()
	return false


static func _obstacle_reason(space: PhysicsDirectSpaceState3D, ground: Vector3, ground_rid: RID, ignore_groups := PackedStringArray(), ignore_characters := false, cell_size := 1.25) -> String:
	var shape := BoxShape3D.new()
	var footprint := maxf(0.2, cell_size * 0.92)
	shape.size = Vector3(footprint, 1.2, footprint)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 0.55)
	query.collide_with_areas = true
	if ground_rid.is_valid():
		query.exclude = [ground_rid]
	for hit in space.intersect_shape(query, 12):
		var collider = hit.get("collider")
		if collider == null:
			continue
		if _collider_in_any_group(collider, ignore_groups):
			continue
		if ignore_characters and _collider_is_character(collider):
			continue
		var reason := obstacle_reason_for_collider(collider)
		if not reason.is_empty():
			return reason
	return ""


static func obstacle_reason_for_collider(collider) -> String:
	var node := collider as Node
	while node != null:
		if node.is_in_group("terrain") or node.is_in_group("farmable_ground"):
			return ""
		if node.is_in_group("world_item") or node.is_in_group("farm_placement_ignore"):
			return ""
		if node is CharacterBody3D:
			return ""
		if node.is_in_group("deep_water"):
			return "deep water"
		if node.is_in_group("farm_plot"):
			return "occupied" if not node.has_method("blocks_farm_placement") \
					or bool(node.call("blocks_farm_placement")) else ""
		if node.is_in_group("world_building") or node.is_in_group("farm_obstacle"):
			return "occupied"
		if node is StaticBody3D or node is AnimatableBody3D:
			return "occupied"
		node = node.get_parent()
	return ""


static func _grid_position_from_key(key: String) -> Vector2i:
	var parts := key.split(":", false, 1)
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


static func _collider_in_any_group(collider, groups: PackedStringArray) -> bool:
	if groups.is_empty():
		return false
	var node := collider as Node
	while node != null:
		for group_name in groups:
			if node.is_in_group(group_name):
				return true
		node = node.get_parent()
	return false


static func _collider_is_character(collider) -> bool:
	var node := collider as Node
	while node != null:
		if node is CharacterBody3D:
			return true
		node = node.get_parent()
	return false
