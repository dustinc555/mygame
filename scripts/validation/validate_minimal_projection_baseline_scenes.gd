extends SceneTree

const MAX_WAIT_FRAMES := 360
const SCENARIOS := [
	{"id": "projection_baseline_1v1", "path": "res://scenes/test_levels/projection_baseline_1v1.tscn", "actors": 2},
	{"id": "projection_baseline_5v5", "path": "res://scenes/test_levels/projection_baseline_5v5.tscn", "actors": 10},
	{"id": "projection_baseline_50v50", "path": "res://scenes/test_levels/projection_baseline_50v50.tscn", "actors": 100},
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	for scenario in SCENARIOS:
		await _validate_scenario(scenario)
	_finish()


func _validate_scenario(scenario: Dictionary) -> void:
	var scene_path := str(scenario.get("path", ""))
	var expected_id := str(scenario.get("id", ""))
	var expected_actors := int(scenario.get("actors", 0))
	var scene_resource := load(scene_path) as PackedScene
	_expect(scene_resource != null, "%s scene loads" % expected_id)
	if scene_resource == null:
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	await process_frame
	_validate_static_scene_contract(scene, expected_id)
	await _wait_for_ready(scene, expected_id)
	_validate_benchmark_state(scene, expected_id, expected_actors)
	scene.queue_free()
	await process_frame


func _validate_static_scene_contract(scene: Node, expected_id: String) -> void:
	_expect(scene.has_method("get_benchmark_state"), "%s exposes benchmark state" % expected_id)
	_expect(scene.has_method("measure_projection_sync"), "%s exposes projection sync measurement" % expected_id)
	_expect(scene.get_node_or_null("GameBootstrap") != null, "%s uses GameBootstrap" % expected_id)
	_expect(scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") is Camera3D, "%s has visible benchmark camera" % expected_id)
	_expect(scene.get_node_or_null("Arena/Floor") != null, "%s has visible benchmark floor" % expected_id)


func _wait_for_ready(scene: Node, expected_id: String) -> void:
	for _frame in range(MAX_WAIT_FRAMES):
		await process_frame
		if not scene.has_method("get_benchmark_state"):
			continue
		var state = scene.call("get_benchmark_state")
		if state is Dictionary and bool((state as Dictionary).get("ready", false)):
			return
	_failures.append("%s becomes ready within wait budget" % expected_id)


func _validate_benchmark_state(scene: Node, expected_id: String, expected_actors: int) -> void:
	if not scene.has_method("get_benchmark_state"):
		return
	var state = scene.call("get_benchmark_state")
	_expect(state is Dictionary, "%s benchmark state is a dictionary" % expected_id)
	if not (state is Dictionary):
		return
	var benchmark_state: Dictionary = state
	_expect(str(benchmark_state.get("scenario_id", "")) == expected_id, "%s records scenario id" % expected_id)
	_expect(int(benchmark_state.get("expected_actor_count", 0)) == expected_actors, "%s records expected actor count" % expected_id)
	_expect(int(benchmark_state.get("projected_actor_count", 0)) == expected_actors, "%s projects expected actor count" % expected_id)
	_expect(int(benchmark_state.get("visible_actor_count", 0)) == expected_actors, "%s keeps all benchmark actors visible" % expected_id)
	var counts: Dictionary = benchmark_state.get("projection_counts_by_kind", {}) if benchmark_state.get("projection_counts_by_kind", {}) is Dictionary else {}
	_expect(int(counts.get("humanoid", 0)) == expected_actors, "%s uses real humanoid projection path" % expected_id)
	_expect(not counts.has("animal_placeholder") and not counts.has("robot_placeholder"), "%s does not use placeholder projection path" % expected_id)
	_expect(int(benchmark_state.get("active_animation_count", -1)) >= 0, "%s records active animation count" % expected_id)
	_expect(float(benchmark_state.get("average_projection_sync_ms", -1.0)) >= 0.0, "%s records projection sync time" % expected_id)
	_expect(float(benchmark_state.get("gecs_tick_ms", -1.0)) >= 0.0, "%s records GECS/fixed tick time" % expected_id)
	_expect(not bool(benchmark_state.get("battle_sim_included", true)), "%s excludes BattleSim/data combat cost" % expected_id)
	_validate_no_live_refs(benchmark_state, expected_id, "benchmark_state")


func _validate_no_live_refs(value, label: String, path: String) -> void:
	if value is Node:
		_failures.append("%s stores live Node at %s" % [label, path])
		return
	if value is NodePath:
		_failures.append("%s stores NodePath at %s" % [label, path])
		return
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			_validate_no_live_refs((value as Dictionary).get(key), label, "%s.%s" % [path, str(key)])
	elif value is Array:
		for index in range((value as Array).size()):
			_validate_no_live_refs((value as Array)[index], label, "%s[%d]" % [path, index])


func _finish() -> void:
	if _failures.is_empty():
		print("MINIMAL_PROJECTION_BASELINE_SCENES_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
