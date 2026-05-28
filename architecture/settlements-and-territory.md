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
Guards
GuardPosts
Storage
ActivityPoints
Territory
RoadSpawn
DefenseSpawn
StateLabel
```

The root exports the settlement definition, resident root, storage paths, facility category roots, territory root, and town border radius.

The operator should be able to drag in a town scene, assign a settlement definition, add bars, fields, facilities, and points under named roots, then press play.

For large open-world production, this town root should normally be saved as its own scene and placed into the persistent world as an instance or streamed scene. Town-level customization happens in the town scene; the open world stores placement, streaming metadata, terrain, roads, and global controllers.

## Population Capacity

A town's max population comes from authored structures in the town scene.

`WorldBuilding.population_capacity` is the normal source. Current defaults are `Tiny House = 2`, `Keep = 4`, `Bar = 6`, and `Jail = 2`.

Use `PopulationCapacitySource` for explicit non-building housing such as an outdoor bedroll, tent, slum camp, or similar world-authored shelter.

Do not count beds inside a home separately. The whole building contributes its authored capacity.

A valid town should have at least one building or explicit population capacity source. Without authored capacity, `SettlementController.max_occupancy` is zero and the town has no population capacity.

Building capacity is a soft auto-generation ceiling, not a hard clamp. Events can push a town above capacity, but generated residents do not grow further until population falls back under the building-derived ceiling.

`SettlementController.population` means total living citizens. Staff, guards, rulers, and wardens are part of that total. The controller also tracks `population_assigned` and `population_available`, where available population is the unassigned labor pool a town can draw from for delayed role replacement.

When a staffed role actor dies, the town records a population death, opens a vacancy, and only fills that vacancy after the replacement delay if the town has available population. If the town has no available population, the role stays vacant until population recovers. Recovery is intentionally simple: if the town is below target population and not starving, daily upkeep can add a small number of citizens back toward the target.

Every citizen that can persist should have a `PopulationController` actor record. Generated residents are record-first and then realized as live actors when the town policy allows it. Authored humanoids are registered into records at runtime, with missing stable IDs generated from settlement-relative paths.

`SettlementTown.actor_realization_policy` controls live actor loading for a town. Use `full_town` by default. Use `important_plus_near` or `near_player` only when unloaded residents can be represented by ledger state without breaking expected local behavior.

## Facilities

`SettlementFacility` describes authored places inside a town.

Facility types include `generic`, `housing`, `farm`, `mine`, `bar`, `shop`, `storage`, `guard`, `social`, `police`, `weapon_shop`, `armor_shop`, `travel_shop`, `potion_shop`, and `tavern`.

Facilities can contribute daily food production, food consumption, storage capacity, job provider count, bar service area count, and activity point count.

The current facility data is simple on purpose so it can grow without forcing every town to use complicated setup.

`SettlementFacilityInstance` is the generic placed-facility contract. It points at a `FacilityFunctionDefinition` resource and can own child roots such as `BuildingSlot`, `Staff`, `ServicePoints`, `Storage`, `JobProviders`, and `ActivityPoints`.

Empty root paths are valid and are not auto-created. Typed facility scenes should expose only meaningful roots for that facility instead of carrying unused generic buckets.

The building or model under `BuildingSlot` is a neutral shell. The `FacilityFunctionDefinition` makes that placed instance behave like a bar, farm, shop, police station, weapon shop, armor shop, travel shop, potion shop, tavern, mine, or storage facility.

Facility records include the stable facility ID, function ID, owner faction, world position, production and consumption values, storage bonus, activity count, job provider count, bar service area count, building count, staff count, service point count, and storage link count.

`SettlementBar`, `SettlementField`, and `SettlementJail` are higher-level authoring presets over `SettlementFacilityInstance` for common facilities.

Use `SettlementBar` under a town's `Bars` root when the operator wants a drag-and-play bar with a building slot, generated or assigned barkeeper/waiter/guard roles, furniture, service points, guard posts, a generic facility visit point, merchant role, and job provider already wired.

`BarServiceArea` is an internal service component owned by `SettlementBar`. It handles paced waiter table service, repeat customer readiness while seated, bed rental checks, barkeeper stock handoff, and service/guard point lookup; operators should configure the `SettlementBar`, not the service area directly.

Server-shift jobs pay their configured base wage over time. Completed table service separately rolls a configurable Charisma check for tip and chance-based XP, using a lower repeatable-work XP scale than major dialogue checks. The default service check becomes very likely around level 30, so waiter training naturally fades to tiny XP. The bar schedules the next customer prompt after delivery, defaulting to roughly `10 +/- 3` seconds, so waiters pause between orders instead of chaining ready tables immediately.

NPC customers ask for waiter service through the simulated table-service flow. Player party members do not get automatic waiter prompts; when a selected party member is seated in a bar seat owned by a `BarServiceArea`, the inspector shows `Order` and the same-bar waiter walks to that table.

Bar furniture can live outside the building shell under one `Furniture` root. The reusable bar discovers seat and bed props recursively, and registers bed props as upper-floor content on the placed `WorldBuilding` so the building level-visibility system hides second-floor beds when the active actor is on the ground floor.

The bar uses one `FacilityVisitActivityPoint` under `ActivityPoints` for normal ambient townie visitors. That point scans real open `SittableSeat` props under `Furniture`, respects `visitor_capacity`, excludes party members, staff, workers, and marked special NPCs, and rejects visitors when no chair is open instead of moving them to a fallback marker. Future facilities can reuse the same visit point with real seats or authored `FacilityStandingPoint` nodes.

Bar default stock mirrors the parent settlement's supply ratio when available, with a standalone fallback for bars outside towns. This is a temporary stock-seeding rule; future economy work should restock barkeepers through settlement storage and broader supply systems instead of only modifying merchant inventory.

Use `SettlementField` under a town's `Fields` root when the operator wants a food-producing farm field with visible rows and farm activity points already wired.

Use `SettlementJail` under `Facilities` or a future `Jails` category root when the operator wants a drag-and-play authority facility with `BuildingSlot`, `EntryPoint`, `Staff`, `GuardPosts`, `Cells`, and a prisoner locker. Jail layout is authored in `scenes/world_sim/settlement_jail.tscn`, while reusable cell collision/visuals live in `scenes/world_sim/jail_cell.tscn` and reusable prisoner locker collision/visuals live in `scenes/world/containers/prisoner_locker_container.tscn`. `LawOrderController` handles witnessed local crimes, warrants, guard response, guard-carried jail admission, confiscation, sentence timing, legal release, and stolen-goods forfeiture.

## Guards And Role Slots

Staffed settlement roles are represented as role slots. Role slots consume citizens from the settlement labor pool and persist as ledger records even when their physical actors are unloaded in a wide open world.

Bar guards are private bouncers for their facility. They are tagged as private security and should not answer general settlement alarms.

Town guards, keep guards, jail guards, wardens, and rulers are settlement authority. Only guard-role authority actors answer law combat and custody responder calls; wardens and rulers remain authority staff without leaving their facility to fight thieves. Settlement alarms and jurisdiction trespass responses should use explicit authority tags, not names containing `guard`.

Generated civilians strip weapon and offhand starting gear. Generated town, keep, and jail guards spawn with authority loadouts, while bar guards spawn as private bouncers with hatchets and bandages.

`SettlementTown` owns town-level `Guards` and `GuardPosts` roots. These allow a town to have authority guards even if it has no jail. Guard post markers are editor-visible helpers and can remain hidden at runtime unless debug display is enabled.

The runtime model should support three simulation levels: abstract ledger updates for far settlements, realized visible actors for near settlements, and full local behavior only for the town currently interacting with the player.

## Activity Points

`SettlementActivityPoint` marks where residents can idle, work, socialize, guard, farm, mine, or sit.

`FacilityVisitActivityPoint` is the reusable facility visitor entry point. It is still an activity point, but it assigns the actor to real visit targets such as seats or `FacilityStandingPoint` nodes instead of being a physical crowd marker itself.

`SettlementActivityController` assigns available non-player residents to activity points by issuing `AMBIENT_ACTIVITY` AI jobs. Activity points expose `begin_ai_activity()` and `end_ai_activity()` so they behave like reusable smart objects instead of hidden movement scripts.

This keeps residents distributed around authored town places instead of clumping at the town center.

Activity points are editor-authored and should be easy to move, duplicate, and tune.

## Jobs

Jobs are their own coexisting system, but active assignments should be visible to the AI job layer.

A town may discover job providers, but it should not own job behavior.

Example: a town has a bar, the bar has a bar owner, and the bar owner has a `JobProvider`.

The job provider and job algorithms stay reusable for other contexts like caravan guard work, mining jobs, bar shifts, construction jobs, or future faction work. Accepted provider assignments create `ASSIGNED_WORK` AI jobs; the AI job owns live execution cadence/debug while the provider keeps slot, wage, and algorithm state.

## Bars, Shops, Mines, Storage

Existing systems should be reused.

- Bars use `SettlementBar`; its internal `BarServiceArea` coordinates bar service/guard nodes.
- Shops use `MerchantHumanoid` and `MerchantRole`.
- Mines use `MiningResourceNode` and job provider resource paths.
- Storage uses `WorldContainer`.

The town ties these systems together through discovery and stable facility records, not scene-specific logic.

For bar authoring, instantiate `scenes/world_sim/settlement_bar.tscn` under a town's `Bars` root instead of manually rebuilding internal bar service nodes.

The bar scene includes a default building. Replace `BuildingSlot/CurrentBuilding` when a different building model is wanted.

If a bar bed is moved or duplicated, keep it under `Furniture` and keep the `SleepableBed` script so the bar can continue registering it with the building's upper-floor visibility.

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

## Roads

Roads are authored as `RoadNetwork` roots with `RoadWaypoint` child nodes, not visible terrain meshes.

A road network is invisible world logic: endpoint waypoints store stable settlement IDs, intermediate waypoints shape the route, and authored waypoint connections define the graph that NPC squads can follow for world actions such as raids.

Operators normally use the inspector `Road Authoring` panel to create connected waypoints, set an existing waypoint as a connection source, connect it to another waypoint, and fill missing or duplicate waypoint IDs. The buttons maintain `connected_waypoint_paths`; `RoadController` compiles those links bidirectionally into an `AStar3D` graph and picks the shortest route between settlement endpoint waypoints.

If the world has a visible road model, texture, or terrain mark, that art is optional and separate from the road network data.

Road networks are visible in the editor as line helpers and waypoint orbs by default, and invisible at runtime unless toggled with the roads debug action.

`RoadController` collects road network records and provides route waypoints to `WorldSquadController`.

## Future Player Bases

Player base construction is not implemented yet.

The design should still allow a first player-built structure or storage object to auto-create a player settlement later.

That player settlement should use the same settlement, facility, storage, activity, and territory contracts as NPC towns.
