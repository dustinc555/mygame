@tool
extends RefCounted

## WorldBuilding concept tool context for the world_authoring plugin.
## Owns the modular-piece toolbar and all piece authoring input (spawn, snap,
## rotate, copy/paste, hierarchy normalization). The plugin router creates one
## of these, mounts toolbar() in the spatial editor menu, and forwards
## editor callbacks through the concept-context contract:
## handles/claims_node/edit/refresh/is_active/process/shortcut_input/
## forward_3d_gui_input/on_selection_changed/on_scene_changed/teardown.

const CATALOG_PATH := "res://features/world/resources/building_pieces/quaternius/medieval_village_woodbrick/starter_woodbrick_catalog.tres"
const WORLD_BUILDING_ICON_PATH := "res://addons/world_authoring/icons/world_building.svg"
const WORLD_BUILDING_SCRIPT := preload("res://features/world/projection/buildings/world_building.gd")
const MODULAR_BUILDING_PIECE_SCRIPT := preload("res://features/world/projection/buildings/modular_building_piece.gd")

const SNAP_DISTANCE_METERS := 0.55
const ROTATION_STEP_RADIANS := PI * 0.5
const CATEGORY_GROUPS := [
	{"label": "Walls", "categories": ["wall"]},
	{"label": "Door Walls", "categories": ["wall_door"]},
	{"label": "Window Walls", "categories": ["wall_window"]},
	{"label": "Window Frames", "categories": ["window"]},
	{"label": "Doors", "categories": ["door"]},
	{"label": "Corners", "categories": ["corner"]},
	{"label": "Floors", "categories": ["floor"]},
	{"label": "Roofs", "categories": ["roof", "roof_front"]},
	{"label": "Stairs", "categories": ["stairs"]},
]

var _plugin: EditorPlugin
var _toolbar: HBoxContainer
var _status_label: Label
var _pieces_menu_button: MenuButton
var _rotate_button: Button
var _fix_hierarchy_button: Button
var _active_building: Node
var _watched_gizmo_anchor_piece: Node3D
var _last_gizmo_anchor_transform := Transform3D.IDENTITY
var _watched_gizmo_pieces: Array[Node3D] = []
var _applying_gizmo_snap := false
var _native_transform_mouse_down := false
var _copied_modular_piece_entries: Array[Dictionary] = []
var _last_handled_shortcut_event_id := 0
var _world_building_icon: Texture2D


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_build_toolbar()


func toolbar() -> Control:
	return _toolbar


func handles(object: Object) -> bool:
	if object is Node:
		return _find_world_building_ancestor(object as Node) != null
	return _find_world_building_from_edited_scene_root() != null


func claims_node(node: Node) -> bool:
	return _is_script_node(node, WORLD_BUILDING_SCRIPT)


func edit(object: Object) -> void:
	if object is Node:
		_active_building = _find_world_building_ancestor(object as Node)
	if _active_building == null:
		_active_building = _find_world_building_from_edited_scene_root()
	_refresh_toolbar()


func refresh() -> void:
	_refresh_active_building_context()


func is_active() -> bool:
	return get_active_building() != null


func on_selection_changed() -> void:
	_refresh_active_building_context()


func on_scene_changed(_scene_root: Node) -> void:
	_refresh_active_building_context()


func process(_delta: float) -> void:
	_snap_selected_gizmo_motion_to_grid()


func teardown() -> void:
	if _toolbar != null:
		_toolbar.free()
		_toolbar = null
	_active_building = null
	_clear_gizmo_watch()
	_native_transform_mouse_down = false
	_plugin = null


func get_active_building() -> Node:
	if _active_building != null and is_instance_valid(_active_building):
		return _active_building
	_active_building = _find_world_building_from_edited_scene_root()
	return _active_building if _active_building != null and is_instance_valid(_active_building) else null


func get_active_piece_definition() -> Resource:
	return null


