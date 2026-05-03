# Agent Models Notes

## Movement and ramps

- `CollisionShape3D` does nothing unless it lives under a physics body like `StaticBody3D` or `CharacterBody3D`.
- If a ramp or stair test seems to have "no collision", check the scene tree first and confirm the shape is under a real physics body.
- `HumanoidCharacter` movement was flattening target reach checks too aggressively; ramp traversal became more reliable after adding floor snap and a vertical tolerance instead of pure XZ arrival.

## Reliable stairs pattern

- The most reliable current pattern is:
  - visible modular stair geometry for readability
  - one hidden simple collision ramp underneath for traversal
- `scenes/world/buildings/interior_stairs.tscn` is the reusable stairs asset that currently works for movement tests.
- Prefer instancing `interior_stairs.tscn` into buildings instead of re-authoring ad hoc stair collision every time.

## Building visibility / click handling

- Invisible building walls should remain physically solid.
- Only click picking should ignore hidden/non-active level geometry.
- `WorldBuilding.should_project_click_shape()` is the key helper for deciding whether a click on hidden building geometry should project to the active level instead of using the raw hit.

## Multi-level buildings

- `two_story_house.tscn` should use real floor/roof openings above stairs; sealed slabs over stair runs cause false stair failures.
- Keep level visibility simple: show the active level, hide the wall side facing the camera, keep roof visible only when the active level is the roof.
- For movement issues, verify the simple ramp/stairs proof in `movement_controls_test.tscn` before blaming the building asset.
