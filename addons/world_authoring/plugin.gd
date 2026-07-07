@tool
extends EditorPlugin

## world_authoring plugin router.
## Each authoring concept (WorldBuilding today; Town, Bar, Jail next) is a
## tool context object that owns its own toolbar and input handling. The
## router mounts every context's toolbar in the spatial editor menu, resolves
## which context a selection belongs to, and forwards editor callbacks.
## Concept-agnostic tools (world nav bake) stay mounted directly.

const WORLD_NAV_BAKE_TOOL := preload("res://addons/world_authoring/world_nav_bake_tool.gd")
const BUILDING_TOOLS := preload("res://addons/world_authoring/building_tools.gd")
const TOWN_TOOLS := preload("res://addons/world_authoring/town_tools.gd")
const ZONE_TOOLS := preload("res://addons/world_authoring/zone_tools.gd")

var _contexts: Array = []
var _world_nav_bake_tool: Control


func _enter_tree() -> void:
	set_process(true)
	set_process_shortcut_input(true)
	# Order matters for input routing: innermost concept first (a piece inside
	# a building inside a town inside a zone resolves to the building tools).
	_contexts = [BUILDING_TOOLS.new(self), TOWN_TOOLS.new(self), ZONE_TOOLS.new(self)]
	for context in _contexts:
		add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, context.toolbar())
	_world_nav_bake_tool = WORLD_NAV_BAKE_TOOL.new()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _world_nav_bake_tool)
	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)
	var selection := get_editor_interface().get_selection()
	if not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)
	call_deferred("_refresh_contexts")


func _exit_tree() -> void:
	set_process(false)
	set_process_shortcut_input(false)
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	var selection := get_editor_interface().get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	for context in _contexts:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, context.toolbar())
		context.teardown()
	_contexts.clear()
	if _world_nav_bake_tool != null:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _world_nav_bake_tool)
		_world_nav_bake_tool.free()
		_world_nav_bake_tool = null


func _handles(object: Object) -> bool:
	return _resolve_context_for_object(object) != null


func _edit(object: Object) -> void:
	var context = _resolve_context_for_object(object)
	if context != null:
		context.edit(object)


func _make_visible(_visible: bool) -> void:
	_refresh_contexts()


func _process(delta: float) -> void:
	for context in _contexts:
		context.process(delta)


func _shortcut_input(event: InputEvent) -> void:
	for context in _contexts:
		if context.shortcut_input(event):
			get_viewport().set_input_as_handled()
			return


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	for context in _contexts:
		if context.is_active():
			return context.forward_3d_gui_input(camera, event)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _resolve_context_for_object(object: Object) -> RefCounted:
	if object is Node:
		return _resolve_context_for_node(object as Node)
	for context in _contexts:
		if context.handles(object):
			return context
	return null


func _resolve_context_for_node(node: Node) -> RefCounted:
	# Innermost concept wins: a node can sit under several concept roots at
	# once (piece inside a WorldBuilding inside a SettlementTown inside a
	# Zone); the nearest ancestor's tools activate. Falls back to handles()
	# so opening a concept scene root directly still activates its context.
	var current := node
	while current != null:
		for context in _contexts:
			if context.claims_node(current):
				return context
		current = current.get_parent()
	for context in _contexts:
		if context.handles(node):
			return context
	return null


func _on_selection_changed() -> void:
	_refresh_contexts()


func _on_scene_changed(scene_root: Node) -> void:
	for context in _contexts:
		context.on_scene_changed(scene_root)


func _refresh_contexts() -> void:
	for context in _contexts:
		context.on_selection_changed()
