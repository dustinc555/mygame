extends SceneTree

const DEMO_WORLD_SCENE := preload("res://scenes/worlds/demo_world/demo_world.tscn")

const MONITOR_NAMES := [
	"TIME_PROCESS",
	"TIME_PHYSICS_PROCESS",
	"MEMORY_STATIC",
	"OBJECT_NODE_COUNT",
	"OBJECT_RESOURCE_COUNT",
	"OBJECT_ORPHAN_NODE_COUNT"
]

const MONITOR_IDS := {
	"TIME_PROCESS": Performance.TIME_PROCESS,
	"TIME_PHYSICS_PROCESS": Performance.TIME_PHYSICS_PROCESS,
	"MEMORY_STATIC": Performance.MEMORY_STATIC,
	"OBJECT_NODE_COUNT": Performance.OBJECT_NODE_COUNT,
	"OBJECT_RESOURCE_COUNT": Performance.OBJECT_RESOURCE_COUNT,
	"OBJECT_ORPHAN_NODE_COUNT": Performance.OBJECT_ORPHAN_NODE_COUNT
}

const TRACKED_GROUPS := [
	"npc_character",
	"humanoid_character",
	"settlement_town",
	"world_item",
	"world_container",
	"population_spawner",
	"law_order_controller",
	"settlement_controller",
	"population_controller",
	"perception_controller",
	"ownership_controller",
	"job_system_controller",
	"job_provider",
	"faction_controller",
	"road_network",
	"faction_territory",
	"party_member",
	"world_sim_registry",
	"world_interaction_controller",
	"world_time_controller",
	"ai_scheduler_controller",
	"world_sim_squad_controller",
	"world_event_choice_controller",
	"population_realization_controller",
	"ledger_simulation_controller",
	"world_simulation_controller",
	"territory_controller",
	"road_controller",
	"conversation_controller",
	"party_inventory_controller",
	"humanoid_details_controller",
	"character_jobs_window",
	"building_visibility_controller",
	"world_status_controller"
]

var _scene: Node
var _sample_count := 0
var _sample_delta_sum := 0.0
var _max_delta := 0.0
var _sample_last_usec := 0

var warmup_frames := 240
var sample_frames := 600
var report_interval := 120
var fixed_fps := 120
var auto_quit := true
var ecs_debug_metrics := false
var _disable_process_groups: Array[String] = []
var _disable_idle_process_groups: Array[String] = []
var _disable_physics_process_groups: Array[String] = []
var _is_finalizing := false

var _monitor_stats: Dictionary = {}
var _group_stats: Dictionary = {}
var _ecs_frame_metrics: Dictionary = {}
var _ecs_cache_start: Dictionary = {}
var _ecs_cache_end: Dictionary = {}
var _gecs_node_count_start := 0
var _gecs_node_count_end := 0
var _gecs_entity_count_start := 0
var _gecs_entity_count_end := 0
var _ecs_singleton: Node = null


# Useful isolation flags:
# --demo-bench-disable-process=humanoid_character isolates non-humanoid scene cost.
# --demo-bench-disable-idle-process=humanoid_character disables only `_process`.
# --demo-bench-disable-physics-process=humanoid_character disables only `_physics_process`.
# --demo-bench-ecs-debug enables ECS metrics, but changes benchmark cost.
# --utility-profile prints utility AI section costs when utility decisions run.
# --humanoid-profile prints humanoid `_process` section costs.


func _initialize() -> void:
	_parse_cli_args()
	# Keep benchmarking deterministic and comparable by forcing a fixed timestep.
	if fixed_fps > 0:
		Engine.max_fps = fixed_fps
	# ECS debug/perf metrics are optional because debug mode changes benchmark cost.
	ProjectSettings.set_setting("gecs/settings/debug_mode", ecs_debug_metrics)
	var ecs_node: Node = _get_ecs_node()
	if ecs_node != null:
		ecs_node.set("debug", ecs_debug_metrics)

	_scene = DEMO_WORLD_SCENE.instantiate()
	root.add_child(_scene)
	call_deferred("_begin_sampling")


func _begin_sampling() -> void:
	# Allow bootstrap, autoloads, and deferred init before sampling.
	await process_frame
	_capture_baseline()
	_apply_process_disables()
	_print_config()

	# Run warmup without collecting metrics.
	for _warmup_index in range(warmup_frames):
		await process_frame
	
	# Collect fixed samples.
	_sample_last_usec = int(Time.get_ticks_usec())
	while _sample_count < sample_frames:
		await process_frame
		var now_usec: int = int(Time.get_ticks_usec())
		var delta: float = float(now_usec - _sample_last_usec) / 1_000_000.0
		_sample_last_usec = now_usec
		_collect_sample(delta)
		_sample_count += 1
		if _sample_count % report_interval == 0:
			_print_progress()
	if _sample_count >= sample_frames:
		if not _is_finalizing:
			_finalize()
