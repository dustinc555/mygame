extends Node

## Event-driven local passage recovery. No idle population scan or durable job
## ownership: only live, bounded sidesteps are retained, through weak references.
const SERVICE_ID := &"navigation_recovery"
const CLEARANCE = preload("res://features/combat/bridge/combat_navigation.gd")

@export var search_radius := 2.4
@export var step_distance := 1.5
@export var passage_clearance := 2.5
@export var yield_timeout_seconds := 6.0

var _query: Node
var _active: Array[Dictionary] = []

func initialize(context: BootstrapContext) -> void:
	_query = context.get_optional(&"actor_query")
	set_physics_process(false)

func request_passage(requester: Node3D) -> bool:
	if not is_instance_valid(_query) or not _live(requester) or not requester.has_move_target() or requester.is_in_combat():
		return false
	for entry in _active:
		if entry.requester.get_ref() == requester:
			return false
	var direction: Vector3 = requester.get_move_target() - requester.global_position
	var agent := requester.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent != null:
		var path := agent.get_current_navigation_path()
		var index := agent.get_current_navigation_path_index()
		if index >= 0 and index < path.size():
			direction = path[index] - requester.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return false
	direction = direction.normalized()
	var neighbors: Array = _query.get_nearby_actors(requester.global_position, search_radius)
	for value in neighbors:
		if not _live(value) or value == requester or not value.has_method("can_navigation_yield"):
			continue
		var blocker: Node3D = value
		if not blocker.can_navigation_yield() or requester.has_hostility_with(blocker):
			continue
		var offset := blocker.global_position - requester.global_position
		if absf(offset.y) > 0.75 or offset.dot(direction) <= 0.0:
			continue
		var lateral := offset - direction * offset.dot(direction)
		if Vector2(lateral.x, lateral.z).length() > requester.navigation_agent_radius + blocker.navigation_agent_radius:
			continue
		var destination := _find_step(blocker, requester, direction)
		if not destination.is_finite() or not blocker.begin_navigation_yield(destination):
			continue
		_active.append({"requester": weakref(requester), "blocker": weakref(blocker), "origin": blocker.global_position, "destination": destination, "radius": blocker.navigation_agent_radius, "remaining": yield_timeout_seconds})
		set_physics_process(true)
		return true
	return false

func _find_step(blocker: Node3D, requester: Node3D, direction: Vector3) -> Vector3:
	var side := direction.cross(Vector3.UP).normalized()
	# Try sideways, then diagonally into either side of the opening.
	for offset in [side, -side, (side + direction).normalized(), (-side + direction).normalized(), (side - direction).normalized(), (-side - direction).normalized()]:
		var candidate := _supported_position(blocker, blocker.global_position + Vector3(offset) * step_distance)
		if not candidate.is_finite():
			continue
		var destination: Vector3 = CLEARANCE.find_reachable_position(blocker, requester, candidate, false)
		if not destination.is_finite() or not _clear_local_route(blocker, destination):
			continue
		var occupied := false
		for entry in _active:
			var separation: Vector3 = entry.destination - destination
			if absf(separation.y) < 0.75 and Vector2(separation.x, separation.z).length() < blocker.navigation_agent_radius + entry.radius + 0.15:
				occupied = true
				break
		if occupied:
			continue
		for neighbor in _query.get_nearby_actors(destination, search_radius):
			if not _live(neighbor) or neighbor == blocker:
				continue
			var separation: Vector3 = neighbor.global_position - destination
			if absf(separation.y) < 0.75 and Vector2(separation.x, separation.z).length() < blocker.navigation_agent_radius + neighbor.navigation_agent_radius + 0.15:
				occupied = true
				break
		if not occupied:
			return destination
	return Vector3.INF

func _clear_local_route(actor: Node3D, destination: Vector3) -> bool:
	# Follow the actual route: a straight capsule sweep to a side point cuts
	# through the jamb even when the route first backs out of the opening.
	# The shared helper checks endpoint fit and wall occlusion along this path.
	var shape := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null or shape.shape == null:
		return false
	var map := actor.get_world_3d().navigation_map
	var origin_offset: Vector3 = actor.get_floor_aligned_origin_position(Vector3.ZERO)
	var start := NavigationServer3D.map_get_closest_point(map, actor.global_position - origin_offset)
	var end := NavigationServer3D.map_get_closest_point(map, destination - origin_offset)
	var path := NavigationServer3D.map_get_path(map, start, end, true)
	if path.size() < 2:
		return false
	var length := 0.0
	var torso_offset := origin_offset + shape.global_position - actor.global_position
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
		if length > step_distance * 2.0:
			return false
		var ray := PhysicsRayQueryParameters3D.create(path[index - 1] + torso_offset, path[index] + torso_offset, 8)
		ray.exclude = [actor.get_rid()]
		if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			return false
		var samples := maxi(1, ceili(path[index - 1].distance_to(path[index]) / 0.2))
		for sample in range(samples + 1):
			var point := path[index - 1].lerp(path[index], float(sample) / samples) + origin_offset
			var grounded := _supported_position(actor, point)
			if not grounded.is_finite() or absf(grounded.y - actor.global_position.y) > 0.3:
				return false
	return true

func _supported_position(actor: Node3D, candidate: Vector3) -> Vector3:
	var origin_offset: Vector3 = actor.get_floor_aligned_origin_position(Vector3.ZERO)
	var floor_hint := candidate - origin_offset
	var query := PhysicsRayQueryParameters3D.create(floor_hint + Vector3.UP * 0.3, floor_hint - Vector3.UP * 0.3, 1 | 4)
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < cos(actor.floor_max_angle):
		return Vector3.INF
	return actor.get_floor_aligned_origin_position(hit.position)

func _physics_process(delta: float) -> void:
	for index in range(_active.size() - 1, -1, -1):
		var entry := _active[index]
		var blocker = entry.blocker.get_ref()
		var requester = entry.requester.get_ref()
		if not _live(blocker) or not blocker.is_navigation_yielding():
			_active.remove_at(index)
			continue
		entry.remaining -= delta
		if not _live(requester) or not requester.has_move_target() or requester.global_position.distance_to(entry.origin) > passage_clearance or entry.remaining <= 0.0:
			blocker.end_navigation_yield()
			_active.remove_at(index)
	set_physics_process(not _active.is_empty())

func _exit_tree() -> void:
	for entry in _active:
		var blocker = entry.blocker.get_ref()
		if _live(blocker):
			blocker.end_navigation_yield()
	_active.clear()

func _live(value: Variant) -> bool:
	return is_instance_valid(value) and value is Node3D and value.is_inside_tree() and not value.is_queued_for_deletion()
