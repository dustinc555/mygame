@tool
extends RefCounted

## Facility concept tool context for the world_authoring plugin. A facility
## is a function node placed under a town's Facilities root: either a
## composed SettlementFacilityInstance (bar/jail/keep — function roots with a
## BuildingSlot shell child) or a raw WorldBuilding shell (housing). The
## Facility bottom dock activates whenever the selection sits inside one and
## edits the function assignment and the building shell — the shell swap is
## the whole point: shells stay neutral scenes, the facility decides which
## one fills its slot.

const FACILITY_ICON_PATH := "res://addons/world_authoring/icons/world_building.svg"
const FACILITY_DOCK := preload("res://addons/world_authoring/facility_dock.gd")
const PLACEMENT_GHOST := preload("res://addons/world_authoring/placement_ghost.gd")
const INSTANCE_UNPACK := preload("res://addons/world_authoring/instance_unpack.gd")
const FACILITY_FURNISHER := preload("res://features/world/projection/props/furnishing/facility_furnisher.gd")
const FURNISH_RULES_DIR := "res://features/settlements/resources/furnishing"
const FURNISH_GENERATED_META := "furnish_generated"
const GUARD_POST_SCRIPT := preload("res://features/settlements/bridge/venues/settlement_guard_post.gd")
const BUILDING_SHELLS_DIR := "res://features/world/projection/buildings/shells/modular"
const WORLD_BUILDING_SCRIPT_PATH := "res://features/world/projection/buildings/world_building.gd"
const DEFAULT_SHELL_PATH := "res://features/world/projection/buildings/shells/modular/woodbrick_shop_medium.tscn"
const GUARD_POST_GHOST_COLOR := Color(0.35, 0.78, 1.0, 0.55)

var _plugin: EditorPlugin
var _toolbar: HBoxContainer
var _status_label: Label
var _dock: Control
var _active_facility: Node
var _shell_catalog: Array[String] = []
var _ghost
var _unpacker
## Managed by the plugin router: the dock is mounted in the bottom panel only
## while a facility node is literally selected.
var dock_mounted := false


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_ghost = PLACEMENT_GHOST.new(plugin)
	_unpacker = INSTANCE_UNPACK.new()
	_build_toolbar()
	_dock = FACILITY_DOCK.new()
	_dock.setup(self)


func toolbar() -> Control:
	return _toolbar


func handles(object: Object) -> bool:
	return object is Node and _find_facility_ancestor(object as Node) != null


func claims_node(node: Node) -> bool:
	return node is SettlementFacilityInstance


func edit(object: Object) -> void:
	if object is Node:
		_active_facility = _find_facility_ancestor(object as Node)
	_refresh_ui()


func refresh() -> void:
	_refresh_from_selection()


func is_active() -> bool:
	return _ghost.is_active() or _get_active_facility() != null


func on_selection_changed() -> void:
	_refresh_from_selection()


func on_scene_changed(_scene_root: Node) -> void:
	_ghost.cancel()
	_active_facility = null
	_refresh_ui()


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
	_active_facility = null
	_plugin = null


## --- Shell catalog ------------------------------------------------------------


## Production shells are discovered recursively under BUILDING_SHELLS_DIR.
## Deprecated initial buildings live outside this root and cannot appear here.
func get_shell_catalog() -> Array[String]:
	if not _shell_catalog.is_empty():
		return _shell_catalog
	_collect_shell_paths(BUILDING_SHELLS_DIR)
	_shell_catalog.sort()
	var default_index := _shell_catalog.find(DEFAULT_SHELL_PATH)
	if default_index > 0:
		_shell_catalog.remove_at(default_index)
		_shell_catalog.insert(0, DEFAULT_SHELL_PATH)
	return _shell_catalog


func _collect_shell_paths(directory_path: String) -> void:
	for file_name in DirAccess.get_files_at(directory_path):
		if file_name.get_extension() != "tscn":
			continue
		var path := directory_path.path_join(file_name)
		if FileAccess.get_file_as_string(path).contains(WORLD_BUILDING_SCRIPT_PATH):
			_shell_catalog.append(path)
	for child_directory in DirAccess.get_directories_at(directory_path):
		_collect_shell_paths(directory_path.path_join(child_directory))


func rescan_shell_catalog() -> Array[String]:
	_shell_catalog.clear()
	return get_shell_catalog()


## --- Shell swap -----------------------------------------------------------------