func set_active_piece_definition(piece: Resource) -> void:
	if piece != null:
		_spawn_piece(piece, _get_default_spawn_position())
	_refresh_toolbar()


func clear_active_piece_definition() -> void:
	_refresh_toolbar()


func rotate_selected_piece() -> void:
	if not _can_author_building(get_active_building()):
		return
	var pieces := _get_selected_modular_pieces()
	if pieces.is_empty():
		return
	var old_transforms: Array[Transform3D] = []
	for piece in pieces:
		old_transforms.append(piece.global_transform)
	for piece in pieces:
		piece.rotate_y(ROTATION_STEP_RADIANS)
		if _piece_auto_snap_enabled(piece):
			piece.global_transform = _snap_piece_transform_to_grid(piece, piece.global_transform)
			_snap_piece_to_nearest(piece)
	var new_transforms: Array[Transform3D] = []
	for piece in pieces:
		new_transforms.append(piece.global_transform)
	_commit_transform_changes(pieces, old_transforms, new_transforms, "Rotate Modular Building Pieces")


func fix_active_building_hierarchy() -> void:
	var building := get_active_building()
	if _can_author_building(building):
		_normalize_modular_piece_hierarchy(building)
	_refresh_toolbar()


func forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if get_active_building() == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if _handle_modular_copy_paste_shortcut(key_event):
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if key_event.keycode == KEY_R:
			rotate_selected_piece()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton:
		return _handle_mouse_button(camera, event as InputEventMouseButton)
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func shortcut_input(event: InputEvent) -> bool:
	return event is InputEventKey and _handle_modular_copy_paste_shortcut(event as InputEventKey)


func _handle_modular_copy_paste_shortcut(key_event: InputEventKey) -> bool:
	if not key_event.pressed or key_event.echo or not _is_control_or_meta_pressed(key_event):
		return false
	var event_id := key_event.get_instance_id()
	if event_id == _last_handled_shortcut_event_id:
		return true
	if _is_text_input_focused():
		return false
	if not _can_author_building(get_active_building()):
		return false
	match key_event.keycode:
		KEY_C:
			_copy_selected_modular_pieces()
			_last_handled_shortcut_event_id = event_id
			return true
		KEY_V:
			_paste_copied_modular_pieces()
			_last_handled_shortcut_event_id = event_id
			return true
	return false


func _handle_mouse_button(camera: Camera3D, event: InputEventMouseButton) -> int:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event.pressed:
		var selected_pieces := _get_selected_modular_pieces()
		_native_transform_mouse_down = not selected_pieces.is_empty()
		if not selected_pieces.is_empty():
			_watch_gizmo_selection(selected_pieces)
	if not event.pressed and _native_transform_mouse_down:
		_native_transform_mouse_down = false
		_snap_selected_gizmo_motion_to_grid()
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _snap_selected_gizmo_motion_to_grid() -> void:
	if _applying_gizmo_snap:
		return
	if not _can_author_building(get_active_building()):
		return
	var pieces := _get_selected_modular_pieces()
	if pieces.is_empty():
		_clear_gizmo_watch()
		return
	if not _is_same_gizmo_selection(pieces):
		_watch_gizmo_selection(pieces)
		return
	if _watched_gizmo_anchor_piece == null or not is_instance_valid(_watched_gizmo_anchor_piece):
		_clear_gizmo_watch()
		return
	var current_anchor_transform := _watched_gizmo_anchor_piece.global_transform
	if current_anchor_transform == _last_gizmo_anchor_transform:
		return
	if _native_transform_mouse_down:
		return
	if not _all_pieces_auto_snap_enabled(pieces):
		_watch_gizmo_selection(pieces)
		return
	var old_transforms: Array[Transform3D] = []
	for piece in pieces:
		old_transforms.append(piece.global_transform)
	var snap_delta := Vector3.ZERO
	var marker_delta: Variant = _get_piece_nearest_snap_delta(_watched_gizmo_anchor_piece, SNAP_DISTANCE_METERS, pieces)
	if marker_delta != null:
		snap_delta = marker_delta
	else:
		var snapped_anchor_transform := _snap_piece_transform_to_grid(_watched_gizmo_anchor_piece, current_anchor_transform)
		snap_delta = snapped_anchor_transform.origin - current_anchor_transform.origin
	if snap_delta.length_squared() > 0.000001:
		_applying_gizmo_snap = true
		for piece in pieces:
			piece.global_position += snap_delta
		_applying_gizmo_snap = false
		var new_transforms: Array[Transform3D] = []
		for piece in pieces:
			new_transforms.append(piece.global_transform)
		_commit_transform_changes(pieces, old_transforms, new_transforms, "Snap Modular Building Pieces")
	_watch_gizmo_selection(pieces)


