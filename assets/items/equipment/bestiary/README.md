# Bestiary equipment assets

Project-owned item assets derived from the purchased Quaternius Bestiary Dungeon Monsters Kit. The vendor GLBs remain unchanged. **Quaternius Asset License (QAL) v1.0 applies to these derivatives; do not redistribute them as a standalone asset collection.** See `assets/vendor/quaternius/bestiary_dungeon_monsters/License_Source.txt`.

## Catalog and source mapping

The authoritative machine-readable catalog is
`assets/vendor/quaternius/bestiary_dungeon_monsters/equipment_manifest.json`.
It contains every item resource path, original mesh name, slot, race fit, icon,
world/equipped scene, inventory footprint, weight, and weapon modifier.
Its `models` dictionary uses GLB filenames as keys, with `race_id`,
`removable_meshes`, and `default_items` for each of the seven vendor models.

All item definitions live directly in `features/inventory/resources/items/`,
so the existing non-recursive item catalog discovers them without a new registry.
For each suffix below, the stable ID is `bestiary.<suffix>`, the definition is
`bestiary_<suffix>.tres`, and this asset directory contains
`<suffix>/{equipped.tscn,dropped.tscn,icon.svg}`.

| Suffix | Source GLB | Mesh node(s) | Slot | Wearable race fit |
|---|---|---|---|---|
| hellwarden_sword | Hellwarden | Hellwarden_Sword | weapon | unrestricted |
| imp_mace | Imp | Imp_Mace | weapon | unrestricted |
| puglin_stick | Puglin | Puglin_Stick | weapon | unrestricted |
| skeleton_axe | Skeleton_A | Skeleton_Axe | weapon | unrestricted |
| skeleton_sword | Skeleton_B | Skeleton_Sword | weapon | unrestricted |
| tidebreaker_anchor | Tidebreaker | Tidebreaker_Anchor | weapon | unrestricted |
| hellwarden_cuirass | Hellwarden | Hellwarden_Torso, Hellwarden_Gorget, Hellwarden_Pauldrons | chest | hellwarden |
| hellwarden_leg_armor | Hellwarden | Hellwarden_Hips, Hellwarden_Cuisses | legs | hellwarden |
| imp_shackles | Imp | Imp_Chains | hands | imp |
| imp_shorts | Imp | Imp_Shorts | legs | imp |
| imp_spiked_collar | Imp | Imp_SpikedCollar | chest | imp |
| skeleton_greaves | Skeleton_A, Skeleton_B | Skeleton_Greaves | legs | skeleton |
| skeleton_horned_helm | Skeleton_A | Skeleton_HelmHorns | head | skeleton |
| skeleton_pauldrons | Skeleton_A | Skeleton_Pauldron | chest | skeleton |
| skeleton_helm | Skeleton_B | Skeleton_Helm | head | skeleton |

The existing slot contract has no neck/shoulder/waist slots: Hellwarden's upper
armor is one chest item and its hips/cuisses are one leg item. The imp's authored
Chains mesh contains both wrist and ankle shackles; hands is its primary slot.
The collar is upper-body armor in chest, not head anatomy. Greaves are shin armor
in legs, not footwear. `Hellwarden_Skull`, `Puglin_Tusks`, and all Body meshes remain
anatomy. Lycan has no separately authored removable equipment. No anatomical
meshes or invented clothing were extracted.

## Equipped and dropped contracts

- **Weapons:** six independent static scenes, no Skeleton3D, Skin, or vertex
  bone/weight arrays. All source weapons were rigidly weighted to `hand_r`.
  Vertices and directional attributes were converted from source bind space into
  the shared default `right_hand_one_hand` socket's local grip space:
  `v_equipped = inverse(shared_socket) * source_inverse_bind * v_source`.
  `GripPoint_Primary` and `ItemDefinition.equipped_transform` are identity;
  `one_hand_melee.tres` supplies the existing grip contract. Do not apply the old
  humanoid FBX weapon scale of 0.189: these assets already use meters. The source
  hand-rest and shared-socket transforms are recorded in `extraction_verification.json`.
- **Wearables:** original full root/Armature/Skeleton3D coordinates, bone names,
  rest transforms, source vertices/weights, and Skin binds are preserved. Only
  the item's selected mesh nodes remain. Each definition provides both its
  `equipped_scene` and an `EquipmentVisualDefinition` with the race identifier as
  `body_archetype_id`; the integration must bind to the matching authored rig.
  No body-region replacement or surface inflation is requested.
- **Dropped scenes:** independently static and centered horizontally, with the
  visible bottom at Y=0. They do not retain a hidden monster body or live rig.
- **Materials:** shared project-owned materials and original GPU-compressed
  textures, including normal, packed metallic/roughness, and emission maps where
  supplied. Skeleton variants share one material family. Packed channels share
  textures rather than duplicating them. No vendor/cache subresource dependency
  is needed by the extracted visual assets.
- **SVGs:** fifteen distinct 128px vector illustrations projected from actual
  source triangles and source colors. The four imp cuffs are arranged compactly
  for the inventory icon only; worn geometry remains unchanged.

Weapon balance values are explicit initial content tuning, not a combat-balance
claim. The nine wearable definitions follow existing clothing content and do not
invent armor modifiers. See the manifest for all numeric values.

## Focused verification

`load_verification.json` records a real Godot 4.7.2 headless load/instantiate pass:
15 item definitions, 30 equipped/dropped scenes, 15 imported SVG icons, 6 weapons,
9 wearables, 16,780 equipped vertices, and 23,026 equipped triangles. Validation
checked catalog discoverability, IDs, race fields, exact worn vertices/weights,
original skeleton rests/binds, static world geometry and grounding, valid grip
markers, and 18 source-identical compressed textures including their mipmaps.
Skeleton_A/B greaves, skeleton rests, and skin binds match, permitting one shared
item. The maximum saved-weapon source-pose roundtrip error was
0.000000961096020546393 meters.

The seven vendor GLB SHA-256 values still match the preexisting
`animation_inspection.json`. SVG import was limited to the fifteen exact files in
an isolated minimal project at identical `res://` paths, copying only their
sidecars/cache files back. No whole-project import or unrelated import cleanup
was performed. The rendered inventory icon sheet was inspected for visibility
and clipping. These checks establish item-asset correctness, **not** completed
actor equip/loot behavior, animation fit, or cross-race visual grip acceptance;
those belong to the actor integration verification.
