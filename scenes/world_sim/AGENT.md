# AGENT.md

Scenes in `scenes/world_sim/` are reusable human-operator building blocks.

- These scenes must be addable or instantiable from the Godot editor.
- Prefer clear root nodes, named child roots, exported fields, safe defaults, and stable IDs.
- A human operator should be able to instance the scene into any bootstrapped level and configure it without reading script code.
- Do not bake test-level assumptions into reusable world-sim scenes.
- If a scene self-builds child nodes, the generated tree must remain readable, editable, and stable.
- When the editor workflow changes, update `operator/` instructions in the same task.
