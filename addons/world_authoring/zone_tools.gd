@tool
extends RefCounted

## Zone concept tool context for the world_authoring plugin. Claims Zone
## nodes wherever they are selected — including Zone instances inside a
## world scene — and owns town creation: "Add Town" asks for a name, then
## click-to-place ghosts the town origin on the terrain; commit writes the
## per-town scene + SettlementDefinition and instances the town under the
## zone's Towns root. When the selected zone is an instance (not the edited
## scene root), Add Town first opens the zone's own scene so the per-town
## scene stays the single source of truth.

const ZONE_ICON_PATH := "res://addons/world_authoring/icons/zone.svg"
const ZONE_SCRIPT := preload("res://features/world/projection/zone_root.gd")
const TOWN_TEMPLATE := preload("res://features/settlements/bridge/settlement_town.tscn")
const SETTLEMENT_DEFINITION_SCRIPT := preload("res://features/world_sim/resources/settlement_definition.gd")
const PLACEMENT_GHOST := preload("res://addons/world_authoring/placement_ghost.gd")
const SETTLEMENT_DEFINITIONS_DIR := "res://features/world_sim/resources/settlements"
const TOWN_GHOST_RADIUS := 24.0
const TOWN_GHOST_COLOR := Color(0.62, 1.0, 0.94, 0.4)

var _plugin: EditorPlugin
var _toolbar: HBoxContainer
var _status_label: Label
var _add_town_button: Button
var _new_town_dialog: ConfirmationDialog
var _town_name_edit: LineEdit
var _zone_icon: Texture2D
var _ghost
var _pending_town_name := ""
var _pending_open_zone_path := ""


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_ghost = PLACEMENT_GHOST.new(plugin)
	_build_toolbar()


func toolbar() -> Control:
	return _toolbar


func handles(object: Object) -> bool:
	if object is Node and _find_zone_ancestor(object as Node) != null:
		return true
	return _edited_zone_root() != null


func claims_node(node: Node) -> bool:
	return _is_script_node(node, ZONE_SCRIPT)


func edit(_object: Object) -> void:
	_refresh_toolbar()


func refresh() -> void:
	_refresh_toolbar()


func is_active() -> bool:
	return _ghost.is_active() or _active_zone() != null


func on_selection_changed() -> void:
	_refresh_toolbar()


func on_scene_changed(scene_root: Node) -> void:
	_ghost.cancel()
	if not _pending_open_zone_path.is_empty() and scene_root != null \
			and scene_root.scene_file_path == _pending_open_zone_path:
		_pending_open_zone_path = ""
		_show_new_town_dialog()
	_refresh_toolbar()


func process(_delta: float) -> void:
	pass


func shortcut_input(_event: InputEvent) -> bool:
	return false


## Pre-GUI wheel claim while placing (router calls this from _input).
func handle_global_input(event: InputEvent) -> bool:
	return _ghost.handle_global_input(event)


func forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	return _ghost.handle_3d_input(camera, event)


func teardown() -> void:
	_ghost.cancel()
	if _new_town_dialog != null and is_instance_valid(_new_town_dialog):
		_new_town_dialog.queue_free()
	_new_town_dialog = null
	if _toolbar != null:
		_toolbar.free()
		_toolbar = null
	_plugin = null


## --- Add Town ---------------------------------------------------------------


func _on_add_town_pressed() -> void:
	var zone := _active_zone()
	if zone == null:
		_set_status("Select a Zone to add a town.")
		return
	if zone != _plugin.get_editor_interface().get_edited_scene_root():
		# Town authoring edits the zone's own scene file; open it first and
		# resume the flow once it is the edited root.
		if zone.scene_file_path.is_empty():
			_set_status("Zone has no scene file; save it before adding towns.")
			return
		_pending_open_zone_path = zone.scene_file_path
		_plugin.get_editor_interface().open_scene_from_path(zone.scene_file_path)
		return
	_show_new_town_dialog()


func _show_new_town_dialog() -> void:
	if _new_town_dialog == null or not is_instance_valid(_new_town_dialog):
		_new_town_dialog = ConfirmationDialog.new()
		_new_town_dialog.title = "Add Town"
		_new_town_dialog.ok_button_text = "Place"
		var row := VBoxContainer.new()
		var hint := Label.new()
		hint.text = "Town name (id becomes snake_case). After confirming, click the terrain to place; R rotates, right-click cancels."
		row.add_child(hint)
		_town_name_edit = LineEdit.new()
		_town_name_edit.placeholder_text = "Rustwash Landing"
		row.add_child(_town_name_edit)
		_new_town_dialog.add_child(row)
		_new_town_dialog.register_text_enter(_town_name_edit)
		_new_town_dialog.confirmed.connect(_on_new_town_confirmed)
		_plugin.get_editor_interface().get_base_control().add_child(_new_town_dialog)
	_town_name_edit.text = ""
	_new_town_dialog.popup_centered(Vector2i(460, 0))
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
	if FileAccess.file_exists(_definition_path(settlement_id)):
		_set_status("Settlement '%s' already exists (definition)." % settlement_id)
		return
	if zone.get_node_or_null("Towns/%s" % display_name.to_pascal_case()) != null:
		_set_status("Town '%s' already exists in this zone." % display_name)
		return
	_pending_town_name = display_name
	# The editor forwards viewport input only while this plugin handles the
	# current selection — select the zone so the ghost actually receives input.
	_select_node(zone)
	if not _ghost.begin_marker(TOWN_GHOST_RADIUS, TOWN_GHOST_COLOR,
			_on_town_placement_committed, _on_town_placement_cancelled):
		_set_status("Could not start placement (no edited scene).")
		return
	_set_status("Placing %s: hold left-click, drag rotates, scroll = height, release places." % display_name)


