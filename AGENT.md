# AGENT.md

## Required Validation
- Whole project: run `godot --headless --editor --path . --quit`
  - This must exit with code `0`.
  - Treat any parse error, load error, missing resource error, or broken reference in output as a validation failure.

- Changed GDScript file: run `godot --headless --path . --check-only --script res://path/to/file.gd`
  - Replace `res://path/to/file.gd` with the modified script.
  - This must exit with code `0`.
  - Any parse error means validation failed.

- If the project uses C#: run `godot --headless --path . --build-solutions --quit`
  - This must exit with code `0`.
  - Any compiler/build error means validation failed.

- Do not say validation passed unless the command was actually run and succeeded.