func current_shell_path(facility: Node) -> String:
	if facility is SettlementFacilityInstance:
		var slot := (facility as SettlementFacilityInstance).get_building_root()
		if slot != null and slot.get_child_count() > 0:
			return slot.get_child(0).scene_file_path
		return ""
	return facility.scene_file_path if facility != null else ""


## clear_furniture also removes the facility's Furniture/Beds children in the
## same undo step: authored furniture is laid out against a specific shell's
## floor plan, so carrying it into a different shell strands it mid-air.
func swap_shell(facility: Node, shell_path: String, clear_furniture := true) -> void:
	if facility == null or not _can_edit_live(facility):
		_set_status("Town is a locked instance — use Edit In Zone on the town first.")
		return
	var shell_scene := load(shell_path) as PackedScene
	if shell_scene == null:
		_set_status("Failed to load %s." % shell_path)
		return
	if facility is SettlementFacilityInstance:
		_swap_slot_shell(facility as SettlementFacilityInstance, shell_scene, shell_path, clear_furniture)
	elif facility is WorldBuilding:
		_swap_facility_node(facility as Node3D, shell_scene, shell_path)
	else:
		_set_status("%s has no swappable shell." % facility.name)
		return
	_refresh_ui()


## Composed facility (bar/jail/keep): replace the BuildingSlot child, keep
## its local transform; function roots (ServicePoints, Furniture…) untouched.
func _swap_slot_shell(facility: SettlementFacilityInstance, shell_scene: PackedScene, shell_path: String, clear_furniture: bool) -> void:
	var slot := facility.get_building_root()
	if slot == null:
		_set_status("%s has no BuildingSlot." % facility.name)
		return
	var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
	var old_shell := slot.get_child(0) if slot.get_child_count() > 0 else null
	var fresh := shell_scene.instantiate() as Node3D
	fresh.name = "CurrentBuilding"
	if old_shell is Node3D:
		fresh.transform = (old_shell as Node3D).transform
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Swap Facility Shell")
	if old_shell != null:
		undo_redo.add_do_method(slot, "remove_child", old_shell)
		undo_redo.add_undo_method(slot, "add_child", old_shell)
		undo_redo.add_undo_method(old_shell, "set_owner", owner_root)
		undo_redo.add_undo_reference(old_shell)
	undo_redo.add_do_method(slot, "add_child", fresh)
	undo_redo.add_do_method(fresh, "set_owner", owner_root)
	undo_redo.add_undo_method(slot, "remove_child", fresh)
	undo_redo.add_do_reference(fresh)
	if clear_furniture:
		for root_name in ["Furniture", "Beds"]:
			var furniture_root := facility.get_node_or_null(root_name)
			if furniture_root == null:
				continue
			for child in furniture_root.get_children():
				undo_redo.add_do_method(furniture_root, "remove_child", child)
				undo_redo.add_undo_method(furniture_root, "add_child", child)
				undo_redo.add_undo_method(child, "set_owner", owner_root)
				undo_redo.add_undo_reference(child)
	undo_redo.commit_action()
	# Keep the facility selected so the inspector and this dock stay on it.
	_select_node(facility)
	_set_status("Shell -> %s%s." % [shell_path.get_file().get_basename(), ", old furniture cleared" if clear_furniture else ""])


## Raw-shell facility (a house standing directly under Facilities): replace
## the whole node, preserving name and transform.
func _swap_facility_node(facility: Node3D, shell_scene: PackedScene, shell_path: String) -> void:
	var parent := facility.get_parent()
	var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
	if parent == null or owner_root == null:
		return
	var fresh := shell_scene.instantiate() as Node3D
	fresh.name = str(facility.name)
	fresh.transform = facility.transform
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Swap Facility Shell")
	undo_redo.add_do_method(parent, "remove_child", facility)
	undo_redo.add_do_method(parent, "add_child", fresh)
	undo_redo.add_do_method(fresh, "set_owner", owner_root)
	undo_redo.add_undo_method(parent, "remove_child", fresh)
	undo_redo.add_undo_method(parent, "add_child", facility)
	undo_redo.add_undo_method(facility, "set_owner", owner_root)
	undo_redo.add_do_reference(fresh)
	undo_redo.add_undo_reference(facility)
	undo_redo.commit_action()
	_active_facility = fresh
	_select_node(fresh)
	_set_status("Shell -> %s." % shell_path.get_file().get_basename())


## --- Instance unpack ---------------------------------------------------------------


## True while this facility is a locked scene instance whose children can't
## be edited in the open scene.
func facility_is_packed(facility: Node) -> bool:
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	return facility != null and facility != root and not facility.scene_file_path.is_empty()


