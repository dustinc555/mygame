# AGENT.md

## 3D Navigation Practices
- Prefer real walkable 3D geometry over `NavigationLink3D` for stairs, ramps, bridges, doors, roofs, and ordinary building traversal.
- Use `NavigationLink3D` only for traversal that is intentionally discontinuous, such as ladders, jumps, vaults, or teleports. Do not use links to patch normal stair geometry.
- Navigation failures are often caused by geometry that looks connected but is not connected to the navmesh. Check floor, ramp, landing, and roof collision overlap before changing actor logic.
- Hidden ramp collision plus visible step meshes is the preferred stair setup for `CharacterBody3D` actors.
- Ensure ramp tops overlap upper-floor collision and ramp bottoms overlap lower-floor collision. Tiny gaps or lips can create separate nav islands.
- Keep side guards and walls from pinching the agent corridor. If the navmesh can enter a stair from the side, add hidden side guard collision.
- Do not place move targets above the navmesh. Spawn clearance and move target height are separate concerns.
- Formation offsets should normally be horizontal only. If an actor needs spawn clearance, add Y only to the spawn position, not to route or move targets.
- Be suspicious of path simplification when actors cut through stair walls, parapets, railings, or corners. Prefer `NavigationAgent3D.simplify_path = false` for precise building traversal unless there is a measured reason to enable it.
- Preserve the Y component from the navigation path when following ramps. Do not invent vertical boosts unless there is a specific physics reason and a live traversal test proves it is needed.

## Debugging Checklist
- Validate with a live `CharacterBody3D` walking through the actual scene. Static `NavigationServer3D.map_get_path()` success is not enough.
- Log actor `global_position`, `_has_move_target`, `_move_target`, current order, velocity, and life state when movement appears stuck or abandoned.
- Log `NavigationAgent3D.get_next_path_position()` and `NavigationAgent3D.get_final_position()` to confirm whether the agent is chasing a reachable point or an off-mesh target.
- Compare target Y to the nearest baked navmesh surface. A target slightly above the floor can make an otherwise correct path look unreachable.
- Check whether the actor dropped its move target because the final position was outside tolerance, because no navigation data was available yet, or because stuck handling failed it.
- Test both single actors and small groups. Group avoidance can reveal corridor width, formation offset, and side-wall issues that single-actor tests miss.
- Test with avoidance enabled first. Disable avoidance only to isolate whether crowd steering is masking a geometry or target-height issue.
- When a route spans roads, settlements, and interiors, verify each route waypoint is on or very near the navmesh and reissue long-lived squad targets if actors can legitimately drop movement orders.

## Common Failure Patterns
- Actor spawns above the floor correctly, but the move target is also above the floor incorrectly.
- Stairs visually touch floors, but collision surfaces do not overlap enough for navmesh baking.
- Path simplification removes stair/ramp waypoints and sends actors into walls or railings.
- The navmesh reaches a final point near the target, but game code demands an exact target that is off-mesh or vertically mismatched.
- Actors reach combat or alarm range, then die, while controller code waits forever for an alive actor to reach a later point.
- A debug path line looks valid, but the `CharacterBody3D` cannot physically slide through the corridor because collision clearance is too tight.

## Validation Expectations
- For stair/building fixes, run or create a traversal check that proves an actor can move from outside to each intended level and back if return travel matters.
- For squad/route fixes, verify that at least one actor travels through the route in the live scene and that the controller reaches a terminal state such as success, defeat, or cancellation.
- Document any remaining leak warnings separately from navigation success. Do not treat known shutdown leaks as proof that movement failed.
