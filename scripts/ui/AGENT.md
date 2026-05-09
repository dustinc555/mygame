# AGENT.md

## Inventory And Equipment UI
- UI controls should emit user intent; inventory/equipment ownership changes belong in `PartyInventoryController` or reusable owner APIs.
- `InventoryWindow` should not directly mutate equipment or transfer ownership except through signals handled by the controller.
- `EquipmentSlotControl` is a reusable slot view. Keep slot compatibility checks data-driven through the inventory owner/item APIs.
- Drag/drop behavior should work for character inventories, containers, equipment slots, and world drops without scene-specific code.
- Character inventory windows should stay compact by using an appropriate row count; do not add arbitrary slot scrolling to hide unused rows.
- Containers may keep their natural grid height unless there is a reusable reason to cap them.
- Inventory interactions should keep at most two windows open: the focused character inventory on the left and one external container/shop/trade inventory on the right.
- Opening a standalone character inventory should close any external context inventory.

## Drop And Pickup
- Dropping inventory/equipment to the world should spawn reusable `WorldItem` scenes through controller logic.
- Shift-click pickup and context-menu pickup should use reusable world-item APIs, not test-level code.
