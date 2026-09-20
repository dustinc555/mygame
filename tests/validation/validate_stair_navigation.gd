extends "res://tests/validation/test_case.gd"

## Controlled multilevel fixture with the production stair asset and baker.
## Preserves direct ascent/descent, off-center approaches and real single/group
## right-click floor picking without mutable towns or a deprecated bar shell.
const STAIRS := "res://scenes/building_pieces/quaternius/medieval_village_woodbrick/stair_interior_simple.tscn"
var _world: Node3D
var _actors: Array[HumanoidCharacter] = []
var _camera: Camera3D
var _dispatcher: WorldInteractionController
var _failures: Array[String] = []
var _completed := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_run.call_deferred()

func _run() -> void:
	_world = load("res://tests/validation/helpers/navigation_fixture.gd").new()
	root.add_child(_world)
	current_scene = _world
	_world.add_floor(Vector3(48, 1, 48))
	var lower: Node3D = load(STAIRS).instantiate()
	_world.add_child(lower)
	# Use the stair currently installed in the large wood hall tower. Snap
	# markers define floor heights. Landings start AT each upper endpoint;
	# overlapping a thick slab into the incline creates an artificial step.
	var lower_top: Vector3 = lower.get_node("SnapPoints/Top").global_position
	_world.add_floor(Vector3(8, 0.2, 3), Vector3(2, lower_top.y - 0.1, lower_top.z - 1.5))
	var upper: Node3D = load(STAIRS).instantiate()
	upper.position = Vector3(4, lower_top.y, lower_top.z)
	upper.rotation.y = PI
	_world.add_child(upper)
	var upper_top: Vector3 = upper.get_node("SnapPoints/Top").global_position
	_world.add_floor(Vector3(5, 0.2, 3), Vector3(4, upper_top.y - 0.1, upper_top.z + 1.5))
	_actors.append(_world.add_actor("stairs.mira", Vector3(-0.7, 0.7, -6)))
	_actors.append(_world.add_actor("stairs.tomas", Vector3(0.7, 0.7, -6)))
	_expect(await _world.boot(), "real stair bake and bootstrap must settle")
	_camera = _world.get_node("CameraRig/CameraPivot/Camera3D")
	_dispatcher = BootstrapContext.service(&"world_interaction")
	_dispatcher.set_process(false)
	var low := Vector3(0, 0.1, 1.2)
	var middle := Vector3(0, lower_top.y, lower_top.z - 1.2)
	var high := Vector3(4, upper_top.y, upper_top.z + 1.2)
	var upper_bottom := Vector3(4, middle.y, middle.z)
	await _direct("lower ascent", low, middle)
	await _direct("lower descent", middle, low)
	await _direct("upper ascent", upper_bottom, high)
	await _direct("upper descent", high, upper_bottom)
	await _direct("two-flight off-center descent", high + Vector3(0.7, 0, 0), low)
	await _clicked("single climb to upper landing", [_actors[0]], [low], high)
	await _clicked("group two-flight ascent", _actors, [low + Vector3(-0.7, 0, 0), low + Vector3(0.7, 0, 0)], high)
	await _clicked("group upper landing descent", _actors, [high + Vector3(-0.7, 0, 0), high + Vector3(0.7, 0, 0)], low)
	_expect(_completed == 8, "all eight direct and click scenarios complete")
	_world.dispose()
	await process_frame
	print("STAIR_NAV_VALIDATION_%s cases=%d" % ["OK" if _failures.is_empty() else "FAILED", _completed])
	quit(0 if _failures.is_empty() else 1)

func _place(actor: HumanoidCharacter, point: Vector3) -> void:
	actor.stop_movement()
	actor.global_position = point + Vector3(0, 0.7, 0)
	actor.velocity = Vector3.ZERO
	_expect(await _world.wait_until(func(): return actor.is_on_floor(), 3.0), "stair subject must settle on physical floor")

func _direct(label: String, start: Vector3, target: Vector3) -> void:
	# Park the unused subject out of the requested passage.
	await _place(_actors[1], Vector3(-10, 0.1, -8))
	await _place(_actors[0], start)
	_expect(await _world.walk(_actors[0], target, 20.0), label + " must physically arrive and release movement")
	_completed += 1

func _clicked(label: String, actors: Array[HumanoidCharacter], starts: Array[Vector3], point: Vector3) -> void:
	for index in range(actors.size()):
		await _place(actors[index], starts[index])
	_world.get_node("PartyManager").set_selection(actors)
	_camera.global_position = point + Vector3(0, 16, -12)
	_camera.look_at(point)
	await physics_frame
	var screen := _camera.unproject_position(point)
	var hit := _dispatcher._pick_ground_hit(screen)
	_expect(not hit.is_empty() and absf(hit.position.y - point.y) < 0.4, label + " ray must pick the intended physical level")
	_expect(_dispatcher._handle_right_click(screen), label + " production right-click issues the command")
	var targets: Array[Vector3] = []
	var initial: Array[Vector3] = []
	for actor in actors:
		targets.append(actor.get_move_target())
		initial.append(actor.global_position)
		_expect(actor.has_move_target() and absf(actor.get_move_target().y - point.y) < 0.4, label + " every selected actor receives the correct level")
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		var done := true
		for actor in actors:
			done = done and not actor.has_move_target()
		if done:
			break
	for index in range(actors.size()):
		var actor := actors[index]
		var delta := actor.global_position - targets[index]
		_expect(not actor.has_move_target() and Vector2(delta.x, delta.z).length() <= actor.navigation_target_desired_distance + 0.05 and absf(delta.y) < 0.8 and actor.global_position.distance_to(initial[index]) > 1.0, label + " each actor physically arrives and stops")
	_completed += 1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
