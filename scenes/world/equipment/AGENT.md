# AGENT.md

## Equipment Model Wrappers
- Scenes in this folder are reusable visual wrappers for equipped/world equipment models.
- The wrapper root transform is preserved when equipped. This is intentional and required for scalable artist-authored item placement.
- The wrapper root origin should represent the intended attachment point, such as the weapon grip point, not whatever origin the imported asset happened to use.
- For hand-held weapons, tune the wrapper root and/or child imported model transform so the wrapper fits naturally inside the character fist in the normal standing idle pose.
- Do not hardcode weapon placement in `HumanoidCharacter`; use this wrapper scene for imported model orientation/pivot correction and the item resource `equipped_transform` for scale and small final offsets.
- Tune weapon placement in this order:
  1. Correct imported model orientation and grip/pivot in the weapon wrapper scene.
  2. Use the item resource `equipped_transform` for scale and small final hand offsets.
  3. Validate in `scenes/test_levels/armory_test.tscn` on normal idle, walk, run, and fighting/combat poses when available.
- `starting_equipment` expects item `.tres` resources, not these visual `.tscn` model wrappers.

## Current References
- `dagger_model.tscn` is the best current visual reference for a human-tuned one-hand fist grip.
- `axe_model.tscn` and `sword_model.tscn` should follow the same one-hand melee contract, but imported model axes can differ, so do not blindly copy exact transforms between weapon types.
- `iron_dagger.tres`, `iron_axe.tres`, and `iron_sword.tres` should keep `equipped_transform` mostly scale-only, with only tiny final offsets when the wrapper orientation is already correct.
- The one-hand melee contract is: wrapper attaches through the item pivot, handle sits in the clenched fist, blade/head projects naturally from the fist, and no per-item code is needed.

## New Weapon Checklist
- Import the model and create a wrapper scene in this folder.
- Choose the closest grip contract from `resources/equipment_grip_profiles/`.
- Align the wrapper so its root/origin is the natural grip or attachment point.
- If the imported asset has an inconvenient orientation, adjust the child imported model transform instead of changing code.
- Use the current dagger as a visual target for one-hand grip, but tune each model according to its own imported axes and pivot.
- Create an `ItemDefinition` resource in `resources/items/` and assign the wrapper as `world_scene` and `equipped_scene`.
- Set the item `grip_profile` and use `equipped_transform` for scale and small final offsets only.
- Validate the item in `armory_test.tscn` before treating the orientation as reusable.
