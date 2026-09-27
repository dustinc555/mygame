extends RefCounted

## Stateless bridge queries. Positions supplied/returned are actor origins, not
## navmesh floor points. This helper never takes ownership of actor navigation.
const SOLID_WORLD_MASK := 1 | 4 # World and furniture; never actors or click-only panels.
const CLOSED_DOOR_MASK := 8
# Numerical/contact allowances, in meters; not tactical arrival radii.
const ENDPOINT_EPSILON := 0.05
const NAV_HEIGHT_EPSILON := 0.25 # Recast floor voxel quantization, checked against real ground.
const FLOOR_CONTACT_LIFT := 0.02
const NAV_QUERIES := preload("res://features/core/navigation/world_navigation_queries.gd")


## Obstruction only: combat components retain reach, timing and turn ownership.
static func can_strike(actor: Node3D, target: Node3D, from_position: Vector3 = Vector3.INF) -> bool:
	if not _live_pair(actor, target):
		return false
	var actor_shape := _body_shape(actor)
	# Downed WorldActors disable collision participation, not strike eligibility.
	var target_shape := _body_shape(target, false)
	if actor_shape == null or target_shape == null:
		return false
	var origin := actor.global_position if from_position == Vector3.INF else from_position
	if not origin.is_finite():
		return false
	var from := actor_shape.global_position + origin - actor.global_position
	var to := target_shape.global_position
	var query := PhysicsRayQueryParameters3D.create(from, to, SOLID_WORLD_MASK | CLOSED_DOOR_MASK)
	query.exclude = _exclude_bodies(actor, target)
	query.hit_from_inside = true
	query.collide_with_areas = false
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


static func find_reachable_position(actor: Node3D, target: Node3D, candidate: Vector3, require_strike: bool = true) -> Vector3:
	if not _live_pair(actor, target) or not candidate.is_finite():
		return Vector3.INF
	var shape := _body_shape(actor)
	if shape == null:
		return Vector3.INF
	var world := actor.get_world_3d()
	var map := world.navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0 or NavigationServer3D.map_get_regions(map).is_empty():
		return Vector3.INF
	var origin_offset := _floor_origin_offset(actor, shape)
	var candidate_floor := candidate - origin_offset
	var actor_floor := actor.global_position - origin_offset
	var destination := NAV_QUERIES.closest_point(actor, map, candidate_floor)
	var start := NAV_QUERIES.closest_point(actor, map, actor_floor)
	# Avoidance can put a live body just outside the baked clearance boundary.
	# Permit a body-width recovery to the mesh, not a remote destination snap.
	var recovery_radius := maxf(shape.shape.get_debug_mesh().get_aabb().size.x, ENDPOINT_EPSILON)
	if not _near_floor_hint(destination, candidate_floor) or Vector2(start.x - actor_floor.x, start.z - actor_floor.z).length() > recovery_radius or absf(start.y - actor_floor.y) > NAV_HEIGHT_EPSILON:
		return Vector3.INF
	var path := NAV_QUERIES.path(actor, map, start, destination)
	if path.is_empty() or path[0].distance_to(start) > ENDPOINT_EPSILON or path[path.size() - 1].distance_to(destination) > ENDPOINT_EPSILON:
		return Vector3.INF
	var ground := _ground_floor(actor, destination)
	if not ground.is_finite() or absf(ground.y - candidate_floor.y) > ENDPOINT_EPSILON:
		return Vector3.INF
	var result := ground + origin_offset
	if require_strike and not can_strike(actor, target, result):
		return Vector3.INF
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.exclude = _exclude_bodies(actor, target)
	query.collision_mask = SOLID_WORLD_MASK | CLOSED_DOOR_MASK
	query.collide_with_areas = false
	query.transform = _shape_at(actor, shape, result)
	if not world.direct_space_state.intersect_shape(query, 1).is_empty():
		return Vector3.INF
	# The shared navigator/body owns clearance along the route. Sweeping a
	# floor-seated upright capsule between nav points falsely intersects valid
	# ramps (the body's support height changes with incline). Only reject gross
	# stale-map wall crossings here; retain the real shape check at the endpoint.
	# Doors are runtime-openable portals, but cannot be occupied or struck through.
	var torso_offset := origin_offset + shape.global_position - actor.global_position
	var route_ray := PhysicsRayQueryParameters3D.new()
	route_ray.collision_mask = SOLID_WORLD_MASK
	route_ray.exclude = query.exclude
	route_ray.hit_from_inside = true
	for index in range(1, path.size()):
		route_ray.from = path[index - 1] + torso_offset
		route_ray.to = path[index] + torso_offset
		if not world.direct_space_state.intersect_ray(route_ray).is_empty():
			return Vector3.INF
	return result


static func _live_pair(actor: Node3D, target: Node3D) -> bool:
	return is_instance_valid(actor) and is_instance_valid(target) and not actor.is_queued_for_deletion() and not target.is_queued_for_deletion() and actor.is_inside_tree() and target.is_inside_tree() and actor.get_world_3d() != null and actor.get_world_3d() == target.get_world_3d()


static func _body_shape(actor: Node3D, require_enabled: bool = true) -> CollisionShape3D:
	var shape := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return shape if shape != null and shape.shape != null and (not require_enabled or not shape.disabled) else null


static func _floor_origin_offset(actor: Node3D, shape: CollisionShape3D) -> Vector3:
	if actor.has_method("get_floor_aligned_origin_position"):
		return actor.call("get_floor_aligned_origin_position", Vector3.ZERO)
	var bounds := shape.shape.get_debug_mesh().get_aabb()
	var local_bounds := shape.transform * bounds
	return Vector3.UP * -local_bounds.position.y


static func _near_floor_hint(point: Vector3, hint: Vector3) -> bool:
	return Vector2(point.x - hint.x, point.z - hint.z).length() <= ENDPOINT_EPSILON and absf(point.y - hint.y) <= NAV_HEIGHT_EPSILON


static func _ground_floor(actor: Node3D, nav_floor: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(nav_floor + Vector3.UP * NAV_HEIGHT_EPSILON, nav_floor - Vector3.UP * NAV_HEIGHT_EPSILON, SOLID_WORLD_MASK)
	if actor is CollisionObject3D:
		query.exclude = [actor.get_rid()]
	query.hit_from_inside = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < cos((actor as CharacterBody3D).floor_max_angle if actor is CharacterBody3D else PI / 4.0):
		return Vector3.INF
	return hit["position"]


static func _shape_at(actor: Node3D, shape: CollisionShape3D, origin: Vector3) -> Transform3D:
	var pose := shape.global_transform
	pose.origin += origin - actor.global_position + Vector3.UP * FLOOR_CONTACT_LIFT
	return pose


static func _exclude_bodies(actor: Node3D, target: Node3D) -> Array[RID]:
	var excluded: Array[RID] = []
	for node in [actor, target]:
		if node is CollisionObject3D:
			excluded.append(node.get_rid())
	return excluded
