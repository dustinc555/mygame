extends SceneTree
## Production bootstrap/time-boundary/LOD proof. No editor or live-game mutation.
var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = load("res://scenes/test_levels/two_towns_road_test.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for frame in 120:
		await process_frame
	var context := BootstrapContext.active
	var skip := context.get_optional(&"debug_time_skip")
	_expect(skip != null, "production bootstrap installs debug time skip")
	if skip == null:
		_finish()
		return
	var clock = context.get_optional(&"world_time")
	var lod = context.get_optional(&"population_realization")
	clock.request_manual_pause()
	clock.set_speed_index(2)
	var settings: Dictionary = lod.serialize_state()
	var start: float = clock.total_world_minutes
	var menu = context.get_optional(&"world_status").get("debug_menu")
	_expect(menu != null and menu.call("get_window_titles").has("Time Skip"), "existing debug menu exposes Time Skip")
	var population = context.get_optional(&"population")
	var settlements = context.get_optional(&"settlement")
	var farmers: Dictionary = {}
	for slot in settlements.get_assignment_slots_for_realization("farmer_crossing"):
		if not PackedStringArray(slot.get("allowed_job_entry_ids", [])).has("category:farm"):
			continue
		var actor_id := str(slot.get("occupant_actor_id", ""))
		if actor_id.is_empty():
			var definition = settlements.get_settlement_definition("farmer_crossing")
			var generated: Array = population.ensure_generated_population("farmer_crossing", "skip_validation_%s" % str(slot.slot_id), 1, {
				"role_id": "resident", "faction_id": definition.get_faction_id(), "available_for_work": true,
				"population_appearance_profile": definition.get_population_appearance_profile(),
				"population_name_profile": definition.get_population_name_profile(),
			})
			actor_id = str(generated[0].actor_id)
			settlements.assign_actor_to_assignment_slot("farmer_crossing", str(slot.assignment_domain), str(slot.slot_id), actor_id)
		settlements.realize_assignment_slot("farmer_crossing", str(slot.assignment_domain), str(slot.slot_id))
		var actor = population.get_live_actor(actor_id)
		if actor != null:
			farmers[actor_id] = actor.get_instance_id()
	_expect(not farmers.is_empty(), "production workers are genuinely realized before skipping")
	var camera = game.get_node("CameraRig/CameraPivot/Camera3D")
	var camera_transform: Transform3D = camera.global_transform
	var party_transforms := {}
	for actor in game.get_node("PartyManager").party_members:
		party_transforms[actor] = actor.global_transform
	var farm = context.get_optional(&"farming")
	var farm_before: Dictionary = farm.get_plots()
	var gecs = context.get_optional(&"gecs_world")
	gecs.upsert_world_sim_squad({"squad_id": "skip_validation", "owner_kind": "validation", "member_count": 1, "position": Vector3(5000, 0, 5000), "target_position": Vector3(10000, 0, 5000), "objective": "travel", "move_speed": 1.0})
	var boundaries: Array[int] = []
	clock.minute_changed.connect(func(minute: int, _day: int, _hour: int, _part: int):
		boundaries.append(minute)
		_expect(clock.get_absolute_minute() == minute, "boundary consumers observe chronological canonical time")
		_expect(population.count_live_non_party_actors() == 0, "every canonical boundary runs with NPC projections absent")
	)
	menu.call("toggle_window", "Time Skip")
	menu.find_child("TimeSkipAmount", true, false).get_line_edit().text = "2"
	menu.find_child("TimeSkipButton", true, false).pressed.emit()
	_expect(bool(skip.call("is_active")), "Skip button starts hours request")
	_expect(not bool(skip.call("request_skip", 1.0, "Days").get("accepted", true)), "duplicate request rejected")
	for frame in 10000:
		if not bool(skip.call("is_active")):
			break
		await process_frame
	_expect(not bool(skip.call("is_active")), "bounded skip finishes")
	_expect(is_equal_approx(clock.total_world_minutes, start + 120.0), "exact requested hours advance")
	_expect(boundaries.size() == 120, "every minute boundary emitted once")
	_expect(clock.is_manual_paused() and clock.get_speed_index() == 2, "pause and speed restored")
	_expect(lod.serialize_state() == settings, "LOD settings unchanged")
	_expect(camera.global_transform == camera_transform, "camera never moves")
	for actor in party_transforms:
		_expect(is_instance_valid(actor) and actor.global_transform == party_transforms[actor], "party stays at its original position")
	for actor_id in farmers:
		var actor = population.get_live_actor(actor_id)
		_expect(actor != null and actor.get_instance_id() != farmers[actor_id], "same durable worker returns as a fresh projection")
	_expect(farm.get_plots() != farm_before, "canonical away simulation actually changes durable fields")
	var squad_found := false
	for squad in gecs.get_world_sim_squads():
		if squad.squad_id == "skip_validation":
			squad_found = true
			_expect(squad.position.x > 5000.0, "ordinary squad world simulation advances while projections are unloaded")
	_expect(squad_found, "injected squad survives the skip and is actually checked")
	var soil_before := 0
	var soil_after := 0
	for plot in farm_before.values():
		for cell in plot.get("cells", {}).values(): soil_before += int(cell.get("soil_created", false))
	for plot in farm.get_plots().values():
		for cell in plot.get("cells", {}).values(): soil_after += int(cell.get("soil_created", false))
	_expect(soil_after > soil_before, "chronological offscreen farm work creates new physical soil, not only a changed clock field")
	print("DEBUG_TIME_SKIP_HANDOFF farmers=%d boundaries=%d" % [farmers.size(), boundaries.size()])
	var before_days: float = clock.total_world_minutes
	menu.find_child("TimeSkipAmount", true, false).get_line_edit().text = "0.01"
	menu.find_child("TimeSkipUnit", true, false).select(1)
	menu.find_child("TimeSkipButton", true, false).pressed.emit()
	await _wait_idle(skip)
	_expect(is_equal_approx(clock.total_world_minutes, before_days + 14.4), "Days UI preserves fractional duration")
	for invalid in [0.0, -1.0, INF, NAN, 366.0]:
		_expect(not bool(skip.call("request_skip", invalid, "Days").get("accepted", true)), "invalid duration rejected without mutation")
	_expect(not skip.call("request_skip", 1.0, "Weeks").accepted, "unknown unit rejected")
	_expect(not lod.is_far_simulation_active() and clock.is_manual_paused(), "rejection leaves settings restored")
	var cancel_start: float = clock.total_world_minutes
	skip.call("request_skip", 1.0, "Days")
	menu.call("close_menu")
	await _wait_idle(skip)
	_expect(is_equal_approx(clock.total_world_minutes, cancel_start), "hiding the window cancels before clock mutation")
	_expect(not lod.is_far_simulation_active() and clock.is_manual_paused(), "cancel restores pause and LOD")
	skip.call("request_skip", 1.0, "Days")
	for frame in 200:
		if clock.total_world_minutes > cancel_start:
			break
		await process_frame
	skip.call("cancel")
	var partial: float = clock.total_world_minutes
	await _wait_idle(skip)
	_expect(partial > cancel_start and partial < cancel_start + 1440.0 and is_equal_approx(clock.total_world_minutes, partial), "mid-skip cancellation preserves only completed chronological steps")
	clock.release_manual_pause()
	clock.set_speed_index(0)
	var was_world_paused: bool = clock.is_world_paused()
	skip.call("request_skip", 0.01, "Hours")
	await _wait_idle(skip)
	_expect(clock.is_world_paused() == was_world_paused and not clock.is_manual_paused() and clock.get_speed_index() == 0, "skip preserves independent loading pause and original speed without adding manual pause")
	clock.request_manual_pause()
	skip.call("request_skip", 1.0, "Hours")
	for frame in 200:
		if str(skip.get("_phase")) == "settling":
			break
		await process_frame
	_expect(population.count_live_non_party_actors() == 0, "teardown regression starts after real unloading")
	skip.get_parent().remove_child(skip)
	_expect(not lod.is_far_simulation_active() and clock.is_manual_paused(), "service teardown synchronously releases its LOD and pause lease")
	skip.free()
	for frame in 60:
		await process_frame
	for actor_id in farmers:
		_expect(population.get_live_actor(actor_id) != null, "population restores projections after skip service teardown even while manually paused")
	_finish()

func _wait_idle(skip: Node) -> void:
	for frame in 10000:
		if not bool(skip.call("is_active")):
			return
		await process_frame
	_expect(false, "skip operation times out")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if is_instance_valid(game):
		game.free()
	if failures.is_empty():
		print("DEBUG_TIME_SKIP_OK")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
