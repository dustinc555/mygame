@tool
extends MeshInstance3D

class_name RoadWaypoint

@export var waypoint_id := ""
@export var display_name := "Road Waypoint"
@export var settlement_id := ""
@export var connected_waypoint_paths: Array[NodePath] = []
@export var debug_radius := 0.75:
	set(value):
		debug_radius = value
		_refresh_debug_marker()
@export var debug_color := Color(1.0, 0.88, 0.2, 0.95):
	set(value):
		debug_color = value
		_refresh_debug_marker()
@export var editor_show_debug_marker := true:
	set(value):
		editor_show_debug_marker = value
		_sync_debug_visibility()

var _runtime_debug_visible := false


func _enter_tree() -> void:
	call_deferred("_refresh_debug_marker")


func _ready() -> void:
	add_to_group("road_waypoint")
	_refresh_debug_marker()


func get_waypoint_id() -> String:
	return waypoint_id if not waypoint_id.is_empty() else name


func get_waypoint_record(network_id := "") -> Dictionary:
	return {
		"waypoint_id": get_waypoint_id(),
		"network_id": network_id,
		"display_name": display_name if not display_name.is_empty() else get_waypoint_id().capitalize(),
		"settlement_id": settlement_id,
		"world_position": global_position,
		"connected_waypoint_ids": _connected_waypoint_ids(),
	}


func get_connected_waypoints() -> Array:
	var waypoints: Array = []
	for path in connected_waypoint_paths:
		var waypoint := get_node_or_null(path)
		if waypoint != null and waypoint.has_method("get_waypoint_id"):
			waypoints.append(waypoint)
	return waypoints


func has_connection_to(target: Node) -> bool:
	if target == null or target == self:
		return false
	var path := get_path_to(target)
	return connected_waypoint_paths.has(path)


func get_connection_paths_with(target: Node) -> Array[NodePath]:
	var paths: Array[NodePath] = connected_waypoint_paths.duplicate()
	if target == null or target == self:
		return paths
	var path := get_path_to(target)
	if not paths.has(path):
		paths.append(path)
	return paths


func add_connection_to(target: Node) -> void:
	connected_waypoint_paths = get_connection_paths_with(target)
	_refresh_road_network_debug()


func get_road_network() -> Node:
	var current := get_parent()
	while current != null:
		if current.has_method("allocate_waypoint_id"):
			return current
		current = current.get_parent()
	return null


func refresh_debug() -> void:
	_refresh_debug_marker()
	_refresh_road_network_debug()


func set_debug_visible(value: bool) -> void:
	_runtime_debug_visible = value
	_create_debug_marker()
	_sync_debug_visibility()


func _create_debug_marker() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = maxf(debug_radius, 0.05)
	mesh.height = maxf(debug_radius * 2.0, 0.1)
	mesh.radial_segments = 16
	mesh.rings = 8
	self.mesh = mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _make_debug_material(debug_color)
	_sync_debug_visibility()


func _refresh_debug_marker() -> void:
	if not is_inside_tree():
		return
	_create_debug_marker()


func _sync_debug_visibility() -> void:
	visible = editor_show_debug_marker if Engine.is_editor_hint() else _runtime_debug_visible


func _connected_waypoint_ids() -> Array[String]:
	var ids: Array[String] = []
	for waypoint in get_connected_waypoints():
		ids.append(str(waypoint.call("get_waypoint_id")))
	return ids


func _refresh_road_network_debug() -> void:
	var network := get_road_network()
	if network != null and network.has_method("refresh_debug"):
		network.call("refresh_debug")


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material
