extends RefCounted

## Local broad phase, native navigation narrow phase. Does not drive actors or
## change their NavigationAgent3D. Both combat and furniture exits use this.
## These distances tune query work only, never gameplay reach or roam limits.
const NEAREST_SEARCH_RADIUS := 4.0
const PATH_SEARCH_MARGIN := 8.0
const PATH_ENDPOINT_EPSILON := 0.05


static func closest_point(context: Node, map: RID, point: Vector3) -> Vector3:
	var regions := _regions(context, map, AABB(point, Vector3.ZERO).grow(NEAREST_SEARCH_RADIUS))
	var nearest := Vector3.INF
	var distance_squared := INF
	for region in regions:
		var candidate := NavigationServer3D.region_get_closest_point(region, point)
		var candidate_distance := candidate.distance_squared_to(point)
		if candidate_distance < distance_squared:
			nearest = candidate
			distance_squared = candidate_distance
	# Every tile touching the search box was considered. A result inside its
	# inscribed sphere is no farther than anything outside the box. Otherwise
	# fall back: a distant local point is NOT necessarily the global nearest.
	if distance_squared < NEAREST_SEARCH_RADIUS * NEAREST_SEARCH_RADIUS:
		return nearest
	return NavigationServer3D.map_get_closest_point(map, point)


static func path(context: Node, map: RID, start: Vector3, finish: Vector3) -> PackedVector3Array:
	var navigation := _navigation(context)
	if navigation != null:
		var cached: Variant = navigation.get_cached_query_path(map, start, finish)
		if cached != null:
			return cached
	var points := _find_path(context, map, start, finish)
	if navigation != null:
		navigation.cache_query_path(start, finish, points)
	return points


static func _find_path(context: Node, map: RID, start: Vector3, finish: Vector3) -> PackedVector3Array:
	var bounds := AABB(start, Vector3.ZERO).expand(finish).grow(PATH_SEARCH_MARGIN)
	var regions := _regions(context, map, bounds)
	if not regions.is_empty():
		var parameters := NavigationPathQueryParameters3D.new()
		parameters.map = map
		parameters.start_position = start
		parameters.target_position = finish
		parameters.included_regions = regions
		parameters.metadata_flags = 0
		var result := NavigationPathQueryResult3D.new()
		NavigationServer3D.query_path(parameters, result)
		var points := result.get_path()
		if not points.is_empty() and points[0].distance_to(start) <= PATH_ENDPOINT_EPSILON and points[-1].distance_to(finish) <= PATH_ENDPOINT_EPSILON:
			return points
	# Never declare a destination unreachable just because its route leaves
	# the local window. The native full-map route remains authoritative.
	return NavigationServer3D.map_get_path(map, start, finish, true)


static func _regions(context: Node, map: RID, bounds: AABB) -> Array[RID]:
	var navigation := _navigation(context)
	if navigation != null:
		return navigation.get_query_regions(map, bounds)
	return []


static func _navigation(context: Node) -> WorldNavigationController:
	if not is_instance_valid(context) or not context.is_inside_tree():
		return null
	return context.get_tree().get_first_node_in_group("world_navigation_controller") as WorldNavigationController