func _watch_gizmo_selection(pieces: Array[Node3D]) -> void:
	_watched_gizmo_pieces.clear()
	if pieces.is_empty():
		_watched_gizmo_anchor_piece = null
		_last_gizmo_anchor_transform = Transform3D.IDENTITY
		return
	_watched_gizmo_anchor_piece = pieces[0]
	_last_gizmo_anchor_transform = _watched_gizmo_anchor_piece.global_transform
	for piece in pieces:
		_watched_gizmo_pieces.append(piece)


func _clear_gizmo_watch() -> void:
	_watched_gizmo_anchor_piece = null
	_last_gizmo_anchor_transform = Transform3D.IDENTITY
	_watched_gizmo_pieces.clear()


func _is_same_gizmo_selection(pieces: Array[Node3D]) -> bool:
	if pieces.size() != _watched_gizmo_pieces.size():
		return false
	for index in range(pieces.size()):
		if pieces[index] != _watched_gizmo_pieces[index] or not is_instance_valid(pieces[index]):
			return false
	return true


func _spawn_piece(piece_definition: Resource, world_position: Vector3) -> void:
	var scene := piece_definition.get("scene") as PackedScene
	if scene == null:
		return
	var building := get_active_building()
	if not _can_author_building(building):
		return
	var parent := _get_or_create_pieces_root(building)
	if parent == null:
		return
	var piece := scene.instantiate() as Node3D
	if piece == null:
		return
	piece.name = _unique_child_name(parent, str(piece_definition.get("piece_id")).to_pascal_case())
	var desired_transform := piece.global_transform
	desired_transform.origin = world_position
	piece.global_transform = desired_transform
	if _piece_auto_snap_enabled(piece) and not _snap_new_piece_to_selected_piece(piece):
		_place_piece_near_world_position(piece, world_position)
	piece.transform = parent.global_transform.affine_inverse() * piece.global_transform
	var edited_root := _plugin.get_editor_interface().get_edited_scene_root()
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Add Modular Building Piece")
	undo_redo.add_do_method(parent, "add_child", piece)
	undo_redo.add_do_method(piece, "set_owner", edited_root)
	if building.has_method("invalidate_modular_piece_cache"):
		undo_redo.add_do_method(building, "invalidate_modular_piece_cache")
	undo_redo.add_undo_method(parent, "remove_child", piece)
	if building.has_method("invalidate_modular_piece_cache"):
		undo_redo.add_undo_method(building, "invalidate_modular_piece_cache")
	undo_redo.add_do_reference(piece)
	undo_redo.commit_action()
	_select_node(piece)


func _place_piece_near_world_position(piece: Node3D, world_position: Vector3) -> void:
	var free_transform := piece.global_transform
	free_transform.origin = world_position
	piece.global_transform = free_transform
	if _snap_piece_to_nearest(piece):
		return
	piece.global_transform = _snap_piece_transform_to_grid(piece, piece.global_transform)


