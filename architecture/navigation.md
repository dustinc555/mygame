# Navigation

Keep the offline world prebake and local runtime patches. Do not replace Godot Navigation or give each town a separate baker.

## Where the mechanics live

- `features/core/navigation/world_nav_bake_pipeline.gd` parses collision into bake input, defines tile coordinates/borders, bakes meshes and reads/writes the cache. The editor and runtime share this code.
- `features/core/navigation/world_navigation_controller.gd` loads the played world's cached tiles, queues changed tiles, owns workers, and installs their results. It covers the assembled world even when authoring happens inside a town or zone.
- `features/actors/bridge/navigation/actor_navigation_follower.gd` extends the actor's actual `NavigationAgent3D`. It owns the movement target, waypoint advancement, avoidance-result cache and stuck/repath state. It has no separate tick or configuration resource.
- `features/actors/bridge/world_actor.gd` owns physical velocity, gravity, floor snap, `move_and_slide()` and player/combat/order authority. It drives the follower and handles its completion signal. Public commands and authored actor settings remain here.

## Which settings mean what

The bake resource is `features/core/navigation/resources/world_navigation_settings.tres`; its definitions and inspector explanations live in `world_navigation_settings.gd` beside the controller. The actor's exported settings stay on `WorldActor`.

| Quantity | Setting | Physical meaning |
| --- | --- | --- |
| Bake clearance | `agent_radius`, `agent_height` | Space reserved around obstacles and beneath ceilings, in meters. Must fit the physical body. |
| Actual body | Actor `CollisionShape3D` | Physics geometry; neither the bake settings nor the avoidance settings resize it. |
| Crowd avoidance | `navigation_agent_radius`, `navigation_agent_height` | RVO dimensions, not physical collision or bake clearance. |
| Slopes | `agent_max_slope`, `max_walkable_slope_degrees` | Baked versus physical floor limits, in degrees. The bake may conservatively reject slopes physics permits. |
| Vertical bake connections | `agent_max_climb` | Recast voxel connection limit, in meters. **Not implemented step-up physics.** Exposed ledges can still block an actor; use real ramps and physical traversal tests. |
| Voxel resolution | `cell_size`, `cell_height` | Horizontal and vertical bake resolution, in meters. |
| Tile volume | `tile_size`, `tile_height` | World-space patch size, in meters. `tile_border_size()` also defines the expanded input border. |
| Arrival | `navigation_target_desired_distance`, `move_target_vertical_tolerance` | Horizontal and vertical body-to-target tolerances, in meters. |
| Path following | `navigation_path_desired_distance`, `navigation_path_height_offset` | Native waypoint advancement and vertical path offset, in meters. Never turn path Y into upward actor velocity. |
| Recovery | `stuck_check_seconds`, `stuck_min_progress`, `stuck_repath_attempt_limit` | Observation interval, required progress in meters, bounded retry count. |

Read the live resource/inspector for values rather than maintaining another tuning table here.

## What happens when geometry changes

Call `notify_geometry_changed(old_world_bounds, new_world_bounds)` with world-space AABBs. For a spawn or removal, pass the occupied bounds twice. Moves must supply both footprints; the empty space between them is not dirtied. `notify_content_changed_at(position)` is the conservative compatibility wrapper when a caller lacks a footprint.

The controller invalidates parsed collision input and queues only existing tiles whose expanded bake volumes touch either bound. `WorldNavBakePipeline.affected_tile_coords()` owns that calculation; the same border definition is used by baking.

Each `Tile` has `requested_revision`, `baking_revision` and `installed_revision`. A change increments the requested revision even while a worker is running. A finished worker installs only when its captured revision and settings generation still match; otherwise the previous live mesh stays in place and the tile is queued again. There is at most one worker per coordinate, including across settings resets.

Workers belong to `BakeTask` objects, not controller methods. Every task is joined before disposal. Scene/terrain teardown waits for active workers; queued callbacks cannot install into a detached controller. An empty successful result removes obsolete live navigation, including the whole-scene fallback used by terrain-free test levels.

Runtime static-body additions/removals use this local path automatically. Moves, resizes and collision-property edits need the explicit notification. **Automatic editor transform/UndoRedo-to-cache updates are not implemented.** Static source parsing still walks the nav root; tile-local baking does not mean tile-local parsing. Runtime patches do not automatically write back to the authored disk cache.

## Native path finish is not body arrival

Godot can finish its native path before the body reaches the actor's arrival tolerance. At that point `NavigationAgent3D.velocity` stops forwarding new desired velocity. `WorldActor._submit_navigation_avoidance_velocity()` sends movement and zero-velocity stops to `NavigationServer3D.agent_set_velocity()` directly while retaining the normal RVO callback and physical collision. Do not disable crowd avoidance or loosen arrival tolerances to conceal this lifecycle difference.

## Shared movement routing

`WorldNavigationController.get_movement_route()` owns a bounded pool in `world_navigation_routes.gd`. Nearby orders with the same start/destination tile pair share a small native map using the existing baked meshes. Longer orders share a coarse tile corridor plus its adjacent tiles. This is a derived query view, not another bake, movement solver or source of durable state. Each actor still follows its own native polygon path and collides normally; physics frequency and combat timing are unchanged.

The follower assigns this map to native path queries but explicitly keeps its avoidance-agent RID on the original world map. Otherwise actors taking different routes would stop avoiding one another. Route handles retain their native RIDs through cache eviction and handover. World-map identity/iteration changes discard cached views; a removed provider restores the native world destination, and an explicit foreign-map override wins.

`WorldInteractionController` treats held-button repeats separately from fresh clicks. An unchanged held destination keeps the existing member targets only while selection and move authority still match. A fresh click, changed destination, interrupted member or changed selection remains a real order. Destination projection uses the existing tile-local nearest-point helper. Formation selection and shared squad combat decisions are not implemented by this change.

**Limits:** tile adjacency is a coarse hint, not proof of connected floors. A native rejection retries a broader corridor, then uses the original world map; do not clone/rebuild the entire world for this fallback. Nearest-point queries outside the local search also retain their original full-map fallback. Coarse graph construction and exceptional full-map queries still depend on world size. This improves ordinary nearby orders; it is not a guarantee that all navigation costs stay constant as the world grows. The map/corridor retention limit is `CACHE_LIMIT` in `world_navigation_routes.gd`; changing it affects derived memory/reuse on the next launch, not gameplay range.

`tests/unit/test_shared_navigation_routes.gd` covers local region isolation, distant geometry, corridor detours, unreachable targets, invalidation, native RVO across separate views, map overrides, tree re-entry and RID lifetime. `test_repeated_move_orders.gd` protects held repeats and interruptions. Production movement/frame-time comparisons must still exercise one selected actor and six selected actors with changing and held destinations; record worst frames as well as averages.

## Focused verification

From the project root:

- `godot --headless --path . --script res://tests/validation/validate_navigation_arrival.gd` — real actor arrival, interrupts, retargeting, unreachable/stuck routes, disposal and authority. Add `-- --benchmark` for the movement CPU fixture.
- `godot --headless --path . --script res://tests/validation/validate_navigation_lifecycle.gd` — stale results, settings resets, old/new bounds, local isolation, empty results and teardown.
- `godot --headless --path . --script res://tests/validation/validate_granary_navigation.gd` — actual World1/Mira, each entry and exit reset independently, after local rebaking. Add `-- --cached` to test existing cached navigation instead.

The granary case runner is also used in the live game. A nonempty path, a registered shape count, or arrival through the opposite doorway alone is not a traversal pass.
