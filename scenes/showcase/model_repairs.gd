@tool
extends RefCounted

class_name ModelRepairs

## Known per-model material/mesh repairs for imported vendor packs, shared by
## every viewer (showcases, prop browser) and by wrapper scenes that
## instantiate raw glTFs. The Quaternius sign models keep their icon in UV2
## with a white-mask albedo, and the planet props ship untextured — these
## repairs make them render as authored.

const SIGN_ICON_SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	float white_mask = min(min(tex.r, tex.g), tex.b);
	float icon = smoothstep(0.28, 0.62, white_mask);
	ALBEDO = mix(vec3(0.035, 0.03, 0.025), vec3(1.0), icon);
	ROUGHNESS = 0.86;
}
"""


static func apply_known_repairs(instance: Node3D, file_name: String, asset_directory: String) -> void:
	if file_name.begins_with("Sign_"):
		copy_uv2_to_uv_for_material(instance, "MI_WoodenSign")
	elif file_name.begins_with("Prop_Planet_"):
		_apply_planet_material(instance, file_name, asset_directory)


static func _apply_planet_material(root: Node, file_name: String, asset_directory: String) -> void:
	var texture := load(_get_planet_texture_path(file_name, asset_directory)) as Texture2D
	if texture == null:
		return
	_apply_material_to_meshes(root, _make_planet_material(file_name, texture))


static func _get_planet_texture_path(file_name: String, asset_directory: String) -> String:
	var base_path := asset_directory.path_join("planet_textures")
	if file_name.contains("Alien"):
		return base_path.path_join("T_AlienDotted.png")
	if file_name.contains("Earth"):
		return base_path.path_join("T_Ground_1.png")
	if file_name.contains("Icy"):
		return base_path.path_join("T_Water_2.png")
	if file_name.contains("Red"):
		return base_path.path_join("T_Ground_2.png")
	return base_path.path_join("T_Clouds_1.png")


static func _make_planet_material(file_name: String, texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = file_name.get_basename() + "_ShowcaseMaterial"
	material.albedo_texture = texture
	material.roughness = 0.72
	if file_name.contains("Icy"):
		material.albedo_color = Color(0.72, 0.92, 1.0, 1.0)
	elif file_name.contains("Red"):
		material.albedo_color = Color(1.0, 0.42, 0.28, 1.0)
	elif file_name.contains("Alien"):
		material.albedo_color = Color(0.62, 1.0, 0.72, 1.0)
	else:
		material.albedo_color = Color.WHITE
	return material


static func _apply_material_to_meshes(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_apply_material_to_meshes(child, material)


static func copy_uv2_to_uv_for_material(root: Node, material_name: String) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh is ArrayMesh:
			mesh_instance.mesh = _make_uv2_as_uv_mesh(mesh_instance.mesh as ArrayMesh, material_name)
	for child in root.get_children():
		copy_uv2_to_uv_for_material(child, material_name)


static func _make_uv2_as_uv_mesh(mesh: ArrayMesh, material_name: String) -> ArrayMesh:
	var repaired := ArrayMesh.new()
	repaired.resource_name = mesh.resource_name
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var material := mesh.surface_get_material(surface_index)
		if material != null and material.resource_name == material_name:
			var uv2 := arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
			if not uv2.is_empty():
				arrays[Mesh.ARRAY_TEX_UV] = uv2
			material = _make_sign_icon_material(material)
		repaired.add_surface_from_arrays(mesh.surface_get_primitive_type(surface_index), arrays)
		repaired.surface_set_material(surface_index, material)
	return repaired


static func _make_sign_icon_material(source_material: Material) -> Material:
	if not (source_material is BaseMaterial3D):
		return source_material
	var source_base := source_material as BaseMaterial3D
	if source_base.albedo_texture == null:
		return source_material

	var shader := Shader.new()
	shader.code = SIGN_ICON_SHADER_CODE
	var material := ShaderMaterial.new()
	material.resource_name = source_material.resource_name + "_Masked"
	material.shader = shader
	material.set_shader_parameter("albedo_texture", source_base.albedo_texture)
	return material
