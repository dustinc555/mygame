extends "res://tests/unit/test_local_navigation_queries.gd"

class QuietActor extends WorldActor:
	func _enter_tree() -> void: pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		navigation_path_height_offset = 0.0
		_navigation_agent.configure()

func test_actor_uses_local_native_path_but_keeps_shared_world_avoidance() -> void:
	var actor := QuietActor.new()
	actor.position = Vector3(10, 0, 10)
	_root.add_child(actor)
	actor.set_move_target(Vector3(40, 0, 10))
	await _sync()
	var agent = actor._navigation_agent
	agent.get_move_direction(0.016)
	assert_ne(agent.get_navigation_map(), _map, "Native path queries no longer search all world regions")
	assert_eq(NavigationServer3D.agent_get_map(agent.get_rid()), _map, "Different route maps must still avoid each other")
	assert_almost_eq(agent.get_final_position(), Vector3(40, 0, 10), Vector3.ONE * 0.001)
	actor.free()

func test_removing_route_owner_restores_native_world_destination() -> void:
	var actor := QuietActor.new()
	actor.position = Vector3(10, 0, 10)
	_root.add_child(actor)
	actor.set_move_target(Vector3(40, 0, 10))
	await _sync()
	var agent = actor._navigation_agent
	agent.get_move_direction(0.016)
	_navigation.free()
	_navigation = null
	actor.set_move_target(Vector3(50, 0, 10))
	agent.get_move_direction(0.016)
	assert_eq(agent.get_navigation_map(), _map)
	assert_almost_eq(agent.get_final_position(), Vector3(50, 0, 10), Vector3.ONE * 0.001)
	actor.free()

func _routes_available() -> bool:
	var available := _navigation.has_method("get_movement_route")
	assert_true(available, "The world navigation owner supplies shared native route maps")
	return available

func test_nearby_members_share_native_map_without_distant_geometry() -> void:
	if not _routes_available(): return
	var first = _navigation.call("get_movement_route", _map, Vector3(10, 0, 10), Vector3(40, 0, 10), 0)
	var second = _navigation.call("get_movement_route", _map, Vector3(11, 0, 11), Vector3(41, 0, 11), 0)
	assert_same(first, second)
	assert_ne(first.map, _map)
	assert_eq(NavigationServer3D.map_get_regions(first.map).size(), 2)
	var points := NavigationServer3D.map_get_path(first.map, Vector3(10, 0, 10), Vector3(40, 0, 10), true)
	assert_false(points.is_empty())
	assert_almost_eq(points[-1], Vector3(40, 0, 10), Vector3.ONE * 0.001)

func test_distant_geometry_does_not_increase_local_route_region_count() -> void:
	if not _routes_available(): return
	for x in range(40):
		for z in range(10):
			_add_tile(Vector2i(x + 100, z + 100))
	await _sync()
	var route = _navigation.call("get_movement_route", _map, Vector3(10, 0, 10), Vector3(40, 0, 10), 0)
	assert_eq(NavigationServer3D.map_get_regions(route.map).size(), 2, "Unrelated world growth does not enter a nearby native query")

func test_long_travel_uses_tile_corridor_instead_of_enclosing_rectangle() -> void:
	if not _routes_available(): return
	for x in range(2, 20): _add_tile(Vector2i(x, 0))
	for z in range(1, 20): _add_tile(Vector2i(19, z))
	await _sync()
	var finish := Vector3(19 * 32 + 16, 0, 19 * 32 + 16)
	var route = _navigation.call("get_movement_route", _map, Vector3(16, 0, 16), finish, 0)
	var path := NavigationServer3D.map_get_path(route.map, Vector3(16, 0, 16), finish, true)
	assert_false(path.is_empty())
	assert_almost_eq(path[-1], finish, Vector3.ONE * 0.001)
	assert_true(route.coarse_route.size() > 20, "Coarse travel route follows the real tile layout")

