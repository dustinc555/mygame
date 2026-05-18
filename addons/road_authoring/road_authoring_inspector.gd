@tool
extends EditorInspectorPlugin

# Dustin's road authoring inspector controls for RoadNetwork waypoint graphs.

const ROAD_NETWORK_SCRIPT = preload("res://scripts/world_sim/road_network.gd")
const ROAD_WAYPOINT_SCRIPT = preload("res://scripts/world_sim/road_waypoint.gd")
const NEW_WAYPOINT_OFFSET = Vector3(4.0, 0.0, 0.0)

var _plugin: EditorPlugin


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _can_handle(object: Object) -> bool:
	return object is Node and (_is_network(object as Node) or _is_waypoint(object as Node))


func _parse_begin(object: Object) -> void:
	var node := object as Node
	if node == null:
		return
	if _is_network(node):
		add_custom_control(_build_network_panel(node))
	elif _is_waypoint(node):
		add_custom_control(_build_waypoint_panel(node))


func _build_network_panel(network: Node) -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Road Authoring"
	root.add_child(title)

	var create_button := Button.new()
	create_button.text = "Create First Waypoint"
	create_button.tooltip_text = "Create an unconnected waypoint under this RoadNetwork."
	create_button.pressed.connect(_on_create_first_waypoint.bind(network))
	root.add_child(create_button)

	var ensure_button := Button.new()
	ensure_button.text = "Ensure All Waypoint IDs"
	ensure_button.tooltip_text = "Fill missing waypoint IDs and replace duplicate waypoint IDs."
	ensure_button.pressed.connect(_on_ensure_ids.bind(network))
	root.add_child(ensure_button)

	return root


func _build_waypoint_panel(waypoint: Node) -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Road Authoring"
	root.add_child(title)

	var source_label := Label.new()
	source_label.text = _connection_source_label()
	root.add_child(source_label)

	var create_button := Button.new()
	create_button.text = "Create Additional Waypoint From This"
	create_button.tooltip_text = "Create a sibling waypoint, connect this waypoint to it, and select the new waypoint."
	create_button.disabled = _find_network(waypoint) == null
	create_button.pressed.connect(_on_create_connected_waypoint.bind(waypoint))
	root.add_child(create_button)

	var set_source_button := Button.new()
	set_source_button.text = "Set As Connection Source"
	set_source_button.tooltip_text = "Use this waypoint as the source for the next Connect From Source action."
	set_source_button.pressed.connect(_on_set_connection_source.bind(waypoint))
	root.add_child(set_source_button)

	var connect_button := Button.new()
	connect_button.text = "Connect From Source"
	connect_button.tooltip_text = "Connect the stored source waypoint to this waypoint."
	connect_button.disabled = not _can_connect_from_source(waypoint)
	connect_button.pressed.connect(_on_connect_from_source.bind(waypoint))
	root.add_child(connect_button)

	var ensure_button := Button.new()
	ensure_button.text = "Ensure Network IDs"
	ensure_button.tooltip_text = "Fill missing waypoint IDs and replace duplicate waypoint IDs in this RoadNetwork."
	ensure_button.disabled = _find_network(waypoint) == null
	ensure_button.pressed.connect(_on_ensure_ids.bind(_find_network(waypoint)))
	root.add_child(ensure_button)

	var delete_button := Button.new()
	delete_button.text = "Delete This Waypoint"
	delete_button.tooltip_text = "Remove this waypoint and clean every connection path that points at it."
	delete_button.disabled = _find_network(waypoint) == null or waypoint.get_parent() == null
	delete_button.pressed.connect(_on_delete_waypoint.bind(waypoint))
	root.add_child(delete_button)

	return root


func _on_create_first_waypoint(network: Node) -> void:
	var parent := network as Node3D
	if parent == null:
		return
	var waypoint := _make_waypoint(parent, network, parent.global_position)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Create Road Waypoint")
	_add_waypoint_do_undo(undo_redo, parent, waypoint, network)
	undo_redo.commit_action()
	_plugin.call("select_node", waypoint)
	if waypoint.has_method("refresh_debug"):
		waypoint.call("refresh_debug")


