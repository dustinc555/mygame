# World State

Runtime truth belongs in controllers and serializable data structures.

Nodes are allowed to execute behavior, display state, provide interaction points, and bridge authored scene data into controllers.

Nodes should not be the only place long-lived world truth exists.

## Controller-Owned Truth

Controllers own mutable state for broad systems.

Current examples:

- `FactionController`: faction definitions and reputations.
- `SettlementController`: settlement states, food, population, facility totals, events, and settlement action requests.
- `WorldSquadController`: active squads and raid execution state.
- `TerritoryController`: faction territory records, town border records, and build-permission queries.
- `RoadController`: authored road records, road debug visibility, and settlement-to-settlement route lookup.
- `WorldSimulationController`: facade for serialized world state and debug actions.
- `WorldTimeController`: authoritative world time for simulation ticks.

Facility records are controller-owned state once discovered. A record should use stable IDs and simple values such as `facility_id`, `function_id`, `owner_faction_id`, `world_position`, production and consumption totals, building count, staff count, service point count, storage link count, activity point count, job provider count, and venue count.

Settlement max occupancy is derived from authored population capacity sources under the town, such as `WorldBuilding.population_capacity` and explicit `PopulationCapacitySource` nodes. `SettlementDefinition` does not define town capacity.

## Serializable State

Controller state should serialize to dictionaries, arrays, strings, numbers, booleans, and basic Godot value types.

Avoid serializing live `Node`, `Resource`, signal, callable, or scene-instance references as durable state.

Use stable IDs in state records and resolve them back to resources or nodes at runtime.

## Events And Actions

Long-lived actions should be dictionaries with stable IDs.

Examples include settlement food changes, occupancy changes, raid requests, squad actions, territory updates, road route selection, and future construction claims.

Events should include enough context to replay, audit, save, or send over a network later.

Useful fields include `type`, stable IDs, amount values, reason, day/hour/minute, and world time.

## Time Authority

`WorldTimeController` is the time authority.

World simulation systems should listen to time signals or query absolute time from it instead of inventing separate calendar logic.

Short-lived animation or UI timers may still use local process time.

Simulation changes that affect the world should use world time when possible.

## Scene Bridge Pattern

Spatial nodes bridge authored scene data into controller state.

Examples:

- `SettlementTown` bridges town layout, facilities, residents, borders, and activity points into settlement systems.
- `SettlementFacilityInstance` bridges a placed building slot, facility function resource, staff, service points, storage links, jobs, and activity points into settlement facility records.
- `FactionTerritoryAnchor` bridges authored territory shape data into territory records.
- `RoadPath` bridges authored path points between stable settlement IDs into road records and squad route waypoints.
- `WorldBuilding` and `PopulationCapacitySource` bridge authored housing/camp capacity into settlement max occupancy.
- Containers, bars, mines, and job providers execute local interactions but can be discovered by town and job systems.

The bridge may use node paths internally, but persisted state should refer to stable IDs.
