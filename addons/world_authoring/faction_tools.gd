@tool
extends RefCounted

## Faction concept tool context for the world_authoring plugin — its own
## vertical slice beside the building/town/zone editors. Activates when the
## Factions root or a Faction child is selected: the root surfaces the
## roster dock (every authored faction + New Faction), a child surfaces that
## faction's editor. Faction truth is the FactionDefinition .tres files
## under features/factions/resources/factions; the nodes are the editor
## affordance and the runtime registration point.

const FACTION_ICON_PATH := "res://addons/world_authoring/icons/faction.svg"
const FACTIONS_DIR := "res://features/factions/resources/factions"
const FACTIONS_SCRIPT := preload("res://features/factions/bridge/factions.gd")
const FACTION_SCRIPT := preload("res://features/factions/bridge/faction.gd")
const FACTION_DEFINITION_SCRIPT := preload("res://features/factions/resources/faction_definition.gd")
const FACTION_DOCK := preload("res://addons/world_authoring/faction_dock.gd")

## Scene-dock emblem repaint cadence (the dock rebuilds its Tree on scene
## edits, wiping custom icons, so they are reapplied on a slow tick).
const EMBLEM_REFRESH_INTERVAL := 0.5

var _plugin: EditorPlugin
var _toolbar: HBoxContainer
var _status_label: Label
var _new_faction_button: Button
var _dock: Control
var _active_root: Node
var _active_faction: Node
var _emblem_refresh_elapsed := 0.0
var _scene_dock_tree: Tree
## Managed by the plugin router: the dock is mounted in the bottom panel only
## while a Factions/Faction node is literally selected.
var dock_mounted := false


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_build_toolbar()
	_dock = FACTION_DOCK.new()
	_dock.setup(self)


func toolbar() -> Control:
	return _toolbar


func handles(object: Object) -> bool:
	return object is Node and _find_context_node(object as Node) != null


func claims_node(node: Node) -> bool:
	return _is_script_node(node, FACTIONS_SCRIPT) or _is_script_node(node, FACTION_SCRIPT)


func edit(object: Object) -> void:
	if object is Node:
		_resolve_context(object as Node)
	_refresh_ui()


func refresh() -> void:
	_refresh_from_selection()


func is_active() -> bool:
	return _active_root != null or _active_faction != null


func on_selection_changed() -> void:
	_refresh_from_selection()


func on_scene_changed(_scene_root: Node) -> void:
	_active_root = null
	_active_faction = null
	_refresh_ui()


func process(delta: float) -> void:
	_emblem_refresh_elapsed += delta
	if _emblem_refresh_elapsed < EMBLEM_REFRESH_INTERVAL:
		return
	_emblem_refresh_elapsed = 0.0
	_paint_scene_tree_emblems()


func shortcut_input(_event: InputEvent) -> bool:
	return false


func forward_3d_gui_input(_camera: Camera3D, _event: InputEvent) -> int:
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func teardown() -> void:
	if _dock != null and is_instance_valid(_dock):
		if dock_mounted:
			_plugin.remove_control_from_bottom_panel(_dock)
		_dock.free()
	dock_mounted = false
	_dock = null
	if _toolbar != null:
		_toolbar.free()
		_toolbar = null
	_active_root = null
	_active_faction = null
	_plugin = null


## --- New faction ----------------------------------------------------------------


