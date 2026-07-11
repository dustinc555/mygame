extends StaticBody3D

class_name SleepableBed

@export var furniture_type := FurnitureRules.Type.BED
@export var interaction_clearance := 0.7
@export var sleep_arrival_distance := 1.25
@export var sleep_vertical_tolerance := 1.25
# The broad upward-facing mattress cloth on every twin-bed variant is at
# 0.515m. The model AABB top is the headboard and must not place the sleeper.
@export var sleep_local_offset := Vector3(0.0, 0.515, 0.1)
# The lying pose comes from the IdleToLay animation; the actor body stays
# upright (roll 0). The clip lays the head out toward actor +Z, so yaw
# offset 180 puts the head on the pillow for beds authored pillow at -Z.
@export var sleep_roll_degrees := 0.0
@export var sleep_yaw_offset_degrees := 180.0
@export var recovery_multiplier := 8.0

var _sleeper: HumanoidCharacter
var _bar_service_area: BarServiceArea
var _bed_half_extents := Vector2(0.95, 1.225)


func _ready() -> void:
	add_to_group("sleepable_bed")
	add_to_group(FurnitureRules.FURNITURE_GROUP)
	_cache_bed_half_extents()


func get_interaction_position(member: HumanoidCharacter) -> Vector3:
	var member_position := member.global_position if member != null else global_position
	var local_member := global_transform.affine_inverse() * member_position
	var outer_x := _bed_half_extents.x + interaction_clearance
	var outer_z := _bed_half_extents.y + interaction_clearance
	var candidates: Array[Vector3] = [
		Vector3(-outer_x, 0.0, clampf(local_member.z, -_bed_half_extents.y, _bed_half_extents.y)),
		Vector3(outer_x, 0.0, clampf(local_member.z, -_bed_half_extents.y, _bed_half_extents.y)),
		Vector3(clampf(local_member.x, -_bed_half_extents.x, _bed_half_extents.x), 0.0, -outer_z),
		Vector3(clampf(local_member.x, -_bed_half_extents.x, _bed_half_extents.x), 0.0, outer_z),
	]
	var best_position := global_transform * candidates[0]
	var best_score := INF
	var fallback_position := best_position
	var fallback_score := INF
	var world := get_world_3d() if is_inside_tree() else null
	var navigation_map := world.navigation_map if world != null else RID()
	var has_navigation := navigation_map.is_valid() and NavigationServer3D.map_get_iteration_id(navigation_map) > 0
	for local_candidate in candidates:
		var candidate := global_transform * local_candidate
		var score := member_position.distance_to(candidate)
		if has_navigation:
			candidate = NavigationServer3D.map_get_closest_point(navigation_map, candidate)
			var projected_score := member_position.distance_to(candidate)
			if projected_score < fallback_score:
				fallback_score = projected_score
				fallback_position = candidate
			var path := NavigationServer3D.map_get_path(navigation_map, member_position, candidate, true)
			if path.is_empty():
				continue
			score = 0.0
			for index in range(1, path.size()):
				score += path[index - 1].distance_to(path[index])
		if score < best_score:
			best_score = score
			best_position = candidate
	return fallback_position if best_score == INF else best_position


func can_sleep_from_position(world_position: Vector3) -> bool:
	var local_position := global_transform.affine_inverse() * world_position
	if absf(local_position.y) > sleep_vertical_tolerance:
		return false
	var outside_x := maxf(absf(local_position.x) - _bed_half_extents.x, 0.0)
	var outside_z := maxf(absf(local_position.z) - _bed_half_extents.y, 0.0)
	return Vector2(outside_x, outside_z).length() <= sleep_arrival_distance


func get_sleep_position(member: WorldActor = null) -> Vector3:
	var mattress_position := global_transform * sleep_local_offset
	if member != null:
		return member.get_floor_aligned_origin_position(mattress_position)
	return mattress_position


func _cache_bed_half_extents() -> void:
	for child in get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape == null or not (collision_shape.shape is BoxShape3D):
			continue
		var size := (collision_shape.shape as BoxShape3D).size
		_bed_half_extents = Vector2(size.x, size.z) * 0.5
		return


func get_sleep_rotation() -> Vector3:
	return Vector3(0.0, global_rotation.y + deg_to_rad(sleep_yaw_offset_degrees), deg_to_rad(sleep_roll_degrees))


func get_recovery_multiplier() -> float:
	return maxf(1.0, recovery_multiplier)


func set_bar_service_area(service_area: BarServiceArea) -> void:
	_bar_service_area = service_area


func request_sleep(member: HumanoidCharacter) -> Dictionary:
	if is_occupied() and _sleeper != member:
		return {"allowed": false, "message": "Bed occupied"}
	var service_area := _resolve_bar_service_area()
	if service_area == null:
		return {"allowed": true, "message": ""}
	return service_area.request_bed_sleep(member, self)


func claim_sleeper(member: HumanoidCharacter) -> bool:
	if member == null:
		return false
	if _sleeper != null and is_instance_valid(_sleeper) and _sleeper != member:
		return false
	_sleeper = member
	return true


func release_sleeper(member: HumanoidCharacter) -> void:
	if _sleeper == member:
		_sleeper = null


func is_occupied() -> bool:
	return _sleeper != null and is_instance_valid(_sleeper)


func get_sleeper() -> HumanoidCharacter:
	return _sleeper if is_occupied() else null


func _resolve_bar_service_area() -> BarServiceArea:
	if _bar_service_area != null and is_instance_valid(_bar_service_area):
		return _bar_service_area
	var node: Node = get_parent()
	while node != null:
		if node is BarServiceArea:
			_bar_service_area = node
			return _bar_service_area
		node = node.get_parent()
	return null
