# Add Road Path

Use this to add an invisible road route for NPC squad world actions between two settlements.

1. Select the scene root or the existing world-data root that should contain roads.

2. Click `Add Child Node`.

3. Add a `Node3D` named `Roads` if the scene does not already have one.

4. Select `Roads`.

5. Click `Add Child Node`.

6. Search `RoadPath` and add it.

7. Rename it for the route, such as `FarmerCrossingToRaiderCamp`.

8. Set these inspector fields:

```text
road_id = farmer_crossing_raider_camp
display_name = Farmer Crossing / Raider Camp Road
source_settlement_id = farmer_crossing
target_settlement_id = raider_camp
bidirectional = true
```

9. Edit `path_points` so the points run from the source settlement road spawn toward the target settlement road spawn.

10. Leave `editor_show_debug_path` enabled so the route is visible in the editor.

11. Keep visible road meshes, decals, or terrain paint separate from `RoadPath`; the `RoadPath` node is gameplay data only.

Done: the editor shows the route helper, runtime hides it by default, and the `Show Roads` debug action can toggle road visibility during testing.
