extends SceneTree

const LEDGER := preload("res://features/inventory/resources/items/town_ledger.tres")
const MAP := preload("res://features/inventory/resources/items/town_map.tres")


func _init() -> void:
	_assert(LEDGER.read_behavior == ItemDefinition.ReadBehavior.TOWN_LEDGER, "Town ledger must expose typed Read behavior")
	_assert(MAP.read_behavior == ItemDefinition.ReadBehavior.DUD, "Map Read must be a harmless dud")
	var world_source := FileAccess.get_file_as_string("res://features/world/bridge/world_interaction_controller.gd")
	var inventory_source := FileAccess.get_file_as_string("res://features/ui/projection/inventory_window.gd")
	var service_source := FileAccess.get_file_as_string("res://features/settlements/bridge/item_read_controller.gd")
	_assert(world_source.contains("ACTION_READ_ITEM") and world_source.contains("get_world_read_action"), "World context menu must compose Read with Pick Up/Steal")
	_assert(inventory_source.contains("ACTION_READ") and inventory_source.contains("\"read\""), "Inventory menu must expose Read")
	_assert(service_source.contains("Read (Private)") and service_source.contains("request_interaction"), "Unauthorized world Read must be visibly private and ownership-authorized")
	_assert(service_source.contains("ItemDefinition.ReadBehavior.TOWN_LEDGER"), "Read dispatch must use the typed behavior enum")
	print("ITEM_READ_ACTIONS_OK")
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
