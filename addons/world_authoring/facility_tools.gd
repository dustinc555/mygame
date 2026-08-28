@tool
extends RefCounted

## Facility concept tool context for the world_authoring plugin. A facility
## is a composed SettlementFacilityInstance placed under a town: a function
## root with a BuildingSlot shell child and Furniture root. The
## Facility bottom dock activates whenever the selection sits inside one and
## edits the function assignment and the building shell — the shell swap is
## the whole point: shells stay neutral scenes, the facility decides which
## one fills its slot.

const FACILITY_ICON_PATH := "res://addons/world_authoring/icons/world_building.svg"
const FACILITY_DOCK := preload("res://addons/world_authoring/facility_dock.gd")
const PLACEMENT_GHOST := preload("res://addons/world_authoring/placement_ghost.gd")
const INSTANCE_UNPACK := preload("res://addons/world_authoring/instance_unpack.gd")
const FIELD_PAINTER := preload("res://addons/world_authoring/field_painter.gd")
## Loaded lazily, never preloaded: the plugin must not fail to mount because a
## gameplay script it only reads a constant from is mid-edit.
const FARM_CONTROLLER_PATH := "res://features/farming/sim/farm_controller.gd"
const ITEMS_DIR := "res://features/inventory/resources/items"
const FACILITY_FURNISHER := preload("res://features/world/projection/props/furnishing/facility_furnisher.gd")
const FURNISH_RULES_DIR := "res://features/settlements/resources/furnishing"
const FURNISH_GENERATED_META := "furnish_generated"
const GUARD_POST_SCENE := preload("res://features/settlements/bridge/venues/facility_guard_post.tscn")
const FURNISH_RULES_SCRIPT := preload("res://features/settlements/resources/furnishing/furnish_rules.gd")
## Hand-placeable furniture catalog roots, scanned (never hardcoded). Each
## .tscn found becomes a browser entry labeled by its folder.
const FURNITURE_DIRS := [
	"res://features/world/projection/props/furniture",
	"res://features/world/projection/props/furniture/throne",
	"res://features/world/projection/props/lighting",
	"res://features/world/projection/containers",
]
const BUILDING_SHELLS_DIR := "res://features/world/projection/buildings/shells/modular"
const WORLD_BUILDING_SCRIPT_PATH := "res://features/world/projection/buildings/world_building.gd"
const DEFAULT_SHELL_PATH := "res://features/world/projection/buildings/shells/modular/medium_wood_hall.tscn"
const GUARD_POST_GHOST_COLOR := Color(0.35, 0.78, 1.0, 0.55)

var _plugin: EditorPlugin
var _toolbar: HBoxContainer
var _status_label: Label
var _dock: Control
var _active_facility: Node
var _active_container: Node
var _shell_catalog: Array[String] = []
## path -> display name. Reading a shell's name means instantiating the whole
## modular building (~25-80ms each); doing that for all seven shells on every
## dock rebuild was costing a quarter second per selection change.
var _shell_name_cache := {}
var _furniture_catalog: Array[Dictionary] = []
var _container_item_catalog: Array[ItemDefinition] = []
var _container_tool_item_paths := {}
var _pending_furniture_path := ""
var _ghost
var _painter
var _unpacker
## Managed by the plugin router: the dock is mounted in the bottom panel only
## while a facility node is literally selected.
var dock_mounted := false


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_ghost = PLACEMENT_GHOST.new(plugin)
	_painter = FIELD_PAINTER.new(plugin)
	_unpacker = INSTANCE_UNPACK.new()
	_build_toolbar()
	_dock = FACILITY_DOCK.new()
	_dock.setup(self)


func toolbar() -> Control:
	return _toolbar


func handles(object: Object) -> bool:
	return object is WorldContainer or (object is Node and _find_facility_ancestor(object as Node) != null)


func claims_node(node: Node) -> bool:
	return node is SettlementFacilityInstance or node is WorldContainer


func edit(object: Object) -> void:
	if object is Node:
		_active_facility = _find_facility_ancestor(object as Node)
		_active_container = object as Node if object is WorldContainer else null
	_refresh_ui()


func refresh() -> void:
	_refresh_from_selection()


