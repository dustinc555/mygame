@tool
extends Marker3D

class_name GripPointMarker

const EDITOR_VISUAL_NAME := "__GripPointEditorVisual"
const FORWARD_COLOR := Color(0.2, 0.45, 1.0, 1.0)
const HAND_UP_COLOR := Color(0.2, 1.0, 0.25, 1.0)
const RIGHT_COLOR := Color(1.0, 0.15, 0.12, 1.0)
const ORIGIN_COLOR := Color(1.0, 0.92, 0.25, 1.0)

@export var axis_length := 0.18:
	set(value):
		axis_length = value
		_rebuild_editor_visual()
@export var center_radius := 0.018:
	set(value):
		center_radius = value
		_rebuild_editor_visual()


func _ready() -> void:
	_rebuild_editor_visual()


func _enter_tree() -> void:
	call_deferred("_rebuild_editor_visual")


func _rebuild_editor_visual() -> void:
	_clear_editor_visual()
	if not Engine.is_editor_hint():
		return
	var visual_root := Node3D.new()
	visual_root.name = EDITOR_VISUAL_NAME
	add_child(visual_root)
	_add_arrow(visual_root, Vector3.FORWARD, Vector3.UP, axis_length, FORWARD_COLOR)
	_add_arrow(visual_root, Vector3.UP, Vector3.FORWARD, axis_length * 0.72, HAND_UP_COLOR)
	_add_axis_line(visual_root, Vector3.RIGHT, axis_length * 0.42, RIGHT_COLOR)
	_add_center_dot(visual_root)


func _clear_editor_visual() -> void:
	var existing := get_node_or_null(EDITOR_VISUAL_NAME)
	if existing != null:
		remove_child(existing)
		existing.free()


func _add_arrow(parent: Node3D, direction: Vector3, up_hint: Vector3, length: float, color: Color) -> void:
	var normalized_direction := direction.normalized()
	var normalized_up_hint := up_hint.normalized()
	var side := normalized_direction.cross(normalized_up_hint).normalized()
	if side.is_zero_approx():
		side = Vector3.RIGHT
	var tip := normalized_direction * length
	var head_length := length * 0.22
	var head_width := length * 0.12
	var head_base := tip - normalized_direction * head_length
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_add_line_vertices(mesh, Vector3.ZERO, tip, color)
	_add_line_vertices(mesh, tip, head_base + side * head_width, color)
	_add_line_vertices(mesh, tip, head_base - side * head_width, color)
	_add_line_vertices(mesh, tip, head_base + normalized_up_hint * head_width, color)
	_add_line_vertices(mesh, tip, head_base - normalized_up_hint * head_width, color)
	mesh.surface_end()
	_add_mesh_instance(parent, mesh, _make_unshaded_material(true, color))


func _add_axis_line(parent: Node3D, direction: Vector3, length: float, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_add_line_vertices(mesh, Vector3.ZERO, direction.normalized() * length, color)
	mesh.surface_end()
	_add_mesh_instance(parent, mesh, _make_unshaded_material(true, color))


func _add_line_vertices(mesh: ImmediateMesh, from_position: Vector3, to_position: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from_position)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to_position)


func _add_mesh_instance(parent: Node3D, mesh: Mesh, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _make_unshaded_material(use_vertex_color: bool, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = use_vertex_color
	if not use_vertex_color:
		material.albedo_color = color
	return material


func _add_center_dot(parent: Node3D) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = center_radius
	sphere.height = center_radius * 2.0
	_add_mesh_instance(parent, sphere, _make_unshaded_material(false, ORIGIN_COLOR))
