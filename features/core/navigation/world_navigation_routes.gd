extends RefCounted

## Derived routing views of the existing baked tile grid. No second bake,
## movement solver, durable actor state or copied navmesh resources.
## Nearby agents share a small native map. Long orders share a coarse tile
## corridor; native polygon routing still decides actual walkability/floors.
const CACHE_LIMIT := 64
const NEIGHBORS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

class Route extends RefCounted:
	var map: RID
	var source_map: RID
	var iteration := 0
	var regions: Array[RID] = []
	var coarse_route: Array[Vector2i] = []
	var retry := 0
	var owns_map := true
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			for region in regions: NavigationServer3D.free_rid(region)
			if owns_map and map.is_valid(): NavigationServer3D.free_rid(map)

var _owner: WeakRef
var _map: RID
var _iteration := -1
var _routes: Dictionary = {}
var _graph: AStar2D
var _ids: Dictionary = {}
var _coordinates: Array[Vector2i] = []
var _corridors: Dictionary = {}

func _init(owner: Node) -> void:
	_owner = weakref(owner)

func acquire(map: RID, start: Vector3, finish: Vector3, retry: int = 0) -> Route:
	var owner = _owner.get_ref()
	if owner == null: return null
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	if _map != map or _iteration != iteration:
		_routes.clear()
		_corridors.clear()
		_graph = null
		_ids.clear()
		_coordinates.clear()
		_map = map
		_iteration = iteration
	var size: float = owner.settings.tile_size
	var from := Vector2i(floori(start.x / size), floori(start.z / size))
	var to := Vector2i(floori(finish.x / size), floori(finish.z / size))
	var key := Vector4i(from.x, from.y, to.x, to.y)
	var cache_key := [key, retry]
	if _routes.has(cache_key): return _routes[cache_key]
	if retry >= 2:
		# A coarse tile can contain disconnected floors/islands. Preserve the
		# native full-map answer in that exceptional case, without duplicating
		# and synchronously rebuilding the entire world's polygon graph.
		var fallback := Route.new()
		fallback.map = map
		fallback.source_map = map
		fallback.iteration = iteration
		fallback.retry = retry
		fallback.owns_map = false
		return fallback
	var coords: Dictionary = {}
	var corridor: Array[Vector2i] = []
	if retry == 0 and maxi(absi(from.x - to.x), absi(from.y - to.y)) <= 1:
		for x in range(mini(from.x, to.x) - 1, maxi(from.x, to.x) + 2):
			for z in range(mini(from.y, to.y) - 1, maxi(from.y, to.y) + 2):
				coords[Vector2i(x, z)] = true
	else:
		_build_graph(owner)
		if not _corridors.has(key):
			var path: Array[Vector2i] = []
			if _ids.has(from) and _ids.has(to):
				for id in _graph.get_id_path(_ids[from], _ids[to]):
					path.append(_coordinates[id])
			if _corridors.size() >= CACHE_LIMIT:
				_corridors.erase(_corridors.keys()[0])
			_corridors[key] = path
		corridor.assign(_corridors[key])
		# A tile can contain disconnected islands or different floors. The
		# coarse route is only a broad phase, never a reachability answer.
		var margin := 1
		for coord in corridor:
			for x in range(-margin, margin + 1):
				for z in range(-margin, margin + 1): coords[coord + Vector2i(x, z)] = true
		for coord in [from, to]:
			coords[coord] = true

	var route := _make_map(owner, coords)
	route.coarse_route = corridor
	route.retry = retry
	if _routes.size() >= CACHE_LIMIT:
		_routes.erase(_routes.keys()[0])
	_routes[cache_key] = route
	return route

func _build_graph(owner: Node) -> void:
	if _graph != null: return
	_graph = AStar2D.new()
	for coord: Vector2i in owner._tiles:
		var tile = owner._tiles[coord]
		if not _usable(tile): continue
		var id := _coordinates.size()
		_coordinates.append(coord)
		_ids[coord] = id
		_graph.add_point(id, Vector2(coord))
	for coord: Vector2i in _ids:
		for neighbor in NEIGHBORS:
			var next: Vector2i = coord + neighbor
			if _ids.has(next) and _ids[next] > _ids[coord]:
				_graph.connect_points(_ids[coord], _ids[next])

func _usable(tile: RefCounted) -> bool:
	if tile == null or not is_instance_valid(tile.region): return false
	var region: NavigationRegion3D = tile.region
	return region.enabled and region.navigation_mesh != null and region.navigation_mesh.get_polygon_count() > 0 and NavigationServer3D.region_get_map(region.get_rid()) == _map

func _make_map(owner: Node, coords: Dictionary) -> Route:
	var route := Route.new()
	route.source_map = _map
	route.iteration = _iteration
	route.map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_use_async_iterations(route.map, false)
	NavigationServer3D.map_set_up(route.map, NavigationServer3D.map_get_up(_map))
	NavigationServer3D.map_set_cell_size(route.map, NavigationServer3D.map_get_cell_size(_map))
	NavigationServer3D.map_set_cell_height(route.map, NavigationServer3D.map_get_cell_height(_map))
	NavigationServer3D.map_set_use_edge_connections(route.map, NavigationServer3D.map_get_use_edge_connections(_map))
	NavigationServer3D.map_set_edge_connection_margin(route.map, NavigationServer3D.map_get_edge_connection_margin(_map))
	NavigationServer3D.map_set_active(route.map, true)
	for coord: Vector2i in coords:
		var tile = owner._tiles.get(coord)
		if not _usable(tile): continue
		var original: NavigationRegion3D = tile.region
		var region := NavigationServer3D.region_create()
		NavigationServer3D.region_set_use_async_iterations(region, false)
		NavigationServer3D.region_set_navigation_mesh(region, original.navigation_mesh)
		NavigationServer3D.region_set_transform(region, original.global_transform)
		NavigationServer3D.region_set_navigation_layers(region, original.navigation_layers)
		NavigationServer3D.region_set_enter_cost(region, original.enter_cost)
		NavigationServer3D.region_set_travel_cost(region, original.travel_cost)
		NavigationServer3D.region_set_use_edge_connections(region, original.use_edge_connections)
		NavigationServer3D.region_set_owner_id(region, original.get_instance_id())
		NavigationServer3D.region_set_map(region, route.map)
		route.regions.append(region)
	NavigationServer3D.map_force_update(route.map)
	return route
