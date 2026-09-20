extends SceneTree

## Real PartyMember movement and Godot RVO, including native navigation_finished
## before body arrival. No fake steering callbacks or stair-specific rules.
## -- --benchmark measures only process_world_actor_movement: 24 actors, 600
## physics frames, alternating 16 m routes, with the same map and workload.
## Reference (taskset -c 8,9, --fixed-fps 60; three runs each): median batch
## mean/p95 before extraction = 1331.07/1938 us, after = 1028.00/1282 us.
## Each run made 14,400 movement calls and completed 48 routes.
const ACTOR_PATH := "res://features/core/party/party_member.tscn"
const BENCHMARK_ACTORS := 24
const BENCHMARK_FRAMES := 600
var _failures: Array[String] = []
var _completed_cases := 0


func _initialize() -> void:
	# PartyMember depends on GECS autoloads; do not preload it in a SceneTree script.
	call_deferred("_run")


func _run() -> void:
	if OS.get_cmdline_user_args().has("--benchmark"):
		await _benchmark()
	else:
		await _arrival("normal", 0.0, false)
		await _arrival("early_native_finish", 0.3, true)
		await _stop_and_replace(false)
		await _stop_and_replace(true)
		await _unreachable()
		await _stuck()
		await _destruction()
		await _settings_and_authority()
		_expect(_completed_cases == 8, "All eight cases must complete without script errors")
	for failure in _failures:
		push_error(failure)
	print("ACTOR_NAVIGATION %s cases=%d failures=%d" % ["OK" if _failures.is_empty() else "FAILED", _completed_cases, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _fixture(nav_height: float, half_size: float = 10.0) -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half_size * 2.0, 0.2, half_size * 2.0)
	floor_shape.shape = box
	floor_body.position.y = -0.1
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-half_size, nav_height, -half_size), Vector3(half_size, nav_height, -half_size), Vector3(half_size, nav_height, half_size), Vector3(-half_size, nav_height, half_size)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = mesh
	world.add_child(region)
	var map := world.get_world_3d().navigation_map
	var previous_iteration := NavigationServer3D.map_get_iteration_id(map)
	for frame in range(120):
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > previous_iteration:
			return world
	_expect(false, "Navigation map did not synchronize within 120 physics frames")
	return world


func _actor(world: Node3D, position := Vector3(0, -0.39, 0)) -> CharacterBody3D:
	var actor: CharacterBody3D = load(ACTOR_PATH).instantiate()
	actor.position = position
	world.add_child(actor)
	return actor


func _arrival(label: String, nav_height: float, require_early_finish: bool) -> void:
	var world := await _fixture(nav_height)
	var actor := _actor(world)
	var agent := actor.get_node("NavigationAgent3D") as NavigationAgent3D
	var target := Vector3(4, nav_height, 0)
	var early_finish := [false]
	agent.navigation_finished.connect(func():
		if actor.has_move_target() and _distance(actor, target) > actor.navigation_target_desired_distance:
			early_finish[0] = true
	)
	actor.set_move_target(target)
	var frames := await _wait_for_stop(actor, 600)
	_expect(not actor.has_move_target() and _distance(actor, target) <= actor.navigation_target_desired_distance, label + " must reach the body's arrival tolerance")
	_expect(not require_early_finish or early_finish[0], label + " must exercise native finish outside body tolerance")
	_expect(agent.avoidance_enabled, label + " must retain avoidance through arrival")
	_expect(not actor.has_active_player_order() and actor.get_current_order_type() == 0, label + " must release the move order")
	print("NAVIGATION_ARRIVAL %s frames=%d distance=%.4f early_native_finish=%s" % [label, frames, _distance(actor, target), early_finish[0]])
	await _dispose(world)
	_completed_cases += 1


func _stop_and_replace(after_native_finish: bool) -> void:
	var world := await _fixture(0.3)
	var actor := _actor(world)
	var agent := actor.get_node("NavigationAgent3D") as NavigationAgent3D
	var native_finished := [false]
	var safe_velocity := [Vector3.INF]
	agent.navigation_finished.connect(func(): native_finished[0] = true)
	agent.velocity_computed.connect(func(value: Vector3): safe_velocity[0] = value)
	actor.set_move_target(Vector3(4, 0.3, 0))
	for frame in range(600 if after_native_finish else 20):
		await physics_frame
		if after_native_finish and native_finished[0]:
			break
	_expect(actor.has_move_target(), "Stop must interrupt an active movement target")
	_expect(not after_native_finish or native_finished[0], "Stop must exercise native finished state")
	actor.stop_movement()
	var stopped_position := actor.global_position
	for frame in range(8):
		await physics_frame
	_expect(_distance(actor, stopped_position) < 0.001 and actor.velocity.length_squared() < 0.001, "Stop must hold the body still")
	_expect(safe_velocity[0].length_squared() < 0.001, "Stop must submit zero to RVO even after native finish")
	_expect(not actor.has_active_player_order() and actor.get_current_order_type() == 0, "Stop must release the move order")
	var replacement := Vector3(-4, 0.3, 0)
	actor.set_move_target(replacement)
	await _wait_for_stop(actor, 600)
	_expect(not actor.has_move_target() and _distance(actor, replacement) <= actor.navigation_target_desired_distance, "Replacement target must arrive without stale avoidance velocity")
	_expect(agent.avoidance_enabled, "Interrupting a route must not disable avoidance")
	print("NAVIGATION_STOP_REPLACE native_finished=%s distance=%.4f" % [after_native_finish, _distance(actor, replacement)])
	await _dispose(world)
	_completed_cases += 1


