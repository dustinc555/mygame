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
const TOWN_SCRIPT := preload("res://features/settlements/bridge/settlement_town.gd")
const SETTLEMENT_DEFINITION_SCRIPT := preload("res://features/world_sim/resources/settlement_definition.gd")
const PLACEMENT_GHOST := preload("res://addons/world_authoring/placement_ghost.gd")
const ZONE_DOCK := preload("res://addons/world_authoring/zone_dock.gd")
const RESOURCE_AUTHORING := preload("res://addons/world_authoring/resource_authoring.gd")
const SCENE_THUMBNAIL := preload("res://addons/world_authoring/scene_thumbnail.gd")
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
var _dock: Control
var dock_mounted := false
var _resource_catalog: Array = []
var _placing_resource: Resource
var _resource_after_open: Resource
var _resource_previews := {}
var _preview_requests := {}
var _thumbnail_stage: SubViewport
var _definition_saves := {}
var _save_pending := false
var _content_refresh_pending := false
var _cached_zone: Node3D
var _cached_deposits: Array = []


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_ghost = PLACEMENT_GHOST.new(plugin)
	_build_toolbar()
	_dock = ZONE_DOCK.new()
	_dock.setup(self)
	if _plugin != null:
		_plugin.get_tree().node_added.connect(_on_content_node_changed)
		_plugin.get_tree().node_removed.connect(_on_content_node_changed)


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
	if _dock != null:
		_dock.set_zone(_active_zone())
		if _plugin != null:
			var selected := _plugin.get_editor_interface().get_selection().get_selected_nodes()
			if _ghost.is_active() and (selected.size() != 1 or selected[0] != _edited_zone_root()):
				_ghost.cancel()
			for node in selected:
				if RESOURCE_AUTHORING.is_deposit(node):
					_dock.select_resource_definition(node.get("deposit_definition") as Resource)


func on_scene_changed(scene_root: Node) -> void:
	_ghost.cancel()
	if not _pending_open_zone_path.is_empty() and scene_root != null \
			and scene_root.scene_file_path == _pending_open_zone_path:
		_pending_open_zone_path = ""
		if _resource_after_open != null:
			var definition := _resource_after_open
			_resource_after_open = null
			begin_resource_placement.call_deferred(definition)
		else:
			_show_new_town_dialog()
	_cached_zone = null
	_cached_deposits.clear()
	_refresh_toolbar()
	if _dock != null:
		_dock.set_zone(_active_zone())


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
	if is_instance_valid(_thumbnail_stage):
		_thumbnail_stage.free()
	_thumbnail_stage = null
	_flush_definition_saves()
	if _plugin != null:
		var tree := _plugin.get_tree()
		if tree.node_added.is_connected(_on_content_node_changed):
			tree.node_added.disconnect(_on_content_node_changed)
		if tree.node_removed.is_connected(_on_content_node_changed):
			tree.node_removed.disconnect(_on_content_node_changed)
	if is_instance_valid(_dock):
		if dock_mounted and _plugin != null:
			_plugin.remove_control_from_bottom_panel(_dock)
		_dock.free()
	_dock = null
	dock_mounted = false
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
	if _plugin == null:
		return null
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		var zone := _find_zone_ancestor(node)
		if zone != null:
			return zone
	return _edited_zone_root()


func _edited_zone_root() -> Node3D:
	if _plugin == null:
		return null
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
	var resources := Button.new()
	resources.name = "PlaceResourceShortcut"
	resources.text = "Place Resource"
	resources.tooltip_text = "Open this zone's resource catalog and shared replenishment settings."
	resources.pressed.connect(show_resources)
	_toolbar.add_child(resources)
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


## --- Zone workspace and independent resources -------------------------------

func wants_dock() -> bool:
	if _plugin == null:
		return false
	if _ghost.is_active():
		return _active_zone() != null
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		if _is_script_node(node, ZONE_SCRIPT):
			return true
		if RESOURCE_AUTHORING.is_deposit(node) and _find_zone_ancestor(node) != null:
			return true
	return false

