extends SceneTree
## Runtime contract for the interactive farm Jobs stress-test level.

const STRESS_SCENE_PATH := "res://scenes/test_levels/farm_jobs_stress_test.tscn"

var _failures: Array[String] = []
var _ecs_placeholder: Node


func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		_ecs_placeholder.name = "ECS"
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var packed := load(STRESS_SCENE_PATH) as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	var ready := bool(await scene.call("wait_until_benchmark_ready", 1800))
	_expect(ready, "stress level becomes ready")
	if ready:
		var initial: Dictionary = scene.call("get_benchmark_snapshot")
		_expect(int(initial.get("actor_count", 0)) == 100 and int(initial.get("projected_count", 0)) == 100, "stress level realizes exactly 100 projected actors")
		_expect(str(initial.get("mode", "")) == "jobs_no_field" and int(initial.get("jobs_enabled_count", 0)) == 100, "stress level defaults to Jobs on with no field")
		_expect(str(initial.get("farm_plot_id", "")).is_empty() and int(initial.get("active_work_count", -1)) == 0, "default stress mode has no field or farm work")
		var active_button := scene.get_node("StressHUD/Panel/Content/Controls/ActiveFieldJobs") as Button
		active_button.pressed.emit()
		var active_started := false
		var start_distance := float(initial.get("total_distance", 0.0))
		for _frame in 900:
			var snapshot: Dictionary = scene.call("get_benchmark_snapshot")
			if not str(snapshot.get("farm_plot_id", "")).is_empty() \
					and int(snapshot.get("active_work_count", 0)) > 0 \
					and float(snapshot.get("total_distance", 0.0)) > start_distance + 0.1:
				active_started = true
				break
			await physics_frame
		_expect(active_started, "active-field button creates real field offers, claims, and worker movement")
		var metrics := scene.get_node("StressHUD/Panel/Content/StressMetrics") as Label
		_expect(metrics.text.contains("ACTIVE FIELD"), "stress HUD identifies the active-field measurement")
		var no_field_button := scene.get_node("StressHUD/Panel/Content/Controls/NoFieldJobs") as Button
		no_field_button.pressed.emit()
		for _frame in 5:
			await process_frame
		var cleared: Dictionary = scene.call("get_benchmark_snapshot")
		_expect(str(cleared.get("farm_plot_id", "")).is_empty() and int(cleared.get("active_work_count", -1)) == 0, "no-field button removes the field and cancels farm assignments")
		_expect(int(cleared.get("jobs_enabled_count", 0)) == 100, "no-field comparison keeps Jobs enabled for every actor")
	root.remove_child(scene)
	scene.free()
	if _failures.is_empty():
		print("FARM_JOBS_STRESS_LEVEL_RUNTIME_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FARM_JOBS_STRESS_LEVEL_RUNTIME_FAILED count=%d" % _failures.size())
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
