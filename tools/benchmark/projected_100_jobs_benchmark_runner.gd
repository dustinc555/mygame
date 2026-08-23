extends SceneTree
## Uncapped headless profiler for 100 realized/projected characters.
## Modes: idle, running, jobs_no_field, jobs, jobs_running.

const SCENE_PATH := "res://scenes/test_levels/projected_100_jobs_benchmark.tscn"
const RESULT_PREFIX := "PROJECTED_100_JOBS_BENCHMARK_RESULT "

var _mode := "idle"
var _actor_count := 100
var _warmup_seconds := 3.0
var _sample_seconds := 8.0
var _scene: Node
var _ecs_placeholder: Node
var _failures: Array[String] = []
var _frame_msec: Array[float] = []
var _process_msec: Array[float] = []
var _physics_msec: Array[float] = []
var _gecs_msec: Array[float] = []
var _farm_work_msec: Array[float] = []
var _farm_assignment_loop_msec: Array[float] = []
var _farm_commit_flush_msec: Array[float] = []
var _job_dispatch_msec: Array[float] = []
var _peak_active_work := 0
var _hot_path_profile: Dictionary = {}
var _profile_hot_paths := false


func _initialize() -> void:
	_register_ecs_compile_placeholder()
	_parse_args()
	OS.low_processor_usage_mode = false
	OS.low_processor_usage_mode_sleep_usec = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	call_deferred("_run")


func _run() -> void:
	if _mode not in ["idle", "running", "jobs_no_field", "jobs", "jobs_running"]:
		_failures.append("Unknown benchmark mode: %s" % _mode)
		_finish(0.0, {}, {})
		return
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_failures.append("Could not load benchmark scene")
		_finish(0.0, {}, {})
		return
	_scene = packed.instantiate()
	if _scene == null:
		_failures.append("Could not instantiate benchmark scene")
		_finish(0.0, {}, {})
		return
	_scene.call("configure_benchmark", _actor_count)
	root.add_child(_scene)
	var setup_started := Time.get_ticks_usec()
	if not bool(await _scene.call("wait_until_benchmark_ready", 1800)):
		_failures.append("Benchmark scene did not become ready")
		_finish(0.0, {}, {})
		return
	if not bool(_scene.call("apply_benchmark_mode", _mode)):
		_failures.append("Could not apply benchmark mode")
		_finish(0.0, {}, {})
		return
	if _profile_hot_paths:
		_hot_path_profile = _scene.call("profile_benchmark_hot_paths")
	if not await _wait_for_non_vacuous_mode():
		_finish(0.0, {}, {})
		return
	var setup_seconds := float(Time.get_ticks_usec() - setup_started) / 1_000_000.0
	var start_snapshot: Dictionary = _scene.call("get_benchmark_snapshot")
	_validate_mode_snapshot(start_snapshot, true)
	print("PROJECTED_100_JOBS_BENCHMARK_START mode=%s actors=%d warmup_seconds=%.1f sample_seconds=%.1f" % [
		_mode, _actor_count, _warmup_seconds, _sample_seconds
	])
	await _wait_wall_seconds(_warmup_seconds)
	var completed_before := int((_scene.call("get_benchmark_snapshot") as Dictionary).get("work_completed_count", 0))
	var distance_before := float((_scene.call("get_benchmark_snapshot") as Dictionary).get("total_distance", 0.0))
	var sample_started := Time.get_ticks_usec()
	var previous_usec := sample_started
	while float(Time.get_ticks_usec() - sample_started) / 1_000_000.0 < _sample_seconds:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		var frame_ms := float(now_usec - previous_usec) / 1000.0
		previous_usec = now_usec
		if frame_ms <= 0.0:
			continue
		_frame_msec.append(frame_ms)
		_process_msec.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		_physics_msec.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		_gecs_msec.append(float(_scene.call("get_gecs_world_process_msec")))
		_farm_work_msec.append(float(_scene.call("get_farm_work_process_msec")))
		var farm_breakdown: Dictionary = _scene.call("get_farm_work_process_breakdown")
		_farm_assignment_loop_msec.append(float(farm_breakdown.get("assignment_loop_msec", 0.0)))
		_farm_commit_flush_msec.append(float(farm_breakdown.get("commit_flush_msec", 0.0)))
		_job_dispatch_msec.append(float(_scene.call("get_job_dispatch_msec")))
		_peak_active_work = maxi(_peak_active_work, int(_scene.call("get_active_work_count")))
	var measured_seconds := float(Time.get_ticks_usec() - sample_started) / 1_000_000.0
	var end_snapshot: Dictionary = _scene.call("get_benchmark_snapshot")
	_validate_mode_snapshot(end_snapshot, false)
	var completed_delta := int(end_snapshot.get("work_completed_count", 0)) - completed_before
	var distance_delta := float(end_snapshot.get("total_distance", 0.0)) - distance_before
	if _mode == "jobs" and (_peak_active_work <= 0 or (distance_delta <= 1.0 and completed_delta <= 0)):
		_failures.append("Jobs mode never produced active work plus movement or completion")
	if _mode == "jobs_running" and distance_delta <= 1.0:
		_failures.append("Jobs-running mode did not produce real running movement")
	_finish(measured_seconds, start_snapshot, end_snapshot, setup_seconds, completed_delta, distance_delta)


