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

## Stationary actors

`WorldActor._process_navigation_motion()` skips repeated floor snapping, zero-velocity avoidance submissions, stuck-state resets and upright-rotation writes only when an upright, motionless actor has no navigation target or combat movement and still passes `_can_keep_stationary_floor()`. Entering this state submits the stop once. A new command, combat movement, residual velocity or invalid support uses the ordinary movement path immediately; the actor and its other capabilities remain active.

Support is checked every physics tick against live collision: a short ray must find the solved static surface, its velocity and normal must still be valid, and the capsule must not overlap a new obstruction. Slopes, platforms, removed/lowered floors and unsupported shapes retain native movement handling when those conditions fail. Do not replace these checks with cached contacts or an idle timer: terrain and other untracked collision changes do not yet supply complete actor wake notifications.

`tests/unit/test_stationary_actor_floor.gd` covers resting work, command/combat wake-up and changed physical support. This is a shared actor path, not a camp-specific lower-fidelity body or a replacement for normal movement validation.

## Background route requests and player orders

`WorldNavigationController.request_paths()` submits native path searches through `navigation_query_jobs.gd`. Workers own value snapshots and retain the `World3D`, not actor nodes or GECS components. The main thread polls completed batches without waiting, then publishes complete results only for the current command ticket. Actor removal, explicit stop and replacement commands cancel old tickets; map identity/iteration checks reject obsolete geometry.

Player routes have reserved worker admission **and** use Godot's high-priority worker tasks. Reserving an application slot alone does not bypass Godot's low-priority backlog. Background requests still have an execution lane. Batches are bounded by destination count, not request count: a tactical request with many candidates yields between chunks and publishes its complete ordered candidate array afterward. A destination may require a second native search for whole-map fallback.

Actual body routes are marked `movement_route` by the shared follower, including autonomous pursuit and ordinary NPC travel. The queue separates them from tactical position searches so a backlog of possible fighting positions cannot occupy every background worker and leave bodies waiting at old route endpoints. Movement can borrow spare background capacity, but leaves a lane for queued position searches; a single background worker alternates between the two. Neither class consumes the player's reserved capacity. This changes request scheduling, not worker count, movement speed, collision or permission to attack.

In the Godot FileSystem, open `features/core/navigation/resources/world_navigation_settings.tres`, then expand **Runtime Path Queries** in the Inspector. `path_query_workers` limits concurrent batches, `path_query_player_workers` reserves player admission, `path_query_batch_size` limits destinations per batch, and `path_query_capacity` bounds outstanding request keys. These are advanced throughput controls, not movement-speed or combat-timing controls. Runtime edits are read on the next request; already running batches finish normally. Saved defaults apply on the next launch.

`WorldInteractionController` distinguishes a fresh click from continuation of the same held gesture and selection. Unchanged held targets are reused only while movement authority still matches. A useful in-flight held route is allowed to finish instead of being discarded every repeat; its result is consumed before submitting the next correction. A fresh click, reversal, interruption or changed selection supersedes it. The actor's latest goal remains authoritative even while following an intermediate held route.

The follower retains a valid current route during replacement. It never continues past that route's endpoint toward an unqueried goal, joins across an unproven corner, or backtracks to an abandoned worker start. If a late replacement cannot be joined safely, it brakes and requests from its current position. Stop, blocked routes, navigation-layer changes and provider removal retain their ordinary cancellation and fallback behavior.

`test_navigation_query_jobs.gd` covers off-thread execution, player admission and actual global-pool priority, movement/position fairness, small worker configurations, bounded chunks, result ordering and cancellation. `test_async_navigation_follower.gd` covers real pursuit request classification, held publication races and route handoff safety; `test_repeated_move_orders.gd` covers selection and command ownership. `validate_player_navigation.gd` exercises actual solo/six-member clicks, held turns before release, stop and arrival, including sustained delayed background work. Its imposed worker delays isolate the failure mechanism; they are not measurements of a populated town battle.

## Combat fighting positions

`GameCombatSlotSystem` proposes fighting positions around the target. New ring points provide horizontal locations, not reliable floor heights: `CombatNavigation.ground_position_hint()` resolves their local physical support using the attacker's body-origin offset and existing `move_target_vertical_tolerance`. The current stance and retained reservation remain exact positions and are not moved by this step.

Grounding runs once when a route batch is submitted, not every time its pending result is checked. It does not approve a destination: returned routes still require current floor contact, standing clearance, connectivity and an unobstructed strike where applicable. A changed or removed floor can therefore reject a completed worker result. Synchronous fallback uses the same grounding and acceptance rules. Defend behavior, target selection and attack timing are unchanged.

`test_combat_navigation.gd` covers sloped front positions, body offsets, distant/disconnected floors and live support changes. The `sloped_defend` case in `validate_combat_navigation_runtime.gd` verifies that an ordinary hostile NPC autonomously approaches and attacks a defending party member through the production navigation and combat systems.

## Pursuit and its leash