func test_route_refresh_keeps_existing_handle_alive_until_agents_release_it() -> void:
	if not _routes_available(): return
	var old = _navigation.call("get_movement_route", _map, Vector3(10, 0, 10), Vector3(40, 0, 10), 0)
	_navigation._tiles[Vector2i(1, 0)].region.enabled = false
	await _sync()
	var fresh = _navigation.call("get_movement_route", _map, Vector3(10, 0, 10), Vector3(40, 0, 10), 0)
	assert_ne(old.map, fresh.map)
	assert_eq(NavigationServer3D.map_get_regions(fresh.map).size(), 1)
	assert_eq(NavigationServer3D.map_get_regions(old.map).size(), 2, "No agent retains a freed native map during handover")

func test_foreign_map_is_not_replaced() -> void:
	if not _routes_available(): return
	var map := NavigationServer3D.map_create()
	assert_null(_navigation.call("get_movement_route", map, Vector3.ZERO, Vector3.ONE, 0))
	NavigationServer3D.free_rid(map)

func test_explicit_map_override_is_preserved_after_using_shared_route() -> void:
	var actor := QuietActor.new()
	actor.position = Vector3(10, 0, 10)
	_root.add_child(actor)
	actor.set_move_target(Vector3(40, 0, 10))
	actor._navigation_agent.get_move_direction(0.016)
	var foreign := NavigationServer3D.map_create()
	actor._navigation_agent.set_navigation_map(foreign)
	actor.set_move_target(Vector3(50, 0, 10))
	actor._navigation_agent.get_move_direction(0.016)
	assert_eq(actor._navigation_agent.get_navigation_map(), foreign)
	actor.free()
	NavigationServer3D.free_rid(foreign)

func test_tree_reentry_preserves_destination_and_rebinds_local_route() -> void:
	var actor := QuietActor.new()
	actor.position = Vector3(10, 0, 10)
	_root.add_child(actor)
	actor.set_move_target(Vector3(40, 0, 10))
	actor._navigation_agent.get_move_direction(0.016)
	_root.remove_child(actor)
	_root.add_child(actor)
	await _sync()
	actor._navigation_agent.get_move_direction(0.016)
	assert_ne(actor._navigation_agent.get_navigation_map(), _map)
	assert_eq(NavigationServer3D.agent_get_map(actor._navigation_agent.get_rid()), _map)
	assert_almost_eq(actor._navigation_agent.get_final_position(), Vector3(40, 0, 10), Vector3.ONE * 0.001)
	actor.free()

func test_wider_retry_preserves_detour_outside_local_window() -> void:
	if not _routes_available(): return
	_navigation._tiles[Vector2i(1, 0)].region.enabled = false
	_add_tile(Vector2i(2, 0))
	for z in range(1, 6):
		_add_tile(Vector2i(0, z))
		_add_tile(Vector2i(2, z))
	_add_tile(Vector2i(1, 5))
	await _sync()
	var finish := Vector3(80, 0, 16)
	var route = _navigation.call("get_movement_route", _map, Vector3(16, 0, 16), finish, 1)
	var points := NavigationServer3D.map_get_path(route.map, Vector3(16, 0, 16), finish, true)
	assert_false(points.is_empty())
	assert_almost_eq(points[-1], finish, Vector3.ONE * 0.001)

func test_follower_retries_a_detour_without_changing_movement_solver() -> void:
	_navigation._tiles[Vector2i(1, 0)].region.enabled = false
	_add_tile(Vector2i(2, 0))
	for z in range(1, 6):
		_add_tile(Vector2i(0, z))
		_add_tile(Vector2i(2, z))
	_add_tile(Vector2i(1, 5))
	await _sync()
	var actor := QuietActor.new()
	actor.position = Vector3(16, 0, 16)
	_root.add_child(actor)
	actor.set_move_target(Vector3(80, 0, 16))
	for tick in range(5):
		actor._navigation_agent.get_move_direction(0.016)
		await get_tree().physics_frame
	assert_true(actor.has_move_target())
	assert_almost_eq(actor._navigation_agent.get_final_position(), Vector3(80, 0, 16), Vector3.ONE * 0.001)
	assert_true(actor._navigation_agent.get_current_navigation_path().size() > 2)
	actor.free()

