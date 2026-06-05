# AGENT.md

This is the single project guidance file for coding agents. Human-facing architecture lives in `architecture/README.md`.

## Core Architecture
- GECS is the canonical game-state layer. Durable actor records, job metadata, scheduler state, world simulation state, save/load truth, and long-lived gameplay state belong in GECS-backed controllers/components.
- GECS fixed-tick systems own gameplay execution. Do not add actor-node-owned executors, schedulers, or autonomous decision loops.
- Rendering and scene nodes are projection only. They may display GECS state, author static content, or expose local interaction anchors, but they do not own durable simulation truth.
- Godot Navigation remains the 3D pathfinding layer for projected movement, but movement outcomes must be driven from GECS commands/objectives.
- AI chooses intent through GECS objective systems. GECS-backed systems/controllers validate and apply consequences.

## Setup And Docs
- LimboAI is included as a local decision-tree/GDExtension tool when needed. If `addons/limboai/` is missing, run `./setup_limboai.sh`; do not commit the downloaded binaries.
- Keep `SETUP.md` for setup instructions and `ATTRIBUTION.md` for licenses.
- Do not edit `addons/gecs/`; it is a git submodule. If GECS behavior seems necessary, stop and ask before touching the submodule.
- Leave vendor docs under `addons/gecs/docs/` alone unless explicitly asked to edit vendor content.
- Do not use the phrase "you're right" in user-facing replies. Acknowledge issues directly.
- Do not frame production work as "good enough for now", "V1", "temporary", or "prototype" unless the user explicitly asks for a throwaway experiment. This project is the product. Implement features as durable, extensible game systems with professional-quality architecture, validation, and authoring workflows.

## State And Persistence
- Controllers/components own mutable runtime truth. Nodes and resources author data, bridge scene content, execute local behavior, and display state.
- Use stable IDs for anything that may persist, serialize, replicate, or be referenced by other systems.
- Serializable state should be dictionaries, arrays, strings, numbers, booleans, and basic Godot value types.
- Do not serialize live `Node`, `Resource`, signal, callable, or scene-instance references as durable state.
- `WorldTimeController` is the time authority for simulation changes.
- `GameBootstrap` owns shared controller/system wiring. Test/demo scenes must not own core gameplay systems.

## AI And Population
- Persistent NPCs must have `PopulationController` actor records before relying on long-lived behavior.
- `PopulationRealizationController` decides which actor records become projected scene actors.
- `LedgerSimulationController` advances far/unloaded actors abstractly through GECS records.
- `ActorQueryController` owns broad live actor lookup. Do not add per-frame node scans.
- Far actors use cheap GECS ledger simulation, not behavior trees, nav agents, or live actor nodes.

## Scenes And Authoring
- Scenes compose reusable systems; they do not own one-off gameplay features.
- Reusable editor content must work when dragged into another bootstrapped scene.
- Prefer `class_name` nodes, exported fields, named child roots, safe defaults, stable IDs, and clear editor workflows.
- Visual shells stay separate from gameplay function. A building model is neutral; a facility function makes it a bar, field, shop, jail, mine, or storage site.
- Test levels are proofs, not implementations. If a feature only works in one test scene, refactor it into a reusable system.
- Treat `project.godot` `run/main_scene` as user-owned development state. Do not revert or normalize it unless explicitly asked.

## Navigation And Buildings
- Prefer real walkable 3D geometry over `NavigationLink3D` for stairs, ramps, bridges, roofs, and normal building traversal.
- Use hidden ramp collision plus visible step meshes for reliable `CharacterBody3D` stairs.
- Keep move targets on or very near the navmesh. Do not add Y offsets to movement targets unless a local interaction truly needs a non-floor target.
- Do not turn navigation path point Y into upward actor velocity. Let `move_and_slide()`, floor snapping, and walkable collision handle vertical movement.
- Be suspicious of path simplification in interiors, stairs, roofs, railings, and tight corners.
- Validate navigation fixes with live `CharacterBody3D` movement through the actual scene, not only static path queries.

## Characters, Items, And Skills
- Characters use race definitions and body archetype definitions. Do not hardcode sex/body/race in scene-specific logic.
- `ItemDefinition` is gameplay-facing item data. Worn clothing visuals belong in `EquipmentVisualDefinition` entries, usually under `ItemDefinition.equipped_visuals`.
- Clothing should bind to the live character skeleton. Do not hide body meshes for clipping unless explicit operator-authored body-region data exists.
- Hand-held equipment attaches by aligning item `GripPoint_Primary` to generated body sockets such as `RightHandGrip` and `LeftHandGrip`.
- Do not hardcode per-item weapon placement in scripts. Fix wrapper scenes, item resources, or shared grip socket profiles.
- Skills and attributes belong to GECS actor records/components, use stable dotted IDs from `SkillRules`, and share the centralized XP curve.

## Imports And Licensing
- Imported third-party assets live under `assets/vendor/<author>/<pack>/` unless explicitly approved otherwise.
- Every imported asset pack must be listed in `ATTRIBUTION.md` with author, license, source URL, and project path.
- Prefer permissive/commercial-safe licenses such as `CC0`, public domain, `MIT`, `BSD`, or `Apache-2.0`.
- Stop and flag unclear, personal-use, no-derivatives, copyleft/share-alike, royalty, source-disclosure, or ownership-risk licenses.
- Use real-world scale: `1 Godot unit = 1 meter`, `1 Blender unit = 1 meter`.

## Validation
- Do not run broad validation sweeps. Run only the smallest command that directly exercises the user-requested scene, file, or subsystem; ask before expanding scope.
- Whole project: `godot --headless --editor --path . --quit`.
- Runtime boot: `timeout 5s godot --headless --path .`.
- Changed GDScript file: `godot --headless --path . --check-only --script res://path/to/file.gd`.
- If the project uses C#: `godot --headless --path . --build-solutions --quit`.
- Performance-sensitive changes must run a relevant framerate/frame-CPU validation and compare against the previous baseline; do not accept unbounded frame-time regressions.
- A successful runtime boot is not acceptable validation for performance-sensitive changes.
- For `res://scenes/test_levels/combat_skirmish_20v20_armory.tscn`, agent validation must prove FPS never drops below 40 during the measured run.
- Average FPS is not an acceptable pass criterion; any frame-rate drop below 40 FPS is a failure.
- If FPS drops below 40, rearchitect the change or find a cheaper solution before calling validation complete.
- New or updated performance validation scenes/scripts should include a short comment with the prior measured FPS or frame-CPU baseline and the scenario size.
- Godot debugger, parse, runtime, and validation `push_error` output are failures to fix, not warnings to ignore.
- Do not say validation passed unless the command was actually run and succeeded.