## True when a packed ancestor (a legacy town instance) makes unpacking this
## facility unsafe — the town must be unpacked first.
func facility_unpack_blocked(facility: Node) -> bool:
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	return root != null and facility != null and _has_instanced_ancestor(facility, root)


## Expand the facility instance into plain nodes owned by the edited scene so
## its furniture and points become editable. Refuses while a scene-instance
## ancestor (a legacy packed town) still owns it — unpacking then would make
## the open scene save duplicates of nodes the town file already provides.
func unpack_facility(facility: Node) -> void:
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	if root == null or not facility_is_packed(facility):
		return
	if _has_instanced_ancestor(facility, root):
		_set_status("Unpack the town first (select the town node, then Unpack Into Zone).")
		return
	_unpacker.unpack(facility, root, _plugin.get_undo_redo())
	_select_node(facility)
	_set_status("%s unpacked — its furniture and points are editable here now." % facility.name)


func _has_instanced_ancestor(node: Node, root: Node) -> bool:
	var current := node.get_parent()
	while current != null and current != root:
		if not current.scene_file_path.is_empty():
			return true
		current = current.get_parent()
	return false


## --- Furnish pass -------------------------------------------------------------------


## Editor furnish pass: solve a furniture layout for the facility's shell and
## instantiate it as plain saved nodes under Furniture, tagged with
## furnish_generated metadata. Re-running replaces only tagged nodes —
## hand-placed or hand-edited (untagged) furniture is never touched. Reroll
## bumps the facility's furnish_seed for a fresh deterministic layout.
func furnish_facility(facility: Node, reroll := false) -> void:
	if not (facility is SettlementFacilityInstance):
		_set_status("Select a composed facility (e.g. a bar) to furnish.")
		return
	if not _can_edit_live(facility):
		_set_status("Unpack the town first (select the town node, then Unpack Into Zone).")
		return
	var building := _facility_building(facility)
	if building == null:
		_set_status("%s has no building shell to furnish." % facility.name)
		return
	var rules := _furnish_rules_for(facility)
	if rules == null:
		_set_status("No furnish rules for facility type '%s' (add %s/<type>.tres)." % [str(facility.get("facility_type")), FURNISH_RULES_DIR])
		return
	var seed_value := int(facility.get("furnish_seed")) + (1 if reroll else 0)
	var furnisher = FACILITY_FURNISHER.new()
	var placements: Array = furnisher.furnish(building, rules, seed_value)
	if placements.is_empty():
		_set_status("Furnish failed: %s" % furnisher.last_error())
		return
	var furniture_root := facility.get_node_or_null("Furniture") as Node3D
	var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
	if furniture_root == null or owner_root == null:
		_set_status("%s has no Furniture root." % facility.name)
		return
	var to_furniture: Transform3D = furniture_root.global_transform.affine_inverse() * building.global_transform
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Furnish Facility")
	undo_redo.add_do_property(facility, "furnish_seed", seed_value)
	undo_redo.add_undo_property(facility, "furnish_seed", facility.get("furnish_seed"))
	for child in furniture_root.get_children():
		if not child.has_meta(FURNISH_GENERATED_META):
			continue
		undo_redo.add_do_method(furniture_root, "remove_child", child)
		undo_redo.add_undo_method(furniture_root, "add_child", child)
		undo_redo.add_undo_method(child, "set_owner", owner_root)
		undo_redo.add_undo_reference(child)
	var counts := {}
	for placement_value in placements:
		var placement: Dictionary = placement_value
		var kind := str(placement["kind"])
		counts[kind] = int(counts.get(kind, 0)) + 1
		var scene: PackedScene = placement["scene"]
		var node := scene.instantiate() as Node3D
		node.name = "%s%d" % [kind.to_pascal_case(), counts[kind]]
		node.transform = to_furniture * (placement["transform"] as Transform3D)
		node.set_meta(FURNISH_GENERATED_META, true)
		undo_redo.add_do_method(furniture_root, "add_child", node)
		undo_redo.add_do_method(self, "_own_facility_placement", node, owner_root)
		undo_redo.add_undo_method(furniture_root, "remove_child", node)
		undo_redo.add_do_reference(node)
	undo_redo.commit_action()
	_select_node(facility)
	_set_status("Furnished %s: %d counter, %d clusters, %d shelves (seed %d)." % [facility.name, int(counts.get("counter", 0)), int(counts.get("cluster", 0)), int(counts.get("shelf", 0)), seed_value])
	if _dock != null and is_instance_valid(_dock):
		_dock.set_facility(facility)


