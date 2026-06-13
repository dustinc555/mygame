@tool
extends RefCounted

class_name SelectionRingVisual

const DEFAULT_SELECTED_COLOR := Color(0.28, 0.78, 1.0, 1.0)
const DEFAULT_FOCUSED_COLOR := Color(0.95, 0.78, 0.26, 1.0)
const MAJOR_RADIUS := 1.12
const TUBE_RADIUS := 0.075
const TUBE_CENTER_Y := 0.06
const MAJOR_SEGMENTS := 96
const TUBE_SEGMENTS := 10
const GENERATED_CHILD_META := "selection_ring_generated_child"

static func setup_ring(ring: MeshInstance3D, material: StandardMaterial3D = null) -> StandardMaterial3D:
	if ring == null:
		return material
	ring.mesh = get_ring_mesh()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cleanup_generated_children(ring)
	var resolved_material := material
	if resolved_material == null:
		resolved_material = StandardMaterial3D.new()
	resolved_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	resolved_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	resolved_material.no_depth_test = false
	resolved_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	resolved_material.emission_enabled = true
	resolved_material.emission_energy_multiplier = 1.35
	ring.material_override = resolved_material
	return resolved_material


static func apply_state(
	ring: MeshInstance3D,
	material: StandardMaterial3D,
	is_selected: bool,
	is_focused: bool,
	selected_color: Color = DEFAULT_SELECTED_COLOR,
	focused_color: Color = DEFAULT_FOCUSED_COLOR
) -> void:
	if ring == null:
		return
	ring.visible = is_selected or is_focused
	if material == null:
		return
	var color := focused_color if is_focused else selected_color
	material.albedo_color = color
	material.emission = color


static func get_ring_mesh() -> ArrayMesh:
	# TODO(actor-decoupling): replace per-ring procedural meshes with a small .tres mesh resource once selection visuals settle.
	return _make_ring_mesh()


static func _cleanup_generated_children(ring: MeshInstance3D) -> void:
	for child in ring.get_children():
		if bool(child.get_meta(GENERATED_CHILD_META, false)):
			child.queue_free()


static func _make_ring_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for major_index in range(MAJOR_SEGMENTS):
		var major_angle := TAU * float(major_index) / float(MAJOR_SEGMENTS)
		var radial_direction := Vector3(cos(major_angle), 0.0, sin(major_angle))
		for tube_index in range(TUBE_SEGMENTS):
			var tube_angle := TAU * float(tube_index) / float(TUBE_SEGMENTS)
			var tube_cos := cos(tube_angle)
			var tube_sin := sin(tube_angle)
			vertices.append(radial_direction * (MAJOR_RADIUS + TUBE_RADIUS * tube_cos) + Vector3.UP * (TUBE_CENTER_Y + TUBE_RADIUS * tube_sin))
			normals.append((radial_direction * tube_cos + Vector3.UP * tube_sin).normalized())
	for major_index in range(MAJOR_SEGMENTS):
		var next_major_index := (major_index + 1) % MAJOR_SEGMENTS
		for tube_index in range(TUBE_SEGMENTS):
			var next_tube_index := (tube_index + 1) % TUBE_SEGMENTS
			var current := major_index * TUBE_SEGMENTS + tube_index
			var next_tube := major_index * TUBE_SEGMENTS + next_tube_index
			var next_major := next_major_index * TUBE_SEGMENTS + tube_index
			var next_both := next_major_index * TUBE_SEGMENTS + next_tube_index
			indices.append(current)
			indices.append(next_major)
			indices.append(next_tube)
			indices.append(next_tube)
			indices.append(next_major)
			indices.append(next_both)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
