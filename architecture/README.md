# Architecture

This folder documents the project architecture that should stay true as systems grow.

Core rule: editor nodes and resources author game data, while reusable controllers own mutable runtime truth through stable IDs and serializable dictionaries.

Read these docs before changing shared gameplay systems, world simulation, settlement systems, inventory, factions, jobs, persistence, or controller/bootstrap wiring.

Update these docs in the same task when changing system ownership, scene contracts, runtime state shape, editor workflow, or online/server compatibility assumptions.

Human-operator workflows live in `operator/`. Update those instructions whenever reusable editor-authored content changes how it is added or configured in the Godot editor.

## Docs

- `game-data.md`: how nodes and resources define factions, towns, items, facilities, and other game data.
- `world-state.md`: how controllers own runtime state, events, serialization, and time-driven simulation.
- `settlements-and-territory.md`: how `SettlementTown`, facilities, jobs, activity points, faction territory, and town borders fit together.
- `online-friendly-design.md`: rules that keep a future DB/server-authoritative design possible without requiring online play now.
- `editor-authoring.md`: practical workflow for a human operator building towns and world data in the editor.
- `../operator/`: concise step-by-step editor instructions for reusable content workflows.

## Design Priorities

- Make editor authoring easy and visible for humans.
- Keep test scenes as composition only.
- Keep reusable logic in controllers, components, resources, and bootstrap systems.
- Use stable IDs for anything that may persist, serialize, replicate, or be referenced by other systems.
- Avoid storing long-lived truth only in node paths, scene-local references, or one-off demo scripts.
