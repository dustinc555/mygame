extends GutTest

const QUERY_PATH := "res://features/core/navigation/world_navigation_queries.gd"
var _viewport: SubViewport
var _root: Node3D
var _navigation: WorldNavigationController
var _map: RID

func before_each() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	add_child(_viewport)
	_root = Node3D.new()
	_viewport.add_child(_root)
	_map = _root.get_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(_map, false)
	NavigationServer3D.map_set_active(_map, true)
	_navigation = WorldNavigationController.new()
	_navigation.settings = WorldNavigationSettings.new()
	_navigation.settings.tile_size = 32.0
	_navigation._mode = WorldNavigationController.Mode.TILED
	_root.add_child(_navigation)
	_navigation.set_process(false)
	_add_tile(Vector2i.ZERO)
	_add_tile(Vector2i(1, 0))
	_add_tile(Vector2i(20, 20))
	await _sync()

func after_each() -> void:
	_viewport.queue_free()
	await get_tree().process_frame

func _queries():
	if not ResourceLoader.exists(QUERY_PATH):
		assert_true(false, "Shared local navigation query implementation exists")
		return null
	return load(QUERY_PATH)

func test_local_regions_exclude_distant_tiles() -> void:
	if not _navigation.has_method("get_query_regions"):
		assert_true(false, "Navigation authority exposes its existing tile index")
		return
	var regions: Array = _navigation.call("get_query_regions", _map, AABB(Vector3(15, 0, 15), Vector3(2, 0, 2)))
	assert_eq(regions.size(), 1)
	assert_eq(regions[0], _navigation._tiles[Vector2i.ZERO].region.get_rid())

func test_local_projection_matches_global_nearest() -> void:
	var queries = _queries()
	if queries == null: return
	for point in [Vector3(16, 0.2, 16), Vector3(31.9, 0, 16), Vector3(-0.1, 0, 16), Vector3(650, 0, 650), Vector3(100, 0, 100)]:
		assert_almost_eq(queries.closest_point(_root, _map, point), NavigationServer3D.map_get_closest_point(_map, point), Vector3.ONE * 0.001)

func test_path_crosses_tile_seam() -> void:
	var queries = _queries()
	if queries == null: return
	var start := Vector3(16, 0, 16)
	var finish := Vector3(48, 0, 16)
	var path: PackedVector3Array = queries.path(_root, _map, start, finish)
	assert_false(path.is_empty())
	assert_almost_eq(path[0], start, Vector3.ONE * 0.001)
	assert_almost_eq(path[-1], finish, Vector3.ONE * 0.001)

func test_disconnected_destination_does_not_become_reachable() -> void:
	var queries = _queries()
	if queries == null: return
	var finish := Vector3(650, 0, 650)
	var path: PackedVector3Array = queries.path(_root, _map, Vector3(16, 0, 16), finish)
	assert_true(path.is_empty() or path[-1].distance_to(finish) > 0.05)

func test_detour_outside_local_bounds_uses_full_map() -> void:
	var queries = _queries()
	if queries == null: return
	# Start/end are close, but the only connection is two tiles to the north.
	_navigation._tiles[Vector2i(1, 0)].region.enabled = false
	_add_tile(Vector2i(2, 0))
	for coord in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1)]:
		_add_tile(coord)
	await _sync()
	var finish := Vector3(80, 0, 16)
	var path: PackedVector3Array = queries.path(_root, _map, Vector3(16, 0, 16), finish)
	assert_false(path.is_empty())
	assert_almost_eq(path[-1], finish, Vector3.ONE * 0.001)
	assert_true(path.size() > 2, "Fallback retains the real detour")

