# AGENT.md

## Character Body Archetype Resources
- Body archetypes define a concrete body/rig visual target such as `human_male` or `human_female`.
- Current human base archetypes are `human_male` using `Superhero_Male_FullBody.gltf` and `human_female` using `Superhero_Female_FullBody.gltf`.
- Body archetypes should reference the base visual scene and visual body type. Do not store gameplay inventory, stats, or item-specific clothing data here.
- Worn clothing should be skinned to a compatible skeleton and selected through `EquipmentVisualDefinition` entries on items.
- Future fit-family metadata should describe reusable clothing compatibility groups, not individual item exceptions.
- When adding a new race/body, first decide whether it can reuse an existing fit family. Only add per-item archetype visuals when the shared fit is visibly wrong.
- Do not auto-hide body parts from an archetype. Body hiding must be operator-authored per item/archetype if it is ever enabled.
