extends SceneTree

const OVERLAY_SCRIPT := preload("res://features/ui/projection/navigation_loading_overlay.gd")

var _failures: Array[String] = []


class FakeWorldTime:
	extends Node

	var reasons: Dictionary = {}

	func request_pause(reason: String) -> bool:
		reasons[reason] = true
		get_tree().paused = true
		return true

	func release_pause(reason: String) -> void:
		reasons.erase(reason)
		get_tree().paused = not reasons.is_empty()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var overlay := OVERLAY_SCRIPT.new()
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(overlay)
	var world_time := FakeWorldTime.new()
	root.add_child(world_time)
	var context := BootstrapContext.new(root)
	context.register(&"world_time", world_time)
	overlay.initialize(context)
	overlay.set_loading_request("test", true)
	overlay.set_process(false)
	overlay._process(0.01)
	if not overlay.is_loading_gate_active("test") or not paused:
		_fail("Requested loading work should immediately show the indicator and pause the tree")
	var title := overlay.get("_title_label") as Label
	if title == null or title.text != "Loading":
		_fail("Loading indicator should use only the player-facing label 'Loading'")
	overlay.set_loading_request("test", false)
	world_time.request_pause("manual")
	overlay.set_process(false)
	overlay._process(0.20)
	if not overlay.is_loading_gate_active():
		_fail("A shown loading splash should remain visible for at least 350ms")
	overlay._process(0.16)
	if overlay.is_loading_gate_active() or not paused:
		_fail("Loading release should preserve another owner's pause")
	world_time.release_pause("manual")
	if paused:
		_fail("The final pause owner should resume the tree")
	overlay.queue_free()
	if _failures.is_empty():
		print("REALIZATION_LOADING_OVERLAY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