func _on_create_connected_waypoint(source: Node) -> void:
	var source_node := source as Node3D
	var parent := source.get_parent() as Node3D
	var network := _find_network(source)
	if source_node == null or parent == null or network == null:
		return
	var waypoint := _make_waypoint(parent, network, source_node.global_position + NEW_WAYPOINT_OFFSET)
	var old_paths: Array = source.get("connected_waypoint_paths").duplicate()
	var new_paths: Array = old_paths.duplicate()
	var path_to_new := NodePath("../%s" % waypoint.name)
	if not new_paths.has(path_to_new):
		new_paths.append(path_to_new)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Create Connected Road Waypoint")
	_add_waypoint_do_undo(undo_redo, parent, waypoint, network)
	undo_redo.add_do_property(source, "connected_waypoint_paths", new_paths)
	undo_redo.add_undo_property(source, "connected_waypoint_paths", old_paths)
	undo_redo.add_do_method(source, "notify_property_list_changed")
	undo_redo.add_undo_method(source, "notify_property_list_changed")
	undo_redo.add_do_method(network, "refresh_debug")
	undo_redo.add_undo_method(network, "refresh_debug")
	undo_redo.commit_action()
	_plugin.call("select_node", waypoint)
	if waypoint.has_method("refresh_debug"):
		waypoint.call("refresh_debug")


func _on_set_connection_source(waypoint: Node) -> void:
	_plugin.call("set_connection_source", waypoint)


func _on_connect_from_source(target: Node) -> void:
	var source: Node = _plugin.call("get_connection_source")
	if source == null or target == null or not _can_connect_from_source(target):
		return
	var old_paths: Array = source.get("connected_waypoint_paths").duplicate()
	var new_paths: Array = source.call("get_connection_paths_with", target)
	var network := _find_network(target)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Connect Road Waypoints")
	undo_redo.add_do_property(source, "connected_waypoint_paths", new_paths)
	undo_redo.add_undo_property(source, "connected_waypoint_paths", old_paths)
	undo_redo.add_do_method(source, "notify_property_list_changed")
	undo_redo.add_undo_method(source, "notify_property_list_changed")
	if network != null:
		undo_redo.add_do_method(network, "refresh_debug")
		undo_redo.add_undo_method(network, "refresh_debug")
	undo_redo.commit_action()


func _on_ensure_ids(network: Node) -> void:
	if network == null or not network.has_method("get_waypoints"):
		return
	var changes := _id_changes_for_network(network)
	if changes.is_empty():
		return
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Ensure Road Waypoint IDs")
	for change in changes:
		var waypoint: Node = change.get("waypoint")
		undo_redo.add_do_property(waypoint, "waypoint_id", str(change.get("new_id", "")))
		undo_redo.add_undo_property(waypoint, "waypoint_id", str(change.get("old_id", "")))
		undo_redo.add_do_method(waypoint, "notify_property_list_changed")
		undo_redo.add_undo_method(waypoint, "notify_property_list_changed")
	undo_redo.commit_action()


func _on_delete_waypoint(waypoint: Node) -> void:
	var network := _find_network(waypoint)
	var parent := waypoint.get_parent()
	if network == null or parent == null:
		return
	var owner := waypoint.owner
	var child_index := waypoint.get_index()
	var reference_changes := _reference_cleanup_changes(network, waypoint)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Delete Road Waypoint")
	for change in reference_changes:
		var source: Node = change.get("source")
		undo_redo.add_do_property(source, "connected_waypoint_paths", change.get("new_paths", []))
		undo_redo.add_undo_property(source, "connected_waypoint_paths", change.get("old_paths", []))
		undo_redo.add_do_method(source, "notify_property_list_changed")
		undo_redo.add_undo_method(source, "notify_property_list_changed")
	undo_redo.add_do_method(parent, "remove_child", waypoint)
	undo_redo.add_undo_method(parent, "add_child", waypoint)
	undo_redo.add_undo_method(parent, "move_child", waypoint, child_index)
	undo_redo.add_undo_method(waypoint, "set_owner", owner)
	undo_redo.add_do_method(network, "refresh_debug")
	undo_redo.add_undo_method(network, "refresh_debug")
	undo_redo.add_undo_reference(waypoint)
	undo_redo.commit_action()
	if _plugin.call("get_connection_source") == waypoint:
		_plugin.call("set_connection_source", null)
	_plugin.call("select_node", network)


