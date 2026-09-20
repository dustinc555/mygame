# Zone authoring and resource deposits

## Where to click

Open a zone scene (for example `scenes/zones/rustwash_basin/rustwash_basin.tscn`) and select its root. The **Zone** bottom panel contains **Overview · Towns · Resources**. World assembly stays in the existing World panel; towns and facilities keep their own editors.

- **Overview:** zone identity, content counts, and **Advanced: Resource Refill Performance**.
- **Towns:** existing town list and Add Town. Selecting/opening a town uses the existing town tools.
- **Resources:** searchable Ore/Scrap catalog, real mesh thumbnails, and **Place / Type Defaults**. The viewport's **Place Resource** button opens this page directly.

Select a deposit, choose **Place in Zone** (or double-click its catalog entry), then click the ground repeatedly. Drag before releasing to aim; **R** turns the preview; the mouse wheel adjusts its height. Escape/right-click stops placement. Use normal Undo/Redo and save the zone. Deposits are ordinary independent scene instances; no field or mandatory grouping is created. Placement while viewing a zone instance opens that zone's source scene first.

Selecting an existing deposit shows its own type's settings, not the previously browsed type. The Inspector still exposes that placed object's transform and ownership fields. **Open Deposit Scene** opens the reusable visual/interaction scene, not a second copy of its gameplay rules.

Existing terrain/collision authoring still uses the normal world-navigation prebake workflow. Adding deposits does not redesign navigation or silently rebake the world.

## Shared tuning

Under **Resources → Type Defaults**:

- **Stock per refill:** a positive minimum/maximum. Copper counts ore; scrap counts scavenging attempts, not guaranteed loot items. Initial stock and subsequent refills use this range.
- **Refill after depletion:** decides whether a *new* depletion schedules replenishment.
- **Refill delay:** minimum/maximum **in-game weeks**, not real-world time. The dock uses quarter-week steps. A single random deadline is chosen when stock reaches zero.

Dock edits save the shared `.tres` automatically and support Undo/Redo. **Open All Type Settings** reveals the same resource in Godot's Inspector; use the Inspector's normal resource-saving workflow there.

Changing these defaults does **not** reset existing stock or change a saved refill deadline. The next refill uses the current stock range. Disabling refills does not cancel an already queued refill; enabling them does not retroactively refill an empty deposit that had no scheduled refill.

The four current entries live under `features/world/resources/resource_deposits/`: copper, scrap pile, twisted scrap heap, and robot wreck. Their data files—not UI constants—define the balance. Copper is now finite. Scrap no longer rerolls stock when its scene loads.

Advanced processing limits are separate from balance: **Overview → Advanced: Resource Refill Performance** opens `features/world/resources/resource_deposit_settings.tres`. It controls maximum refills per frame and a soft millisecond work budget. A single callback is indivisible, so this is not a guarantee about whole-game frame time.

## One owner for each responsibility

| Responsibility | Owner |
| --- | --- |
| Zone context, selection, UndoRedo, source-scene opening | `addons/world_authoring/zone_tools.gd` |
| Workspace tabs / resource master-detail UI | `zone_dock.gd` / `zone_resource_browser.gd` in the same addon |
| Catalog discovery, ordinary scene placement, stable IDs | `addons/world_authoring/resource_authoring.gd` |
| Cached editor-only mesh thumbnails | `addons/world_authoring/scene_thumbnail.gd` |
| Shared type defaults | `features/world/resources/resource_deposit_definition.gd` and the catalog `.tres` files |
| Stock transactions, scheduling, weak live bindings | `features/world/sim/resource_deposit_controller.gd` |
| Saved scalar record | `features/world/sim/c_game_resource_deposit_state.gd`, indexed/serialized by GECS |
| Mining/scavenging scene facade | `features/world/bridge/resource_nodes/resource_deposit_node.gd` and its existing subclasses |

GameBootstrap registers the resource controller once through `world_module.gd`. Inventory delivery and depletion share one authorized completion boundary; unavailable tools, denied access, and full mining inventories do not spend stock. Existing mining/scavenging, theft, skill, and job interfaces remain the callers.

Depleted records enter one indexed deadline heap. World-clock notifications wake a bounded drain only when work is due. Stock refills in place without rebuilding meshes, colliders, navigation, or actors. Unloaded deposits continue as saved records. Loading a save rebuilds the derived index after clock hydration; normal clock advances do not scan every deposit. This load-time reconstruction is distinct from the bounded due-work drain.

New placements receive saved unique IDs; scene-tree copies receive distinct IDs through the editor save/apply hook. Keep authored IDs stable. Older saves did not capture deposit stock, so missing records seed once from authored defaults; legacy blank-ID scenes use a path-scoped runtime key until authored IDs are saved. This cannot recover depletion that old versions never saved.

## Adding another type

Create a reusable deposit scene using the existing mining/scavenging facade. Duplicate a catalog `.tres`, assign a unique type ID, human name/category, and that scene path; configure its stock and refill ranges. Save it in the catalog directory and reload the World Authoring plugin (or restart the editor) to discover the new entry. No UI list or runtime scheduler registration needs changing. A future scatter tool can call the same placement contract; no generator is required or implemented.

## Focused verification

Run from the project root, serially:

- `godot --headless --path . --script res://tests/validation/validate_zone_authoring.gd`
- `godot --headless --path . --script res://tests/validation/validate_resource_deposit_definitions.gd`
- `godot --headless --path . --script res://tests/validation/validate_resource_deposits.gd`

The authoring check covers all catalog scenes, transformed-zone placement, independent identities, duplicate repair, Undo/Redo, and scene round trips. The runtime check covers saved stock/deadlines, clock-load ordering, projection destruction/rebinding, real timed mining/scavenging transactions, denial/full-inventory behavior, and bounded simultaneous refills. It measures the resource drain, not overall gameplay FPS.

Also exercise the real editor: select a zone, search/filter, place twice, rotate/cancel, select an existing different type, edit a copied type's week control, Undo, and verify the saved setting's runtime minute range. Inspect thumbnails and control clipping in the actual dock; headless checks do not prove appearance.
