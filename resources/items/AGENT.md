# AGENT.md

## Item Resources
- Item resources define gameplay behavior and metadata. Prefer data changes here over one-off code or test-level logic.
- Equipment must be represented by `ItemDefinition` `.tres` resources. Visual-only `.tscn` scenes are not valid `starting_equipment` entries.
- `starting_equipment` should reference item resources such as `res://resources/items/iron_dagger.tres`.
- `world_scene` is the scene used for world item display.
- `equipped_scene` or body-specific equipped scenes define the visual used when equipped.
- `grip_profile` chooses the reusable grip/stance contract for equipped items.
- `equipped_transform` is applied to an attachment pivot and should be used for scale and small final placement tweaks after the visual wrapper scene has a good origin/orientation.

## Clothing Fit
- Clothing should layer over the visible base character model.
- Do not hide base body meshes to solve clothing clipping.
- Use `equipped_surface_offset_ratio` to inflate clothing over the base body at runtime.
- Offset ratios are character-relative, not fixed world sizes, so they scale with the equipped character.
- Current clothing fit baselines:
  - Chest/body: about `0.018`
  - Legs: about `0.016`
  - Gloves/arms: about `0.014`
  - Feet: about `0.012`
  - Hood/head: about `0.004` or lower

## Weapon Fit
- Weapon model orientation and grip/pivot corrections should usually live in `scenes/world/equipment/*.tscn`.
- Weapon item resources should usually keep `equipped_transform` focused on scale and small final offsets.
- Validate hand-held weapon placement in normal standing idle before tuning other poses or animations.
- For one-hand melee, the item transform should usually be scale-only after the wrapper is correct. Tiny origin offsets are acceptable for final fist seating.

## Weapon Grip Profiles
- Phase-1 supported profiles are `one_hand_melee` and `offhand_shield`.
- Future profile families should include `two_hand_sword`, `two_hand_axe`, `two_hand_blunt`, `polearm`, `bow`, `crossbow`, and `thrown`.
- Two-handed and ranged weapons will require stance-specific animations or IK later; do not expect transforms alone to solve those classes.
- The current `iron_dagger.tres` plus `dagger_model.tscn` is the one-hand melee visual reference.
- Sword, axe, and dagger share the same grip contract, but their wrapper transforms may differ because imported model axes/pivots differ.

## New Weapon Resource Checklist
- Create or reuse an equipment wrapper scene under `scenes/world/equipment/`.
- Create an item resource in this folder.
- Set `equip_slot`, `world_scene`, `equipped_scene`, `grip_profile`, icon, grid size, weight, and stat modifiers.
- Use `equipped_transform` for scale and minor final offsets only.
- For `starting_equipment`, use the item resource, never the visual wrapper scene.
