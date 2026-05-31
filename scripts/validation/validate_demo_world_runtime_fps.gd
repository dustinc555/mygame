extends SceneTree

const DEMO_WORLD_SCENE := preload("res://scenes/worlds/demo_world/demo_world.tscn")

const WARMUP_FRAMES := 80
const SAMPLE_FRAMES := 180
const CHUNK_FRAMES := 30
const MIN_RUNTIME_FPS := 20.0

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_scene = DEMO_WORLD_SCENE.instantiate()
	_scene.set("auto_open_character_creator", false)
	_scene.set("auto_spawn_default_character", true)
	root.add_child(_scene)
	current_scene = _scene
	await _wait_frames(WARMUP_FRAMES)
	var result := await _measure_runtime_fps()
	_print_runtime_summary(result)
	if float(result.get("min_chunk_fps", 0.0)) < MIN_RUNTIME_FPS:
		_fail("Demo world runtime FPS dropped below %.1f: min_chunk_fps=%.2f avg_fps=%.2f" % [MIN_RUNTIME_FPS, float(result.get("min_chunk_fps", 0.0)), float(result.get("avg_fps", 0.0))])
	if _failures.is_empty():
		print("DEMO_WORLD_RUNTIME_FPS_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("DEMO_WORLD_RUNTIME_FPS_FAILED count=%d" % _failures.size())
	quit(1)


func _measure_runtime_fps() -> Dictionary:
	var total_started := Time.get_ticks_usec()
	var chunk_started := total_started
	var min_chunk_fps := INF
	var max_chunk_usec := 0
	for frame_index in range(SAMPLE_FRAMES):
		await process_frame
		if (frame_index + 1) % CHUNK_FRAMES == 0:
			var now := Time.get_ticks_usec()
			var elapsed_usec := now - chunk_started
			var chunk_fps := float(CHUNK_FRAMES) * 1000000.0 / maxf(float(elapsed_usec), 1.0)
			min_chunk_fps = minf(min_chunk_fps, chunk_fps)
			max_chunk_usec = maxi(max_chunk_usec, elapsed_usec)
			chunk_started = now
	var total_elapsed_usec := Time.get_ticks_usec() - total_started
	return {
		"avg_fps": float(SAMPLE_FRAMES) * 1000000.0 / maxf(float(total_elapsed_usec), 1.0),
		"min_chunk_fps": min_chunk_fps,
		"total_elapsed_usec": total_elapsed_usec,
		"max_chunk_usec": max_chunk_usec,
	}


func _print_runtime_summary(result: Dictionary) -> void:
	var humanoids := get_nodes_in_group("humanoid_character")
	var scavenging := get_nodes_in_group("scavenging_resource")
	var nest_controller := _get_controller("nest_controller")
	var nest_summary: Dictionary = nest_controller.call("get_debug_summary") if nest_controller != null and nest_controller.has_method("get_debug_summary") else {}
	print("DEMO_WORLD_RUNTIME_FPS avg=%.2f min_chunk=%.2f max_chunk_usec=%d humanoids=%d scavenging=%d nests=%s" % [
		float(result.get("avg_fps", 0.0)),
		float(result.get("min_chunk_fps", 0.0)),
		int(result.get("max_chunk_usec", 0)),
		humanoids.size(),
		scavenging.size(),
		str(nest_summary),
	])


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] if not nodes.is_empty() else null


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
