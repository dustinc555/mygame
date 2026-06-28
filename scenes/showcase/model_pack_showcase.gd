extends Node3D


const GLTF_EXTENSION := "gltf"
const PLATFORM_HEIGHT := 0.35
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

@export_dir var asset_directory: String = ""
@export var showcase_title := "Model Pack Showcase"
@export_multiline var pack_note := ""
@export_range(1, 32, 1) var columns := 12
@export var item_spacing := 3.4
@export var row_spacing := 3.8
@export var platform_margin := 4.0
@export var target_model_extent := 1.85
@export var min_model_scale := 0.08
@export var max_model_scale := 6.0
@export var flat_surface_lift := 0.035
@export var model_yaw_degrees := 0.0
@export var auto_play_animations := false
## When true, each model is rescaled to target_model_extent. Set false for kits authored at
## real-world scale (e.g. modular building pieces) so they keep their authored proportions.
@export var normalize_model_scale := true
## Turn off shadow casting on every showcased model (useful for dense kits with many meshes).
@export var disable_model_shadows := false
## File names (with extension) in asset_directory to skip — e.g. a sample-scene ground plane.
@export var excluded_model_files: PackedStringArray = PackedStringArray()
@export var platform_color := Color(0.28, 0.22, 0.16, 1.0)
@export var title_label_color := Color(1.0, 0.92, 0.78, 1.0)
@export var item_label_color := Color(0.92, 0.88, 0.78, 1.0)


func _ready() -> void:
	_build_showcase()


func _build_showcase() -> void:
	var model_files := _get_model_files()
	if model_files.is_empty():
		_add_hud_label(0, "No .gltf models found in %s" % asset_directory)
		return

	var row_count := ceili(float(model_files.size()) / float(columns))
	_add_platform(model_files.size(), row_count)
	_add_title_label(model_files.size(), row_count)
	_populate_models(model_files, row_count)
	_add_hud_label(model_files.size(), "")


func _get_model_files() -> PackedStringArray:
	var result := PackedStringArray()
	if asset_directory.is_empty():
		return result

	var files := DirAccess.get_files_at(asset_directory)
	files.sort()
	for file_name in files:
		if file_name.get_extension().to_lower() == GLTF_EXTENSION and not excluded_model_files.has(file_name):
			result.append(file_name)
	return result


func _populate_models(model_files: PackedStringArray, row_count: int) -> void:
	var start_x := -float(columns - 1) * item_spacing * 0.5
	var start_z := -float(row_count - 1) * row_spacing * 0.5
	for index in range(model_files.size()):
		var column := index % columns
		var row := index / columns
		var slot_position := Vector3(start_x + float(column) * item_spacing, 0.0, start_z + float(row) * row_spacing)
		_add_model_slot(index, model_files[index], slot_position)


func _add_model_slot(index: int, file_name: String, slot_position: Vector3) -> void:
	var slot := Node3D.new()
	slot.name = "Slot_%03d_%s" % [index + 1, _sanitize_node_name(file_name.get_basename())]
	slot.position = slot_position
	add_child(slot)

	var label_text := _make_display_label(file_name)
	var model_path := asset_directory.path_join(file_name)
	var packed_scene := load(model_path) as PackedScene
	if packed_scene == null:
		_add_item_label(slot, label_text + "\n(load failed)", target_model_extent)
		return

	var instance := packed_scene.instantiate() as Node3D
	if instance == null:
		_add_item_label(slot, label_text + "\n(not Node3D)", target_model_extent)
		return

	instance.name = _sanitize_node_name(file_name.get_basename())
	instance.rotation.y = deg_to_rad(model_yaw_degrees)
	slot.add_child(instance)
	_apply_known_model_repairs(instance, file_name)
	if disable_model_shadows:
		_disable_shadow_casting(instance)

	var display_height := _fit_model_to_slot(instance)
	if auto_play_animations:
		_play_first_animation(instance)
	_add_item_label(slot, label_text, display_height)


func _fit_model_to_slot(instance: Node3D) -> float:
	var bounds_info := _get_node_local_bounds(instance)
	if not bool(bounds_info.get("has_bounds", false)):
		return target_model_extent

	var bounds := bounds_info["bounds"] as AABB
	var largest_extent := maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z)
	if largest_extent <= 0.0001:
		return target_model_extent

	var scale_factor := 1.0
	if normalize_model_scale:
		scale_factor = clampf(target_model_extent / largest_extent, min_model_scale, max_model_scale)
	instance.scale = Vector3.ONE * scale_factor

	var bounds_center := bounds.get_center()
	var display_height := bounds.size.y * scale_factor
	instance.position += Vector3(
		-bounds_center.x * scale_factor,
		-bounds.position.y * scale_factor,
		-bounds_center.z * scale_factor
	)
	if display_height < 0.03:
		instance.position.y += flat_surface_lift
	return maxf(display_height, 0.35)


