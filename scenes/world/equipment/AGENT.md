# AGENT.md

## Equipment Model Wrappers
- Scenes in this folder are reusable visual wrappers for equipped/world equipment models.
- Hand-held equipment wrappers should include a `Marker3D` named `GripPoint_Primary` that represents the exact palm/grip point and orientation for the item.
- Attach `res://scripts/world/equipment/grip_point_marker.gd` to `GripPoint_Primary` so operators get editor-only colored cues while tuning: yellow origin, blue forward, green hand-up, and red right-hand reference.
- For hand-held weapons, tune `GripPoint_Primary` when the item-specific grip is wrong across bodies, and tune the child imported model when the model's visual axes/origin are wrong.
- Do not hardcode weapon placement in `HumanoidCharacter`; use this wrapper scene for item grip/orientation and the item resource `equipped_transform` for scale and small final offsets.
- If every one-hand weapon is wrong across characters, use `scenes/tools/humanoid_grip_socket_calibrator.tscn` to tune shared `RightHandGrip`; do not compensate inside each weapon wrapper.
- Keep wrapper roots at origin. Center/orient the visible model for sane editing, then place `GripPoint_Primary` on the handle or grip point where the skeleton hand should snap.
- Tune weapon placement in this order:
  1. Correct imported model orientation in the wrapper scene's visible `Model` child.
  2. Move/rotate `GripPoint_Primary` so the item grip aligns to the body's hand socket.
  3. Use the item resource `equipped_transform` for scale and small final hand offsets.
  4. Validate in `scenes/test_levels/armory_test.tscn` on normal idle, walk, run, and fighting/combat poses when available.
- `starting_equipment` expects item `.tres` resources, not these visual `.tscn` model wrappers.

## Current References
- `dagger_model.tscn` is the best current visual reference for a human-tuned one-hand fist grip.
- `axe_model.tscn` and `sword_model.tscn` should follow the same one-hand melee contract, but imported model axes can differ, so do not blindly copy exact transforms between weapon types.
- `iron_dagger.tres`, `iron_axe.tres`, and `iron_sword.tres` should keep `equipped_transform` mostly scale-only, with only tiny final offsets when the wrapper orientation is already correct.
- The one-hand melee contract is: `GripPoint_Primary` aligns to generated body `RightHandGrip`; runtime snaps the item marker to the hand socket with no per-character offsets.

## New Weapon Checklist
- Import the model and create a wrapper scene in this folder.
- Choose the closest grip contract from `resources/equipment_grip_profiles/`.
- Add and tune `GripPoint_Primary` as the natural grip or attachment point.
- If the imported asset has an inconvenient orientation, adjust the child imported model transform instead of changing code.
- Use the current dagger as a visual target for one-hand grip, but tune each model according to its own imported axes and pivot.
- Create an `ItemDefinition` resource in `resources/items/` and assign the wrapper as `world_scene` and `equipped_scene`.
- Set the item `grip_profile` and use `equipped_transform` for scale and small final offsets only.
- Validate the item in `armory_test.tscn` before treating the orientation as reusable.
