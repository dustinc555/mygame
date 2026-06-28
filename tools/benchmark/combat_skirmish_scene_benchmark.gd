extends SceneTree

const DEFAULT_SCENE_PATH := "res://scenes/test_levels/combat_skirmish_20v20_armory.tscn"
const RUSTDEAD_5V10_SCENE_PATH := "res://scenes/test_levels/rustdead_5v10_demo.tscn"
const RUSTDEAD_5V10_AVG_FPS_FLOOR := 55.0

# Baseline before WorldActor job/combat refactor on this machine, 600 sampled
# frames after 240 warmup at max 120 FPS: 10v10 avg 85.13/min 46.50 FPS;
# 20v20 avg 36.84/min 14.83 FPS.
# 2026-07-01 (post stats-capability fix, ECS placeholder added so GECS actually
# runs in --script mode): 20v20 avg 116.44/min 55.37 FPS measured with GECS
# state-sync degraded and combat NOT engaging (scan radii were zero).
# 2026-07-01 honest scene-mode baseline after combat-config restoration, 40 actors
# all engaged (validate_combat_skirmish_engagement.tscn, 5s warmup + 25s sample):
# avg 60.55 / min 32.87 FPS — BELOW the 40 floor; perf work outstanding.

var scene_path := DEFAULT_SCENE_PATH
var warmup_frames := 240
var sample_frames := 600
var report_interval := 120
var fixed_fps := 120
var auto_quit := true
var actor_query_metrics_enabled := false

var _scene: Node
var _ecs_compile_placeholder: Node
var _sample_count := 0
var _sample_delta_sum := 0.0
var _max_delta := 0.0
var _sample_last_usec := 0
var _is_finalizing := false


func _initialize() -> void:
	_register_ecs_compile_placeholder()
	_parse_cli_args()
	OS.low_processor_usage_mode = false
	OS.low_processor_usage_mode_sleep_usec = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if fixed_fps > 0:
		Engine.max_fps = fixed_fps
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Could not load benchmark scene: %s" % scene_path)
		quit(1)
		return
	_scene = packed_scene.instantiate()
	root.add_child(_scene)
	call_deferred("_begin_sampling")


func _begin_sampling() -> void:
	await process_frame
	_print_config()
	for _warmup_index in range(warmup_frames):
		await process_frame
	_reset_benchmark_metrics()
	_sample_last_usec = int(Time.get_ticks_usec())
	while _sample_count < sample_frames:
		await process_frame
		var now_usec := int(Time.get_ticks_usec())
		var delta := float(now_usec - _sample_last_usec) / 1_000_000.0
		_sample_last_usec = now_usec
		_collect_sample(delta)
		_sample_count += 1
		if report_interval > 0 and _sample_count % report_interval == 0:
			_print_progress()
	if _sample_count >= sample_frames and not _is_finalizing:
		_finish_benchmark()


func _collect_sample(delta: float) -> void:
	_sample_delta_sum += delta
	_max_delta = maxf(_max_delta, delta)


func _print_config() -> void:
	print("COMBAT_SKIRMISH_BENCHMARK_START scene=%s warmup_frames=%d sample_frames=%d fixed_fps=%d" % [scene_path, warmup_frames, sample_frames, fixed_fps])


func _print_progress() -> void:
	var avg_fps := float(_sample_count) / maxf(_sample_delta_sum, 0.00001)
	var min_fps := 1.0 / maxf(_max_delta, 0.00001)
	print("COMBAT_SKIRMISH_BENCHMARK_PROGRESS scene=%s frames=%d avg_fps=%.2f min_fps=%.2f" % [scene_path, _sample_count, avg_fps, min_fps])