func test_actor_rejects_disconnected_destination_with_bounded_retries() -> void:
	var actor := QuietActor.new()
	actor.position = Vector3(16, 0, 16)
	_root.add_child(actor)
	actor.set_move_target(Vector3(650, 0, 650))
	for tick in range(30):
		if not actor.has_move_target(): break
		actor._navigation_agent.get_move_direction(0.016)
		await get_tree().physics_frame
	assert_false(actor.has_move_target())
	assert_almost_eq(actor.position, Vector3(16, 0, 16), Vector3.ONE * 0.001)
	assert_eq(actor._navigation_agent._route_retry, 2)
	actor.free()

func test_agent_refreshes_route_after_live_geometry_changes() -> void:
	var actor := QuietActor.new()
	actor.position = Vector3(16, 0, 16)
	_root.add_child(actor)
	actor.set_move_target(Vector3(48, 0, 16))
	actor._navigation_agent.get_move_direction(0.016)
	var old_map: RID = actor._navigation_agent.get_navigation_map()
	_navigation._tiles[Vector2i(1, 0)].region.enabled = false
	await _sync()
	actor._navigation_agent.get_move_direction(0.016)
	assert_ne(actor._navigation_agent.get_navigation_map(), old_map)
	assert_true(actor._navigation_agent.get_final_position().distance_to(Vector3(48, 0, 16)) > 1.0)
	actor.free()

func test_eviction_does_not_free_an_agents_active_map() -> void:
	var held = _navigation.get_movement_route(_map, Vector3(10, 0, 10), Vector3(40, 0, 10))
	for index in range(70):
		_navigation.get_movement_route(_map, Vector3(10, 0, 10), Vector3(1000 + index * 32, 0, 1000))
	assert_true(_navigation._movement_routes._routes.size() <= 64)
	assert_true(_navigation._movement_routes._corridors.size() <= 64)
	var path := NavigationServer3D.map_get_path(held.map, Vector3(10, 0, 10), Vector3(40, 0, 10), true)
	assert_almost_eq(path[-1], Vector3(40, 0, 10), Vector3.ONE * 0.001)

func test_exceptional_fallback_borrows_map_without_rebuilding_or_freeing_world() -> void:
	var route = _navigation.get_movement_route(_map, Vector3(10, 0, 10), Vector3(650, 0, 650), 2)
	assert_eq(route.map, _map)
	assert_false(route.owns_map)
	route = null
	assert_eq(NavigationServer3D.map_get_regions(_map).size(), 3)

func test_different_route_views_still_produce_mutual_avoidance() -> void:
	var actors: Array[WorldActor] = []
	for i in range(2):
		var actor := QuietActor.new()
		actor.position = Vector3(31.5 + i, 0, 16)
		_root.add_child(actor)
		actor._navigation_agent.avoidance_enabled = true
		actor.set_move_target(Vector3(50 if i == 0 else 10, 0, 16))
		actor._navigation_agent.get_move_direction(0.016)
		actors.append(actor)
	assert_ne(actors[0]._navigation_agent.get_navigation_map(), actors[1]._navigation_agent.get_navigation_map())
	for tick in range(5):
		for i in range(2):
			actors[i]._navigation_agent.velocity = Vector3(3 if i == 0 else -3, 0, 0)
		await get_tree().physics_frame
	await get_tree().process_frame
	for i in range(2):
		var agent = actors[i]._navigation_agent
		assert_true(agent.has_safe_velocity)
		assert_true(agent.safe_velocity.distance_to(Vector3(3 if i == 0 else -3, 0, 0)) > 0.01, "RVO reacts to the agent on the other local map")
		actors[i].free()
