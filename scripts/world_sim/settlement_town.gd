@tool
extends "res://scripts/world_sim/settlement_anchor.gd"

class_name SettlementTown

@export var facilities_root_path: NodePath = NodePath("Facilities")
@export var keeps_root_path: NodePath = NodePath("Keeps")
@export var bars_root_path: NodePath = NodePath("Bars")
@export var fields_root_path: NodePath = NodePath("Fields")
@export var shops_root_path: NodePath = NodePath("Shops")
@export var mines_root_path: NodePath = NodePath("Mines")
@export var housing_root_path: NodePath = NodePath("Housing")
@export var activity_points_root_path: NodePath = NodePath("ActivityPoints")
@export var storage_root_path: NodePath = NodePath("Storage")
@export var territory_root_path: NodePath = NodePath("Territory")
@export var auto_town_border_from_footprint := true:
	set(value):
		auto_town_border_from_footprint = value
		_refresh_town_border_debug()
@export var town_border_radius := 24.0:
	set(value):
		town_border_radius = value
		_refresh_town_border_debug()
@export_range(0.0, 30.0, 0.5) var town_border_padding := 6.0:
	set(value):
		town_border_padding = maxf(0.0, float(value))
		_refresh_town_border_debug()
@export_range(0.25, 10.0, 0.25) var town_border_dash_length := 2.0:
	set(value):
		town_border_dash_length = maxf(0.25, float(value))
		_refresh_town_border_debug()
@export_range(0.0, 10.0, 0.25) var town_border_dash_gap := 1.0:
	set(value):
		town_border_dash_gap = maxf(0.0, float(value))
		_refresh_town_border_debug()
@export var town_border_debug_color := Color(0.62, 1.0, 0.94, 0.34):
	set(value):
		town_border_debug_color = value
		_refresh_town_border_debug()
@export var editor_show_debug_shape := true:
	set(value):
		editor_show_debug_shape = value
		_sync_town_border_debug_visibility()

var _town_border_debug: MeshInstance3D
var _town_border_refresh_timer := 0.0
var _last_town_border_signature := ""


func _enter_tree() -> void:
	call_deferred("_refresh_town_border_debug")


func _ready() -> void:
	super._ready()
	add_to_group("settlement_town")
	_refresh_town_border_debug()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint() or not editor_show_debug_shape:
		return
	_town_border_refresh_timer -= delta
	if _town_border_refresh_timer > 0.0:
		return
	_town_border_refresh_timer = 0.25
	_refresh_town_border_debug_if_changed()


func get_facility_nodes() -> Array:
	var facilities: Array = []
	for root_path in _get_facility_root_paths():
		var root := get_node_or_null(root_path)
		if root != null:
			_collect_facilities(root, facilities)
	return facilities


func get_facility_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var settlement_id := get_settlement_id()
	for facility in get_facility_nodes():
		if facility.has_method("get_facility_record"):
			records.append(facility.call("get_facility_record", settlement_id))
	return records


func get_population_capacity_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	_collect_population_capacity_records(self, records, get_settlement_id())
	return records


func get_authored_population_capacity() -> int:
	var total := 0
	for record in get_population_capacity_records():
		total += max(0, int(record.get("population_capacity", 0)))
	return total


func get_activity_points() -> Array:
	var points: Array = []
	var activity_root := get_node_or_null(activity_points_root_path)
	if activity_root != null:
		_collect_activity_points(activity_root, points)
	for facility in get_facility_nodes():
		if facility.has_method("get_activity_points"):
			for point in facility.call("get_activity_points"):
				if not points.has(point):
					points.append(point)
	return points


func get_job_provider_nodes() -> Array:
	var providers: Array = []
	_collect_nodes_with_group(self, "job_provider", providers)
	return providers


func get_bar_service_area_nodes() -> Array:
	var service_areas: Array = []
	_collect_nodes_with_group(self, "bar_service_area", service_areas)
	return service_areas


func get_town_border_record() -> Dictionary:
	var shape := _get_town_border_shape()
	shape["settlement_id"] = get_settlement_id()
	shape["display_name"] = str(settlement_definition.get("display_name")) if settlement_definition != null else name
	return shape


func contains_town_border_position(world_position: Vector3) -> bool:
	var shape := _get_town_border_shape()
	match str(shape.get("shape_mode", "circle")):
		"box":
			var local := to_local(world_position)
			var bounds_min: Vector2 = shape.get("bounds_min", Vector2.ZERO)
			var bounds_max: Vector2 = shape.get("bounds_max", Vector2.ZERO)
			return Rect2(bounds_min, bounds_max - bounds_min).has_point(Vector2(local.x, local.z))
		_:
			var radius := float(shape.get("radius", town_border_radius))
			if radius <= 0.0:
				return false
			var flat_center := Vector2(global_position.x, global_position.z)
			var flat_position := Vector2(world_position.x, world_position.z)
			return flat_center.distance_to(flat_position) <= radius


