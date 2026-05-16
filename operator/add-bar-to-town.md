# Add Bar To Town

Use this to add a reusable drag-and-play bar facility to Farmer Crossing or another `SettlementTown`.

1. Select `Settlements/FarmerCrossing/Bars`.

2. Right-click `Bars`.

3. Click `Instantiate Child Scene...`.

4. Choose `res://scenes/world_sim/settlement_bar.tscn`.

5. Rename it `FarmerBar`.

6. Set these inspector fields on `FarmerBar`:

```text
facility_id = farmer_crossing.bar
display_name = Farmer Crossing Bar
owner_faction_id = Farmers
staff_stable_id_prefix = npc.farmer_crossing.bar
staff_squad_name = FarmerCrossing
waiter_count = 1
waiter_point_count = 1
guard_count = 1
guard_post_count = 1
```

7. Done for the default bar: it already includes a building, barkeeper, waiter, guard, shop stock, jobs, service points, guard posts, furniture, and beds.

8. To add more table staff, increase `waiter_count`. The bar creates `Staff/Waiter*` and matching server job slots.

9. To add more waiter standing spots, increase `waiter_point_count`. The bar creates `ServicePoints/WaiterPoint*`.

10. To add more guards, increase `guard_count`. The bar creates `Staff/Guard*` and matching guard job slots. Set `guard_count = 0` for no generated guards.

11. To add more guard standing spots, increase `guard_post_count`. The bar creates `GuardPosts/GuardPost*`.

12. Move `ServicePoints/WaiterPoint*` to control where waiters wait between table service. Do not use `BarkeeperCounterPoint` for waiters; it is only for barkeeper/counter service until it is replaced by a shop counter.

13. Move `GuardPosts/GuardPost*` to control where guards stand. Extra guard posts let guards shuffle positions over time.

14. The service point and guard post pyramids are editor-only markers. Disable a marker with `editor_show_debug_marker` if it gets in the way.

Generated default names are `WaiterPoint`, `WaiterPoint2`, `GuardPost`, and `GuardPost2`. Lowering a point/post count removes generated default-name extras; custom-renamed points and posts are left alone.

15. To use a different visual building, select `Settlements/FarmerCrossing/Bars/FarmerBar/BuildingSlot/CurrentBuilding`.

16. Replace that child with another building scene, or delete it and instantiate a different child under `BuildingSlot` named `CurrentBuilding`.

17. If the replacement building should contribute town population capacity, set its `population_capacity` and a stable `population_capacity_id`.

Do not manually add or configure `BarServiceArea`; it is an internal child of `SettlementBar` and is wired by the bar asset.

Leave beds under `FarmerBar/Furniture/Beds` if you want them upstairs. The bar registers that root as upper-floor building content so beds hide when the active actor is on the ground floor.

Done: `SettlementBar` is the reusable operator-facing asset; its internal service area handles waiter ordering, shop inventory, bed rental, and bar jobs.
