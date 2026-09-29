extends "res://tests/validation/test_case.gd"

## Real click/held-input workflow for one and six production party characters.
## A delayed mailbox models busy navigation workers, not a fake route or motor.
## Before the repair, every changed held order discarded the usable route.
## Sustained-load regression: published paths were also discarded on every held
## update, so actors never turned until release. Exercise 32 background requests
## with ten destinations each, 220ms player tasks and 450ms background tasks.
class SlowBatch extends "res://features/core/navigation/navigation_query_jobs.gd".Batch:
	var delay_player_ms := 0
	var delay_background_ms := 0
	func run() -> void:
		OS.delay_msec(delay_player_ms if player_order else delay_background_ms)
		super.run()

class DelayedQueries extends "res://features/core/navigation/navigation_query_jobs.gd":
	var paused := false
	var delay_player_ms := 0
	var delay_background_ms := 0
	func pump() -> void:
		if not paused:
			super.pump()
	func _new_batch() -> Batch:
		var batch := SlowBatch.new()
		batch.delay_player_ms = delay_player_ms
		batch.delay_background_ms = delay_background_ms
		return batch

var _world: Node3D
var _viewport: Viewport
var _camera: Camera3D
var _dispatcher: WorldInteractionController
var _actors: Array[HumanoidCharacter] = []
var _queries: DelayedQueries
var _failures: Array[String] = []
var _completed := 0
var _command_usec: Array[int] = []
var _load_tickets: Dictionary = {}
var _load_completed := 0
var _turn_seconds: Array[float] = []
var _steering_cases := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_viewport = root
	_world = load("res://tests/validation/helpers/navigation_fixture.gd").new()
	_viewport.add_child(_world)
	current_scene = _world
	_world.add_floor(Vector3(64, 1, 48))
	for index in range(6):
		_actors.append(_world.add_actor("player.navigation.%d" % index, Vector3(-14, 0.7, -12 + index * 2)))
	if not _expect(await _world.boot(), "production navigation and bootstrap become ready"):
		quit(1)
		return
	_dispatcher = BootstrapContext.service(&"world_interaction")
	_camera = _world.get_node("CameraRig/CameraPivot/Camera3D")
	# Keep the camera fixed; drive the production held-input timer in idle, like
	# WorldInteractionController._process, not inside the actor physics loop.
	_dispatcher.set_process(false)
	_world.get_node("PartyManager").clear_followed_member()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 36.0
	_camera.global_position = Vector3(0, 30, 20)
	_camera.look_at(Vector3.ZERO)
	_queries = DelayedQueries.new()
	if _world.navigation.query_jobs != null:
		_world.navigation.query_jobs.close()
	_world.navigation.query_jobs = _queries
	set_process(true)
	for count in [1, 6]:
		await _exercise(count)
	_expect(_completed == 2, "both solo and six-character workflows complete")
	# Repeatedly complete and replenish real native background paths for more
	# than the reported 30 seconds, then steer while that load remains active.
	_queries.delay_player_ms = 220
	_queries.delay_background_ms = 450
	for index in range(32):
		_load_tickets["load:%d" % index] = 0
	await create_timer(32.0).timeout
	for count in [1, 6]:
		await _exercise_loaded_steering(count)
	_expect(_steering_cases == 8, "every solo and party turn is observed before release")
	_expect(_load_completed > 0, "background requests also complete during player load")
	for key: String in _load_tickets:
		_queries.cancel(key)
	_load_tickets.clear()
	set_process(false)
	print("PLAYER_NAVIGATION_RESULT cases=%d steering_cases=%d failures=%d command_max_usec=%d turn_max_seconds=%.3f background_completed=%d" % [_completed, _steering_cases, _failures.size(), _command_usec.max() if not _command_usec.is_empty() else 0, _turn_seconds.max() if not _turn_seconds.is_empty() else 0.0, _load_completed])
	_world.dispose()
	await process_frame
	quit(0 if _failures.is_empty() else 1)

func _process(delta: float) -> void:
	if _dispatcher == null or not is_instance_valid(_dispatcher):
		return
	var started := Time.get_ticks_usec()
	_dispatcher._process_hold_move(_dispatcher._get_unscaled_input_delta(delta))
	_command_usec.append(Time.get_ticks_usec() - started)
	if _load_tickets.is_empty():
		return
	var world := _world.get_world_3d()
	for key: String in _load_tickets:
		var ticket: int = _load_tickets[key]
		if ticket > 0:
			if _queries.take(key, ticket).is_empty():
				continue
			_load_completed += 1
		var targets := PackedVector3Array()
		for index in range(10):
			targets.append(Vector3(22, 0, -8 + index))
		_load_tickets[key] = _world.navigation.request_paths(key, world, world.navigation_map, Vector3(-22, 0, -8), targets)

