extends SceneTree

## Live keeper-custodian proof in the real world1: advance time into business
## hours (bartender unlocks and opens the bar), have the player-like actor
## shut the front door mid-business, and require the bartender to walk over
## and reopen it via the drift-reconcile path.

const WORLD_SCENE_PATH := "res://scenes/worlds/world1/world1.tscn"
const MAX_SECONDS := 25.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := (load(WORLD_SCENE_PATH) as PackedScene).instantiate()
	get_root().add_child(world)
	current_scene = world
	for _frame in range(60):
		await process_frame
	var doors = BootstrapContext.service(&"doors")
	var world_time = BootstrapContext.service(&"world_time")
	doors.keeper_reconcile_delay_seconds = 0.5
	# Land exactly on the opening hour: the schedule acts on the hour edge.
	world_time.set_time_of_day(8, 0)
	doors._on_world_hour_changed(8, 0, 8)
	var door := _find_bar_door()
	if door == null:
		push_error("No bar door found")
		quit(1)
		return
	var door_id := str(door.get("door_id"))
	if not await _wait_for_open(doors, door_id, 10.0):
		push_error("KEEPER_FAILED door never entered business-hours open state: %s" % str(doors.get_door_state(door_id)))
		quit(1)
		return
	print("KEEPER business-hours state reached, closing the door out from under the bar")
	var closer := _find_nearest_actor(door as Node3D)
	var interactions = BootstrapContext.service(&"door_interactions")
	if closer == null or not interactions.request_actor_action(closer, door, "close", true):
		push_error("KEEPER_FAILED could not issue the close command (closer=%s)" % closer)
		quit(1)
		return
	if not await _wait_for(func() -> bool: return not bool(doors.get_door_state(door_id).get("is_open", true)), 10.0):
		push_error("KEEPER_FAILED door never closed: %s" % str(doors.get_door_state(door_id)))
		quit(1)
		return
	print("KEEPER door closed mid-business, waiting for the bartender")
	if not await _wait_for_open(doors, door_id, MAX_SECONDS):
		push_error("KEEPER_FAILED bartender never reopened the door: %s" % str(doors.get_door_state(door_id)))
		quit(1)
		return
	print("KEEPER_RECONCILE_OK")
	quit()


func _wait_for_open(doors, door_id: String, seconds: float) -> bool:
	return await _wait_for(func() -> bool:
		var state: Dictionary = doors.get_door_state(door_id)
		return bool(state.get("is_open", false)) and not bool(state.get("is_locked", true)), seconds)


func _wait_for(condition: Callable, seconds: float) -> bool:
	for _frame in range(int(seconds * 60.0)):
		await physics_frame
		if bool(condition.call()):
			return true
	return false


func _find_bar_door() -> Node:
	for door in get_nodes_in_group("world_door"):
		# world1's bar facility is canyon.rest_stop; door IDs are minted from the building ID.
		if str(door.get("door_id")).contains("rest_stop.building"):
			return door
	return null


func _find_nearest_actor(door: Node3D) -> Node:
	var best: Node = null
	var best_distance := INF
	for actor in get_nodes_in_group("world_actor"):
		if not actor is Node3D:
			continue
		var distance := (actor as Node3D).global_position.distance_to(door.global_position)
		if distance < best_distance:
			best_distance = distance
			best = actor
	return best
