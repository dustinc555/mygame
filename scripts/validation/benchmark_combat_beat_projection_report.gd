extends SceneTree

const BASELINE_PATH := "res://benchmarks/projection_baselines.json"
const REPORT_PATH := "res://benchmarks/combat_beat_projection_report.json"
const MAX_WAIT_FRAMES := 420
const WARMUP_FRAMES := 90
const SAMPLE_FRAME_COUNT := 360
const PROJECTION_SYNC_SAMPLES := 5
const SCENARIOS := [
	{"id": "combat_beat_1v1", "baseline_id": "projection_baseline_1v1", "path": "res://scenes/test_levels/combat_beat_1v1_test.tscn", "actors": 2},
	{"id": "combat_beat_5v5", "baseline_id": "projection_baseline_5v5", "path": "res://scenes/test_levels/combat_beat_5v5_test.tscn", "actors": 10},
	{"id": "combat_beat_50v50", "baseline_id": "projection_baseline_50v50", "path": "res://scenes/test_levels/combat_beat_50v50_test.tscn", "actors": 100},
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
		"issues": [108, 109, 110],
		"baseline_path": BASELINE_PATH,
		"command": "godot --headless --path . --script scripts/validation/benchmark_combat_beat_projection_report.gd",
		"sample_frames": SAMPLE_FRAME_COUNT,
		"projection_sync_samples": PROJECTION_SYNC_SAMPLES,
		"scenarios": reports,
	}
	_write_report(report)
	for scenario_report in reports:
		print("COMBAT_BEAT_PROJECTION_RESULT %s" % JSON.stringify(scenario_report))
	_finish(reports.size())


func _benchmark_scenario(scenario: Dictionary, baselines: Dictionary) -> Dictionary:
	var scene_path := str(scenario.get("path", ""))
	var scenario_id := str(scenario.get("id", ""))
	var baseline_id := str(scenario.get("baseline_id", ""))
	var source_actors := int(scenario.get("actors", 0))
	var expected_actors := int(scenario.get("projected", source_actors))
	var baseline: Dictionary = baselines.get(baseline_id, {}) if baselines.get(baseline_id, {}) is Dictionary else {}
	_expect(not baseline.is_empty(), "%s baseline exists in %s" % [scenario_id, BASELINE_PATH])
	var scene_resource := load(scene_path) as PackedScene
	_expect(scene_resource != null, "%s projection combat benchmark scene loads" % scenario_id)
	if scene_resource == null:
		return _empty_report(scenario, baseline)
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	await process_frame
	await _wait_for_ready(scene, scenario_id)
	for _frame in range(WARMUP_FRAMES):
		await process_frame
	var frame_metrics := await _sample_frame_metrics()
	var sync_metrics: Dictionary = scene.call("measure_projection_sync", PROJECTION_SYNC_SAMPLES) if scene.has_method("measure_projection_sync") else {}
	var state: Dictionary = scene.call("get_benchmark_state") if scene.has_method("get_benchmark_state") else {}
	if state.is_empty() and scene.has_method("get_review_state"):
		state = scene.call("get_review_state")
	var projection_metrics: Dictionary = _projection_metrics_from_state(state)
	_expect(int(state.get("projected_actor_count", projection_metrics.get("projected_actor_count", 0))) == expected_actors, "%s projects expected actor count" % scenario_id)
	_expect(int(state.get("visible_actor_count", projection_metrics.get("visible_actor_count", 0))) == expected_actors, "%s keeps all actors visible" % scenario_id)
	_expect(bool(projection_metrics.get("combat_projection_active", false)), "%s has active combat projection playback" % scenario_id)
	_expect(int(projection_metrics.get("combat_projection_scheduled_event_count", 0)) > 0, "%s has scheduled combat projection events" % scenario_id)
	var before_fps := float(baseline.get("average_fps", 0.0))
	var after_fps := float(frame_metrics.get("average_fps", 0.0))
	var before_projection_ms := float(baseline.get("projection_sync_average_ms", 0.0))
	var after_projection_ms := float(sync_metrics.get("average_ms", state.get("average_projection_sync_ms", 0.0)))
	var report := {
		"scenario_id": scenario_id,
		"scene_path": scene_path,
		"actor_count": source_actors,
		"expected_projected_actor_count": expected_actors,
		"before_average_fps": before_fps,
		"after_average_fps": after_fps,
		"average_fps_delta": after_fps - before_fps,
		"before_min_fps": float(baseline.get("min_fps", 0.0)),
		"after_min_fps": float(frame_metrics.get("min_fps", 0.0)),
		"min_fps_delta": float(frame_metrics.get("min_fps", 0.0)) - float(baseline.get("min_fps", 0.0)),
		"before_projection_update_ms": before_projection_ms,
		"after_projection_update_ms": after_projection_ms,
		"projection_update_delta_ms": after_projection_ms - before_projection_ms,
		"combat_projection_update_ms": float(projection_metrics.get("combat_projection_update_ms", 0.0)),
		"visible_actor_count": int(state.get("visible_actor_count", projection_metrics.get("visible_actor_count", 0))),
		"projected_actor_count": int(state.get("projected_actor_count", projection_metrics.get("projected_actor_count", 0))),
		"active_animation_count": int(state.get("active_animation_count", projection_metrics.get("combat_projection_active_animation_count", 0))),
		"engagement_group_count": int(projection_metrics.get("combat_projection_engagement_group_count", 0)),
		"scheduled_event_count": int(projection_metrics.get("combat_projection_scheduled_event_count", 0)),
		"active_event_count": int(projection_metrics.get("combat_projection_active_event_count", 0)),
		"skipped_beat_count": int(projection_metrics.get("combat_projection_skipped_beat_count", 0)),
		"summarized_beat_count": int(projection_metrics.get("combat_projection_summarized_beat_count", 0)),
		"slot_role_anchor_change_count": int(projection_metrics.get("combat_projection_slot_change_count", 0)),
		"active_ragdoll_downed_count": int(projection_metrics.get("combat_projection_active_ragdoll_downed_count", 0)),
		"gecs_tick_ms": float(state.get("gecs_tick_ms", 0.0)),
	}
	scene.queue_free()
	await process_frame
	return report


