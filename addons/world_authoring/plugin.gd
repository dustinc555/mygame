@tool
extends EditorPlugin

## world_authoring plugin router.
## Each authoring concept (WorldBuilding today; Town, Bar, Jail next) is a
## tool context object that owns its own toolbar and input handling. The
## router mounts every context's toolbar in the spatial editor menu, resolves
## which context a selection belongs to, and forwards editor callbacks.
## The world nav bake row lives in the World bottom dock (world_dock.gd).

const BUILDING_TOOLS := preload("res://addons/world_authoring/building_tools.gd")
const TOWN_TOOLS := preload("res://addons/world_authoring/town_tools.gd")
const ZONE_TOOLS := preload("res://addons/world_authoring/zone_tools.gd")
const FACILITY_TOOLS := preload("res://addons/world_authoring/facility_tools.gd")
const FACTION_TOOLS := preload("res://addons/world_authoring/faction_tools.gd")
const WORLD_TOOLS := preload("res://addons/world_authoring/world_tools.gd")

var _contexts: Array = []
var _suppress_selection_refresh := false
## Scene roots (instance IDs) already folded once — manual expand state is
## never fought after the initial collapse.
var _folded_scene_roots := {}


func _enter_tree() -> void:
	set_process(true)
	set_process_input(true)
	set_process_shortcut_input(true)
	# Order matters for input routing: innermost concept first (a piece inside
	# a building inside a facility inside a town inside a zone resolves to the
	# building tools).
	_contexts = [BUILDING_TOOLS.new(self), FACILITY_TOOLS.new(self), TOWN_TOOLS.new(self), FACTION_TOOLS.new(self), ZONE_TOOLS.new(self), WORLD_TOOLS.new(self)]
	for context in _contexts:
		add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, context.toolbar())
	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)
	var selection := get_editor_interface().get_selection()
	if not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)
	call_deferred("_startup_refresh")


func _startup_refresh() -> void:
	_fold_scene_once(get_editor_interface().get_edited_scene_root())
	_refresh_contexts()


func _exit_tree() -> void:
	set_process(false)
	set_process_input(false)
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


func _handles(object: Object) -> bool:
	return _resolve_context_for_object(object) != null


func _edit(object: Object) -> void:
	if _suppress_selection_refresh:
		return
	var context = _resolve_context_for_object(object)
	if context != null:
		context.edit(object)


func _make_visible(_visible: bool) -> void:
	_refresh_contexts()


func _process(delta: float) -> void:
	for context in _contexts:
		context.process(delta)


## Pre-GUI interception: the 3D viewport applies mouse-wheel zoom without
## consulting AFTER_GUI_INPUT_STOP, so ghost placement claims the wheel here,
## before viewport navigation ever sees it. Only fires during an active
## placement session.
func _input(event: InputEvent) -> void:
	for context in _contexts:
		if context.has_method("handle_global_input") and context.handle_global_input(event):
			get_viewport().set_input_as_handled()
			return


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
	if _suppress_selection_refresh:
		return
	_refresh_contexts()


## Select a dock-owned subobject in the scene tree and 3D viewport without
## rebuilding every world-authoring context or forcing a redundant Inspector
## edit. The dock already owns the active editing context.
func select_node_without_context_refresh(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_suppress_selection_refresh = true
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(node)
	_finish_suppressed_selection.call_deferred()


func _finish_suppressed_selection() -> void:
	_suppress_selection_refresh = false


func _on_scene_changed(scene_root: Node) -> void:
	for context in _contexts:
		context.on_scene_changed(scene_root)
	_fold_scene_once(scene_root)
	_sync_docks()
	_sync_toolbars()


func _refresh_contexts() -> void:
	for context in _contexts:
		context.on_selection_changed()
	_sync_docks()
	_sync_toolbars()


## One toolbar at a time: only the innermost concept owning the current
## selection shows its controls. Zone root selected -> zone tools; a town ->
## town tools; a facility -> facility tools. Never stacked together.
func _sync_toolbars() -> void:
	var active := _resolve_selection_context()
	for context in _contexts:
		var bar: Control = context.toolbar()
		if bar != null:
			bar.visible = bar.visible and context == active


func _resolve_selection_context() -> RefCounted:
	for node in get_editor_interface().get_selection().get_selected_nodes():
		var context := _resolve_context_for_node(node)
		if context != null:
			return context
	var root := get_editor_interface().get_edited_scene_root()
	return _resolve_context_for_node(root) if root != null else null


## A concept's bottom dock exists only while one of its nodes is literally
## selected — the Facility tab for a selected facility node, the Town tab for
## a selected SettlementTown. Selection merely sitting somewhere inside the
## concept does not surface the dock; deselecting removes the tab entirely.
func _sync_docks() -> void:
	for context in _contexts:
		if not context.has_method("wants_dock"):
			continue
		var wanted: bool = context.wants_dock()
		if wanted and not context.dock_mounted:
			add_control_to_bottom_panel(context.dock_control(), context.dock_title())
			context.dock_mounted = true
			make_bottom_panel_item_visible(context.dock_control())
		elif not wanted and context.dock_mounted:
			remove_control_from_bottom_panel(context.dock_control())
			context.dock_mounted = false


## Scenes open collapsed: every branch folds so the tree shows only the top
## level until deliberately expanded. Runs once per scene root, so tab
## switches and manual expansion are left alone afterwards.
func _fold_scene_once(scene_root: Node) -> void:
	if scene_root == null:
		return
	var key := scene_root.get_instance_id()
	if _folded_scene_roots.has(key):
		return
	_folded_scene_roots[key] = true
	_fold_branch(scene_root)


func _fold_branch(node: Node) -> void:
	for child in node.get_children():
		if child.get_child_count() > 0:
			child.set_display_folded(true)
			_fold_branch(child)
