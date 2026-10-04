extends GutTest

const JOBS_PATH := "res://features/core/navigation/navigation_query_jobs.gd"
const JOBS = preload(JOBS_PATH)

class HeldBatch extends JOBS.Batch:
	var gate: Semaphore
	func run() -> void:
		gate.wait()
		super.run()

class HeldJobs extends JOBS:
	var gate := Semaphore.new()
	func _new_batch() -> Batch:
		var batch := HeldBatch.new()
		batch.gate = gate
		return batch
var _world: World3D
var _region: RID
var _jobs: RefCounted

func before_each() -> void:
	_world = World3D.new()
	var map := _world.navigation_map
	NavigationServer3D.map_set_use_async_iterations(map, false)
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-8, 0, -8), Vector3(-8, 0, 8), Vector3(8, 0, 8), Vector3(8, 0, -8)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_use_async_iterations(_region, false)
	NavigationServer3D.region_set_navigation_mesh(_region, mesh)
	NavigationServer3D.region_set_map(_region, map)
	NavigationServer3D.map_set_active(map, true)
	NavigationServer3D.map_force_update(map)
	if ResourceLoader.exists(JOBS_PATH):
		_jobs = load(JOBS_PATH).new()

func after_each() -> void:
	if _jobs != null:
		_jobs.close()
	_jobs = null
	NavigationServer3D.free_rid(_region)
	_world = null

func _request(destination: Vector3) -> Dictionary:
	return {"world": _world, "map": _world.navigation_map, "iteration": NavigationServer3D.map_get_iteration_id(_world.navigation_map), "start": Vector3(-4, 0, 0), "targets": PackedVector3Array([destination]), "layers": 1}