func _make_waypoint(parent: Node3D, network: Node, world_position: Vector3) -> Node3D:
	var waypoint := MeshInstance3D.new()
	waypoint.name = _unique_child_name(parent, "Waypoint")
	waypoint.set_script(ROAD_WAYPOINT_SCRIPT)
	waypoint.position = parent.to_local(world_position)
	waypoint.set("waypoint_id", network.call("allocate_waypoint_id"))
	return waypoint


func _add_waypoint_do_undo(undo_redo: EditorUndoRedoManager, parent: Node, waypoint: Node, network: Node) -> void:
	var edited_root := _plugin.get_editor_interface().get_edited_scene_root()
	undo_redo.add_do_method(parent, "add_child", waypoint)
	undo_redo.add_do_method(waypoint, "set_owner", edited_root)
	undo_redo.add_do_method(waypoint, "refresh_debug")
	if network != null:
		undo_redo.add_do_method(network, "refresh_debug")
		undo_redo.add_undo_method(network, "refresh_debug")
	undo_redo.add_undo_method(parent, "remove_child", waypoint)
	undo_redo.add_do_reference(waypoint)


func _id_changes_for_network(network: Node) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var reserved_ids: Array = []
	var seen_ids := {}
	for waypoint in network.call("get_waypoints"):
		if waypoint == null:
			continue
		var old_id := str(waypoint.get("waypoint_id"))
		if old_id.is_empty() or seen_ids.has(old_id):
			var new_id := str(network.call("allocate_waypoint_id", reserved_ids))
			changes.append({
				"waypoint": waypoint,
				"old_id": old_id,
				"new_id": new_id,
			})
			reserved_ids.append(new_id)
			seen_ids[new_id] = true
		else:
			reserved_ids.append(old_id)
			seen_ids[old_id] = true
	return changes


func _reference_cleanup_changes(network: Node, target: Node) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for source in network.call("get_waypoints"):
		if source == null or source == target or not source.has_method("get_node_or_null"):
			continue
		var old_paths: Array = source.get("connected_waypoint_paths").duplicate()
		var new_paths: Array = []
		var changed := false
		for path in old_paths:
			if source.get_node_or_null(path) == target:
				changed = true
				continue
			new_paths.append(path)
		if changed:
			changes.append({
				"source": source,
				"old_paths": old_paths,
				"new_paths": new_paths,
			})
	return changes


func _can_connect_from_source(target: Node) -> bool:
	var source: Node = _plugin.call("get_connection_source")
	if source == null or target == null or source == target:
		return false
	if not _is_waypoint(source) or not _is_waypoint(target):
		return false
	if _find_network(source) != _find_network(target):
		return false
	return not bool(source.call("has_connection_to", target))


func _connection_source_label() -> String:
	var source: Node = _plugin.call("get_connection_source")
	if source == null:
		return "Connection source: none"
	return "Connection source: %s" % source.name


func _find_network(node: Node) -> Node:
	var current := node
	while current != null:
		if _is_network(current):
			return current
		current = current.get_parent()
	return null


func _unique_child_name(parent: Node, base_name: String) -> String:
	var index := parent.get_child_count() + 1
	var candidate := "%s%04d" % [base_name, index]
	while parent.has_node(candidate):
		index += 1
		candidate = "%s%04d" % [base_name, index]
	return candidate


func _matches_script(node: Node, script_resource) -> bool:
	return node != null and node.get_script() == script_resource


func _is_network(node: Node) -> bool:
	return node != null and (node.get_script() == ROAD_NETWORK_SCRIPT or (node.has_method("get_waypoints") and node.has_method("allocate_waypoint_id")))


func _is_waypoint(node: Node) -> bool:
	return node != null and (node.get_script() == ROAD_WAYPOINT_SCRIPT or (node.has_method("get_waypoint_id") and node.has_method("get_road_network")))
