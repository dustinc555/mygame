extends SceneTree

const BROWSER_SCRIPT := preload("res://tools/building_piece_browser/building_piece_browser.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var browser := BROWSER_SCRIPT.new()
	root.add_child(browser)
	await process_frame
	var models: Array = browser.get("_models")
	var wrapped_by_path: Dictionary = browser.get("_wrapped_by_path")
	var expected_sources := {}
	for file in DirAccess.get_files_at(BROWSER_SCRIPT.PACK_DIR):
		if file.get_extension().to_lower() == "gltf" and file != "SampleScene_Ground.gltf":
			expected_sources[BROWSER_SCRIPT.PACK_DIR.path_join(file)] = true
	_assert(not expected_sources.is_empty(), "Source pack must contain models")
	var seen := {}
	for model in models:
		var path := str(model.get("path", ""))
		_assert(expected_sources.has(path), "Browser exposes unexpected source: " + path)
		_assert(not seen.has(path), "Browser repeats source: " + path)
		seen[path] = true
		var source := load(path) as PackedScene
		_assert(source != null, "Source must load: " + path)
	_assert(seen.size() == expected_sources.size(), "Browser must enumerate every non-sample source")
	_assert(not wrapped_by_path.is_empty(), "Browser must discover reviewed definitions")
	var ids := {}
	for source_path in wrapped_by_path:
		_assert(seen.has(source_path), "Wrapper must refer to a browsed source: " + source_path)
		var definition := load(str(wrapped_by_path[source_path])) as ModularBuildingPieceDefinition
		_assert(definition != null, "Discovered wrapper definition must load")
		if definition == null:
			continue
		_assert(not definition.piece_id.strip_edges().is_empty() and not ids.has(definition.piece_id), "Definition IDs must be nonblank and unique: " + definition.piece_id)
		ids[definition.piece_id] = true
		_assert(definition.source_scene != null and definition.source_scene.resource_path == source_path, "Wrapper source must match the actual resource, not a text mention")
		_assert(definition.scene != null, "Definition must load its wrapper scene")
		if definition.scene != null:
			var wrapper := definition.scene.instantiate()
			_assert(wrapper != null and wrapper.has_method("get_piece_id"), "Wrapper must instantiate as a modular piece")
			if wrapper != null:
				_assert(wrapper.get_piece_id() == definition.piece_id, "Wrapper/definition identity mismatch: " + definition.piece_id)
				wrapper.free()
	browser.queue_free()
	await process_frame
	for failure in _failures:
		push_error(failure)
	print("MEDIEVAL_PIECE_BROWSER_OK sources=%d wrapped=%d" % [models.size(), wrapped_by_path.size()] if _failures.is_empty() else "MEDIEVAL_PIECE_BROWSER_FAILED")
	quit(0 if _failures.is_empty() else 1)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
