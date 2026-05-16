@tool
extends Node3D

class_name RoadPath

@export var road_id := ""
@export var display_name := "Road"
@export var source_settlement_id := ""
@export var target_settlement_id := ""
@export var bidirectional := true
@export var path_points := PackedVector3Array():
	set(value):
		path_points = value
		_refresh_debug_mesh()
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


func _ready() -> void:
	add_to_group("road_path")
	_refresh_debug_mesh()


func get_road_id() -> String:
	return road_id if not road_id.is_empty() else name


func get_road_record() -> Dictionary:
	return {
		"road_id": get_road_id(),
		"display_name": display_name if not display_name.is_empty() else get_road_id().capitalize(),
		"source_settlement_id": source_settlement_id,
		"target_settlement_id": target_settlement_id,
		"bidirectional": bidirectional,
		"points": get_world_points(),
	}


func get_world_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for point in path_points:
		points.append(to_global(point))
	return points


func connects_settlements(source_id: String, target_id: String) -> bool:
	if source_settlement_id == source_id and target_settlement_id == target_id:
		return true
	return bidirectional and source_settlement_id == target_id and target_settlement_id == source_id


func set_debug_visible(value: bool) -> void:
	_runtime_debug_visible = value
	if _debug_mesh == null or not is_instance_valid(_debug_mesh):
		_create_debug_mesh()
	_sync_debug_visibility()


func _create_debug_mesh() -> void:
	_debug_mesh = get_node_or_null("RoadDebug") as MeshInstance3D
	if _debug_mesh == null:
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "RoadDebug"
		add_child(_debug_mesh)
		_set_editor_owner(_debug_mesh)
	_debug_mesh.mesh = _build_path_mesh(path_points)
	_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_mesh.material_override = _make_debug_material(debug_color)
	_sync_debug_visibility()


func _refresh_debug_mesh() -> void:
	if not is_inside_tree():
		return
	_create_debug_mesh()


func _sync_debug_visibility() -> void:
	if _debug_mesh == null or not is_instance_valid(_debug_mesh):
		return
	_debug_mesh.visible = editor_show_debug_path if Engine.is_editor_hint() else _runtime_debug_visible


func _build_path_mesh(points: PackedVector3Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for index in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
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
	var tree := get_tree()
	if tree == null:
		return
	var edited_root := tree.edited_scene_root
	if edited_root != null:
		node.owner = edited_root