func is_active() -> bool:
	return _ghost.is_active() or _painter.is_active() or _get_active_facility() != null \
			or (_active_container != null and is_instance_valid(_active_container))


func on_selection_changed() -> void:
	_refresh_from_selection()


func on_scene_changed(_scene_root: Node) -> void:
	_ghost.cancel()
	_painter.end()
	_active_facility = null
	_active_container = null
	_refresh_ui()


func process(_delta: float) -> void:
	pass


func shortcut_input(_event: InputEvent) -> bool:
	return false


## Pre-GUI wheel claim while placing (router calls this from _input).
func handle_global_input(event: InputEvent) -> bool:
	return _ghost.handle_global_input(event)


func forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	# Painting owns the viewport while it is live; a field footprint is drawn
	# on the ground, so it cannot share input with the placement ghost.
	if _painter.is_active():
		return _painter.handle_3d_input(camera, event)
	return _ghost.handle_3d_input(camera, event)


func teardown() -> void:
	_ghost.cancel()
	_painter.end()
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
	_active_container = null
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
	return ""


func shell_display_name(shell_path: String) -> String:
	if _shell_name_cache.has(shell_path):
		return str(_shell_name_cache[shell_path])
	var name := _read_shell_display_name(shell_path)
	_shell_name_cache[shell_path] = name
	return name


func _read_shell_display_name(shell_path: String) -> String:
	var scene := load(shell_path) as PackedScene
	var shell := scene.instantiate() as WorldBuilding if scene != null else null
	if shell == null:
		return shell_path.get_file().get_basename()
	var label := shell.display_name.strip_edges()
	shell.free()
	return label if not label.is_empty() else shell_path.get_file().get_basename()


## clear_furniture also removes the facility's Furniture/Beds children in the
## same undo step: authored furniture is laid out against a specific shell's
## floor plan, so carrying it into a different shell strands it mid-air.
func swap_shell(facility: Node, shell_path: String, clear_furniture := true) -> void:
	if facility == null or not _can_edit_live(facility):
		_set_status("Town is a locked instance — use Edit In Zone on the town first.")
		return
	if not (facility is SettlementFacilityInstance):
		_set_status("Select a composed facility to swap its shell.")
		return
	var shell_scene := load(shell_path) as PackedScene if not shell_path.is_empty() else null
	if not shell_path.is_empty() and shell_scene == null:
		_set_status("Failed to load %s." % shell_path)
		return
	_swap_slot_shell(facility as SettlementFacilityInstance, shell_scene, shell_path, clear_furniture)
	_refresh_ui()


## Composed facility: replace or remove the BuildingSlot child, keep
## its local transform; function roots (ServicePoints, Furniture…) untouched.
func _swap_slot_shell(facility: SettlementFacilityInstance, shell_scene: PackedScene, shell_path: String, clear_furniture: bool) -> void:
	var slot := facility.get_building_root()
	if slot == null:
		_set_status("%s has no BuildingSlot." % facility.name)
		return
	var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
	var old_shell := slot.get_child(0) if slot.get_child_count() > 0 else null
	var fresh := shell_scene.instantiate() as Node3D if shell_scene != null else null
	if fresh != null:
		fresh.name = "CurrentBuilding"
		if old_shell is Node3D:
			fresh.transform = (old_shell as Node3D).transform
		facility.stamp_building_node_identity(fresh)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Remove Facility Shell" if fresh == null else "Swap Facility Shell")
	if old_shell != null:
		undo_redo.add_do_method(slot, "remove_child", old_shell)
		undo_redo.add_undo_method(slot, "add_child", old_shell)
		undo_redo.add_undo_method(old_shell, "set_owner", owner_root)
		undo_redo.add_undo_reference(old_shell)
	if fresh != null:
		undo_redo.add_do_method(slot, "add_child", fresh)
		undo_redo.add_do_method(fresh, "set_owner", owner_root)
		undo_redo.add_undo_method(slot, "remove_child", fresh)
		undo_redo.add_do_reference(fresh)
	if clear_furniture:
		_append_clear_furniture_undo(undo_redo, facility, owner_root)
	undo_redo.commit_action()
	# Keep the facility selected so the inspector and this dock stay on it.
	_select_node(facility)
	var shell_label := "No Shell" if shell_path.is_empty() else shell_display_name(shell_path)
	_set_status("Shell -> %s%s." % [shell_label, ", old furniture cleared" if clear_furniture else ""])


