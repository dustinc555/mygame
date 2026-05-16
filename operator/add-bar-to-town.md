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
```

7. Done for the default bar: it already includes a building, barkeeper, waiter, guard, shop stock, jobs, service point, guard post, furniture, and beds.

8. To use a different visual building, select `Settlements/FarmerCrossing/Bars/FarmerBar/BuildingSlot/CurrentBuilding`.

9. Replace that child with another building scene, or delete it and instantiate a different child under `BuildingSlot` named `CurrentBuilding`.

10. If the replacement building should contribute town population capacity, set its `population_capacity` and a stable `population_capacity_id`.

Do not manually add or configure `BarServiceArea`; it is an internal child of `SettlementBar` and is wired by the bar asset.

Leave beds under `FarmerBar/Furniture/Beds` if you want them upstairs. The bar registers that root as upper-floor building content so beds hide when the active actor is on the ground floor.

Done: `SettlementBar` is the reusable operator-facing asset; its internal service area handles waiter ordering, shop inventory, bed rental, and bar jobs.