func _collect_sample(delta: float) -> void:
	_sample_delta_sum += delta
	if delta > _max_delta:
		_max_delta = delta

	for monitor_name in MONITOR_NAMES:
		var monitor_value: float = _monitor_value(monitor_name)
		if monitor_value < 0:
			continue
		var stats: Dictionary = _monitor_stats.get(monitor_name, {"sum": 0.0, "min": INF, "max": -INF, "samples": 0})
		stats["sum"] += float(monitor_value)
		stats["min"] = minf(stats["min"], float(monitor_value))
		stats["max"] = maxf(stats["max"], float(monitor_value))
		stats["samples"] += 1
		_monitor_stats[monitor_name] = stats

	for group_name in TRACKED_GROUPS:
		var nodes: Array = get_nodes_in_group(group_name)
		var group_count: int = int(nodes.size())
		var stats: Dictionary = _group_stats.get(group_name, {"sum": 0, "min": INF, "max": -INF, "samples": 0, "last": 0})
		stats["sum"] += group_count
		var prev_min := float(stats["min"])
		var prev_max := float(stats["max"])
		stats["min"] = prev_min if prev_min < float(group_count) else float(group_count)
		stats["max"] = prev_max if prev_max > float(group_count) else float(group_count)
		stats["samples"] += 1
		stats["last"] = group_count
		_group_stats[group_name] = stats

	_collect_ecs_metrics()


func _collect_ecs_metrics() -> void:
	var ecs_world: Object = _get_ecs_world()
	if ecs_world == null:
		return
	var metrics: Dictionary = ecs_world.perf_get_frame_metrics()
	for metric_name in metrics.keys():
		var metric_entry = metrics.get(metric_name)
		if metric_entry == null:
			continue
		var metric_time := float(metric_entry.get("time_usec", 0.0))
		var metric_count := int(metric_entry.get("count", 0))
		if not _ecs_frame_metrics.has(metric_name):
			_ecs_frame_metrics[metric_name] = {"time_usec": 0.0, "count": 0, "max_time_usec": 0.0}
		var stat = _ecs_frame_metrics[metric_name]
		stat["time_usec"] += metric_time
		stat["count"] += metric_count
		if metric_time > stat["max_time_usec"]:
			stat["max_time_usec"] = metric_time
		_ecs_frame_metrics[metric_name] = stat


func _capture_baseline() -> void:
	_gecs_node_count_start = get_node_count()
	_collect_baseline_group_counts()
	var ecs_world: Object = _get_ecs_world()
	_gecs_entity_count_start = ecs_world.entities.size() if ecs_world != null else 0
	var start_nodes := _monitor_value("OBJECT_NODE_COUNT")
	var start_resources := _monitor_value("OBJECT_RESOURCE_COUNT")
	if start_nodes >= 0:
		_monitor_stats["BASE_NODE_COUNT_START"] = {"start": float(start_nodes)}
	if start_resources >= 0:
		_monitor_stats["BASE_RESOURCE_COUNT_START"] = {"start": float(start_resources)}
	if ecs_world != null and ecs_world.has_method("perf_reset_accum"):
		ecs_world.perf_reset_accum()
		ecs_world.perf_reset_frame()
		if ecs_world.has_method("get_cache_stats"):
			_ecs_cache_start = ecs_world.get_cache_stats()
		_gecs_node_count_end = _gecs_node_count_start
		_gecs_entity_count_end = _gecs_entity_count_start


func _finalize() -> void:
	if _is_finalizing:
		return
	_is_finalizing = true
	_sample_count = maxi(_sample_count, 1)
	var safe_delta_sum := maxf(_sample_delta_sum, 0.00001)
	var sample_avg_fps := float(_sample_count) / safe_delta_sum
	var min_fps := 1.0 / maxf(_max_delta, 0.00001)
	var avg_delta_ms := (safe_delta_sum / float(_sample_count)) * 1000.0

	_gecs_node_count_end = get_node_count()
	var ecs_world: Object = _get_ecs_world()
	if ecs_world != null:
		_gecs_entity_count_end = ecs_world.entities.size()
		if ecs_world.has_method("get_cache_stats"):
			_ecs_cache_end = ecs_world.get_cache_stats()

	_print_ecs_breakdown()
	_print_group_breakdown()
	_print_monitor_summary()

	var end_nodes := _monitor_value("OBJECT_NODE_COUNT")
	var end_resources := _monitor_value("OBJECT_RESOURCE_COUNT")
	var end_memory_static := _monitor_value("MEMORY_STATIC")
	var report := {
		"mode": "demo_world_headless",
		"warmup_frames": warmup_frames,
		"sample_frames": sample_frames,
		"sample_delta_seconds": safe_delta_sum,
		"avg_fps": sample_avg_fps,
		"min_fps": min_fps,
		"avg_frame_delta_ms": avg_delta_ms,
		"monitors": {
			"object_node_count_end": end_nodes,
			"object_resource_count_end": end_resources,
			"memory_static_bytes_end": end_memory_static,
			"tree_nodes_end": _gecs_node_count_end,
			"gecs_entities_end": _gecs_entity_count_end,
			"node_count_delta": _monitor_value("OBJECT_NODE_COUNT") - _monitor_stats.get("BASE_NODE_COUNT_START", {"start": 0.0}).get("start", 0.0),
			"resource_count_delta": _monitor_value("OBJECT_RESOURCE_COUNT") - _monitor_stats.get("BASE_RESOURCE_COUNT_START", {"start": 0.0}).get("start", 0.0)
		}
	}
	print("DEMO_WORLD_BENCHMARK_RESULT " + JSON.stringify(report))

	if auto_quit:
		quit(0)


