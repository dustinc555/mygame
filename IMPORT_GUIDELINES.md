# Import Guidelines

## World Units
- `1 Godot unit = 1 meter`
- `1 Blender unit = 1 meter`
- Treat all planning squares as `1m x 1m`

## Canonical Reference Sizes
- Humanoid: about `2.0m` tall, about `0.9m` wide collision footprint
  - Current reference comes from `CapsuleShape3D radius = 0.45` and `height = 1.1` in `scenes/test_levels/mining_test.tscn`
- Barrel: about `1.1m` diameter, `1.15m` tall
  - Reference: `scenes/world/containers/barrel_container.tscn`
- Small resource node: about `4.2m x 4.2m x 1.8m`
  - Reference: `scenes/world/copper_node.tscn`

## Import Rule
- Import assets at real-world size first.
- If a source model represents a `10 ft` object and the in-game humanoid represents a `5 ft` character, the object should import at `2x` the character height.
- Do not eyeball scale against the scene if you know the real size of the source asset.

## Blender Setup
- Use metric units.
- Model with `1 Blender unit = 1 meter`.
- Use the grid as meter spacing so dimensions read directly.

## Godot Workflow
1. Identify the asset's intended real-world dimensions.
2. Convert feet/inches to meters before judging final size.
3. Import the raw model.
4. Compare it against the humanoid reference first, then against a prop reference like barrel or door.
5. If wrapper scaling is needed, record it in the wrapper scene and keep collision aligned to the intended real footprint.

## Quick Conversions
- `1 ft = 0.3048m`
- `5 ft = 1.524m`
- `6 ft = 1.8288m`
- `10 ft = 3.048m`

## Expected Asset Classes
- Human-sized prop: `1m` to `2m` tall
- Barrel/crate: about `1m` footprint
- Cart/car: about `2m x 5m`
- Small structure/stall: several meters wide, sized from real dimensions
- Tent/building: scale from real dimensions, not from what "looks right"

## Wrapper Scene Rule
- Keep raw imported visuals in `assets/models/.../*_model.tscn`
- Keep placeable world assets in `scenes/world/...`
- Collision should match the intended real occupied footprint, not an arbitrary visual guess
