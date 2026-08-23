extends Node3D

class_name ProjectedHundredJobsBenchmarkLevel

signal benchmark_ready

const PARTY_MEMBER_SCENE := preload("res://features/core/party/party_member.tscn")
const HOE := preload("res://features/inventory/resources/items/hoe.tres")
const BENCHMARK_SETTLEMENT_ID := "projected_jobs_benchmark"
const FARM_WIDTH := 20
const FARM_HEIGHT := 10
const FARM_CELL_SIZE := 1.25
const RUN_TARGET_X := 88.0

@export_range(0, 100, 1) var actor_count := 100
@export var create_farm_on_start := true
@export var interactive_stress_test := false

var _actors: Array[WorldActor] = []
var _initial_positions: Dictionary = {}
var _job_system: JobSystemController
var _farm: FarmController
var _farm_work: FarmWorkBridge
var _population_realization: PopulationRealizationController
var _gecs: GecsWorldController
var _navigation: WorldNavigationController
var _loading_overlay: NavigationLoadingOverlay
var _benchmark_ready := false
var _farm_plot_id := ""
var _mode := "idle"
var _work_completed_count := 0
var _stress_frame_msec: Array[float] = []
var _stress_warmup_remaining := 0.0
var _stress_refresh_remaining := 0.0


func configure_benchmark(count: int) -> void:
	if is_inside_tree():
		return
	actor_count = clampi(count, 0, 100)


func _enter_tree() -> void:
	_spawn_benchmark_actors()


func _ready() -> void:
	var party_manager := get_node_or_null("PartyManager") as PartyManager
	if party_manager != null:
		party_manager.set_party_members(_actors)
	set_process(interactive_stress_test)
	call_deferred("_initialize_benchmark_services")


func _process(delta: float) -> void:
	if not interactive_stress_test or not _benchmark_ready:
		return
	_stress_refresh_remaining -= delta
	if _stress_warmup_remaining > 0.0:
		_stress_warmup_remaining = maxf(0.0, _stress_warmup_remaining - delta)
	elif delta > 0.0:
		_stress_frame_msec.append(delta * 1000.0)
		if _stress_frame_msec.size() > 600:
			_stress_frame_msec.pop_front()
	if _stress_refresh_remaining <= 0.0:
		_stress_refresh_remaining = 0.25
		_update_stress_metrics()


func _spawn_benchmark_actors() -> void:
	var party_root := get_node_or_null("PartyMembers") as Node3D
	if party_root == null or not _actors.is_empty():
		return
	var columns := 10
	var rows := ceili(float(maxi(actor_count, 1)) / float(columns))
	var spacing := 2.15
	var x_origin := -0.5 * float(columns - 1) * spacing
	var z_origin := 8.0 + 0.5 * float(rows - 1) * spacing
	for index in actor_count:
		var actor := PARTY_MEMBER_SCENE.instantiate() as PartyMember
		if actor == null:
			continue
		var row := index / columns
		var column := index % columns
		actor.name = "BenchmarkWorker%03d" % (index + 1)
		actor.stable_id = "benchmark.worker.%03d" % (index + 1)
		actor.member_name = "Worker %03d" % (index + 1)
		actor.faction_name = "Player"
		actor.base_color = Color.from_hsv(float(index % 20) / 20.0, 0.48, 0.78)
		# Seat the capsule bottom on the floor immediately; avoid measuring a
		# 100-body startup fall as idle movement.
		actor.position = Vector3(x_origin + float(column) * spacing, -0.4, z_origin - float(row) * spacing)
		actor.set_meta("assigned_settlement_id", BENCHMARK_SETTLEMENT_ID)
		var hoe_stock := InventoryStock.new()
		hoe_stock.item_definition = HOE
		hoe_stock.quantity = 1
		actor.starting_items = [hoe_stock]
		party_root.add_child(actor)
		_actors.append(actor)
		_initial_positions[actor.stable_id] = actor.position


