extends GutTest

const BODY := preload("res://features/actors/resources/character_body_archetypes/character_body_archetype_definition.gd")
const PROFILE := preload("res://features/actors/resources/wardrobe/wardrobe_body_profile.gd")
const VISUAL := preload("res://features/inventory/resources/items/equipment_visual_definition.gd")
const BINDING := preload("res://features/inventory/resources/items/clothing_binding.gd")
const ITEM := preload("res://features/inventory/resources/items/item_definition.gd")


func test_one_source_visual_resolves_for_distinct_registered_bodies() -> void:
	var male := BODY.new()
	var female := BODY.new()
	male.archetype_id = "male"
	female.archetype_id = "female"
	assert_true(male.has_method("get_wardrobe_profile"), "Body owns its shared clothing registration")
	if not male.has_method("get_wardrobe_profile"):
		return
	var male_profile := PROFILE.new()
	male_profile.body_scene_path = "res://male_test.glb"
	var female_profile := PROFILE.new()
	female_profile.body_scene_path = "res://female_test.glb"
	male.wardrobe_profiles[male_profile.body_scene_path] = male_profile
	female.wardrobe_profiles[female_profile.body_scene_path] = female_profile
	male.regular_visual_scene = PackedScene.new()
	male.regular_visual_scene.take_over_path(male_profile.body_scene_path)
	female.regular_visual_scene = PackedScene.new()
	female.regular_visual_scene.take_over_path(female_profile.body_scene_path)
	var visual := VISUAL.new()
	var binding := BINDING.new()
	binding.reference_profile = male_profile
	visual.clothing_binding = binding
	visual.visual_scene = PackedScene.new()
	var item := ITEM.new()
	item.equipped_visuals.append(visual)
	item.equipped_scene = visual.visual_scene
	assert_eq(item.get_equipment_visual_for_body_archetype(male, male_profile.body_scene_path), visual)
	assert_eq(item.get_equipment_visual_for_body_archetype(female, female_profile.body_scene_path), visual)
	assert_eq(item.get_equipped_scene_for_body_archetype(female), visual.visual_scene)
	assert_eq(male.get_wardrobe_profile(), male_profile)
	assert_eq(female.get_wardrobe_profile(female_profile.body_scene_path), female_profile)
	assert_null(female.get_wardrobe_profile("res://missing_test.glb"), "Never substitute the regular body registration for a missing build")


func test_unregistered_body_never_receives_an_unfitted_source_fallback() -> void:
	var visual := VISUAL.new()
	var binding := BINDING.new()
	binding.reference_profile = PROFILE.new()
	visual.clothing_binding = binding
	visual.visual_scene = PackedScene.new()
	var item := ITEM.new()
	item.equipped_visuals.append(visual)
	item.equipped_scene = visual.visual_scene
	var unsupported := BODY.new()
	unsupported.archetype_id = "robot"
	assert_null(item.get_equipped_scene_for_body_archetype(unsupported))
	assert_null(item.get_equipped_scene_for_body_archetype(null))
	assert_null(item.get_equipment_visual_for_body_archetype(unsupported))


func test_legacy_unbound_item_keeps_its_original_fallback() -> void:
	var item := ITEM.new()
	item.equipped_scene = PackedScene.new()
	assert_eq(item.get_equipped_scene_for_body_archetype(BODY.new()), item.equipped_scene)
