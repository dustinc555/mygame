extends "res://scripts/characters/humanoid_character.gd"

class_name PartyMember

@export var base_color := Color(0.7, 0.7, 0.7, 1.0)
@export var selected_color := Color(0.28, 0.78, 1.0, 1.0)
@export var focused_color := Color(0.95, 0.78, 0.26, 1.0)

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var selection_ring: MeshInstance3D = $SelectionRing

var _body_material := StandardMaterial3D.new()
var _ring_material := StandardMaterial3D.new()


func _ready() -> void:
	player_party_member = true
	super._ready()
	_body_material.roughness = 0.85
	_body_material.albedo_color = base_color
	body_mesh.material_override = _body_material
	_setup_selection_ring()
	_update_visuals()


func set_selected(value: bool) -> void:
	is_selected = value
	_update_visuals()


func set_focused(value: bool) -> void:
	is_focused = value
	_update_visuals()


func _update_visuals() -> void:
	var body_color := base_color
	if is_selected:
		body_color = base_color.lerp(selected_color, 0.4)
	if is_focused:
		body_color = body_color.lerp(focused_color, 0.45)
	_body_material.albedo_color = body_color
	selection_ring.visible = is_selected or is_focused
	if is_focused:
		_ring_material.albedo_color = focused_color
		_ring_material.emission = focused_color
	elif is_selected:
		_ring_material.albedo_color = selected_color
		_ring_material.emission = selected_color
	if _inspect_ring != null:
		_inspect_ring.visible = is_inspected and not is_selected and not is_focused
	_update_ground_markers()


func _setup_selection_ring() -> void:
	selection_ring.mesh = _make_selection_ring_mesh()
	selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in selection_ring.get_children():
		child.queue_free()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_ring_material.no_depth_test = false
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.emission_enabled = true
	_ring_material.emission_energy_multiplier = 1.35
	selection_ring.material_override = _ring_material


func _make_selection_ring_mesh() -> ArrayMesh:
	var major_radius := 1.12
	var tube_radius := 0.075
	var tube_center_y := 0.06
	var major_segments := 96
	var tube_segments := 10
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for major_index in range(major_segments):
		var major_angle := TAU * float(major_index) / float(major_segments)
		var radial_direction := Vector3(cos(major_angle), 0.0, sin(major_angle))
		for tube_index in range(tube_segments):
			var tube_angle := TAU * float(tube_index) / float(tube_segments)
			var tube_cos := cos(tube_angle)
			var tube_sin := sin(tube_angle)
			vertices.append(radial_direction * (major_radius + tube_radius * tube_cos) + Vector3.UP * (tube_center_y + tube_radius * tube_sin))
			normals.append((radial_direction * tube_cos + Vector3.UP * tube_sin).normalized())
	for major_index in range(major_segments):
		var next_major_index := (major_index + 1) % major_segments
		for tube_index in range(tube_segments):
			var next_tube_index := (tube_index + 1) % tube_segments
			var current := major_index * tube_segments + tube_index
			var next_tube := major_index * tube_segments + next_tube_index
			var next_major := next_major_index * tube_segments + tube_index
			var next_both := next_major_index * tube_segments + next_tube_index
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