func _snap_piece_to_nearest(piece: Node3D, max_distance: float = SNAP_DISTANCE_METERS, excluded_pieces: Array = []) -> bool:
	var snap_result := _get_piece_nearest_snap_result(piece, max_distance, excluded_pieces)
	if snap_result.is_empty():
		return false
	piece.global_transform = snap_result["transform"]
	return true


func _get_piece_nearest_snap_delta(piece: Node3D, max_distance: float = SNAP_DISTANCE_METERS, excluded_pieces: Array = []) -> Variant:
	var snap_result := _get_piece_nearest_snap_result(piece, max_distance, excluded_pieces)
	if snap_result.is_empty():
		return null
	var snap_transform: Transform3D = snap_result["transform"]
	return snap_transform.origin - piece.global_transform.origin


func _get_piece_nearest_snap_result(piece: Node3D, max_distance: float = SNAP_DISTANCE_METERS, excluded_pieces: Array = []) -> Dictionary:
	if piece == null or not piece.has_method("get_snap_markers"):
		return {}
	var best_distance := INF
	var best_transform := Transform3D.IDENTITY
	var found := false
	for source_marker in piece.call("get_snap_markers"):
		if not (source_marker is Node3D):
			continue
		for target_marker in _get_other_snap_markers(piece, excluded_pieces):
			if not _snap_markers_compatible(source_marker, target_marker):
				continue
			var delta := (target_marker as Node3D).global_position - (source_marker as Node3D).global_position
			var distance := delta.length()
			if distance < best_distance:
				best_distance = distance
				best_transform = _get_piece_snap_transform(piece, source_marker, target_marker)
				found = true
	if found and best_distance <= max_distance:
		return {"transform": best_transform, "distance": best_distance}
	return {}


func _snap_new_piece_to_selected_piece(piece: Node3D) -> bool:
	var selected_piece := _get_selected_modular_piece()
	if selected_piece == null or selected_piece == piece or not selected_piece.has_method("get_snap_markers") or not piece.has_method("get_snap_markers"):
		return false
	var best_score := INF
	var best_transform := Transform3D.IDENTITY
	var found := false
	for source_marker in piece.call("get_snap_markers"):
		if not (source_marker is Node3D):
			continue
		for target_marker in selected_piece.call("get_snap_markers"):
			if not _snap_markers_compatible(source_marker, target_marker):
				continue
			var delta := (target_marker as Node3D).global_position - (source_marker as Node3D).global_position
			var score := _new_piece_snap_score(source_marker, target_marker) + delta.length() * 0.01
			if score < best_score:
				best_score = score
				best_transform = _get_piece_snap_transform(piece, source_marker, target_marker)
				found = true
	if found:
		piece.global_transform = best_transform
	return found


func _new_piece_snap_score(source_marker: Node, target_marker: Node) -> float:
	var source_type := str(source_marker.get("connector_type"))
	var target_type := str(target_marker.get("connector_type"))
	var target_id := str(target_marker.get("snap_id"))
	if _snap_markers_align_transform(source_marker, target_marker):
		return 0.0
	if source_type == "wall_bottom" and target_type == "floor_edge":
		return 0.0 if target_id == "south" else 5.0
	return 10.0


func _get_other_snap_markers(piece: Node3D, excluded_pieces: Array = []) -> Array:
	var result: Array = []
	var building := get_active_building()
	if building == null or not building.has_method("get_modular_pieces"):
		return result
	for other_piece in building.call("get_modular_pieces"):
		if other_piece == piece or excluded_pieces.has(other_piece) or not is_instance_valid(other_piece) or not other_piece.has_method("get_snap_markers"):
			continue
		result.append_array(other_piece.call("get_snap_markers"))
	return result


func _snap_markers_compatible(source_marker: Node, target_marker: Node) -> bool:
	var source_type := str(source_marker.get("connector_type"))
	var target_type := str(target_marker.get("connector_type"))
	var source_accepts: PackedStringArray = source_marker.get("accepts_types")
	var target_accepts: PackedStringArray = target_marker.get("accepts_types")
	return source_accepts.has(target_type) or target_accepts.has(source_type)