func _initialize_benchmark_services() -> void:
	for _frame in 1200:
		var context := BootstrapContext.active
		if context != null and context.root_scene == self:
			_job_system = context.get_optional(JobSystemController.SERVICE_ID) as JobSystemController
			_farm = context.get_optional(FarmController.SERVICE_ID) as FarmController
			_farm_work = context.get_optional(FarmWorkBridge.SERVICE_ID) as FarmWorkBridge
			_population_realization = context.get_optional(PopulationRealizationController.SERVICE_ID) as PopulationRealizationController
			_gecs = context.get_optional(GecsWorldController.SERVICE_ID) as GecsWorldController
			_navigation = context.get_optional(WorldNavigationController.SERVICE_ID) as WorldNavigationController
			_loading_overlay = context.get_optional(NavigationLoadingOverlay.SERVICE_ID) as NavigationLoadingOverlay
			if _job_system != null and _farm != null and _farm_work != null and _gecs != null \
					and _navigation != null and _loading_overlay != null:
				break
		await get_tree().process_frame
	if _job_system == null or _farm == null or _farm_work == null or _gecs == null \
			or _navigation == null or _loading_overlay == null:
		push_error("Projected Jobs benchmark failed to resolve required services")
		return
	if create_farm_on_start:
		_create_benchmark_farm()
	for _frame in 1200:
		if _all_actors_registered() and not _navigation.is_initial_navigation_pending() \
				and _navigation.is_idle() and not _loading_overlay.is_loading_gate_active() and not get_tree().paused:
			_benchmark_ready = true
			benchmark_ready.emit()
			if interactive_stress_test:
				_setup_stress_controls()
				set_stress_mode("jobs_no_field")
			return
		await get_tree().process_frame
	push_error("Projected Jobs benchmark timed out waiting for actor registration/navigation")


func _create_benchmark_farm() -> void:
	if actor_count <= 0 or _farm == null or not _farm.get_plots().is_empty():
		return
	var positions: Array[Vector3] = []
	var x_origin := -0.5 * float(FARM_WIDTH - 1) * FARM_CELL_SIZE
	var z_origin := -24.0
	for z in FARM_HEIGHT:
		for x in FARM_WIDTH:
			positions.append(Vector3(x_origin + float(x) * FARM_CELL_SIZE, 0.02, z_origin + float(z) * FARM_CELL_SIZE))
	var plot := _farm.create_plot(
		positions,
		Vector2i(FARM_WIDTH, FARM_HEIGHT),
		"",
		"Player",
		BENCHMARK_SETTLEMENT_ID
	)
	_farm_plot_id = str(plot.get("plot_id", ""))
	if _farm_plot_id.is_empty():
		push_error("Projected Jobs benchmark could not create its farm")
		return
	_farm.set_plot_crop_policy(_farm_plot_id, "tomato", _actors[0])
	if not _farm.work_completed.is_connected(_on_farm_work_completed):
		_farm.work_completed.connect(_on_farm_work_completed)


func _all_actors_registered() -> bool:
	if _gecs == null or _actors.size() != actor_count:
		return false
	for actor in _actors:
		if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree() \
				or _gecs.get_actor_by_stable_id(actor.stable_id) != actor:
			return false
	return true


func wait_until_benchmark_ready(max_frames := 1200) -> bool:
	for _frame in maxi(max_frames, 1):
		if _benchmark_ready:
			return true
		await get_tree().process_frame
	return false


func apply_benchmark_mode(mode: String) -> bool:
	if not _benchmark_ready or mode not in ["idle", "running", "jobs_no_field", "jobs", "jobs_running"]:
		return false
	if mode == "jobs_no_field":
		_set_benchmark_farm_enabled(false)
	elif mode in ["jobs", "jobs_running"]:
		_set_benchmark_farm_enabled(true)
	_mode = mode
	var jobs_enabled := mode in ["jobs_no_field", "jobs", "jobs_running"]
	for actor in _actors:
		if actor == null or not is_instance_valid(actor):
			continue
		_farm_work.cancel_work_for_actor(actor)
		actor.stop_movement()
		actor.set_running_enabled(false)
		if not _job_system.set_actor_jobs_enabled(actor, jobs_enabled):
			return false
		if mode in ["running", "jobs_running"]:
			actor.set_running_enabled(true)
			actor.set_move_target(_run_target_for(actor), true)
	return true


