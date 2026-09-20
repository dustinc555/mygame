extends "res://tests/validation/test_case.gd"

## World1's Canyon bar intentionally has no business schedule. This retained
## mechanics regression explicitly authors a scheduled kept-open door and
## checks a live eligible keeper, never a random nearest actor.
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world = load("res://tests/validation/helpers/navigation_fixture.gd").new()
	root.add_child(world)
	world.add_floor()
	var door: Node3D = world.add_door("validation.keeper.front")
	var keeper: CharacterBody3D = world.add_actor("validation.keeper", Vector3(0.5142, 0.5, -5), false)
	var closer: CharacterBody3D = world.add_actor("validation.closer", Vector3(0.5142, 0.5, 4))
	_expect(await world.boot(), "navigation/bootstrap must settle")
	var doors = BootstrapContext.service(&"doors")
	var interactions = BootstrapContext.service(&"door_interactions")
	var world_time = BootstrapContext.service(&"world_time")
	world_time.set_process(false)
	world_time.set_time_of_day(7, 0)
	doors.keeper_reconcile_delay_seconds = 0.5
	doors.configure_building_doors(door.building_id, {"public_access": true,
		"keeper_actor_id": keeper.stable_id, "initial_state": "locked",
		"open_hour": 8, "close_hour": 20, "kept_open": true})
	var state: Dictionary = doors.get_door_state(door.door_id)
	_expect(not state.is_open and state.is_locked and state.kept_open and state.scheduled_actor_id == keeper.stable_id, "explicit scheduled fixture begins closed and locked")
	var results: Array[Dictionary] = []
	doors.door_command_resolved.connect(func(result: Dictionary): results.append(result))
	var keeper_start := keeper.global_position
	# Use the real hour-boundary signal, not a manual door-controller callback.
	world_time.advance_hours(1.0)
	_expect(await world.wait_until(func(): return doors.get_door_state(door.door_id).is_open), "keeper opens for business through a real approach")
	_expect(keeper.global_position.distance_to(keeper_start) > 0.5, "keeper physically moved to the door")
	_expect(not closer.has_move_target() and not closer.is_in_combat(), "closer is available before the close command")
	_expect(interactions.request_actor_action(closer, door, "close", true), "eligible closer command accepted")
	_expect(await world.wait_until(func(): return not doors.get_door_state(door.door_id).is_open), "door actually transitions open to closed before reconciliation")
	var close_revision: int = doors.get_door_state(door.door_id).state_revision
	_expect(await world.wait_until(func(): return doors.get_door_state(door.door_id).is_open), "keeper reopens the drifted door")
	var keeper_opens := 0
	var closer_closed := false
	for result in results:
		if result.actor_id == keeper.stable_id and result.result_code == "opened":
			keeper_opens += 1
		if result.actor_id == closer.stable_id and result.result_code == "closed":
			closer_closed = true
	_expect(keeper_opens == 2 and closer_closed and doors.get_door_state(door.door_id).state_revision > close_revision, "opening ceremony and drift repair are distinct keeper commands around this closer's completed close")
	world.dispose()
	await process_frame
	print("KEEPER_RECONCILE_%s" % ("OK" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
