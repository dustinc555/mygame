extends GutTest

const CONTAINER = preload("res://features/world/projection/containers/container.tscn")

@warning_ignore("missing_tool")
class CountedContainer extends WorldContainer:
	var projections := 0
	func _clamped_to_navmesh(point: Vector3) -> Vector3:
		projections += 1
		return super._clamped_to_navmesh(point)

class Interactor extends HumanoidCharacter:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass

class CountedNavigation extends WorldNavigationController:
	var local_queries := 0
	func get_query_regions(map: RID, bounds: AABB) -> Array[RID]:
		local_queries += 1
		return super.get_query_regions(map, bounds)

var _viewport: SubViewport
var _world: Node3D
var _map: RID
var _region: NavigationRegion3D
var _navigation: CountedNavigation
var _bag: CountedContainer
var _actor: Interactor

func before_each() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_map = _world.get_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(_map, false)
	NavigationServer3D.map_set_active(_map, true)
	_region = NavigationRegion3D.new()
	NavigationServer3D.region_set_use_async_iterations(_region.get_rid(), false)
	_region.navigation_mesh = _floor_mesh(0.0)
	_world.add_child(_region)
	_navigation = CountedNavigation.new()
	_navigation.settings = WorldNavigationSettings.new()
	_navigation.settings.tile_size = 32.0
	_navigation._mode = WorldNavigationController.Mode.TILED
	_world.add_child(_navigation)
	_navigation.set_process(false)
	var tile := WorldNavigationController.Tile.new()
	tile.region = _region
	tile.state = WorldNavigationController.TileState.BAKED
	_navigation._tiles[Vector2i.ZERO] = tile
	var bag := CONTAINER.instantiate()
	bag.set_script(CountedContainer)
	_bag = bag
	_bag.container_id = "unit.container.approach"
	_bag.position = Vector3(16, 1, 16)
	_world.add_child(_bag)
	_actor = Interactor.new()
	_actor.position = Vector3(24, 0, 16)
	_world.add_child(_actor)
	await _sync()

func after_each() -> void:
	_viewport.queue_free()
	await get_tree().process_frame

func _floor_mesh(height: float) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(0, height, 0), Vector3(32, height, 0), Vector3(32, height, 32), Vector3(0, height, 32)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return mesh

func _sync() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(_map)

func test_unchanged_bag_projects_approach_once_instead_of_every_tick() -> void:
	for tick in 20:
		assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(17.3, 0, 16), Vector3.ONE * 0.001)
	assert_eq(_bag.projections, 1, "Approaching a stationary bag must not repeat native navigation searches")

func test_first_projection_uses_the_existing_local_tile_index() -> void:
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(17.3, 0, 16), Vector3.ONE * 0.001)
	assert_eq(_navigation.local_queries, 1, "An uncached camp bag must not search the whole world first")

func test_multiple_members_keep_independent_cached_slots() -> void:
	_bag.slot_count = 2
	var other := Interactor.new()
	other.position = Vector3(8, 0, 16)
	_world.add_child(other)
	for tick in 20:
		assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(17.3, 0, 16), Vector3.ONE * 0.001)
		assert_almost_eq(_bag.get_interaction_position(other), Vector3(14.7, 0, 16), Vector3.ONE * 0.001)
	assert_eq(_bag.projections, 2, "Alternating actors must not evict one another's approach point")

func test_moving_parent_recalculates_the_world_space_approach() -> void:
	var furniture := Node3D.new()
	_world.add_child(furniture)
	_bag.reparent(furniture)
	_bag.get_interaction_position(_actor)
	var iteration := NavigationServer3D.map_get_iteration_id(_map)
	furniture.position.x = 2.0
	assert_eq(NavigationServer3D.map_get_iteration_id(_map), iteration, "Placement invalidation is independent of a later nav rebuild")
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(19.3, 0, 16), Vector3.ONE * 0.001)
	assert_eq(_bag.projections, 2)

func test_slot_distance_edit_recalculates_the_approach() -> void:
	_bag.get_interaction_position(_actor)
	_bag.slot_distance = 2.0
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(18, 0, 16), Vector3.ONE * 0.001)
	assert_eq(_bag.projections, 2)

func test_slot_count_edit_recalculates_an_assigned_slot() -> void:
	_bag.slot_count = 2
	_actor.position = Vector3(8, 0, 16)
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(14.7, 0, 16), Vector3.ONE * 0.001)
	_bag.slot_count = 4
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(16, 0, 17.3), Vector3.ONE * 0.001)
	assert_eq(_bag.projections, 2)

func test_navigation_rebuild_invalidates_cached_height() -> void:
	_bag.get_interaction_position(_actor)
	_region.navigation_mesh = _floor_mesh(2.0)
	await _sync()
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(17.3, 2, 16), Vector3.ONE * 0.001)
	assert_eq(_bag.projections, 2)

func test_world_change_does_not_reuse_another_maps_point() -> void:
	_bag.get_interaction_position(_actor)
	var other_world := _move_to_new_world()
	var other_region := NavigationRegion3D.new()
	NavigationServer3D.region_set_use_async_iterations(other_region.get_rid(), false)
	other_region.navigation_mesh = _floor_mesh(3.0)
	other_world.add_child(other_region)
	await _sync()
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(17.3, 3, 16), Vector3.ONE * 0.001)
	assert_eq(_bag.projections, 2)

func test_unsynchronized_map_does_not_cache_an_unprojected_point() -> void:
	var other_world := _move_to_new_world()
	assert_eq(NavigationServer3D.map_get_iteration_id(_map), 0)
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(17.3, 1, 16), Vector3.ONE * 0.001)
	assert_eq(_bag.projections, 0)
	var other_region := NavigationRegion3D.new()
	NavigationServer3D.region_set_use_async_iterations(other_region.get_rid(), false)
	other_region.navigation_mesh = _floor_mesh(0.0)
	other_world.add_child(other_region)
	await _sync()
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(17.3, 0, 16), Vector3.ONE * 0.001)
	assert_eq(_bag.projections, 1)

func test_missing_nearby_tiles_retains_full_map_projection() -> void:
	_bag.position = Vector3(100, 1, 16)
	_actor.position = Vector3(110, 0, 16)
	assert_almost_eq(_bag.get_interaction_position(_actor), Vector3(32, 0, 16), Vector3.ONE * 0.001)
	assert_eq(_navigation.local_queries, 1)

func test_repeated_placement_changes_keep_the_cache_bounded() -> void:
	for offset in 30:
		_bag.position.x = 1.0 + offset
		_bag.get_interaction_position(_actor)
		assert_lte(_bag._approach_points.size(), _bag.slot_count)

func test_released_actor_can_be_freed_and_replaced_without_stale_references() -> void:
	_bag.register_interactor(_actor)
	var point := _bag.get_interaction_position(_actor)
	_bag.release_interactor(_actor)
	_actor.free()
	_actor = Interactor.new()
	_actor.position = Vector3(24, 0, 16)
	_world.add_child(_actor)
	_bag.register_interactor(_actor)
	assert_eq(_bag.get_interaction_position(_actor), point)
	assert_true(_bag.resolve_interaction(_actor), "Replacement can complete the normal pending interaction")
	assert_eq(_bag.projections, 1, "Geometry cache must not own an actor projection")

func _move_to_new_world() -> Node3D:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	_viewport.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	_map = world.get_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(_map, false)
	NavigationServer3D.map_set_active(_map, true)
	_bag.reparent(world)
	_actor.reparent(world)
	return world
