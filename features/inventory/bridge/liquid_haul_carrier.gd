extends RefCounted

## Inventory adapter used by generic hauling endpoints for loose liquids.
## The haul provider knows only resource IDs and quantities; carrier details stay here.

const DEFAULT_CAPACITY := 10.0
const WATERING_CAN_CAPACITY := 16.0
const LIQUIDS_META := "carried_liquids"
const LEGACY_WATER_META := "farm_water"


## farm_water is authoritative when present; old generic-only stacks migrate
## on their next write. Never add the mirror to the authoritative quantity.
static func water_from_metadata(metadata: Dictionary) -> float:
	return maxf(0.0, float(metadata.get(LEGACY_WATER_META, (metadata.get(LIQUIDS_META, {}) as Dictionary).get("water", 0.0))))


static func metadata_with_water(metadata: Dictionary, liters: float) -> Dictionary:
	var result := metadata.duplicate(true)
	var water := maxf(0.0, liters)
	result[LEGACY_WATER_META] = water
	var liquids: Dictionary = (result.get(LIQUIDS_META, {}) as Dictionary).duplicate(true)
	if water > 0.0:
		liquids["water"] = water
	else:
		liquids.erase("water")
	result[LIQUIDS_META] = liquids
	return result


static func amount(actor: Node, resource_id: String) -> float:
	var carrier := _capture(actor)
	return _amount_in_carrier(carrier, resource_id)


static func free_capacity(actor: Node, resource_id: String) -> float:
	var carrier := _capture(actor)
	if carrier.is_empty():
		return 0.0
	var available := maxf(0.0, float(carrier.get("capacity", 0.0)) - _total_liquid(carrier))
	var inventory = carrier.get("inventory")
	if inventory != null and bool(inventory.get("use_weight")):
		available = minf(available, maxf(0.0,
				float(inventory.get("max_weight")) - float(inventory.call("get_total_weight"))))
	return available if not resource_id.strip_edges().is_empty() else 0.0


static func set_amount(actor: Node, resource_id: String, value: float, emit_changed := true) -> bool:
	var carrier := _capture(actor)
	if carrier.is_empty() or resource_id.strip_edges().is_empty():
		return false
	var entry = carrier.get("entry")
	var inventory = carrier.get("inventory")
	if entry == null or inventory == null or not inventory.entries.has(entry):
		return false
	var metadata: Dictionary = entry.metadata.duplicate(true)
	var liquids: Dictionary = (metadata.get(LIQUIDS_META, {}) as Dictionary).duplicate(true)
	var clamped := clampf(value, 0.0, float(carrier.get("capacity", 0.0)))
	if clamped <= 0.001:
		liquids.erase(resource_id)
	else:
		liquids[resource_id] = clamped
	metadata[LIQUIDS_META] = liquids
	if resource_id == "water":
		metadata = metadata_with_water(metadata, clamped)
	return inventory.set_entry_metadata(entry, metadata, emit_changed)


static func _capture(actor: Node) -> Dictionary:
	var inventory = _inventory(actor)
	if inventory == null:
		return {}
	for entry in inventory.entries:
		if entry == null or entry.definition == null:
			continue
		if entry.definition.has_tool_tag("tool.liquid_container") \
				or entry.definition.has_tool_tag("tool.water_container"):
			var capacity := WATERING_CAN_CAPACITY \
					if str(entry.definition.item_id) == "tool.watering_can" else DEFAULT_CAPACITY
			return {"entry": entry, "inventory": inventory, "capacity": capacity}
	return {}


static func _amount_in_carrier(carrier: Dictionary, resource_id: String) -> float:
	var entry = carrier.get("entry")
	if entry == null:
		return 0.0
	var liquids := entry.metadata.get(LIQUIDS_META, {}) as Dictionary
	if resource_id == "water":
		return water_from_metadata(entry.metadata)
	if liquids.has(resource_id):
		return maxf(0.0, float(liquids.get(resource_id, 0.0)))
	return maxf(0.0, float(entry.metadata.get(LEGACY_WATER_META, 0.0))) if resource_id == "water" else 0.0


static func _total_liquid(carrier: Dictionary) -> float:
	var entry = carrier.get("entry")
	if entry == null:
		return 0.0
	var liquids := entry.metadata.get(LIQUIDS_META, {}) as Dictionary
	var total := water_from_metadata(entry.metadata)
	for key in liquids:
		if str(key) != "water":
			total += maxf(0.0, float(liquids[key]))
	return total


static func _inventory(actor: Node):
	if actor == null:
		return null
	var value = actor.call("get_inventory") if actor.has_method("get_inventory") else actor.get("inventory")
	if value != null and value.has_method("get_inventory_for_display"):
		var carried = value.get("inventory")
		if carried == null and value.has_method("initialize_from_actor"):
			value.call("initialize_from_actor")
			carried = value.get("inventory")
		return carried
	return value
