# AGENT.md

## Test Levels
- Test/demo levels live in `scenes/test_levels/`.
- Follow `scenes/test_levels/AGENT.md` when working in those scenes.

## Architecture Rules
- Before editing, search for all applicable `AGENT.md` files in the project and follow the most specific guidance for the files being touched.
- Before shared system, gameplay architecture, persistence, world simulation, settlement, faction, inventory, job, or bootstrap work, read `architecture/README.md` and the relevant docs in `architecture/`.
- When changing system ownership, scene contracts, runtime state shape, editor workflow, or online/server compatibility assumptions, update the relevant `architecture/` docs in the same task.
- When changing world-sim data relationships, settlement/faction/territory/job/inventory ownership, or controller serialization, update the node data graph in `architecture/game-data.md`.
- Reusable editor-authored content must be designed for a human operator using the Godot editor, not just for code-driven setup.
- Prefer drag-in scenes, `class_name` nodes, exported fields, named child roots, safe defaults, stable IDs, and clear editor workflows.
- If reusable content only works in one test/demo scene, refactor it into a reusable contract before continuing.
- When changing how a human operator adds, configures, or composes reusable content, update concise instructions in `operator/` in the same task.
- Scenes are composition only. Test/demo scenes place content and shared anchor nodes; they do not own gameplay features.
- Bootstrap owns systems. Shared gameplay, UI, and controller wiring must live in `GameBootstrap` or another reusable bootstrap layer.
- No scene-specific feature logic. If a feature only works in one demo scene, stop and refactor it into a reusable system before continuing.
- Shared scene contract first. When adding a new system, define the nodes/components the bootstrap expects instead of hardcoding feature behavior into a level.
- Test levels are proofs, not implementations. Levels may customize content and instructions, but not core interaction, inventory, combat, trade, HUD, AI, or simulation logic.
- Before writing code, ask: `If I drag this asset into another bootstrapped scene, will it still work?` If not, refactor first.

## Human Operator Design
- A human operator should be able to add reusable gameplay content from the editor without reading implementation code.
- Visual shells should stay separate from gameplay function; for example, a building model is neutral and a facility function makes it a bar, field, shop, police station, mine, or other facility.
- Generated or self-built node trees must remain readable, editable, and stable in the editor.
- Before considering reusable editor content complete, confirm the operator can add it with `Add Child Node` or `Instantiate Child Scene...`, set obvious exported fields, replace visual models safely, and reuse it in another bootstrapped scene.

## Character And Equipment Modeling
- Characters use race definitions and body archetype definitions. Do not treat sex/body/race as hardcoded scene-specific state.
- `ItemDefinition` is gameplay-facing item data. Worn clothing model selection belongs in `EquipmentVisualDefinition` entries, usually stored in `ItemDefinition.equipped_visuals`.
- Clothing should bind to the live character skeleton when possible. Do not create scene-specific clothing animation hacks.
- Body hiding is off by default. Do not hide or delete body meshes to fix clipping unless an explicit, operator-authored body-region system is in place for that asset.
- Avoid a full race-by-sex-by-item matrix when adding races. Reuse compatible body fit families where possible and add exact archetype visuals only where the shared fit fails.

## Imported Assets
- Imported third-party assets must live under `assets/vendor/<author>/<pack>/` unless explicitly approved otherwise.
- Every imported asset pack must be listed in `ATTRIBUTION.md` with author, license, source URL, and project path.
- Do not add, keep, or reference imported assets that are missing approved source and license information.
- Always validate current and newly introduced license terms from the live/source license text before importing or retaining third-party assets.
- Prefer simple permissive/free-use licenses such as `CC0`, public domain, `MIT`, `BSD`, `Apache-2.0`, or equivalent commercial-use-safe terms.
- Red alert: stop and flag any license or source terms that could require payment, royalties, revenue share, source disclosure, project relicensing, ownership transfer, loss of project ownership, restrictions on commercial use, restrictions on modification or redistribution, copyleft/share-alike obligations, or any obligation that could compromise the project.
- Red alert: stop and flag unclear custom licenses, marketplace-only terms, personal-use-only terms, educational-use-only terms, no-derivatives terms, AI-generated/copyright-ambiguous assets, and licenses such as `GPL`, `AGPL`, `LGPL`, or `CC BY-SA` unless explicitly approved before import.
- Project-authored meshes built from Godot primitives or custom code do not need attribution entries.

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
- Import and scale new models using `IMPORT_GUIDELINES.md`.
- When instantiating a scene that depends on its initial transform in `_ready()`, set its position before `add_child()` or provide an explicit setup method and call it immediately after adding it.
- Keep typed `@onready` variables aligned with the exact node type in the scene tree; mismatches can pass parse checks and fail only at runtime.

- If the project uses C#: run `godot --headless --path . --build-solutions --quit`
  - This must exit with code `0`.
  - Any compiler/build error means validation failed.

- Do not say validation passed unless the command was actually run and succeeded.
