# Editor Authoring

The project should be easy for a human operator to author in the Godot editor.

Reusable systems should expose clear nodes, exported fields, child roots, and debug tools.

Reusable editor-authored content should also have concise workflow instructions in `operator/` when a human needs specific steps to add or configure it.

## Town Authoring

Use `scenes/world_sim/settlement_town.tscn` as the starting point for a town.

For the open world, each authored city or town should live in its own scene file, such as `scenes/world/towns/farmer_crossing.tscn`. The persistent world scene should instance or stream that town scene instead of owning all of the town's editable children directly.

Open the town scene directly when customizing bars, residents, fields, roads, activity points, interiors, or furniture. This keeps the editor scene tree focused on one settlement instead of forcing operators to filter through the whole world.

Assign a `SettlementDefinition` and set key exported paths such as residents, storage, facilities, territory, raid spawn, defense spawn, and state label.

Place visible buildings, optional road art, props, containers, NPCs, bars, fields, mines, guards, guard posts, jails, and activity points under the town.

At least one building or explicit `PopulationCapacitySource` must contribute population capacity for the town to have residents.

The test scene should only compose the town; it should not own town-specific gameplay code.

## Facilities

Add `SettlementFacility` or `SettlementFacilityInstance` nodes under `Facilities`, or use typed category roots such as `Bars`, `Fields`, `Shops`, `Mines`, and `Housing`.

Set the facility type, display name, owner faction, food production, food consumption, storage capacity, and activity point root as needed.

Keep facilities broad and readable.

Examples include farm fields, storehouse, village social area, bar, shop, mine, guard camp, housing block, and loot pile.

For generic facilities, set `facility_id`, `display_name`, `owner_faction_id`, and `facility_function`. Put the visible building or model under `BuildingSlot`, then add or edit only the staff, service points, storage links, job providers, and activity points that the facility actually uses. Empty root paths are valid and should stay empty instead of creating unused buckets.

For common facilities, prefer drag-in authoring scenes over manual node assembly:

- Instantiate `scenes/world_sim/settlement_bar.tscn` under `SettlementTown/Bars` for a drag-and-play bar.
- Use the default child under `SettlementBar/BuildingSlot`, or replace `BuildingSlot/CurrentBuilding` if a different building model is wanted.
- For normal bars, let the bar infer `facility_id`, owner faction, staff IDs, and staff squad from the parent settlement and bar node name.
- Keep tables, chairs, and beds directly under `SettlementBar/Furniture`; the bar discovers seats/beds there and registers bed props with the placed building's upper-floor visibility.
- Keep the generated `ActivityPoints/FacilityVisitPoint` as the single ambient visitor entry point. It scans real open chairs under `Furniture`; do not add per-chair visitor points or fallback crowd markers.
- Do not manually configure `BarServiceArea`; it is the internal service component owned by `SettlementBar`.
- Add `scenes/world_sim/settlement_field.tscn` under `SettlementTown/Fields`, or use `Add Child Node > SettlementField`, for a food-producing field.
- Set `facility_id`, `display_name`, `owner_faction_id`, and `food_production_per_day` on the field.
- Instantiate `scenes/world_sim/settlement_jail.tscn` under `SettlementTown/Facilities` for a jail with a building slot, entry point, staff, guard posts, lockable cells, and a prisoner locker.
- Edit jail layout in `scenes/world_sim/settlement_jail.tscn`; edit reusable cell internals in `scenes/world_sim/jail_cell.tscn`; edit reusable prisoner locker internals in `scenes/world/containers/prisoner_locker_container.tscn`.
- Use town-level `Guards` and `GuardPosts` for settlement authority guards that are not owned by a jail or keep.
- Use `scenes/test_levels/jail_law_demo.tscn` as the standalone manual smoke scene for witnessed theft, guard response, jail cells, and locker lock difficulty.

## Population Capacity

Set `population_capacity` on reusable `WorldBuilding` scenes that represent housing or other resident capacity.

Use whole-structure counts, such as `3` for a tiny house and `6` for a two-story house.

Do not count beds inside a building as extra population.

For outdoor slums, tents, sleeping rolls, or other non-building shelters, add a `PopulationCapacitySource` node under the town and set its capacity explicitly.

`SettlementDefinition` does not define town capacity; authored town content does.

`SettlementController.population` is total living citizens. Staff and guards draw from that total through role slots, while `population_available` is the unassigned labor pool. Killing a staffed actor reduces total population and opens a delayed vacancy; the slot only refills when the replacement delay has passed and an available citizen exists.

## Population Appearance

Use `PopulationAppearanceProfile` resources for generated settlement residents instead of hardcoding race, sex, clothing, hair, skin, or skeleton variation in scene scripts.

Assign a profile to `SettlementPopulationSpawner.population_appearance_profile`. The profile controls allowed races, allowed body types, outfit pools, hair/beard styles, natural hair colors, natural skin tones, and conservative body slider ranges.

Leave `allowed_races` empty when the population can use any available race. Set explicit race resources when authoring restricted groups such as human-only guards, robot-only towns, or mixed-race slave populations.