func _collect_baseline_group_counts() -> void:
	for group_name in TRACKED_GROUPS:
		if not _group_stats.has(group_name):
			_group_stats[group_name] = {"sum": 0, "min": INF, "max": -INF, "samples": 0, "last": 0, "start": 0}
		_group_stats[group_name]["start"] = int(get_nodes_in_group(group_name).size())


func _print_config() -> void:
	var start_message := "DEMO_WORLD_BENCHMARK_START warmup_frames=%d sample_frames=%d fixed_fps=%d" % [warmup_frames, sample_frames, fixed_fps]
	if ecs_debug_metrics:
		start_message += " ecs_debug=true"
	if not _disable_process_groups.is_empty():
		start_message += " disable_process=" + ",".join(_disable_process_groups)
	if not _disable_idle_process_groups.is_empty():
		start_message += " disable_idle_process=" + ",".join(_disable_idle_process_groups)
	if not _disable_physics_process_groups.is_empty():
		start_message += " disable_physics_process=" + ",".join(_disable_physics_process_groups)
	print(start_message)


func _print_progress() -> void:
	var sampled := float(_sample_count)
	var delta_avg := (_sample_delta_sum / maxf(1.0, sampled)) * 1000.0
	var fps := sampled / maxf(_sample_delta_sum, 0.00001)
	var node_count := _monitor_value("OBJECT_NODE_COUNT")
	var resource_count := _monitor_value("OBJECT_RESOURCE_COUNT")
	var memory_static := _monitor_value("MEMORY_STATIC")
	var node_summary := ""
	for group_name in ["npc_character", "humanoid_character", "settlement_town", "settlement_controller", "law_order_controller"]:
		var stat = _group_stats.get(group_name)
		if stat != null and stat.size() > 0:
			node_summary += "%s=%d " % [group_name, int(stat.get("last", 0))]
	print("DEMO_WORLD_BENCHMARK_PROGRESS sample=%d/%d fps=%.2f avg_frame_ms=%.3f nodes=%0.0f resources=%0.0f mem_static_kb=%d %s" % [
		_sample_count,
		sample_frames,
		fps,
		delta_avg,
		node_count,
		resource_count,
		int(memory_static / 1024.0),
		node_summary
	])


func _print_monitor_summary() -> void:
	for monitor_name in _monitor_stats.keys():
		if not monitor_name.begins_with("BASE_"):
			var s: Dictionary = _monitor_stats[monitor_name]
			if s.get("samples", 0) <= 0:
				continue
			var avg: float = float(s["sum"]) / float(s["samples"])
			print("MONITOR_STATS %s avg=%s min=%s max=%s" % [
				monitor_name,
				str(avg),
				str(s.get("min", 0.0)),
				str(s.get("max", 0.0))
			])


func _print_group_breakdown() -> void:
	for group_name in TRACKED_GROUPS:
		var stats: Dictionary = _group_stats.get(group_name)
		if stats == null or stats.get("samples", 0) <= 0:
			continue
		var avg: float = float(stats["sum"]) / float(stats["samples"])
		var start_count := 0
		if _group_stats.has(group_name):
			start_count = int(_group_stats[group_name].get("start", int(stats["last"])))
		print("GROUP_STATS %s start=%d end=%d avg=%0.2f min=%d max=%d" % [
			group_name,
			start_count,
			int(stats.get("last", 0)),
			avg,
			int(stats.get("min", 0)),
			int(stats.get("max", 0))
		])


