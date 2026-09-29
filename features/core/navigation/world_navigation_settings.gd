extends Resource

class_name WorldNavigationSettings

## Shared authoring surface for offline prebaking and runtime tile patches.
## Edit the default
## resource at features/core/navigation/resources/world_navigation_settings.tres,
## or tune live in game via the debug menu (Navigation section) and copy the
## values back to that resource. Hover a property for its units and trade-off.

@export_group("Clearance")

## Walkable area is eroded by this much around every obstacle. INVARIANT:
## must be >= the character capsule radius (0.45) or the navmesh promises
## paths the body cannot fit (wedged characters at stair bottoms/doorways).
## At cell_size 0.1, 0.5m/side keeps a center path through 1.2m modular
## doorways while clearing the 0.45m physical capsule.
@export_range(0.2, 0.6, 0.01) var agent_radius := 0.5

## Ceiling clearance reserved by the baker, in meters. This must fit the
## physical body; it is not NavigationAgent3D.height (crowd avoidance).
@export_range(1.0, 2.5, 0.05) var agent_height := 1.5

## Steepest baked walkable slope, in degrees. Must stay at or below the
## actor's physical floor limit (WorldActor.max_walkable_slope_degrees).
@export_range(30.0, 75.0, 1.0) var agent_max_slope := 40.0

## Maximum vertical connection between bake voxels, in meters. This is a
## Recast setting, NOT a CharacterBody3D step-up implementation. WorldActor
## uses floor snapping and real ramps; an exposed ledge this high is not
## guaranteed walkable. Keep physical traversal tests when changing it.
## Rounded down to a multiple of cell_height by the baker.
@export_range(0.1, 0.6, 0.05) var agent_max_climb := 0.3

@export_group("Bake Resolution")

## Voxel size of the bake. THE bake-time knob: per-tile cost scales with
## (tile_size / cell_size)^2. Coarser cells erase narrow corridors and snag
## agents on small ground bumps. The default .tres overrides this to 0.1m.
@export_range(0.05, 0.5, 0.01) var cell_size := 0.16

## Voxel height of the bake. Finer values make agent_max_climb resolve more
## precisely at door thresholds and stair junctions.
@export_range(0.05, 0.5, 0.01) var cell_height := 0.1

## Edge length of one navmesh tile. Smaller = faster individual bakes and
## finer dynamic patching, more regions/edges on the map. Borders are
## cell-aligned so neighboring tiles stitch via edge connections.
@export_range(32.0, 128.0, 16.0) var tile_size := 64.0

## Vertical extent of each tile bake.
@export_range(64.0, 512.0, 32.0) var tile_height := 256.0

@export_group("Scheduling")

## Concurrent worker limit for initial cache misses and local tile patches.
## Matching prebaked tiles are loaded, not rebuilt on every startup.
@export_range(1, 8, 1) var max_concurrent_bakes := 4

@export_group("Runtime Path Queries")

## Background native path queries. Actor collision and scene changes remain on
## the main thread. Changes apply to subsequently submitted movement commands.
@export var threaded_queries_enabled := true
## Concurrent path batches, separate from background navmesh baking.
@export_range(1, 8, 1) var path_query_workers := 4
## Workers reserved for direct player orders when at least two workers exist.
## Remaining workers keep ordinary AI routes progressing during held input.
@export_range(1, 4, 1) var path_query_player_workers := 1
## Destination paths per task, including chunks of multi-candidate combat work.
## A restricted-region miss may also retry that destination on the whole map.
@export_range(1, 16, 1) var path_query_batch_size := 4
## Maximum distinct outstanding actor requests; repeated commands coalesce.
@export_range(32, 4096, 32) var path_query_capacity := 512

@export_group("Terrain and Diagnostics")

## false: whole terrain is walkable, filtered by agent_max_slope.
## true: only areas painted navigable with Terrain3D's editor brush.
@export var require_navigable_paint := false

## Godot #85548 workaround (vertex rounding + degenerate/overlap removal).
## Also keeps tile border vertices cell-aligned so edge connections match.
@export var postprocess_enabled := true

## Print each tile bake's duration to the console.
@export var log_timing := false
