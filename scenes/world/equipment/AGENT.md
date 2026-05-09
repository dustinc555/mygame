# AGENT.md

## Equipment Model Wrappers
- Scenes in this folder are reusable visual wrappers for equipped/world equipment models.
- The wrapper root origin should represent the intended attachment point, such as the weapon grip point, not whatever origin the imported asset happened to use.
- For hand-held weapons, tune the child imported model transform so the wrapper origin sits naturally inside the character fist in the normal standing idle pose.
- Do not hardcode weapon placement in `HumanoidCharacter`; use this wrapper scene for imported model orientation/pivot correction and the item resource `equipped_transform` for scale and small final offsets.
- Tune weapon placement in this order:
  1. Correct imported model orientation and grip/pivot in the weapon wrapper scene.
  2. Use the item resource `equipped_transform` for scale and small final hand offsets.
  3. Validate in `scenes/test_levels/armory_test.tscn` on a character using normal standing idle.
- `starting_equipment` expects item `.tres` resources, not these visual `.tscn` model wrappers.

## Current References
- `dagger_model.tscn` is the best current reference for a human-tuned fist grip.
- `iron_dagger.tres` intentionally uses a scale-only `equipped_transform`; the grip/orientation correction lives in `dagger_model.tscn` on the child `Model` node.
