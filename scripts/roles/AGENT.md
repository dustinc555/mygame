# AGENT.md

## Merchant Roles
- `MerchantRole` owns tradable shop stock through its dedicated shop inventory.
- Do not seed shop goods into a humanoid's personal inventory; personal inventory and `starting_equipment` are for what the NPC carries or wears.
- Town shops, caravans, and temporary traders should all use the same merchant role APIs for prices, stock, and trade display.
