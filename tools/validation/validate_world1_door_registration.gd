extends SceneTree

## Boots the real world1 scene (bootstrap and all) and reports every door's
## identity and blocker state. Repro harness for "doors are walk-through in
## world1": a healthy door has a minted door_id, a registered controller
## record, and an enabled ClosedBlocker while closed.

const WORLD_SCENE_PATH := "res://scenes/worlds/world1/world1.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load(WORLD_SCENE_PATH) as PackedScene
	if scene == null:
		push_error("Failed to load %s" % WORLD_SCENE_PATH)
		quit(1)
		return
	var world := scene.instantiate()
	get_root().add_child(world)
	current_scene = world
	for _frame in range(30):
		await process_frame
	var doors := get_nodes_in_group("world_door")
	print("WORLD1_DOORS found=%d" % doors.size())
	var buildings := get_nodes_in_group("world_building")
	print("WORLD1_BUILDINGS found=%d" % buildings.size())
	var failures := 0
	for door in doors:
		var door_id := str(door.get("door_id"))
		var blocker := door.get_node_or_null("ClosedBlocker") as StaticBody3D
		var blocker_layer := blocker.collision_layer if blocker != null else -1
		var registered := false
		var state := {}
		var controller = door.get("_door_controller")
		if controller != null:
			state = controller.get_door_state(door_id) as Dictionary
			registered = not state.is_empty()
		print("WORLD1_DOOR id='%s' registered=%s blocker_layer=%d open=%s locked=%s kept_open=%s keeper='%s' hours=%d-%d authorized=%d" % [door_id, registered, blocker_layer, state.get("is_open"), state.get("is_locked"), state.get("kept_open"), state.get("scheduled_actor_id"), int(state.get("scheduled_open_hour", -1)), int(state.get("scheduled_close_hour", -1)), (state.get("authorized_actor_ids", PackedStringArray()) as PackedStringArray).size()])
		if door_id.is_empty() or not registered:
			failures += 1
	if doors.is_empty():
		failures += 1
	# The blocker only works if live actors actually mask its layer; a raw
	# CharacterBody3D test missed _configure_world_actor_movement resetting
	# collision_mask, so assert against the real spawned actors.
	var actors := get_nodes_in_group("world_actor")
	print("WORLD1_ACTORS found=%d" % actors.size())
	for actor in actors:
		var mask := int(actor.get("collision_mask"))
		if mask & 8 == 0:
			push_error("Actor %s does not mask door blockers (mask=%d)" % [actor.get_path(), mask])
			failures += 1
	if failures > 0:
		push_error("WORLD1_DOOR_REGISTRATION_FAILED unhealthy_doors=%d" % failures)
		quit(1)
		return
	print("WORLD1_DOOR_REGISTRATION_OK")
	quit()
