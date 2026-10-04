extends GutTest

const APPROVED_ALBEDO := "res://assets/characters/humans/frontier_regular/source/textures/male_abdomen_basecolor.png"


func test_human_regular_male_palette_source_is_the_accepted_softened_artwork() -> void:
	var source_path := SkinTextureBuilder.get_source_texture_path(2, "regular")
	assert_eq(source_path, APPROVED_ALBEDO)
	var source := Image.load_from_file(ProjectSettings.globalize_path(source_path))
	assert_not_null(source, "Offline palette generation must read the .gdignore source without importing it")
	assert_false(source.is_empty())


func test_other_palette_sources_remain_vendor_artwork() -> void:
	for race_id in ["human", "rustdead"]:
		for variant in SkinTextureBuilder.get_supported_body_variants():
			for body_type in [2, 3]:
				if race_id == "human" and variant == "regular" and body_type == 2:
					continue
				assert_eq(SkinTextureBuilder.get_source_texture_path(body_type, variant, race_id), SkinTextureBuilder.SOURCE_TEXTURE_PATHS_BY_VARIANT[variant][body_type])


func test_every_runtime_regular_male_tone_keeps_the_approved_abdominal_contrast() -> void:
	var approved := Image.load_from_file(ProjectSettings.globalize_path(APPROVED_ALBEDO))
	approved.resize(768, 768, Image.INTERPOLATE_BILINEAR)
	# Two samples within the authored abdomen mask: a muscle highlight and its
	# adjacent crease. Recoloring may change hue, not restore the old deep crease.
	var highlight := Vector2i(88, 392)
	var crease := Vector2i(104, 392)
	var approved_ratio := approved.get_pixelv(highlight).r / approved.get_pixelv(crease).r
	var body: Resource = load("res://features/actors/resources/character_body_archetypes/human_male.tres")
	var appearance := CharacterAppearanceData.new()
	appearance.visual_age_years = 23
	appearance.visual_toughness_level = 1
	appearance.skin_color_customized = true
	for tone in SkinTextureBuilder.NATURAL_SKIN_TONES:
		appearance.skin_color = tone
		var root := CharacterVisualAssembler.instantiate_body(body, appearance, "human", 2)
		var mesh := root.find_child("RegularMale", true, false) as MeshInstance3D
		var source := mesh.mesh.surface_get_material(0) as BaseMaterial3D
		var material := mesh.get_active_material(0) as BaseMaterial3D
		assert_not_same(material, source)
		assert_same(material.normal_texture, source.normal_texture, "The approved softened normal is not replaced")
		assert_eq(material.normal_scale, source.normal_scale)
		var image := material.albedo_texture.get_image()
		if image.is_compressed():
			assert_eq(image.decompress(), OK)
		var actual_ratio := image.get_pixelv(highlight).r / image.get_pixelv(crease).r
		assert_almost_eq(actual_ratio, approved_ratio, 0.025, "Faint abs survive runtime palette selection for %s" % tone)
		root.free()