func _set_benchmark_farm_enabled(enabled: bool) -> void:
	if _farm == null:
		return
	for actor in _actors:
		if actor != null and is_instance_valid(actor):
			_farm_work.cancel_work_for_actor(actor)
	if enabled:
		if _farm_plot_id.is_empty():
			_create_benchmark_farm()
		return
	if not _farm_plot_id.is_empty():
		_farm.remove_plot(_farm_plot_id)
	_farm_plot_id = ""


func _setup_stress_controls() -> void:
	var no_field := get_node_or_null("StressHUD/Panel/Content/Controls/NoFieldJobs") as Button
	var active_field := get_node_or_null("StressHUD/Panel/Content/Controls/ActiveFieldJobs") as Button
	var reset := get_node_or_null("StressHUD/Panel/Content/Controls/ResetStats") as Button
	if no_field != null and not no_field.pressed.is_connected(set_stress_mode.bind("jobs_no_field")):
		no_field.pressed.connect(set_stress_mode.bind("jobs_no_field"))
	if active_field != null and not active_field.pressed.is_connected(set_stress_mode.bind("jobs")):
		active_field.pressed.connect(set_stress_mode.bind("jobs"))
	if reset != null and not reset.pressed.is_connected(reset_stress_metrics):
		reset.pressed.connect(reset_stress_metrics)


func set_stress_mode(mode: String) -> bool:
	if not apply_benchmark_mode(mode):
		return false
	reset_stress_metrics()
	return true


func reset_stress_metrics() -> void:
	_stress_frame_msec.clear()
	_stress_warmup_remaining = 2.0
	_stress_refresh_remaining = 0.0
	_update_stress_metrics()


func _update_stress_metrics() -> void:
	var label := get_node_or_null("StressHUD/Panel/Content/StressMetrics") as Label
	if label == null:
		return
	var snapshot := get_benchmark_snapshot()
	if _stress_warmup_remaining > 0.0:
		label.text = "%s | WARMUP %.1fs | actors=%d jobs=%d active=%d" % [
			_stress_mode_label(),
			_stress_warmup_remaining,
			int(snapshot.get("projected_count", 0)),
			int(snapshot.get("jobs_enabled_count", 0)),
			int(snapshot.get("active_work_count", 0)),
		]
		return
	if _stress_frame_msec.is_empty():
		label.text = "%s | collecting frame samples..." % _stress_mode_label()
		return
	var total_msec := 0.0
	for frame_msec in _stress_frame_msec:
		total_msec += frame_msec
	var average_msec := total_msec / float(_stress_frame_msec.size())
	var ordered := _stress_frame_msec.duplicate()
	ordered.sort()
	var p99_index := clampi(ceili(float(ordered.size()) * 0.99) - 1, 0, ordered.size() - 1)
	label.text = "%s | FPS %.1f | avg %.1fms | p99 %.1fms | samples %d | active %d | completed %d" % [
		_stress_mode_label(),
		1000.0 / maxf(average_msec, 0.0001),
		average_msec,
		ordered[p99_index],
		_stress_frame_msec.size(),
		int(snapshot.get("active_work_count", 0)),
		int(snapshot.get("work_completed_count", 0)),
	]


func _stress_mode_label() -> String:
	return "JOBS + ACTIVE FIELD" if _mode == "jobs" else "JOBS + NO FIELD" if _mode == "jobs_no_field" else _mode.to_upper()


