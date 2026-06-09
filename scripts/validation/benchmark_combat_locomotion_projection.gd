extends SceneTree

const BASELINE_PATH := "res://benchmarks/projection_baselines.json"
const REPORT_PATH := "res://benchmarks/combat_locomotion_projection_report.json"
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
	var baselines := _load_baselines_by_id()
	var reports: Array[Dictionary] = []
	for scenario in SCENARIOS:
		reports.append(await _benchmark_scenario(scenario, baselines))
	var report := {
		"schema_version": 1,
		"issue": 107,
		"baseline_path": BASELINE_PATH,
		"command": "godot --headless --path . --script scripts/validation/benchmark_combat_locomotion_projection.gd",
		"sample_frames": SAMPLE_FRAME_COUNT,
		"projection_sync_samples": PROJECTION_SYNC_SAMPLES,
		"scenarios": reports,
	}
	_write_report(report)
	for scenario_report in reports:
		print("COMBAT_LOCOMOTION_PROJECTION_RESULT %s" % JSON.stringify(scenario_report))
	_finish(reports.size())


func _benchmark_scenario(scenario: Dictionary, baselines: Dictionary) -> Dictionary:
	var scene_path := str(scenario.get("path", ""))
	var scenario_id := str(scenario.get("id", ""))
	var expected_actors := int(scenario.get("actors", 0))
	var baseline: Dictionary = baselines.get(scenario_id, {}) if baselines.get(scenario_id, {}) is Dictionary else {}
	_expect(not baseline.is_empty(), "%s baseline exists in %s" % [scenario_id, BASELINE_PATH])
	var scene_resource := load(scene_path) as PackedScene
	_expect(scene_resource != null, "%s locomotion benchmark scene loads" % scenario_id)
	if scene_resource == null:
		return _empty_report(scenario, baseline)
	var scene := scene_resource.instantiate()
	scene.set("combat_locomotion_projection_enabled", true)
	root.add_child(scene)
	await process_frame
	await _wait_for_ready(scene, scenario_id)
	var before_positions: Dictionary = scene.call("get_population_position_snapshot") if scene.has_method("get_population_position_snapshot") else {}
	for _frame in range(WARMUP_FRAMES):
		await process_frame
	var frame_metrics := await _sample_frame_metrics()
	var sync_metrics: Dictionary = scene.call("measure_projection_sync", PROJECTION_SYNC_SAMPLES) if scene.has_method("measure_projection_sync") else {}
	var state: Dictionary = scene.call("get_benchmark_state") if scene.has_method("get_benchmark_state") else {}
	var after_positions: Dictionary = scene.call("get_population_position_snapshot") if scene.has_method("get_population_position_snapshot") else {}
	var locomotion_metrics: Dictionary = state.get("combat_locomotion_metrics", {}) if state.get("combat_locomotion_metrics", {}) is Dictionary else {}
	var mutation_count := _position_mutation_count(before_positions, after_positions)
	_expect(int(state.get("projected_actor_count", 0)) == expected_actors, "%s projects expected actor count" % scenario_id)
	_expect(int(state.get("visible_actor_count", 0)) == expected_actors, "%s keeps all actors visible" % scenario_id)
	_expect(not bool(state.get("battle_sim_included", true)), "%s does not resolve BattleSim during projection locomotion" % scenario_id)
	_expect(int(state.get("active_held_encounter_count", 0)) == 1, "%s keeps one held GECS encounter" % scenario_id)
	_expect(bool(locomotion_metrics.get("enabled", false)), "%s enables combat locomotion projection" % scenario_id)
	_expect(int(locomotion_metrics.get("pair_check_count", 0)) <= int(locomotion_metrics.get("max_allowed_pair_checks", 0)), "%s keeps local pair checks bounded" % scenario_id)
	_expect(int(locomotion_metrics.get("overlap_violations", 0)) == 0, "%s has no overlap violations" % scenario_id)
	_expect(int(locomotion_metrics.get("pass_through_violations", 0)) == 0, "%s has no pass-through violations" % scenario_id)
	_expect(mutation_count == 0, "%s projection locomotion does not mutate GECS positions" % scenario_id)
	var before_fps := float(baseline.get("average_fps", 0.0))
	var after_fps := float(frame_metrics.get("average_fps", 0.0))
	var before_projection_ms := float(baseline.get("projection_sync_average_ms", 0.0))
	var after_projection_ms := float(sync_metrics.get("average_ms", state.get("average_projection_sync_ms", 0.0)))
	var report := {
		"scenario_id": scenario_id,
		"scene_path": scene_path,
		"actor_count": expected_actors,
		"before_average_fps": before_fps,
		"after_average_fps": after_fps,
		"average_fps_delta": after_fps - before_fps,
		"before_min_fps": float(baseline.get("min_fps", 0.0)),
		"after_min_fps": float(frame_metrics.get("min_fps", 0.0)),
		"min_fps_delta": float(frame_metrics.get("min_fps", 0.0)) - float(baseline.get("min_fps", 0.0)),
		"before_projection_update_ms": before_projection_ms,
		"after_projection_update_ms": after_projection_ms,
		"projection_update_delta_ms": after_projection_ms - before_projection_ms,
		"visible_actor_count": int(state.get("visible_actor_count", 0)),
		"projected_actor_count": int(state.get("projected_actor_count", 0)),
		"neighbor_pair_check_count": int(locomotion_metrics.get("pair_check_count", 0)),
		"max_allowed_pair_checks": int(locomotion_metrics.get("max_allowed_pair_checks", 0)),
		"overlap_violations": int(locomotion_metrics.get("overlap_violations", 0)),
		"pass_through_violations": int(locomotion_metrics.get("pass_through_violations", 0)),
		"gecs_position_mutation_count": mutation_count,
		"gecs_tick_ms": float(state.get("gecs_tick_ms", 0.0)),
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
	_failures.append("%s locomotion benchmark becomes ready within wait budget" % scenario_id)


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


func _load_baselines_by_id() -> Dictionary:
	var result := {}
	var file := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	if file == null:
		_failures.append("Could not read baseline file: %s" % BASELINE_PATH)
		return result
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		_failures.append("Baseline file is not a dictionary: %s" % BASELINE_PATH)
		return result
	var scenarios = (parsed as Dictionary).get("scenarios", [])
	if not (scenarios is Array):
		_failures.append("Baseline file has no scenarios array: %s" % BASELINE_PATH)
		return result
	for entry in scenarios:
		if entry is Dictionary:
			var scenario_id := str((entry as Dictionary).get("scenario_id", ""))
			if not scenario_id.is_empty():
				result[scenario_id] = (entry as Dictionary).duplicate(true)
	return result


func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write locomotion projection report: %s" % REPORT_PATH)
		return
	file.store_string(JSON.stringify(report, "  "))


func _position_mutation_count(before_positions: Dictionary, after_positions: Dictionary) -> int:
	var count := 0
	for actor_id in before_positions.keys():
		var before = before_positions.get(actor_id)
		var after = after_positions.get(actor_id)
		if not (before is Vector3) or not (after is Vector3):
			count += 1
			continue
		if (before as Vector3).distance_to(after as Vector3) > 0.001:
			count += 1
	return count


func _empty_report(scenario: Dictionary, baseline: Dictionary) -> Dictionary:
	return {
		"scenario_id": str(scenario.get("id", "")),
		"scene_path": str(scenario.get("path", "")),
		"actor_count": int(scenario.get("actors", 0)),
		"before_average_fps": float(baseline.get("average_fps", 0.0)),
		"after_average_fps": 0.0,
		"average_fps_delta": -float(baseline.get("average_fps", 0.0)),
		"before_projection_update_ms": float(baseline.get("projection_sync_average_ms", 0.0)),
		"after_projection_update_ms": 0.0,
		"projection_update_delta_ms": -float(baseline.get("projection_sync_average_ms", 0.0)),
		"visible_actor_count": 0,
		"neighbor_pair_check_count": 0,
		"max_allowed_pair_checks": 0,
		"overlap_violations": 0,
		"pass_through_violations": 0,
		"gecs_position_mutation_count": 0,
	}


func _finish(scenario_count: int) -> void:
	if _failures.is_empty():
		print("COMBAT_LOCOMOTION_PROJECTION_BENCHMARK_OK scenarios=%d sample_frames=%d report=%s" % [scenario_count, SAMPLE_FRAME_COUNT, REPORT_PATH])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("COMBAT_LOCOMOTION_PROJECTION_BENCHMARK_FAILED scenarios=%d sample_frames=%d report=%s" % [scenario_count, SAMPLE_FRAME_COUNT, REPORT_PATH])
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