func _append_clear_furniture_undo(undo_redo: EditorUndoRedoManager, facility: Node, owner_root: Node) -> void:
	for root_name in ["Furniture", "Beds"]:
		var furniture_root := facility.get_node_or_null(root_name)
		if furniture_root == null:
			continue
		for child in furniture_root.get_children():
			undo_redo.add_do_method(furniture_root, "remove_child", child)
			undo_redo.add_undo_method(furniture_root, "add_child", child)
			undo_redo.add_undo_method(child, "set_owner", owner_root)
			undo_redo.add_undo_reference(child)


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


## --- Hand furniture placement ---------------------------------------------------


## Catalog entries: {"path": String, "category": String, "name": String},
## sorted by category then name.
func get_furniture_catalog() -> Array[Dictionary]:
	if not _furniture_catalog.is_empty():
		return _furniture_catalog
	for dir_path in FURNITURE_DIRS:
		var category := str(dir_path).get_file()
		for file_name in DirAccess.get_files_at(str(dir_path)):
			if file_name.get_extension() != "tscn":
				continue
			# *_model.tscn are raw visual halves of container wrappers, not
			# placeable furniture.
			if file_name.ends_with("_model.tscn"):
				continue
			_furniture_catalog.append({
				"path": str(dir_path).path_join(file_name),
				"category": category,
				"name": file_name.get_basename().capitalize(),
			})
	_furniture_catalog.sort_custom(func(a, b):
		return a["category"] < b["category"] if a["category"] != b["category"] else a["name"] < b["name"])
	return _furniture_catalog


func rescan_furniture_catalog() -> Array[Dictionary]:
	_furniture_catalog.clear()
	return get_furniture_catalog()


## Ghost-place a single furniture piece under the facility's Furniture root —
## the "just add a torch" path. The placed node is a plain editable child
## with NO furnish_generated tag, so Furnish/Reroll never touch it.
func begin_furniture_placement(facility: Node, scene_path: String) -> void:
	if not (facility is SettlementFacilityInstance):
		_set_status("Select a composed facility (e.g. a bar) to add furniture.")
		return
	if not _can_edit_live(facility):
		_set_status("Unpack the town first (select the town node, then Unpack Into Zone).")
		return
	var furniture_scene := load(scene_path) as PackedScene
	if furniture_scene == null:
		_set_status("Failed to load %s." % scene_path)
		return
	_pending_furniture_path = scene_path
	# Keep the facility selected so the editor keeps forwarding viewport input
	# to this context while the ghost is live.
	_select_node(facility)
	var committed := func(world_transform: Transform3D) -> void:
		_place_furniture_piece(facility, world_transform)
	if not _ghost.begin_scene(furniture_scene, committed, _on_furniture_placement_cancelled):
		_set_status("Could not start placement (no edited scene).")
		return
	_set_status("Placing %s: hold left-click to anchor, drag rotates, scroll = height, release places. Right-click cancels." % scene_path.get_file().get_basename())


func _on_furniture_placement_cancelled() -> void:
	_pending_furniture_path = ""
	_set_status("Placement cancelled.")


