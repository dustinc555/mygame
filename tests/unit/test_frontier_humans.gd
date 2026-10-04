extends GutTest
## Accepted artwork must be selected by ordinary gameplay resources, not a lab catalog.

func test_canonical_humans_select_the_accepted_body_for_age_and_build() -> void:
	for sex in ["male", "female"]:
		var body: Resource = load("res://features/actors/resources/character_body_archetypes/human_" + sex + ".tres")
		for sample in [["regular", 23, 1], ["heroic", 23, 60], ["teen", 15, 60]]:
			var folder := "frontier_regular" if sample[0] == "regular" else "frontier_variants"
			var expected: String = "res://assets/characters/humans/" + folder + "/" + sex + "_" + sample[0] + ".glb"
			var selected := CharacterVisualRules.get_body_visual_scene(body, sample[1], sample[2])
			assert_not_null(selected)
			assert_eq(selected.resource_path, expected)
		assert_same(body.visual_scene, body.regular_visual_scene)
