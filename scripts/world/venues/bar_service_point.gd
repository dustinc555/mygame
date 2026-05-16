@tool
extends Node3D

class_name BarServicePoint

@export_enum("barkeeper", "waiter") var point_role := "barkeeper":
	set(value):
		point_role = value
		_refresh_debug_marker()
@export var work_radius := 1.1
@export var editor_show_debug_marker := true:
	set(value):
		editor_show_debug_marker = value
		_sync_debug_marker_visibility()
@export var debug_color := Color(0.0, 0.82, 0.78, 0.76):
	set(value):
		debug_color = value
		_refresh_debug_marker()

var _assigned_worker: HumanoidCharacter
var _debug_marker: MeshInstance3D


func _enter_tree() -> void:
	call_deferred("_refresh_debug_marker")


func _ready() -> void:
	add_to_group("bar_service_point")
	_refresh_debug_marker()


func get_work_position() -> Vector3:
	return global_position


func get_point_role() -> String:
	return point_role


func is_point_role(role: String) -> bool:
	return point_role == role


func claim_worker(worker: HumanoidCharacter) -> bool:
	if worker == null:
		return false
	if _assigned_worker != null and is_instance_valid(_assigned_worker) and _assigned_worker != worker:
		return false
	_assigned_worker = worker
	return true


func release_worker(worker: HumanoidCharacter) -> void:
	if _assigned_worker == worker:
		_assigned_worker = null


func is_available_for(worker: HumanoidCharacter) -> bool:
	return _assigned_worker == null or not is_instance_valid(_assigned_worker) or _assigned_worker == worker


func get_assigned_worker() -> HumanoidCharacter:
	return _assigned_worker if _assigned_worker != null and is_instance_valid(_assigned_worker) else null


func is_worker_at_point(worker: HumanoidCharacter) -> bool:
	return worker != null and worker.global_position.distance_to(global_position) <= work_radius


func _refresh_debug_marker() -> void:
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint():
		_hide_debug_marker()
		return
	_create_debug_marker()
	if _debug_marker == null:
		return
	_debug_marker.mesh = _build_pyramid_mesh()
	_debug_marker.material_override = _make_debug_material(debug_color)
	_debug_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sync_debug_marker_visibility()


func _create_debug_marker() -> void:
	_debug_marker = get_node_or_null("DebugMarker") as MeshInstance3D
	if _debug_marker != null:
		return
	_debug_marker = MeshInstance3D.new()
	_debug_marker.name = "DebugMarker"
	add_child(_debug_marker, false, Node.INTERNAL_MODE_BACK)


func _sync_debug_marker_visibility() -> void:
	if _debug_marker == null or not is_instance_valid(_debug_marker):
		return
	_debug_marker.visible = Engine.is_editor_hint() and editor_show_debug_marker


func _hide_debug_marker() -> void:
	_debug_marker = get_node_or_null("DebugMarker") as MeshInstance3D
	if _debug_marker != null:
		_debug_marker.visible = false


func _build_pyramid_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(-0.28, 0.0, -0.28),
		Vector3(0.28, 0.0, -0.28),
		Vector3(0.28, 0.0, 0.28),
		Vector3(-0.28, 0.0, 0.28),
		Vector3(0.0, 0.9, 0.0),
	])
	var indices := PackedInt32Array([
		0, 1, 2,
		0, 2, 3,
		0, 4, 1,
		1, 4, 2,
		2, 4, 3,
		3, 4, 0,
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
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