func set_town_border_debug_visible(value: bool) -> void:
	if _town_border_debug == null or not is_instance_valid(_town_border_debug):
		_create_town_border_debug()
	if _town_border_debug != null:
		_town_border_debug.visible = editor_show_debug_shape if Engine.is_editor_hint() else value


func _collect_facilities(root: Node, facilities: Array) -> void:
	for child in root.get_children():
		if child.has_method("get_facility_record") and not facilities.has(child):
			facilities.append(child)
		_collect_facilities(child, facilities)


func _collect_population_capacity_records(root: Node, records: Array[Dictionary], settlement_id: String) -> void:
	for child in root.get_children():
		if child.is_in_group("settlement_town"):
			continue
		if child.has_method("get_population_capacity_record"):
			var record: Dictionary = child.call("get_population_capacity_record", settlement_id)
			if int(record.get("population_capacity", 0)) > 0:
				records.append(record)
			continue
		_collect_population_capacity_records(child, records, settlement_id)


func _get_facility_root_paths() -> Array[NodePath]:
	return [
		facilities_root_path,
		keeps_root_path,
		bars_root_path,
		fields_root_path,
		shops_root_path,
		mines_root_path,
		housing_root_path,
	]


func _get_border_root_paths() -> Array[NodePath]:
	return [
		housing_root_path,
		facilities_root_path,
		bars_root_path,
		keeps_root_path,
		shops_root_path,
		storage_root_path,
	]


func _collect_activity_points(root: Node, points: Array) -> void:
	for child in root.get_children():
		if child.has_method("get_activity_record"):
			points.append(child)
		_collect_activity_points(child, points)


func _collect_nodes_with_group(root: Node, group_name: String, nodes: Array) -> void:
	if root.is_in_group(group_name) and not nodes.has(root):
		nodes.append(root)
	for child in root.get_children():
		_collect_nodes_with_group(child, group_name, nodes)


func _get_town_border_shape() -> Dictionary:
	if auto_town_border_from_footprint:
		var auto_rect := _get_auto_town_border_rect()
		if auto_rect.size.x > 0.0 and auto_rect.size.y > 0.0:
			var center_local := auto_rect.get_center()
			return {
				"shape_mode": "box",
				"center": global_transform * Vector3(center_local.x, 0.0, center_local.y),
				"bounds_min": auto_rect.position,
				"bounds_max": auto_rect.position + auto_rect.size,
				"radius": maxf(auto_rect.size.x, auto_rect.size.y) * 0.5,
				"polygon_points": PackedVector2Array([
					auto_rect.position,
					Vector2(auto_rect.position.x + auto_rect.size.x, auto_rect.position.y),
					auto_rect.position + auto_rect.size,
					Vector2(auto_rect.position.x, auto_rect.position.y + auto_rect.size.y),
				]),
			}
	return {
		"shape_mode": "circle",
		"center": global_position,
		"radius": town_border_radius,
		"bounds_min": Vector2(-town_border_radius, -town_border_radius),
		"bounds_max": Vector2(town_border_radius, town_border_radius),
		"polygon_points": _circle_points(town_border_radius, 96),
	}


func _get_auto_town_border_rect() -> Rect2:
	var bounds := {
		"has": false,
		"min": Vector2.ZERO,
		"max": Vector2.ZERO,
	}
	for root_path in _get_border_root_paths():
		var root := get_node_or_null(root_path)
		if root == null:
			continue
		for child in root.get_children():
			_collect_border_bounds(child, bounds)
	if not bool(bounds["has"]):
		return Rect2()
	var min_point: Vector2 = bounds["min"]
	var max_point: Vector2 = bounds["max"]
	var padding := maxf(town_border_padding, 0.0)
	min_point -= Vector2.ONE * padding
	max_point += Vector2.ONE * padding
	return Rect2(min_point, max_point - min_point)


func _collect_border_bounds(node: Node, bounds: Dictionary) -> void:
	if _should_skip_border_node(node):
		return
	if node is Node3D:
		_include_node3d_border_bounds(node as Node3D, bounds)
	for child in node.get_children():
		_collect_border_bounds(child, bounds)


func _should_skip_border_node(node: Node) -> bool:
	if node == null:
		return true
	if node == _town_border_debug or str(node.name) in ["TownBorderDebug", "TerritoryDebug", "StateLabel"]:
		return true
	if node is Label3D:
		return true
	if node.has_method("get_activity_record"):
		return true
	return false


