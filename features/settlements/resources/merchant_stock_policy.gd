extends RefCounted

## Cadence supply is deliberately separate from character ownership and trade.
## Future NPC businesses/caravans deliver real goods to this same inventory;
## they must replace the supply source, not create a second trading economy.
static func resolve(defaults: Dictionary, overrides: Dictionary) -> Dictionary:
	var result := defaults.duplicate(true)
	for path in overrides:
		result[path] = (overrides[path] as Dictionary).duplicate(true)
	return result


static func first_due_minute(now: int, days: int, hour: int) -> int:
	return (floori(float(now) / 1440.0) + maxi(1, days)) * 1440 + clampi(hour, 0, 23) * 60


static func advance_due_minute(due: int, now: int, days: int) -> int:
	var period := maxi(1, days) * 1440
	return due + (floori(float(maxi(0, now - due)) / period) + 1) * period


static func replenish(inventory: InventoryData, rules: Dictionary) -> bool:
	var changed := false
	for path in rules:
		var rule: Dictionary = rules[path]
		if not bool(rule.get("replenishes", false)) or int(rule.get("quantity", 0)) <= 0:
			continue
		var item := load(str(path)) as ItemDefinition
		# Currency is finite and only exchanged, never minted by goods restocks.
		if item == null or item.is_currency_item():
			continue
		var missing := maxi(0, int(rule.quantity) - inventory.count_item(item))
		if missing > 0 and inventory.add_item_count(item, missing):
			changed = true
	return changed
