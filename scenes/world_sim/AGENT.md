# AGENT.md

Scenes in `scenes/world_sim/` are reusable human-operator building blocks.

- These scenes must be addable or instantiable from the Godot editor.
- Prefer clear root nodes, named child roots, exported fields, safe defaults, and stable IDs.
- A human operator should be able to instance the scene into any bootstrapped level and configure it without reading script code.
- Do not bake test-level assumptions into reusable world-sim scenes.
- If a scene self-builds child nodes, the generated tree must remain readable, editable, and stable.
- When the editor workflow changes, update `operator/` instructions in the same task.

## Reusable Building Authoring

- One reusable source scene owns layout. Town instances are data/config only.
- Edit furniture, guard posts, service points, and workstations in the source scene.
- Do not hard-code transforms over authored source-scene transforms. Script transforms are fallbacks only.
- Use bar-style layout metadata for editable generated layout nodes: generated flag, role, index, layout version, last default transform, custom flag.
- Add points only when a system needs them: guards, shop counters, workstations, waiters, barber chairs. Do not add generic visitor/audience points.
- Use only meaningful roots. Avoid empty `Storage`, `ServicePoints`, `JobProviders`, or `ActivityPoints` unless that building actually uses them.
- Role point counts use `max(role_count, point_count)` so defaults work and designers can add extra possible positions.
- Props are wrapper scenes. Do not place raw GLBs in town instances.
- Generated staff are data-driven and should not be manually duplicated in each town scene.
- Generated NPCs must look and read like real settlement members: derive names from population name profiles, appearance/clothing from population appearance profiles, faction/squad from the owning settlement, and append role/title suffixes for readability.
- Town scenes should leave `actor_realization_policy` at `full_town` unless the town has been verified with unloaded actor ledger behavior. Large city policies must still keep important roles and nearby actors available as expected.
- Every building type needs a focused validation for source layout, count behavior, and town instance configuration.
