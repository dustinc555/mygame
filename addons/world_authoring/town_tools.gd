@tool
extends RefCounted

## SettlementTown concept tool context for the world_authoring plugin.
## Activates when a SettlementTown is selected or a Zone scene is open.
## Towns are simple: a root plus Facilities. The tools are exactly that —
## "New Town" (minimal per-town scene + SettlementDefinition, instanced into
## the open Zone at the camera's ground point), "Add Facility" (pick from the
## catalog, lands under Facilities, ground-snapped at runtime), and
## "Remove Facility". When the town is an instance inside the open zone,
## add/remove edits the town's own scene file and refreshes the instance, so
## per-town scenes stay the single source of truth.

const TOWN_ICON_PATH := "res://addons/world_authoring/icons/town.svg"
const FACILITY_CATALOG := [
	{"label": "House", "scene": "res://features/world/projection/buildings/woodbrick_house.tscn"},
	{"label": "Medium Shop Shell", "scene": "res://features/world/projection/buildings/woodbrick_shop_medium.tscn"},
	{"label": "Bar", "scene": "res://features/settlements/bridge/settlement_bar.tscn"},
	{"label": "Jail", "scene": "res://features/settlements/bridge/settlement_jail.tscn"},
	{"label": "Keep", "scene": "res://features/settlements/bridge/settlement_keep.tscn"},
	{"label": "Field", "scene": "res://features/settlements/bridge/settlement_field.tscn"},
]
const SETTLEMENT_TOWN_SCRIPT := preload("res://features/settlements/bridge/settlement_town.gd")
const ZONE_SCRIPT := preload("res://features/world/projection/zone_root.gd")
const TOWN_TEMPLATE := preload("res://features/settlements/bridge/settlement_town.tscn")
const SETTLEMENT_DEFINITION_SCRIPT := preload("res://features/world_sim/resources/settlement_definition.gd")
const SETTLEMENT_DEFINITIONS_DIR := "res://features/world_sim/resources/settlements"

var _plugin: EditorPlugin
var _toolbar: HBoxContainer
var _status_label: Label
var _new_town_button: Button
var _add_facility_button: MenuButton
var _remove_facility_button: Button
var _active_town: Node
var _new_town_dialog: ConfirmationDialog
var _town_name_edit: LineEdit
var _town_icon: Texture2D


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_build_toolbar()


func toolbar() -> Control:
	return _toolbar


func handles(object: Object) -> bool:
	if object is Node and _find_town_ancestor(object as Node) != null:
		return true
	return _edited_zone_root() != null or _find_town_from_edited_scene_root() != null


func claims_node(node: Node) -> bool:
	return _is_script_node(node, SETTLEMENT_TOWN_SCRIPT)


func edit(object: Object) -> void:
	if object is Node:
		_active_town = _find_town_ancestor(object as Node)
	if _active_town == null:
		_active_town = _find_town_from_edited_scene_root()
	_refresh_toolbar()


func refresh() -> void:
	_refresh_active_town_context()


func is_active() -> bool:
	return _get_active_town() != null or _edited_zone_root() != null


func on_selection_changed() -> void:
	_refresh_active_town_context()


func on_scene_changed(_scene_root: Node) -> void:
	_refresh_active_town_context()


func process(_delta: float) -> void:
	pass


func shortcut_input(_event: InputEvent) -> bool:
	return false


func forward_3d_gui_input(_camera: Camera3D, _event: InputEvent) -> int:
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func teardown() -> void:
	if _new_town_dialog != null and is_instance_valid(_new_town_dialog):
		_new_town_dialog.queue_free()
	_new_town_dialog = null
	if _toolbar != null:
		_toolbar.free()
		_toolbar = null
	_active_town = null
	_plugin = null


## --- New Town -------------------------------------------------------------


func _show_new_town_dialog() -> void:
	if _new_town_dialog == null or not is_instance_valid(_new_town_dialog):
		_new_town_dialog = ConfirmationDialog.new()
		_new_town_dialog.title = "New Town"
		_new_town_dialog.ok_button_text = "Create"
		var row := VBoxContainer.new()
		var hint := Label.new()
		hint.text = "Town name (id becomes snake_case; faction and behavior are wired later in the inspector):"
		row.add_child(hint)
		_town_name_edit = LineEdit.new()
		_town_name_edit.placeholder_text = "Rustwash Landing"
		row.add_child(_town_name_edit)
		_new_town_dialog.add_child(row)
		_new_town_dialog.register_text_enter(_town_name_edit)
		_new_town_dialog.confirmed.connect(_on_new_town_confirmed)
		_plugin.get_editor_interface().get_base_control().add_child(_new_town_dialog)
	_town_name_edit.text = ""
	_new_town_dialog.popup_centered(Vector2i(420, 0))
	_town_name_edit.grab_focus()


