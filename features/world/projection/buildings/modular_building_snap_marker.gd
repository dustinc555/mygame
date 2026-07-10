@tool
extends Marker3D

class_name ModularBuildingSnapMarker

const VISUAL_NAME := "__ModularBuildingSnapVisual"
const SNAP_POINT_SCRIPT := preload("res://features/world/resources/building_pieces/modular_building_snap_point.gd")
const DEFAULT_COLOR := Color(0.1, 0.85, 1.0, 1.0)
const ACCEPT_COLOR := Color(0.25, 1.0, 0.35, 1.0)
const SIDE_COLOR := Color(1.0, 0.25, 0.15, 1.0)
const DOT_COLOR := Color(1.0, 0.9, 0.2, 1.0)

@export var snap_id := ""
@export var display_name := ""
@export var connector_type := ""
@export var accepts_types: PackedStringArray = PackedStringArray()
@export var editor_show_visual := true:
	set(value):
		editor_show_visual = value
		_rebuild_visual()
@export var runtime_show_visual := false:
	set(value):
		runtime_show_visual = value
		_rebuild_visual()
@export var axis_length := 0.42:
	set(value):
		axis_length = value
		_rebuild_visual()
@export var center_radius := 0.045:
	set(value):
		center_radius = value
		_rebuild_visual()


func _enter_tree() -> void:
	call_deferred("_rebuild_visual")


func _ready() -> void:
	_rebuild_visual()


func make_snap_point_resource() -> Resource:
	var snap_point := SNAP_POINT_SCRIPT.new()
	snap_point.snap_id = snap_id
	snap_point.display_name = display_name
	snap_point.connector_type = connector_type
	snap_point.accepts_types = accepts_types.duplicate()
	snap_point.local_transform = transform
	return snap_point


func _rebuild_visual() -> void:
	_clear_visual()
	if Engine.is_editor_hint():
		if not editor_show_visual:
			return
	elif not runtime_show_visual:
		return
	var visual_root := Node3D.new()
	visual_root.name = VISUAL_NAME
	add_child(visual_root)
	_add_arrow(visual_root, Vector3.FORWARD, Vector3.UP, axis_length, DEFAULT_COLOR)
	_add_arrow(visual_root, Vector3.UP, Vector3.FORWARD, axis_length * 0.65, ACCEPT_COLOR)
	_add_axis_line(visual_root, Vector3.RIGHT, axis_length * 0.45, SIDE_COLOR)
	_add_center_dot(visual_root)
	_add_label(visual_root)


func _clear_visual() -> void:
	var existing := get_node_or_null(VISUAL_NAME)
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
	mesh_instance.name = "SnapVisualMesh"
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _add_center_dot(parent: Node3D) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = center_radius
	sphere.height = center_radius * 2.0
	_add_mesh_instance(parent, sphere, _make_unshaded_material(false, DOT_COLOR))


func _add_label(parent: Node3D) -> void:
	var label := Label3D.new()
	label.name = "SnapLabel"
	label.text = snap_id if not snap_id.is_empty() else String(name)
	label.position = Vector3.UP * (axis_length * 0.72)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 34
	label.modulate = Color(1.0, 0.96, 0.55, 1.0)
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.no_depth_test = true
	parent.add_child(label)


func _make_unshaded_material(use_vertex_color: bool, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = use_vertex_color
	material.no_depth_test = true
	if not use_vertex_color:
		material.albedo_color = color
	return material
