extends SceneTree

const MAX_WAIT_FRAMES := 360
const WARMUP_FRAMES := 90
const SAMPLE_FRAME_COUNT := 360
const PROJECTION_SYNC_SAMPLES := 5
const SCENARIOS := [
	{"id": "projection_baseline_1v1", "path": "res://scenes/test_levels/projection_baseline_1v1.tscn", "actors": 2},
	{"id": "projection_baseline_5v5", "path": "res://scenes/test_levels/projection_baseline_5v5.tscn", "actors": 10},
	{"id": "projection_baseline_50v50", "path": "res://scenes/test_levels/projection_baseline_50v50.tscn", "actors": 100},
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_benchmark")


func _run_benchmark() -> void:
	var reports: Array[Dictionary] = []
	for scenario in SCENARIOS:
		reports.append(await _benchmark_scenario(scenario))
	for report in reports:
		_print_report(report)
	_finish(reports)


func _benchmark_scenario(scenario: Dictionary) -> Dictionary:
	var scene_path := str(scenario.get("path", ""))
	var scenario_id := str(scenario.get("id", ""))
	var expected_actors := int(scenario.get("actors", 0))
	var scene_resource := load(scene_path) as PackedScene
	_expect(scene_resource != null, "%s benchmark scene loads" % scenario_id)
	if scene_resource == null:
		return _empty_report(scenario)
	var scene := scene_resource.instantiate()
	scene.set("combat_locomotion_projection_enabled", false)
	root.add_child(scene)
	await process_frame
	await _wait_for_ready(scene, scenario_id)
	for _frame in range(WARMUP_FRAMES):
		await process_frame
	var frame_metrics := await _sample_frame_metrics()
	var sync_metrics: Dictionary = scene.call("measure_projection_sync", PROJECTION_SYNC_SAMPLES) if scene.has_method("measure_projection_sync") else {}
	var state: Dictionary = scene.call("get_benchmark_state") if scene.has_method("get_benchmark_state") else {}
	_expect(int(state.get("projected_actor_count", 0)) == expected_actors, "%s benchmark projects expected actor count" % scenario_id)
	_expect(not bool(state.get("battle_sim_included", true)), "%s benchmark excludes BattleSim cost" % scenario_id)
	_expect(int(state.get("active_held_encounter_count", 0)) == 1, "%s benchmark uses held active GECS encounter" % scenario_id)
	var report := {
		"scenario_id": scenario_id,
		"scene_path": scene_path,
		"actor_count": expected_actors,
		"sample_frames": SAMPLE_FRAME_COUNT,
		"average_fps": frame_metrics.get("average_fps", 0.0),
		"min_fps": frame_metrics.get("min_fps", 0.0),
		"projected_actor_count": int(state.get("projected_actor_count", 0)),
		"visible_actor_count": int(state.get("visible_actor_count", 0)),
		"active_animation_count": int(state.get("active_animation_count", 0)),
		"projection_sync_average_ms": float(sync_metrics.get("average_ms", state.get("average_projection_sync_ms", 0.0))),
		"projection_sync_last_ms": float(sync_metrics.get("last_ms", state.get("last_projection_sync_ms", 0.0))),
		"gecs_tick_ms": float(state.get("gecs_tick_ms", 0.0)),
		"battle_sim_included": false,
		"active_held_encounter_count": int(state.get("active_held_encounter_count", 0)),
	}
	scene.queue_free()
	await process_frame
	return report


func _wait_for_ready(scene: Node, scenario_id: String) -> void:
	for _frame in range(MAX_WAIT_FRAMES):
		await process_frame
		if not scene.has_method("get_benchmark_state"):
			continue
		var state = scene.call("get_benchmark_state")
		if state is Dictionary and bool((state as Dictionary).get("ready", false)):
			return
	_failures.append("%s benchmark becomes ready within wait budget" % scenario_id)


func _sample_frame_metrics() -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var previous_usec := started_usec
	var max_frame_seconds := 0.0
	for _frame in range(SAMPLE_FRAME_COUNT):
		await process_frame
		var now_usec := Time.get_ticks_usec()
		var frame_seconds := float(now_usec - previous_usec) / 1000000.0
		max_frame_seconds = maxf(max_frame_seconds, frame_seconds)
		previous_usec = now_usec
	var elapsed_seconds := float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var average_fps := float(SAMPLE_FRAME_COUNT) / maxf(elapsed_seconds, 0.000001)
	var min_fps := 1.0 / maxf(max_frame_seconds, 0.000001)
	return {"average_fps": average_fps, "min_fps": min_fps, "elapsed_seconds": elapsed_seconds}


func _empty_report(scenario: Dictionary) -> Dictionary:
	return {
		"scenario_id": str(scenario.get("id", "")),
		"scene_path": str(scenario.get("path", "")),
		"actor_count": int(scenario.get("actors", 0)),
		"sample_frames": SAMPLE_FRAME_COUNT,
		"average_fps": 0.0,
		"min_fps": 0.0,
		"projected_actor_count": 0,
		"visible_actor_count": 0,
		"active_animation_count": 0,
		"projection_sync_average_ms": 0.0,
		"projection_sync_last_ms": 0.0,
		"gecs_tick_ms": 0.0,
		"battle_sim_included": false,
		"active_held_encounter_count": 0,
	}


func _print_report(report: Dictionary) -> void:
	print("PROJECTION_BASELINE_RESULT %s" % JSON.stringify(report))


func _finish(reports: Array[Dictionary]) -> void:
	if _failures.is_empty():
		print("MINIMAL_PROJECTION_BASELINE_BENCHMARK_OK scenarios=%d sample_frames=%d" % [reports.size(), SAMPLE_FRAME_COUNT])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("MINIMAL_PROJECTION_BASELINE_BENCHMARK_FAILED scenarios=%d sample_frames=%d" % [reports.size(), SAMPLE_FRAME_COUNT])
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
