extends SceneTree

const PROJECT_PATH := "res://project.godot"
const PLUGIN_CFG_PATH := "res://addons/modular_building_authoring/plugin.cfg"
const PLUGIN_SCRIPT_PATH := "res://addons/modular_building_authoring/plugin.gd"
const WORLD_BUILDING_ICON_PATH := "res://addons/modular_building_authoring/icons/world_building.svg"
const WOODBRICK_HOUSE_SCENE_PATH := "res://features/world/projection/buildings/woodbrick_house.tscn"
const WORLD_BUILDING_SCRIPT_PATH := "res://features/world/projection/buildings/world_building.gd"
const MODULAR_BUILDING_PIECE_SCRIPT_PATH := "res://features/world/projection/buildings/modular_building_piece.gd"
const WORLD_BUILDING_SCRIPT := preload("res://features/world/projection/buildings/world_building.gd")
const MODULAR_BUILDING_PIECE_SCRIPT := preload("res://features/world/projection/buildings/modular_building_piece.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_plugin_files()
	_validate_project_enables_plugin()
	_validate_woodbrick_house_root()
	_validate_world_building_modular_visibility()
	_finish()


func _validate_plugin_files() -> void:
	if not FileAccess.file_exists(PLUGIN_CFG_PATH):
		_fail("Missing modular building plugin.cfg")
	var plugin_cfg_text := _read_text(PLUGIN_CFG_PATH)
	if not plugin_cfg_text.contains("script=\"plugin.gd\""):
		_fail("modular building plugin.cfg script must be relative: script=\"plugin.gd\"")
	var plugin_text := _read_text(PLUGIN_SCRIPT_PATH)
	if plugin_text.contains("add_control_to_dock") or plugin_text.contains("DOCK_SLOT"):
		_fail("modular building plugin must not add editor docks")
	if not plugin_text.contains("CONTAINER_SPATIAL_EDITOR_MENU"):
		_fail("modular building plugin should live in the 3D editor menu toolbar")
	if plugin_text.contains("CheckButton.new()"):
		_fail("modular building plugin should not require a Build toggle")
	if plugin_text.contains("OptionButton.new()"):
		_fail("modular building plugin should use category dropdowns, not one brush picker")
	if not plugin_text.contains("MenuButton.new()"):
		_fail("modular building plugin should expose category dropdowns")
	if not plugin_text.contains("_on_piece_menu_item_pressed"):
		_fail("modular building plugin should spawn pieces from dropdown item clicks")
	if not plugin_text.contains("scene_changed.connect"):
		_fail("modular building plugin should refresh when the edited scene changes")
	if not plugin_text.contains("_find_world_building_from_edited_scene_root"):
		_fail("modular building plugin should activate from an open WorldBuilding scene root")
	if not plugin_text.contains("func _handles"):
		_fail("modular building plugin should tell Godot it handles WorldBuilding nodes")
	if not plugin_text.contains("func _edit"):
		_fail("modular building plugin should refresh when Godot edits handled nodes")
	if not plugin_text.contains("func _make_visible"):
		_fail("modular building plugin should control 3D toolbar visibility")
	if not plugin_text.contains("resource_path == script_resource.resource_path"):
		_fail("modular building plugin should detect WorldBuilding by script path, not only resource identity")
	if not plugin_text.contains("_normalize_modular_piece_hierarchy"):
		_fail("modular building plugin should normalize copied pieces back under Pieces")
	if not plugin_text.contains("_place_piece_near_world_position"):
		_fail("modular building plugin should try marker snap before grid fallback")
	if not plugin_text.contains("_can_author_building"):
		_fail("modular building plugin should only author the opened WorldBuilding source scene")
	if plugin_text.contains("source.duplicate()"):
		_fail("modular building paste must instantiate piece scenes, not duplicate live editor nodes")
	if not plugin_text.contains("scene_file_path") or not plugin_text.contains("_paste_copied_modular_pieces"):
		_fail("modular building plugin should copy/paste modular pieces by scene path")
	if not plugin_text.contains("_select_nodes(pieces_to_add)"):
		_fail("modular building paste should select only newly pasted pieces")
	if not plugin_text.contains("func _shortcut_input") or not plugin_text.contains("set_input_as_handled"):
		_fail("modular building copy/paste shortcuts must intercept editor shortcuts before Godot default paste")
	if not plugin_text.contains("_handle_modular_copy_paste_shortcut") or not plugin_text.contains("_last_handled_shortcut_event_id"):
		_fail("modular building copy/paste should share shortcut handling and guard duplicate events")
	if not plugin_text.contains("_append_modular_pieces_under(node as Node, pieces)"):
		_fail("modular building copy should include modular descendants from selected roots")
	if not plugin_text.contains("_watched_gizmo_pieces") or not plugin_text.contains("Snap Modular Building Pieces"):
		_fail("modular building gizmo snap should preserve group selection and commit group snap as one action")
	if not plugin_text.contains("_get_piece_nearest_snap_delta") or not plugin_text.contains("excluded_pieces.has(other_piece)"):
		_fail("modular building group snap should use one anchor snap delta and ignore selected pieces as snap targets")
	if not plugin_text.contains("_get_piece_snap_transform") or not plugin_text.contains("_snap_markers_align_transform"):
		_fail("modular building plugin should align transform for window insert sockets")
	if not plugin_text.contains("Door Walls") or not plugin_text.contains("Window Walls"):
		_fail("modular building plugin should label wall-door/window pieces as wall categories")
	if not plugin_text.contains("Window Frames") or not plugin_text.contains("\"Doors\", \"categories\": [\"door\"]"):
		_fail("modular building plugin should expose real window frames and doors separately")
	if not plugin_text.contains("door_insert") or not plugin_text.contains("door_socket"):
		_fail("modular building plugin should align transform for door insert sockets")
	if plugin_text.contains("Auto Snap") or plugin_text.contains("_auto_snap_button"):
		_fail("modular building plugin should not expose toolbar Auto Snap; snap is per piece")
	if plugin_text.contains("_snap_button") or plugin_text.contains("func snap_selected_piece") or plugin_text.contains("_on_snap_selected_pressed"):
		_fail("modular building plugin should not expose a manual Snap toolbar button")
	if not plugin_text.contains("_piece_auto_snap_enabled") or not plugin_text.contains("_all_pieces_auto_snap_enabled"):
		_fail("modular building plugin should gate automatic snapping with the selected piece bool")
	if not plugin_text.contains("_piece_auto_snap_enabled(piece) and not _snap_new_piece_to_selected_piece"):
		_fail("modular building plugin should gate spawn marker/grid snapping with the spawned piece bool")
	var modular_piece_text := _read_text(MODULAR_BUILDING_PIECE_SCRIPT_PATH)
	if not modular_piece_text.contains("@export var auto_snap_enabled := true"):
		_fail("ModularBuildingPiece should expose an enabled-by-default auto_snap_enabled inspector bool")
	if not FileAccess.file_exists(WORLD_BUILDING_ICON_PATH):
		_fail("Missing WorldBuilding icon")
	else:
		var icon_image := Image.new()
		var icon_bytes := FileAccess.get_file_as_bytes(WORLD_BUILDING_ICON_PATH)
		if icon_bytes.size() == 0 or icon_image.load_svg_from_buffer(icon_bytes) != OK:
			_fail("WorldBuilding icon should load as SVG image data")
	if not plugin_text.contains("WORLD_BUILDING_ICON_PATH") or not plugin_text.contains("_pieces_menu_button.icon = _get_world_building_icon()"):
		_fail("modular building toolbar should show the WorldBuilding icon")
	var world_building_text := _read_text(WORLD_BUILDING_SCRIPT_PATH)
	if not world_building_text.contains("@icon(\"%s\")" % WORLD_BUILDING_ICON_PATH):
		_fail("WorldBuilding should declare the modular building editor icon")
	if load(PLUGIN_SCRIPT_PATH) == null:
		_fail("Missing or invalid modular building plugin script")


func _validate_project_enables_plugin() -> void:
	var project_text := _read_text(PROJECT_PATH)
	if not project_text.contains("res://addons/modular_building_authoring/plugin.cfg"):
		_fail("project.godot should enable modular building authoring plugin")


func _validate_woodbrick_house_root() -> void:
	var scene := load(WOODBRICK_HOUSE_SCENE_PATH) as PackedScene
	if scene == null:
		_fail("Missing woodbrick house authoring scene")
		return
	var root_node := scene.instantiate()
	if root_node == null:
		_fail("Unable to instantiate woodbrick house authoring scene")
		return
	var root_script := root_node.get_script() as Script
	if root_script == null or root_script.resource_path != WORLD_BUILDING_SCRIPT_PATH:
		_fail("woodbrick_house.tscn root should use WorldBuilding script")
	root_node.free()


func _validate_world_building_modular_visibility() -> void:
	var building := Node3D.new()
	building.name = "VisibilityTestBuilding"
	building.set_script(WORLD_BUILDING_SCRIPT)
	root.add_child(building)

	var pieces_root := Node3D.new()
	pieces_root.name = "Pieces"
	building.add_child(pieces_root)

	var front_piece := _make_piece("FrontWall", "wall", Vector3(0.0, 0.0, 3.0))
	var back_piece := _make_piece("BackWall", "wall", Vector3(0.0, 0.0, -3.0))
	var roof_piece := _make_piece("RoofPiece", "roof", Vector3(0.0, 3.0, 0.0))
	pieces_root.add_child(front_piece)
	pieces_root.add_child(back_piece)
	pieces_root.add_child(roof_piece)

	building.call("set_visibility_for_camera", true, Vector3(0.0, 4.0, 12.0), null)
	if front_piece.visible:
		_fail("Front modular wall should hide when camera is on front side")
	if not back_piece.visible:
		_fail("Back modular wall should stay visible when camera is on front side")
	if roof_piece.visible:
		_fail("Modular roof should hide while showing interior")
	if not bool(front_piece.get_meta("world_building_hidden_by_camera", false)):
		_fail("Hidden modular wall should be marked for raycast skip")

	building.call("set_visibility_for_camera", false, Vector3(0.0, 4.0, 12.0), null)
	if not front_piece.visible or not back_piece.visible or not roof_piece.visible:
		_fail("All modular pieces should restore when interior visibility is disabled")
	building.queue_free()
	_validate_auto_pieces_root_creation()


func _validate_auto_pieces_root_creation() -> void:
	var building := StaticBody3D.new()
	building.name = "AutoPiecesBuilding"
	building.set_script(WORLD_BUILDING_SCRIPT)
	root.add_child(building)
	var pieces_root = building.call("get_or_create_modular_pieces_root")
	if not (pieces_root is Node3D):
		_fail("WorldBuilding should auto-create a Pieces Node3D")
	elif pieces_root.name != "Pieces":
		_fail("WorldBuilding auto-created piece root should be named Pieces")
	building.queue_free()


func _make_piece(node_name: String, category: String, position: Vector3) -> Node3D:
	var piece := Node3D.new()
	piece.name = node_name
	piece.set_script(MODULAR_BUILDING_PIECE_SCRIPT)
	piece.set("category", category)
	piece.set("building_level", 0)
	piece.position = position
	return piece


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Missing text file: %s" % path)
		return ""
	return file.get_as_text()


func _finish() -> void:
	if _failures.is_empty():
		print("MODULAR_BUILDING_DESIGNER_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("MODULAR_BUILDING_DESIGNER_FAILED count=%d" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
