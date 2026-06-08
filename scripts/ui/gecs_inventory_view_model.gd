extends RefCounted

class_name GecsInventoryViewModel

signal inventory_changed

const DEFAULT_SLOT_NAMES: Array[String] = ["head", "chest", "hands", "legs", "feet", "weapon", "offhand"]

var bridge: Node
var actor_id := ""
var container_id := ""
var display_name := "Inventory"
var name := "Inventory"
var player_party_member := false
var player_controllable := false
var inventory: InventoryData = InventoryData.new()

var _record: Dictionary = {}
var _equipment_by_slot: Dictionary = {}
var _stacks_by_id: Dictionary = {}
var _definition_cache_by_identifier: Dictionary = {}


func setup(target_bridge: Node, target_actor_id: String, target_container_id := "") -> void:
	bridge = target_bridge
	actor_id = target_actor_id.strip_edges()
	container_id = target_container_id.strip_edges()
	if container_id.is_empty() and bridge != null and bridge.has_method("get_actor_inventory_container_id"):
		container_id = str(bridge.call("get_actor_inventory_container_id", actor_id))
	if container_id.is_empty():
		container_id = "%s.inventory" % actor_id
	refresh()


func refresh() -> void:
	_record = _record_snapshot()
	display_name = str(_record.get("member_name", actor_id)).strip_edges()
	if display_name.is_empty():
		display_name = container_id
	name = display_name
	player_party_member = bool(_record.get("player_party_member", false))
	player_controllable = bool(_record.get("player_controllable", false))
	_rebuild_inventory_data()
	_rebuild_equipment_data()
	inventory_changed.emit()


func get_inventory_for_display() -> InventoryData:
	return inventory


func get_inventory_display_name() -> String:
	return display_name


func get_inventory_display_title() -> String:
	return "%s Inventory" % display_name


func get_inventory_cell_size() -> Vector2:
	return Vector2(30.0, 30.0)


func shows_inventory_weight() -> bool:
	return container_id != "world"


func shows_inventory_equipment() -> bool:
	return not actor_id.is_empty()


func get_equipment_slot_names() -> Array[String]:
	var slot_names: Array[String] = DEFAULT_SLOT_NAMES.duplicate()
	for slot_name_value in _equipment_by_slot.keys():
		var slot_name := str(slot_name_value)
		if not slot_names.has(slot_name):
			slot_names.append(slot_name)
	return slot_names


func get_equipment_slot_label(slot_name: String) -> String:
	match slot_name:
		"offhand":
			return "Off Hand"
		_:
			return slot_name.capitalize()


func get_equipped_item(slot_name: String):
	var item_path := str(_equipment_by_slot.get(slot_name, ""))
	return _definition_for_identifier(item_path)


func can_equip_item_to_slot(definition: ItemDefinition, slot_name: String) -> bool:
	if definition == null or slot_name.is_empty():
		return false
	if str(definition.equip_slot) == slot_name:
		return true
	var alternates = definition.alternate_equip_slots
	if alternates is Array or alternates is PackedStringArray:
		for alternate in alternates:
			if str(alternate) == slot_name:
				return true
	return false


func can_eat_inventory_entry(entry) -> bool:
	return entry != null and can_eat_item(entry.definition)


func can_eat_item(definition) -> bool:
	return definition != null and float(definition.get("nutrition_value")) > 0.0


func get_inventory_world_position() -> Vector3:
	var position = _record.get("last_world_position", _record.get("world_position", Vector3.ZERO))
	return position if position is Vector3 else Vector3.ZERO


func can_transfer_display_inventory_to(_target_owner) -> bool:
	return true


func can_receive_inventory_transfer_from(_source_owner) -> bool:
	return true


func get_stack_snapshot(stack_id: String) -> Dictionary:
	var snapshot = _stacks_by_id.get(stack_id, {})
	return snapshot.duplicate(true) if snapshot is Dictionary else {}


func get_equipment_stat_profile() -> Dictionary:
	if bridge != null and not actor_id.is_empty() and bridge.has_method("get_actor_stat_profile"):
		var profile = bridge.call("get_actor_stat_profile", actor_id, _record)
		if profile is Dictionary:
			return (profile as Dictionary).duplicate(true)
	var record_profile = _record.get("equipment_stat_profile", {})
	return (record_profile as Dictionary).duplicate(true) if record_profile is Dictionary else {}


func _record_snapshot() -> Dictionary:
	if bridge == null or actor_id.is_empty() or not bridge.has_method("get_population_record"):
		return {}
	var record = bridge.call("get_population_record", actor_id)
	return record.duplicate(true) if record is Dictionary else {}


func _rebuild_inventory_data() -> void:
	var container: Dictionary = bridge.call("get_inventory_container", container_id) if bridge != null and bridge.has_method("get_inventory_container") else {}
	inventory = InventoryData.new(
		int(container.get("columns", 10)),
		int(container.get("rows", 6)),
		float(container.get("max_weight", 60.0)),
		container_id != "world"
	)
	_stacks_by_id.clear()
	if bridge == null or not bridge.has_method("get_inventory_stacks"):
		return
	for stack in bridge.call("get_inventory_stacks", container_id):
		if not (stack is Dictionary):
			continue
		var stack_id := str((stack as Dictionary).get("stack_id", ""))
		var item_path := str((stack as Dictionary).get("item_definition_path", ""))
		var definition := _definition_for_identifier(item_path)
		if stack_id.is_empty() or definition == null:
			continue
		_stacks_by_id[stack_id] = (stack as Dictionary).duplicate(true)
		inventory.entries.append(InventoryData.InventoryEntry.new(
			definition,
			(stack as Dictionary).get("grid_position", Vector2i.ZERO),
			int((stack as Dictionary).get("count", 1)),
			((stack as Dictionary).get("contained_item_counts", {}) as Dictionary).duplicate(true),
			((stack as Dictionary).get("metadata", {}) as Dictionary).duplicate(true),
			stack_id
		))


func _rebuild_equipment_data() -> void:
	_equipment_by_slot.clear()
	if bridge == null or actor_id.is_empty() or not bridge.has_method("get_equipment_slots"):
		return
	for slot in bridge.call("get_equipment_slots", actor_id):
		if not (slot is Dictionary):
			continue
		var slot_name := str((slot as Dictionary).get("slot_name", "")).strip_edges()
		var item_path := str((slot as Dictionary).get("item_definition_path", "")).strip_edges()
		if not slot_name.is_empty() and not item_path.is_empty():
			_equipment_by_slot[slot_name] = item_path


func _definition_for_identifier(identifier: String) -> ItemDefinition:
	var key := identifier.strip_edges()
	if key.is_empty():
		return null
	if _definition_cache_by_identifier.has(key):
		return _definition_cache_by_identifier[key] as ItemDefinition
	var definition := ItemDefinitionIndex.load_definition(key)
	_definition_cache_by_identifier[key] = definition
	return definition