func _place_furniture_piece(facility: Node, world_transform: Transform3D) -> void:
	var scene_path := _pending_furniture_path
	_pending_furniture_path = ""
	var furniture_scene := load(scene_path) as PackedScene
	var owner_root := _plugin.get_editor_interface().get_edited_scene_root()
	if furniture_scene == null or owner_root == null or facility == null or not is_instance_valid(facility):
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Add Furniture Piece")
	var furniture_root := facility.get_node_or_null("Furniture") as Node3D
	if furniture_root == null:
		furniture_root = Node3D.new()
		furniture_root.name = "Furniture"
		undo_redo.add_do_method(facility, "add_child", furniture_root)
		undo_redo.add_do_method(furniture_root, "set_owner", owner_root)
		undo_redo.add_undo_method(facility, "remove_child", furniture_root)
		undo_redo.add_do_reference(furniture_root)
	var node := furniture_scene.instantiate() as Node3D
	node.name = _unique_child_name(furniture_root, scene_path.get_file().get_basename().to_pascal_case())
	undo_redo.add_do_method(furniture_root, "add_child", node)
	undo_redo.add_do_method(node, "set_owner", owner_root)
	undo_redo.add_do_property(node, "global_transform", world_transform)
	undo_redo.add_undo_method(furniture_root, "remove_child", node)
	undo_redo.add_do_reference(node)
	undo_redo.commit_action()
	_select_node(facility)
	_set_status("Placed %s." % node.name)
	if _dock != null and is_instance_valid(_dock):
		_dock.set_facility(facility)


## --- Field authoring ----------------------------------------------------------------


static func is_field(facility: Node) -> bool:
	return facility != null and str(facility.get("facility_type")) == "farm" and "cell_coordinates" in facility


func is_painting_field() -> bool:
	return _painter.is_active()


## Crop ids offered for a field policy, read straight off FarmController's
## registry so the dock can never drift from what the sim accepts.
static func field_crop_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var farm_script := load(FARM_CONTROLLER_PATH)
	if farm_script == null:
		return options
	for crop_id in farm_script.CROP_PATHS:
		var crop := load(farm_script.CROP_PATHS[crop_id]) as Resource
		options.append({
			"crop_id": str(crop_id),
			"label": str(crop.get("display_name")) if crop != null else str(crop_id).capitalize(),
		})
	options.sort_custom(func(a, b): return str(a["label"]) < str(b["label"]))
	return options


func toggle_field_paint(facility: Node) -> void:
	if _painter.is_active():
		_painter.end()
		_set_status("Field painting finished.")
		_refresh_ui()
		return
	if not is_field(facility):
		_set_status("Select a field facility to paint its soil.")
		return
	if not _can_edit_live(facility):
		_set_status("Unpack the town first (select the town node, then Unpack Into Zone).")
		return
	_select_node(facility)
	if not _painter.begin(facility as Node3D, Callable(self, "_on_field_painted")):
		_set_status("Could not start painting.")
		return
	_set_status("Painting soil: drag to add cells, Shift-drag or right-drag to erase, Escape to finish.")
	_refresh_ui()


func _on_field_painted() -> void:
	var summary := "%d soil cells (painted)%s" % [
		_painter.cell_count(),
		", %d refused by a foreign town border" % _painter.refused_count() if _painter.refused_count() > 0 else "",
	]
	# Deliberately NOT set_facility(): that rebuilds every dock section, which
	# is far too heavy to run once per brush stroke.
	if _dock != null and is_instance_valid(_dock) and _dock.has_method("refresh_field_status"):
		_dock.refresh_field_status(summary)
	_set_status("Field footprint: %s." % summary)


## Terrain edits do not notify the nodes standing on them, so re-sculpting the
## ground under a field leaves its cells at the old heights until this runs.
func refit_field_to_terrain(facility: Node) -> void:
	if not is_field(facility) or not facility.has_method("refit_to_terrain"):
		return
	facility.call("refit_to_terrain")
	_set_status("Field re-seated on the current terrain.")


func set_field_crop_policy(facility: Node, crop_id: String) -> void:
	if not is_field(facility) or not _can_edit_live(facility):
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Set Field Crop")
	undo_redo.add_do_property(facility, "crop_policy_id", crop_id)
	undo_redo.add_undo_property(facility, "crop_policy_id", facility.get("crop_policy_id"))
	undo_redo.commit_action()
	_set_status("Crop policy: %s." % ("auto" if crop_id == "auto" else (crop_id if not crop_id.is_empty() else "manual")))


## --- Container authoring ------------------------------------------------------

