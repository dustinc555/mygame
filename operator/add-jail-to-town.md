# Add Jail To Town

Use this to add a reusable settlement jail facility.

1. Select the town's `Facilities` node, such as `Settlements/FarmerCrossing/Facilities`.

2. Right-click `Facilities`.

3. Click `Instantiate Child Scene...`.

4. Choose `res://src/settlements/bridge/settlement_jail.tscn`.

5. Rename the instance, such as `FarmerJail`.

6. Move the jail to the desired town position.

7. For a normal town jail, keep inferred ids and ownership. The jail infers its facility id, owner faction, staff stable-id prefix, and squad from the parent settlement.

8. Set the jail counts:

```text
guard_count = number of jail guards
guard_post_count = optional extra guard posts
cell_count = number of cells
prisoners_per_cell = capacity per cell
cell_lock_difficulties = per-cell lock difficulty
locker_lock_difficulty = prisoner locker lock difficulty
```

9. Done for the default jail. It auto-creates:

```text
BuildingSlot/CurrentBuilding
EntryPoint
Staff/Warden
Staff/Guard* as needed
GuardPosts/GuardPost* as needed
Cells/Cell* as lightweight prisoner assignment hooks
Lockers/PrisonerLocker
```

`Cells/Cell*` are instances of `res://src/settlements/bridge/jail_cell.tscn`. Edit that source scene for shared cage visuals or collision.

`Lockers/PrisonerLocker` is an instance of `res://src/world/projection/containers/prisoner_locker_container.tscn`. Edit that source scene for shared locker visuals, inventory dimensions, or collision.

Jail guards and the warden are settlement authority roles. Only guard-role authority actors answer law combat/custody calls; the warden stays available for sentencing and jail administration. If they die, the settlement records the death and the role refills later only if the town has available population.

Witnessed crimes are handled by `LawOrderController`. Unconscious wanted actors are carried by a guard through `EntryPoint`, placed at the cell's interaction point, then admitted when a cell and locker are available; legal release returns non-stolen gear and forfeits stolen goods.

Done check: run `res://scenes/test_levels/jail_law_demo.tscn` or `godot --headless --path . --script res://tools/validation/validate_law_order_jail.gd`.
