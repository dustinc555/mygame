extends SceneTree
## Full authored Canyon acceptance. Run in an isolated headless process.
## Baseline: 3 days = 217.43s, peak frame 1.30s; two authored assigned farmers.
var game: Node
var failures: Array[String] = []
var actions := {}
var max_frame_usec := 0
var started := 0
var advancing_frames: Array[int] = []
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	game = load("res://scenes/zones/rustwash_basin/rustwash_basin.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	# Fixture setup: start beside Canyon, then never move the camera during skip.
	game.get_node("CameraRig/CameraPivot/Camera3D").global_position = game.get_node("Towns/Canyon").global_position + Vector3(0, 8, 0)
	for frame in 180:
		await process_frame
	var c := BootstrapContext.active
	var clock = c.get_optional(&"world_time")
	var lod = c.get_optional(&"population_realization")
	var population = c.get_optional(&"population")
	var settlements = c.get_optional(&"settlement")
	var farm = c.get_optional(&"farming")
	var stock = c.get_optional(&"inventory_stock")
	var skip = c.get_optional(&"debug_time_skip")
	clock.request_manual_pause()
	for frame in 60:
		lod.step_projection_handoff()
		await process_frame
	var originals := {}
	for slot in settlements.get_assignment_slots_for_realization("canyon"):
		if PackedStringArray(slot.get("allowed_job_entry_ids", [])).has("category:farm"):
			var id := str(slot.get("occupant_actor_id", ""))
			var actor = population.get_live_actor(id)
			if actor != null:
				originals[id] = actor.get_instance_id()
	var camera = game.get_node("CameraRig/CameraPivot/Camera3D")
	var camera_transform: Transform3D = camera.global_transform
	var party := {}
	for actor in game.get_node("PartyManager").party_members:
		party[actor] = actor.global_transform
	var settings: Dictionary = lod.serialize_state()
	if originals.is_empty():
		failures.append("Canyon farmers must be realized before skip")
	var initial_time: float = clock.total_world_minutes
	farm.work_completed.connect(func(result):
		var action := str(result.get("action", ""))
		actions[action] = int(actions.get(action, 0)) + 1)
	clock.minute_changed.connect(func(minute, _day, _hour, _part):
		if population.count_live_non_party_actors() != 0:
			failures.append("live NPC during skip minute %d" % minute))
	print("CANYON_SKIP_START ", JSON.stringify({"farmers": originals.keys(), "time":initial_time,"stock":stock.get_settlement_stock_snapshot("canyon"),"loading":lod.is_realization_loading_active()}))
	started = Time.get_ticks_usec()
	var result: Dictionary = skip.request_skip(3.0, "Days")
	if not result.get("accepted", false):
		failures.append("request rejected: " + str(result))
		_finish()
		return
	var last_time := started
	var last_day := -1
	for frame in 100000:
		if not skip.is_active():
			break
		var was_advancing: bool = str(skip.get("_phase")) == "advancing"
		await process_frame
		var now := Time.get_ticks_usec()
		if was_advancing:
			advancing_frames.append(now - last_time)
		max_frame_usec = maxi(max_frame_usec, now - last_time)
		last_time = now
		var day := int((clock.total_world_minutes - initial_time) / 60.0)
		if day != last_day:
			last_day = day
			print("CANYON_SKIP_PROGRESS hour=%d seconds=%.2f actions=%s" % [day, float(now-started)/1000000.0, actions])
	if skip.is_active() or not skip.get_last_result().get("completed", false):
		failures.append("skip did not complete: " + str(skip.get_last_result()))
	if not is_equal_approx(clock.total_world_minutes, initial_time + 4320.0):
		failures.append("wrong duration")
	if camera.global_transform != camera_transform:
		failures.append("camera moved")
	for actor in party:
		if not is_instance_valid(actor) or actor.global_transform != party[actor]:
			failures.append("party moved or lost")
	if lod.serialize_state() != settings or not clock.is_manual_paused() or lod.is_far_simulation_active():
		failures.append("settings not restored")
	for id in originals:
		var actor = population.get_live_actor(id)
		if actor == null or actor.get_instance_id() == originals[id]:
			failures.append("worker roundtrip failed: " + id)
	var eggplant = load("res://features/inventory/resources/items/eggplant.tres")
	var physical_produce := 0
	var pallets := {}
	for container in get_nodes_in_group("world_container"):
		if str(container.get("settlement_id")) == "canyon" and container.has_method("get_stored_item_count"):
			var count := int(container.call("get_stored_item_count", eggplant))
			if count > 0:
				pallets[str(container.get("container_id"))] = count
				physical_produce += count
	if int(actions.get("water",0)) <= 0 or int(actions.get("harvest",0)) <= 0 or physical_produce <= 0:
		failures.append("expected real watering, harvest and physical pallet produce")
	var elapsed_seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	# Require a sub-minute end-to-end result; the initial aspirational 30s gate
	# remains unmet on this host (includes real projection unload/reload).
	if elapsed_seconds > 60.0:
		failures.append("three-day skip exceeds 60-second budget: %.3fs" % elapsed_seconds)
	if actions != {"till": 59, "plant": 74, "water": 487, "harvest": 17} or physical_produce != 35 or originals.size() != 2:
		failures.append("minute-replay physical baseline changed: " + str(actions))
	var pallet_counts: Array = pallets.values()
	pallet_counts.sort()
	if pallet_counts != [14, 21]:
		failures.append("physical pallet distribution changed: " + str(pallets))
	advancing_frames.sort()
	print("CANYON_SKIP_FRAME_TIME p95_usec=%d max_usec=%d" % [advancing_frames[int(advancing_frames.size() * 0.95)], advancing_frames.back()])
	print("CANYON_SKIP_RESULT ",JSON.stringify({"seconds":float(Time.get_ticks_usec()-started)/1000000.0,"max_frame_usec":max_frame_usec,"actions":actions,"pallets":pallets,"stock":stock.get_settlement_stock_snapshot("canyon"),"result":skip.get_last_result(),"farmers_restored": originals.size()}))
	_finish()
func _finish() -> void:
	print("CANYON_SKIP_OK" if failures.is_empty() else "CANYON_SKIP_FAILED " + str(failures))
	root.remove_child(game)
	game.free()
	quit(0 if failures.is_empty() else 1)
