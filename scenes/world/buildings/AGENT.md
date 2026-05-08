# AGENT.md

- Building scenes must be reusable shells, not test-level hacks.
- Derive stair and floor geometry from working references before editing; know the intended rise, run, landing, and floor heights.
- Stairs must physically connect floor collisions: bottom landing, stair/ramp path, and top landing must overlap walkable floor collision.
- Prefer visible individual steps plus a simple reliable hidden ramp collision when using `CharacterBody3D`.
- Do not rely on test-scene overrides to fix building geometry; reusable building scenes own correct transforms.
- Validate stairs with an actual physics traversal check, not only scene-load checks.
- Verify prop orientation against intended use: chairs face tables, beds put heads toward pillows, doors and stairs face paths.
- Account for mesh origin offsets; do not assume the node origin is the visual center or contact point.

## House and Building Authoring Notes

- Build houses as reusable `scenes/world/buildings/` scenes; test levels should only place them.
- Define floor heights before editing: ground, upper floors, roof, stair rise/run, and landing positions.
- Keep walkable collision aligned with what the global `WorldNavigation` bake should consider walkable.
- Use visible steps for readability and hidden ramp collisions for reliable `CharacterBody3D` traversal.
- Add invisible side guard collisions to stairs when needed so navmesh cannot enter ramps from the side.
- Keep side guard meshes hidden unless they are intentionally part of the art.
- Make stair bottom/top landings overlap neighboring floor collisions enough for both physics and navmesh baking.
- If a stacked-floor stair still bakes as separate nav islands, add a `NavigationLink3D` along the stair centerline and validate that the link entry is reachable from the lower floor.
- Watch for furniture, walls, and props creating accidental navmesh shortcuts or blocked doorways.
- Validate actual traversal to each intended level: outside, ground floor, upper floors, and roof when present.