func get_benchmark_snapshot() -> Dictionary:
	var projected_count := 0
	var jobs_enabled_count := 0
	var running_requested_count := 0
	var actually_running_count := 0
	var move_target_count := 0
	var alive_count := 0
	for actor in _actors:
		if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
			continue
		if _population_realization == null or _population_realization.is_position_within_realization_range(actor.global_position):
			projected_count += 1
		if _job_system != null and _job_system.is_actor_jobs_enabled(actor):
			jobs_enabled_count += 1
		if actor.is_running_requested():
			running_requested_count += 1
		if actor.has_move_target():
			move_target_count += 1
		if actor.is_running_enabled() and Vector2(actor.velocity.x, actor.velocity.z).length_squared() > 0.01:
			actually_running_count += 1
		if actor.life_state == NpcRules.LifeState.ALIVE:
			alive_count += 1
	return {
		"mode": _mode,
		"actor_count": _actors.size(),
		"projected_count": projected_count,
		"alive_count": alive_count,
		"jobs_enabled_count": jobs_enabled_count,
		"running_requested_count": running_requested_count,
		"actually_running_count": actually_running_count,
		"move_target_count": move_target_count,
		"active_work_count": get_active_work_count(),
		"work_completed_count": _work_completed_count,
		"total_distance": get_total_distance_travelled(),
		"farm_plot_id": _farm_plot_id,
	}


func get_active_work_count() -> int:
	if _farm_work == null:
		return 0
	var assignments = _farm_work.get("_assignments")
	return (assignments as Dictionary).size() if assignments is Dictionary else 0


func get_total_distance_travelled() -> float:
	var total := 0.0
	for actor in _actors:
		if actor == null or not is_instance_valid(actor):
			continue
		var start: Vector3 = _initial_positions.get(actor.stable_id, actor.global_position)
		total += actor.global_position.distance_to(start)
	return total


func get_gecs_world_process_msec() -> float:
	return float(_gecs.get("_last_world_process_usec")) / 1000.0 if _gecs != null else 0.0


func get_farm_work_process_msec() -> float:
	return _farm_work.get_last_process_msec() if _farm_work != null else 0.0


func get_farm_work_process_breakdown() -> Dictionary:
	return _farm_work.get_last_process_breakdown() if _farm_work != null else {}


func get_job_dispatch_msec() -> float:
	return _job_system.get_last_dispatch_msec() if _job_system != null else 0.0