Pursuit and approval to strike are separate. `GameCombatMovementSystem` can approach a live opponent through the ordinary navigation follower while `GameCombatSlotSystem` searches for a fighting position. It stops outside the opponent's body; this does not grant an attack slot or bypass physical strike checks. An already clear, reachable current stance can be approved without first waiting for a ring-position batch.

`WorldActor` continues the same combat navigation order while the opponent moves. A useful route or completed result is not discarded merely because that opponent has taken another step. Switching opponents still replaces the order, and map, clearance, connectivity and current-position checks still reject unusable results.

Recovery measures the body's progress, not destination updates or completed route calculations. Continuing pursuit and held steering preserve the stuck timer, retry count and precise-corner recovery; a changed goal or route rebases the distance comparison from the last physical progress point. A fresh command resets recovery. This applies to both threaded routes and native fallback, so an approaching opponent cannot make a stationary pursuer appear to advance. The actor's existing **Recovery** settings still control the interval and retry limit.

Replacing a blocked retained route consumes that same retry budget, even while the newest correction is pending. A fresh command always gets its first replacement attempt, including when retries are disabled; repeatedly following blocked replacements cannot keep an unchanged pursuit alive indefinitely. Reporting a failed approach returns control to combat positioning rather than dropping the opponent or granting a remote strike.

`GameCombatTargetingSystem` retains an aggressive fighter's chosen opponent within the shared **fighter-to-target** leash, independently of an approved melee position. It is not a radius around the camp, spawn point or start of combat. Fresh enemy detection keeps its existing shorter range. Invalid, dead, protected or no-longer-visible targets release normally; Defend and explicit player movement retain their existing behavior. Exact player attack orders are not limited by the autonomous leash.

Tune the saved default in the Godot Inspector at `features/combat/resources/combat_pursuit_settings.tres`: **Leash Distance**, in meters. The default is 100 m; the boundary is inclusive and uses horizontal distance. In-game, **Esc → Debug - Combat** exposes the same setting as a runtime-only override, read on the next target check. It does not change attack reach, speed or attack timing.

The same panel's **Show pursuit leashes** toggle is off by default. Cyan lines connect fighters to their current opponents; gold circles show the pursuit boundary around each fighter. Labels show current activity and actual distance. The overlay uses indexed lookup, limits itself to nearby fighters, and stops processing when disabled.

`test_combat_leash.gd` exercises target commitment, release, player authority and the runtime control. The `continuous_pursuit` case in `validate_combat_navigation_runtime.gd` requires physical enemies to follow and turn while the defending player keeps moving; catching up only after the player stops is not a pass.

## Native fallback and shared movement routing

When threaded queries are unavailable or disabled, `WorldNavigationController.get_movement_route()` owns a bounded pool in `world_navigation_routes.gd`. Nearby orders with the same start/destination tile pair share a small native map using the existing baked meshes. Longer orders share a coarse tile corridor plus its adjacent tiles. This is a derived query view, not another bake, movement solver or source of durable state. Each actor still follows its own native polygon path and collides normally; physics frequency and combat timing are unchanged.

The follower assigns this map to native path queries but explicitly keeps its avoidance-agent RID on the original world map. Otherwise actors taking different routes would stop avoiding one another. Route handles retain their native RIDs through cache eviction and handover. World-map identity/iteration changes discard cached views; a removed provider restores the native world destination, and an explicit foreign-map override wins.

Destination projection uses the existing tile-local nearest-point helper. Formation selection and shared squad combat decisions are not implemented by this change.

**Limits:** tile adjacency is a coarse hint, not proof of connected floors. A native rejection retries a broader corridor, then uses the original world map; do not clone/rebuild the entire world for this fallback. Nearest-point queries outside the local search also retain their original full-map fallback. Coarse graph construction and exceptional full-map queries still depend on world size. This improves ordinary nearby orders; it is not a guarantee that all navigation costs stay constant as the world grows. The map/corridor retention limit is `CACHE_LIMIT` in `world_navigation_routes.gd`; changing it affects derived memory/reuse on the next launch, not gameplay range.

`tests/unit/test_shared_navigation_routes.gd` covers local region isolation, distant geometry, corridor detours, unreachable targets, invalidation, native RVO across separate views, map overrides, tree re-entry and RID lifetime. `test_repeated_move_orders.gd` protects held repeats and interruptions. Production movement/frame-time comparisons must still exercise one selected actor and six selected actors with changing and held destinations; record worst frames as well as averages.

## Focused verification

From the project root:

- `godot --headless --path . --script res://tests/validation/validate_navigation_arrival.gd` — real actor arrival, interrupts, retargeting, unreachable/stuck routes, disposal and authority. Add `-- --benchmark` for the movement CPU fixture.
- `godot --headless --path . --script res://tests/validation/validate_navigation_lifecycle.gd` — stale results, settings resets, old/new bounds, local isolation, empty results and teardown.
- `godot --headless --path . --script res://tests/validation/validate_granary_navigation.gd` — actual World1/Mira, each entry and exit reset independently, after local rebaking. Add `-- --cached` to test existing cached navigation instead.

The granary case runner is also used in the live game. A nonempty path, a registered shape count, or arrival through the opposite doorway alone is not a traversal pass.