func _get_piece_snap_transform(piece: Node3D, source_marker: Node, target_marker: Node) -> Transform3D:
	var snapped_transform := piece.global_transform
	var source_marker_3d := source_marker as Node3D
	var target_marker_3d := target_marker as Node3D
	if source_marker_3d == null or target_marker_3d == null:
		return snapped_transform
	if _snap_markers_align_transform(source_marker, target_marker):
		var source_local_transform := piece.global_transform.affine_inverse() * source_marker_3d.global_transform
		return target_marker_3d.global_transform * source_local_transform.affine_inverse()
	snapped_transform.origin += target_marker_3d.global_position - source_marker_3d.global_position
	return snapped_transform


func _snap_markers_align_transform(source_marker: Node, target_marker: Node) -> bool:
	var source_type := str(source_marker.get("connector_type"))
	var target_type := str(target_marker.get("connector_type"))
	return (source_type == "window_insert" and target_type == "window_socket") or (source_type == "window_socket" and target_type == "window_insert") or (source_type == "door_insert" and target_type == "door_socket") or (source_type == "door_socket" and target_type == "door_insert")


func _snap_piece_transform_to_grid(piece: Node3D, source_transform: Transform3D) -> Transform3D:
	var snapped := source_transform
	snapped.origin = _snap_world_position_to_grid(piece, source_transform.origin)
	return snapped


func _snap_world_position_to_grid(piece: Node3D, world_position: Vector3) -> Vector3:
	var building := get_active_building() as Node3D
	if building == null:
		return world_position
	var grid_size := _grid_size_for_piece(piece)
	var local_position := building.to_local(world_position)
	local_position.x = roundf(local_position.x / grid_size) * grid_size
	local_position.y = roundf(local_position.y / grid_size) * grid_size
	local_position.z = roundf(local_position.z / grid_size) * grid_size
	return building.to_global(local_position)


func _grid_size_for_piece(piece: Node) -> float:
	if piece != null:
		var value = piece.get("grid_cell_size_meters")
		if value != null:
			return maxf(0.25, float(value))
	return 2.0


func _get_default_spawn_position() -> Vector3:
	var selected_piece := _get_selected_modular_piece()
	if selected_piece != null:
		return selected_piece.global_position
	var building := get_active_building() as Node3D
	return building.global_position if building != null else Vector3.ZERO


func _get_or_create_pieces_root(building: Node) -> Node3D:
	if building.has_method("get_or_create_modular_pieces_root"):
		var root := building.call("get_or_create_modular_pieces_root") as Node3D
		_ensure_scene_owner(root)
		return root
	var pieces_root := building.get_node_or_null("Pieces") as Node3D
	if pieces_root != null:
		_ensure_scene_owner(pieces_root)
		return pieces_root
	pieces_root = Node3D.new()
	pieces_root.name = "Pieces"
	building.add_child(pieces_root)
	_ensure_scene_owner(pieces_root)
	return pieces_root


func _ensure_scene_owner(node: Node) -> void:
	if node == null:
		return
	var edited_root := _plugin.get_editor_interface().get_edited_scene_root()
	if edited_root != null and node != edited_root:
		node.owner = edited_root


func _commit_transform_change(piece: Node3D, old_transform: Transform3D, new_transform: Transform3D, action_name: String) -> void:
	if piece == null or old_transform == new_transform:
		return
	_commit_transform_changes([piece], [old_transform], [new_transform], action_name)