func _result(key: String, ticket: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		_jobs.pump()
		var result: Dictionary = _jobs.take(key, ticket)
		if not result.is_empty():
			return result
		await get_tree().process_frame
	fail_test("Worker navigation did not finish within two seconds")
	return {}

func test_route_calculation_runs_off_main_thread_and_preserves_native_endpoint() -> void:
	assert_not_null(_jobs, "The production navigation job queue must exist")
	if _jobs == null:
		return
	var ticket: int = _jobs.submit("actor:move", _request(Vector3(4, 0, 0)))
	assert_gt(ticket, 0)
	var result := await _result("actor:move", ticket)
	assert_false(result.is_empty())
	if result.is_empty():
		return
	assert_ne(result.worker_thread, OS.get_thread_caller_id(), "Navigation must execute on a worker, not the frame thread")
	var path: PackedVector3Array = result.paths[0]
	assert_false(path.is_empty(), "The connected fixture must produce a route")
	if path.is_empty():
		return
	assert_almost_eq(path[0], Vector3(-4, 0, 0), Vector3.ONE * 0.001)
	assert_almost_eq(path[-1], Vector3(4, 0, 0), Vector3.ONE * 0.001)

func test_frame_poll_does_not_wait_for_unfinished_work_and_old_command_cannot_return() -> void:
	_jobs.close()
	_jobs = HeldJobs.new()
	_jobs.worker_limit = 1
	var first: int = _jobs.submit("actor:move", _request(Vector3(4, 0, 0)))
	_jobs.pump()
	_jobs.pump() # A blocking join here deadlocks: the worker is deliberately held.
	assert_true(_jobs.take("actor:move", first).is_empty())
	var replacement: int = _jobs.submit("actor:move", _request(Vector3(0, 0, 4)))
	_jobs.gate.post()
	_jobs.gate.post()
	var result := await _result("actor:move", replacement)
	assert_true(_jobs.take("actor:move", first).is_empty(), "Replaced commands never publish")
	assert_almost_eq(result.paths[0][-1], Vector3(0, 0, 4), Vector3.ONE * 0.001)

func test_queue_coalesces_commands_and_refuses_unbounded_new_actors() -> void:
	_jobs.capacity = 2
	for index in range(20):
		assert_gt(_jobs.submit("same", _request(Vector3(index * 0.1, 0, 4))), 0)
	assert_eq(_jobs._pending.size(), 1)
	assert_gt(_jobs.submit("second", _request(Vector3.ZERO)), 0)
	assert_eq(_jobs.submit("third", _request(Vector3.ZERO)), 0)
	_jobs.cancel("same")
	assert_gt(_jobs.submit("third", _request(Vector3.ZERO)), 0)

func test_player_request_starts_while_background_workers_are_busy() -> void:
	_jobs.close()
	_jobs = HeldJobs.new()
	for index in range(16):
		_jobs.submit("combat:%d" % index, _request(Vector3(4, 0, index * 0.1)))
	_jobs.pump()
	var request := _request(Vector3(0, 0, 4))
	request.player_order = true
	var ticket: int = _jobs.submit("player", request)
	_jobs.pump()
	var player_started := false
	for batch in _jobs._active:
		for entry in batch.requests:
			if entry.key == "player" and entry.ticket == ticket:
				player_started = true
	# Always release test-owned workers, even when the assertion is red.
	for index in range(32):
		_jobs.gate.post()
	assert_true(player_started, "A player's route must not wait behind busy combat batches")
	assert_false((await _result("player", ticket)).is_empty())

func test_multi_target_request_yields_between_bounded_path_batches() -> void:
	_jobs.close()
	_jobs = HeldJobs.new()
	_jobs.worker_limit = 1
	_jobs.batch_size = 3
	var targets := PackedVector3Array()
	for index in range(7):
		targets.append(Vector3(4, 0, index * 0.5))
	var request := _request(targets[0])
	request.targets = targets
	var ticket: int = _jobs.submit("many", request)
	_jobs.pump()
	var batch = _jobs._active[0]
	var path_count := 0
	for entry in batch.requests:
		path_count += entry.request.targets.size()
	assert_lte(path_count, 3, "The batch limit counts native path targets, not actor envelopes")
	_jobs.gate.post()
	var deadline := Time.get_ticks_msec() + 2000
	while not WorkerThreadPool.is_task_completed(batch.task_id) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_true(WorkerThreadPool.is_task_completed(batch.task_id))
	_jobs.pump()
	assert_false(_jobs._ready.has("many"), "Do not publish a partial candidate array")
	for index in range(16):
		_jobs.gate.post()
	var result := await _result("many", ticket)
	assert_eq(result.paths.size(), targets.size())
	for index in targets.size():
		assert_almost_eq(result.paths[index][-1], targets[index], Vector3.ONE * 0.001,
			"Chunking preserves candidate order and every endpoint")

func test_npc_route_starts_while_position_searches_are_busy_without_taking_player_lane() -> void:
	_jobs.close()
	_jobs = HeldJobs.new()
	for index in range(40):
		var positions := _request(Vector3(4, 0, 0))
		positions.targets = PackedVector3Array([Vector3(4, 0, 0), Vector3(4, 0, 1), Vector3(4, 0, 2), Vector3(4, 0, 3)])
		_jobs.submit("position:%d" % index, positions)
	_jobs.pump()
	var pursuit := _request(Vector3(0, 0, 4))
	pursuit.movement_route = true
	var npc_ticket: int = _jobs.submit("npc", pursuit)
	_jobs.pump()
	var player := _request(Vector3(0, 0, -4))
	player.player_order = true
	var player_ticket: int = _jobs.submit("player", player)
	_jobs.pump()
	var started: Array[String] = []
	for batch in _jobs._active:
		for entry in batch.requests:
			started.append(entry.key)
	# Always release held workers, including on the expected RED.
	for index in range(100):
		_jobs.gate.post()
	assert_has(started, "npc", "An NPC's actual route must start before busy position searches finish")
	assert_has(started, "player", "NPC pursuit must not occupy the player's reserved lane")
	assert_false((await _result("npc", npc_ticket)).is_empty())
	assert_false((await _result("player", player_ticket)).is_empty())

func test_position_search_gets_next_free_lane_during_a_movement_backlog() -> void:
	_jobs.close()
	_jobs = HeldJobs.new()
	_jobs.batch_size = 1
	for index in range(20):
		var request := _request(Vector3(4, 0, 0))
		request.movement_route = true
		_jobs.submit("route:%d" % index, request)
	_jobs.pump()
	var ticket: int = _jobs.submit("position", _request(Vector3(0, 0, 4)))
	_jobs.gate.post()
	var started := false
	var deadline := Time.get_ticks_msec() + 2000
	while not started and Time.get_ticks_msec() < deadline:
		_jobs.pump()
		for batch in _jobs._active:
			for entry in batch.requests:
				started = started or entry.key == "position"
		await get_tree().process_frame
	for index in range(32):
		_jobs.gate.post()
	assert_true(started, "Pursuit may borrow idle lanes, but cannot starve fighting-position searches")
	assert_false((await _result("position", ticket)).is_empty())

func test_single_background_lane_alternates_movement_and_position_work() -> void:
	for workers in [1, 2]:
		_jobs.close()
		_jobs = HeldJobs.new()
		_jobs.worker_limit = workers
		_jobs.batch_size = 1
		for index in range(4):
			var request := _request(Vector3(4, 0, 0))
			request.movement_route = true
			_jobs.submit("route:%d" % index, request)
		var ticket: int = _jobs.submit("position", _request(Vector3(0, 0, 4)))
		_jobs.pump()
		var first = _jobs._active[0]
		var first_is_movement: bool = first.movement_route
		_jobs.gate.post()
		var deadline := Time.get_ticks_msec() + 2000
		while not WorkerThreadPool.is_task_completed(first.task_id) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var first_completed := WorkerThreadPool.is_task_completed(first.task_id)
		_jobs.pump()
		var next_is_position: bool = _jobs._active.size() == 1 and not _jobs._active[0].movement_route
		for index in range(16):
			_jobs.gate.post()
		assert_true(first_completed)
		assert_true(first_is_movement)
		assert_true(next_is_position, "A small worker configuration must not drain the route backlog before positioning")
		assert_false((await _result("position", ticket)).is_empty())

func test_player_path_finishes_before_global_background_pool_is_released() -> void:
	# Fill Godot's low-priority allowance with unrelated work. Being admitted to
	# our own active list must also mean player work can actually start in Godot.
	var gate := Semaphore.new()
	var background: Array[int] = []
	var count := maxi(OS.get_processor_count(), int(ProjectSettings.get_setting("threading/worker_pool/max_threads", -1)))
	for index in range(count):
		background.append(WorkerThreadPool.add_task(gate.wait, false, "TestBackgroundGate"))
	var request := _request(Vector3(0, 0, 4))
	request.player_order = true
	var ticket: int = _jobs.submit("player", request)
	var result := {}
	var deadline := Time.get_ticks_msec() + 500
	while result.is_empty() and Time.get_ticks_msec() < deadline:
		_jobs.pump()
		result = _jobs.take("player", ticket)
		await get_tree().process_frame
	# Release every test task before assertions, including the expected red run.
	for index in range(count):
		gate.post()
	for task in background:
		WorkerThreadPool.wait_for_task_completion(task)
	assert_false(result.is_empty(), "Player path must finish while low-priority background tasks remain blocked")
	if not result.is_empty():
		assert_almost_eq(result.paths[0][-1], Vector3(0, 0, 4), Vector3.ONE * 0.001)

func test_removed_actor_cannot_receive_results_after_same_id_is_realized_again() -> void:
	var old: int = _jobs.submit("persistent-actor", _request(Vector3(4, 0, 0)))
	_jobs.pump()
	_jobs.cancel("persistent-actor")
	var fresh: int = _jobs.submit("persistent-actor", _request(Vector3(0, 0, 4)))
	var result := await _result("persistent-actor", fresh)
	assert_true(_jobs.take("persistent-actor", old).is_empty())
	assert_almost_eq(result.paths[0][-1], Vector3(0, 0, 4), Vector3.ONE * 0.001)

func test_map_changed_during_query_is_returned_as_obsolete_not_accepted() -> void:
	var ticket: int = _jobs.submit("move", _request(Vector3(4, 0, 0)))
	NavigationServer3D.region_set_enabled(_region, false)
	NavigationServer3D.map_force_update(_world.navigation_map)
	var result := await _result("move", ticket)
	assert_ne(result.iteration, NavigationServer3D.map_get_iteration_id(_world.navigation_map), "Consumers must reject a result from a different map revision")

class QuietActor extends WorldActor:
	func _enter_tree() -> void: pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		navigation_path_height_offset = 0.0
		_navigation_agent.configure()

func _long_route_fixture() -> WorldNavigationController:
	# Synthetic corridor: gameplay navigation must not depend on World1.
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	for x in range(4301):
		vertices.append(Vector3(x, 0, 0))
		vertices.append(Vector3(x, 0, 1))
	mesh.vertices = vertices
	for x in range(4300):
		mesh.add_polygon(PackedInt32Array([x * 2, x * 2 + 1, x * 2 + 3, x * 2 + 2]))
	NavigationServer3D.region_set_navigation_mesh(_region, mesh)
	NavigationServer3D.map_force_update(_world.navigation_map)
	var viewport := SubViewport.new()
	viewport.world_3d = _world
	add_child(viewport)
	var navigation := WorldNavigationController.new()
	navigation.settings = WorldNavigationSettings.new()
	navigation.query_jobs = _jobs
	viewport.add_child(navigation)
	navigation.set_process(false)
	return navigation

func test_movement_route_can_cross_more_than_default_4096_polygons() -> void:
	var navigation := _long_route_fixture()
	var finish := Vector3(4299.5, 0, 0.5)
	var ticket := navigation.request_paths("long-move", _world, _world.navigation_map, Vector3(0.5, 0, 0.5), PackedVector3Array([finish]), 1, true, true)
	assert_gt(ticket, 0)
	var result := await _result("long-move", ticket)
	assert_false(result.is_empty())
	if not result.is_empty():
		var path: PackedVector3Array = result.paths[0]
		assert_false(path.is_empty())
		if not path.is_empty():
			assert_almost_eq(path[-1], finish, Vector3.ONE * 0.001, "An accepted move must not be clipped at the tactical search budget")
	navigation.get_parent().queue_free()
	await get_tree().process_frame

func test_native_agent_fallback_can_cross_more_than_default_4096_polygons() -> void:
	var navigation := _long_route_fixture()
	navigation.settings.threaded_queries_enabled = false
	var actor := QuietActor.new()
	actor.position = Vector3(0.5, 0, 0.5)
	navigation.get_parent().add_child(actor)
	var finish := Vector3(4299.5, 0, 0.5)
	actor.set_move_target(finish)
	await get_tree().physics_frame
	actor._navigation_agent.get_move_direction(0.016)
	assert_almost_eq(actor._navigation_agent.get_final_position(), finish, Vector3.ONE * 0.001, "Turning worker queries off must not truncate the same move")
	navigation.get_parent().queue_free()
	await get_tree().process_frame

func test_movement_budget_is_bounded_configurable_and_not_used_for_tactics() -> void:
	var navigation := _long_route_fixture()
	var finish := Vector3(4299.5, 0, 0.5)
	for scenario in [
		{"movement": false, "player": true, "budget": 65536, "reaches": false},
		{"movement": true, "player": false, "budget": 65536, "reaches": true},
		{"movement": true, "player": true, "budget": 4096, "reaches": false},
		{"movement": true, "player": true, "budget": 0, "reaches": false},
	]:
		navigation.settings.movement_path_max_polygons = scenario.budget
		var ticket := navigation.request_paths("budget", _world, _world.navigation_map, Vector3(0.5, 0, 0.5), PackedVector3Array([finish]), 1, scenario.player, scenario.movement)
		var result := await _result("budget", ticket)
		assert_false(result.is_empty())
		if not result.is_empty():
			var path: PackedVector3Array = result.paths[0]
			assert_eq(not path.is_empty() and path[-1].distance_to(finish) < 0.001, scenario.reaches, str(scenario))
	navigation.get_parent().queue_free()
	await get_tree().process_frame
