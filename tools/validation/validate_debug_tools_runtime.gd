extends SceneTree

const DEMO_WORLD_SCENE := preload("res://scenes/worlds/demo_world/demo_world.tscn")

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = DEMO_WORLD_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(180)
	_validate_debug_tools()
	if _failures.is_empty():
		print("DEBUG_TOOLS_RUNTIME_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("DEBUG_TOOLS_RUNTIME_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_debug_tools() -> void:
	var debug_node := root.get_node_or_null("GameDebug")
	if debug_node == null or not bool(debug_node.call("is_debug_enabled")):
		_fail("GameDebug should be enabled for dev debug tools")
	var hud := _scene.get_node_or_null("GameHUD")
	if hud == null:
		_fail("GameHUD missing")
		return
	var fps_label := hud.get_node_or_null("FPSLabel") as Label
	if fps_label == null or not fps_label.visible:
		_fail("FPSLabel should exist and be visible")
	var status := get_first_node_in_group("world_status_controller")
	if status == null:
		_fail("WorldStatusController missing")
		return
	var debug_menu := status.get("debug_menu") as Control
	if debug_menu == null or not debug_menu.visible:
		_fail("DebugMenu should be created and visible in debug mode")
	var lod_overlay := status.get("lod_radius_overlay") as Node3D
	if lod_overlay == null or not lod_overlay.visible:
		_fail("LOD radius overlay should be created and visible in debug mode")


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
