# AGENT.md

## Clothing Visual Wrappers
- Scenes in this folder are reusable worn-clothing visual wrappers, not gameplay item resources.
- Do not reference these scenes directly from `starting_equipment`; create an `ItemDefinition` in `resources/items/` and reference the wrapper through an `EquipmentVisualDefinition` entry.
- Use wrappers to kitbash, tint, or lightly compose imported clothing meshes without editing vendor `.gltf` files.
- Worn clothing should remain skinned to a compatible humanoid skeleton so `HumanoidCharacter` can bind its `MeshInstance3D` nodes to the live character skeleton.
- Keep body hiding out of these wrappers. Fit should be handled through compatible meshes and per-archetype `EquipmentVisualDefinition.surface_offset_ratio` / `equipped_transform`.
- If a wrapper becomes item-specific, name it after the item and body fit, such as `travel_cloak_male.tscn`.