func _on_new_town_confirmed() -> void:
	var display_name := _town_name_edit.text.strip_edges()
	if display_name.is_empty():
		_set_status("Town name required.")
		return
	var zone := _edited_zone_root()
	if zone == null:
		_set_status("Open a Zone scene to create a town.")
		return
	var settlement_id := display_name.to_snake_case()
	var zone_scene_dir := zone.scene_file_path.get_base_dir()
	var town_scene_path := "%s/towns/%s.tscn" % [zone_scene_dir, settlement_id]
	var definition_path := "%s/%s.tres" % [SETTLEMENT_DEFINITIONS_DIR, settlement_id]
	if FileAccess.file_exists(town_scene_path) or FileAccess.file_exists(definition_path):
		_set_status("Town '%s' already exists (scene or definition)." % settlement_id)
		return
	var drop_position := _camera_ground_point(zone)
	var definition := _save_settlement_definition(settlement_id, display_name, drop_position, definition_path)
	if definition == null:
		_set_status("Failed to save settlement definition.")
		return
	if not _save_town_scene(settlement_id, display_name, definition, town_scene_path):
		_set_status("Failed to save town scene.")
		return
	_instance_town_into_zone(zone, town_scene_path, drop_position)
	_set_status("Created %s (%s)." % [display_name, town_scene_path])


func _save_settlement_definition(settlement_id: String, display_name: String, world_position: Vector3, path: String) -> Resource:
	var definition: Resource = SETTLEMENT_DEFINITION_SCRIPT.new()
	definition.set("settlement_id", settlement_id)
	definition.set("display_name", display_name)
	definition.set("world_position", world_position)
	DirAccess.make_dir_recursive_absolute(SETTLEMENT_DEFINITIONS_DIR)
	if ResourceSaver.save(definition, path) != OK:
		return null
	return load(path)


func _save_town_scene(settlement_id: String, _display_name: String, definition: Resource, path: String) -> bool:
	var town := TOWN_TEMPLATE.instantiate()
	town.name = settlement_id.to_pascal_case()
	# Expand the template into a standalone per-town scene (demo-town pattern)
	# instead of an inherited scene: towns diverge freely once authored.
	town.scene_file_path = ""
	town.set("settlement_definition", definition)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var packed := PackedScene.new()
	if packed.pack(town) != OK:
		town.free()
		return false
	var saved := ResourceSaver.save(packed, path) == OK
	town.free()
	if saved:
		EditorInterface.get_resource_filesystem().scan()
	return saved


func _instance_town_into_zone(zone: Node3D, town_scene_path: String, drop_position: Vector3) -> void:
	var town_scene := load(town_scene_path) as PackedScene
	if town_scene == null:
		return
	var towns_root := zone.get_node_or_null("Towns") as Node3D
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("New Town")
	if towns_root == null:
		towns_root = Node3D.new()
		towns_root.name = "Towns"
		undo_redo.add_do_method(zone, "add_child", towns_root)
		undo_redo.add_do_method(towns_root, "set_owner", zone)
		undo_redo.add_undo_method(zone, "remove_child", towns_root)
		undo_redo.add_do_reference(towns_root)
	var town := town_scene.instantiate() as Node3D
	town.position = drop_position - zone.global_position
	undo_redo.add_do_method(towns_root, "add_child", town)
	undo_redo.add_do_method(town, "set_owner", zone)
	undo_redo.add_undo_method(towns_root, "remove_child", town)
	undo_redo.add_do_reference(town)
	undo_redo.commit_action()
	_select_node(town)


## --- Add / Remove Facility --------------------------------------------------