func _on_town_placement_committed(world_transform: Transform3D) -> void:
	var display_name := _pending_town_name
	_pending_town_name = ""
	var zone := _edited_zone_root()
	if zone == null or display_name.is_empty():
		return
	var settlement_id := display_name.to_snake_case()
	var drop_position := world_transform.origin
	var definition := _save_settlement_definition(settlement_id, display_name, drop_position)
	if definition == null:
		_set_status("Failed to save settlement definition.")
		return
	_add_inline_town(zone, settlement_id, definition, drop_position)
	_set_status("Created %s in %s (save the zone to keep it)." % [display_name, zone.name])


func _on_town_placement_cancelled() -> void:
	_pending_town_name = ""
	_set_status("Town placement cancelled.")


func _definition_path(settlement_id: String) -> String:
	return "%s/%s.tres" % [SETTLEMENT_DEFINITIONS_DIR, settlement_id]


func _save_settlement_definition(settlement_id: String, display_name: String, world_position: Vector3) -> Resource:
	var definition: Resource = SETTLEMENT_DEFINITION_SCRIPT.new()
	definition.set("settlement_id", settlement_id)
	definition.set("display_name", display_name)
	definition.set("world_position", world_position)
	DirAccess.make_dir_recursive_absolute(SETTLEMENT_DEFINITIONS_DIR)
	var path := _definition_path(settlement_id)
	if ResourceSaver.save(definition, path) != OK:
		return null
	return load(path)


## Towns are plain child nodes of the zone (Dustin decision 2026-07-07):
## one file, one truth — the zone scene owns its towns outright, no per-town
## .tscn, no instance dance. The template expands into plain nodes at add
## time; the SettlementDefinition .tres stays the sim-truth resource.
func _add_inline_town(zone: Node3D, settlement_id: String, definition: Resource, drop_position: Vector3) -> void:
	var town := TOWN_TEMPLATE.instantiate() as Node3D
	town.name = settlement_id.to_pascal_case()
	town.scene_file_path = ""
	town.set("settlement_definition", definition)
	town.position = drop_position - zone.global_position
	var towns_root := zone.get_node_or_null("Towns") as Node3D
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Add Town")
	if towns_root == null:
		towns_root = SettlementTownsRoot.new()
		towns_root.name = "Towns"
		undo_redo.add_do_method(zone, "add_child", towns_root)
		undo_redo.add_do_method(towns_root, "set_owner", zone)
		undo_redo.add_undo_method(zone, "remove_child", towns_root)
		undo_redo.add_do_reference(towns_root)
	undo_redo.add_do_method(towns_root, "add_child", town)
	undo_redo.add_do_method(self, "_own_town_tree", town, zone)
	undo_redo.add_undo_method(towns_root, "remove_child", town)
	undo_redo.add_do_reference(town)
	undo_redo.commit_action()
	_select_node(town)


## Every node of the expanded town belongs to the zone scene so it saves with
## the zone; nested scene instances keep their internals. Everything folds
## in the scene tree so only what's being worked on stays visible.
func _own_town_tree(town: Node, zone: Node) -> void:
	town.owner = zone
	_own_children_recursive(town, zone)
	town.set_display_folded(true)


func _own_children_recursive(node: Node, zone: Node) -> void:
	# An instance root owns its internals. Claiming them makes the editor save
	# duplicate type+instance entries that load as phantom off-tree nodes.
	if not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		child.owner = zone
		if child.get_child_count() > 0:
			child.set_display_folded(true)
		if child.scene_file_path.is_empty():
			_own_children_recursive(child, zone)


## --- Context plumbing --------------------------------------------------------


func _active_zone() -> Node3D:
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		var zone := _find_zone_ancestor(node)
		if zone != null:
			return zone
	return _edited_zone_root()


func _edited_zone_root() -> Node3D:
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	return root as Node3D if root != null and _is_script_node(root, ZONE_SCRIPT) else null


func _find_zone_ancestor(node: Node) -> Node3D:
	var current := node
	while current != null:
		if _is_script_node(current, ZONE_SCRIPT):
			return current as Node3D
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


## --- Toolbar ------------------------------------------------------------------


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "ZoneToolbar"
	_toolbar.add_theme_constant_override("separation", 6)
	_status_label = Label.new()
	_status_label.text = "Zone: none"
	# Hard width cap: status messages must never stretch the spatial editor
	# menu row (that pushes the viewport past the screen edge). Full text
	# lives in the tooltip.
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.custom_minimum_size = Vector2(180, 0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_toolbar.add_child(_status_label)
	_add_town_button = Button.new()
	_add_town_button.text = "Add Town"
	_add_town_button.icon = _get_zone_icon()
	_add_town_button.tooltip_text = "Create a town as plain nodes in this zone: hold left-click on terrain to anchor, drag to rotate, scroll to raise/lower, release to place."
	_add_town_button.pressed.connect(_on_add_town_pressed)
	_toolbar.add_child(_add_town_button)
	_refresh_toolbar()


func _refresh_toolbar() -> void:
	if _toolbar == null:
		return
	var zone := _active_zone()
	_toolbar.visible = zone != null
	if zone != null:
		_status_label.text = "Zone: %s" % zone.name
	_add_town_button.disabled = zone == null


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
		_status_label.tooltip_text = message


func _get_zone_icon() -> Texture2D:
	if _zone_icon != null:
		return _zone_icon
	var icon_bytes := FileAccess.get_file_as_bytes(ZONE_ICON_PATH)
	if icon_bytes.size() == 0:
		return null
	var image := Image.new()
	if image.load_svg_from_buffer(icon_bytes) != OK:
		return null
	_zone_icon = ImageTexture.create_from_image(image)
	return _zone_icon
