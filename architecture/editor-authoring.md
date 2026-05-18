# Editor Authoring

The project should be easy for a human operator to author in the Godot editor.

Reusable systems should expose clear nodes, exported fields, child roots, and debug tools.

Reusable editor-authored content should also have concise workflow instructions in `operator/` when a human needs specific steps to add or configure it.

## Town Authoring

Use `scenes/world_sim/settlement_town.tscn` as the starting point for a town.

Assign a `SettlementDefinition` and set key exported paths such as residents, storage, facilities, territory, raid spawn, defense spawn, and state label.

Place visible buildings, optional road art, props, containers, NPCs, bars, fields, mines, and activity points under the town.

At least one building or explicit `PopulationCapacitySource` must contribute population capacity for the town to have residents.

The test scene should only compose the town; it should not own town-specific gameplay code.

## Facilities

Add `SettlementFacility` or `SettlementFacilityInstance` nodes under `Facilities`, or use typed category roots such as `Bars`, `Fields`, `Shops`, `Mines`, and `Housing`.

Set the facility type, display name, owner faction, food production, food consumption, storage capacity, and activity point root as needed.

Keep facilities broad and readable.

Examples include farm fields, storehouse, village social area, bar, shop, mine, guard camp, housing block, and loot pile.

For generic facilities, set `facility_id`, `display_name`, `owner_faction_id`, and `facility_function`. Put the visible building or model under `BuildingSlot`, then add or edit staff, service points, storage links, job providers, and activity points under their matching roots.

For common facilities, prefer drag-in authoring scenes over manual node assembly:

- Instantiate `scenes/world_sim/settlement_bar.tscn` under `SettlementTown/Bars` for a drag-and-play bar.
- Use the default child under `SettlementBar/BuildingSlot`, or replace `BuildingSlot/CurrentBuilding` if a different building model is wanted.
- Set `facility_id`, `display_name`, `owner_faction_id`, `staff_stable_id_prefix`, and `staff_squad_name` on the bar.
- Keep second-floor bar beds under `SettlementBar/Furniture/Beds`; the bar registers that root with the placed building's upper-floor visibility.
- Do not manually configure `BarServiceArea`; it is the internal service component owned by `SettlementBar`.
- Add `scenes/world_sim/settlement_field.tscn` under `SettlementTown/Fields`, or use `Add Child Node > SettlementField`, for a food-producing field.
- Set `facility_id`, `display_name`, `owner_faction_id`, and `food_production_per_day` on the field.

## Population Capacity

Set `population_capacity` on reusable `WorldBuilding` scenes that represent housing or other resident capacity.

Use whole-structure counts, such as `3` for a tiny house and `6` for a two-story house.

Do not count beds inside a building as extra population.

For outdoor slums, tents, sleeping rolls, or other non-building shelters, add a `PopulationCapacitySource` node under the town and set its capacity explicitly.

`SettlementDefinition` does not define town capacity; authored town content does.

## Activity Points

Add `SettlementActivityPoint` nodes where NPCs should go.

Use activity types such as idle, social, farm, guard, work, mine, and sit.

Tune weight and active hours to shape daily behavior.

Use exclusive points for guard posts or single-worker locations.

## Territory And Borders

Add `FactionTerritoryAnchor` for faction land claims.

Use polygon data as the preferred mental model, even if a circle or box is enough for early testing.

Set the town border radius on `SettlementTown` for hard no-build space around the town.

Territory and borders should be visible in the editor as helper meshes and invisible at runtime by default.

Use debug buttons to show faction territories and town borders when authoring or testing.

## Roads

Add `RoadNetwork` nodes under a scene-level `Roads` root or another clear world-data root.

Set `network_id` and `display_name` on the network.

Use the inspector `Road Authoring` panel to create, connect, and remove `RoadWaypoint` children. `Create First Waypoint` starts a network, `Create Additional Waypoint From This` adds an attached sibling waypoint, `Set As Connection Source` plus `Connect From Source` connects two existing waypoints, and `Delete This Waypoint` removes a waypoint while cleaning inbound connection paths.

Move waypoints in the 3D viewport and set `settlement_id` on waypoints that represent settlement road entrances. Road waypoints are visible clickable meshes so operators can click the orb instead of finding the node in a large scene tree.

Use settlement IDs from the linked `SettlementDefinition` resources, not node names or paths.

The authoring buttons maintain `connected_waypoint_paths`; manual edits are only needed for unusual cleanup. Author each connection once; the runtime graph compiles links bidirectionally.

Use `Ensure All Waypoint IDs` or `Ensure Network IDs` to fill missing IDs and fix duplicates. Waypoint node names are only editor handles; stable route identity comes from `waypoint_id`.

Roads are invisible gameplay data. Keep any visible road mesh, decal, or terrain paint separate from `RoadNetwork` and `RoadWaypoint` nodes.

Road debug lines and waypoint markers should be visible in the editor and hidden at runtime unless the roads debug action is toggled.

## Validation

After changing shared systems, run the validation listed in root `AGENT.md`.

For changed GDScript files, run the `--check-only --script` command.

For scene composition changes, load the relevant scene headlessly long enough to catch startup errors.

Do not claim validation passed unless the command was run and succeeded.

## Operator Instructions

When reusable editor workflow changes, update the matching file in `operator/` or add a new one.

Instructions should name the exact scene tree path to select, the exact editor action to use, any scene or resource path to pick, exported fields to set, required renames, and a simple done check.

## Operator Checklist

Before considering a town ready, check:

- The town has a stable settlement ID through its definition.
- The town has at least one building or explicit capacity source contributing population capacity.
- The town has facilities with stable facility IDs.
- Drag-in bars and fields live under the named `Bars` and `Fields` roots when used.
- Residents have stable IDs or are spawned from a stable prefix.
- Storage ownership uses the correct faction.
- Activity points are spread around meaningful places.
- Territory and town border debug toggles display expected fields.
- Road waypoint endpoints use stable settlement IDs, waypoint IDs are unique within each network, and the roads debug toggle displays expected routes.
- No gameplay logic is hardcoded in the test scene.