## Adds a facility scene under the town scene's Facilities root, editing the
## town's own .tscn (single source of truth). Pure file surgery: usable from
## the editor context and from headless validation.
static func add_facility_to_town_scene(town_scene_path: String, facility_scene_path: String, local_position: Vector3) -> bool:
	var town_scene := ResourceLoader.load(town_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var facility_scene := load(facility_scene_path) as PackedScene
	if town_scene == null or facility_scene == null:
		return false
	var town := town_scene.instantiate()
	var facilities := town.get_node_or_null("Facilities") as Node3D
	if facilities == null:
		facilities = Node3D.new()
		facilities.name = "Facilities"
		town.add_child(facilities)
		facilities.owner = town
	var facility := facility_scene.instantiate() as Node3D
	if facility == null:
		town.free()
		return false
	facility.name = _unique_facility_name(facilities, facility_scene_path.get_file().get_basename().to_pascal_case())
	facilities.add_child(facility)
	facility.owner = town
	facility.position = local_position
	var packed := PackedScene.new()
	var saved := packed.pack(town) == OK and ResourceSaver.save(packed, town_scene_path) == OK
	town.free()
	return saved


static func remove_facility_from_town_scene(town_scene_path: String, facility_name: String) -> bool:
	var town_scene := ResourceLoader.load(town_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if town_scene == null:
		return false
	var town := town_scene.instantiate()
	var facility := town.get_node_or_null("Facilities/%s" % facility_name)
	if facility == null:
		town.free()
		return false
	facility.get_parent().remove_child(facility)
	facility.free()
	var packed := PackedScene.new()
	var saved := packed.pack(town) == OK and ResourceSaver.save(packed, town_scene_path) == OK
	town.free()
	return saved


static func _unique_facility_name(parent: Node, base_name: String) -> String:
	var cleaned := base_name if not base_name.is_empty() else "Facility"
	var candidate := cleaned
	var index := 2
	while parent.get_node_or_null(candidate) != null:
		candidate = "%s%d" % [cleaned, index]
		index += 1
	return candidate


func _on_add_facility_pressed(item_index: int) -> void:
	if item_index < 0 or item_index >= FACILITY_CATALOG.size():
		return
	var town := _get_active_town() as Node3D
	if town == null:
		return
	var entry: Dictionary = FACILITY_CATALOG[item_index]
	var drop := _camera_ground_point(town)
	var local_position := town.global_transform.affine_inverse() * drop
	if _town_is_edited_scene_root(town):
		_add_facility_to_open_town(town, entry, local_position)
		return
	if town.scene_file_path.is_empty():
		_set_status("Town has no scene file; open its scene to edit.")
		return
	if not add_facility_to_town_scene(town.scene_file_path, str(entry["scene"]), local_position):
		_set_status("Failed to add %s." % entry["label"])
		return
	var fresh := _refresh_town_instance(town)
	_set_status("Added %s to %s." % [entry["label"], fresh.name if fresh != null else "town"])


func _add_facility_to_open_town(town: Node3D, entry: Dictionary, local_position: Vector3) -> void:
	var facility_scene := load(str(entry["scene"])) as PackedScene
	if facility_scene == null:
		return
	var facilities := town.get_node_or_null("Facilities")
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Add Facility")
	if facilities == null:
		facilities = Node3D.new()
		facilities.name = "Facilities"
		undo_redo.add_do_method(town, "add_child", facilities)
		undo_redo.add_do_method(facilities, "set_owner", town)
		undo_redo.add_undo_method(town, "remove_child", facilities)
		undo_redo.add_do_reference(facilities)
	var facility := facility_scene.instantiate() as Node3D
	facility.name = _unique_facility_name(facilities, str(entry["scene"]).get_file().get_basename().to_pascal_case())
	facility.position = local_position
	undo_redo.add_do_method(facilities, "add_child", facility)
	undo_redo.add_do_method(facility, "set_owner", town)
	undo_redo.add_undo_method(facilities, "remove_child", facility)
	undo_redo.add_do_reference(facility)
	undo_redo.commit_action()
	_select_node(facility)
	_set_status("Added %s." % entry["label"])


func _on_remove_facility_pressed() -> void:
	var facility := _selected_facility()
	if facility == null:
		return
	var town := _find_town_ancestor(facility) as Node3D
	if town == null:
		return
	if _town_is_edited_scene_root(town):
		var facilities := facility.get_parent()
		var undo_redo := _plugin.get_undo_redo()
		undo_redo.create_action("Remove Facility")
		undo_redo.add_do_method(facilities, "remove_child", facility)
		undo_redo.add_undo_method(facilities, "add_child", facility)
		undo_redo.add_undo_method(facility, "set_owner", town)
		undo_redo.add_undo_reference(facility)
		undo_redo.commit_action()
		_set_status("Removed facility.")
		return
	if town.scene_file_path.is_empty():
		_set_status("Town has no scene file; open its scene to edit.")
		return
	var facility_name := str(facility.name)
	if not remove_facility_from_town_scene(town.scene_file_path, facility_name):
		_set_status("Failed to remove %s." % facility_name)
		return
	_refresh_town_instance(town)
	_set_status("Removed %s." % facility_name)


## The selected node's facility: the direct child of the town's Facilities
## root that the selection sits under.
func _selected_facility() -> Node3D:
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		var town := _find_town_ancestor(node)
		if town == null:
			continue
		var facilities := town.get_node_or_null("Facilities")
		if facilities == null:
			continue
		var current := node as Node
		while current != null and current.get_parent() != facilities:
			current = current.get_parent()
		if current is Node3D:
			return current as Node3D
	return null


func _town_is_edited_scene_root(town: Node) -> bool:
	return town == _plugin.get_editor_interface().get_edited_scene_root()


## Swaps a zone-embedded town instance for a fresh instantiate of its just-
## saved scene file, preserving name, parent, and transform.
func _refresh_town_instance(town: Node3D) -> Node3D:
	var parent := town.get_parent()
	var zone_root := _plugin.get_editor_interface().get_edited_scene_root()
	if parent == null or zone_root == null:
		return null
	var scene_path := town.scene_file_path
	var town_name := str(town.name)
	var town_transform := town.transform
	town.free()
	var fresh_scene := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if fresh_scene == null:
		return null
	var fresh := fresh_scene.instantiate() as Node3D
	fresh.name = town_name
	parent.add_child(fresh)
	fresh.owner = zone_root
	fresh.transform = town_transform
	EditorInterface.get_resource_filesystem().scan()
	_select_node(fresh)
	return fresh


## Ground point at the center of the editor camera's view; zone origin when
## the ray misses terrain.
func _camera_ground_point(zone: Node3D) -> Vector3:
	var viewport := _plugin.get_editor_interface().get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return zone.global_position
	var space := camera.get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 2000.0
	var hit := BuildingPlacementSolver.terrain_ray(space, from, to)
	return hit.get("position", zone.global_position)


## --- Context plumbing ------------------------------------------------------


func _refresh_active_town_context() -> void:
	_active_town = _find_town_from_selection()
	if _active_town == null:
		_active_town = _find_town_from_edited_scene_root()
	_refresh_toolbar()


func _get_active_town() -> Node:
	if _active_town != null and is_instance_valid(_active_town):
		return _active_town
	_active_town = _find_town_from_edited_scene_root()
	return _active_town if _active_town != null and is_instance_valid(_active_town) else null


func _edited_zone_root() -> Node3D:
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	return root as Node3D if root != null and _is_script_node(root, ZONE_SCRIPT) else null


func _find_town_from_selection() -> Node:
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		var town := _find_town_ancestor(node)
		if town != null:
			return town
	return null


func _find_town_from_edited_scene_root() -> Node:
	return _find_town_ancestor(_plugin.get_editor_interface().get_edited_scene_root())


func _find_town_ancestor(node: Node) -> Node:
	var current := node
	while current != null:
		if _is_script_node(current, SETTLEMENT_TOWN_SCRIPT):
			return current
		current = current.get_parent()
	return null


func _is_script_node(node: Node, script_resource: Script) -> bool:
	if node == null or script_resource == null:
		return false
	var node_script := node.get_script() as Script
	if node_script == null:
		return false
	return node_script == script_resource or node_script.resource_path == script_resource.resource_path


func _select_node(node: Node) -> void:
	var selection := _plugin.get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(node)
	_plugin.get_editor_interface().edit_node(node)


## --- Toolbar ---------------------------------------------------------------


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "TownToolbar"
	_toolbar.add_theme_constant_override("separation", 6)
	_status_label = Label.new()
	_status_label.text = "Town: none"
	_toolbar.add_child(_status_label)
	_new_town_button = Button.new()
	_new_town_button.text = "New Town"
	_new_town_button.icon = _get_town_icon()
	_new_town_button.tooltip_text = "Create a per-town scene in this Zone's towns/ folder and place it at the camera's ground point."
	_new_town_button.pressed.connect(_show_new_town_dialog)
	_toolbar.add_child(_new_town_button)
	_add_facility_button = MenuButton.new()
	_add_facility_button.text = "Add Facility"
	_add_facility_button.icon = _get_town_icon()
	_add_facility_button.tooltip_text = "Add a facility to the selected town at the camera's ground point (ground-snapped at runtime)."
	var popup := _add_facility_button.get_popup()
	for index in range(FACILITY_CATALOG.size()):
		popup.add_item(str(FACILITY_CATALOG[index]["label"]), index)
	popup.id_pressed.connect(_on_add_facility_pressed)
	_toolbar.add_child(_add_facility_button)
	_remove_facility_button = Button.new()
	_remove_facility_button.text = "Remove Facility"
	_remove_facility_button.tooltip_text = "Remove the selected facility from its town."
	_remove_facility_button.pressed.connect(_on_remove_facility_pressed)
	_toolbar.add_child(_remove_facility_button)
	_refresh_toolbar()


func _refresh_toolbar() -> void:
	if _toolbar == null:
		return
	var town := _get_active_town()
	var zone := _edited_zone_root()
	_toolbar.visible = town != null or zone != null
	if town != null:
		_status_label.text = "Town: %s" % town.name
	elif zone != null:
		_status_label.text = "Zone: %s" % zone.name
	_new_town_button.disabled = zone == null
	_add_facility_button.disabled = town == null
	_remove_facility_button.disabled = _selected_facility() == null


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _get_town_icon() -> Texture2D:
	if _town_icon != null:
		return _town_icon
	var icon_bytes := FileAccess.get_file_as_bytes(TOWN_ICON_PATH)
	if icon_bytes.size() == 0:
		return null
	var image := Image.new()
	if image.load_svg_from_buffer(icon_bytes) != OK:
		return null
	_town_icon = ImageTexture.create_from_image(image)
	return _town_icon