func _commit_transform_changes(pieces: Array, old_transforms: Array, new_transforms: Array, action_name: String) -> void:
	if pieces.is_empty() or pieces.size() != old_transforms.size() or pieces.size() != new_transforms.size():
		return
	var changed := false
	for index in range(pieces.size()):
		if pieces[index] != null and old_transforms[index] != new_transforms[index]:
			changed = true
			break
	if not changed:
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action(action_name)
	for index in range(pieces.size()):
		var piece := pieces[index] as Node3D
		if piece == null or old_transforms[index] == new_transforms[index]:
			continue
		undo_redo.add_do_property(piece, "global_transform", new_transforms[index])
		undo_redo.add_undo_property(piece, "global_transform", old_transforms[index])
	undo_redo.commit_action()


func _copy_selected_modular_pieces() -> bool:
	var building := get_active_building() as Node3D
	if not _can_author_building(building):
		return false
	_copied_modular_piece_entries.clear()
	var pieces := _get_selected_modular_pieces()
	if pieces.is_empty():
		return false
	var building_inverse := building.global_transform.affine_inverse()
	for piece in pieces:
		var scene_path := piece.scene_file_path
		if scene_path.is_empty():
			continue
		_copied_modular_piece_entries.append({
			"scene_path": scene_path,
			"source_name": str(piece.name),
			"local_transform": building_inverse * piece.global_transform,
		})
	return true


func _paste_copied_modular_pieces() -> bool:
	var building := get_active_building() as Node3D
	if not _can_author_building(building) or _copied_modular_piece_entries.is_empty():
		return false
	var parent := _get_or_create_pieces_root(building)
	if parent == null:
		return false
	var edited_root := _plugin.get_editor_interface().get_edited_scene_root()
	var pieces_to_add: Array[Node3D] = []
	for entry in _copied_modular_piece_entries:
		var scene_path := str(entry.get("scene_path", ""))
		if scene_path.is_empty():
			continue
		var scene := load(scene_path) as PackedScene
		if scene == null:
			continue
		var copy := scene.instantiate() as Node3D
		if copy == null:
			continue
		copy.name = _unique_child_name(parent, str(entry.get("source_name", copy.name)))
		var local_transform: Transform3D = entry.get("local_transform", Transform3D.IDENTITY)
		copy.transform = parent.global_transform.affine_inverse() * (building.global_transform * local_transform)
		pieces_to_add.append(copy)
	if pieces_to_add.is_empty():
		return false
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Paste Modular Building Pieces")
	for copy in pieces_to_add:
		undo_redo.add_do_method(parent, "add_child", copy)
		undo_redo.add_do_method(copy, "set_owner", edited_root)
		undo_redo.add_undo_method(parent, "remove_child", copy)
		undo_redo.add_do_reference(copy)
	if building.has_method("invalidate_modular_piece_cache"):
		undo_redo.add_do_method(building, "invalidate_modular_piece_cache")
		undo_redo.add_undo_method(building, "invalidate_modular_piece_cache")
	undo_redo.commit_action()
	_select_nodes(pieces_to_add)
	call_deferred("_select_nodes", pieces_to_add)
	return true


func _refresh_active_building_context() -> void:
	_active_building = _find_world_building_from_selection()
	if _active_building == null:
		_active_building = _find_world_building_from_edited_scene_root()
	if _can_author_building(_active_building):
		_normalize_modular_piece_hierarchy(_active_building)
	_refresh_toolbar()


func _can_author_building(building: Node) -> bool:
	if building == null:
		return false
	return building == _plugin.get_editor_interface().get_edited_scene_root()


func _normalize_modular_piece_hierarchy(building: Node) -> void:
	if building == null:
		return
	var pieces_root := _get_or_create_pieces_root(building)
	if pieces_root == null:
		return
	var pieces: Array = []
	for selected_node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		var selected_piece := _find_modular_piece_ancestor(selected_node)
		if selected_piece != null and not pieces.has(selected_piece):
			pieces.append(selected_piece)
	_append_modular_pieces_under(pieces_root, pieces)
	for piece_node in pieces:
		var piece := piece_node as Node3D
		if piece == null or not is_instance_valid(piece) or piece.get_parent() == pieces_root:
			continue
		var global_transform := piece.global_transform
		var old_parent := piece.get_parent()
		if old_parent != null:
			old_parent.remove_child(piece)
		if pieces_root.get_node_or_null(str(piece.name)) != null:
			piece.name = _unique_child_name(pieces_root, str(piece.name))
		pieces_root.add_child(piece)
		_ensure_scene_owner(piece)
		piece.global_transform = global_transform
	if building.has_method("invalidate_modular_piece_cache"):
		building.call("invalidate_modular_piece_cache")


