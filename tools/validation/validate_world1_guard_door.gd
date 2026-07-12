extends SceneTree

## Live repro for "guards walk into the bar door and it never opens": boots
## the real world1, takes an actual bar guard, sends them through the front
## door, and requires the auto-open pipeline to open it.

const WORLD_SCENE_PATH := "res://scenes/worlds/world1/world1.tscn"
const MAX_SECONDS := 12.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := (load(WORLD_SCENE_PATH) as PackedScene).instantiate()
	get_root().add_child(world)
	current_scene = world
	for _frame in range(60):
		await process_frame
	var door := _find_bar_door()
	var guard := _find_authorized_staff(door)
	if door == null or guard == null:
		push_error("Missing repro cast: door=%s guard=%s" % [door, guard])
		quit(1)
		return
	var sides: Array = door.call("get_interaction_positions")
	var outside: Vector3 = sides[0]
	var inside: Vector3 = sides[1]
	guard.global_position = outside + (outside - inside).normalized() * 1.5
	guard.call("set_move_target", inside, false)
	var opened := false
	var frames := int(MAX_SECONDS * 60.0)
	for _frame in range(frames):
		await physics_frame
		if bool(_door_state(door).get("is_open", false)):
			opened = true
			break
	var state := _door_state(door)
	print("GUARD_DOOR guard=%s dist_to_door=%.2f door_open=%s locked=%s has_move_target=%s" % [guard.get("stable_id"), (guard as Node3D).global_position.distance_to((door as Node3D).global_position), state.get("is_open"), state.get("is_locked"), guard.call("has_move_target")])
	if not opened:
		push_error("GUARD_DOOR_FAILED guard never opened the bar door")
		quit(1)
		return
	print("GUARD_DOOR_OK")
	quit()


func _door_state(door: Node) -> Dictionary:
	var controller = door.get("_door_controller")
	return controller.get_door_state(str(door.get("door_id"))) as Dictionary if controller != null else {}


func _find_bar_door() -> Node:
	for door in get_nodes_in_group("world_door"):
		if str(door.get("door_id")).contains("SettlementBar"):
			return door
	return null


func _find_authorized_staff(door: Node) -> Node:
	if door == null:
		return null
	var authorized := _door_state(door).get("authorized_actor_ids", PackedStringArray()) as PackedStringArray
	for actor in get_nodes_in_group("world_actor"):
		if actor is Node3D and authorized.has(str(actor.get("stable_id"))):
			return actor
	return null
