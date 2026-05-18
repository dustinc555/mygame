@tool
extends Node3D

class_name RoadNetwork

@export var network_id := ""
@export var display_name := "Road Network"
@export var debug_width := 1.25:
	set(value):
		debug_width = value
		_refresh_debug_mesh()
@export var debug_color := Color(1.0, 0.72, 0.08, 0.58):
	set(value):
		debug_color = value
		_refresh_debug_mesh()
@export var editor_show_debug_path := true:
	set(value):
		editor_show_debug_path = value
		_sync_debug_visibility()

var _debug_mesh: MeshInstance3D
var _runtime_debug_visible := false


func _enter_tree() -> void:
	call_deferred("_refresh_debug_mesh")
	set_process(Engine.is_editor_hint())


func _ready() -> void:
	add_to_group("road_network")
	_refresh_debug_mesh()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_refresh_debug_mesh()


func get_network_id() -> String:
	return network_id if not network_id.is_empty() else name


func get_network_record() -> Dictionary:
	return {
		"network_id": get_network_id(),
		"display_name": display_name if not display_name.is_empty() else get_network_id().capitalize(),
		"waypoints": _get_waypoint_records(),
	}


func get_waypoints() -> Array:
	var waypoints: Array = []
	_collect_waypoints(self, waypoints)
	return waypoints


func get_waypoint_id_prefix() -> String:
	var prefix := _sanitize_id_prefix(get_network_id())
	return prefix if not prefix.is_empty() else "road"


func make_waypoint_id(index: int) -> String:
	return "%s.wp_%04d" % [get_waypoint_id_prefix(), max(index, 1)]


func allocate_waypoint_id(reserved_ids := []) -> String:
	var used_ids := {}
	for waypoint in get_waypoints():
		var existing_id := _raw_waypoint_id(waypoint)
		if not existing_id.is_empty():
			used_ids[existing_id] = true
	for id in reserved_ids:
		var reserved_id := str(id)
		if not reserved_id.is_empty():
			used_ids[reserved_id] = true
	var index := 1
	while used_ids.has(make_waypoint_id(index)):
		index += 1
	return make_waypoint_id(index)


func refresh_debug() -> void:
	_refresh_debug_mesh()


func set_debug_visible(value: bool) -> void:
	_runtime_debug_visible = value
	if _debug_mesh == null or not is_instance_valid(_debug_mesh):
		_create_debug_mesh()
	_sync_debug_visibility()
	for waypoint in get_waypoints():
		if waypoint.has_method("set_debug_visible"):
			waypoint.call("set_debug_visible", value)


func _create_debug_mesh() -> void:
	_debug_mesh = get_node_or_null("RoadDebug") as MeshInstance3D
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "RoadDebug"
		add_child(_debug_mesh)
		_set_editor_owner(_debug_mesh)
	_debug_mesh.mesh = _build_connection_mesh()
	_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_mesh.material_override = _make_debug_material(debug_color)
	_sync_debug_visibility()


func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	_create_debug_mesh()


func _remove_debug_mesh() -> void:
	if _debug_mesh == null or not is_instance_valid(_debug_mesh):
		_debug_mesh = get_node_or_null("RoadDebug") as MeshInstance3D
	if _debug_mesh != null and is_instance_valid(_debug_mesh):
		_debug_mesh.queue_free()
	_debug_mesh = null


func _sync_debug_visibility() -> void:
	if _debug_mesh == null or not is_instance_valid(_debug_mesh):
		return
	_debug_mesh.visible = editor_show_debug_path if Engine.is_editor_hint() else _runtime_debug_visible


func _build_connection_mesh() -> ArrayMesh:
	var segments: Array[Dictionary] = []
	var seen_pairs := {}
	for waypoint in get_waypoints():
		if waypoint == null or not waypoint.has_method("get_connected_waypoints"):
			continue
		for connected in waypoint.call("get_connected_waypoints"):
			if connected == null or not is_instance_valid(connected) or not is_ancestor_of(connected):
				continue
			var pair_key := _connection_pair_key(waypoint, connected)
			if seen_pairs.has(pair_key):
				continue
			seen_pairs[pair_key] = true
			segments.append({
				"start": to_local(waypoint.global_position),
				"end": to_local(connected.global_position),
			})
	return _build_segment_mesh(segments)


func _build_segment_mesh(segments: Array[Dictionary]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for segment in segments:
		var start: Vector3 = segment.get("start", Vector3.ZERO)
		var end: Vector3 = segment.get("end", Vector3.ZERO)
		var direction := end - start
		direction.y = 0.0
		if direction.length_squared() <= 0.0001:
			continue
		var side := Vector3(-direction.z, 0.0, direction.x).normalized() * maxf(debug_width * 0.5, 0.02)
		var base := vertices.size()
		vertices.append(start - side)
		vertices.append(start + side)
		vertices.append(end - side)
		vertices.append(end + side)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	if vertices.size() >= 4:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _get_waypoint_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for waypoint in get_waypoints():
		if waypoint.has_method("get_waypoint_record"):
			records.append(waypoint.call("get_waypoint_record", get_network_id()))
	return records


func _collect_waypoints(root: Node, waypoints: Array) -> void:
	for child in root.get_children():
		if child != _debug_mesh and child.has_method("get_waypoint_id"):
			waypoints.append(child)
		_collect_waypoints(child, waypoints)


func _raw_waypoint_id(waypoint: Node) -> String:
	if waypoint == null:
		return ""
	var value = waypoint.get("waypoint_id")
	return "" if value == null else str(value)


func _sanitize_id_prefix(value: String) -> String:
	var source := value.strip_edges().to_lower()
	var result := ""
	var last_was_separator := false
	for index in range(source.length()):
		var code := source.unicode_at(index)
		var character := source.substr(index, 1)
		var is_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		if is_letter or is_digit or character == "_" or character == ".":
			result += character
			last_was_separator = false
		elif not last_was_separator:
			result += "_"
			last_was_separator = true
	while result.begins_with("_") or result.begins_with("."):
		result = result.substr(1)
	while result.ends_with("_") or result.ends_with("."):
		result = result.substr(0, result.length() - 1)
	return result


func _connection_pair_key(a: Node, b: Node) -> String:
	var a_path := str(a.get_path())
	var b_path := str(b.get_path())
	return "%s|%s" % [a_path, b_path] if a_path < b_path else "%s|%s" % [b_path, a_path]


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material


func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	# Debug helpers are generated by @tool scripts and should not be serialized into large scenes.
	node.owner = null
