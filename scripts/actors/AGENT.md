# AGENT.md

## Actor Navigation Rules
- Actor movement code must follow the baked path rather than guessing shortcuts through 3D space.
- Keep move targets on or very near the navmesh. Do not add Y offsets to movement targets unless a local interaction explicitly requires a non-floor target.
- Spawn clearance is different from target height. If a character needs to spawn above the ground to avoid penetration, add that Y offset only to the spawn position.
- Formation offsets should be horizontal by default. A formation offset with Y can make every squad waypoint unreachable.
- Prefer small, explainable movement changes over recovery systems that hide bad geometry or bad targets.
- Do not add elevator-like logic for stairs. If a ramp or stair requires special vertical teleport/link behavior, inspect the building collision and navmesh first.
- Avoid broad stuck recovery that changes destination semantics. A stuck actor should either repath to the same real target, finish if close enough, or report unreachable.

## NavigationAgent3D Practices
- Disable path simplification for tight interior, stair, roof, or multi-level traversal unless live testing proves simplification is safe.
- Preserve useful Y motion from `NavigationAgent3D.get_next_path_position()` so actors can climb ramps naturally.
- Keep arrival and unreachable tolerances separate. Arrival can be tight for interaction points; unreachable tolerance should account for nearest valid navmesh points.
- If navigation data may still be baking, use a short grace period before declaring unreachable.
- If an actor reaches the agent final position but not the requested target, check whether the requested target is off-mesh before changing movement code.

## Debugging Actor Movement
- Print `global_position`, `_has_move_target`, `_move_target`, order type, `velocity`, and life state.
- Print the agent next and final path positions. If final is far from `_move_target`, the target is probably off the navmesh.
- Check whether `_clear_actor_move_target()` or unreachable handling fired before assuming navigation failed.
- Check whether combat, sleep, carry, downed, or animation reaction state is suppressing movement.
- For group movement, inspect each member separately. One actor may be moving correctly while another has an invalid formation target or avoidance conflict.

## Controller Interactions
- Controllers that issue long route movement should be able to reissue the current target if an actor dropped a valid move order.
- Controllers must have terminal states. If all actors in a squad are unconscious, dead, or gone, resolve the squad as defeated/cancelled instead of waiting forever for an alive actor to arrive.
- Combat/alarm logic can be a valid route outcome. If defenders engage and wipe a squad before it reaches the exact final marker, the controller should still resolve that outcome.