## Creates the FactionDefinition .tres on disk, then adds the Faction node
## under the root (node add is undoable; the file, like every dock edit,
## lives on disk and is not).
func create_faction(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
	if owner_root == null:
		return
	var slug := _unique_faction_slug()
	var definition: Resource = FACTION_DEFINITION_SCRIPT.new()
	definition.set("faction_id", slug.to_pascal_case())
	definition.set("display_name", slug.capitalize())
	var path := "%s/%s.tres" % [FACTIONS_DIR, slug]
	if ResourceSaver.save(definition, path) != OK:
		_set_status("Failed to save %s." % path)
		return
	definition.take_over_path(path)
	var node := Node.new()
	node.name = slug.to_pascal_case()
	node.set_script(FACTION_SCRIPT)
	node.set("definition", definition)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("New Faction")
	undo_redo.add_do_method(root, "add_child", node)
	undo_redo.add_do_method(node, "set_owner", owner_root)
	undo_redo.add_undo_method(root, "remove_child", node)
	undo_redo.add_do_reference(node)
	undo_redo.commit_action()
	EditorInterface.get_resource_filesystem().scan()
	_select_node(node)
	_set_status("Created %s (%s)." % [node.name, path.get_file()])


func _unique_faction_slug() -> String:
	var base := "new_faction"
	var slug := base
	var index := 2
	while ResourceLoader.exists("%s/%s.tres" % [FACTIONS_DIR, slug]):
		slug = "%s_%d" % [base, index]
		index += 1
	return slug


## --- Scene-dock emblems ------------------------------------------------------------


## Each Faction node shows its faction's emblem in the Scene dock instead of
## the generic flag (the flag stays as the fallback for factions without an
## icon). Godot only supports per-script icons natively, so the plugin
## repaints the dock's Tree items directly; the dock rebuilds that Tree on
## scene edits, which reverts icons, so this reapplies on a slow tick and
## only while the edited scene actually contains a Factions root.
func _paint_scene_tree_emblems() -> void:
	var scene_root := _plugin.get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		return
	var factions_root := _find_factions_root(scene_root)
	if factions_root == null:
		return
	var emblems := {}
	for faction in factions_root.get_children():
		if not _is_script_node(faction, FACTION_SCRIPT):
			continue
		var definition: Resource = faction.get("definition") as Resource
		var emblem := definition.get("icon") as Texture2D if definition != null else null
		if emblem != null:
			emblems[str(faction.get_path())] = emblem
	if emblems.is_empty():
		return
	var tree := _get_scene_dock_tree()
	if tree == null or tree.get_root() == null:
		return
	_paint_tree_item_emblems(tree.get_root(), emblems)


func _find_factions_root(scene_root: Node) -> Node:
	if _is_script_node(scene_root, FACTIONS_SCRIPT):
		return scene_root
	for child in scene_root.get_children():
		if _is_script_node(child, FACTIONS_SCRIPT):
			return child
	return null


## The Scene dock's Tree stores each row's node path in metadata(0); match
## those against the Faction node paths and swap the row icon.
func _paint_tree_item_emblems(item: TreeItem, emblems: Dictionary) -> void:
	var metadata = item.get_metadata(0)
	if metadata != null and emblems.has(str(metadata)):
		var emblem: Texture2D = emblems[str(metadata)]
		if item.get_icon(0) != emblem:
			item.set_icon(0, emblem)
			item.set_icon_max_width(0, 16)
	var child := item.get_first_child()
	while child != null:
		_paint_tree_item_emblems(child, emblems)
		child = child.get_next()


func _get_scene_dock_tree() -> Tree:
	if _scene_dock_tree != null and is_instance_valid(_scene_dock_tree):
		return _scene_dock_tree
	var editors := _plugin.get_editor_interface().get_base_control().find_children("*", "SceneTreeEditor", true, false)
	if editors.is_empty():
		return null
	var trees := (editors[0] as Node).find_children("*", "Tree", true, false)
	if trees.is_empty():
		return null
	_scene_dock_tree = trees[0] as Tree
	return _scene_dock_tree


## --- Context plumbing -------------------------------------------------------------


func _refresh_from_selection() -> void:
	_active_root = null
	_active_faction = null
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		if _resolve_context(node):
			break
	_refresh_ui()


func _resolve_context(node: Node) -> bool:
	var context := _find_context_node(node)
	if context == null:
		return false
	if _is_script_node(context, FACTION_SCRIPT):
		_active_faction = context
		_active_root = context.get_parent() if _is_script_node(context.get_parent(), FACTIONS_SCRIPT) else null
	else:
		_active_root = context
		_active_faction = null
	return true


func _find_context_node(node: Node) -> Node:
	var current := node
	while current != null:
		if claims_node(current):
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


## --- Toolbar / dock ---------------------------------------------------------------


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "FactionToolbar"
	_toolbar.add_theme_constant_override("separation", 6)
	_status_label = Label.new()
	_status_label.text = "Factions"
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.custom_minimum_size = Vector2(180, 0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_toolbar.add_child(_status_label)
	_new_faction_button = Button.new()
	_new_faction_button.text = "New Faction"
	_new_faction_button.tooltip_text = "Create a new FactionDefinition .tres on disk and its Faction node under the Factions root."
	_new_faction_button.pressed.connect(func(): create_faction(_active_root))
	_toolbar.add_child(_new_faction_button)
	_toolbar.visible = false


func _refresh_ui() -> void:
	if _toolbar != null:
		_toolbar.visible = is_active()
		if _active_faction != null:
			_status_label.text = "Faction: %s" % _active_faction.name
		elif _active_root != null:
			_status_label.text = "Factions: %d authored" % _active_root.get_child_count()
		_new_faction_button.disabled = _active_root == null
	if _dock != null and is_instance_valid(_dock):
		_dock.set_context(_active_root, _active_faction)


## Dock mounting is managed by the plugin router: the Factions tab exists only
## while the Factions root or a Faction node itself is selected.
func wants_dock() -> bool:
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		if claims_node(node):
			return true
	return false


func dock_control() -> Control:
	return _dock


func dock_title() -> String:
	return "Factions"


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
		_status_label.tooltip_text = message