func _own_facility_placement(node: Node, owner_root: Node) -> void:
	node.owner = owner_root
	_own_restored_children(node, owner_root)


func _facility_building(facility: Node) -> Node3D:
	var slot: Node3D = (facility as SettlementFacilityInstance).get_building_root()
	if slot == null or slot.get_child_count() == 0:
		return null
	return slot.get_child(0) as Node3D


func _furnish_rules_for(facility: Node) -> Resource:
	var facility_type := str(facility.get("facility_type"))
	var path := "%s/%s.tres" % [FURNISH_RULES_DIR, facility_type]
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## --- Function assignment ---------------------------------------------------------


func assign_function(facility: Node, function_resource: Resource) -> void:
	if not (facility is SettlementFacilityInstance):
		return
	if not _can_edit_live(facility):
		_set_status("Town is a locked instance — use Edit In Zone on the town first.")
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Assign Facility Function")
	undo_redo.add_do_property(facility, "facility_function", function_resource)
	undo_redo.add_undo_property(facility, "facility_function", facility.get("facility_function"))
	undo_redo.commit_action()
	_set_status("Function assigned.")
	_refresh_ui()


## --- Staffing -------------------------------------------------------------------------


## Undo-aware property write for the facility's staffing knobs (guard_count,
## guard_post_count, guard_name…). Property setters on the facility scripts
## regenerate their guard/post trees, so this is all the dock needs.
func set_facility_property(facility: Node, property_name: String, value) -> void:
	if facility == null or not _can_edit_live(facility):
		_set_status("Town is a locked instance — use Edit In Zone on the town first.")
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Set %s" % property_name)
	undo_redo.add_do_property(facility, property_name, value)
	undo_redo.add_undo_property(facility, property_name, facility.get(property_name))
	undo_redo.commit_action()
	if _dock != null and is_instance_valid(_dock):
		_dock.set_facility(facility)


## Ghost-place an authored guard post under the facility's GuardPosts root.
func begin_guard_post_placement(facility: Node) -> void:
	if facility == null or not _can_edit_live(facility):
		_set_status("Town is a locked instance — use Edit In Zone on the town first.")
		return
	_select_node(facility)
	var committed := func(world_transform: Transform3D) -> void:
		_place_guard_post(facility, world_transform)
	if not _ghost.begin_marker(0.8, GUARD_POST_GHOST_COLOR, committed, func(): _set_status("Placement cancelled.")):
		_set_status("Could not start placement (no edited scene).")
		return
	_set_status("Click terrain to place a guard post; right-click cancels.")


func _place_guard_post(facility: Node, world_transform: Transform3D) -> void:
	var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
	var facility_3d := facility as Node3D
	if facility_3d == null or owner_root == null:
		return
	var posts_root := facility.get_node_or_null("GuardPosts")
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Place Guard Post")
	if posts_root == null:
		posts_root = Node3D.new()
		posts_root.name = "GuardPosts"
		undo_redo.add_do_method(facility, "add_child", posts_root)
		undo_redo.add_do_method(posts_root, "set_owner", owner_root)
		undo_redo.add_undo_method(facility, "remove_child", posts_root)
		undo_redo.add_do_reference(posts_root)
	var post := Node3D.new()
	post.name = _unique_child_name(posts_root, "GuardPost")
	post.set_script(GUARD_POST_SCRIPT)
	post.position = facility_3d.global_transform.affine_inverse() * world_transform.origin
	post.set_meta("settlement_guard_post_custom", true)
	undo_redo.add_do_method(posts_root, "add_child", post)
	undo_redo.add_do_method(post, "set_owner", owner_root)
	undo_redo.add_undo_method(posts_root, "remove_child", post)
	undo_redo.add_do_reference(post)
	undo_redo.commit_action()
	_select_node(facility)
	_set_status("Placed %s." % post.name)
	if _dock != null and is_instance_valid(_dock):
		_dock.set_facility(facility)


func _unique_child_name(parent: Node, base_name: String) -> String:
	if parent == null or parent.get_node_or_null(base_name) == null:
		return base_name
	var index := 2
	while parent.get_node_or_null("%s%d" % [base_name, index]) != null:
		index += 1
	return "%s%d" % [base_name, index]


## --- Context plumbing --------------------------------------------------------------


