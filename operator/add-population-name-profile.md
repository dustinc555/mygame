# Add Population Name Profile

Use this to give generated settlement residents deterministic display names instead of placeholders like `Farmer 19`.

1. Create or duplicate a `PopulationNameProfile` resource under `res://resources/world_sim/population_name_profiles/`.
2. Set `profile_id` and `display_name` to stable, readable values.
3. Use `body_specific_weight`, `neutral_weight`, and `nickname_weight` to shape the mix of masculine/feminine, neutral, and wasteland nickname names.
4. Leave the name arrays empty to use the shared curated defaults, or fill the arrays when a population needs a culture-specific pool.
5. Keep `unique_retry_count` high enough for the expected spawner size.
6. Keep `duplicate_name_chance` low; generated names are unique-first and only repeat after the available pool is exhausted.
7. For a faction-wide culture, assign the resource to `FactionDefinition.population_name_profile`.
8. For a settlement-specific culture, assign the resource to `SettlementDefinition.population_name_profile`.
9. For a local group such as slaves, guards, nobles, or fort occupiers, select the group's `SettlementPopulationSpawner` node and set `population_name_profile` there.
10. Keep `apply_name_profile_to_existing_residents` enabled if authored residents under the spawner should receive generated names too.

Resolution order is spawner override, settlement override, faction default, then the shared curated default pool. This lets conquered towns keep local population names while new forts or replacement populations use the controlling faction's culture.

Current defaults are curated normal, neutral, and wasteland nickname pools. If larger external datasets are added later, add them behind `PopulationNameProfile` resources rather than hardcoding town-specific names in scenes.

Done check: run the scene and confirm residents have readable names from the profile, no `Farmer 19` or `Raider 20` placeholders, and no repeated names in the same resident group.
