extends "res://scripts/actors/capabilities/actor_capability.gd"

class_name EquipmentCapability

var equipped_items: Dictionary = {}

var _initialized := false
var _equipment_update_batch_depth := 0
var _equipment_change_pending := false
var _equipment_changed_slots: Dictionary = {}
var _gecs_world_controller: Node
var _actor_property_cache: Dictionary = {}


func _init() -> void:
	super._init(&"equipment")


func setup(target_actor: Node) -> void:
	super.setup(target_actor)
	_actor_property_cache.clear()


func ready() -> void:
	initialize_from_actor()


func teardown() -> void:
	equipped_items.clear()
	_equipment_changed_slots.clear()
	_equipment_update_batch_depth = 0
	_equipment_change_pending = false
	_gecs_world_controller = null
	_actor_property_cache.clear()
	_initialized = false
	super.teardown()


func initialize_from_actor() -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var existing = actor.get("equipped_items") if _actor_has_property("equipped_items") else {}
	if existing is Dictionary:
		equipped_items = existing
	else:
		equipped_items = {}
	_write_actor_equipment()
	if _initialized:
		return true
	_initialized = true
	seed_starting_equipment_from_actor()
	return true


func get_equipped_items() -> Dictionary:
	_ensure_equipment_ready()
	return equipped_items


func get_equipped_item(slot_name: String) -> ItemDefinition:
	if not _ensure_equipment_ready():
		return null
	return equipped_items.get(slot_name) as ItemDefinition


func can_equip_item_to_slot(definition: ItemDefinition, slot_name: String) -> bool:
	if definition == null or not definition.is_equippable():
		return false
	var actor_slot_names := _get_actor_equipment_slot_names()
	if not actor_slot_names.is_empty() and not actor_slot_names.has(slot_name):
		return false
	return definition.can_equip_to_slot(slot_name)


func equip_item_to_slot(definition: ItemDefinition, slot_name: String) -> ItemDefinition:
	if not can_equip_item_to_slot(definition, slot_name):
		return null
	var previous := get_equipped_item(slot_name)
	equipped_items[slot_name] = definition
	_write_actor_equipment()
	_mark_equipment_changed(slot_name)
	return previous


func unequip_item_from_slot(slot_name: String) -> ItemDefinition:
	if not _ensure_equipment_ready():
		return null
	var previous := get_equipped_item(slot_name)
	if previous == null:
		return null
	equipped_items.erase(slot_name)
	_write_actor_equipment()
	_mark_equipment_changed(slot_name)
	return previous


func begin_equipment_update_batch() -> void:
	_equipment_update_batch_depth += 1


func end_equipment_update_batch() -> void:
	if _equipment_update_batch_depth <= 0:
		return
	_equipment_update_batch_depth -= 1
	if _equipment_update_batch_depth > 0 or not _equipment_change_pending:
		return
	_equipment_change_pending = false
	_apply_equipment_changed()


func has_equipment() -> bool:
	return _ensure_equipment_ready() and not equipped_items.is_empty()


func get_equipped_weight() -> float:
	if not _ensure_equipment_ready():
		return 0.0
	var total := 0.0
	for item in equipped_items.values():
		if item is ItemDefinition:
			total += (item as ItemDefinition).unit_weight
	return total


func get_stat_modifiers() -> Array:
	if not _ensure_equipment_ready():
		return []
	var modifiers: Array = []
	for item in equipped_items.values():
		if not (item is ItemDefinition):
			continue
		for modifier in (item as ItemDefinition).stat_modifiers:
			if modifier == null:
				continue
			modifiers.append(modifier.to_modifier_dictionary())
	return modifiers


func has_item_stat_modifier(item: ItemDefinition, stat_name: String) -> bool:
	if item == null:
		return false
	for modifier in item.stat_modifiers:
		if modifier != null and modifier.stat_name == stat_name:
			return true
	return false


func get_item_stat_value(item: ItemDefinition, stat_name: String, base_value: float) -> float:
	if item == null:
		return base_value
	var value := base_value
	for modifier in item.stat_modifiers:
		if modifier == null or modifier.stat_name != stat_name:
			continue
		value = (value + modifier.add) * modifier.mul
	return value


func seed_starting_equipment_from_actor() -> void:
	if not _ensure_equipment_ready():
		return
	var starting_equipment = actor.get("starting_equipment") if _actor_has_property("starting_equipment") else []
	if not (starting_equipment is Array):
		return
	var changed := false
	for stock in starting_equipment:
		var item_definition := _get_stock_item_definition(stock)
		if item_definition == null:
			continue
		if not item_definition.is_equippable():
			_add_item_to_actor_inventory(item_definition)
			continue
		if get_equipped_item(item_definition.equip_slot) == null and can_equip_item_to_slot(item_definition, item_definition.equip_slot):
			equipped_items[item_definition.equip_slot] = item_definition
			changed = true
	if changed:
		_write_actor_equipment()


func sync_to_gecs() -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var bridge := _get_gecs_world_controller()
	if bridge != null and bridge.has_method("sync_actor_inventory"):
		bridge.call("sync_actor_inventory", actor)


func _ensure_equipment_ready() -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if equipped_items.is_empty() and not _initialized:
		initialize_from_actor()
	return true


func _mark_equipment_changed(slot_name := "") -> void:
	if not slot_name.is_empty():
		_equipment_changed_slots[slot_name] = true
	if _equipment_update_batch_depth > 0:
		_equipment_change_pending = true
		return
	_apply_equipment_changed()


func _apply_equipment_changed() -> void:
	_equipment_change_pending = false
	var changed_slots := _equipment_changed_slots.keys()
	_equipment_changed_slots.clear()
	if actor != null and is_instance_valid(actor) and actor.has_method("_notify_equipment_changed"):
		actor.call("_notify_equipment_changed", changed_slots)
		return
	sync_to_gecs()


func _write_actor_equipment() -> void:
	if actor != null and is_instance_valid(actor) and _actor_has_property("equipped_items"):
		actor.set("equipped_items", equipped_items)


func _get_stock_item_definition(stock) -> ItemDefinition:
	if stock is ItemDefinition:
		return stock as ItemDefinition
	if stock is Object:
		return stock.get("item_definition") as ItemDefinition
	return null


func _add_item_to_actor_inventory(item_definition: ItemDefinition) -> void:
	if item_definition == null or actor == null or not is_instance_valid(actor):
		return
	var actor_inventory = actor.get("inventory") if _actor_has_property("inventory") else null
	if actor_inventory == null and actor.has_method("_setup_inventory_capability"):
		actor.call("_setup_inventory_capability")
		actor_inventory = actor.get("inventory") if _actor_has_property("inventory") else null
	if actor_inventory != null and actor_inventory.has_method("add_item_count"):
		actor_inventory.call("add_item_count", item_definition, 1)


func _get_actor_equipment_slot_names() -> Array[String]:
	if actor != null and is_instance_valid(actor) and actor.has_method("get_equipment_slot_names"):
		return actor.call("get_equipment_slot_names") as Array[String]
	return []


func _get_gecs_world_controller() -> Node:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return null
	if _gecs_world_controller != null and is_instance_valid(_gecs_world_controller):
		return _gecs_world_controller
	_gecs_world_controller = actor.get_tree().get_first_node_in_group("gecs_world_controller")
	return _gecs_world_controller


func _actor_has_property(property_name: String) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if _actor_property_cache.has(property_name):
		return bool(_actor_property_cache[property_name])
	for property in actor.get_property_list():
		if str(property.get("name", "")) == property_name:
			_actor_property_cache[property_name] = true
			return true
	_actor_property_cache[property_name] = false
	return false
