@tool
extends HBoxContainer

## World nav tools for the 3D viewport toolbar:
## - "Bake World Nav": bakes the edited world scene's navcache by launching
##   the headless CLI baker (tools/bake_world_navcache.gd) as a background
##   subprocess. The editor process never bakes: in-editor worker bakes fight
##   the filesystem watcher/import pool over 288 saved .res files and freeze
##   the editor. Progress is read from tile files appearing on disk; the
##   button doubles as Cancel (kills the subprocess).
## - "Nav" / "Tiles" toggles: preview the CACHED bake result directly in the
##   editor viewport (transient meshes, never saved into the scene).
##
## Visible whenever the edited scene contains a Terrain3D.

const PIPELINE := preload("res://features/core/navigation/world_nav_bake_pipeline.gd")
const SETTINGS_PATH := "res://features/core/navigation/resources/world_navigation_settings.tres"
const BAKER_SCRIPT_PATH := "res://tools/bake_world_navcache.gd"

var _bake_button: Button
var _progress_bar: ProgressBar
var _status_label: Label
var _nav_toggle: CheckBox
var _tiles_toggle: CheckBox

var _baking := false
var _bake_pid := -1
var _bake_elapsed := 0.0
var _expected_tiles := 0
var _cache_dir := ""

var _preview_root: Node3D
var _preview_scene_root: Node


func _ready() -> void:
	_bake_button = Button.new()
	_bake_button.text = "Bake World Nav"
	_bake_button.tooltip_text = "Bake this world's navmesh tiles to disk (navcache/ beside the scene) in a background process. Runtime loads them instantly."
	_bake_button.pressed.connect(_on_bake_pressed)
	add_child(_bake_button)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(140.0, 0.0)
	_progress_bar.show_percentage = false
	_progress_bar.visible = false
	add_child(_progress_bar)
	_status_label = Label.new()
	add_child(_status_label)
	_nav_toggle = CheckBox.new()
	_nav_toggle.text = "Nav"
	_nav_toggle.tooltip_text = "Preview the cached navmesh in the viewport."
	_nav_toggle.toggled.connect(func(_pressed: bool) -> void: _refresh_preview())
	add_child(_nav_toggle)
	_tiles_toggle = CheckBox.new()
	_tiles_toggle.text = "Tiles"
	_tiles_toggle.tooltip_text = "Preview cached tile boundaries in the viewport."
	_tiles_toggle.toggled.connect(func(_pressed: bool) -> void: _refresh_preview())
	add_child(_tiles_toggle)
	set_process(true)


func _process(delta: float) -> void:
	var root := _edited_root()
	if _preview_scene_root != root:
		# Scene switched: previews belong to the old scene.
		_clear_preview()
		_nav_toggle.set_pressed_no_signal(false)
		_tiles_toggle.set_pressed_no_signal(false)
		_preview_scene_root = root
	if not _baking:
		visible = _find_terrains(root).size() > 0
		return
	_bake_elapsed += delta
	var done := PIPELINE.cached_tile_coords(_cache_dir).size()
	var manifest_written := FileAccess.file_exists(_cache_dir + "/manifest.json")
	if manifest_written:
		_finish_bake("Baked %d tiles -> %s" % [done, _cache_dir])
		return
	if not OS.is_process_running(_bake_pid):
		DirAccess.remove_absolute(_cache_dir)
		_finish_bake("Bake process exited without finishing; partial cache discarded.")
		return
	_progress_bar.value = done
	_status_label.text = "Baking %d / %d  %s %.0fs" % [done, _expected_tiles, _spinner_glyph(), _bake_elapsed]


func _spinner_glyph() -> String:
	return ["|", "/", "-", "\\"][int(_bake_elapsed * 6.0) % 4]


## --- Baking (background subprocess) --------------------------------------------


