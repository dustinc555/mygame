extends GutTest
## Exercise the production appearance assembly used by actors and the editor.

const MALE_BODY = preload("res://features/actors/resources/character_body_archetypes/human_male.tres")
const FEMALE_BODY = preload("res://features/actors/resources/character_body_archetypes/human_female.tres")
const MALE_BROWS = preload("res://features/actors/resources/character_appearance/eyebrows_regular.tres")
const FEMALE_BROWS = preload("res://features/actors/resources/character_appearance/eyebrows_female.tres")


func test_default_styles_reuse_fitted_brows_and_lashes_in_every_body() -> void:
	for body in [MALE_BODY, FEMALE_BODY]:
		for sample in [[23, 1], [23, 60], [15, 60]]:
			var appearance := _appearance(body, sample[0], sample[1])
			var visual := Node3D.new()
			add_child_autofree(visual)
			var model := CharacterVisualAssembler.instantiate_body(body, appearance, "human", appearance.visual_body_type)
			visual.add_child(model)
			var brow := model.find_child("BrowDetail", true, false) as MeshInstance3D
			assert_not_null(brow)
			var source := brow.mesh.surface_get_material(0) as BaseMaterial3D
			var projection := HumanoidBodyProjection.new()
			add_child_autofree(projection)
			projection.configure_appearance(appearance)
			projection.set_base_eyebrow_visuals_visible(model, false)
			projection._setup_head_attachment_visuals(visual, projection._find_skeleton(model))
			assert_null(visual.get_node_or_null("AppearanceEyebrows"), "Default styles must not overlay vendor brows")
			assert_true(brow.visible, "The fitted brow/lash mesh remains visible")
			var tinted := brow.get_active_material(0) as BaseMaterial3D
			assert_not_same(tinted, source, "Color is instance-local, not a mutation of imported artwork")
			assert_same(tinted.albedo_texture, source.albedo_texture)
			assert_same(tinted.normal_texture, source.normal_texture)
			assert_eq(tinted.cull_mode, source.cull_mode)
			assert_eq(tinted.roughness, source.roughness)


func test_editor_uses_fitted_brows_and_recolors_without_rebuilding() -> void:
	var editor := CharacterEditorWindow.new()
	add_child_autofree(editor)
	editor.draft_appearance = _appearance(FEMALE_BODY)
	var model := editor._create_preview_model()
	add_child_autofree(model)
	editor._preview_model = model
	await get_tree().process_frame
	var brow := model.find_child("BrowDetail", true, false) as MeshInstance3D
	assert_null(model.find_child("AppearanceEyebrows", true, false))
	assert_true(editor.preview_has_custom_eyebrows(), "Embedded selected styles are customized too")
	var original := brow.mesh.surface_get_material(0) as BaseMaterial3D
	assert_true(editor._apply_preview_style_color(FEMALE_BROWS, "Eyebrows", FEMALE_BROWS.default_color))
	assert_same(brow.get_active_material(0).albedo_texture, original.albedo_texture)
	assert_eq(brow.get_active_material(0).albedo_color, original.albedo_color, "The authored style color preserves the accepted texture's brightness")
	var lighter := FEMALE_BROWS.default_color * 2.0
	lighter.a = 1.0
	assert_true(editor._apply_preview_style_color(FEMALE_BROWS, "Eyebrows", lighter))
	assert_eq(brow.get_active_material(0).albedo_color, Color(2, 2, 2, 1))
	assert_eq(original.albedo_color, Color.WHITE, "Recoloring leaves other actors and the import unchanged")


func test_thick_style_replaces_the_embedded_brow_lash_pair_without_duplicates() -> void:
	var thick: Resource = load("res://features/actors/resources/character_appearance/eyebrows_thick.tres")
	for age in [23, 15]:
		var editor := CharacterEditorWindow.new()
		add_child_autofree(editor)
		editor.draft_appearance = _appearance(MALE_BODY, age)
		editor.draft_appearance.eyebrow_style = thick
		var model := editor._create_preview_model()
		add_child_autofree(model)
		editor._preview_model = model
		await get_tree().process_frame
		var brow := model.find_child("BrowDetail", true, false) as MeshInstance3D
		assert_false(brow.visible, "Do not stack the embedded pair with the replacement pair")
		var replacement := model.find_child("AppearanceEyebrows", true, false)
		assert_not_null(replacement)
		var source := CharacterVisualAssembler.instantiate_head_attachment(thick, age, Color.WHITE)
		var source_mesh := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var copied_mesh := replacement.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		assert_same(copied_mesh.mesh, source_mesh.mesh, "The complete replacement includes its authored lashes")
		source.free()


func test_external_default_fallback_hides_vendor_placeholder_brows() -> void:
	var scene: PackedScene = load("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Female_FullBody.gltf")
	var visual := Node3D.new()
	add_child_autofree(visual)
	var model := scene.instantiate()
	visual.add_child(model)
	var projection := HumanoidBodyProjection.new()
	add_child_autofree(projection)
	projection.configure_appearance(_appearance(FEMALE_BODY))
	projection._setup_head_attachment_visuals(visual, projection._find_skeleton(model))
	assert_not_null(visual.get_node_or_null("AppearanceEyebrows"))
	var brows := model.find_child("*Eyebrow*", true, false) as MeshInstance3D
	assert_not_null(brows)
	assert_false(brows.visible)


func test_actor_automatic_default_and_rebuild_keep_the_fitted_style() -> void:
	var actor := HumanoidCharacter.new()
	actor.member_name = "Appearance fixture"
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.appearance_data = _appearance(MALE_BODY)
	actor.appearance_data.eyebrow_style = null
	actor.appearance_data.hair_color = Color(0.48, 0.28, 0.12)
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	body_mesh.mesh = CapsuleMesh.new()
	body_mesh.position.y = 1.0
	actor.add_child(body_mesh)
	add_child_autofree(actor)
	await get_tree().process_frame
	var projection := actor.get_body_projection() as HumanoidBodyProjection
	assert_not_null(projection)
	assert_same(projection.appearance_data.eyebrow_style, MALE_BROWS)
	assert_eq(projection.appearance_data.eyebrow_color, actor.appearance_data.hair_color)
	var visual := projection.get_visual_root()
	assert_not_null(visual)
	assert_null(visual.get_node_or_null("AppearanceEyebrows"))
	var brow := visual.find_child("BrowDetail", true, false) as MeshInstance3D
	var color_before: Color = brow.get_active_material(0).albedo_color
	projection.rebuild_visual_for_appearance()
	await get_tree().process_frame
	var rebuilt := projection.get_visual_root()
	assert_null(rebuilt.get_node_or_null("AppearanceEyebrows"))
	var rebuilt_brow := rebuilt.find_child("BrowDetail", true, false) as MeshInstance3D
	assert_true(rebuilt_brow.visible)
	assert_eq(rebuilt_brow.get_active_material(0).albedo_color, color_before)


func _appearance(body: Resource, age: int = 23, toughness: int = 1) -> CharacterAppearanceData:
	var result := CharacterAppearanceData.new()
	result.body_archetype = body
	result.visual_body_type = 2 if body == MALE_BODY else 3
	result.visual_age_years = age
	result.visual_toughness_level = toughness
	result.eyebrow_style = MALE_BROWS if body == MALE_BODY else FEMALE_BROWS
	result.eyebrow_color = Color(0.65, 0.4, 0.18)
	return result
