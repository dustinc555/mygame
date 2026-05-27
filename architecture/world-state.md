# World State

Runtime truth belongs in controllers and serializable data structures.

Nodes are allowed to execute behavior, display state, provide interaction points, and bridge authored scene data into controllers.

Nodes should not be the only place long-lived world truth exists.

## Controller-Owned Truth

Controllers own mutable state for broad systems.

Current examples:

- `FactionController`: faction definitions and reputations.
- `SettlementController`: settlement states, food, total population, available labor, assigned staff role counts, vacancies, facility totals, events, and settlement action requests.
- `WorldSquadController`: active squads and raid execution state.
- `TerritoryController`: faction territory records, town border records, and build-permission queries.
- `RoadController`: authored road records, road debug visibility, and settlement-to-settlement route lookup.
- `WorldSimulationController`: facade for serialized world state and debug actions.
- `WorldTimeController`: authoritative world time for simulation ticks.
- `CharacterAppearanceController`: bootstrapped modal editor ownership, barber payment, and save/cancel routing.

Facility records are controller-owned state once discovered. A record should use stable IDs and simple values such as `facility_id`, `function_id`, `owner_faction_id`, `world_position`, production and consumption totals, building count, staff count, service point count, storage link count, activity point count, job provider count, and bar service area count.

Settlement max occupancy is derived from authored population capacity sources under the town, such as `WorldBuilding.population_capacity` and explicit `PopulationCapacitySource` nodes. `SettlementDefinition` does not define town capacity.

Staff role slots are controller-visible state. Physical staff actors may be unloaded in far settlements, but the slot ledger persists vacancy timing, assignment count, authority scope, and population consequences.

Character appearance truth lives on the actor as `CharacterAppearanceData`. The appearance controller owns only short-lived editor session state: draft data, the target actor, barber fee collection, editor-specific world pause, and applying the saved draft back to the actor.

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

Local world speed is also owned by `WorldTimeController`. Its speed presets drive `Engine.time_scale`, so movement, animation, hunger, bleeding, recovery, mining, jobs, guard shifts, raids, lighting, weather-style effects, and world-clock advancement derive from the same world-sim speed.

`LawOrderController` also depends on world time. Stolen item tags, warrant expiry, prisoner sentence duration, and delayed legal release should use absolute minutes from `WorldTimeController`.

Manual pause is a world pause and shows the HUD `PAUSED` overlay. Conversation pause is also requested through `WorldTimeController` for local/offline play, but it does not show the `PAUSED` overlay because the conversation window is the active modal UI.

The current `server_authoritative_mode` flag is only a future-proof policy seam. If a future online/server-authoritative mode is enabled, conversation pause requests should not pause server-owned world state; server simulation speed should default to Normal unless an explicit server/admin setting changes it.

## Scene Bridge Pattern

Spatial nodes bridge authored scene data into controller state.

Examples:

- `SettlementTown` bridges town layout, facilities, residents, borders, and activity points into settlement systems.
- `SettlementFacilityInstance` bridges a placed building slot, facility function resource, staff, service points, storage links, jobs, and activity points into settlement facility records.
- `FactionTerritoryAnchor` bridges authored territory shape data into territory records.
- `RoadNetwork` and `RoadWaypoint` bridge authored road graph data between stable settlement IDs into road records and squad route waypoints.
- `WorldBuilding` and `PopulationCapacitySource` bridge authored housing/camp capacity into settlement max occupancy.
- `SettlementJail`, reusable `JailCell` scene instances, and the reusable `PrisonerLocker` container scene bridge authored jail layout into local custody state owned by `LawOrderController`.
- Containers, bars, mines, and job providers execute local interactions but can be discovered by town and job systems.

The bridge may use node paths internally, but persisted state should refer to stable IDs.