func _unreachable() -> void:
	var world := await _fixture(0.0)
	var actor := _actor(world)
	actor.set_move_target(Vector3(20, 0, 0))
	var frames := await _wait_for_stop(actor, 120)
	_expect(not actor.has_move_target() and actor.position.x < 1.0, "Partial path outside reachability tolerance must fail, not walk off mesh")
	_expect(not actor.has_active_player_order() and actor.get_current_order_type() == 0, "Unreachable path must release the move order")
	# The next valid command must reset the failed path/query state.
	actor.set_move_target(Vector3(4, 0, 0))
	await _wait_for_stop(actor, 600)
	_expect(not actor.has_move_target() and _distance(actor, Vector3(4, 0, 0)) <= actor.navigation_target_desired_distance, "Valid target after unreachable path must arrive")
	print("NAVIGATION_UNREACHABLE frames=%d recovery_distance=%.4f" % [frames, _distance(actor, Vector3(4, 0, 0))])
	await _dispose(world)
	_completed_cases += 1


func _stuck() -> void:
	var world := await _fixture(0.0)
	# Deliberately stale nav data crossing solid collision exercises real retries.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 3, 20)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(1, 1.5, 0)
	world.add_child(wall)
	var actor := _actor(world)
	var agent := actor.get_node("NavigationAgent3D") as NavigationAgent3D
	var paths := [0]
	agent.path_changed.connect(func(): paths[0] += 1)
	var target := Vector3(4, 0, 0)
	actor.set_move_target(target)
	var frames := 0
	for frame in range(1500):
		await physics_frame
		frames = frame + 1
		if not actor.has_move_target():
			break
		# Interaction approaches refresh the same target; this must not reset retries.
		actor._set_actor_move_target(target)
	_expect(not actor.has_move_target() and actor.position.x < 1.0, "Blocked route must terminate within its repath budget")
	_expect(paths[0] > 1, "Stuck route must try repathing before failing")
	# Native path_changed also fires on engine-driven refreshes, not only retries.
	var frame_budget: int = int((actor.stuck_repath_attempt_limit + 1) * actor.stuck_check_seconds * Engine.physics_ticks_per_second) + 120
	_expect(frames <= frame_budget, "Repeated identical targets must not extend the authored stuck budget")
	print("NAVIGATION_STUCK frames=%d paths=%d position=%s" % [frames, paths[0], actor.position])
	await _dispose(world)
	_completed_cases += 1


func _destruction() -> void:
	var world := await _fixture(0.3)
	var actor := _actor(world)
	actor.set_move_target(Vector3(4, 0.3, 0))
	for frame in range(20):
		await physics_frame
	var agent := actor.get_node("NavigationAgent3D") as NavigationAgent3D
	var rid := agent.get_rid()
	actor.queue_free()
	for frame in range(3):
		await physics_frame
	_expect(not is_instance_valid(actor) and not is_instance_valid(agent), "Destroying the actor must destroy its navigation agent")
	_expect(not NavigationServer3D.map_get_agents(world.get_world_3d().navigation_map).has(rid), "Destroyed actor must unregister from RVO")
	var replacement := _actor(world)
	replacement.set_move_target(Vector3(4, 0.3, 0))
	await _wait_for_stop(replacement, 600)
	_expect(not replacement.has_move_target() and _distance(replacement, Vector3(4, 0.3, 0)) <= replacement.navigation_target_desired_distance, "New actor after destruction must navigate normally")
	# Scene instances may also be discarded before ever entering the tree.
	var orphan_count := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var never_entered: Node = load(ACTOR_PATH).instantiate()
	never_entered.free()
	_expect(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == orphan_count, "Discarding an unmounted actor must not leak navigation nodes")
	print("NAVIGATION_DESTRUCTION freed=true replacement_distance=%.4f" % _distance(replacement, Vector3(4, 0.3, 0)))
	await _dispose(world)
	_completed_cases += 1