func _print_ecs_breakdown() -> void:
	var ecs_world: Object = _get_ecs_world()
	if ecs_world == null:
		print("ECS_STATS unavailable: no world")
		return
	var total_frame_time_usec := maxf(0.0001, _sample_delta_sum * 1000000.0)
	var rows: Array = []
	for metric_name in _ecs_frame_metrics.keys():
		var stat = _ecs_frame_metrics[metric_name]
		var count := int(stat["count"])
		if count <= 0:
			continue
		var time_usec := float(stat["time_usec"])
		rows.append([
			metric_name,
			time_usec / 1000.0,
			(time_usec / total_frame_time_usec) * 100.0
		])
	rows.sort_custom(func(a, b): return b[1] > a[1])
	for i in range(mini(20, rows.size())):
		var metric_name = str(rows[i][0])
		var ms = float(rows[i][1])
		var pct = float(rows[i][2])
		print("ECS_METRIC rank=%d name=%s time_ms=%0.3f frame_pct=%0.2f%%" % [i + 1, metric_name, ms, pct])
	print("ECS_CACHE_START=" + str(_ecs_cache_start))
	print("ECS_CACHE_END=" + str(_ecs_cache_end))
	var total_entities := int(ecs_world.entities.size()) if ecs_world != null else 0
	var system_count := int(ecs_world.systems.size()) if ecs_world != null else 0
	print("ECS_COUNTS entities=%d systems=%d" % [total_entities, system_count])


func _get_ecs_node() -> Node:
	if not is_instance_valid(root):
		return null
	if is_instance_valid(_ecs_singleton):
		return _ecs_singleton
	var by_name := root.get_node_or_null("ECS")
	if by_name != null:
		_ecs_singleton = by_name
		return _ecs_singleton
	var by_root_children: Array = root.get_children()
	for child in by_root_children:
		if str(child.name) == "ECS":
			_ecs_singleton = child as Node
			break
	if _ecs_singleton == null:
		var root_node := root.get_node_or_null("Root")
		if root_node != null:
			_ecs_singleton = root_node.get_node_or_null("ECS") as Node
	return _ecs_singleton


func _get_ecs_world() -> Object:
	var ecs_node := _get_ecs_node()
	if ecs_node == null or not is_instance_valid(ecs_node):
		return null
	return ecs_node.get("world")


func _monitor_value(monitor_name: String) -> float:
	if not MONITOR_IDS.has(monitor_name):
		return -1.0
	var monitor_id: int = int(MONITOR_IDS[monitor_name])
	return Performance.get_monitor(monitor_id)


func _parse_cli_args() -> void:
	for arg_value in OS.get_cmdline_args():
		var arg := str(arg_value)
		if arg.begins_with("--demo-bench-warmup="):
			warmup_frames = max(0, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--demo-bench-samples="):
			sample_frames = max(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--demo-bench-interval="):
			report_interval = max(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--demo-bench-fps="):
			fixed_fps = max(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--demo-bench-disable-process="):
			_disable_process_groups = _parse_group_list_arg(arg)
		elif arg.begins_with("--demo-bench-disable-idle-process="):
			_disable_idle_process_groups = _parse_group_list_arg(arg)
		elif arg.begins_with("--demo-bench-disable-physics-process="):
			_disable_physics_process_groups = _parse_group_list_arg(arg)
		elif arg == "--demo-bench-ecs-debug":
			ecs_debug_metrics = true
		elif arg == "--demo-bench-no-quit":
			auto_quit = false


func _parse_group_list_arg(arg: String) -> Array[String]:
	var raw := ""
	var parts := arg.split("=", false)
	if parts.size() > 1:
		raw = parts[1]
	if raw.is_empty():
		return []
	var groups: Array[String] = []
	for group_name in raw.split(",", false):
		var normalized := str(group_name).strip_edges()
		if not normalized.is_empty():
			groups.append(normalized)
	return groups


func _apply_process_disables() -> void:
	for group_name in _disable_process_groups:
		if group_name.is_empty():
			continue
		var nodes := get_nodes_in_group(group_name)
		for node in nodes:
			if node is Node:
				var target := node as Node
				target.set_process(false)
				target.set_physics_process(false)
		print("DEMO_WORLD_BENCHMARK_DISABLE group=%s nodes=%d" % [group_name, nodes.size()])
	for group_name in _disable_idle_process_groups:
		if group_name.is_empty():
			continue
		var nodes := get_nodes_in_group(group_name)
		for node in nodes:
			if node is Node:
				(node as Node).set_process(false)
		print("DEMO_WORLD_BENCHMARK_DISABLE_IDLE_PROCESS group=%s nodes=%d" % [group_name, nodes.size()])
	for group_name in _disable_physics_process_groups:
		if group_name.is_empty():
			continue
		var nodes := get_nodes_in_group(group_name)
		for node in nodes:
			if node is Node:
				(node as Node).set_physics_process(false)
		print("DEMO_WORLD_BENCHMARK_DISABLE_PHYSICS_PROCESS group=%s nodes=%d" % [group_name, nodes.size()])
