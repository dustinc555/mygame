# Settlements And Territory

`SettlementTown` is the human-facing editor root for an NPC town.

It extends the older settlement anchor contract and keeps towns easy to operate in the editor.

## Town Shape

A town should be organized under a single root like this:

```text
SettlementTown
Facilities
Bars
Fields
Shops
Mines
Housing
Residents
Storage
ActivityPoints
Territory
RoadSpawn
DefenseSpawn
StateLabel
```

The root exports the settlement definition, resident root, storage paths, facility category roots, territory root, and town border radius.

The operator should be able to drag in a town scene, assign a settlement definition, add bars, fields, facilities, and points under named roots, then press play.

## Facilities

`SettlementFacility` describes authored places inside a town.

Facility types include `generic`, `housing`, `farm`, `mine`, `bar`, `shop`, `storage`, `guard`, `social`, `police`, `weapon_shop`, `armor_shop`, `travel_shop`, `potion_shop`, and `tavern`.

Facilities can contribute daily food production, food consumption, storage capacity, job provider count, bar venue count, and activity point count.

The current facility data is simple on purpose so it can grow without forcing every town to use complicated setup.

`SettlementFacilityInstance` is the generic placed-facility contract. It points at a `FacilityFunctionDefinition` resource and owns standard child roots named `BuildingSlot`, `Staff`, `ServicePoints`, `Storage`, `JobProviders`, and `ActivityPoints`.

The building or model under `BuildingSlot` is a neutral shell. The `FacilityFunctionDefinition` makes that placed instance behave like a bar, farm, shop, police station, weapon shop, armor shop, travel shop, potion shop, tavern, mine, or storage facility.

Facility records include the stable facility ID, function ID, owner faction, world position, production and consumption values, storage bonus, activity count, job provider count, bar venue count, building count, staff count, service point count, and storage link count.

`SettlementBar` and `SettlementField` are higher-level authoring presets over `SettlementFacilityInstance` for common facilities.

Use `SettlementBar` under a town's `Bars` root when the operator wants a bar with a building slot, `BarVenue`, barkeeper, waiter, guard, furniture, service point, guard post, merchant role, and job provider already wired.

Bar furniture can live outside the building shell under `Furniture`. The reusable bar registers its `Furniture/Beds` root as upper-floor content on the placed `WorldBuilding` so the building level-visibility system hides second-floor beds when the active actor is on the ground floor.

Use `SettlementField` under a town's `Fields` root when the operator wants a food-producing farm field with visible rows and farm activity points already wired.

## Activity Points

`SettlementActivityPoint` marks where residents can idle, work, socialize, guard, farm, mine, or sit.

`SettlementActivityController` assigns available non-player residents to activity points.

This keeps residents distributed around authored town places instead of clumping at the town center.

Activity points are editor-authored and should be easy to move, duplicate, and tune.

## Jobs

Jobs are their own coexisting system.

A town may discover job providers, but it should not own job behavior.

Example: a town has a bar, the bar has a bar owner, and the bar owner has a `JobProvider`.

The job provider and job algorithms stay reusable for other contexts like caravan guard work, mining jobs, bar shifts, construction jobs, or future faction work.

## Bars, Shops, Mines, Storage

Existing systems should be reused.

- Bars use `BarVenue` and related bar service/guard nodes.
- Shops use `MerchantHumanoid` and `MerchantRole`.
- Mines use `MiningResourceNode` and job provider resource paths.
- Storage uses `WorldContainer`.

The town ties these systems together through discovery and stable facility records, not scene-specific logic.

For bar authoring, prefer `scenes/world_sim/settlement_bar.tscn` or `Add Child Node > SettlementBar` over manually rebuilding the `BarVenue` tree.

The bar scene does not require a baked-in building. Put the desired building model under `BuildingSlot`, or replace the current `BuildingSlot/CurrentBuilding` child in a composed town scene.

If a bar bed is moved, keep it under `Furniture/Beds` so the bar can continue registering it with the building's upper-floor visibility.

## Territory

Faction territory is authored through `FactionTerritoryAnchor`.

The data contract should be polygon-friendly even if early debug shapes are circles or boxes.

Territory means the land is claimed by a faction.

Future construction may be allowed inside another faction's territory, but it can trigger faction response, submission demands, reputation changes, or fighting.

## Town Borders

Town borders are different from faction territory.

A town border is a hard no-build radius around an existing town.

The town border protects authored settlements from being crowded by future player construction.

Town borders and territories are visible as editor helper meshes by default, but invisible at runtime unless toggled with debug actions.

## Future Player Bases

Player base construction is not implemented yet.

The design should still allow a first player-built structure or storage object to auto-create a player settlement later.

That player settlement should use the same settlement, facility, storage, activity, and territory contracts as NPC towns.
