@tool
extends RefCounted

## SettlementTown concept tool context for the world_authoring plugin.
## Activates when a SettlementTown is selected. Towns are simple: a root
## plus Facilities. The placement catalog is scanned from FacilityDefinition
## resources (never hardcoded); facilities and spawn markers click-place
## through a terrain ghost; town properties are edited in the bottom-panel
## Town dock, which writes the SettlementDefinition .tres (single sim-truth
## home). When the town is an instance inside the open zone, add/remove
## edits the town's own scene file and refreshes the instance, so per-town
## scenes stay the single source of truth.
##
## By design towns stay minimal (root + Facilities): no authored
## ActivityPoints/GuardPosts roots — guard posts come from the definition's
## guard_post_count, activity points live inside facility scenes. The only
## authored markers are the RoadSpawn / DefenseSpawn nodes.

const TOWN_ICON_PATH := "res://addons/world_authoring/icons/town.svg"
const FACILITIES_DIR := "res://features/settlements/resources/facilities"
const SETTLEMENT_TOWN_SCRIPT := preload("res://features/settlements/bridge/settlement_town.gd")
const PLACEMENT_GHOST := preload("res://addons/world_authoring/placement_ghost.gd")
const TOWN_DOCK := preload("res://addons/world_authoring/town_dock.gd")
const INSTANCE_UNPACK := preload("res://addons/world_authoring/instance_unpack.gd")
const MARKER_GHOST_RADIUS := 1.2
const MARKER_GHOST_COLORS := {
	"RoadSpawn": Color(0.95, 0.8, 0.2, 0.5),
	"DefenseSpawn": Color(0.9, 0.3, 0.2, 0.5),
}

var _plugin: EditorPlugin
var _toolbar: HBoxContainer
var _status_label: Label
var _add_facility_button: MenuButton
var _edit_in_zone_button: Button
var _snap_terrain_button: Button
var _active_town: Node
var _town_icon: Texture2D
var _ghost
var _dock: Control
var _facility_catalog: Array = []
var _pending_facility: Resource
var _unpacker
## Managed by the plugin router: the dock is mounted in the bottom panel only
## while a SettlementTown node is literally selected.
var dock_mounted := false


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_ghost = PLACEMENT_GHOST.new(plugin)
	_unpacker = INSTANCE_UNPACK.new()
	_build_toolbar()
	_dock = TOWN_DOCK.new()
	_dock.setup(self)


func toolbar() -> Control:
	return _toolbar


func handles(object: Object) -> bool:
	if object is Node and _find_town_ancestor(object as Node) != null:
		return true
	return _find_town_from_edited_scene_root() != null


func claims_node(node: Node) -> bool:
	return _is_script_node(node, SETTLEMENT_TOWN_SCRIPT)


func edit(object: Object) -> void:
	if object is Node:
		_active_town = _find_town_ancestor(object as Node)
	if _active_town == null:
		_active_town = _find_town_from_edited_scene_root()
	_refresh_context_ui()


func refresh() -> void:
	_refresh_active_town_context()


func is_active() -> bool:
	return _ghost.is_active() or _get_active_town() != null


func on_selection_changed() -> void:
	_refresh_active_town_context()


func on_scene_changed(_scene_root: Node) -> void:
	_ghost.cancel()
	_refresh_active_town_context()


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
	if _dock != null and is_instance_valid(_dock):
		if dock_mounted:
			_plugin.remove_control_from_bottom_panel(_dock)
		_dock.free()
	dock_mounted = false
	_dock = null
	if _toolbar != null:
		_toolbar.free()
		_toolbar = null
	_active_town = null
	_plugin = null


## --- Facility catalog (scanned, never hardcoded) ----------------------------


func get_facility_catalog() -> Array:
	if _facility_catalog.is_empty():
		_facility_catalog = _scan_facility_catalog()
	return _facility_catalog


func rescan_facility_catalog() -> Array:
	_facility_catalog = _scan_facility_catalog()
	return _facility_catalog


