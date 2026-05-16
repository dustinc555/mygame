# AGENT.md

World-sim resources are reusable definitions for editor-authored content.

- Resources should describe portable gameplay meaning, not scene-specific state.
- Use stable IDs for definitions that controllers, saves, events, or future DB records may reference.
- Keep resources reusable across NPC towns, player settlements, and test scenes.
- If adding or changing a resource type changes editor workflow, update architecture docs and `operator/` instructions.
