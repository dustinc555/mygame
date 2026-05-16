# Game Data

Game data is primarily authored with Godot resources and nodes.

Resources define reusable data such as items, factions, settlement definitions, facility function definitions, behavior profiles, squad templates, prices, stock, jobs, race data, and body archetypes.

Scene nodes define authored world composition such as towns, facilities, NPCs, containers, bars, mines, activity points, territory anchors, buildings, and debug objects.

## Node Data Graph

Keep this graph current when world-sim data relationships change.

```dot
digraph GameData {
  rankdir=LR;
  node [shape=box, style="rounded"];

  Resources [label="Resource Definitions"];
  Nodes [label="Editor Nodes"];
  Controllers [label="Runtime Controllers"];

  Resources -> FactionDefinitions;
  Resources -> SettlementDefinitions;
  Resources -> ItemDefinitions;
  Resources -> JobDefinitions;
  Resources -> FacilityFunctionDefinitions;
  Resources -> BehaviorProfiles;
  Resources -> SquadTemplates;

  Nodes -> SettlementTown;
  Nodes -> FactionTerritoryAnchor;
  Nodes -> NPCs;
  Nodes -> Containers;
  Nodes -> Bars;
  Nodes -> Mines;
  Nodes -> ActivityPoints;
  Nodes -> SettlementFacilityInstance;
  Nodes -> SettlementBar;
  Nodes -> SettlementField;

  FactionDefinitions -> Factions;
  Factions -> Territories;
  Factions -> Towns;
  Factions -> Squads;
  Factions -> NPCs;

  FactionTerritoryAnchor -> Territories;
  Territories -> BuildRules;
  BuildRules -> ForeignFactionResponse;
  BuildRules -> TownNoBuildRadius;

  SettlementDefinitions -> Towns;
  SettlementTown -> Towns;
  Towns -> Facilities;
  Towns -> Residents;
  Towns -> Storage;
  Towns -> TownBorders;
  Towns -> ActivityPoints;

  SettlementFacilityInstance -> Facilities;
  FacilityFunctionDefinitions -> FacilityFunctions;
  Facilities -> FacilityFunctions;
  Facilities -> BuildingSlots;
  Facilities -> Staff;
  Facilities -> ServicePoints;
  Facilities -> JobProviders;
  Facilities -> StorageLinks;
  Facilities -> Farms;
  Facilities -> Bars;
  Facilities -> Shops;
  Facilities -> Mines;
  Facilities -> GuardPosts;
  Facilities -> Housing;
  Facilities -> SocialAreas;
  SettlementBar -> Bars;
  SettlementField -> Farms;
  BuildingSlots -> BuildingModels;

  Bars -> BarOwner;
  Shops -> Merchant;
  Mines -> ResourceNodes;
  Farms -> FoodProduction;

  BarOwner -> JobProviders;
  Merchant -> JobProviders;
  JobProviders -> Jobs;
  Jobs -> Workers;

  NPCs -> Inventory;
  Containers -> Inventory;
  Shops -> ShopInventory;
  ItemDefinitions -> Inventory;
  ResourceNodes -> ResourceItems;
  ResourceItems -> ItemDefinitions;

  Controllers -> FactionController;
  Controllers -> SettlementController;
  Controllers -> TerritoryController;
  Controllers -> WorldSquadController;
  Controllers -> WorldTimeController;

  FactionController -> FactionState;
  SettlementController -> SettlementState;
  TerritoryController -> TerritoryState;
  WorldSquadController -> SquadState;
  WorldTimeController -> DailyUpkeep;

  DailyUpkeep -> FoodProduction;
  DailyUpkeep -> FoodConsumption;
  DailyUpkeep -> SettlementState;
  SettlementState -> Events;
  SquadState -> Events;
  TerritoryState -> BuildRules;
}
```

## Definitions Versus State

Definitions answer: what is this thing supposed to be?

Runtime state answers: what is true right now?

Examples:

- `ItemDefinition` defines an item type; inventory data stores item counts and ownership state.
- `FactionDefinition` defines faction defaults; `FactionController` stores reputation and discovered faction state.
- `SettlementDefinition` defines a town's authored defaults; `SettlementController` stores food, population, events, and facility totals.
- `FacilityFunctionDefinition` defines what a placed facility does, such as bar, farm, shop, police, weapon shop, armor shop, travel shop, potion shop, tavern, mine, or storage.
- `SettlementFacilityInstance` bridges the placed building slot, staff, service points, storage links, jobs, and activity points into a serializable facility record.
- `SettlementTown` and child nodes define authored town layout; controllers use stable IDs to serialize the town's runtime truth.

## Stable IDs

Anything referenced by save data, world simulation, faction logic, server records, or long-lived events needs a stable ID.

Use IDs like `farmer_crossing`, `raider_camp`, `Farmers`, `Raiders`, `farmer_crossing.farm_fields`, `farmer_crossing.bar`, `bar`, and `npc.farmer_crossing.01`.

Do not rely on node names or `NodePath` values as permanent identity when the state may need to persist or replicate.

Node paths are acceptable for editor-local wiring, such as a bar pointing to its owner, a job provider pointing to resources, or an activity point pointing to a target node.

## Scene Data

Scenes should compose reusable systems.

Scenes may place a `SettlementTown`, facility instances, containers, NPCs, roads, labels, debug buttons, buildings, and activity markers.

Scenes must not own unique gameplay behavior that only works in that scene.

If a scene needs new behavior, add it as a reusable script, controller, resource, or scene contract first.

## Resource Data

Resources should be portable and reusable.

Prefer resources for data that should be reused across scenes or stored as a definition in future save/DB records.

Prefer nodes for data that is spatial, editor-authored, and scene-composed.

When in doubt, use a resource for the reusable definition and a node for the placed instance.
