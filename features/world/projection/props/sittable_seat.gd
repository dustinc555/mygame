@tool
extends StaticBody3D

class_name SittableSeat

@export var furniture_type := FurnitureRules.Type.SEAT
@export var facility_role_ids: Array[String] = []
@export var interaction_local_offset := Vector3(0.0, 0.0, 0.9)
@export var service_local_offset := Vector3(0.0, 0.0, -1.15)
@export var seated_floor_local_offset := Vector3.ZERO
@export var seated_yaw_offset_degrees := 180.0
@export var stand_local_offset := Vector3(0.0, 0.0, 0.65)
@export var sit_arrival_distance := 0.65

const EXIT_SEARCH_RADII := [0.8, 1.1, 1.4, 1.8, 2.3, 2.9]
const EXIT_SEARCH_ANGLES_DEGREES := [90.0, -90.0, 60.0, -60.0, 120.0, -120.0, 30.0, -30.0, 150.0, -150.0, 180.0, 0.0]
const EXIT_FLOOR_PROBE_UP := 0.35
const EXIT_FLOOR_PROBE_DOWN := 0.8
const EXIT_MAX_NAV_SNAP_DISTANCE := 0.65
const EXIT_CLEARANCE_LIFT := 0.08

var _sitter: HumanoidCharacter
var _bar_service_area: BarServiceArea
var _seated_since_seconds := 0.0
var _service_wait_started_seconds := 0.0
var _service_requested := false


func _ready() -> void:
	add_to_group("sittable_seat")
	add_to_group(FurnitureRules.FURNITURE_GROUP)


func get_interaction_position(_member: HumanoidCharacter) -> Vector3:
	return global_transform * interaction_local_offset


func supports_facility_role(role_id: String) -> bool:
	var normalized := role_id.strip_edges().to_lower()
	for candidate in facility_role_ids:
		if candidate.strip_edges().to_lower() == normalized:
			return true
	return false


func get_service_position(_member: HumanoidCharacter) -> Vector3:
	return global_transform * service_local_offset


func get_seat_position(member: HumanoidCharacter = null) -> Vector3:
	var seated_floor_position := global_transform * seated_floor_local_offset
	if member != null:
		return member.get_floor_aligned_origin_position(seated_floor_position)
	return seated_floor_position


func get_seat_rotation(_member: HumanoidCharacter = null) -> Vector3:
	return Vector3(0.0, global_rotation.y + deg_to_rad(seated_yaw_offset_degrees), 0.0)


func get_stand_position() -> Vector3:
	return global_transform * stand_local_offset


## Resolves a nearby floor point that can hold the actor's real collision shape.
## Authored offsets define the preferred aisle direction; physics and navigation
## decide where the actor can actually finish standing when furniture moved.
func get_safe_stand_position(member: HumanoidCharacter, preferred_position := Vector3.INF) -> Vector3:
	if member == null or not is_instance_valid(member) or not is_inside_tree():
		return get_stand_position()
	var candidates: Array[Vector3] = []
	if preferred_position is Vector3 and (preferred_position as Vector3).is_finite():
		candidates.append(preferred_position)
	var world := get_world_3d()
	var nearest_nav_exit := Vector3.INF
	if world != null:
		var nav_map: RID = world.navigation_map
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0 and not NavigationServer3D.map_get_regions(nav_map).is_empty():
			nearest_nav_exit = NavigationServer3D.map_get_closest_point(nav_map, global_position)
			var nav_exit_distance := Vector2(nearest_nav_exit.x - global_position.x, nearest_nav_exit.z - global_position.z).length()
			if nearest_nav_exit.is_finite() and nav_exit_distance <= 3.0:
				candidates.append(nearest_nav_exit)
	candidates.append(get_stand_position())
	candidates.append(get_interaction_position(member))
	var aisle_direction := Vector3(stand_local_offset.x, 0.0, stand_local_offset.z)
	if aisle_direction.length_squared() < 0.01:
		aisle_direction = Vector3(0.0, 0.0, 1.0)
	else:
		aisle_direction = aisle_direction.normalized()
	for radius_value in EXIT_SEARCH_RADII:
		var radius := float(radius_value)
		for angle_value in EXIT_SEARCH_ANGLES_DEGREES:
			var angle_degrees := float(angle_value)
			var local_direction: Vector3 = aisle_direction.rotated(Vector3.UP, deg_to_rad(angle_degrees))
			var local_candidate: Vector3 = local_direction * radius
			local_candidate.y = stand_local_offset.y
			candidates.append(global_transform * local_candidate)
	for candidate in candidates:
		var floor_position := _resolve_exit_floor(member, candidate)
		if not floor_position.is_finite():
			continue
		var actor_origin := member.get_floor_aligned_origin_position(floor_position)
		if _actor_has_clearance(member, actor_origin) and _anchor_has_connected_nav(member, actor_origin):
			return actor_origin
	# Never fall back onto the raw authored point: that is precisely how actors
	# ended up on tables when an indoor navmesh could not resolve the offset.
	return Vector3.INF


