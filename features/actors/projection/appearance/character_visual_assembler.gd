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
	if appearance != null and bool(appearance.get("skin_color_customized")):
		SkinTextureBuilder.apply_custom_skin_materials(root, race_id, body_type, appearance.get("skin_color"))
	return root


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


static func _apply_color_material(root: Node, color: Color) -> void:
	if root is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.82
		(root as MeshInstance3D).material_override = material
	for child in root.get_children():
		_apply_color_material(child, color)