func dock_control() -> Control:
	return _dock

func dock_title() -> String:
	return "Zone"

func show_resources() -> void:
	var zone := _active_zone()
	if zone == null or _dock == null:
		return
	_select_node(zone)
	_dock.set_zone(zone)
	_dock.show_resources()
	_plugin.call("_sync_docks")
	_plugin.make_bottom_panel_item_visible(_dock)

func get_resource_catalog() -> Array:
	if _resource_catalog.is_empty():
		_resource_catalog = RESOURCE_AUTHORING.load_catalog()
	return _resource_catalog

func get_zone_towns(zone: Node) -> Array:
	if not is_instance_valid(zone):
		return []
	var towns := zone.get_node_or_null("Towns")
	return towns.get_children() if towns != null else []

func get_zone_resources(zone: Node3D) -> Array:
	if not is_instance_valid(zone):
		return []
	if _cached_zone != zone:
		_cached_zone = zone
		_cached_deposits = RESOURCE_AUTHORING.collect_deposits(zone)
	return _cached_deposits.filter(func(node): return is_instance_valid(node) and node.owner != null)

func open_town_editor(town: Node) -> void:
	if is_instance_valid(town):
		_select_node(town)

func set_zone_property(zone: Node, property: String, value: Variant) -> void:
	if not is_instance_valid(zone) or _plugin == null or zone.get(property) == value:
		return
	var undo := _plugin.get_undo_redo()
	undo.create_action("Edit Zone %s" % property, UndoRedo.MERGE_DISABLE, zone)
	undo.add_do_property(zone, property, value)
	undo.add_undo_property(zone, property, zone.get(property))
	undo.add_do_method(_dock, "refresh")
	undo.add_undo_method(_dock, "refresh")
	undo.commit_action()

func begin_resource_placement(definition: Resource) -> void:
	var zone := _active_zone()
	if zone == null or definition == null or _plugin == null:
		return
	if not definition.call("validation_errors").is_empty():
		_set_status("Fix the resource settings before placing this deposit.")
		return
	if zone != _plugin.get_editor_interface().get_edited_scene_root():
		if zone.scene_file_path.is_empty():
			_set_status("Save and open this zone's own scene before placing resources.")
			return
		_resource_after_open = definition
		_pending_open_zone_path = zone.scene_file_path
		_plugin.get_editor_interface().open_scene_from_path(zone.scene_file_path)
		return
	_ghost.cancel()
	_placing_resource = definition
	_select_node(zone)
	_dock.set_zone(zone)
	_dock.show_resources()
	var scene := load(str(definition.get("scene_path"))) as PackedScene
	if not _ghost.begin_scene(scene, _on_resource_placement_committed, _on_resource_placement_cancelled):
		_on_resource_placement_cancelled()
		_set_status("Could not start resource placement.")
		return
	_dock.set_placement_active(true, str(definition.get("display_name")))
	_set_status("Placing %s — Esc or right-click finishes." % definition.get("display_name"))

func _on_resource_placement_committed(world_transform: Transform3D) -> void:
	var zone := _edited_zone_root()
	if zone == null or _placing_resource == null:
		_on_resource_placement_cancelled()
		return
	var node := RESOURCE_AUTHORING.place_resource(zone, zone, _placing_resource, world_transform, _plugin.get_undo_redo())
	if node == null:
		_set_status("Resource placement failed; nothing was added.")
		_on_resource_placement_cancelled()
		return
	_invalidate_content()
	# Keep the zone selected, so the browser and viewport input stay active.
	var scene := load(str(_placing_resource.get("scene_path"))) as PackedScene
	_ghost.begin_scene(scene, _on_resource_placement_committed, _on_resource_placement_cancelled)

func cancel_resource_placement() -> void:
	_ghost.cancel()

