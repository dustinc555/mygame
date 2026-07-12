extends SceneTree

const BROWSER_SCRIPT := preload("res://tools/building_piece_browser/building_piece_browser.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var browser := BROWSER_SCRIPT.new()
	root.add_child(browser)
	await process_frame
	var models: Array = browser.get("_models")
	var wrapped_by_path: Dictionary = browser.get("_wrapped_by_path")
	_assert(models.size() == 304, "Expected every non-sample Medieval Village GLTF source, found %d." % models.size())
	_assert(wrapped_by_path.size() == 30, "Expected 30 reviewed modular wrappers, found %d." % wrapped_by_path.size())
	browser.queue_free()
	print("MEDIEVAL_PIECE_BROWSER_OK sources=%d wrapped=%d" % [models.size(), wrapped_by_path.size()])
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
