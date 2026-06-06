extends RefCounted

class_name WorldMapProjection


static func world_to_map(world_position: Vector3, world_bounds: Rect2, map_rect: Rect2) -> Vector2:
	var normalized := Vector2(
		_safe_ratio(world_position.x - world_bounds.position.x, world_bounds.size.x),
		_safe_ratio(world_position.z - world_bounds.position.y, world_bounds.size.y)
	)
	return map_rect.position + normalized * map_rect.size


static func map_to_world(map_position: Vector2, world_bounds: Rect2, map_rect: Rect2, y := 0.0) -> Vector3:
	var normalized := Vector2(
		_safe_ratio(map_position.x - map_rect.position.x, map_rect.size.x),
		_safe_ratio(map_position.y - map_rect.position.y, map_rect.size.y)
	)
	return Vector3(
		world_bounds.position.x + normalized.x * world_bounds.size.x,
		y,
		world_bounds.position.y + normalized.y * world_bounds.size.y
	)


static func _safe_ratio(value: float, divisor: float) -> float:
	if is_zero_approx(divisor):
		return 0.0
	return value / divisor
