# AGENT.md

## Item Resources
- Item resources define gameplay behavior and metadata. Prefer data changes here over one-off code or test-level logic.
- Equipment must be represented by `ItemDefinition` `.tres` resources. Visual-only `.tscn` scenes are not valid `starting_equipment` entries.
- `starting_equipment` should reference item resources such as `res://resources/items/iron_dagger.tres`.
- `world_scene` is the scene used for world item display.
- `equipped_scene` is for hand-held equipment that uses grip/socket attachment.
- `equipped_visuals` is for worn clothing/armor. Each entry should be an `EquipmentVisualDefinition` matched to a body archetype.
- `grip_profile` chooses the reusable grip/stance contract for equipped items.
- Item-level `equipped_transform` is for hand-held equipment scale and small final placement tweaks after body-socket to item-marker alignment.

## Clothing Fit
- Clothing should layer over the visible base character model.
- Do not hide base body meshes to solve clothing clipping unless an explicit operator-authored body-region system exists for that item and archetype.
- Use `EquipmentVisualDefinition.surface_offset_ratio` to inflate clothing over the base body at runtime.
- Use `EquipmentVisualDefinition.equipped_transform` for per-archetype fit corrections such as small torso width/depth changes.
- Offset ratios are character-relative, not fixed world sizes, so they scale with the equipped character.
- Do not use or reintroduce top-level `equipped_surface_offset_ratio`, `male_equipped_scene`, or `female_equipped_scene`; migrated clothing fit lives in `equipped_visuals`.
- Reuse visual entries across compatible body fit families when possible. Add exact archetype variants only when the shared fit fails.
- If a clothing piece is fake or visually wrong for the slot, remove it from content instead of keeping it as a misleading item. Peasant Sleeves were removed for this reason.
- Current clothing fit baselines:
  - Chest/body: about `0.018`
  - Legs: about `0.016`
  - Hands/arms: about `0.014`
  - Feet: about `0.012`
  - Hood/head: about `0.004` or lower

## New Clothing Resource Checklist
- Create an `ItemDefinition` resource in this folder with the correct `equip_slot`.
- Add `EquipmentVisualDefinition` entries under `equipped_visuals` for supported body archetypes.
- Point each visual entry at a skinned clothing mesh compatible with the target skeleton/body fit.
- Tune `surface_offset_ratio` and visual `equipped_transform` per archetype; do not change the gameplay item for one body's fit.
- Validate on `human_male` and `human_female` when both are supported, because Tomas and Mira can require different visual fit values.
- If a race/body has no acceptable visual, leave it unsupported rather than falling back to broken human clothing.

## Weapon Fit
- Weapon model orientation and grip/pivot corrections should usually live in `scenes/world/equipment/*.tscn`.
- Hand-held equipment wrappers should expose `GripPoint_Primary` as the item-side grip marker.
- Weapon item resources should usually keep `equipped_transform` focused on scale and small final offsets after marker-to-socket alignment.
- Validate hand-held weapon placement in normal standing idle before tuning other poses or animations.
- For one-hand melee, the item transform should usually be scale-only after the wrapper is correct. Tiny origin offsets are acceptable for final fist seating.

## Weapon Grip Profiles
- Phase-1 supported profiles are `one_hand_melee` and `offhand_shield`.
- Future profile families include `two_hand_weapon`, `polearm`, `bow`, `crossbow`, and `thrown`; split them into narrower profiles later only when animations/IK need that distinction.
- Two-handed and ranged weapons will require stance-specific animations or IK later; do not expect transforms alone to solve those classes.
- The current `iron_dagger.tres` plus `dagger_model.tscn` is the one-hand melee visual reference.
- Sword, axe, and dagger share the same grip contract, but their wrapper transforms may differ because imported model axes/pivots differ.

## Current Weapon Families
- One-hand melee: `iron_sword.tres`, `steel_sword.tres`, `golden_sword.tres`, `iron_axe.tres`, `hatchet.tres`, `war_hammer.tres`, `iron_dagger.tres`, `steel_dagger.tres`.
- Two-handed weapons: `greatsword.tres`, `claymore.tres`, `maul.tres`, `iron_axe_double.tres`.
- Polearms: `spear.tres`, `scythe.tres`.
- Bows: `wooden_bow.tres`, `recurve_bow.tres`, `golden_bow.tres`, `evil_bow.tres`.
- Shields: `round_shield.tres`, `round_shield_2.tres`, `heater_shield.tres`, `heater_shield_2.tres`, `golden_celtic_shield.tres`.
- Keep future-family item resources available as data, but do not treat them as fully supported combat items until matching animation/IK support and grip calibration exist.

## New Weapon Resource Checklist
- Create or reuse an equipment wrapper scene under `scenes/world/equipment/`.
- Create an item resource in this folder.
- Set `equip_slot`, `world_scene`, `equipped_scene`, `grip_profile`, icon, grid size, weight, and stat modifiers.
- Use `equipped_transform` for scale and minor final offsets only.
- For `starting_equipment`, use the item resource, never the visual wrapper scene.