func _include_node3d_border_bounds(node: Node3D, bounds: Dictionary) -> void:
	if not node.is_inside_tree():
		return
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var aabb := mesh_instance.mesh.get_aabb()
		for corner in _aabb_corners(aabb):
			_expand_border_bounds(bounds, node.global_transform * corner)
		return
	_expand_border_bounds(bounds, node.global_position)


func _aabb_corners(aabb: AABB) -> Array[Vector3]:
	var end := aabb.position + aabb.size
	return [
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z),
		Vector3(end.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, end.z),
		Vector3(end.x, aabb.position.y, end.z),
		Vector3(aabb.position.x, end.y, aabb.position.z),
		Vector3(end.x, end.y, aabb.position.z),
		Vector3(aabb.position.x, end.y, end.z),
		Vector3(end.x, end.y, end.z),
	]


func _expand_border_bounds(bounds: Dictionary, world_position: Vector3) -> void:
	var local := to_local(world_position)
	var point := Vector2(local.x, local.z)
	if not bool(bounds["has"]):
		bounds["has"] = true
		bounds["min"] = point
		bounds["max"] = point
		return
	var min_point: Vector2 = bounds["min"]
	var max_point: Vector2 = bounds["max"]
	bounds["min"] = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
	bounds["max"] = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))


func _town_border_outline_points(shape: Dictionary) -> PackedVector2Array:
	var points = shape.get("polygon_points", PackedVector2Array())
	if points is PackedVector2Array and points.size() >= 3:
		return points
	return _circle_points(float(shape.get("radius", town_border_radius)), 96)


func _circle_points(target_radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if target_radius <= 0.0:
		return points
	for index in range(max(segments, 3)):
		var angle := TAU * float(index) / float(max(segments, 3))
		points.append(Vector2(cos(angle), sin(angle)) * target_radius)
	return points


func _build_dashed_outline_mesh(points: PackedVector2Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	if points.size() >= 2:
		for index in range(points.size()):
			var start := points[index]
			var end := points[0] if index == points.size() - 1 else points[index + 1]
			_append_dashed_edge(vertices, start, end)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _append_dashed_edge(vertices: PackedVector3Array, start: Vector2, end: Vector2) -> void:
	var delta := end - start
	var length := delta.length()
	if length <= 0.001:
		return
	var direction := delta / length
	var dash := maxf(town_border_dash_length, 0.25)
	var gap := maxf(town_border_dash_gap, 0.0)
	var cursor := 0.0
	while cursor < length:
		var dash_end := minf(cursor + dash, length)
		var from := start + direction * cursor
		var to := start + direction * dash_end
		vertices.append(Vector3(from.x, 0.0, from.y))
		vertices.append(Vector3(to.x, 0.0, to.y))
		cursor += dash + gap


func _create_town_border_debug() -> void:
	var shape := _get_town_border_shape()
	var points := _town_border_outline_points(shape)
	if points.size() < 3:
		return
	_town_border_debug = get_node_or_null("TownBorderDebug") as MeshInstance3D
	if _town_border_debug == null:
		_town_border_debug = MeshInstance3D.new()
		_town_border_debug.name = "TownBorderDebug"
		add_child(_town_border_debug)
		_set_editor_owner(_town_border_debug)
	_town_border_debug.mesh = _build_dashed_outline_mesh(points)
	_town_border_debug.position = Vector3(0.0, 0.16, 0.0)
	_town_border_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_town_border_debug.material_override = _make_debug_material(town_border_debug_color)
	_town_border_debug.visible = Engine.is_editor_hint() and editor_show_debug_shape


func _refresh_town_border_debug() -> void:
	if not is_inside_tree():
		return
	_create_town_border_debug()
	_last_town_border_signature = _town_border_signature(_get_town_border_shape())


func _refresh_town_border_debug_if_changed() -> void:
	if not is_inside_tree():
		return
	var shape := _get_town_border_shape()
	var signature := _town_border_signature(shape)
	if signature == _last_town_border_signature:
		return
	_last_town_border_signature = signature
	_create_town_border_debug()


func _sync_town_border_debug_visibility() -> void:
	if _town_border_debug == null or not is_instance_valid(_town_border_debug):
		return
	if Engine.is_editor_hint():
		_town_border_debug.visible = editor_show_debug_shape


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material


func _town_border_signature(shape: Dictionary) -> String:
	var bounds_min: Vector2 = shape.get("bounds_min", Vector2.ZERO)
	var bounds_max: Vector2 = shape.get("bounds_max", Vector2.ZERO)
	return "%s:%.3f:%.3f:%.3f:%.3f" % [str(shape.get("shape_mode", "circle")), bounds_min.x, bounds_min.y, bounds_max.x, bounds_max.y]


func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var tree := get_tree()
	if tree == null:
		return
	var edited_root := tree.edited_scene_root
	if edited_root != null:
		node.owner = edited_root