func _scan_facility_catalog() -> Array:
	var catalog: Array = []
	var dir := DirAccess.open(FACILITIES_DIR)
	if dir == null:
		return catalog
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension() == "tres":
			var definition := load("%s/%s" % [FACILITIES_DIR, file_name]) as FacilityDefinition
			if definition != null and definition.catalog_enabled and not definition.scene_path.is_empty():
				catalog.append(definition)
		file_name = dir.get_next()
	dir.list_dir_end()
	catalog.sort_custom(func(a, b): return a.get_display_name() < b.get_display_name())
	return catalog


func find_catalog_entry_for_scene(scene_path: String) -> FacilityDefinition:
	for entry in get_facility_catalog():
		if entry.scene_path == scene_path:
			return entry
	return null


## --- Facility placement (ghost) ---------------------------------------------


func begin_facility_placement(definition: FacilityDefinition) -> void:
	var town := _get_active_town() as Node3D
	if town == null or definition == null:
		return
	var facility_scene := load(definition.scene_path) as PackedScene
	if facility_scene == null:
		_set_status("Failed to load %s." % definition.scene_path)
		return
	_pending_facility = definition
	# Keep the town selected so the editor keeps forwarding viewport input to
	# this plugin while the ghost is live.
	_select_node(town)
	if not _ghost.begin_scene(facility_scene, _on_facility_placement_committed, _on_placement_cancelled):
		_set_status("Could not start placement (no edited scene).")
		return
	_set_status("Placing %s: hold left-click, drag rotates, scroll = height, release places." % definition.get_display_name())


func _on_facility_placement_committed(world_transform: Transform3D) -> void:
	var definition := _pending_facility as FacilityDefinition
	_pending_facility = null
	var town := _get_active_town() as Node3D
	if town == null or definition == null:
		return
	var local_transform := town.global_transform.affine_inverse() * world_transform
	if _can_edit_town_live(town):
		_add_facility_live(town, definition, local_transform)
	else:
		if town.scene_file_path.is_empty():
			_set_status("Town has no scene file; open its scene to edit.")
			return
		if not add_facility_to_town_scene(town.scene_file_path, definition, local_transform):
			_set_status("Failed to add %s." % definition.get_display_name())
			return
		var fresh := _refresh_town_instance(town)
		_set_status("Added %s to %s." % [definition.get_display_name(), fresh.name if fresh != null else "town"])
	_refresh_dock()


func _on_placement_cancelled() -> void:
	_pending_facility = null
	_set_status("Placement cancelled.")


## --- Spawn marker placement --------------------------------------------------


## marker_name is "RoadSpawn" or "DefenseSpawn"; the ghost click creates or
## moves the named marker at the town root and keeps the anchor's exported
## spawn path pointing at it.
func begin_spawn_marker_placement(marker_name: String) -> void:
	var town := _get_active_town() as Node3D
	if town == null or not MARKER_GHOST_COLORS.has(marker_name):
		return
	var color: Color = MARKER_GHOST_COLORS[marker_name]
	_select_node(town)
	var committed := func(world_transform: Transform3D) -> void:
		_place_spawn_marker(marker_name, world_transform)
	if not _ghost.begin_marker(MARKER_GHOST_RADIUS, color, committed, _on_placement_cancelled):
		_set_status("Could not start placement (no edited scene).")
		return
	_set_status("Click terrain to place %s." % marker_name)


