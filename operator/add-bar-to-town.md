# Add Bar To Town

Use this to add a reusable drag-and-play bar facility to a `SettlementTown`.

1. Select the town's `Bars` node, such as `Settlements/FarmerCrossing/Bars`.

2. Right-click `Bars`.

3. Click `Instantiate Child Scene...`.

4. Choose `res://scenes/world_sim/settlement_bar.tscn`.

5. Rename the instance, such as `FarmerBar`.

6. Move the bar to the desired town position.

7. For a normal town bar, you do not need to set ids or faction ownership manually. The bar infers them from the parent settlement and its node name.

For example, a bar named `FarmerBar` under Farmer Crossing infers:

```text
facility_id = farmer_crossing.farmer_bar
owner_faction_id = Farmers
staff_stable_id_prefix = npc.farmer_crossing.farmer_bar
staff_squad_name = FarmerCrossing
```

Override those fields only if this bar needs a special id, owner, or staff namespace.

8. Set staff counts. The bar creates missing staff automatically:

```text
waiter_count = 1
guard_count = 1
has_barber = false or true
visitor_capacity = 4
```

9. Optional: assign prebuilt NPCs instead of generating every role:

```text
barkeeper_actor_path = optional existing NPC
assigned_waiter_paths = optional existing waiter NPCs
assigned_guard_paths = optional existing guard NPCs
barber_actor_path = optional existing barber NPC
```

Assigned NPCs stay where they are in the scene tree. They count toward the role total, and only the missing staff are generated under `Staff`.

10. Done for the default bar. It auto-creates:

```text
Staff/Barkeeper
Staff/Waiter* as needed
Staff/Guard* as needed
Staff/Barber when has_barber is enabled
ServicePoints/BarkeeperCounterPoint
ServicePoints/WaiterPoint* from waiter_count
GuardPosts/GuardPost* from guard_count
ActivityPoints/VisitorPoint* from visitor_capacity
Furniture, shop stock, jobs, and BarServiceArea wiring
```

11. Move service points, guard posts, visitor points, furniture, or the building mesh if you want a custom layout.

Barbers, mercenaries, doctors, traders, and other non-working bar occupants should use the normal bar space and existing chairs instead of getting bespoke service points. Guards need posts and waiters need service points because those are active jobs; idle occupants just exist in the bar.

Furniture is intentionally one bucket. Copy/paste tables, chairs, and beds directly under `Furniture`; do not create or maintain `Furniture/Tables`, `Furniture/Stools`, or `Furniture/Beds` folders for normal bar authoring.

Seats work when the copied prop uses `SittableSeat`. Beds work when the copied prop uses `SleepableBed`. The bar service area scans `Furniture` recursively so older nested furniture remains usable, but new bars should stay flat.

Generated staff display their role in the crowd, such as `Name (barkeeper)`, `Name (waiter)`, `Name (guard)`, and `Name (barber)`.

To change global default positions for future and uncustomized bars, edit `res://scenes/world_sim/settlement_bar.tscn` and drag nodes like `GuardPosts/GuardPost` or `ServicePoints/WaiterPoint` there.

12. If you need extra standing points beyond the staff count, use the advanced point fields:

```text
waiter_point_count = extra/minimum waiter points
guard_post_count = extra/minimum guard posts
guard_job_slot_count = extra/minimum player guard job slots
```

13. To use a different visual building, replace the child under `BuildingSlot` with another building scene.

14. If the replacement building should contribute town population capacity, set its `population_capacity` and a stable `population_capacity_id`.

Do not manually add or configure `BarServiceArea`; it is an internal child of `SettlementBar` and is wired by the bar asset.

Generated staff use the settlement/faction population appearance and name setup when available. Hand-authored assigned NPCs keep their authored identity and appearance.

Generated service points, guard posts, and visitor points carry migration metadata. If future default bar layouts change, unchanged generated points can migrate to new defaults, while moved/customized points are preserved.

Barkeeper stock defaults from the parent town's current supply ratio when the bar is under a `SettlementTown`. A standalone bar uses `standalone_stock_ratio`. This only seeds merchant inventory for now; future economy work should restock through settlement storage and supply systems.