func _wait_for_ready(scene: Node, scenario_id: String) -> void:
	for _frame in range(MAX_WAIT_FRAMES):
		await process_frame
		if scene.has_method("get_benchmark_state"):
			var state = scene.call("get_benchmark_state")
			if state is Dictionary and bool((state as Dictionary).get("ready", false)) and bool(_projection_metrics_from_state(state).get("combat_projection_active", false)):
				return
		elif scene.has_method("get_review_state"):
			var review_state = scene.call("get_review_state")
			if review_state is Dictionary and bool((review_state as Dictionary).get("ready", false)) and bool((review_state as Dictionary).get("playback_active", false)):
				return
	_failures.append("%s combat projection benchmark becomes ready within wait budget" % scenario_id)


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


func _projection_metrics_from_state(state: Dictionary) -> Dictionary:
	var direct: Dictionary = state.get("projection_metrics", {}) if state.get("projection_metrics", {}) is Dictionary else {}
	if not direct.is_empty():
		return direct
	var nested: Dictionary = state.get("combat_projection", {}) if state.get("combat_projection", {}) is Dictionary else {}
	return nested


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
		_failures.append("Could not write combat projection report: %s" % REPORT_PATH)
		return
	file.store_string(JSON.stringify(report, "  "))


func _empty_report(scenario: Dictionary, baseline: Dictionary) -> Dictionary:
	return {
		"scenario_id": str(scenario.get("id", "")),
		"scene_path": str(scenario.get("path", "")),
		"actor_count": int(scenario.get("actors", 0)),
		"before_average_fps": float(baseline.get("average_fps", 0.0)),
		"after_average_fps": 0.0,
		"average_fps_delta": -float(baseline.get("average_fps", 0.0)),
	}


func _finish(scenario_count: int) -> void:
	if _failures.is_empty():
		print("COMBAT_BEAT_PROJECTION_BENCHMARK_OK scenarios=%d sample_frames=%d report=%s" % [scenario_count, SAMPLE_FRAME_COUNT, REPORT_PATH])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("COMBAT_BEAT_PROJECTION_BENCHMARK_FAILED scenarios=%d sample_frames=%d report=%s" % [scenario_count, SAMPLE_FRAME_COUNT, REPORT_PATH])
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