func _settings_and_authority() -> void:
	var world := await _fixture(0.0)
	var actor: CharacterBody3D = load(ACTOR_PATH).instantiate()
	actor.position = Vector3(0, -0.39, 0)
	actor.navigation_agent_radius = 0.52
	actor.navigation_neighbor_distance = 3.1
	actor.navigation_target_desired_distance = 0.4
	actor.stuck_check_seconds = 1.7
	world.add_child(actor)
	actor.set_physics_process(false)
	var agent := actor.get_node("NavigationAgent3D") as NavigationAgent3D
	_expect(is_equal_approx(agent.radius, actor.navigation_agent_radius) and is_equal_approx(agent.neighbor_distance, actor.navigation_neighbor_distance), "Agent must use the actor's authored RVO settings")
	_expect(is_equal_approx(agent.target_desired_distance, actor.navigation_target_desired_distance) and not agent.simplify_path, "Agent must preserve authored arrival distance and unsimplified paths")
	actor.set_move_target(Vector3(4, 0, 0))
	actor.set_system_movement_bridge(0, true, Vector3(-4, 0, 0), Vector3(-1, 0, 0), Vector3(-4, 0, 0), false, 0)
	for frame in range(20):
		await physics_frame
		actor.process_world_actor_movement(1.0 / 60.0)
	_expect(actor.position.x > 0.1, "Player navigation order must outrank combat movement")
	actor.set_active_player_order(false)
	actor.process_world_actor_movement(1.0 / 60.0)
	_expect(is_equal_approx(actor.velocity.x, -1.0), "Combat must resume when player authority is released")
	actor.set_system_movement_bridge(0, false, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, false, 0)
	# Replace the live target without an intervening stop; no stale route may win.
	actor.navigation_target_desired_distance = 0.35
	actor.set_move_target(Vector3(-4, 0, 0))
	actor.set_physics_process(true)
	await _wait_for_stop(actor, 600)
	_expect(not actor.has_move_target() and _distance(actor, Vector3(-4, 0, 0)) <= actor.navigation_target_desired_distance, "Live retarget and arrival-setting changes must use the original actor properties")
	_expect(is_equal_approx(agent.target_desired_distance, actor.navigation_target_desired_distance), "Native target tolerance must track the actor setting")
	var interaction = actor.get_interaction()
	interaction.current_order_type = interaction.ORDER_TYPE_MINE
	actor._set_actor_move_target(Vector3(4, 0, 0))
	_expect(actor.get("_has_move_target") and actor.get("_move_target") == actor.get_move_target(), "Reflection aliases must expose the single target state")
	actor._clear_actor_move_target()
	_expect(not actor.has_move_target() and interaction.current_order_type == interaction.ORDER_TYPE_MINE, "Internal navigation cancellation must not clear a productive work order")
	actor.stop_movement()
	# Real quadbot _ready changes move_speed before calling WorldActor._ready.
	var robot: CharacterBody3D = load("res://features/actors/projection/quadbot/quadbot_character.gd").new()
	world.add_child(robot)
	robot.set_process(false)
	robot.set_physics_process(false)
	var robot_agent := robot.get_node("NavigationAgent3D") as NavigationAgent3D
	_expect(is_equal_approx(robot_agent.max_speed, robot.move_speed), "Agent configuration must follow subclass ready defaults")
	robot._set_navigation_avoidance_enabled(false)
	_expect(not robot_agent.avoidance_enabled, "Quadbot's existing direct-child avoidance hook must still work")
	robot._set_navigation_avoidance_enabled(true)
	_expect(robot_agent.avoidance_enabled, "Quadbot must restore avoidance through its existing hook")
	print("NAVIGATION_SETTINGS_AUTHORITY retarget_distance=%.4f robot_speed=%.2f" % [_distance(actor, Vector3(-4, 0, 0)), robot_agent.max_speed])
	await _dispose(world)
	_completed_cases += 1


func _benchmark() -> void:
	var world := await _fixture(0.0, 30.0)
	var actors: Array[CharacterBody3D] = []
	for index in range(BENCHMARK_ACTORS):
		var actor := _actor(world, Vector3(-8, -0.39, (index - (BENCHMARK_ACTORS - 1) * 0.5) * 1.5))
		actor.set_physics_process(false)
		actor.set_move_target(Vector3(8, 0, actor.position.z))
		actors.append(actor)
	var samples: Array[int] = []
	var arrivals := 0
	# Warm up 60 frames, then measure identical production movement calls only.
	for frame in range(BENCHMARK_FRAMES + 60):
		await physics_frame
		for actor in actors:
			if not actor.has_move_target():
				arrivals += 1
				actor.set_move_target(Vector3(-8 if actor.position.x > 0 else 8, 0, actor.position.z))
		var started := Time.get_ticks_usec()
		for actor in actors:
			actor.process_world_actor_movement(1.0 / 60.0)
		if frame >= 60:
			samples.append(Time.get_ticks_usec() - started)
	samples.sort()
	var total := 0
	for sample in samples:
		total += sample
	_expect(arrivals > 0, "Benchmark must exercise completed and replaced routes")
	print("NAVIGATION_TIMING actors=%d frames=%d calls=%d total_us=%d mean_frame_us=%.2f p95_frame_us=%d arrivals=%d" % [BENCHMARK_ACTORS, samples.size(), BENCHMARK_ACTORS * samples.size(), total, float(total) / samples.size(), samples[int(samples.size() * 0.95)], arrivals])
	await _dispose(world)


func _wait_for_stop(actor: CharacterBody3D, limit: int) -> int:
	for frame in range(limit):
		await physics_frame
		if not actor.has_move_target():
			return frame + 1
	return limit


func _distance(actor: Node3D, target: Vector3) -> float:
	return Vector2(actor.position.x - target.x, actor.position.z - target.z).length()


func _dispose(world: Node) -> void:
	world.queue_free()
	await physics_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