func profile_benchmark_hot_paths() -> Dictionary:
	if not _benchmark_ready:
		return {}
	var started := Time.get_ticks_usec()
	var offers := _farm_work.get_available_work_offers()
	var offer_read_msec := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var enabled_reads := 0
	for actor in _actors:
		if _job_system.is_actor_jobs_enabled(actor):
			enabled_reads += 1
	var policy_read_msec := float(Time.get_ticks_usec() - started) / 1000.0
	var single_rank_read_msec := 0.0
	var single_accept_msec := 0.0
	var single_cell_read_msec := 0.0
	var single_owner_read_msec := 0.0
	var single_tool_read_msec := 0.0
	var single_tool_find_msec := 0.0
	var single_tool_equip_msec := 0.0
	var tool_equip_breakdown: Dictionary = {}
	var tool_equip_succeeded := false
	var tool_equip_preserved_visual_root := false
	var tool_equip_preserved_skeleton := false
	var tool_equip_visual_present := false
	var single_move_start_msec := 0.0
	if _mode == "jobs" and not _actors.is_empty() and not offers.is_empty():
		var profile_actor: WorldActor = _actors.back()
		var probe_actor: WorldActor = _actors[maxi(_actors.size() - 2, 0)]
		for candidate in _actors:
			var candidate_equipment := candidate.get_equipment()
			var candidate_weapon = candidate_equipment.get_equipped_item("weapon") if candidate_equipment != null else null
			if not _farm_work.has_active_work_for_actor(candidate) \
					and (candidate_weapon == null or not candidate_weapon.has_tool_tag("tool.hoe")):
				probe_actor = candidate
				break
		var profile_offer: Dictionary = offers[0]
		started = Time.get_ticks_usec()
		_job_system.get_actor_ranked_jobs(profile_actor)
		single_rank_read_msec = float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		var profile_work: Dictionary = _farm.get_cell_work(str(profile_offer.get("plot_id", "")), str(profile_offer.get("cell_key", "")))
		single_cell_read_msec = float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		_farm.can_actor_command_plot(probe_actor, str(profile_offer.get("plot_id", "")))
		single_owner_read_msec = float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		var tool_entry = _farm_work._find_tool_entry(probe_actor, str(profile_work.get("required_tool_tag", "")))
		single_tool_find_msec = float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		var equipment = probe_actor.get_equipment()
		var body_before := probe_actor.get_body_projection()
		var visual_root_before := body_before.get_visual_root() if body_before != null else null
		var skeleton_before: Skeleton3D = body_before._find_skeleton(visual_root_before) as Skeleton3D if body_before != null and visual_root_before != null else null
		tool_equip_succeeded = _farm_work._equip_carried_tool(probe_actor, equipment, tool_entry)
		single_tool_equip_msec = float(Time.get_ticks_usec() - started) / 1000.0
		tool_equip_breakdown = _farm_work.get_last_tool_equip_timings()
		var body_after := probe_actor.get_body_projection()
		var visual_root_after := body_after.get_visual_root() if body_after != null else null
		tool_equip_preserved_visual_root = tool_equip_succeeded and visual_root_before != null and is_instance_valid(visual_root_before) \
				and visual_root_after == visual_root_before
		var skeleton_after: Skeleton3D = body_after._find_skeleton(visual_root_after) as Skeleton3D if body_after != null and visual_root_after != null else null
		tool_equip_preserved_skeleton = tool_equip_succeeded and skeleton_before != null and is_instance_valid(skeleton_before) \
				and skeleton_after == skeleton_before
		tool_equip_visual_present = tool_equip_succeeded and skeleton_after != null \
				and body_after._find_node3d_by_name(skeleton_after, body_after._get_bone_equipment_visual_name("weapon")) != null
		single_tool_read_msec = single_tool_find_msec + single_tool_equip_msec
		started = Time.get_ticks_usec()
		probe_actor.set_move_target(profile_work.get("world_position", Vector3.ZERO), false)
		single_move_start_msec = float(Time.get_ticks_usec() - started) / 1000.0
		probe_actor.stop_movement()
		started = Time.get_ticks_usec()
		_farm_work.accept_work_offer(offers[0], profile_actor)
		single_accept_msec = float(Time.get_ticks_usec() - started) / 1000.0
		_farm_work.cancel_work_for_actor(profile_actor)
		profile_actor.stop_movement()
	started = Time.get_ticks_usec()
	_job_system._process_party_job_dispatch()
	var dispatch_msec := float(Time.get_ticks_usec() - started) / 1000.0
	return {
		"offer_count": offers.size(),
		"farm_offer_read_msec": offer_read_msec,
		"all_actor_policy_read_msec": policy_read_msec,
		"enabled_policy_reads": enabled_reads,
		"single_rank_read_msec": single_rank_read_msec,
		"single_accept_msec": single_accept_msec,
		"single_cell_read_msec": single_cell_read_msec,
		"single_owner_read_msec": single_owner_read_msec,
		"single_tool_read_msec": single_tool_read_msec,
		"single_tool_find_msec": single_tool_find_msec,
		"single_tool_equip_msec": single_tool_equip_msec,
		"tool_equip_breakdown": tool_equip_breakdown if _mode == "jobs" else {},
		"tool_equip_succeeded": tool_equip_succeeded,
		"tool_equip_preserved_visual_root": tool_equip_preserved_visual_root,
		"tool_equip_preserved_skeleton": tool_equip_preserved_skeleton,
		"tool_equip_visual_present": tool_equip_visual_present,
		"single_move_start_msec": single_move_start_msec,
		"dispatch_once_msec": dispatch_msec,
		"active_work_after_dispatch": get_active_work_count(),
	}


func _run_target_for(actor: WorldActor) -> Vector3:
	var start: Vector3 = _initial_positions.get(actor.stable_id, actor.global_position)
	var target_x := RUN_TARGET_X if start.x <= 0.0 else -RUN_TARGET_X
	return Vector3(target_x, 0.0, start.z)


func _on_farm_work_completed(_result: Dictionary) -> void:
	_work_completed_count += 1
