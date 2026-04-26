# AGENT.md

## Test Levels
- Test/demo levels live in `scenes/test_levels/`.
- Follow `scenes/test_levels/AGENT.md` when working in those scenes.

## Required Validation
- Whole project: run `godot --headless --editor --path . --quit`
  - This must exit with code `0`.
  - Treat any parse error, load error, missing resource error, or broken reference in output as a validation failure.

- Runtime boot: run `timeout 5s godot --headless --path .`
  - This must exit without parse errors, stack traces, or runtime type errors in output.
  - Use this to catch scene instantiation and `_ready()` failures that `--check-only` misses.

- Changed GDScript file: run `godot --headless --path . --check-only --script res://path/to/file.gd`
  - Replace `res://path/to/file.gd` with the modified script.
  - This must exit with code `0`.
  - Any parse error means validation failed.

## Implementation Notes
- When instantiating a scene that depends on its initial transform in `_ready()`, set its position before `add_child()` or provide an explicit setup method and call it immediately after adding it.
- Keep typed `@onready` variables aligned with the exact node type in the scene tree; mismatches can pass parse checks and fail only at runtime.

- If the project uses C#: run `godot --headless --path . --build-solutions --quit`
  - This must exit with code `0`.
  - Any compiler/build error means validation failed.

- Do not say validation passed unless the command was actually run and succeeded.
