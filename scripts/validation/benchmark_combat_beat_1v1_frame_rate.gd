extends SceneTree

const TEST_SCENE_PATH := "res://scenes/test_levels/combat_beat_1v1_test.tscn"
const MIN_AVERAGE_FPS := 140.0
const MAX_WAIT_FRAMES := 360
const SAMPLE_FRAME_COUNT := 420

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_benchmark")


func _run_benchmark() -> void:
	var scene_resource := load(TEST_SCENE_PATH) as PackedScene
	_expect(scene_resource != null, "CombatBeat 1v1 benchmark scene loads")
	if scene_resource == null:
		_finish(0.0)
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	await process_frame
	if scene.has_method("restart_duel"):
		# The scene auto-starts, but explicitly restart so the benchmark always samples an active fight.
		scene.call("restart_duel")
	await _wait_for_combat_started(scene)
	var average_fps := await _sample_average_fps()
	_expect(average_fps >= MIN_AVERAGE_FPS, "CombatBeat 1v1 average FPS %.2f below required %.2f" % [average_fps, MIN_AVERAGE_FPS])
	_finish(average_fps)


func _wait_for_combat_started(scene: Node) -> void:
	for _frame in range(MAX_WAIT_FRAMES):
		await process_frame
		if not scene.has_method("get_review_state"):
			continue
		var state = scene.call("get_review_state")
		if not (state is Dictionary):
			continue
		var battle_result: Dictionary = (state as Dictionary).get("battle_result", {}) if (state as Dictionary).get("battle_result", {}) is Dictionary else {}
		if bool((state as Dictionary).get("playback_active", false)) and not battle_result.is_empty():
			return
	_failures.append("CombatBeat 1v1 benchmark starts combat within wait budget")


func _sample_average_fps() -> float:
	var started_usec := Time.get_ticks_usec()
	for _frame in range(SAMPLE_FRAME_COUNT):
		await process_frame
	var elapsed_seconds := float(Time.get_ticks_usec() - started_usec) / 1000000.0
	if elapsed_seconds <= 0.0:
		return 0.0
	return float(SAMPLE_FRAME_COUNT) / elapsed_seconds


func _finish(average_fps: float) -> void:
	if _failures.is_empty():
		print("COMBAT_BEAT_1V1_FRAME_BENCHMARK_OK average_fps=%.2f min_required=%.2f sample_frames=%d" % [average_fps, MIN_AVERAGE_FPS, SAMPLE_FRAME_COUNT])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("COMBAT_BEAT_1V1_FRAME_BENCHMARK_FAILED average_fps=%.2f min_required=%.2f sample_frames=%d" % [average_fps, MIN_AVERAGE_FPS, SAMPLE_FRAME_COUNT])
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
