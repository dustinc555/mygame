extends SceneTree
## Historical audit identity; controlled real-service farming replay.
## The 60-second end-to-end requirement includes unload/advance/restore.
## Prior authored-world baseline: 341 cells / two plots / two workers,
## 4320 minutes in 35.605 seconds. Preserve that workload, not its layout.
const FIXTURE := "res://tests/validation/fixtures/farming_replay/farming_replay_load.tscn"
const SETTLEMENT_ID := "farming_replay"
const WORKER_IDS := ["farming_replay.farmer_a", "farming_replay.farmer_b"]
var game: Node
var failures: Array[String] = []
var actions := {}
var max_frame_usec := 0
var started := 0
var advancing_frames: Array[int] = []
var transition_ledger: Array[Dictionary] = []
var consumed_items := {}
var produced_items := {}
var food_days := {}
var initial_plot_ids := {}
var harvested_items := {}
var water_applied := 0.0
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	game = (load(FIXTURE) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	var bootstrap_deadline := Time.get_ticks_msec() + 60000
	while not _fixture_registered() and Time.get_ticks_msec() < bootstrap_deadline:
		await process_frame
	if not _fixture_registered():
		failures.append("controlled fixture failed to register farm, funded stock, water and declared workers")
		_finish()
		return
	var c := BootstrapContext.active
	var clock = c.get_optional(&"world_time")
	var lod = c.get_optional(&"population_realization")
	var population = c.get_optional(&"population")

	var farm = c.get_optional(&"farming")
	var stock = c.get_optional(&"inventory_stock")
	var skip = c.get_optional(&"debug_time_skip")
	var loading_gate = c.get_optional(&"navigation_loading_overlay")
	var navigation = c.get_optional(&"world_navigation")
	var initial_pause_reasons: Dictionary = clock.get("_pause_reasons").duplicate()
	# Frame warmup is not startup readiness: the ordinary loading owner must
	# release controls before this test owns a manual pause or measures a skip.
	var startup_started := Time.get_ticks_msec()
	var startup_deadline := startup_started + 90000
	while clock.is_world_paused() or navigation.is_initial_navigation_pending() or lod.is_realization_loading_active():
		if Time.get_ticks_msec() >= startup_deadline:
			failures.append("initial world loading did not finish before skip: pauses=%s navigation_pending=%s" % [clock.get("_pause_reasons"), navigation.gate_tiles_pending()])
			_finish()
			return
		await process_frame
	print("CANYON_STARTUP_READY ", JSON.stringify({"seconds": float(Time.get_ticks_msec() - startup_started) / 1000.0, "pause_reasons": clock.get("_pause_reasons"), "navigation_pending": navigation.gate_tiles_pending(), "loading": lod.is_realization_loading_active()}))
	clock.request_manual_pause()
	var originals := {}
	for id in WORKER_IDS:
		var actor = population.get_live_actor(id)
		if actor != null: originals[id] = actor.get_instance_id()
	var camera = game.get_node("CameraRig/CameraPivot/Camera3D")
	var camera_transform: Transform3D = camera.global_transform
	var party_manager = game.get_node("PartyManager")
	party_manager.select_only(game.get_node("PartyMembers/Observer"))
	var selected_before: Array = party_manager.selected_members.duplicate()
	var party := {}
	for actor in party_manager.party_members:
		party[actor] = actor.global_transform
	var settings: Dictionary = lod.serialize_state()
	if party.is_empty():
		failures.append("fixture must retain a real party member during the skip")
	if originals.size() != WORKER_IDS.size():
		failures.append("every declared fixture farmer must be realized before skip")
		_finish()
		return
	var initial_time: float = clock.total_world_minutes
	var initial_stock: Dictionary = stock.get_settlement_stock_snapshot(SETTLEMENT_ID)
	var initial_farms := {}
	for id in farm.get_plots():
		var plot: Dictionary = farm.get_plot(id)
		if str(plot.get("settlement_id", "")) == SETTLEMENT_ID:
			initial_plot_ids[id] = true
			initial_farms[id] = plot
	var cell_counts: Array[int] = []
	for plot in initial_farms.values(): cell_counts.append(plot.cells.size())
	cell_counts.sort()
	if cell_counts != [132, 209]:
		failures.append("throughput fixture must retain two plots with 132 + 209 cells: " + str(cell_counts))
		_finish()
		return
	var food = c.get_optional(&"settlement_food")
	food_days[int(food.get_status(SETTLEMENT_ID).get("last_processed_day", -1))] = true
	food.food_status_changed.connect(_record_food_status)
	farm.work_completed.connect(_record_work.bind(farm, clock))
	var initial_sources := {}
	var available_water := 0.0
	for source in c.get_optional(&"gecs_world").get_farm_water_source_states().values():
		if str(source.get("settlement_id", "")) != SETTLEMENT_ID: continue
		initial_sources[source.source_id] = source
		available_water += float(source.current_water) + float(farm._water_source_recharge_per_minute(source)) * 4320.0
	for tank in c.get_optional(&"liquid_storage").get_settlement_liquid_container_states(SETTLEMENT_ID, "water"):
		available_water += float(tank.current_liters)
	# Derealization can settle water a projected farmer already carries.
	# Count that initial physical water too, rather than inventing a supply
	# deficit when it legitimately returns to a durable tank during unload.
	var carrier = load("res://features/inventory/bridge/liquid_haul_carrier.gd")
	for actor in get_nodes_in_group("humanoid_characters"):
		if str(actor.get_meta("settlement_id", "")) == SETTLEMENT_ID: available_water += float(carrier.amount(actor, "water"))
	print("CANYON_SKIP_FIXTURE ", JSON.stringify({"seed":2026,"plots":initial_farms,"sources":initial_sources,"crop":farm.get_crop("eggplant").to_sim_profile(),"seconds_per_minute":clock.real_seconds_per_game_minute,"water_supply_ceiling":available_water}))
	var check_unloaded := func(minute, _day, _hour, _part):
		if population.count_live_non_party_actors() != 0:
			failures.append("live NPC during skip minute %d" % minute)
	clock.minute_changed.connect(check_unloaded)
	print("CANYON_SKIP_START ", JSON.stringify({"farmers": originals.keys(), "time":initial_time,"stock":initial_stock,"loading":lod.is_realization_loading_active(), "pause_reasons": clock.get("_pause_reasons"), "gate_requests": loading_gate.get("_requests") if loading_gate != null else null, "navigation_pending": navigation.call("gate_tiles_pending") if navigation != null else null}))
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
		if Time.get_ticks_usec() - started > 60000000:
			failures.append("three-day skip exceeded the unchanged 60-second budget before completion")
			_finish()
			return
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
	if party_manager.selected_members != selected_before or not game.get_node("PartyMembers/Observer").is_selected:
		failures.append("party selection changed during skip")
	if lod.serialize_state() != settings or not clock.is_manual_paused() or lod.is_far_simulation_active():
		failures.append("settings not restored")
	if lod.is_realization_loading_active():
		failures.append("realization loading overlay still owns controls after skip")
	for id in originals:
		var actor = population.get_live_actor(id)
		if actor == null or actor.get_instance_id() == originals[id]:
			failures.append("worker roundtrip failed: " + id)
	var eggplant = load("res://features/inventory/resources/items/eggplant.tres")
	var physical_produce := 0
	var pallets := {}
	for container in get_nodes_in_group("world_container"):
		if str(container.get("settlement_id")) == SETTLEMENT_ID and container.has_method("get_stored_item_count"):
			var count := int(container.call("get_stored_item_count", eggplant))
			if count > 0:
				pallets[str(container.get("container_id"))] = count
				physical_produce += count
	if int(actions.get("plant",0)) <= 0 or int(actions.get("water",0)) <= 0 or int(actions.get("harvest",0)) <= 0 or physical_produce <= 0:
		failures.append("expected real planting, watering, harvest and physical produce")
	var elapsed_seconds := float(Time.get_ticks_usec() - started) / 1000000.0
	# This is still the measured unload + canonical replay + restoration gate.
	if elapsed_seconds > 60.0:
		failures.append("three-day skip exceeds 60-second budget: %.3fs" % elapsed_seconds)
	# Counts are consequences of real crop rules, not world-design goldens.
	# The test-owned 341-cell fixture must account for every committed item.
	var final_stock: Dictionary = stock.get_settlement_stock_snapshot(SETTLEMENT_ID)
	var expected_items: Dictionary = initial_stock.get("items", {}).duplicate(true)
	for item_id in harvested_items: expected_items[item_id] = int(expected_items.get(item_id, 0)) + int(harvested_items[item_id])
	for item_id in produced_items: expected_items[item_id] = int(expected_items.get(item_id, 0)) + int(produced_items[item_id])
	for item_id in consumed_items: expected_items[item_id] = int(expected_items.get(item_id, 0)) - int(consumed_items[item_id])
	expected_items["seed.eggplant"] = int(expected_items.get("seed.eggplant", 0)) - int(actions.get("plant", 0))
	for item_id in expected_items.keys():
		if int(expected_items[item_id]) == 0: expected_items.erase(item_id)
	if final_stock.get("items", {}) != expected_items:
		failures.append("physical stock fails seed/harvest/upkeep conservation: expected %s actual %s" % [expected_items, final_stock])
	if water_applied <= 0.0 or water_applied > available_water + 0.001:
		failures.append("farm water exceeds finite source + capped recharge + initial tank supply")
	var remaining_water := 0.0
	for source in c.get_optional(&"gecs_world").get_farm_water_source_states().values():
		if str(source.get("settlement_id", "")) == SETTLEMENT_ID:
			remaining_water += float(source.current_water)
	for tank in c.get_optional(&"liquid_storage").get_settlement_liquid_container_states(SETTLEMENT_ID, "water"):
		remaining_water += float(tank.current_liters)
	for id in WORKER_IDS:
		var actor = population.get_live_actor(id)
		if actor != null: remaining_water += float(carrier.amount(actor, "water"))
	if not is_equal_approx(available_water, remaining_water + water_applied):
		failures.append("finite fixture water must balance exactly: initial=%s remaining=%s applied=%s" % [available_water, remaining_water, water_applied])
	if consumed_items.is_empty() or food_days.size() != 4:
		failures.append("three real daily upkeep events with positive physical food consumption required")
	if not produced_items.is_empty() or int(final_stock.get("items", {}).get("food.generic", 0)) != 0:
		failures.append("physical farming must not mint abstract food during upkeep")
	if int(final_stock.get("items", {}).get("food.eggplant", 0)) != physical_produce:
		failures.append("durable stock index and realized pallets disagree")
	var seed_container = game.get_node("Town/Seeds")
	if int(seed_container.inventory.count_item(eggplant)) != 0 or int(seed_container.inventory.count_item(farm.get_crop("eggplant").seed_item)) != int(final_stock.get("items", {}).get("seed.eggplant", 0)):
		failures.append("typed physical seed stock must match index and exclude produce")
	advancing_frames.sort()
	if advancing_frames.is_empty():
		failures.append("no advancing frames were measured")
	else:
		print("CANYON_SKIP_FRAME_TIME p95_usec=%d max_usec=%d" % [advancing_frames[int(advancing_frames.size() * 0.95)], advancing_frames.back()])
	print("CANYON_SKIP_TRANSITIONS ", JSON.stringify({"work":transition_ledger,"harvested":harvested_items,"consumed":consumed_items,"produced":produced_items,"water_applied":water_applied}))
	print("CANYON_SKIP_RESULT ",JSON.stringify({"seconds":elapsed_seconds,"cells_by_plot":cell_counts,"max_frame_usec":max_frame_usec,"actions":actions,"pallets":pallets,"stock":final_stock,"result":skip.get_last_result(),"farmers_restored": originals.size(), "water_initial":available_water,"water_remaining":remaining_water,"water_applied":water_applied}))
	clock.minute_changed.disconnect(check_unloaded)
	# Restoring flags alone does not prove the real pause control was released.
	# Publish ordinary post-replay work so both recreated workers must rejoin
	# the event-driven scheduler, independently of the last crop's due time.
	var resume_positions: Array[Vector3] = [Vector3(-3, 0, 8), Vector3(-1.75, 0, 8)]
	var resume_plot: Dictionary = farm.create_plot(resume_positions, Vector2i(2, 1), "", "Player", SETTLEMENT_ID)
	if resume_plot.is_empty():
		failures.append("could not publish controlled post-handoff farm work")
	else:
		for key in resume_plot.cells:
			farm.request_cell_operation(str(resume_plot.plot_id), str(key), "till")
	var completed_time: float = clock.total_world_minutes
	clock.release_manual_pause()
	var reacquired := {}
	var farm_work = c.get_optional(&"farm_work")
	var resume_deadline := Time.get_ticks_msec() + 2000
	while (clock.total_world_minutes <= completed_time or reacquired.size() != WORKER_IDS.size()) and Time.get_ticks_msec() < resume_deadline:
		for id in WORKER_IDS:
			var actor = population.get_live_actor(id)
			if actor != null and farm_work.has_active_work_for_actor(actor): reacquired[id] = true
		await process_frame
	if reacquired.size() != WORKER_IDS.size():
		failures.append("restored workers did not reacquire ordinary farm work: " + str(reacquired.keys()))
	if clock.is_world_paused() or (loading_gate != null and loading_gate.is_loading_gate_active()):
		failures.append("pause/loading owner still blocks returned control")
	print("FARM_REPLAY_RETURNED_CONTROL ", JSON.stringify({"workers_reacquired":reacquired.keys(), "time_advanced":clock.total_world_minutes > completed_time, "selected_party_count":party_manager.selected_members.size(), "paused":clock.is_world_paused()}))
	if clock.total_world_minutes <= completed_time:
		print("CANYON_CONTROL_TRACE ", JSON.stringify({
			"initial_pause_reasons": initial_pause_reasons,
			"pause_reasons": clock.get("_pause_reasons"), "tree_paused": paused,
			"clock_processing": clock.is_processing(), "clock_process_mode": clock.process_mode,
			"scene_process_mode": game.process_mode, "engine_time_scale": Engine.time_scale,
			"loading": lod.is_realization_loading_active(), "skip_phase": skip.get("_phase"),
			"gate_active": loading_gate.is_loading_gate_active() if loading_gate != null else null,
			"gate_requests": loading_gate.get("_requests") if loading_gate != null else null,
			"navigation_pending": navigation.call("gate_tiles_pending") if navigation != null else null,
			"navigation_idle": navigation.call("is_idle") if navigation != null else null,
			"completed_time": completed_time, "current_time": clock.total_world_minutes,
		}))
		failures.append("ordinary time/control did not resume after releasing the restored manual pause")
	clock.request_manual_pause()
	_finish()


func _record_food_status(settlement_id: String, status: Dictionary) -> void:
	var day := int(status.get("last_processed_day", -1))
	if settlement_id != SETTLEMENT_ID or food_days.has(day): return
	food_days[day] = true
	for item_id in status.get("last_consumed_item_counts", {}):
		consumed_items[item_id] = int(consumed_items.get(item_id, 0)) + int(status.last_consumed_item_counts[item_id])
	for item_id in status.get("last_produced_item_counts", {}):
		produced_items[item_id] = int(produced_items.get(item_id, 0)) + int(status.last_produced_item_counts[item_id])


func _record_work(result: Dictionary, farm: Node, clock: Node) -> void:
	var plot_id := str(result.get("plot_id", ""))
	if not initial_plot_ids.has(plot_id): return
	var action := str(result.get("action", ""))
	actions[action] = int(actions.get(action, 0)) + 1
	var cell: Dictionary = farm.get_cell(plot_id, str(result.get("cell_key", "")))
	var expected_state := str({"till":"tilled", "plant":"growing", "water":"growing", "harvest":"tilled", "clear":"tilled"}.get(action, ""))
	if expected_state.is_empty() or str(cell.get("state", "")) != expected_state or not bool(cell.get("soil_created", false)):
		failures.append("completed work has no corresponding durable physical transition: " + str(result))
	var liters := float(result.get("water_applied", 0.0))
	if action == "water" and (liters <= 0.0 or liters > 5.001): failures.append("offscreen watering must commit a positive finite draw of at most 5 L")
	water_applied += liters
	if action == "harvest":
		var item: ItemDefinition = result.get("produce_item")
		if item == null or str(result.get("crop_id", "")) != "eggplant":
			failures.append("fixture harvest must identify actual eggplant produce")
		else:
			if int(result.get("yield", 0)) != int(farm.get_crop("eggplant").base_yield): failures.append("offscreen harvest yield differs from zero-skill authored crop yield")
			harvested_items[item.item_id] = int(harvested_items.get(item.item_id, 0)) + int(result.get("yield", 0))
	transition_ledger.append({"minute":clock.total_world_minutes,"plot":plot_id,"cell":result.get("cell_key"),"action":action,"state":cell.get("state"),"yield":result.get("yield",0),"water_applied":liters})

func _fixture_registered() -> bool:
	var c := BootstrapContext.active
	if c == null: return false
	for id in [&"world_time", &"farming", &"inventory_stock", &"settlement_food", &"population", &"population_realization", &"world_navigation", &"debug_time_skip", &"liquid_storage"]:
		if c.get_optional(id) == null: return false
	if game.get_node("Town/Facilities/Farm").get_plot_id().is_empty(): return false
	if game.get_node("Town/Facilities/SecondFarm").get_plot_id().is_empty(): return false
	if c.get_optional(&"farming").get_water_source("farming_replay.water").is_empty(): return false
	var items: Dictionary = c.get_optional(&"inventory_stock").get_settlement_stock_snapshot(SETTLEMENT_ID).get("items", {})
	var authored_seed_count := int(game.get_node("Town/Seeds").starting_items[0].quantity)
	if int(items.get("seed.eggplant", 0)) != authored_seed_count or int(items.get("food.eggplant", 0)) != 12: return false
	for id in WORKER_IDS:
		if c.get_optional(&"population").get_live_actor(id) == null: return false
	return true

func _finish() -> void:
	print("CANYON_SKIP_OK" if failures.is_empty() else "CANYON_SKIP_FAILED " + str(failures))
	root.remove_child(game)
	game.free()
	quit(0 if failures.is_empty() else 1)
