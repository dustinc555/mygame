extends RefCounted

## Inventory feature module.
##
## Bridge: the party inventory controller that maps shared party item state onto
## the HUD and the live carrying actors.
##
## Installed by GameBootstrap into BridgeRoot.

const PARTY_INVENTORY := preload("res://features/inventory/bridge/party_inventory_controller.gd")

const CORE := []
const PROJECTION := []
const SIM := []
const BRIDGE := [
	{"name": "PartyInventoryController", "script": PARTY_INVENTORY, "service": PARTY_INVENTORY.SERVICE_ID},
]
