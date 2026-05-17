# Online-Friendly Design

Online play and a DB-backed server are stretch goals, not current requirements.

The architecture should avoid choices that would block them later.

## Good Fit

The current direction is compatible with a future server-authoritative or DB-backed model because authored nodes/resources define data while controllers serialize runtime truth.

Stable IDs, dictionary state, event records, and time-driven simulation all map well to server records.

The server or save system can store facts like settlement food, population, facility records, faction reputation, inventory contents, active squads, and territory claims without storing a Godot scene tree.

## DB Shape

A future DB should store records, not nodes.

Example record fields:

- `faction_id`
- `settlement_id`
- `facility_id`
- `function_id`
- `definition_id`
- `owner_faction_id`
- `world_position`
- `building_count`
- `staff_count`
- `service_point_count`
- `storage_link_count`
- `shape_points`
- `inventory_entries`
- `road_id`
- `route_points`
- `population`
- `population_capacity`
- `population_capacity_sources`
- `food`
- `event_type`
- `absolute_minute`

Godot clients can instantiate scene views from these records and local authored definitions.

## Server Authority

If online support is added later, the server should own outcomes that affect persistent world truth.

Examples include construction claims, faction territory response, settlement food changes, raids, inventory transfers, reputation changes, death, recruitment, and production output.

Clients can still predict movement, show UI, animate, and request actions.

World speed is local/offline-controlled for now, but future online play should treat server world time as authoritative and hard-lock normal simulation speed unless a server/admin setting explicitly changes it. Client-side pause should not stop server-owned world state.

Local conversations pause world state through `WorldTimeController`; future online conversations should keep the dialog UI local and let the server simulation continue. If danger, combat, distance, or participant state invalidates the conversation, the client should close the dialog rather than expecting the server world to pause.

## Anti-Patterns

Avoid these if the state may persist, save, or replicate:

- Treating a `NodePath` as permanent identity.
- Storing live node references in serialized state.
- Putting one-off feature logic in a test scene.
- Letting client-only code decide permanent world outcomes.
- Generating important IDs from unstable node names or instance IDs.
- Mutating resource definitions as if they were per-save runtime state.

## Friendly Patterns

Prefer these for future-proof systems:

- Stable IDs for factions, settlements, facilities, items, squads, characters, territories, roads, and population capacity sources.
- Serializable controller dictionaries for mutable state.
- Resource definitions for reusable data.
- Facility function definitions for reusable building roles.
- Scene nodes as editor-authored views, anchors, and executors.
- Event/action dictionaries for long-lived state changes.
- `WorldTimeController` as the time source for simulation.

## Checklist

Before adding a new system, ask:

- Can the authored data be loaded from resources or scene nodes?
- Can the runtime state serialize without live nodes?
- Does every persistent object have a stable ID?
- Could a server validate this action later?
- Could a DB row represent the important state?
- Can a client rebuild the visual scene from state plus definitions?
