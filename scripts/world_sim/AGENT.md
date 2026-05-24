# AGENT.md

World-sim scripts define reusable editor-authored systems.

- Design towns, factions, facilities, jobs, activity points, territory, and future player bases to scale beyond one demo scene.
- Scene nodes and resources author data; controllers own mutable runtime truth.
- Prefer stable IDs, serializable dictionaries, reusable resources, explicit child-root paths, and clear `class_name` nodes.
- Avoid one-off scene logic.
- Any new reusable node should be understandable in the Godot editor through exported fields, named roots, and operator docs.
- For reusable building/facility authoring, follow `scenes/world_sim/AGENT.md` so source scenes own layout and town instances stay data/config only.
- Generated settlement/facility NPCs must use the settlement/faction population contracts: stable IDs, squad/faction ownership, population name profile, population appearance/clothing profile, and role/title suffixes. Do not ship generic placeholder staff such as `Mayor`, `Guard`, or unprofiled capsule bodies.
- If a script changes how a human adds or configures content, update `operator/` instructions in the same task.
