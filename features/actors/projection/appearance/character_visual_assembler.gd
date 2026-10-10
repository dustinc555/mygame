@tool
extends RefCounted

class_name CharacterVisualAssembler


static func instantiate_body(body_archetype: Resource, appearance: Resource, race_id: String, body_type: int, fallback_scene: PackedScene = null) -> Node3D:
	var age_years := int(appearance.get("visual_age_years")) if appearance != null else CharacterVisualRules.DEFAULT_ADULT_AGE
	var toughness_level := int(appearance.get("visual_toughness_level")) if appearance != null else 0
	var visual_scene: PackedScene = CharacterVisualRules.get_body_visual_scene(body_archetype, age_years, toughness_level)
	if visual_scene == null:
		visual_scene = fallback_scene
	if visual_scene == null:
		return null
	var instance: Node = visual_scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return null
	var root := instance as Node3D
	apply_skin(root, appearance, race_id, body_type)
	return root


static func apply_skin(root: Node, appearance: Resource, race_id: String, body_type: int) -> bool:
	if appearance == null:
		return false
	var race: Resource = appearance.get("character_race")
	if race != null and race.has_method("apply_skin_palette") and race.call("apply_skin_palette", root, appearance.get("skin_color")):
		return true
	if bool(appearance.get("skin_color_customized")) and race_id in ["human", "rustdead"]:
		return SkinTextureBuilder.apply_custom_skin_materials(root, race_id, body_type, appearance.get("skin_color"))
	return false


static func instantiate_head_attachment(style: Resource, age_years: int, color: Color) -> Node3D:
	var visual_scene := CharacterVisualRules.get_head_attachment_scene(style, age_years)
	if visual_scene == null:
		return null
	var instance := visual_scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return null
	var root := instance as Node3D
	if bool(style.get("colorize")):
		_apply_color_material(root, color)
	return root


## Returns true when the style is already part of the body (including its lashes).
## Duplicate materials, not meshes or textures, so recoloring never edits the import.
static func apply_embedded_head_attachment(root: Node, style: Resource, color: Color) -> bool:
	var mesh_instance := get_embedded_head_attachment(root, style)
	if mesh_instance == null or mesh_instance.mesh == null:
		return false
	var definition := style as HeadAttachmentStyleDefinition
	mesh_instance.visible = true
	if definition.colorize:
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface_index) as BaseMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as BaseMaterial3D
			# The texture already contains the authored default color. A plain
			# multiplicative tint would darken it twice and make blond brows black.
			var reference := definition.default_color
			material.albedo_color = source.albedo_color * Color(
				color.r / maxf(reference.r, 0.001),
				color.g / maxf(reference.g, 0.001),
				color.b / maxf(reference.b, 0.001),
				color.a)
			mesh_instance.set_surface_override_material(surface_index, material)
	return true


static func get_embedded_head_attachment(root: Node, style: Resource) -> MeshInstance3D:
	if root == null or not (style is HeadAttachmentStyleDefinition):
		return null
	var definition := style as HeadAttachmentStyleDefinition
	if definition.embedded_mesh_name.is_empty():
		return null
	return root.find_child(str(definition.embedded_mesh_name), true, false) as MeshInstance3D


static func is_base_eyebrow_visual(node: Node) -> bool:
	if not (node is MeshInstance3D):
		return false
	var mesh_name := str(node.name).to_lower()
	return mesh_name.contains("eyebrow") or mesh_name == "browdetail"


static func set_base_eyebrows_visible(root: Node, visible_flag: bool) -> void:
	if root == null:
		return
	if is_base_eyebrow_visual(root):
		(root as MeshInstance3D).visible = visible_flag
	for child in root.get_children():
		set_base_eyebrows_visible(child, visible_flag)


static func _apply_color_material(root: Node, color: Color) -> void:
	if root is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.82
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_color_material(child, color)