func _disable_shadow_casting(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadow_casting(child)


func _apply_known_model_repairs(instance: Node3D, file_name: String) -> void:
	if file_name.begins_with("Sign_"):
		_copy_uv2_to_uv_for_material(instance, "MI_WoodenSign")
	elif file_name.begins_with("Prop_Planet_"):
		_apply_planet_material(instance, file_name)


func _apply_planet_material(root: Node, file_name: String) -> void:
	var texture_path := _get_planet_texture_path(file_name)
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	_apply_material_to_meshes(root, _make_planet_material(file_name, texture))


func _get_planet_texture_path(file_name: String) -> String:
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


func _make_planet_material(file_name: String, texture: Texture2D) -> StandardMaterial3D:
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


func _apply_material_to_meshes(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface_index, material)
	for child in node.get_children():
		_apply_material_to_meshes(child, material)


func _copy_uv2_to_uv_for_material(root: Node, material_name: String) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh is ArrayMesh:
			mesh_instance.mesh = _make_uv2_as_uv_mesh(mesh_instance.mesh as ArrayMesh, material_name)
	for child in root.get_children():
		_copy_uv2_to_uv_for_material(child, material_name)


func _make_uv2_as_uv_mesh(mesh: ArrayMesh, material_name: String) -> ArrayMesh:
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


func _make_sign_icon_material(source_material: Material) -> Material:
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


func _get_node_local_bounds(root: Node3D) -> Dictionary:
	var state := {
		"has_bounds": false,
		"bounds": AABB(),
	}
	_accumulate_mesh_bounds(root, root, state)
	return state


func _accumulate_mesh_bounds(root: Node3D, node: Node, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var to_root := root.global_transform.affine_inverse() * mesh_instance.global_transform
			var transformed_bounds := _transform_aabb(mesh_instance.mesh.get_aabb(), to_root)
			if bool(state["has_bounds"]):
				state["bounds"] = (state["bounds"] as AABB).merge(transformed_bounds)
			else:
				state["bounds"] = transformed_bounds
				state["has_bounds"] = true

	for child in node.get_children():
		_accumulate_mesh_bounds(root, child, state)


func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	var result := AABB()
	var has_point := false
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				var corner := aabb.position + Vector3(aabb.size.x * x, aabb.size.y * y, aabb.size.z * z)
				var transformed_corner := transform * corner
				if has_point:
					result = result.expand(transformed_corner)
				else:
					result = AABB(transformed_corner, Vector3.ZERO)
					has_point = true
	return result


func _play_first_animation(root: Node) -> void:
	var animation_players: Array[AnimationPlayer] = []
	_collect_animation_players(root, animation_players)
	for animation_player in animation_players:
		var animation_names := animation_player.get_animation_list()
		if animation_names.is_empty():
			continue
		var animation_name := String(animation_names[0])
		var animation := animation_player.get_animation(animation_name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR
		animation_player.play(animation_name)


func _collect_animation_players(node: Node, result: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer:
		result.append(node as AnimationPlayer)
	for child in node.get_children():
		_collect_animation_players(child, result)


func _add_platform(model_count: int, row_count: int) -> void:
	var width := maxf(float(columns - 1) * item_spacing + platform_margin * 2.0, 10.0)
	var depth := maxf(float(row_count - 1) * row_spacing + platform_margin * 2.0, 10.0)

	var platform_body := StaticBody3D.new()
	platform_body.name = "ShowcasePlatform"
	platform_body.position = Vector3(0.0, -PLATFORM_HEIGHT * 0.5, 0.0)
	add_child(platform_body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(width, PLATFORM_HEIGHT, depth)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	platform_body.add_child(collision)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, PLATFORM_HEIGHT, depth)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PlatformMesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material(platform_color)
	platform_body.add_child(mesh_instance)

	var label := Label3D.new()
	label.name = "ModelCountLabel"
	label.position = Vector3(width * 0.5 - 1.35, 0.25, depth * 0.5 - 0.7)
	label.rotation.x = deg_to_rad(-90.0)
	label.text = "%d models" % model_count
	label.font_size = 36
	label.modulate = Color(0.82, 0.78, 0.66, 1.0)
	add_child(label)


func _add_title_label(model_count: int, row_count: int) -> void:
	var depth := maxf(float(row_count - 1) * row_spacing + platform_margin * 2.0, 10.0)
	var label := Label3D.new()
	label.name = "ShowcaseTitleLabel"
	label.position = Vector3(0.0, target_model_extent + 1.4, -depth * 0.5 + 1.25)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = showcase_title
	if not pack_note.is_empty():
		label.text += "\n" + pack_note
	label.text += "\n%d imported glTF models" % model_count
	label.font_size = 50
	label.modulate = title_label_color
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	add_child(label)


func _add_item_label(slot: Node3D, text: String, display_height: float) -> void:
	var label := Label3D.new()
	label.name = "Label"
	label.position = Vector3(0.0, display_height + 0.35, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = text
	label.font_size = 22
	label.modulate = item_label_color
	label.outline_size = 5
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	slot.add_child(label)


func _add_hud_label(model_count: int, error_message: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "ShowcaseHUD"
	add_child(layer)

	var label := Label.new()
	label.offset_left = 18.0
	label.offset_top = 18.0
	label.offset_right = 900.0
	label.offset_bottom = 116.0
	if error_message.is_empty():
		label.text = "%s: %d models. WASD fly, mouse look, Space/E up, Ctrl/Q down, Shift faster, Esc releases mouse." % [showcase_title, model_count]
	else:
		label.text = error_message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(label)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material


func _make_display_label(file_name: String) -> String:
	return file_name.get_basename().replace("_", " ")


func _sanitize_node_name(value: String) -> String:
	var sanitized := value
	for character in [" ", "-", "/", "\\", ":", ".", "\n", "(", ")", "[", "]"]:
		sanitized = sanitized.replace(character, "_")
	return sanitized