func test_disabled_or_replaced_region_is_not_cached() -> void:
	var queries = _queries()
	if queries == null: return
	var point := Vector3(16, 0, 16)
	assert_almost_eq(queries.closest_point(_root, _map, point), point, Vector3.ONE * 0.001)
	_navigation._tiles[Vector2i.ZERO].region.enabled = false
	await _sync()
	assert_almost_eq(queries.closest_point(_root, _map, point), NavigationServer3D.map_get_closest_point(_map, point), Vector3.ONE * 0.001)
	_navigation._tiles[Vector2i.ZERO].region.navigation_mesh = _mesh(Vector2i.ZERO, 2.0)
	_navigation._tiles[Vector2i.ZERO].region.enabled = true
	await _sync()
	assert_almost_eq(queries.closest_point(_root, _map, point), Vector3(16, 2, 16), Vector3.ONE * 0.001)

func test_path_reuses_exact_query_until_navigation_changes() -> void:
	var queries = _queries()
	if queries == null: return
	if not _navigation.has_method("get_cached_query_path"):
		assert_true(false, "Navigation retains exact path queries between unchanged positions")
		return
	var start := Vector3(16, 0, 16)
	var finish := Vector3(48, 0, 16)
	var path: PackedVector3Array = queries.path(_root, _map, start, finish)
	assert_eq(_navigation.call("get_cached_query_path", _map, start, finish), path)
	assert_null(_navigation.call("get_cached_query_path", _map, start + Vector3(0.01, 0, 0), finish), "Movement invalidates rather than rounding positions")
	_navigation._tiles[Vector2i(1, 0)].region.enabled = false
	await _sync()
	assert_null(_navigation.call("get_cached_query_path", _map, start, finish))
	var changed: PackedVector3Array = queries.path(_root, _map, start, finish)
	assert_true(changed.is_empty() or changed[-1].distance_to(finish) > 0.05)

func test_other_world_does_not_use_this_world_tiles() -> void:
	var queries = _queries()
	if queries == null: return
	var other_map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_use_async_iterations(other_map, false)
	NavigationServer3D.map_set_active(other_map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_use_async_iterations(region, false)
	NavigationServer3D.region_set_navigation_mesh(region, _mesh(Vector2i(10, 10)))
	NavigationServer3D.region_set_map(region, other_map)
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(other_map)
	assert_eq(queries.closest_point(_root, other_map, Vector3(16, 0, 16)), NavigationServer3D.map_get_closest_point(other_map, Vector3(16, 0, 16)))
	NavigationServer3D.free_rid(region)
	NavigationServer3D.free_rid(other_map)

func test_overland_movement_uses_world_graph_without_a_clipped_local_first_search() -> void:
	_navigation.settings.threaded_queries_enabled = true
	var world := _root.get_world_3d()
	_navigation.request_paths("overland", world, _map, Vector3(16, 0, 16), PackedVector3Array([Vector3(650, 0, 650)]), 1, true, true)
	assert_true(_navigation.query_jobs._pending.overland.request.regions.is_empty(), "A distant destination needs the world graph, not an enclosing local rectangle")
	_navigation.request_paths("nearby", world, _map, Vector3(16, 0, 16), PackedVector3Array([Vector3(48, 0, 16)]), 1, true, true)
	assert_false(_navigation.query_jobs._pending.nearby.request.regions.is_empty(), "Nearby movement retains the local optimization")
	_navigation.request_paths("tactical", world, _map, Vector3(16, 0, 16), PackedVector3Array([Vector3(650, 0, 650)]))
	assert_false(_navigation.query_jobs._pending.tactical.request.regions.is_empty(), "Tactical candidate searches retain their existing policy")

func _add_tile(coord: Vector2i) -> void:
	var region := NavigationRegion3D.new()
	NavigationServer3D.region_set_use_async_iterations(region.get_rid(), false)
	region.navigation_mesh = _mesh(coord)
	_root.add_child(region)
	var tile := WorldNavigationController.Tile.new()
	tile.region = region
	tile.state = WorldNavigationController.TileState.BAKED
	_navigation._tiles[coord] = tile

func _mesh(coord: Vector2i, height: float = 0.0) -> NavigationMesh:
	var origin := Vector3(coord.x * 32.0, height, coord.y * 32.0)
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([origin, origin + Vector3(32, 0, 0), origin + Vector3(32, 0, 32), origin + Vector3(0, 0, 32)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return mesh

func _sync() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(_map)
	await get_tree().process_frame
