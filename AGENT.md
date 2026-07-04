# AGENT.md

This is the single project guidance file for coding agents. Human-facing architecture lives in `architecture/README.md`.

## Core Architecture
- GECS is the canonical game-state layer. Durable actor records, job metadata, scheduler state, world simulation state, save/load truth, and long-lived gameplay state belong in GECS-backed controllers/components.
- LimboAI is the realized actor behavior execution layer. Live NPC jobs run through `AiBrain -> AiJob -> AiLimboJobDriver -> BTPlayer/BehaviorTree -> BTAction wrappers`.
- Godot Navigation remains the 3D pathfinding layer through `WorldActor`, `HumanoidCharacter`, and `NavigationAgent3D`.
- `HumanoidCharacter` and `WorldActor` are actuators for movement, combat, interaction, equipment, needs, and animation. Do not move durable state ownership or broad autonomous decision ownership into actor nodes.
- AI chooses intent. GECS-backed systems/controllers validate and apply consequences.
- LimboAI blackboards are runtime scratch unless a value is explicitly mirrored to GECS. Do not treat blackboard values as save/load truth.

## Project Layout (where does a file go?)
- Game code is **feature-first**: `features/<feature>/` owns a single domain. Inside it, split by execution layer: `sim/` (durable simulation/state), `bridge/` (maps sim <-> projection), `projection/` (camera-facing scene work). A feature's data lives in `features/<feature>/resources/` (its `.tres` plus the definition `.gd`), and its scenes sit next to the scripts that drive them.
- Each feature declares its controllers in `features/<feature>/<feature>_module.gd` as `CORE/PROJECTION/SIM/BRIDGE` arrays of `{name, script, service}`. To add a controller: write it under the right layer folder, give it a `const SERVICE_ID`, and add one line to that module. Do not register it anywhere else.
- `features/core/` holds the composition root only: `game_bootstrap.gd`, `bootstrap_context.gd`, `core_services_module.gd`, and engine-level services (time, GECS world, actor query).
- Top-level roots: `scenes/` = composed levels (`worlds/`, `zones/`, `test_levels/`, `showcase/`); `assets/` = raw art + `vendor/<author>/`; `addons/` = third-party; `tools/` = validation/benchmark/editor scripts. New files use `snake_case`; node names use `PascalCase`.
- Wiring rule: `GameBootstrap` is the only composition root. Controllers receive dependencies through the injected `BootstrapContext` (`_context.get_optional(id)` / `require(id)`). The static `BootstrapContext.service(id)` is for leaf scene nodes only (authored content the bootstrap does not construct) — **never** call it from a `*_controller.gd`. This is enforced by `tools/validation/validate_controller_no_service_locator.gd`.

## Setup And Docs
- LimboAI is fetched locally, not versioned. If `addons/limboai/` is missing, run `./setup_limboai.sh` before Godot validation.
- Keep `SETUP.md` for setup instructions and `ATTRIBUTION.md` for licenses.
- Do not edit `addons/gecs/`; it is a git submodule. If GECS behavior seems necessary, stop and ask before touching the submodule.
- Leave vendor docs under `addons/gecs/docs/` alone unless explicitly asked to edit vendor content.
- Do not use the phrase "you're right" in user-facing replies. Acknowledge issues directly.
- Do not frame production work as "good enough for now", "V1", "temporary", or "prototype" unless the user explicitly asks for a throwaway experiment. This project is the product. Implement features as durable, extensible game systems with professional-quality architecture, validation, and authoring workflows.

## Dependency Graph Workflow
- After any project file change, regenerate the architecture dependency graph before finishing: `cd architecture/dependency-graph && node extract_deps.js`.
- Ensure the graph viewer is served at <http://localhost:3031>: `cd architecture/dependency-graph && node serve.js`.
- If the viewer is already running, do not start a duplicate server.
- If graph generation or serving fails, report it as a blocker.
- **FORBIDDEN: changing the graph type / layout.** The Dependencies view is a force-directed graph by design — the honest physics layout. Do NOT convert it to columns, buckets, lanes, rows, grids, trees, or any category-positioned arrangement (`layout:'none'` with computed x/y), and do not otherwise change the layout/graph type. That hides coupling instead of fixing it. The hairball is removed only by changing the actual code to have fewer cross-cutting edges, then regenerating. Node color/size/labels/highlights and `extract_deps.js` analysis are fine to change; the layout is not. If you believe a different view is warranted, ask the user first.

## State And Persistence
- Controllers/components own mutable runtime truth. Nodes and resources author data, bridge scene content, execute local behavior, and display state.
- Use stable IDs for anything that may persist, serialize, replicate, or be referenced by other systems.
- Serializable state should be dictionaries, arrays, strings, numbers, booleans, and basic Godot value types.
- Do not serialize live `Node`, `Resource`, signal, callable, or scene-instance references as durable state.
- `WorldTimeController` is the time authority for simulation changes.
- `GameBootstrap` owns shared controller/system wiring. Test/demo scenes must not own core gameplay systems.

## AI And Population
- Persistent NPCs must have `PopulationController` actor records before relying on long-lived behavior.
- `PopulationRealizationController` decides which actor records become live scene actors.
- `LedgerSimulationController` advances far/unloaded actors abstractly through controller records.
- `AiSchedulerController` controls decision cadence. Do not make every actor think every frame.
- `ActorQueryController` owns broad live actor lookup. Do not add per-frame all-humanoid scans.
- `AiBrain.request_job()` is the compatibility facade for gameplay systems. `AiTaskStep` is migration scaffolding; new realized behavior should move toward LimboAI tasks/trees that call existing actuator methods.
- Far actors use cheap GECS ledger simulation, not behavior trees, nav agents, or live scene actors.

## Scenes And Authoring
- Scenes compose reusable systems; they do not own one-off gameplay features.
- Reusable editor content must work when dragged into another bootstrapped scene.
- Prefer `class_name` nodes, exported fields, named child roots, safe defaults, stable IDs, and clear editor workflows.
- Visual shells stay separate from gameplay function. A building model is neutral; a facility function makes it a bar, field, shop, jail, mine, or storage site.
- Test levels are proofs, not implementations. If a feature only works in one test scene, refactor it into a reusable system.
- Treat `project.godot` `run/main_scene` as user-owned development state. Do not revert or normalize it unless explicitly asked.

## Navigation And Buildings
- Prefer real walkable 3D geometry over `NavigationLink3D` for stairs, ramps, bridges, roofs, and normal building traversal.
- Use hidden ramp collision plus visible step meshes for reliable `CharacterBody3D` stairs. Instance the reusable `features/world/projection/buildings/interior_stairs.tscn` instead of re-authoring stair collision per building.
- Multi-level buildings need real floor/roof openings above stair runs; a sealed slab over stairs presents as a stair traversal failure. Level visibility stays simple: show the active level, hide the camera-facing wall side, keep the roof visible only when the roof is the active level.
- Hidden building walls stay physically solid; only click picking ignores hidden/non-active geometry (`WorldBuilding.should_project_click_shape()` decides whether a click on hidden geometry projects to the active level).
- When triaging movement bugs, verify the plain ramp/stairs proof in `scenes/test_levels/movement_controls_test.tscn` before blaming a building asset.
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
- Skills and attributes belong to `WorldActor`, use stable dotted IDs from `SkillRules`, and share the centralized XP curve.

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
