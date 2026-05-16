# Add Population Capacity

Use this to define how many residents a town can support from authored buildings or outdoor shelter.

1. For a reusable housing building, open the building scene such as `res://scenes/world/buildings/tiny_house.tscn`.

2. Select the root `WorldBuilding` node.

3. Set `population_capacity` to the whole-building resident capacity.

```text
Tiny House = 3
Two-Story House = 6
```

4. Do not add capacity markers for beds inside that building. The building capacity already represents the whole structure.

5. For an outdoor bedroll, tent, slum camp, or similar non-building shelter, select the town root or a clear child root under the town.

6. Click `Add Child Node`.

7. Search `PopulationCapacitySource` and add it.

8. Rename it to a stable source name, such as `SlumBedrollA`.

9. Set these inspector fields:

```text
capacity_id = farmer_crossing.slum_bedroll_a
display_name = Slum Bedroll A
source_type = bedroll
population_capacity = 1
enabled = true
```

Done: the settlement controller derives `max_occupancy` from the town's authored buildings and capacity sources, then applies the normal occupancy state multiplier.