func _append_modular_pieces_under(node: Node, result: Array) -> void:
	if node == null:
		return
	if _is_script_node(node, MODULAR_BUILDING_PIECE_SCRIPT) and not result.has(node):
		result.append(node)
	for child in node.get_children():
		_append_modular_pieces_under(child, result)


func _find_world_building_from_selection() -> Node:
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		var building := _find_world_building_ancestor(node)
		if building != null:
			return building
	return null


func _find_world_building_from_edited_scene_root() -> Node:
	return _find_world_building_ancestor(_plugin.get_editor_interface().get_edited_scene_root())


func _find_world_building_ancestor(node: Node) -> Node:
	var current := node
	while current != null:
		if _is_script_node(current, WORLD_BUILDING_SCRIPT):
			return current
		current = current.get_parent()
	return null


func _get_selected_modular_piece() -> Node3D:
	var pieces := _get_selected_modular_pieces()
	return pieces[0] if not pieces.is_empty() else null


func _get_selected_modular_pieces() -> Array[Node3D]:
	var pieces: Array[Node3D] = []
	for node in _plugin.get_editor_interface().get_selection().get_selected_nodes():
		var piece := _find_modular_piece_ancestor(node)
		if piece != null and not pieces.has(piece):
			pieces.append(piece)
		elif node is Node:
			_append_modular_pieces_under(node as Node, pieces)
	return pieces


func _is_control_or_meta_pressed(key_event: InputEventKey) -> bool:
	return key_event.ctrl_pressed or key_event.meta_pressed


func _is_text_input_focused() -> bool:
	var base_control := _plugin.get_editor_interface().get_base_control()
	if base_control == null:
		return false
	var focus_owner := base_control.get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _find_modular_piece_ancestor(node: Node) -> Node3D:
	var current := node
	while current != null:
		if _is_script_node(current, MODULAR_BUILDING_PIECE_SCRIPT):
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
	_select_nodes([node])


func _select_nodes(nodes: Array) -> void:
	var selection := _plugin.get_editor_interface().get_selection()
	selection.clear()
	var first_node: Node = null
	for node in nodes:
		if not (node is Node) or not is_instance_valid(node):
			continue
		if first_node == null:
			first_node = node
		selection.add_node(node)
	if first_node != null and nodes.size() == 1:
		_plugin.get_editor_interface().edit_node(first_node)


func _unique_child_name(parent: Node, base_name: String) -> String:
	var cleaned := base_name if not base_name.is_empty() else "ModularPiece"
	var candidate := cleaned
	var index := 2
	while parent.get_node_or_null(candidate) != null:
		candidate = "%s%d" % [cleaned, index]
		index += 1
	return candidate


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "ModularBuildingToolbar"
	_toolbar.visible = true
	_toolbar.add_theme_constant_override("separation", 6)

	_status_label = Label.new()
	_status_label.text = "Building: none"
	_status_label.tooltip_text = "Open a WorldBuilding scene, or select a WorldBuilding/modular piece."
	_toolbar.add_child(_status_label)

	_add_piece_drawer()

	_rotate_button = Button.new()
	_rotate_button.text = "Rot 90"
	_rotate_button.tooltip_text = "Rotate selected modular piece. Shortcut: R."
	_rotate_button.pressed.connect(_on_rotate_selected_pressed)
	_toolbar.add_child(_rotate_button)

	_fix_hierarchy_button = Button.new()
	_fix_hierarchy_button.text = "Fix Hierarchy"
	_fix_hierarchy_button.tooltip_text = "Move copied modular pieces back under Pieces as siblings."
	_fix_hierarchy_button.pressed.connect(_on_fix_hierarchy_pressed)
	_toolbar.add_child(_fix_hierarchy_button)

	_refresh_toolbar()


