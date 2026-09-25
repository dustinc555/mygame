extends GutTest

const PROFILE = preload("res://features/world_sim/resources/population_appearance_profile.gd")
const FACTION = preload("res://features/factions/resources/faction_definition.gd")

func test_faction_weighted_races_exclude_zero_weight_and_preserve_palette() -> void:
	var faction := FACTION.new()
	var properties := faction.get_property_list().map(func(p): return str(p.name))
	assert_has(properties, "race_weights", "Faction authors race probabilities")
	if not properties.has("race_weights"):
		return
	var profile := PROFILE.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8271
	for index in 20:
		var appearance = profile.call("create_appearance", rng, {"human": 0.0, "desert_puglin": 1.0})
		assert_eq(appearance.character_race.race_id, "desert_puglin")
		assert_has(appearance.character_race.skin_tones, appearance.skin_color)
		assert_eq(appearance.character_race.skin_textures.size(), 3)
		assert_eq(appearance.body_archetype.grip_socket_profile, load("res://features/actors/resources/humanoid_grip_socket_profiles/puglin.tres"))

func test_weighted_race_draws_are_seeded_and_mixed() -> void:
	var method = PROFILE.new().get_method_list().filter(func(m): return m.name == "create_appearance")[0]
	if method.args.size() < 2:
		fail_test("Population generation needs faction weights")
		return
	var profile := PROFILE.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3456
	var counts := {"human": 0, "desert_puglin": 0}
	for index in 200:
		var appearance = profile.call("create_appearance", rng, {"human": 0.7, "desert_puglin": 0.3})
		counts[appearance.character_race.race_id] += 1
	assert_between(counts.desert_puglin, 35, 85)
	assert_gt(counts.human, counts.desert_puglin)
