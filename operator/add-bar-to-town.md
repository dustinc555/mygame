# Add Bar To Town

Use this to add a reusable bar facility to Farmer Crossing or another `SettlementTown`.

1. Select `Settlements/FarmerCrossing/Bars`.

2. Click `Add Child Node`.

3. Search `SettlementBar` and add it.

4. Rename it `FarmerBar`.

5. Set these inspector fields:

```text
facility_id = farmer_crossing.bar
display_name = Farmer Crossing Bar
owner_faction_id = Farmers
staff_stable_id_prefix = npc.farmer_crossing.bar
staff_squad_name = FarmerCrossing
```

6. Select `Settlements/FarmerCrossing/Bars/FarmerBar/BuildingSlot`.

7. Right-click `BuildingSlot`.

8. Click `Instantiate Child Scene...`.

9. Choose `res://scenes/world/buildings/two_story_house.tscn`.

10. Rename the new building child to `CurrentBuilding`.

11. Leave the default beds under `FarmerBar/Furniture/Beds` if you want them upstairs. The bar registers that root as upper-floor building content so they hide when the active actor is on the ground floor.

Done: the building is the visual shell, and `SettlementBar` provides the bar function, staff, service points, jobs, and venue wiring.
