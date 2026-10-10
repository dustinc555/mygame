extends "res://tests/unit/test_local_navigation_queries.gd"

func test_cached_tiles_do_not_release_gate_before_native_map_installation() -> void:
	_navigation.root_scene = _root
	_navigation._geometry_dirty = false
	# An already nonzero map iteration may describe the earlier empty or
	# partial map. A freshly installed cached tile must be queryable too.
	_add_tile(Vector2i(2, 0))
	assert_gt(NavigationServer3D.map_get_iteration_id(_map), 0)
	assert_eq(_navigation.pending_tile_count(), 0, "All tile resources are baked")
	assert_gt(_navigation.gate_tiles_pending(), 0, "Loading still owns the initial navigation gate")
	_navigation._process(0.0)
	assert_true(_navigation.is_initial_navigation_pending(), "An old native map iteration is not readiness")
	await _sync()
	_navigation._process(0.0)
	assert_false(_navigation.is_initial_navigation_pending(), "Native installation releases the gate")
	assert_eq(_navigation.gate_tiles_pending(), 0)
	assert_almost_eq(NavigationServer3D.map_get_closest_point(_map, Vector3(80, 0, 16)), Vector3(80, 0, 16), Vector3.ONE * 0.001)

func test_empty_baked_world_releases_gate_and_emits_readiness_once() -> void:
	_navigation.root_scene = _root
	_navigation._geometry_dirty = false
	for tile: WorldNavigationController.Tile in _navigation._tiles.values():
		tile.region.navigation_mesh = null
	watch_signals(_navigation)
	_navigation._process(0.0)
	assert_false(_navigation.is_initial_navigation_pending())
	assert_signal_emit_count(_navigation, "initial_navigation_ready", 1)
	_navigation._process(0.0)
	assert_signal_emit_count(_navigation, "initial_navigation_ready", 1)

func test_startup_checks_are_bounded_and_later_changes_do_not_repause() -> void:
	_navigation.root_scene = _root
	_navigation._geometry_dirty = false
	for x in range(3, 43):
		_add_tile(Vector2i(x, 0))
	await _sync()
	_navigation._process(0.0)
	assert_true(_navigation.is_initial_navigation_pending(), "A large map spreads readiness queries across frames")
	_navigation._process(0.0)
	assert_false(_navigation.is_initial_navigation_pending())
	_navigation._mark_tile_dirty(Vector2i.ZERO)
	assert_eq(_navigation.gate_tiles_pending(), 0, "Local runtime patches never re-pause the world")

func test_full_scene_gate_waits_for_native_installation_too() -> void:
	_navigation.root_scene = _root
	_navigation._mode = WorldNavigationController.Mode.FULL_SCENE
	_navigation._geometry_dirty = false
	_navigation._full_scene_bake_completed = true
	_navigation._has_navmesh = true
	var region := NavigationRegion3D.new()
	region.navigation_mesh = _mesh(Vector2i(3, 0))
	_root.add_child(region)
	_navigation._full_scene_region = region
	assert_gt(_navigation.gate_tiles_pending(), 0)
	_navigation._process(0.0)
	assert_true(_navigation.is_initial_navigation_pending())
	await _sync()
	_navigation._process(0.0)
	assert_eq(_navigation.gate_tiles_pending(), 0)

func test_thin_sloped_polygon_projection_does_not_hold_loading_forever() -> void:
	_navigation.root_scene = _root
	_navigation._geometry_dirty = false
	# A controlled long, thin triangle far from zero exposes native closest-
	# point roundoff. Readiness is installation, not sub-millimeter precision.
	var mesh := NavigationMesh.new()
	var grid := Vector3.ONE * 0.1 * 1.001
	mesh.vertices = PackedVector3Array([Vector3(-1919, -9, 7032) * grid, Vector3(-2240, -6, 7038) * grid, Vector3(-2558, -5, 7032) * grid])
	mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	_navigation._tiles[Vector2i.ZERO].region.navigation_mesh = mesh
	await _sync()
	_navigation._process(0.0)
	assert_false(_navigation.is_initial_navigation_pending(), "An installed region is ready even when native projection rounds its sample")
