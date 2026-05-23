# Add Faction Culture

Use this when adding a faction that needs operator-editable names, behavior, personality, laws, and formal diplomacy at scale.

1. Create or duplicate a faction resource under `res://resources/world_sim/factions/`.
2. Set `faction_id`, `display_name`, `description`, `open_access`, reputation threshold, and permanent hostility as needed.
3. Use `starting_war_faction_ids` for formal starting wars. Do not use reputation to imply alliance or war.
4. Use `default_hostile_faction_ids` only for non-diplomatic always-hostile cases.
5. Assign `behavior_profile` to a `SettlementBehaviorProfile` under `res://resources/world_sim/behavior_profiles/`.
6. Assign `personality_profile` to a `FactionPersonalityProfile` under `res://resources/world_sim/personality_profiles/`.
7. Assign `law_profile` to a `FactionLawProfile` under `res://resources/world_sim/law_profiles/`.
8. Assign `population_name_profile` to a `PopulationNameProfile` under `res://resources/world_sim/population_name_profiles/`.
9. Add the faction resource to the scene's `WorldSimRegistry.faction_definitions`, or reference it from a `SettlementDefinition.faction_definition`.
10. For special settlements, set settlement-level profile overrides on `SettlementDefinition`; these override faction defaults without changing the faction resource.
11. For special groups inside a settlement, set spawner-level population profiles; these override settlement and faction defaults for that local group only.

Use local overrides for conquered towns, dual populations, slaves, garrisons, nobles, cult enclaves, or any group that should not inherit the faction default culture.

Done check: load the scene and confirm generated residents use faction names by default, local spawner overrides still work, and buildings under the settlement use the expected law profile for trespass response.

The Factions menu shows formal diplomacy, player reputation, and favor points. Reputation labels are `Vilified`, `Hostile`, `Neutral`, `Accepted`, `Friendly`, and `Beloved`; formal diplomacy is separate and includes `War`, `Hostile`, `Neutral`, `Truce`, `Trade`, `Alliance`, `Vassal`, `Tributary`, and `Protectorate`.
