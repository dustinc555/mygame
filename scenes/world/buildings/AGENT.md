# AGENT.md

- Building scenes must be reusable shells, not test-level hacks.
- Derive stair and floor geometry from working references before editing; know the intended rise, run, landing, and floor heights.
- Stairs must physically connect floor collisions: bottom landing, stair/ramp path, and top landing must overlap walkable floor collision.
- Prefer visible individual steps plus a simple reliable hidden ramp collision when using `CharacterBody3D`.
- Do not rely on test-scene overrides to fix building geometry; reusable building scenes own correct transforms.
- Validate stairs with an actual physics traversal check, not only scene-load checks.
- Verify prop orientation against intended use: chairs face tables, beds put heads toward pillows, doors and stairs face paths.
- Account for mesh origin offsets; do not assume the node origin is the visual center or contact point.