func _add_piece_drawer() -> void:
	# One "Building Pieces" drawer with a submenu per category (Terrain3D-style),
	# instead of a row of category buttons cluttering the spatial menu bar.
	var catalog = load(CATALOG_PATH)
	if catalog == null:
		return
	var pieces_by_category := {}
	for piece in catalog.get("pieces"):
		if piece == null:
			continue
		var category := str(piece.get("category"))
		if not pieces_by_category.has(category):
			pieces_by_category[category] = []
		pieces_by_category[category].append(piece)
	_pieces_menu_button = MenuButton.new()
	_pieces_menu_button.text = "Building Pieces"
	_pieces_menu_button.icon = _get_world_building_icon()
	_pieces_menu_button.tooltip_text = "Spawn a modular building piece"
	_toolbar.add_child(_pieces_menu_button)
	var root_popup := _pieces_menu_button.get_popup()
	for group in CATEGORY_GROUPS:
		var pieces: Array = []
		for category in group["categories"]:
			pieces.append_array(pieces_by_category.get(category, []))
		if pieces.is_empty():
			continue
		var label := str(group["label"])
		var submenu := PopupMenu.new()
		submenu.name = label
		for index in range(pieces.size()):
			var piece: Resource = pieces[index]
			submenu.add_item(str(piece.get("display_name")), index)
			submenu.set_item_tooltip(index, str(piece.get("piece_id")))
		submenu.id_pressed.connect(_on_piece_menu_item_pressed.bind(pieces))
		root_popup.add_child(submenu)
		root_popup.add_submenu_item(label, label)


func _get_world_building_icon() -> Texture2D:
	if _world_building_icon != null:
		return _world_building_icon
	var icon_bytes := FileAccess.get_file_as_bytes(WORLD_BUILDING_ICON_PATH)
	if icon_bytes.size() == 0:
		return null
	var image := Image.new()
	if image.load_svg_from_buffer(icon_bytes) != OK:
		return null
	_world_building_icon = ImageTexture.create_from_image(image)
	return _world_building_icon


func _refresh_toolbar() -> void:
	if _toolbar == null:
		return
	var building := get_active_building()
	var has_building := building != null
	var can_author := _can_author_building(building)
	# Only show the building toolbar when a WorldBuilding is actually in play — not
	# while Terrain3D or unrelated nodes are selected.
	_toolbar.visible = has_building
	_status_label.text = "Building: %s" % (building.name if has_building else "open/select WorldBuilding")
	if has_building and not can_author:
		_status_label.text = "Building: open source scene to edit"
	for child in _toolbar.get_children():
		if child is MenuButton:
			(child as MenuButton).disabled = not can_author
	var selected_piece := _get_selected_modular_piece()
	_rotate_button.disabled = selected_piece == null or not can_author
	_fix_hierarchy_button.disabled = not can_author


func _piece_auto_snap_enabled(piece: Node) -> bool:
	return piece != null and piece.get("auto_snap_enabled") != false


func _all_pieces_auto_snap_enabled(pieces: Array[Node3D]) -> bool:
	for piece in pieces:
		if not _piece_auto_snap_enabled(piece):
			return false
	return true


func _on_piece_menu_item_pressed(item_id: int, pieces: Array) -> void:
	if item_id < 0 or item_id >= pieces.size():
		return
	set_active_piece_definition(pieces[item_id] as Resource)


func _on_rotate_selected_pressed() -> void:
	rotate_selected_piece()
	_refresh_toolbar()


func _on_fix_hierarchy_pressed() -> void:
	fix_active_building_hierarchy()
