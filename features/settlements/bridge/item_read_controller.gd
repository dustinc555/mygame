extends Node

class_name ItemReadBridge

## Routes readable item interactions to their presentation bridge.

signal read_open_requested(stack_id: String, definition: ItemDefinition, payload: Dictionary)
signal read_notice_requested(message: String)

const SERVICE_ID := &"item_read"

var _ledger: Node
var _ownership: OwnershipController


func initialize(context: BootstrapContext) -> void:
	_ledger = context.require(&"town_ledger")
	_ownership = context.require(OwnershipController.SERVICE_ID) as OwnershipController


func can_read(definition: ItemDefinition) -> bool:
	return definition != null and definition.read_behavior != ItemDefinition.ReadBehavior.NONE


func get_world_read_action(actor: HumanoidCharacter, item: WorldItem) -> Dictionary:
	if item == null or not can_read(item.item_definition):
		return {}
	var action := {"label": "Read", "illegal": false}
	if actor != null and _ownership.get_take_item_color(actor, item).a > 0.0:
		action["label"] = "Read (Private)"
		action["color"] = OwnershipController.STEAL_ACTION_COLOR
		action["illegal"] = true
	return action


func read_world_item(actor: HumanoidCharacter, item: WorldItem) -> bool:
	if actor == null or item == null or not can_read(item.item_definition):
		return false
	if _ownership.get_take_item_color(actor, item).a > 0.0 and not _ownership.request_interaction(actor, item, "Read"):
		return false
	return _dispatch(item.stack_id, item.item_definition)


func read_inventory_item(_actor, entry) -> bool:
	if entry == null or not can_read(entry.definition):
		return false
	return _dispatch(str(entry.stack_id), entry.definition)


func _dispatch(stack_id: String, definition: ItemDefinition) -> bool:
	if definition.read_behavior == ItemDefinition.ReadBehavior.TOWN_LEDGER:
		var report: Dictionary = _ledger.get_report(stack_id)
		if report.is_empty():
			read_notice_requested.emit("The ledger has not yet been bound to a town.")
			return false
		read_open_requested.emit(stack_id, definition, report)
		return true
	read_notice_requested.emit("Nothing useful is written here.")
	return true