func _on_bake_pressed() -> void:
	if _baking:
		if _bake_pid > 0 and OS.is_process_running(_bake_pid):
			OS.kill(_bake_pid)
		_remove_partial_cache()
		_finish_bake("Bake cancelled; partial cache discarded.")
		return
	var root := _edited_root()
	if root == null or root.scene_file_path.is_empty():
		_status_label.text = "Save the scene first."
		return
	var terrains := _find_terrains(root)
	if terrains.is_empty():
		_status_label.text = "No Terrain3D in this scene."
		return
	var settings: WorldNavigationSettings = load(SETTINGS_PATH)
	_expected_tiles = PIPELINE.enumerate_world_tiles(terrains, settings).size()
	if _expected_tiles == 0:
		_status_label.text = "No terrain regions to bake."
		return
	_cache_dir = PIPELINE.cache_dir_for_scene(root.scene_file_path)
	_remove_partial_cache()
	DirAccess.remove_absolute(_cache_dir + "/manifest.json")
	var arguments := PackedStringArray([
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", BAKER_SCRIPT_PATH,
		"--", root.scene_file_path,
	])
	_bake_pid = OS.create_process(OS.get_executable_path(), arguments)
	if _bake_pid <= 0:
		_status_label.text = "Failed to launch bake process."
		return
	_baking = true
	_bake_elapsed = 0.0
	_bake_button.text = "Cancel Bake"
	_progress_bar.max_value = _expected_tiles
	_progress_bar.value = 0
	_progress_bar.visible = true
	_status_label.text = "Baking 0 / %d" % _expected_tiles


func _finish_bake(message: String) -> void:
	_baking = false
	_bake_pid = -1
	_bake_button.text = "Bake World Nav"
	_progress_bar.visible = false
	_status_label.text = message
	EditorInterface.get_resource_filesystem().scan()
	_refresh_preview()


func _remove_partial_cache() -> void:
	# A cache without a manifest is unusable; clear stale tile files so the
	# next bake's progress count starts at zero.
	for coord in PIPELINE.cached_tile_coords(_cache_dir):
		DirAccess.remove_absolute(PIPELINE.tile_cache_path(_cache_dir, coord))


## --- Viewport preview of the cached bake ---------------------------------------


func _refresh_preview() -> void:
	_clear_preview()
	if not (_nav_toggle.button_pressed or _tiles_toggle.button_pressed):
		return
	var root := _edited_root()
	if root == null:
		return
	var settings: WorldNavigationSettings = load(SETTINGS_PATH)
	# Preview is strict per-scene: with world1 open you see world1's bake and
	# nothing else. (Runtime keeps a zone-cache fallback; the preview must not
	# lie about what THIS scene has baked.)
	var cache_dir := PIPELINE.cache_dir_for_scene(root.scene_file_path)
	if not PIPELINE.manifest_matches(cache_dir, settings):
		_status_label.text = "%s has no bake; nothing to preview." % root.name
		return
	_preview_root = Node3D.new()
	_preview_root.name = "WorldNavPreview"
	# Transient: no owner, so it can never be saved into the scene.
	root.add_child(_preview_root)
	var tile := PIPELINE.clamped_tile_size(settings)
	var nav_material: StandardMaterial3D = PIPELINE.debug_material(Color(0.35, 0.75, 0.95, 0.35))
	var frame_material: StandardMaterial3D = PIPELINE.debug_material(Color(0.71, 0.58, 0.32, 0.9))
	var shown := 0
	for coord in PIPELINE.cached_tile_coords(cache_dir):
		if _nav_toggle.button_pressed:
			var nav_mesh: NavigationMesh = PIPELINE.load_tile(cache_dir, coord)
			if nav_mesh != null:
				var mesh: ArrayMesh = PIPELINE.build_navmesh_debug_mesh(nav_mesh)
				if mesh != null:
					var instance := MeshInstance3D.new()
					instance.mesh = mesh
					instance.material_override = nav_material
					_preview_root.add_child(instance)
		if _tiles_toggle.button_pressed:
			var frame := MeshInstance3D.new()
			frame.mesh = PIPELINE.build_tile_frame_mesh(coord, tile)
			frame.material_override = frame_material
			_preview_root.add_child(frame)
		shown += 1
	_status_label.text = "Previewing %d cached tiles" % shown


func _clear_preview() -> void:
	if _preview_root != null and is_instance_valid(_preview_root):
		_preview_root.queue_free()
	_preview_root = null


func _edited_root() -> Node:
	return EditorInterface.get_edited_scene_root()


func _find_terrains(node: Node) -> Array:
	var result: Array = []
	if node == null:
		return result
	if node.is_class("Terrain3D"):
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_terrains(child))
	return result
