# Create Town Scene

Use this for towns in the large seamless world.

1. Create a new inherited/instanced scene from `res://src/settlements/bridge/settlement_town.tscn`.

2. Save it under a town path, such as:

```text
res://scenes/zones/demo_zone/towns/surf_city.tscn
```

3. Assign the town's `SettlementDefinition` on the `SettlementTown` root.

4. Leave `actor_realization_policy` set to `full_town` unless this town is being prepared for large-city streaming with ledger-simulated unloaded citizens.

5. Keep town content under the standard child roots:

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

6. Add bars, fields, residents, storage, guard posts, and furniture inside this town scene, not in the giant open-world scene.

7. Open this town scene directly whenever you need to customize it. This is the normal way to edit one city without loading or filtering the whole world tree.

8. Instance or stream this town scene from the persistent world scene.

Done check: opening the town scene should show the town root and its children directly, including paths like `Bars/FarmerBar`, without needing to filter through unrelated world content.