func _finish_benchmark() -> void:
	_is_finalizing = true
	var safe_samples := maxi(_sample_count, 1)
	var safe_delta_sum := maxf(_sample_delta_sum, 0.00001)
	var avg_fps := float(safe_samples) / safe_delta_sum
	var min_fps := 1.0 / maxf(_max_delta, 0.00001)
	var avg_delta_ms := safe_delta_sum / float(safe_samples) * 1000.0
	var report := {
		"mode": "combat_skirmish_headless",
		"scene": scene_path,
		"warmup_frames": warmup_frames,
		"sample_frames": sample_frames,
		"avg_fps": avg_fps,
		"min_fps": min_fps,
		"avg_frame_delta_ms": avg_delta_ms,
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"memory_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"groups": _collect_group_counts(),
		"actor_query_metrics": _collect_actor_query_metrics(),
	}
	print("COMBAT_SKIRMISH_BENCHMARK_RESULT " + JSON.stringify(report))
	if scene_path == RUSTDEAD_5V10_SCENE_PATH:
		var failed := false
		if avg_fps < RUSTDEAD_5V10_AVG_FPS_FLOOR:
			push_error("Rustdead 5v10 benchmark average FPS %.2f below floor %.2f" % [avg_fps, RUSTDEAD_5V10_AVG_FPS_FLOOR])
			failed = true
		if failed:
			if auto_quit:
				_quit_after_cleanup(1)
			return
	if auto_quit:
		_quit_after_cleanup(0)


func _quit_after_cleanup(exit_code: int) -> void:
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
		_scene = null
	quit(exit_code)


# In `--script` (SceneTree) mode project autoloads are not instantiated and the ECS
# identifier does not resolve at compile time, so GECS-dependent scripts in the loaded
# scene fail to compile without this. GecsWorldController swaps the placeholder for the
# real _ECS node during its initialization. Same template as the validation scripts.
func _register_ecs_compile_placeholder() -> void:
	if Engine.has_singleton("ECS") or root.get_node_or_null("ECS") != null:
		return
	_ecs_compile_placeholder = Node.new()
	_ecs_compile_placeholder.name = "ECS"
	Engine.register_singleton("ECS", _ecs_compile_placeholder)


func _collect_group_counts() -> Dictionary:
	# WorldActor/NpcRules must not be referenced by class_name in this script: that would
	# compile the GECS chain while this script itself compiles, before
	# _register_ecs_compile_placeholder() can run. Load them at runtime instead.
	var world_actor_script: Script = load("res://features/actors/bridge/world_actor.gd")
	var npc_rules = load("res://features/world_sim/sim/npc_rules.gd")
	var alive_life_state: int = npc_rules.LifeState.ALIVE
	var groups := {}
	for group_name in ["world_actor", "party_member"]:
		groups[group_name] = root.get_tree().get_nodes_in_group(group_name).size()
	var alive := 0
	var in_combat := 0
	for node in root.get_tree().get_nodes_in_group("world_actor"):
		if not is_instance_of(node, world_actor_script):
			continue
		if int(node.life_state) == alive_life_state:
			alive += 1
		if bool(node.is_in_combat()):
			in_combat += 1
	groups["alive_world_actor"] = alive
	groups["in_combat_world_actor"] = in_combat
	return groups


func _reset_benchmark_metrics() -> void:
	var query_controller := root.get_tree().get_first_node_in_group("actor_query_controller")
	if query_controller != null and query_controller.has_method("reset_actor_query_metrics"):
		if query_controller.has_method("set_actor_query_metrics_enabled"):
			query_controller.call("set_actor_query_metrics_enabled", actor_query_metrics_enabled)
		query_controller.call("reset_actor_query_metrics")


func _collect_actor_query_metrics() -> Dictionary:
	var query_controller := root.get_tree().get_first_node_in_group("actor_query_controller")
	if query_controller != null and query_controller.has_method("get_actor_query_metrics"):
		return query_controller.call("get_actor_query_metrics") as Dictionary
	return {}


func _parse_cli_args() -> void:
	for arg_value in OS.get_cmdline_args():
		var arg := str(arg_value)
		if arg.begins_with("--benchmark-scene="):
			scene_path = arg.get_slice("=", 1)
		elif arg.begins_with("--benchmark-warmup="):
			warmup_frames = max(0, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--benchmark-frames="):
			sample_frames = max(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--benchmark-report-interval="):
			report_interval = max(0, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--benchmark-fixed-fps="):
			fixed_fps = max(0, int(arg.get_slice("=", 1)))
		elif arg == "--benchmark-no-quit":
			auto_quit = false
		elif arg == "--actor-query-metrics":
			actor_query_metrics_enabled = true