func _place_spawn_marker(marker_name: String, world_transform: Transform3D) -> void:
	var town := _get_active_town() as Node3D
	if town == null:
		return
	var local_position := town.global_transform.affine_inverse() * world_transform.origin
	if _can_edit_town_live(town):
		var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
		var marker := town.get_node_or_null(marker_name) as Node3D
		var undo_redo := _plugin.get_undo_redo()
		undo_redo.create_action("Place %s" % marker_name)
		if marker == null:
			marker = Node3D.new()
			marker.name = marker_name
			undo_redo.add_do_method(town, "add_child", marker)
			undo_redo.add_do_method(marker, "set_owner", owner_root)
			undo_redo.add_do_property(marker, "position", local_position)
			undo_redo.add_do_property(town, _spawn_path_property(marker_name), NodePath(marker_name))
			undo_redo.add_undo_method(town, "remove_child", marker)
			undo_redo.add_do_reference(marker)
		else:
			undo_redo.add_do_property(marker, "position", local_position)
			undo_redo.add_undo_property(marker, "position", marker.position)
		undo_redo.commit_action()
	else:
		if town.scene_file_path.is_empty():
			_set_status("Town has no scene file; open its scene to edit.")
			return
		if not set_spawn_marker_in_town_scene(town.scene_file_path, marker_name, local_position):
			_set_status("Failed to place %s." % marker_name)
			return
		_refresh_town_instance(town)
	_set_status("Placed %s." % marker_name)
	_refresh_dock()


static func _spawn_path_property(marker_name: String) -> String:
	return "raid_spawn_path" if marker_name == "RoadSpawn" else "defense_spawn_path"


## --- Scene file surgery (single source of truth for instanced towns) ---------