func _exercise_loaded_steering(count: int) -> void:
	var subjects: Array[HumanoidCharacter] = []
	for index in range(_actors.size()):
		var actor := _actors[index]
		actor.stop_movement()
		actor.global_position = Vector3(-12 + (index % 3) * 2, 0.7, (index / 3) * 2) if index < count else Vector3(-24, 0.7, -12 + index * 2)
		if index < count:
			subjects.append(actor)
	_world.get_node("PartyManager").set_selection(subjects)
	await _world.wait_until(func(): return subjects.all(func(actor): return actor.is_on_floor()), 3.0)
	_button(Vector3(20, 0, 0), true)
	_button(Vector3(20, 0, 0), false)
	if not _expect(await _world.wait_until(func(): return subjects.all(func(actor): return actor.velocity.x > 0.5), 3.0), "loaded initial click starts every member"):
		return
	var pointer := Vector3(-6, 0, 12)
	_button(pointer, true)
	for phase in range(4):
		var sign_z := 1.0 if phase % 2 == 0 else -1.0
		var start := Time.get_ticks_msec()
		var elapsed := 0.0
		var all_turned := false
		var next_pointer := 0.0
		while elapsed < 2.0:
			await process_frame
			elapsed = float(Time.get_ticks_msec() - start) / 1000.0
			if elapsed >= next_pointer:
				pointer = Vector3(-6.0 + sin(elapsed * 5.0), 0, sign_z * 12.0)
				_move_pointer(pointer)
				next_pointer += 0.075
			if not all_turned and subjects.all(func(actor): return actor.velocity.z * sign_z > 0.5):
				all_turned = true
				_turn_seconds.append(elapsed)
				_expect(elapsed < 1.3, "all %d members respond to held turn %d within 1.3s despite imposed worker delay (%.3fs)" % [count, phase, elapsed])
		_expect(all_turned, "all %d members physically turn %d while the cursor keeps changing" % [count, phase])
		_expect(_dispatcher.is_hold_move_active and _dispatcher.is_right_mouse_down, "turn was observed before releasing held input")
		print("PLAYER_NAVIGATION_TURN actors=%d phase=%d turned=%s background_completed=%d" % [count, phase, all_turned, _load_completed])
		_steering_cases += int(all_turned)
	_button(pointer, false)
	for actor in subjects:
		actor.stop_movement()