func container_item_options(container_type: String) -> Array[ItemDefinition]:
	if _container_item_catalog.is_empty():
		for file_name in DirAccess.get_files_at(ITEMS_DIR):
			if file_name.get_extension() != "tres":
				continue
			var item_path := ITEMS_DIR.path_join(file_name)
			var item := load(item_path) as ItemDefinition
			if item != null:
				_container_item_catalog.append(item)
				if _resource_declares_tool_tags(item_path):
					_container_tool_item_paths[item_path] = true
		_container_item_catalog.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool: return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	var result: Array[ItemDefinition] = []
	for item in _container_item_catalog:
		if _item_matches_container_type(item, container_type):
			result.append(item)
	return result


func _item_matches_container_type(item: ItemDefinition, container_type: String) -> bool:
	if item == null:
		return false
	var item_id := item.item_id.strip_edges()
	if item_id.is_empty():
		item_id = item.resource_path
	match container_type:
		"seeds":
			return item_id.begins_with("seed.")
		"tools":
			return item_id.begins_with("tool.") or _container_tool_item_paths.has(item.resource_path)
		"food":
			return item_id.begins_with("food.") or not item.food_type_id.is_empty()
		"materials":
			return item_id.begins_with("material.") or item_id.begins_with("ore.")
		_:
			return true


func _resource_declares_tool_tags(item_path: String) -> bool:
	var source := FileAccess.get_file_as_string(item_path)
	for line in source.split("\n"):
		var stripped := str(line).strip_edges()
		if stripped.begins_with("tool_tags = PackedStringArray("):
			return stripped.contains("\"")
	return false


func set_container_property(container: Node, property_name: String, value) -> void:
	if container == null or not is_instance_valid(container) or not _can_edit_live(container):
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Set Container %s" % property_name.capitalize())
	undo_redo.add_do_property(container, property_name, value)
	undo_redo.add_do_method(self, "_notify_container_property_changed", container, property_name)
	undo_redo.add_undo_property(container, property_name, container.get(property_name))
	undo_redo.add_undo_method(self, "_notify_container_property_changed", container, property_name)
	undo_redo.commit_action()
	_active_container = container


func _notify_container_property_changed(container: Node, property_name: String) -> void:
	if container == null or not is_instance_valid(container):
		return
	_active_container = container
	if _dock != null and is_instance_valid(_dock) and _dock.has_method("refresh_container_property"):
		_dock.call("refresh_container_property", container, property_name)


func set_container_starting_item_amount(container: Node, item: ItemDefinition, amount: int) -> void:
	if container == null or item == null or not _can_edit_live(container):
		return
	var previous: Array[InventoryStock] = container.get("starting_items")
	var next: Array[InventoryStock] = []
	var replaced := false
	for stock in previous:
		if stock == null or stock.item_definition == null:
			continue
		if stock.item_definition == item:
			replaced = true
			if amount > 0:
				var updated := stock.duplicate(true) as InventoryStock
				updated.quantity = amount
				next.append(updated)
		else:
			next.append(stock.duplicate(true) as InventoryStock)
	if amount > 0 and not replaced:
		var added := InventoryStock.new()
		added.item_definition = item
		added.quantity = amount
		next.append(added)
	set_container_property(container, "starting_items", next)


func select_container(container: Node) -> void:
	if container != null and is_instance_valid(container):
		_select_node(container)


