extends Resource

class_name WorldNavigationSettings

## Authoring surface for runtime navmesh tile baking. Edit the default
## resource at features/core/navigation/resources/world_navigation_settings.tres,
## or tune live in game via the debug menu (Navigation section) and copy the
## winners back here. Hover any property in the inspector for its trade-off.

## Walkable area is eroded by this much around every obstacle. INVARIANT:
## must be >= the character capsule radius (0.45) or the navmesh promises
## paths the body cannot fit (wedged characters at stair bottoms/doorways).
## At cell_size 0.1, 0.5m/side keeps a center path through 1.2m modular
## doorways while clearing the 0.45m physical capsule.
@export_range(0.2, 0.6, 0.01) var agent_radius := 0.5

## Actor capsule height for ceiling clearance.
@export_range(1.0, 2.5, 0.05) var agent_height := 1.5

## Steepest walkable slope. Must stay at or below CharacterBody3D's physical
## climb limit (floor_max_angle ~45) or paths cross ground actors cannot
## walk and orders fail mid-route. Stair ramp colliders are ~33 degrees.
@export_range(30.0, 75.0, 1.0) var agent_max_slope := 40.0

## Highest step an agent climbs without a ramp (thresholds, curbs). Also
## rounded to voxels: effective climb = floor(agent_max_climb / cell_height).
@export_range(0.1, 0.6, 0.05) var agent_max_climb := 0.3

## Voxel size of the bake. THE bake-time knob: per-tile cost scales with
## (tile_size / cell_size)^2. Coarser cells erase narrow corridors and snag
## agents on small ground bumps; 0.1 (operator-tuned 2026-07-04) walks clean.
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

## How many tile bakes may run on worker threads at once. The whole world
## bakes once at startup behind the loading screen; more workers = shorter
## load.
@export_range(1, 8, 1) var max_concurrent_bakes := 4

## false: whole terrain is walkable, filtered by agent_max_slope.
## true: only areas painted navigable with Terrain3D's editor brush.
@export var require_navigable_paint := false

## Godot #85548 workaround (vertex rounding + degenerate/overlap removal).
## Also keeps tile border vertices cell-aligned so edge connections match.
@export var postprocess_enabled := true

## Print each tile bake's duration to the console.
@export var log_timing := false