func _exercise(count: int) -> void:
	var subjects: Array[HumanoidCharacter] = []
	_queries.paused = false
	for index in range(_actors.size()):
		var actor := _actors[index]
		actor.stop_movement()
		var angle := TAU * float(index) / float(count)
		actor.global_position = Vector3(-14, 0.7, 0) + Vector3(cos(angle), 0, sin(angle)) * 1.35 if index < count else Vector3(-20, 0.7, -12 + index * 2)
		actor.velocity = Vector3.ZERO
		if index < count:
			subjects.append(actor)
	_world.get_node("PartyManager").set_selection(subjects)
	_expect(await _world.wait_until(func(): return subjects.all(func(actor): return actor.is_on_floor()), 3.0), "subjects settle on the real floor")
	_button(Vector3(20, 0, 0), true)
	_button(Vector3(20, 0, 0), false)
	if not _expect(await _world.wait_until(func(): return subjects.all(func(actor): return _speed(actor) > 1.0 and actor._navigation_agent._target_synced), 5.0), "initial click starts every selected character"):
		return
	# Exercise ordinary worker completion as well as a deliberately busy mailbox.
	_button(Vector3(20, 0, -2), true)
	for step in range(4):
		_move_pointer(Vector3(20, 0, -2.0 + step * 0.4))
		await _measure_motion(subjects, 0.18, "held cursor normal workers")
	_expect(_dispatcher._move_group_destination.distance_to(Vector3(20, 0, -0.8)) < 0.05, "normal held input follows the changed cursor")
	_button(Vector3(20, 0, -0.8), false)
	# A real changed click must not erase motion while its route is pending.
	_queries.paused = true
	_button(Vector3(20, 0, 1), true)
	_button(Vector3(20, 0, 1), false)
	await _measure_motion(subjects, 0.3, "changed click pending")
	_queries.paused = false
	_expect(await _world.wait_until(func(): return subjects.all(func(actor): return actor._navigation_agent._target_synced), 3.0), "changed click obtains a replacement route")
	# Hold, change the cursor at the production repeat interval, and retain
	# physical motion through delayed replacement requests for the whole party.
	_button(Vector3(20, 0, 2), true)
	_queries.paused = true
	for step in range(4):
		_move_pointer(Vector3(20, 0, 2.0 + step * 0.4))
		await _measure_motion(subjects, 0.18, "held cursor changing")
	_expect(_dispatcher._move_group_destination.distance_to(Vector3(20, 0, 3.2)) < 0.05, "held cursor updates the actual destination")
	_queries.paused = false
	_expect(await _world.wait_until(func(): return subjects.all(func(actor): return actor._navigation_agent._target_synced), 3.0), "latest held order obtains a route")
	var serial := _queries._serial
	await _measure_motion(subjects, 0.5, "held cursor unchanged")
	_expect(_queries._serial == serial, "unchanged held input does not request more routes")
	_button(Vector3(20, 0, 3.2), false)
	_expect(not _dispatcher.is_hold_move_active, "button release ends held input")
	# Reverse through a fresh click; a late old route must never win.
	_button(Vector3(-18, 0, 0), true)
	_button(Vector3(-18, 0, 0), false)
	_expect(await _world.wait_until(func(): return subjects.all(func(actor): return actor.velocity.x < -0.5), 3.0), "all characters turn toward the newest click")
	# Stop while a different route is still pending, then let it complete.
	_queries.paused = true
	_button(Vector3(16, 0, -4), true)
	_button(Vector3(16, 0, -4), false)
	await physics_frame
	var stopped: Array[Vector3] = []
	for actor in subjects:
		actor.stop_movement()
		stopped.append(actor.global_position)
	_queries.paused = false
	await create_timer(0.35).timeout
	for index in range(subjects.size()):
		var actor := subjects[index]
		_expect(not actor.has_move_target() and _speed(actor) < 0.05 and actor.global_position.distance_to(stopped[index]) < 0.1, "stop survives late worker completion for actor %d" % index)
	# Complete another ordinary command to prove cancellation did not poison
	# subsequent orders. Record each member's own projected formation target.
	var destination := subjects[0].global_position + Vector3(5, 0, 0)
	destination.y = 0.0
	_button(destination, true)
	_button(destination, false)
	var targets: Array[Vector3] = []
	for actor in subjects:
		targets.append(actor.get_move_target())
	_expect(await _world.wait_until(func(): return subjects.all(func(actor): return not actor.has_move_target()), 8.0), "all selected characters finish the final move")
	for index in range(subjects.size()):
		var offset := subjects[index].global_position - targets[index]
		_expect(Vector2(offset.x, offset.z).length() <= subjects[index].navigation_target_desired_distance + 0.05, "actor %d physically arrives at its own target" % index)
	_completed += 1

func _measure_motion(subjects: Array[HumanoidCharacter], seconds: float, label: String) -> void:
	var elapsed := 0.0
	var minimum_speed := INF
	var starting: Array[Vector3] = []
	for actor in subjects:
		starting.append(actor.global_position)
	while elapsed < seconds:
		await physics_frame
		var delta := get_physics_process_delta_time()
		elapsed += delta
		for actor in subjects:
			minimum_speed = minf(minimum_speed, _speed(actor))
	_expect(minimum_speed > 0.5, "%s: movement must continue, minimum speed=%s" % [label, minimum_speed])
	for index in range(subjects.size()):
		_expect(subjects[index].global_position.distance_to(starting[index]) > seconds * 0.5, "%s: actor %d physically advances" % [label, index])
	print("PLAYER_NAVIGATION_MOTION actors=%d phase=%s min_speed=%.3f elapsed=%.3f" % [subjects.size(), label, minimum_speed, elapsed])

func _move_pointer(point: Vector3) -> Vector2:
	var screen := _camera.unproject_position(point)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = _viewport.get_screen_transform() * screen
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT if _dispatcher.is_right_mouse_down else 0
	# Headless Windows read Input's emulated pointer. push_input alone routes
	# the event but leaves that pointer unchanged, breaking held cursor picking.
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	_expect(_viewport.get_mouse_position().distance_to(screen) < 0.1, "injected cursor reaches requested world point")
	return screen

func _button(point: Vector3, pressed: bool) -> void:
	var screen := _move_pointer(point)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT if pressed else 0
	event.position = screen
	event.global_position = screen
	var started := Time.get_ticks_usec()
	_viewport.push_input(event, true)
	_command_usec.append(Time.get_ticks_usec() - started)
	_expect(_dispatcher.is_right_mouse_down == pressed, "production input receives right-button state")

func _speed(actor: CharacterBody3D) -> float:
	return Vector2(actor.velocity.x, actor.velocity.z).length()

func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failures.append(message)
		push_error(message)
	return condition