## Adds a facility scene as a direct child of the town root, editing the
## town's own .tscn. Pure file surgery: usable from the editor context and
## from headless validation.
static func add_facility_to_town_scene(town_scene_path: String, definition: FacilityDefinition, local_transform: Transform3D) -> bool:
	var town_scene := ResourceLoader.load(town_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var facility_scene := load(definition.scene_path) as PackedScene if definition != null else null
	if town_scene == null or facility_scene == null:
		return false
	var town := town_scene.instantiate()
	var facility := facility_scene.instantiate() as Node3D
	if facility == null:
		town.free()
		return false
	_apply_facility_identity(facility, town, definition)
	town.add_child(facility)
	facility.owner = town
	facility.transform = local_transform
	var packed := PackedScene.new()
	var saved := packed.pack(town) == OK and ResourceSaver.save(packed, town_scene_path) == OK
	town.free()
	return saved


static func remove_facility_from_town_scene(town_scene_path: String, facility_name: String) -> bool:
	var town_scene := ResourceLoader.load(town_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if town_scene == null:
		return false
	var town := town_scene.instantiate()
	var facility := town.get_node_or_null(NodePath(facility_name))
	if facility == null:
		# Legacy towns still group facilities under a "Facilities" container.
		facility = town.get_node_or_null("Facilities/%s" % facility_name)
	if facility == null:
		town.free()
		return false
	facility.get_parent().remove_child(facility)
	facility.free()
	var packed := PackedScene.new()
	var saved := packed.pack(town) == OK and ResourceSaver.save(packed, town_scene_path) == OK
	town.free()
	return saved


static func set_spawn_marker_in_town_scene(town_scene_path: String, marker_name: String, local_position: Vector3) -> bool:
	var town_scene := ResourceLoader.load(town_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if town_scene == null:
		return false
	var town := town_scene.instantiate()
	var marker := town.get_node_or_null(marker_name) as Node3D
	if marker == null:
		marker = Node3D.new()
		marker.name = marker_name
		town.add_child(marker)
		marker.owner = town
	marker.position = local_position
	town.set(_spawn_path_property(marker_name), NodePath(marker_name))
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


static func facility_identity_for(parent: Node, settlement_id: String, definition_id: String) -> Dictionary:
	var clean_id := definition_id.strip_edges().to_snake_case()
	var base_name := clean_id.to_pascal_case()
	var node_name := _unique_facility_name(parent, base_name)
	var suffix := node_name.trim_prefix(base_name).to_lower()
	var local_id := "%s%s" % [clean_id, suffix]
	var facility_id := "%s.%s" % [settlement_id, local_id] if not settlement_id.is_empty() else local_id
	return {
		"node_name": node_name,
		"facility_id": facility_id,
		"building_id": "%s.building" % facility_id,
	}


static func _apply_facility_identity(facility: Node, town: Node, definition: FacilityDefinition) -> void:
	var settlement_id := str(town.call("get_settlement_id")) if town.has_method("get_settlement_id") else ""
	var identity := facility_identity_for(town, settlement_id, definition.get_id())
	facility.name = identity["node_name"]
	var facility_id := str(identity["facility_id"])
	facility.set("facility_id", facility_id)
	if "building_id" in facility:
		facility.set("building_id", identity["building_id"])
	if "staff_role_counts" in facility:
		facility.set("staff_role_counts", definition.staff_role_counts.duplicate(true))
	var owner_faction_id := str(facility.get("owner_faction_id")).strip_edges()
	if owner_faction_id.is_empty() and town.has_method("get_faction_id"):
		owner_faction_id = str(town.call("get_faction_id"))
	_stamp_building_ids_recursive(facility, settlement_id, facility_id, str(facility.get("facility_type")), owner_faction_id, int(facility.get("housing_capacity")))


static func _stamp_building_ids_recursive(node: Node, settlement_id: String, facility_id: String, facility_type: String, owner_faction_id: String, housing_capacity: int) -> void:
	if node is WorldBuilding:
		var building := node as WorldBuilding
		building.building_id = "%s.building" % facility_id
		building.settlement_id = settlement_id
		building.facility_id = facility_id
		building.building_type = facility_type
		building.owner_faction_id = owner_faction_id
		building.housing_capacity = housing_capacity
		return
	for child in node.get_children():
		_stamp_building_ids_recursive(child, settlement_id, facility_id, facility_type, owner_faction_id, housing_capacity)


## --- Facility add/remove entry points ----------------------------------------


func _on_add_facility_pressed(item_index: int) -> void:
	var catalog := get_facility_catalog()
	if item_index < 0 or item_index >= catalog.size():
		return
	begin_facility_placement(catalog[item_index])


## Live add: works when the town scene is open directly AND when the town is
## an editable instance inside the open zone — the owner is always the edited
## scene root (the town itself in the first case, the zone in the second,
## where the addition persists as an instance override until Save Town).
func _add_facility_live(town: Node3D, definition: FacilityDefinition, local_transform: Transform3D) -> void:
	var facility_scene := load(definition.scene_path) as PackedScene
	if facility_scene == null:
		return
	var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Add Facility")
	# Facilities are direct town children — no container ceremony.
	var facility := facility_scene.instantiate() as Node3D
	facility.transform = local_transform
	_apply_facility_identity(facility, town, definition)
	# Same 2026-07-07 decision as inline towns: the facility template expands
	# into plain nodes owned by the edited scene, so its children (furniture,
	# service points) are freely editable. Nested instances (the shell,
	# furniture pieces) stay intact.
	facility.scene_file_path = ""
	undo_redo.add_do_method(town, "add_child", facility)
	undo_redo.add_do_method(self, "_own_facility_tree", facility, owner_root)
	undo_redo.add_undo_method(town, "remove_child", facility)
	undo_redo.add_do_reference(facility)
	undo_redo.commit_action()
	_select_node(facility)
	_set_status("Added %s." % definition.get_display_name())


func _own_facility_tree(facility: Node, owner_root: Node) -> void:
	facility.owner = owner_root
	_own_facility_children(facility, owner_root)
	facility.set_display_folded(true)


func _own_facility_children(node: Node, owner_root: Node) -> void:
	# An instance root owns its internals. Claiming them makes the editor save
	# duplicate type+instance entries that load as phantom off-tree nodes.
	if not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		child.owner = owner_root
		if child.get_child_count() > 0:
			child.set_display_folded(true)
		if child.scene_file_path.is_empty():
			_own_facility_children(child, owner_root)


func get_town_facility_nodes(town: Node) -> Array:
	var result: Array = []
	if town == null:
		return result
	for child in town.get_children():
		if _is_facility_node(child):
			result.append(child)
	var legacy := town.get_node_or_null("Facilities")
	if legacy != null:
		for child in legacy.get_children():
			if child is Node3D:
				result.append(child)
	return result


func _is_facility_node(node: Node) -> bool:
	return node is SettlementFacilityInstance


func _town_is_edited_scene_root(town: Node) -> bool:
	return town == _plugin.get_editor_interface().get_edited_scene_root()


## An instanced town whose children are unlocked in the open scene (zone) —
## the primary authoring mode: terrain visible, facilities gizmo-editable,
## edits stored as instance overrides until Save Town writes them back.
func _town_is_editable_instance(town: Node) -> bool:
	if town == null or _town_is_edited_scene_root(town) or town.scene_file_path.is_empty():
		return false
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	return root != null and root.is_editable_instance(town)


## Inline towns (plain nodes in the zone — the primary model since
## 2026-07-07) are always live-editable; instanced towns need to be the
## edited root or an unlocked (editable-children) instance.
func _town_is_inline(town: Node) -> bool:
	if town == null or not town.scene_file_path.is_empty():
		return false
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	return root != null and root.is_ancestor_of(town)


func _can_edit_town_live(town: Node) -> bool:
	return _town_is_edited_scene_root(town) or _town_is_editable_instance(town) or _town_is_inline(town)


## Unpack an instanced (legacy) town into plain zone-owned nodes — the
## inline model: the zone scene becomes the single truth for this town.
## Facility instances inside keep their own scene links until unpacked
## themselves from the Facility dock. Undoable.
func make_town_editable(town: Node) -> void:
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	if town == null or root == null or _town_is_edited_scene_root(town):
		return
	_unpacker.unpack(town, root, _plugin.get_undo_redo())
	# The unpack reattaches the node, which drops the editor selection.
	_select_node(town)
	_refresh_context_ui()
	_set_status("%s is now plain nodes owned by this zone (save the zone to keep it)." % town.name)


## Conform the town's facilities and markers to the current terrain height —
## the editor-side twin of the runtime ground snap, for use while sculpting
## terrain around a placed town. Editor terrain has no physics, so heights
## come from Terrain3D data directly.
func snap_town_to_terrain(town: Node3D) -> void:
	if town == null or not _can_edit_town_live(town):
		return
	var terrain: Node = PLACEMENT_GHOST.find_terrain_in(_plugin.get_editor_interface().get_edited_scene_root())
	if terrain == null:
		_set_status("No Terrain3D in the open scene.")
		return
	var terrain_data = terrain.get("data")
	if terrain_data == null:
		_set_status("Terrain has no height data.")
		return
	var targets: Array = get_town_facility_nodes(town)
	for marker_name in ["RoadSpawn", "DefenseSpawn"]:
		var marker := town.get_node_or_null(marker_name)
		if marker is Node3D:
			targets.append(marker)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Snap Town To Terrain")
	var moved := 0
	for target_value in targets:
		var target := target_value as Node3D
		var height = terrain_data.call("get_height", target.global_position)
		if height == null or is_nan(float(height)):
			continue
		var foundation = target.get("foundation_height")
		var new_y := float(height) + (float(foundation) if foundation != null else 0.0)
		if absf(target.global_position.y - new_y) < 0.005:
			continue
		var new_position := Vector3(target.global_position.x, new_y, target.global_position.z)
		undo_redo.add_do_property(target, "global_position", new_position)
		undo_redo.add_undo_property(target, "global_position", target.global_position)
		moved += 1
	undo_redo.commit_action()
	_set_status("Snapped %d nodes to terrain." % moved)


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
	# In-zone editing is the primary authoring mode: keep the fresh instance's
	# children unlocked.
	zone_root.set_editable_instance(fresh, true)
	EditorInterface.get_resource_filesystem().scan()
	_select_node(fresh)
	_active_town = fresh
	return fresh


## --- Context plumbing ------------------------------------------------------


func _refresh_active_town_context() -> void:
	_active_town = _find_town_from_selection()
	if _active_town == null:
		_active_town = _find_town_from_edited_scene_root()
	_refresh_context_ui()


func _get_active_town() -> Node:
	if _active_town != null and is_instance_valid(_active_town):
		return _active_town
	_active_town = _find_town_from_edited_scene_root()
	return _active_town if _active_town != null and is_instance_valid(_active_town) else null


func get_active_town() -> Node:
	return _get_active_town()


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


## --- Toolbar / dock ----------------------------------------------------------


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "TownToolbar"
	_toolbar.add_theme_constant_override("separation", 6)
	_status_label = Label.new()
	_status_label.text = "Town: none"
	# Hard width cap: status messages must never stretch the spatial editor
	# menu row (that pushes the viewport past the screen edge). Full text
	# lives in the tooltip.
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.custom_minimum_size = Vector2(180, 0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_toolbar.add_child(_status_label)
	_add_facility_button = MenuButton.new()
	_add_facility_button.text = "Add Facility"
	_add_facility_button.icon = _get_town_icon()
	_add_facility_button.tooltip_text = "Pick a facility, then: hold left-click on terrain to anchor, drag to rotate, scroll to raise/lower, release to place. Right-click cancels."
	_add_facility_button.about_to_popup.connect(_populate_facility_menu)
	_add_facility_button.get_popup().id_pressed.connect(_on_add_facility_pressed)
	_toolbar.add_child(_add_facility_button)
	# Facility removal lives on the Facility toolbar (it acts on the selected
	# facility, and selecting a facility switches toolbars).
	_edit_in_zone_button = Button.new()
	_edit_in_zone_button.text = "Unpack Into Zone"
	_edit_in_zone_button.tooltip_text = "Expand this legacy town instance into plain nodes owned by the zone scene — the inline model. Undoable."
	_edit_in_zone_button.pressed.connect(func(): make_town_editable(_get_active_town()))
	_toolbar.add_child(_edit_in_zone_button)
	_snap_terrain_button = Button.new()
	_snap_terrain_button.text = "Snap To Terrain"
	_snap_terrain_button.tooltip_text = "Conform facilities and markers to the current terrain height (after sculpting)."
	_snap_terrain_button.pressed.connect(func(): snap_town_to_terrain(_get_active_town() as Node3D))
	_toolbar.add_child(_snap_terrain_button)
	_refresh_toolbar()


func _populate_facility_menu() -> void:
	var popup := _add_facility_button.get_popup()
	popup.clear()
	var catalog := rescan_facility_catalog()
	for index in range(catalog.size()):
		popup.add_item(catalog[index].get_display_name(), index)


func _refresh_context_ui() -> void:
	_refresh_toolbar()
	_refresh_dock()


func _refresh_toolbar() -> void:
	if _toolbar == null:
		return
	var town := _get_active_town()
	_toolbar.visible = town != null
	if town != null:
		var mode := "editing here" if _can_edit_town_live(town) else "locked instance"
		_status_label.text = "Town: %s (%s)" % [town.name, mode]
	_add_facility_button.disabled = town == null
	# Any instanced town in a zone is legacy now — offer the unpack regardless
	# of whether its children happen to be unlocked (editable instance).
	_edit_in_zone_button.visible = town != null and not _town_is_edited_scene_root(town) and not town.scene_file_path.is_empty()
	_snap_terrain_button.disabled = town == null or not _can_edit_town_live(town)


func _refresh_dock() -> void:
	if _dock == null or not is_instance_valid(_dock):
		return
	_dock.set_town(_get_active_town())


## Dock mounting is managed by the plugin router: the Town tab exists only
## while a SettlementTown node itself is selected — never merely because the
## selection sits somewhere inside a town.
func wants_dock() -> bool:
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		if claims_node(node):
			return true
	return false


func dock_control() -> Control:
	return _dock


func dock_title() -> String:
	return "Town"


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
		_status_label.tooltip_text = message


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
