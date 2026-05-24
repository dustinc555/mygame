# Create Town Scene

Use this for towns in the large seamless world.

1. Create a new inherited/instanced scene from `res://scenes/world_sim/settlement_town.tscn`.

2. Save it under a town path, such as:

```text
res://scenes/world/towns/farmer_crossing.tscn
```

3. Assign the town's `SettlementDefinition` on the `SettlementTown` root.

4. Keep town content under the standard child roots:

```text
Bars
Fields
Shops
Mines
Housing
Residents
Storage
ActivityPoints
Territory
RoadSpawn
DefenseSpawn
```

5. Add bars, fields, residents, storage, guard posts, and furniture inside this town scene, not in the giant open-world scene.

6. Open this town scene directly whenever you need to customize it. This is the normal way to edit one city without loading or filtering the whole world tree.

7. Instance or stream this town scene from the persistent world scene.

Done check: opening the town scene should show the town root and its children directly, including paths like `Bars/FarmerBar`, without needing to filter through unrelated world content.