func _wait_for_non_vacuous_mode() -> bool:
	var distance_start := float((_scene.call("get_benchmark_snapshot") as Dictionary).get("total_distance", 0.0))
	for _frame in 900:
		var snapshot: Dictionary = _scene.call("get_benchmark_snapshot")
		if _mode == "idle":
			return true
		if _mode == "jobs_no_field" \
				and int(snapshot.get("jobs_enabled_count", 0)) == _actor_count \
				and str(snapshot.get("farm_plot_id", "")).is_empty() \
				and int(snapshot.get("active_work_count", 0)) == 0:
			return true
		if _mode == "jobs" and int(snapshot.get("active_work_count", 0)) > 0:
			return true
		if _mode in ["running", "jobs_running"] \
				and int(snapshot.get("running_requested_count", 0)) == _actor_count \
				and int(snapshot.get("move_target_count", 0)) == _actor_count \
				and float(snapshot.get("total_distance", 0.0)) > distance_start + 0.1:
			return true
		await physics_frame
	_failures.append("Benchmark mode never became non-vacuous: %s" % _mode)
	return false


func _validate_mode_snapshot(snapshot: Dictionary, at_start: bool) -> void:
	var phase := "start" if at_start else "end"
	if int(snapshot.get("actor_count", -1)) != _actor_count:
		_failures.append("%s actor count mismatch" % phase)
	if int(snapshot.get("projected_count", -1)) != _actor_count:
		_failures.append("%s projected count mismatch" % phase)
	if int(snapshot.get("alive_count", -1)) != _actor_count:
		_failures.append("%s alive count mismatch" % phase)
	var expected_jobs := _actor_count if _mode in ["jobs_no_field", "jobs", "jobs_running"] else 0
	if int(snapshot.get("jobs_enabled_count", -1)) != expected_jobs:
		_failures.append("%s Jobs-enabled count mismatch" % phase)
	if _mode == "idle":
		if int(snapshot.get("running_requested_count", -1)) != 0 or int(snapshot.get("move_target_count", -1)) != 0:
			_failures.append("%s idle actors are not actually idle" % phase)
		if int(snapshot.get("active_work_count", -1)) != 0:
			_failures.append("%s idle mode has active work" % phase)
	elif _mode == "jobs_no_field":
		if not str(snapshot.get("farm_plot_id", "")).is_empty() or int(snapshot.get("active_work_count", -1)) != 0:
			_failures.append("%s Jobs/no-field mode has field work" % phase)
		if int(snapshot.get("running_requested_count", -1)) != 0 or int(snapshot.get("move_target_count", -1)) != 0:
			_failures.append("%s Jobs/no-field actors are not idle" % phase)
	elif _mode in ["running", "jobs_running"]:
		if int(snapshot.get("running_requested_count", -1)) != _actor_count:
			_failures.append("%s not every actor is set to run" % phase)
		if at_start and int(snapshot.get("move_target_count", -1)) != _actor_count:
			_failures.append("%s not every running actor has a target" % phase)


