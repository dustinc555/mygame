# Add Road Network

Use this to add invisible road route data for NPC squad world actions between settlements.

1. Select the scene root or the existing world-data root that should contain roads.

2. Click `Add Child Node`.

3. Add a `Node3D` named `Roads` if the scene does not already have one.

4. Select `Roads`.

5. Click `Add Child Node`.

6. Search `RoadNetwork` and add it.

7. Rename it for the route or region, such as `FarmerCrossingToRaiderCamp`.

8. Set these inspector fields:

```text
network_id = farmer_crossing_raider_camp
display_name = Farmer Crossing / Raider Camp Road
```

9. Select the `RoadNetwork` and use the inspector's `Road Authoring` panel.

10. Click `Create First Waypoint`.

11. Move the new waypoint in the 3D viewport to the first road entrance.

12. Set `settlement_id` on endpoint waypoints that represent settlement road entrances, such as `farmer_crossing` or `raider_camp`.

13. Select a `RoadWaypoint` and click `Create Additional Waypoint From This` to add the next attached waypoint.

14. Drag the new selected waypoint into place, then repeat `Create Additional Waypoint From This` to continue the road. Waypoints are visible clickable meshes, so click the orb in the 3D view to select the real `RoadWaypoint`.

15. To connect two existing waypoints, select the source waypoint, click `Set As Connection Source`, select the target waypoint, then click `Connect From Source`.

16. Click `Ensure All Waypoint IDs` or `Ensure Network IDs` whenever needed. This fills missing waypoint IDs and fixes duplicates with IDs like `farmer_crossing_raider_camp.wp_0001`.

17. To remove a waypoint, select it and click `Delete This Waypoint`. This removes the waypoint and clears other waypoint connections that pointed at it.

18. Author each connection once. `RoadController` compiles connections bidirectionally at runtime.

19. Leave `editor_show_debug_path` and `editor_show_debug_marker` enabled so route lines and waypoint orbs are visible in the editor.

20. Keep visible road meshes, decals, or terrain paint separate from `RoadNetwork` and `RoadWaypoint`; these nodes are gameplay data only.

Done: the editor shows route helpers, runtime hides them by default, and the `Show Roads` debug action can toggle road visibility during testing.
