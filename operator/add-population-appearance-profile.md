# Add Population Appearance Profile

Use this to give generated settlement residents race, sex/body type, clothing, hair, skin, and conservative body variation.

1. Create or duplicate a `PopulationAppearanceProfile` resource under `res://resources/world_sim/population_appearance_profiles/`.
2. Set `profile_id` and `display_name` to stable, readable values.
3. Leave `allowed_races` empty for any available race, or add explicit race resources for restricted populations.
4. Set `allowed_body_type_flags` to the sex/body types this population can generate.
5. Add compatible hair styles and optional beard styles.
6. Use the default natural hair palette unless the group needs a curated natural subset.
7. Fill outfit pools for `chest_items`, `leg_items`, `feet_items`, and optionally `head_items`.
8. Keep skeleton ranges conservative; avoid extremes for background townspeople.
9. Select the town's `SettlementPopulationSpawner` node.
10. Set `population_appearance_profile` to the profile resource.
11. Keep `apply_profile_to_existing_residents` enabled if authored residents under the spawner should receive the same generated look.

Done check: run the scene and confirm residents are clothed, have natural hair/skin colors, and do not use naked default bodies.