func _on_resource_placement_cancelled() -> void:
	_placing_resource = null
	if is_instance_valid(_dock):
		_dock.set_placement_active(false)
	_set_status("Resource placement finished.")

func set_resource_definition_property(definition: Resource, property: String, value: Variant) -> String:
	if _plugin == null or definition == null:
		return "No resource definition selected."
	if property not in ["refill_enabled", "refill_min_weeks", "refill_max_weeks", "min_stock", "max_stock"]:
		return "This control is not a shared deposit setting."
	if definition.get(property) == value:
		return ""
	var candidate := definition.duplicate()
	candidate.set(property, value)
	var errors = candidate.call("validation_errors")
	if not errors.is_empty():
		return "; ".join(errors)
	var undo := _plugin.get_undo_redo()
	undo.create_action("Edit %s %s" % [definition.get("display_name"), property], UndoRedo.MERGE_DISABLE, definition)
	undo.add_do_property(definition, property, value)
	undo.add_undo_property(definition, property, definition.get(property))
	undo.add_do_method(self, "_definition_changed", definition)
	undo.add_undo_method(self, "_definition_changed", definition)
	undo.commit_action()
	return ""

func _definition_changed(definition: Resource) -> void:
	_definition_saves[definition.resource_path] = definition
	if not _save_pending:
		_save_pending = true
		_flush_definition_saves.call_deferred()
	if is_instance_valid(_dock):
		_dock.refresh_resource_settings()

func _flush_definition_saves() -> void:
	_save_pending = false
	for path in _definition_saves:
		if not str(path).is_empty() and ResourceSaver.save(_definition_saves[path], path) != OK:
			_set_status("Could not save resource settings: %s" % path)
	_definition_saves.clear()

func inspect_resource_definition(definition: Resource) -> void:
	if _plugin != null and definition != null:
		_plugin.get_editor_interface().edit_resource(definition)

func inspect_resource_performance_settings() -> void:
	if _plugin != null:
		_plugin.get_editor_interface().edit_resource(load("res://features/world/resources/resource_deposit_settings.tres"))

func open_resource_scene(definition: Resource) -> void:
	if _plugin != null and definition != null:
		_ghost.cancel()
		_plugin.get_editor_interface().open_scene_from_path(str(definition.get("scene_path")))

func request_resource_preview(definition: Resource, callback: Callable) -> void:
	if _plugin == null or definition == null or not callback.is_valid():
		return
	var key := definition.resource_path
	if _resource_previews.has(key):
		callback.call(key, _resource_previews[key])
		return
	if _preview_requests.has(key):
		return
	_preview_requests[key] = true
	if not is_instance_valid(_thumbnail_stage):
		_thumbnail_stage = SCENE_THUMBNAIL.new()
		_plugin.add_child(_thumbnail_stage)
	_thumbnail_stage.request(str(definition.get("scene_path")), _resource_preview_ready.bind(key, callback))

func _resource_preview_ready(texture: Texture2D, key: String, callback: Callable) -> void:
	_preview_requests.erase(key)
	if texture == null:
		return
	_resource_previews[key] = texture
	if callback.is_valid():
		callback.call(key, texture)

func _on_content_node_changed(node: Node) -> void:
	if node is Node3D and (RESOURCE_AUTHORING.is_deposit(node) or _is_script_node(node, TOWN_SCRIPT)):
		_invalidate_content()

func _invalidate_content() -> void:
	_cached_zone = null
	_cached_deposits.clear()
	if not _content_refresh_pending:
		_content_refresh_pending = true
		_refresh_content.call_deferred()

func _refresh_content() -> void:
	_content_refresh_pending = false
	if is_instance_valid(_dock):
		_dock.refresh()

func apply_changes() -> void:
	_flush_definition_saves()
	if _plugin != null:
		var scene := _plugin.get_editor_interface().get_edited_scene_root()
		if scene != null:
			RESOURCE_AUTHORING.repair_duplicate_ids(scene, _plugin.get_undo_redo())