## Keep the scene tree, viewport, and Inspector pointed at the dock selection
## without recursively rebuilding the whole Facility workspace.
func select_container_from_dock(container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	_active_container = container
	_active_facility = _find_facility_ancestor(container)
	if _plugin.has_method("select_node_without_context_refresh"):
		_plugin.call("select_node_without_context_refresh", container)


## Reset to a plain rectangle — the escape hatch from a painted shape.
func reset_field_footprint(facility: Node, dimensions: Vector2i) -> void:
	if not is_field(facility) or not _can_edit_live(facility):
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Reset Field Footprint")
	undo_redo.add_do_property(facility, "dimensions", Vector2i(maxi(1, dimensions.x), maxi(1, dimensions.y)))
	undo_redo.add_do_property(facility, "cell_coordinates", PackedVector2Array())
	undo_redo.add_undo_property(facility, "dimensions", facility.get("dimensions"))
	undo_redo.add_undo_property(facility, "cell_coordinates", facility.get("cell_coordinates"))
	undo_redo.commit_action()
	if _dock != null and is_instance_valid(_dock):
		_dock.set_facility(facility)
	_set_status("Field reset to a %dx%d rectangle." % [dimensions.x, dimensions.y])


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
	var resolved := resolve_furnish_rules(facility)
	var rules: Resource = resolved.get("rules")
	if rules == null:
		_set_status("No furnish rules resolve for type '%s' — create %s/default.tres." % [str(facility.get("facility_type")), FURNISH_RULES_DIR])
		return
	var seed_value := int(facility.get("furnish_seed")) + (1 if reroll else 0)
	var furnisher = FACILITY_FURNISHER.new()
	# Plugin-authored/world-generated facilities bake their starter recipe. A
	# runtime player furnishing call uses FacilityFurnisher's default false and
	# therefore creates empty containers.
	var placements: Array = furnisher.furnish(building, rules, seed_value, true)
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
		var placement_transform: Transform3D = to_furniture * (placement["transform"] as Transform3D)
		# Vignettes are solver-only layout stencils. Their children always land
		# as individual editable nodes; no cluster container enters the scene.
		if node is FurnitureVignette:
			for child in node.get_children():
				var child_3d := child as Node3D
				if child_3d == null or str(child_3d.scene_file_path).is_empty():
					continue
				var piece := (load(child_3d.scene_file_path) as PackedScene).instantiate() as Node3D
				var base_name := str(child_3d.name).rstrip("0123456789")
				counts[base_name] = int(counts.get(base_name, 0)) + 1
				piece.name = "%s%d" % [base_name, counts[base_name]]
				_stamp_furniture_ids(piece, facility)
				piece.transform = placement_transform * child_3d.transform
				piece.set_meta(FURNISH_GENERATED_META, true)
				undo_redo.add_do_method(furniture_root, "add_child", piece)
				undo_redo.add_do_method(self, "_own_facility_placement", piece, owner_root)
				undo_redo.add_undo_method(furniture_root, "remove_child", piece)
				undo_redo.add_do_reference(piece)
			node.free()
			continue
		var base_name := kind.to_pascal_case()
		if placement.has("item_id"):
			# "food.tomato" -> PalletTomato3: the crop lock is visible in the
			# scene tree and rides into the stamped container_id. Item ids
			# without a category prefix name the pallet whole.
			var item_id := str(placement["item_id"])
			var item_name := item_id.get_slice(".", 1) if item_id.contains(".") else item_id
			base_name += item_name.to_pascal_case()
		node.name = "%s%d" % [base_name, counts[kind]]
		_stamp_furniture_ids(node, facility)
		node.transform = placement_transform
		if placement.has("storage_item_overrides"):
			node.set("storage_item_overrides", placement["storage_item_overrides"])
		if placement.has("container_type") and "container_type" in node:
			node.set("container_type", str(placement["container_type"]))
		if placement.has("stock"):
			# Rolled loot bakes into the saved container node; the fresh
			# InventoryStock resources embed in the town scene on save.
			node.set("starting_items", placement["stock"])
		node.set_meta(FURNISH_GENERATED_META, true)
		undo_redo.add_do_method(furniture_root, "add_child", node)
		undo_redo.add_do_method(self, "_own_facility_placement", node, owner_root)
		undo_redo.add_undo_method(furniture_root, "remove_child", node)
		undo_redo.add_do_reference(node)
	undo_redo.commit_action()
	_select_node(facility)
	var facility_label := str(facility.get("display_name")).strip_edges() if facility.get("display_name") != null else str(facility.name)
	var storage_count := int(counts.get("container", 0)) + int(counts.get("utility", 0))
	_set_status("Furnished %s: %d beds, %d dining sets, %d storage, %d shelves, %d lights (seed %d)." % [facility_label, int(counts.get("bed", 0)), int(counts.get("cluster", 0)), storage_count, int(counts.get("shelf", 0)), int(counts.get("light", 0)), seed_value])
	if _dock != null and is_instance_valid(_dock):
		_dock.set_facility(facility)


func _stamp_furniture_ids(node: Node, facility: Node) -> void:
	if node == null:
		return
	var local_id := str(node.name).to_snake_case()
	if "surface_id" in node:
		node.set("surface_id", local_id)
	if "container_id" in node:
		var facility_id := str(facility.get("facility_id")).strip_edges()
		if not facility_id.is_empty():
			node.set("container_id", "%s.%s" % [facility_id, local_id])
			if "facility_id" in node:
				node.set("facility_id", facility_id)
	# Haul offers are filtered by settlement, so a storage container with a
	# blank settlement_id is invisible to its own town's work queue.
	if "settlement_id" in node:
		var settlement_id := _facility_settlement_id(facility)
		if not settlement_id.is_empty():
			node.set("settlement_id", settlement_id)
	if "owner_faction_name" in node:
		var owner_faction_id := _facility_owner_faction_id(facility)
		if not owner_faction_id.is_empty():
			node.set("owner_faction_name", owner_faction_id)


func _facility_settlement_id(facility: Node) -> String:
	var current := facility.get_parent()
	while current != null:
		if current.has_method("get_settlement_id"):
			return str(current.call("get_settlement_id")).strip_edges()
		current = current.get_parent()
	return ""


func _own_facility_placement(node: Node, owner_root: Node) -> void:
	node.owner = owner_root
	_own_restored_children(node, owner_root)


func _facility_building(facility: Node) -> Node3D:
	var slot: Node3D = (facility as SettlementFacilityInstance).get_building_root()
	if slot == null or slot.get_child_count() == 0:
		return null
	return slot.get_child(0) as Node3D


## Furnish rules resolve through four visible tiers, first hit wins:
## the facility's own furnish_rules export, the owning faction's
## <faction>/<type>.tres, the type's <type>.tres, then default.tres.
## Returns {rules, tier, path, label} so the dock can show which tier won.
func resolve_furnish_rules(facility: Node) -> Dictionary:
	if facility == null or not is_instance_valid(facility):
		return {}
	var explicit = facility.get("furnish_rules")
	if explicit is Resource:
		var explicit_path := str((explicit as Resource).resource_path)
		return {
			"rules": explicit,
			"tier": "override",
			"path": explicit_path,
			"label": "%s (override)" % (explicit_path.get_file() if not explicit_path.is_empty() else "embedded"),
		}
	for candidate in _furnish_rule_candidates(facility):
		if ResourceLoader.exists(str(candidate["path"])):
			candidate["rules"] = load(str(candidate["path"]))
			return candidate
	return {}


## The convention tiers that do NOT exist yet for this facility — the dock
## offers a Create button per entry so authoring never requires the
## filesystem. The faction tier only appears once the facility has an owner
## faction to name the folder after.
func missing_furnish_rule_tiers(facility: Node) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	if facility == null or not is_instance_valid(facility):
		return missing
	for candidate in _furnish_rule_candidates(facility):
		if not ResourceLoader.exists(str(candidate["path"])):
			missing.append(candidate)
	return missing


## Create a tier's .tres seeded from whatever currently resolves (or blank
## rules when nothing does), then open it in the Inspector. Shallow copy on
## purpose: the new file references the same piece scenes and stock table
## rather than embedding duplicates.
func create_furnish_rules_file(facility: Node, tier: Dictionary) -> void:
	var path := str(tier.get("path", ""))
	if path.is_empty():
		return
	var resolved := resolve_furnish_rules(facility)
	var base: Resource = resolved.get("rules")
	var rules: Resource = base.duplicate(false) if base != null else FURNISH_RULES_SCRIPT.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := ResourceSaver.save(rules, path)
	if error != OK:
		_set_status("Failed to save %s (error %d)." % [path, error])
		return
	var editor := _plugin.get_editor_interface()
	editor.get_resource_filesystem().scan()
	editor.edit_resource(load(path))
	_set_status("Created %s — tune it in the Inspector, then Furnish." % path)


func _furnish_rule_candidates(facility: Node) -> Array[Dictionary]:
	var facility_type := str(facility.get("facility_type")).strip_edges()
	var candidates: Array[Dictionary] = []
	var faction_id := _facility_faction_id(facility)
	# Function first: several functions share one facility_type (a granary and
	# a warehouse are both "storage"), and they do not want the same floor.
	var function_id := _facility_function_id(facility)
	if not faction_id.is_empty() and not function_id.is_empty():
		candidates.append({
			"tier": "faction_function",
			"path": "%s/%s/%s.tres" % [FURNISH_RULES_DIR, faction_id, function_id],
			"label": "%s/%s.tres (faction function)" % [faction_id, function_id],
		})
	if not function_id.is_empty():
		candidates.append({
			"tier": "function",
			"path": "%s/%s.tres" % [FURNISH_RULES_DIR, function_id],
			"label": "%s.tres (function)" % function_id,
		})
	if not faction_id.is_empty() and not facility_type.is_empty():
		candidates.append({
			"tier": "faction",
			"path": "%s/%s/%s.tres" % [FURNISH_RULES_DIR, faction_id, facility_type],
			"label": "%s/%s.tres (faction)" % [faction_id, facility_type],
		})
	if not facility_type.is_empty():
		candidates.append({
			"tier": "type",
			"path": "%s/%s.tres" % [FURNISH_RULES_DIR, facility_type],
			"label": "%s.tres (type)" % facility_type,
		})
	candidates.append({
		"tier": "default",
		"path": "%s/default.tres" % FURNISH_RULES_DIR,
		"label": "default.tres (default)",
	})
	return candidates


func _facility_function_id(facility: Node) -> String:
	var function_resource: Resource = facility.get("facility_function") as Resource
	if function_resource == null:
		return ""
	return str(function_resource.get("function_id")).strip_edges()


func _facility_faction_id(facility: Node) -> String:
	if facility.has_method("get_property_owner_faction"):
		return str(facility.call("get_property_owner_faction")).strip_edges()
	var value = facility.get("owner_faction_id")
	return str(value).strip_edges() if value != null else ""


func _facility_owner_faction_id(facility: Node) -> String:
	return _facility_faction_id(facility)


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


## --- People ---------------------------------------------------------------------------


func set_facility_role_slots(facility: Node, role_slots: Variant, action_name: String) -> void:
	if facility == null or not _can_edit_live(facility):
		_set_status("Town is a locked instance — use Edit In Zone on the town first.")
		return
	var before = facility.get("role_slots").duplicate(true)
	var after = role_slots.duplicate(true)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action(action_name)
	undo_redo.add_do_property(facility, "role_slots", after)
	undo_redo.add_undo_property(facility, "role_slots", before)
	undo_redo.commit_action()
	if _dock != null and is_instance_valid(_dock):
		_dock.set_facility(facility)


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


func select_facility_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		_select_node(node)


## Ghost-place an authored guard stand spot under the facility's GuardPosts root.
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
	var posts_root := facility.get_node_or_null("GuardPosts") as Node3D
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Place Guard Post")
	if posts_root == null:
		posts_root = Node3D.new()
		posts_root.name = "GuardPosts"
		undo_redo.add_do_method(facility, "add_child", posts_root)
		undo_redo.add_do_method(posts_root, "set_owner", owner_root)
		undo_redo.add_undo_method(facility, "remove_child", posts_root)
		undo_redo.add_do_reference(posts_root)
	var post := GUARD_POST_SCENE.instantiate() as Node3D
	post.name = _unique_child_name(posts_root, "GuardPost")
	var parent_global := posts_root.global_transform if posts_root.is_inside_tree() else facility_3d.global_transform
	post.transform = parent_global.affine_inverse() * world_transform
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
	_active_container = null
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		_active_facility = _find_facility_ancestor(node)
		if node is WorldContainer:
			_active_container = node
		if _active_facility != null:
			break
	_refresh_ui()


## Innermost composed facility above the node.
func _find_facility_ancestor(node: Node) -> Node:
	var current := node
	while current != null:
		if current is SettlementFacilityInstance:
			return current
		current = current.get_parent()
	return null


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
		_dock.set_container(_active_container if _active_container != null and is_instance_valid(_active_container) else null)


## Facility roots expose the complete workspace; directly selected containers
## inside one also mount it so one-off stock never falls back to raw Inspector
## resource slots.
func wants_dock() -> bool:
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		if node is SettlementFacilityInstance or node is WorldContainer:
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
