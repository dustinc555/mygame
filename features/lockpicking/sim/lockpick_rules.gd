extends RefCounted

## Inventory-only tools. Wear belongs to the exact stack, never its shared item.
const WEAR_KEY := "lockpick_wear"

static func find_pick(inventory: InventoryData, stack_id := ""):
	if inventory == null:
		return null
	var best = null
	for entry in inventory.entries:
		if entry.definition == null or not entry.definition.has_tool_tag("lockpick"):
			continue
		if not stack_id.is_empty() and entry.stack_id != stack_id:
			continue
		if remaining_condition(entry) <= 0.0:
			continue
		if best == null or remaining_condition(entry) > remaining_condition(best):
			best = entry
	return best

static func remaining_condition(entry) -> float:
	if entry == null or entry.definition == null or not entry.definition.has_tool_tag("lockpick"):
		return 0.0
	return maxf(0.0, float(entry.definition.lockpick_durability) - float(entry.metadata.get(WEAR_KEY, 0.0)))

static func condition_ratio(entry) -> float:
	return remaining_condition(entry) / maxf(1.0, float(entry.definition.lockpick_durability))

static func condition_label(entry) -> String:
	return "Condition: %d%%" % ceili(condition_ratio(entry) * 100.0)

static func apply_wear(inventory: InventoryData, stack_id: String, amount: float) -> Dictionary:
	var entry = find_pick(inventory, stack_id)
	if entry == null or stack_id.is_empty() or amount < 0.0 or not is_finite(amount):
		return {"accepted": false, "broke": false}
	var metadata: Dictionary = inventory.get_entry_metadata(entry)
	metadata[WEAR_KEY] = float(metadata.get(WEAR_KEY, 0.0)) + amount
	var broke := float(metadata[WEAR_KEY]) >= float(entry.definition.lockpick_durability)
	if broke:
		inventory.remove_entry(entry)
	else:
		inventory.set_entry_metadata(entry, metadata)
	return {"accepted": true, "broke": broke}