func _anchor_has_connected_nav(member: HumanoidCharacter, actor_origin: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var nav_map: RID = world.navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0 or NavigationServer3D.map_get_regions(nav_map).is_empty():
		return true
	var anchor_nav := NavigationServer3D.map_get_closest_point(nav_map, actor_origin)
	if Vector2(anchor_nav.x - actor_origin.x, anchor_nav.z - actor_origin.z).length() > EXIT_MAX_NAV_SNAP_DISTANCE:
		return false
	var door_targets := _door_navigation_targets()
	if not door_targets.is_empty():
		for target_position in door_targets:
			var door_nav := NavigationServer3D.map_get_closest_point(nav_map, target_position)
			var door_path := NavigationServer3D.map_get_path(nav_map, anchor_nav, door_nav, true)
			if not door_path.is_empty() and door_path[door_path.size() - 1].distance_to(door_nav) <= 0.35 \
					and _nav_path_has_actor_clearance(member, door_path):
				return true
		return false
	for direction_value in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var local_direction: Vector3 = direction_value
		var distant_probe: Vector3 = global_position + global_basis * (local_direction * 3.5)
		var distant_nav := NavigationServer3D.map_get_closest_point(nav_map, distant_probe)
		if Vector2(distant_nav.x - anchor_nav.x, distant_nav.z - anchor_nav.z).length() < 1.5:
			continue
		var path := NavigationServer3D.map_get_path(nav_map, anchor_nav, distant_nav, true)
		if not path.is_empty() and path[path.size() - 1].distance_to(distant_nav) <= 0.35 \
				and _nav_path_has_actor_clearance(member, path):
			return true
	return false


func _door_navigation_targets() -> Array[Vector3]:
	var node: Node = self
	while node != null:
		var building := node.get_node_or_null("BuildingSlot/CurrentBuilding")
		if building != null:
			var targets: Array[Vector3] = []
			for candidate in building.find_children("*", "Node", true, false):
				if candidate.has_method("get_interaction_positions"):
					for position in candidate.call("get_interaction_positions"):
						if position is Vector3:
							targets.append(position)
			return targets
		node = node.get_parent()
	return []


func _nav_path_has_actor_clearance(member: HumanoidCharacter, path: PackedVector3Array) -> bool:
	for index in range(1, path.size()):
		var start := path[index - 1]
		var finish := path[index]
		var steps := maxi(1, int(ceilf(start.distance_to(finish) / 0.3)))
		for step in range(steps + 1):
			var floor_position := start.lerp(finish, float(step) / float(steps))
			var actor_origin := member.get_floor_aligned_origin_position(floor_position)
			if not _actor_has_clearance(member, actor_origin):
				return false
	return true


func _resolve_exit_floor(member: HumanoidCharacter, candidate: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return Vector3.INF
	var floor_hint := candidate
	var nav_map: RID = world.navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0 and not NavigationServer3D.map_get_regions(nav_map).is_empty():
		var nav_position := NavigationServer3D.map_get_closest_point(nav_map, candidate)
		var nav_flat_delta := Vector2(nav_position.x - candidate.x, nav_position.z - candidate.z)
		if nav_flat_delta.length() <= EXIT_MAX_NAV_SNAP_DISTANCE and absf(nav_position.y - candidate.y) <= 0.8:
			var nav_start := NavigationServer3D.map_get_closest_point(nav_map, get_interaction_position(member))
			var exit_path := NavigationServer3D.map_get_path(nav_map, nav_start, nav_position, true)
			if not exit_path.is_empty() and exit_path[exit_path.size() - 1].distance_to(nav_position) <= 0.35:
				floor_hint = nav_position
	var query := PhysicsRayQueryParameters3D.create(
		floor_hint + Vector3.UP * EXIT_FLOOR_PROBE_UP,
		floor_hint - Vector3.UP * EXIT_FLOOR_PROBE_DOWN,
		member.collision_mask
	)
	query.exclude = [member.get_rid()]
	query.hit_from_inside = true
	query.collide_with_areas = false
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var floor_position: Vector3 = hit.get("position", Vector3.INF)
	if normal.y < 0.65 or not floor_position.is_finite():
		return Vector3.INF
	if absf(floor_position.y - floor_hint.y) > 0.45:
		return Vector3.INF
	return floor_position


func _actor_has_clearance(member: HumanoidCharacter, actor_origin: Vector3) -> bool:
	var collision_shape := member.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var world := get_world_3d()
	if collision_shape == null or collision_shape.shape == null or world == null:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape.shape
	query.transform = Transform3D(member.global_basis.orthonormalized(), actor_origin + Vector3.UP * EXIT_CLEARANCE_LIFT) * collision_shape.transform
	query.collision_mask = member.collision_mask
	query.exclude = [member.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return world.direct_space_state.intersect_shape(query, 1).is_empty()


func get_arrival_distance() -> float:
	return sit_arrival_distance


func can_sit_from_position(world_position: Vector3) -> bool:
	return get_sit_distance_to(world_position) <= sit_arrival_distance


func get_sit_distance_to(world_position: Vector3) -> float:
	var interaction_position := global_transform * interaction_local_offset
	var flat_delta := Vector3(world_position.x - interaction_position.x, 0.0, world_position.z - interaction_position.z)
	return flat_delta.length()


func set_bar_service_area(service_area: BarServiceArea) -> void:
	_bar_service_area = service_area


func get_bar_service_area() -> BarServiceArea:
	return _bar_service_area if _bar_service_area != null and is_instance_valid(_bar_service_area) else null


func claim_sitter(member: HumanoidCharacter) -> bool:
	if member == null:
		return false
	if _sitter != null and is_instance_valid(_sitter) and _sitter != member:
		return false
	if _sitter != member:
		_seated_since_seconds = _now_seconds()
		_service_wait_started_seconds = _seated_since_seconds
		_service_requested = false
	_sitter = member
	return true


func release_sitter(member: HumanoidCharacter) -> void:
	if _sitter == member:
		_sitter = null
		_seated_since_seconds = 0.0
		_service_wait_started_seconds = 0.0
		_service_requested = false


func is_occupied() -> bool:
	return _sitter != null and is_instance_valid(_sitter)


func get_sitter() -> HumanoidCharacter:
	return _sitter if is_occupied() else null


func get_seated_seconds() -> float:
	if not is_occupied():
		return 0.0
	return _now_seconds() - _seated_since_seconds


func is_waiting_for_service(required_seconds: float) -> bool:
	return is_waiting_customer_for_service(required_seconds, true, false)


func is_waiting_customer_for_service(required_seconds: float, include_player_party := true, include_npcs := true) -> bool:
	if not is_occupied() or _service_requested:
		return false
	if _sitter == null:
		return false
	if _sitter.is_player_party_member() and not include_player_party:
		return false
	if not _sitter.is_player_party_member() and not include_npcs:
		return false
	return _now_seconds() - _service_wait_started_seconds >= required_seconds


func mark_service_requested() -> void:
	_service_requested = true


func clear_service_request() -> void:
	_service_requested = false


func mark_service_completed() -> void:
	_service_requested = false
	_service_wait_started_seconds = _now_seconds()


func should_use_sitting_talking_idle(member: HumanoidCharacter) -> bool:
	return _bar_service_area != null and member != null and not member.is_player_party_member()


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
