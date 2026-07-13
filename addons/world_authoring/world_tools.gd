@tool
extends RefCounted

## World concept tool context for the world_authoring plugin. Activates when
## a WorldRoot is selected and surfaces the World dock — session spawn
## options (start time first; anything a fresh boot should honor lands
## here). Concept-agnostic world workflows like nav baking stay on their own
## toolbar tool; this context is the world's property editor.

const WORLD_ROOT_SCRIPT := preload("res://features/world/projection/world_root.gd")
const WORLD_DOCK := preload("res://addons/world_authoring/world_dock.gd")

var _plugin: EditorPlugin
var _toolbar: HBoxContainer
var _status_label: Label
var _dock: Control
var _active_world: Node
## Managed by the plugin router: the dock is mounted in the bottom panel only
## while a WorldRoot node is literally selected.
var dock_mounted := false


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_build_toolbar()
	_dock = WORLD_DOCK.new()
	_dock.setup(self)


func toolbar() -> Control:
	return _toolbar


func handles(object: Object) -> bool:
	return object is Node and _find_world_ancestor(object as Node) != null


func claims_node(node: Node) -> bool:
	return _is_script_node(node, WORLD_ROOT_SCRIPT)


func edit(object: Object) -> void:
	if object is Node:
		_active_world = _find_world_ancestor(object as Node)
	_refresh_ui()


func refresh() -> void:
	_refresh_from_selection()


func is_active() -> bool:
	return _active_world != null


func on_selection_changed() -> void:
	_refresh_from_selection()


func on_scene_changed(_scene_root: Node) -> void:
	_active_world = null
	_refresh_ui()


func process(_delta: float) -> void:
	pass


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
	_active_world = null
	_plugin = null


## --- Property writes ---------------------------------------------------------------


## Undo-aware write for WorldRoot exports; saving the world scene persists it.
func set_world_property(world: Node, property_name: String, value) -> void:
	if world == null or not is_instance_valid(world):
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Set World %s" % property_name.capitalize())
	undo_redo.add_do_property(world, property_name, value)
	undo_redo.add_undo_property(world, property_name, world.get(property_name))
	undo_redo.commit_action()
	if _dock != null and is_instance_valid(_dock):
		_dock.refresh()


func set_world_start_time(world: Node, hour: int, minute: int) -> void:
	if world == null or not is_instance_valid(world):
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Set World Start Time")
	undo_redo.add_do_property(world, "start_hour", hour)
	undo_redo.add_undo_property(world, "start_hour", world.get("start_hour"))
	undo_redo.add_do_property(world, "start_minute", minute)
	undo_redo.add_undo_property(world, "start_minute", world.get("start_minute"))
	undo_redo.commit_action()
	if _dock != null and is_instance_valid(_dock):
		_dock.refresh()


## --- Context plumbing ---------------------------------------------------------------


func _refresh_from_selection() -> void:
	_active_world = null
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		_active_world = _find_world_ancestor(node)
		if _active_world != null:
			break
	_refresh_ui()


func _find_world_ancestor(node: Node) -> Node:
	var current := node
	while current != null:
		if _is_script_node(current, WORLD_ROOT_SCRIPT):
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


## --- Toolbar / dock -------------------------------------------------------------------


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "WorldToolbar"
	_status_label = Label.new()
	_status_label.text = "World: none"
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.custom_minimum_size = Vector2(160, 0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_toolbar.add_child(_status_label)
	_toolbar.visible = false


func _refresh_ui() -> void:
	if _toolbar != null:
		_toolbar.visible = _active_world != null
		if _active_world != null:
			_status_label.text = "World: %s" % str(_active_world.call("get_world_id"))
	if _dock != null and is_instance_valid(_dock):
		_dock.set_world(_active_world)


## Dock mounting is managed by the plugin router: the World tab exists only
## while a WorldRoot node itself is selected.
func wants_dock() -> bool:
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		if claims_node(node):
			return true
	return false


func dock_control() -> Control:
	return _dock


func dock_title() -> String:
	return "World"
