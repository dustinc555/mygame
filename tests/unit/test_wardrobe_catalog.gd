extends GutTest
## Protect the saved authoring contract independently of the fitter's synthetic tests.
const CATALOG = preload("res://tools/outfitter/outfitter_catalog.gd")
const VENDOR := "res://assets/vendor/quaternius/modular_character_outfits_fantasy/"
const LEATHER := "res://assets/items/equipment/traveler_"

func test_every_catalog_garment_uses_one_source_for_all_registered_humans() -> void:
	var catalog = CATALOG.new()
	var garments := 0
	for item: ItemDefinition in catalog.items:
		if item.world_scene == null: continue
		var source_path := item.world_scene.resource_path
		if not source_path.begins_with(VENDOR) and not source_path.begins_with(LEATHER): continue
		garments += 1
		assert_eq(item.equipped_visuals.size(), 1, item.display_name + ": one maintained clothing model")
		if item.equipped_visuals.size() != 1: continue
		var visual: EquipmentVisualDefinition = item.equipped_visuals[0]
		assert_not_null(visual.clothing_binding, item.display_name + ": shared binding")
		if visual.clothing_binding == null: continue
		assert_eq(visual.visual_scene.resource_path, source_path, "Worn and dropped art share the one source")
		assert_eq(visual.clothing_binding.source_scene_path, source_path)
		assert_true(visual.body_fits.is_empty(), "No garment-by-body replacement lookup")
		assert_true(visual.replaces_body_slots.is_empty(), "Fitting must not hide anatomy")
		assert_eq(visual.surface_offset_ratio, 0.0, "Clearance belongs to the binding, applied once")
		for sex in ["male", "female"]:
			var body: Resource = load("res://features/actors/resources/character_body_archetypes/human_" + sex + ".tres")
			for build in ["regular", "heroic", "teen"]:
				var scene: PackedScene = body.get(build + "_visual_scene")
				var profile: Resource = body.get_wardrobe_profile(scene.resource_path)
				assert_not_null(profile, sex + " " + build + ": body owns reusable registration")
				assert_same(item.get_equipment_visual_for_body_archetype(body, scene.resource_path), visual, item.display_name + " must reuse its source across bodies")
	assert_gt(garments, 0, "Discover actual saved clothing rather than passing on an empty catalog")
