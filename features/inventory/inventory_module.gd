extends RefCounted

## Inventory feature module.
##
## Bridge: the party inventory controller that maps shared party item state onto
## the HUD and the live carrying actors.
##
## Installed by GameBootstrap into BridgeRoot.

const PARTY_INVENTORY := preload("res://features/inventory/bridge/party_inventory_controller.gd")
const BULK_STORAGE_HAUL := preload("res://features/inventory/bridge/bulk_storage_haul_provider.gd")
const WORLD_ITEM_PROJECTION := preload("res://features/inventory/bridge/world_item_projection_bridge.gd")
const INVENTORY_STOCK := preload("res://features/inventory/sim/inventory_stock_controller.gd")
const ITEM_LIFECYCLE := preload("res://features/inventory/sim/item_lifecycle_controller.gd")

const CORE := []
const PROJECTION := []
const SIM := [
	{"name": "InventoryStockController", "script": INVENTORY_STOCK, "service": INVENTORY_STOCK.SERVICE_ID},
	{"name": "ItemLifecycleController", "script": ITEM_LIFECYCLE, "service": ITEM_LIFECYCLE.SERVICE_ID},
]
const BRIDGE := [
	{"name": "WorldItemProjectionBridge", "script": WORLD_ITEM_PROJECTION, "service": WORLD_ITEM_PROJECTION.SERVICE_ID},
	{"name": "PartyInventoryController", "script": PARTY_INVENTORY, "service": PARTY_INVENTORY.SERVICE_ID},
	{"name": "BulkStorageHaulProvider", "script": BULK_STORAGE_HAUL, "service": BULK_STORAGE_HAUL.SERVICE_ID},
]
