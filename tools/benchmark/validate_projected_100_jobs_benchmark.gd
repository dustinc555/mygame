extends SceneTree
## Focused contract test for the projected 100-character Jobs benchmark.

const SCENE_PATH := "res://scenes/test_levels/projected_100_jobs_benchmark.tscn"
const STRESS_SCENE_PATH := "res://scenes/test_levels/farm_jobs_stress_test.tscn"
const RUNNER_PATH := "res://tools/benchmark/projected_100_jobs_benchmark_runner.gd"

var _failures: Array[String] = []
var _ecs_placeholder: Node


func _initialize() -> void:
	_register_ecs_compile_placeholder()
	call_deferred("_run")


func _run() -> void:
	_expect(ResourceLoader.exists(RUNNER_PATH), "benchmark runner exists")
	_expect(ResourceLoader.exists(SCENE_PATH), "benchmark scene exists")
	_expect(ResourceLoader.exists(STRESS_SCENE_PATH), "interactive farm Jobs stress-test level exists")
	if ResourceLoader.exists(STRESS_SCENE_PATH):
		var stress_packed := load(STRESS_SCENE_PATH) as PackedScene
		var stress_scene := stress_packed.instantiate() if stress_packed != null else null
		_expect(stress_scene != null, "interactive farm Jobs stress-test level instantiates")
		if stress_scene != null:
			_expect(stress_scene.has_method("set_stress_mode"), "stress level exposes interactive mode switching")
			_expect(stress_scene.has_method("reset_stress_metrics"), "stress level exposes metric reset")
			_expect(stress_scene.get_node_or_null("StressHUD/Panel/Content/Controls/NoFieldJobs") != null, "stress level exposes Jobs/no-field control")
			_expect(stress_scene.get_node_or_null("StressHUD/Panel/Content/Controls/ActiveFieldJobs") != null, "stress level exposes Jobs/active-field control")
			_expect(stress_scene.get_node_or_null("StressHUD/Panel/Content/StressMetrics") != null, "stress level exposes live frame metrics")
			stress_scene.free()
	if not ResourceLoader.exists(SCENE_PATH):
		_finish()
		return
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "benchmark scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	_expect(scene != null, "benchmark scene instantiates")
	if scene == null:
		_finish()
		return
	_expect(int(scene.get("actor_count")) == 100, "benchmark scene defaults to 100 projected actors")
	_expect(scene.has_method("configure_benchmark"), "benchmark scene exposes configure_benchmark")
	_expect(scene.has_method("wait_until_benchmark_ready"), "benchmark scene exposes bounded readiness")
	_expect(scene.has_method("apply_benchmark_mode"), "benchmark scene exposes mode switching")
	_expect(scene.has_method("get_benchmark_snapshot"), "benchmark scene exposes verification snapshot")
	_expect(scene.has_method("profile_benchmark_hot_paths"), "benchmark scene exposes focused Jobs profiling")
	if not scene.has_method("configure_benchmark") or not scene.has_method("wait_until_benchmark_ready") \
			or not scene.has_method("apply_benchmark_mode") or not scene.has_method("get_benchmark_snapshot") \
			or not scene.has_method("profile_benchmark_hot_paths"):
		scene.free()
		_finish()
		return
	scene.call("configure_benchmark", 3)
	root.add_child(scene)
	var ready := bool(await scene.call("wait_until_benchmark_ready", 1200))
	_expect(ready, "benchmark scene becomes ready")
	if ready:
		await _assert_mode(scene, "idle", 3, 0, 0, 0)
		await _assert_mode(scene, "jobs_no_field", 3, 3, 0, 0)
		var no_field_snapshot: Dictionary = scene.call("get_benchmark_snapshot")
		_expect(str(no_field_snapshot.get("farm_plot_id", "")).is_empty(), "Jobs/no-field mode removes the authoritative field")
		_expect(int(no_field_snapshot.get("active_work_count", -1)) == 0, "Jobs/no-field mode has no farm assignments")
		await _assert_mode(scene, "jobs", 3, 3, 0, 0)
		var profile: Dictionary = scene.call("profile_benchmark_hot_paths")
		_expect(int(profile.get("offer_count", 0)) > 0, "Jobs benchmark publishes real farm offers")
		_expect(bool(profile.get("tool_equip_preserved_skeleton", false)), "work tool equip refreshes only its equipment slot")
		_expect(bool(profile.get("tool_equip_visual_present", false)), "partial work-tool refresh creates the equipped visual")
		var jobs_start: Dictionary = scene.call("get_benchmark_snapshot")
		var jobs_start_distance := float(jobs_start.get("total_distance", 0.0))
		var jobs_start_completed := int(jobs_start.get("work_completed_count", 0))
		var jobs_became_active := false
		for _frame in 600:
			var jobs_snapshot: Dictionary = scene.call("get_benchmark_snapshot")
			var advanced := float(jobs_snapshot.get("total_distance", 0.0)) > jobs_start_distance + 0.1 \
					or int(jobs_snapshot.get("work_completed_count", 0)) > jobs_start_completed
			if int(jobs_snapshot.get("active_work_count", 0)) > 0 and advanced:
				jobs_became_active = true
				break
			await physics_frame
		var active_snapshot: Dictionary = scene.call("get_benchmark_snapshot")
		_expect(jobs_became_active, "Jobs mode produces an active claim plus movement or completion")
		_expect(not str(active_snapshot.get("farm_plot_id", "")).is_empty(), "Jobs benchmark has an authoritative farm source")
		await _assert_mode(scene, "jobs_running", 3, 3, 3, 3)
		var before := float((scene.call("get_benchmark_snapshot") as Dictionary).get("total_distance", 0.0))
		for _frame in 90:
			await physics_frame
		var after := float((scene.call("get_benchmark_snapshot") as Dictionary).get("total_distance", 0.0))
		_expect(after > before + 0.1, "jobs_running mode produces actual running movement")
	root.remove_child(scene)
	scene.free()
	_finish()


func _assert_mode(scene: Node, mode: String, expected_actors: int, expected_jobs: int, expected_running: int, expected_targets: int) -> void:
	_expect(bool(scene.call("apply_benchmark_mode", mode)), "%s mode applies" % mode)
	for _frame in 3:
		await process_frame
	var snapshot: Dictionary = scene.call("get_benchmark_snapshot")
	_expect(int(snapshot.get("actor_count", -1)) == expected_actors, "%s keeps the configured actor count" % mode)
	_expect(int(snapshot.get("projected_count", -1)) == expected_actors, "%s keeps every actor projected" % mode)
	_expect(int(snapshot.get("jobs_enabled_count", -1)) == expected_jobs, "%s has the expected Jobs-enabled count" % mode)
	_expect(int(snapshot.get("running_requested_count", -1)) == expected_running, "%s has the expected running count" % mode)
	_expect(int(snapshot.get("move_target_count", -1)) == expected_targets, "%s has the expected movement-target count" % mode)


func _register_ecs_compile_placeholder() -> void:
	if Engine.has_singleton("ECS") or root.get_node_or_null("ECS") != null:
		return
	_ecs_placeholder = Node.new()
	_ecs_placeholder.name = "ECS"
	Engine.register_singleton("ECS", _ecs_placeholder)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PROJECTED_100_JOBS_BENCHMARK_CONTRACT_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("PROJECTED_100_JOBS_BENCHMARK_CONTRACT_FAILED count=%d" % _failures.size())
	quit(1)