func _wait_wall_seconds(seconds: float) -> void:
	var started := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1_000_000.0 < maxf(seconds, 0.0):
		await process_frame


func _finish(measured_seconds: float, start_snapshot: Dictionary, end_snapshot: Dictionary, setup_seconds := 0.0, completed_delta := 0, distance_delta := 0.0) -> void:
	var frame_count := _frame_msec.size()
	var total_frame_msec := _sum(_frame_msec)
	var average_frame_msec := total_frame_msec / float(maxi(frame_count, 1))
	var worst_frame_msec := _max_value(_frame_msec)
	var report := {
		"mode": _mode,
		"actor_count": _actor_count,
		"setup_seconds": setup_seconds,
		"sample_seconds": measured_seconds,
		"sample_frames": frame_count,
		"avg_fps": 1000.0 / maxf(average_frame_msec, 0.0001),
		"min_fps": 1000.0 / maxf(worst_frame_msec, 0.0001),
		"frame_msec": _stats(_frame_msec),
		"process_msec": _stats(_process_msec),
		"physics_msec": _stats(_physics_msec),
		"gecs_msec": _stats(_gecs_msec),
		"farm_work_msec": _stats(_farm_work_msec),
		"farm_assignment_loop_msec": _stats(_farm_assignment_loop_msec),
		"farm_commit_flush_msec": _stats(_farm_commit_flush_msec),
		"job_dispatch_msec": _stats(_job_dispatch_msec),
		"hot_path_profile": _hot_path_profile,
		"peak_active_work": _peak_active_work,
		"completed_work_delta": completed_delta,
		"distance_delta": distance_delta,
		"start": start_snapshot,
		"end": end_snapshot,
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"memory_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"failures": _failures,
	}
	print(RESULT_PREFIX + JSON.stringify(report))
	var exit_code := 0 if _failures.is_empty() and frame_count > 0 else 1
	if frame_count <= 0:
		push_error("Benchmark collected no frames")
	for failure in _failures:
		push_error(failure)
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
		_scene = null
	quit(exit_code)


func _stats(values: Array[float]) -> Dictionary:
	return {
		"avg": _sum(values) / float(maxi(values.size(), 1)),
		"p50": _percentile(values, 0.50),
		"p95": _percentile(values, 0.95),
		"p99": _percentile(values, 0.99),
		"p999": _percentile(values, 0.999),
		"max": _max_value(values),
	}


func _sum(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total


func _max_value(values: Array[float]) -> float:
	var maximum := 0.0
	for value in values:
		maximum = maxf(maximum, value)
	return maximum


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var ordered := values.duplicate()
	ordered.sort()
	var index := clampi(ceili(clampf(ratio, 0.0, 1.0) * float(ordered.size())) - 1, 0, ordered.size() - 1)
	return ordered[index]


func _parse_args() -> void:
	var arguments := OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	for argument_value in arguments:
		var argument := str(argument_value)
		if argument.begins_with("--benchmark-mode="):
			_mode = argument.get_slice("=", 1)
		elif argument.begins_with("--benchmark-actors="):
			_actor_count = clampi(int(argument.get_slice("=", 1)), 0, 100)
		elif argument.begins_with("--benchmark-warmup="):
			_warmup_seconds = maxf(float(argument.get_slice("=", 1)), 0.0)
		elif argument.begins_with("--benchmark-sample="):
			_sample_seconds = maxf(float(argument.get_slice("=", 1)), 1.0)
		elif argument == "--benchmark-profile-hot-paths":
			_profile_hot_paths = true


func _register_ecs_compile_placeholder() -> void:
	if Engine.has_singleton("ECS") or root.get_node_or_null("ECS") != null:
		return
	_ecs_placeholder = Node.new()
	_ecs_placeholder.name = "ECS"
	Engine.register_singleton("ECS", _ecs_placeholder)
