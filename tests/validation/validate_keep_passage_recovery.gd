extends "res://tests/validation/test_case.gd"

## Real keep collision, production bootstrap/navigation, and physical RVO actors.
## No teleporting or manual steering after the initial fixture placement.
var _world: Node3D
var _actors: Array = []
var _failures: Array[String] = []
var _cases := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_world = load("res://tests/validation/helpers/navigation_fixture.gd").new()
	root.add_child(_world)
	current_scene = _world
	_world.add_floor(Vector3(48, 1, 48), Vector3(0, -1.18, 0))
	var shell = load("res://features/world/projection/buildings/shells/modular/large_wood_hall_tower.tscn").instantiate()
	shell.building_id = "validation.passage.keep"
	_world.add_child(shell)
	if not await _world.boot():
		push_error("KEEP_PASSAGE: navigation bootstrap failed")
		quit(2)
		return
	# Isolate congestion at an open door, not door access policy.
	shell.get_node("Pieces/MainDoor")._apply_door_state({"is_open": true}, false)
	await _case("entry", [Vector3(0, 0, 11)], [Vector3(0, 0, 3)])
	await _case("exit", [Vector3(0, 0, 3)], [Vector3(0, 0, 11)])
	await _case("jamb", [Vector3(-0.7, 0, 6.28)], [Vector3(0, 0, 11)])
	for repetition in range(4):
		await _case("opposing_%d" % repetition, [Vector3(0, 0, 11), Vector3(0, 0, 3)], [Vector3(0, 0, 3), Vector3(0, 0, 11)])
	await _case("group", [Vector3(-0.5, 0, 11), Vector3(0.5, 0, 11), Vector3(-0.5, 0, 4), Vector3(0.5, 0, 4)], [Vector3(-2, 0, 3), Vector3(2, 0, 3), Vector3(-2, 0, 11), Vector3(2, 0, 11)])
	await _case("idle_blocker", [Vector3(0, 0, 7), Vector3(0, 0, 3)], [Vector3(0, 0, 7), Vector3(0, 0, 11)])
	_world.dispose()
	await process_frame
	print("KEEP_PASSAGE_RESULT cases=%d failures=%s" % [_cases, _failures])
	quit(0 if _failures.is_empty() and _cases == 9 else 1)

func _case(label: String, starts: Array, goals: Array) -> void:
	for actor in _actors:
		actor.queue_free()
	_actors.clear()
	for frame in range(4):
		await physics_frame
	for index in starts.size():
		var actor = _world.add_actor("passage.%s.%d" % [label, index], starts[index] + Vector3.UP, true)
		actor.set_combat_stance(NpcRules.CombatStance.PASSIVE)
		_actors.append(actor)
	for frame in range(90):
		await physics_frame
	var targets: Array[Vector3] = []
	for index in _actors.size():
		var goal: Vector3 = goals[index]
		goal.y = -0.68 if goal.z > 8 else 0.0
		targets.append(_actors[index].get_floor_aligned_origin_position(goal))
		if label != "idle_blocker" or index != 0:
			_actors[index].set_move_target(targets[index], true)
	var yielded := false
	var completed := false
	for frame in range(1500):
		await physics_frame
		completed = true
		for index in _actors.size():
			var actor = _actors[index]
			yielded = yielded or actor.is_navigation_yielding()
			var offset: Vector3 = actor.global_position - targets[index]
			if Vector2(offset.x, offset.z).length() > 0.65 or absf(offset.y) > 0.8 or actor.has_move_target() or actor.is_navigation_yielding():
				completed = false
		if completed:
			break
	if not completed or (label == "idle_blocker" and not yielded):
		_failures.append(label)
		for actor in _actors:
			print("KEEP_PASSAGE_FAILURE ", label, " ", _world.actor_motion_snapshot(actor))
	print("KEEP_PASSAGE_CASE %s completed=%s yielded=%s" % [label, completed, yielded])
	_cases += 1