func _get_active_facility() -> Node:
	if _active_facility != null and is_instance_valid(_active_facility):
		return _active_facility
	return null


func _refresh_from_selection() -> void:
	_active_facility = null
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		_active_facility = _find_facility_ancestor(node)
		if _active_facility != null:
			break
	_refresh_ui()


## Innermost facility above the node: a composed facility instance, or a
## WorldBuilding standing directly under a town's Facilities root.
func _find_facility_ancestor(node: Node) -> Node:
	var current := node
	while current != null:
		if current is SettlementFacilityInstance:
			return current
		if current is WorldBuilding and _is_town_facility_child(current):
			return current
		current = current.get_parent()
	return null


## Flat model: facilities are direct town children. Legacy towns still group
## them under a "Facilities" container; both count.
func _is_town_facility_child(node: Node) -> bool:
	var parent := node.get_parent()
	if parent == null:
		return false
	if parent is SettlementTown:
		return true
	if str(parent.name) != "Facilities":
		return false
	var walker := parent.get_parent()
	while walker != null:
		if walker is SettlementTown:
			return true
		walker = walker.get_parent()
	return false


## Live-editable when the facility sits under the edited scene root through
## editable instances only (same gate as town editing).
func _can_edit_live(facility: Node) -> bool:
	var root := _plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		return false
	var current := facility
	while current != null and current != root:
		if not current.scene_file_path.is_empty() and current != facility:
			if not root.is_editable_instance(current):
				return false
		current = current.get_parent()
	return current == root


func _select_node(node: Node) -> void:
	var selection := _plugin.get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(node)
	_plugin.get_editor_interface().edit_node(node)


## --- Toolbar / dock -------------------------------------------------------------------


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "FacilityToolbar"
	_status_label = Label.new()
	_status_label.text = "Facility: none"
	# Hard width cap: status messages must never stretch the spatial editor
	# menu row (that pushes the viewport past the screen edge). Full text
	# lives in the tooltip.
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.custom_minimum_size = Vector2(180, 0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_toolbar.add_child(_status_label)
	var remove_button := Button.new()
	remove_button.text = "Remove Facility"
	remove_button.tooltip_text = "Delete this facility from its town. Undoable."
	remove_button.pressed.connect(func(): remove_facility(_get_active_facility()))
	_toolbar.add_child(remove_button)
	_toolbar.visible = false


## Delete the facility node from its town with undo. Packed facilities need
## their town unpacked first (same live-edit gate as every other action).
func remove_facility(facility: Node) -> void:
	if facility == null:
		return
	if not _can_edit_live(facility):
		_set_status("Unpack the town first (select the town node, then Unpack Into Zone).")
		return
	var parent := facility.get_parent()
	var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
	if parent == null or owner_root == null:
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Remove Facility")
	undo_redo.add_do_method(parent, "remove_child", facility)
	undo_redo.add_undo_method(parent, "add_child", facility)
	undo_redo.add_undo_method(self, "_restore_facility_owners", facility, owner_root)
	undo_redo.add_undo_reference(facility)
	undo_redo.commit_action()
	_active_facility = null
	_refresh_ui()


## remove_child clears owners across the subtree; undo must restore them or
## the resurrected facility would silently drop out of the saved scene.
func _restore_facility_owners(facility: Node, owner_root: Node) -> void:
	facility.owner = owner_root
	_own_restored_children(facility, owner_root)


func _own_restored_children(node: Node, owner_root: Node) -> void:
	# An instance root owns its internals. Claiming them makes the editor save
	# duplicate type+instance entries that load as phantom off-tree nodes.
	if not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		child.owner = owner_root
		if child.scene_file_path.is_empty():
			_own_restored_children(child, owner_root)


func _refresh_ui() -> void:
	var facility := _get_active_facility()
	if _toolbar != null:
		_toolbar.visible = facility != null
		if facility != null:
			_status_label.text = "Facility: %s" % facility.name
	if _dock != null and is_instance_valid(_dock):
		_dock.set_facility(facility)


## Dock mounting is managed by the plugin router: the Facility tab exists
## only while a facility node itself is selected (a composed facility
## instance, or a WorldBuilding directly under a town's Facilities root) —
## never merely because the selection sits somewhere inside one.
func wants_dock() -> bool:
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		if node is SettlementFacilityInstance:
			return true
		if node is WorldBuilding and _is_town_facility_child(node):
			return true
	return false


func dock_control() -> Control:
	return _dock


func dock_title() -> String:
	return "Facility"


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
		_status_label.tooltip_text = message
