extends SceneTree

const KIT_DIR := "res://assets/vendor/quaternius/medieval_village_megakit/gltf_godot"
const KIT_ROOT := "res://assets/vendor/quaternius/medieval_village_megakit"
const EXCLUDED_SAMPLE_GROUND := "SampleScene_Ground.gltf"
const SHOWCASE_SCENE := preload("res://scenes/showcase/medieval_village_megakit_showcase.tscn")
const ATTRIBUTION_PATH := "res://ATTRIBUTION.md"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_license_files()
	_validate_attribution()
	_validate_models_load()
	await _validate_showcase_scene()
	if _failures.is_empty():
		print("MEDIEVAL_VILLAGE_MEGAKIT_SHOWCASE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("MEDIEVAL_VILLAGE_MEGAKIT_SHOWCASE_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_license_files() -> void:
	var license_text := _read_text(KIT_ROOT.path_join("License_Source.txt"))
	if not license_text.contains("CC0 1.0 Universal"):
		_fail("Medieval Village MegaKit license file should state CC0 1.0 Universal")
	var format_text := _read_text(KIT_ROOT.path_join("Format Differences.txt"))
	if not format_text.contains("glTF (Godot) - Meshes with collisions"):
		_fail("Format notes should document Godot glTF collision naming")


func _validate_attribution() -> void:
	var attribution_text := _read_text(ATTRIBUTION_PATH)
	if not attribution_text.contains("Medieval Village MegaKit Source"):
		_fail("ATTRIBUTION.md should list Medieval Village MegaKit Source")
	if not attribution_text.contains("assets/vendor/quaternius/medieval_village_megakit/"):
		_fail("ATTRIBUTION.md should list medieval village project path")


func _validate_models_load() -> void:
	var files := DirAccess.get_files_at(KIT_DIR)
	var model_count := 0
	for file_name in files:
		if file_name.get_extension().to_lower() != "gltf":
			continue
		model_count += 1
		var model_path := KIT_DIR.path_join(file_name)
		var packed_scene := load(model_path) as PackedScene
		if packed_scene == null:
			_fail("Failed to load model as PackedScene: %s" % model_path)
	if model_count < 304:
		_fail("Expected at least 304 Godot glTF models, found %d" % model_count)
	print("MEDIEVAL_VILLAGE_MEGAKIT_MODELS count=%d" % model_count)


func _validate_showcase_scene() -> void:
	var scene := SHOWCASE_SCENE.instantiate()
	if scene == null:
		_fail("Failed to instantiate medieval village showcase scene")
		return
	if String(scene.get("asset_directory")) != KIT_DIR:
		_fail("Showcase scene should point at %s" % KIT_DIR)
	if scene.get("normalize_model_scale"):
		_fail("Showcase scene should preserve modular model scale")
	var excluded_files = scene.get("excluded_model_files")
	if not excluded_files.has(EXCLUDED_SAMPLE_GROUND):
		_fail("Showcase scene should exclude hilly sample ground")
	if not scene.get("disable_model_shadows"):
		_fail("Showcase scene should disable model shadow casting")
	if int(scene.get("columns")) <= 0:
		_fail("Showcase scene should define a positive column count")
	root.add_child(scene)
	await process_frame
	var slot_count := 0
	for child in scene.get_children():
		if String(child.name).begins_with("Slot_"):
			slot_count += 1
			if String(child.name).contains("SampleScene_Ground"):
				_fail("Showcase scene should not build a slot for SampleScene_Ground")
	if slot_count != 304:
		_fail("Showcase scene should build 304 modular model slots, found %d" % slot_count)
	scene.queue_free()
	await process_frame


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Missing text file: %s" % path)
		return ""
	return file.get_as_text()


func _fail(message: String) -> void:
	_failures.append(message)