Use multiple spawners or profiles under the same town when groups have different rules, such as slaves, guards, merchants, or owners.

## Population Names

Use `PopulationNameProfile` resources for generated settlement resident display names instead of placeholder prefixes like `Farmer 19` or scene-specific hardcoded lists.

Assign a default profile to `FactionDefinition.population_name_profile`. Settlement-level and spawner-level name profiles are local overrides for special settlements or groups such as slaves, guards, nobles, or fort occupiers.

The profile picks deterministic names from body-specific, neutral, and wasteland nickname pools using the spawner seed and each actor's stable ID.

Generated names are unique-first within each spawner. Keep duplicate chances low and expand the profile pools when a town can spawn more residents than the available name set.

Leave name arrays empty to use the shared curated defaults, or fill them for culture-specific populations. Larger external datasets can be added later behind the same profile resource contract.

## Faction Culture

Use `FactionDefinition` as the human-operator entry point for culture defaults. A faction can reference behavior, personality, law, and population name profiles.

Settlement definitions can override behavior, personality, law, and names for special local cultures. Spawners can override population names and appearance for local groups. The override order is local group, settlement, faction, then shared defaults.

Do not use faction defaults to rename existing persisted locals after conquest. Names belong to actors/populations; use replacement spawners or local profile changes only when the population itself changes.

`FactionLawProfile` should keep the stable common law baseline: no killing, no stealing, and no trespassing. Use profile options for cultural differences such as personal retaliation for petty theft, different trespass warning counts, or wider/narrower alarm radius.

Current runtime law uses `LawOrderController`: witnesses create warrants, stolen item metadata applies immediately, same-settlement merchants refuse active stolen goods, and jail release returns legal gear while forfeiting stolen goods.

Reputation and diplomacy are separate. Reputation controls standing labels from `Vilified` through `Beloved`; formal diplomacy controls political state such as `War`, `Trade`, `Alliance`, `Vassal`, `Tributary`, or `Protectorate`.

The player faction only auto-helps formal allies and protectorates when `Help allies` is enabled in the Factions menu. Neutral reputation never causes automatic intervention.

## World Conflict Events

Use `WorldConflictEvent` and `WorldEventChoiceController` for nearby player choices in faction conflicts. The event should be spatial, reusable, and local to the conflict, not a global notification.

Conflict prompts pause the game and appear only when the player party is inside the event radius. `Ignore` is always valid. Choosing a side creates temporary event hostility, but reputation and favor changes apply only after the player satisfies participation.

Use this pattern for settlement raids, caravan ambushes, survivors attacked by hostile groups, and other reusable world events where the simulation needs to know which side the player actually helped.

## Activity Points

Add `SettlementActivityPoint` nodes where NPCs should go.

Use activity types such as idle, social, farm, guard, work, mine, and sit.

Tune weight and active hours to shape daily behavior.

Use exclusive points for guard posts or single-worker locations.

Use `FacilityVisitActivityPoint` when a facility needs normal resident visitors. Configure it to scan real seats or authored `FacilityStandingPoint` nodes so visitors occupy physical spots instead of clumping at the activity marker.

## Character Appearance And Barbers

Use `CharacterAppearanceData` resources or actor defaults for reusable actor appearance. The live actor should only change after the editor saves; previews and cancel flow must stay draft-only. Creation mode also stores race, sex, body adjusters, and skin color before spawning a new party member.

Use `HeadAttachmentStyleDefinition` resources for reusable hair, beard, and eyebrow entries. The visual scene should be an imported `PackedScene` and the resource should provide a stable `style_id`, display name, slot, and default color. Eyebrows are automatic by body type, not exposed as barber style controls: human male bodies use Regular eyebrows and human female bodies use Fine eyebrows. Eyebrow color follows hair color.

`CharacterAppearanceController` is created by `GameBootstrap`. Scenes should not manually own the character editor; they place actors and optional barber NPCs, and the bootstrapped controller handles opening, payment, editor-specific world pause, save, and cancel routing.

Character creation should use a dedicated creation scene, not a barber shortcut. `res://scenes/test_levels/character_creation_demo.tscn` opens creation mode, then spawns and selects a new party member with starter gear after save.

The character editor is a full-screen opaque modal. Its preview viewport must use an isolated `World3D`, studio backdrop, visual-only mannequin nodes, actor-matching clothing, full-body and compact Face toggle camera modes, and mouse-drag yaw/pitch rotation, not duplicated live actors, collision bodies, navigation agents, or scene-world cameras.

Body-specific style rules belong in reusable appearance/style data and editor filtering. Human male hair options are Buzzed, Simple Parted, and Long; human female hair options are Buns, Long, and Buzzed Female. Female bodies should not expose beard options. Barber/update mode must not expose Race, Sex, body adjusters, or skin color.

Instantiate `res://scenes/characters/vendors/barber_npc.tscn` for a reusable barber. Set the barber's display fields, conversation definition, starting equipment, and `barber_service_price` in the inspector. The default conversation opens the barber editor through `barber.open_editor` and charges the speaking actor.

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
