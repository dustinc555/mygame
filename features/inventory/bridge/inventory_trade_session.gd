extends RefCounted

## Ephemeral offers only. Real stock and purses stay untouched until settlement.
## Endpoint 0 is personal inventory, 1 merchant stock, 2+ item-owned bags.
## Purses remain endpoints 0/1; each offer names its separate destination.
const SILVER = InventoryData.SILVER_ITEM

var inventories: Array[InventoryData] = []
var views: Array[InventoryData] = []
var offers: Array[Dictionary] = []
var quote: Callable
var _baseline: Array[Dictionary] = []
var equipment: EquipmentCapability
var equipment_views: Dictionary = {}
var _equipped: Dictionary = {}
var _stack_snapshot: Callable
# Rearrangements depending on an offered item's vacant cells settle with the deal.
# They must never overlap goods that still exist in the authoritative inventories.
var _positions: Array[Dictionary] = [{}, {}]
var _access_checks: Dictionary = {}

func add_inventory(inventory: InventoryData, access_check := Callable()) -> int:
	var existing := inventories.find(inventory)
	if existing >= 0:
		return existing
	var side := inventories.size()
	inventories.append(inventory)
	_positions.append({})
	_baseline.append(inventory._snapshot_standard_transaction())
	if access_check.is_valid():
		_access_checks[side] = access_check
	_rebuild_views()
	return side

func quote_price(side: int, entry) -> int:
	if entry == null or InventoryData.has_stored_items(entry.metadata):
		return -1
	for index in range(inventories.size()):
		if inventories[index].storage_stack_id == entry.stack_id:
			for offer in offers:
				if offer.side == index or _target(offer) == index:
					return -1
	return int(quote.call(1 if side == 1 else 0, entry))

func _storage_is_offered(side: int) -> bool:
	var id := inventories[side].storage_stack_id
	for offer in offers:
		if offer.entry.stack_id == id:
			return true
	return false

func _target(offer: Dictionary) -> int:
	return int(offer.get("target", 0 if offer.side == 1 else 1))

func bind_equipment(target: EquipmentCapability, snapshot: Callable) -> void:
	equipment = target
	_stack_snapshot = snapshot
	reset()

func _capture_equipment() -> void:
	_equipped.clear()
	if equipment == null:
		return
	for slot in equipment.get_equipped_items():
		var id := equipment.get_equipped_stack_id(slot)
		var details: Dictionary = _stack_snapshot.call(id) if _stack_snapshot.is_valid() else {}
		_equipped[slot] = InventoryData.InventoryEntry.new(equipment.get_equipped_item(slot), Vector2i.ZERO, 1, details.get("contained_item_counts", {}), details.get("metadata", {}), id)

func equipment_entry(slot: String):
	return equipment_views.get(slot)

func _source_slot(entry) -> String:
	if entry != null:
		for slot in _equipped:
			if _equipped[slot].stack_id == entry.stack_id:
				return slot
	return ""

func _displacing_offer(entry) -> Dictionary:
	for offer in offers:
		if offer.has("displaced") and offer.displaced.stack_id == entry.stack_id:
			return offer
	return {}

func _rebase_owned_state() -> void:
	_capture_equipment()
	for side in range(inventories.size()):
		_baseline[side] = inventories[side]._snapshot_standard_transaction()
	_rebuild_views()

func _owned_equip_bag(entry, source_side: int) -> InventoryData:
	var bag := InventoryData.new(inventories[source_side].columns, inventories[source_side].rows)
	for current in views[source_side].entries:
		if current.stack_id != entry.stack_id:
			bag.entries.append(current)
	for current in inventories[source_side].entries:
		if current.stack_id != entry.stack_id:
			bag.entries.append(current)
	return bag

func owned_equipment_error(entry, slot: String, source_side := 0) -> String:
	if not is_current():
		return "Inventory changed — reset this deal"
	if source_side < 0 or source_side >= inventories.size() or source_side == 1 or _storage_is_offered(source_side):
		return "Unavailable"
	var live = original(source_side, entry)
	if live == null or live.count != 1 or equipment == null or not equipment.can_equip_item_to_slot(live.definition, slot):
		return "Cannot equip"
	if not offer_for(live).is_empty() or not _displacing_offer(live).is_empty():
		return "Withdraw the offer first"
	for offer in offers:
		if offer.get("slot", "") == slot:
			return "Move the pending item first"
	var old = _equipped.get(slot)
	if old != null and old.stack_id != live.stack_id:
		if not offer_for(old).is_empty():
			return "Withdraw the offer first"
		if _owned_equip_bag(live, source_side).find_first_space(old.definition, null, entry.grid_position) == Vector2i(-1, -1):
			return "No room for equipped item"
		var bag := inventories[source_side]
		var same_carrier := bag.get_carrying_inventory() == inventories[0].get_carrying_inventory()
		var removed_weight := bag.get_entry_weight(live) if bag.entries.has(live) and not (same_carrier and live.definition.has_storage()) else 0.0
		var added_weight := 0.0 if same_carrier and old.definition.has_storage() else bag.get_entry_weight(old)
		if not bag.accepts_item_count(old.definition, 1) or (bag.use_weight and bag.get_capacity_weight() - removed_weight + added_weight > bag.get_capacity_limit()):
			return "Too heavy"
	return ""

func equip_owned(entry, slot: String, source_side := 0) -> String:
	var error := owned_equipment_error(entry, slot, source_side)
	if not error.is_empty():
		return error
	var live = original(source_side, entry)
	var old = _equipped.get(slot)
	if old != null and old.stack_id == live.stack_id:
		return ""
	var source_slot := _source_slot(live)
	var cell := _owned_equip_bag(live, source_side).find_first_space(old.definition, null, entry.grid_position) if old != null else Vector2i.ZERO
	equipment.begin_equipment_update_batch()
	if not source_slot.is_empty():
		equipment.unequip_item_from_slot(source_slot)
	inventories[source_side].entries.erase(live)
	_positions[source_side].erase(live.stack_id)
	if old != null:
		inventories[source_side].entries.append(inventories[source_side].create_entry(old.definition, cell, 1, old.contained_item_counts, old.metadata, old.stack_id))
	equipment.equip_item_to_slot(live.definition, slot, live.stack_id)
	equipment.end_equipment_update_batch()
	if source_side != 0:
		inventories[source_side].changed.emit()
	inventories[0].changed.emit()
	_rebase_owned_state()
	return ""

func _init(bag: InventoryData, stock: InventoryData, price_provider: Callable) -> void:
	inventories.assign([bag, stock])
	quote = price_provider
	reset()

func reset() -> void:
	offers.clear()
	_positions.clear()
	for inventory in inventories:
		_positions.append({})
	_capture_equipment()
	_baseline.clear()
	for inventory in inventories:
		_baseline.append(inventory._snapshot_standard_transaction())
	_rebuild_views()

func is_current() -> bool:
	for check: Callable in _access_checks.values():
		if not check.is_valid() or not check.call():
			return false
	if equipment != null:
		if equipment.get_equipped_items().size() != _equipped.size():
			return false
		for slot in _equipped:
			if equipment.get_equipped_item(slot) != _equipped[slot].definition or equipment.get_equipped_stack_id(slot) != _equipped[slot].stack_id:
				return false
	for side in range(inventories.size()):
		var live := inventories[side]
		var saved: Array = _baseline[side].entries
		if live.entries.size() != saved.size():
			return false
		for i in range(saved.size()):
			var a = live.entries[i]
			var b = saved[i]
			if a != _baseline[side].original_entries[i] or a.definition != b.definition or a.count != b.count or a.grid_position != b.grid_position or a.metadata != b.metadata or a.contained_item_counts != b.contained_item_counts or a.stack_id != b.stack_id:
				return false
	return true

func original(side: int, entry):
	if side < 0 or side >= inventories.size() or entry == null:
		return null
	for live in inventories[side].entries:
		if live.stack_id == entry.stack_id:
			return live
	if side == 0:
		for live in _equipped.values():
			if live.stack_id == entry.stack_id:
				return live
	return null

func offer_for(entry) -> Dictionary:
	if entry != null:
		for offer in offers:
			if offer.entry.stack_id == entry.stack_id:
				return offer
	return {}

func drop_error(source_side: int, entry, target_side: int, cell: Vector2i, amount := -1) -> String:
	if not is_current():
		return "Inventory changed — reset this deal"
	if source_side < 0 or source_side >= inventories.size() or target_side < 0 or target_side >= inventories.size() or entry == null:
		return "Unavailable"
	if _storage_is_offered(source_side) or _storage_is_offered(target_side):
		return "Withdraw the bag offer first"
	if not inventories[target_side].accepts_item_count(entry.definition, entry.count):
		return "Cannot store that here"
	var pending := offer_for(entry)
	if not pending.is_empty() and pending.side != source_side:
		# Drag a proposed item back to its original owner to withdraw it.
		if target_side == pending.side:
			return _withdraw_offer(pending, cell, false)
		if pending.side != 1 and target_side != 1:
			return "Return to the source inventory to withdraw"
		return "" if views[target_side].can_place_item(entry.definition, cell, _view_entry(target_side, entry.stack_id)) else "No room"
	if source_side != target_side and source_side != 1 and target_side != 1:
		var owned = original(source_side, entry)
		if owned == null or not pending.is_empty() or not _displacing_offer(owned).is_empty():
			return "Withdraw the offer first"
		if not views[target_side].can_place_item(owned.definition, cell):
			return "No room"
		if not _source_slot(owned).is_empty():
			return "" if inventories[target_side].can_place_item(owned.definition, cell) else "No room"
		return "" if inventories[source_side].can_move_entry_to_inventory(owned, inventories[target_side], cell) else "No room or carrying capacity"
	if source_side == target_side:
		if source_side == 1 or original(source_side, entry) == null:
			return "Not your inventory"
		if not _source_slot(entry).is_empty() and _displacing_offer(entry).is_empty():
			var bag := inventories[0]
			if not bag.can_place_item(entry.definition, cell):
				return "No room"
			# An equipped storage item already contributes its shell and contents.
			var added_weight: float = 0.0 if entry.definition.has_storage() else bag.get_item_weight(entry.definition, 1, entry.contained_item_counts, entry.metadata)
			if not bag.accepts_item_count(entry.definition, 1) or (bag.use_weight and bag.get_capacity_weight() + added_weight > bag.get_capacity_limit()):
				return "Too heavy"
		return "" if views[target_side].can_place_item(entry.definition, cell, _view_entry(target_side, entry.stack_id)) else "No room"
	var live = original(source_side, entry)
	if live == null or live.definition == null or not live.definition.sellable or live.definition.is_currency_item():
		return "Not for trade"
	var offered: int = pending.get("count", 0)
	var available: int = live.count - offered
	var count: int = available if amount < 0 else amount
	if count <= 0 or count > available or (count < live.count and not live.contained_item_counts.is_empty()):
		return "Invalid quantity"
	if quote_price(source_side, live) < 0:
		return "Not accepted"
	if count + offered > inventories[target_side].get_stack_limit(live.definition):
		return "Split this stack first"
	if not views[target_side].can_place_item(live.definition, cell, _view_entry(target_side, live.stack_id)):
		return "No room"
	return ""

func propose(source_side: int, entry, target_side: int, cell: Vector2i, amount := -1) -> String:
	var error := drop_error(source_side, entry, target_side, cell, amount)
	if not error.is_empty():
		return error
	var pending := offer_for(entry)
	if source_side != target_side and source_side != 1 and target_side != 1 and pending.is_empty():
		var live = original(source_side, entry)
		var slot := _source_slot(live)
		if not slot.is_empty():
			equipment.begin_equipment_update_batch()
			equipment.unequip_item_from_slot(slot)
			inventories[target_side].entries.append(inventories[target_side].create_entry(live.definition, cell, 1, live.contained_item_counts, live.metadata, live.stack_id))
			equipment.end_equipment_update_batch()
			inventories[target_side].changed.emit()
		elif not inventories[source_side].move_entry_to_inventory(live, inventories[target_side], cell):
			return "No room or carrying capacity"
		_positions[source_side].erase(live.stack_id)
		_rebase_owned_state()
		return ""
	if source_side == target_side and (pending.is_empty() or pending.side == source_side):
		var live = original(source_side, entry)
		var displacement := _displacing_offer(live)
		if not displacement.is_empty():
			displacement.displaced_position = cell
			_rebuild_views()
			return ""
		var source_slot := _source_slot(live)
		if not source_slot.is_empty():
			equipment.begin_equipment_update_batch()
			equipment.unequip_item_from_slot(source_slot)
			inventories[0].entries.append(inventories[0].create_entry(live.definition, cell, 1, live.contained_item_counts, live.metadata, live.stack_id))
			equipment.end_equipment_update_batch()
			_rebase_owned_state()
			inventories[0].changed.emit()
			return ""
		if inventories[source_side].can_place_item(live.definition, cell, live):
			live.grid_position = cell
			_positions[source_side].erase(live.stack_id)
			_baseline[source_side] = inventories[source_side]._snapshot_standard_transaction()
		else:
			_positions[source_side][live.stack_id] = cell
		_rebuild_views()
		inventories[source_side].changed.emit()
		_rebase_owned_state()
		return ""
	if not pending.is_empty():
		if target_side == pending.side:
			return _withdraw_offer(pending, cell, true)
		else:
			if source_side == pending.side:
				pending.count += int(pending.entry.count) - int(pending.count) if amount < 0 else amount
			pending.position = cell
			pending.target = target_side
			pending.erase("slot")
			pending.erase("displaced")
	else:
		var live = original(source_side, entry)
		offers.append({"side": source_side, "target": target_side, "entry": live, "count": live.count if amount < 0 else amount,
			"position": cell, "price": quote_price(source_side, live)})
		if source_side == 0 and not _source_slot(live).is_empty():
			offers[-1].source_slot = _source_slot(live)
	_rebuild_views()
	return ""

func _view_entry(side: int, stack_id: String):
	for entry in views[side].entries:
		if entry.stack_id == stack_id:
			return entry
	return null

func net_silver() -> int:
	var total := 0
	for offer in offers:
		total += int(offer.price) * int(offer.count) * (1 if offer.side == 1 else -1)
	return total

func withdraw(entry) -> String:
	if not is_current():
		return "Inventory changed — reset this deal"
	var pending := offer_for(entry)
	if pending.is_empty():
		return ""
	var side: int = pending.side
	var cell: Vector2i = _positions[side].get(entry.stack_id, pending.entry.grid_position)
	if _withdraw_offer(pending, cell, false).is_empty():
		return _withdraw_offer(pending, cell, true)
	cell = views[side].find_first_space(entry.definition)
	return _withdraw_offer(pending, cell, true)

func _withdraw_offer(pending: Dictionary, cell: Vector2i, apply: bool) -> String:
	# Test the complete result: withdrawing a purchase can also restore equipment.
	var saved_offers := offers.duplicate()
	var saved_positions := _positions.duplicate(true)
	var displacement := _displacing_offer(pending.entry)
	var old_displaced_position: Vector2i = displacement.get("displaced_position", Vector2i.ZERO)
	var side: int = pending.side
	offers.erase(pending)
	if not displacement.is_empty():
		displacement.displaced_position = cell
	elif not pending.has("source_slot"):
		_positions[side][pending.entry.stack_id] = cell
	_rebuild_views()
	var valid := _layout_valid(views)
	if not apply or not valid:
		offers = saved_offers
		_positions = saved_positions
		if not displacement.is_empty():
			displacement.displaced_position = old_displaced_position
		_rebuild_views()
	return "" if valid else "No room"

func _layout_valid(bags: Array[InventoryData]) -> bool:
	for bag in bags:
		for entry in bag.entries:
			if not bag.can_place_item(entry.definition, entry.grid_position, entry):
				return false
	return true

func commit() -> String:
	if offers.is_empty():
		return "No goods offered"
	if not is_current():
		return "Inventory changed — reset this deal"
	for offer in offers:
		if quote_price(offer.side, offer.entry) != int(offer.price):
			return "Offer changed — reset this deal"
	var net := net_silver()
	var payer := inventories[0 if net >= 0 else 1]
	var receiver := inventories[1 if net >= 0 else 0]
	if payer.count_item(SILVER) < absi(net):
		return "Cannot afford"
	if not receiver.exchange_for_silver(payer, absi(net), _move_offered_goods, _finish_equipment, inventories):
		return "No room or carrying capacity"
	reset()
	return ""

func _move_offered_goods() -> bool:
	# Remove both sides before placing either side; publication happens only
	# after the existing bilateral transaction has settled goods AND payment.
	for offer in offers:
		var source := inventories[int(offer.side)]
		if int(offer.count) == int(offer.entry.count):
			source.entries.erase(offer.entry)
		else:
			offer.entry.count -= int(offer.count)
	for side in range(inventories.size()):
		for entry in inventories[side].entries:
			entry.grid_position = _positions[side].get(entry.stack_id, entry.grid_position)
	if not _layout_valid(inventories):
		return false
	for offer in offers:
		var destination := inventories[_target(offer)]
		var entry = offer.entry
		if offer.has("slot"):
			if equipment == null or not equipment.can_equip_item_to_slot(entry.definition, offer.slot):
				return false
			if offer.has("displaced") and offer_for(offer.displaced).is_empty():
				var old = offer.displaced
				if not destination.accepts_item_count(old.definition, 1) or not destination.can_place_item(old.definition, offer.displaced_position):
					return false
				destination.entries.append(destination.create_entry(old.definition, offer.displaced_position, 1, old.contained_item_counts, old.metadata, old.stack_id))
			continue
		if not destination.accepts_item_count(entry.definition, offer.count) or not destination.can_place_item(entry.definition, offer.position) or int(offer.count) > destination.get_stack_limit(entry.definition):
			return false
		var whole := not inventories[int(offer.side)].entries.has(entry)
		destination.entries.append(destination.create_entry(entry.definition, offer.position, offer.count, entry.contained_item_counts, entry.metadata, entry.stack_id if whole else ""))
	return _final_capacity_valid()

func _finish_equipment() -> bool:
	if not _final_capacity_valid():
		return false
	if equipment != null:
		equipment.begin_equipment_update_batch()
		for offer in offers:
			if offer.has("source_slot"):
				equipment.unequip_item_from_slot(offer.source_slot)
		for offer in offers:
			if offer.has("slot"):
				equipment.equip_item_to_slot(offer.entry.definition, offer.slot, offer.entry.stack_id)
		equipment.end_equipment_update_batch()
	return true

func equipment_drop_error(source_side: int, entry, slot: String) -> String:
	if not is_current():
		return "Inventory changed — reset this deal"
	if entry == null or equipment == null or not equipment.can_equip_item_to_slot(entry.definition, slot):
		return "Cannot equip"
	var pending := offer_for(entry)
	if source_side != 1 and (pending.is_empty() or pending.side != 1):
		return "Not a purchase"
	var live = original(1, entry)
	if live == null or live.count != 1 or quote_price(1, live) < 0:
		return "Not accepted"
	for offer in offers:
		if offer != pending and offer.get("slot", "") == slot:
			return "Move the pending item first"
	var displaced = _equipped.get(slot)
	if displaced != null and offer_for(displaced).is_empty():
		var space := _space_without_purchase(pending, displaced.definition)
		if space == Vector2i(-1, -1):
			return "No room for equipped item"
	return ""

func propose_equipment(source_side: int, entry, slot: String) -> String:
	var error := equipment_drop_error(source_side, entry, slot)
	if not error.is_empty():
		return error
	var pending := offer_for(entry)
	if pending.is_empty():
		pending = {"side": 1, "target": 0, "entry": original(1, entry), "count": 1, "price": quote_price(1, entry), "position": Vector2i.ZERO}
		offers.append(pending)
	var displaced = _equipped.get(slot)
	var cell := _space_without_purchase(pending, displaced.definition) if displaced != null else Vector2i.ZERO
	pending.erase("displaced")
	pending.slot = slot
	pending.target = 0
	if displaced != null:
		pending.displaced = displaced
		pending.displaced_position = cell
	_rebuild_views()
	return ""

func _space_without_purchase(pending: Dictionary, definition: ItemDefinition) -> Vector2i:
	var preview := InventoryData.new(inventories[0].columns, inventories[0].rows)
	for entry in views[0].entries:
		if not pending.is_empty() and (entry.stack_id == pending.entry.stack_id or (pending.has("displaced") and entry.stack_id == pending.displaced.stack_id)):
			continue
		preview.entries.append(entry)
	return preview.find_first_space(definition)

func _final_capacity_valid() -> bool:
	# Equipment changes publish only after payment and goods can both settle.
	# Include their final storage weight now without mutating live equipment.
	var equipment_weight_change := 0.0
	if inventories[0].additional_weight_provider.is_valid():
		equipment_weight_change = _storage_equipment_weight(equipment_views) - _storage_equipment_weight(_equipped)
	for inventory in inventories:
		var weight := inventory.get_capacity_weight()
		if inventory.get_carrying_inventory() == inventories[0]:
			weight += equipment_weight_change
		if inventory.use_weight and weight > inventory.get_capacity_limit():
			return false
	return true

func _storage_equipment_weight(items: Dictionary) -> float:
	var weight := 0.0
	var carrier := inventories[0]
	for entry in items.values():
		if not entry.definition.has_storage():
			continue
		var in_grid := false
		for current in carrier.entries:
			if current.stack_id == entry.stack_id:
				in_grid = true
		if not in_grid:
			weight += carrier.get_item_weight(entry.definition, 1, entry.contained_item_counts) + carrier.get_item_storage_weight(entry.stack_id, entry.metadata)
	return weight

func entry_state(side: int, entry) -> String:
	var offer := offer_for(entry)
	if offer.is_empty():
		return ""
	return "" if offer.side == side else "incoming"

func entry_tooltip(side: int, entry) -> String:
	var offer := offer_for(entry)
	if not offer.is_empty() and offer.side != side:
		return "%s\n%d × %d silver · Pending" % [entry.definition.display_name, offer.count, offer.price]
	var price := quote_price(side, entry)
	return "%s\n%s" % [entry.definition.display_name, "%d silver each" % price if price >= 0 else "Not for trade"]

func _rebuild_views() -> void:
	views.clear()
	equipment_views = _equipped.duplicate()
	for side in range(inventories.size()):
		var inventory := inventories[side]
		var view := InventoryData.new(inventory.columns, inventory.rows, inventory.max_weight, inventory.use_weight)
		for entry in inventory.entries:
			var offered := offer_for(entry)
			var count: int = entry.count - int(offered.get("count", 0))
			if count > 0:
				var cell: Vector2i = _positions[side].get(entry.stack_id, entry.grid_position)
				view.entries.append(InventoryData.InventoryEntry.new(entry.definition, cell, count, entry.contained_item_counts, entry.metadata, entry.stack_id))
		views.append(view)
	for offer in offers:
		if offer.has("source_slot"):
			equipment_views.erase(offer.source_slot)
	for offer in offers:
		var entry = offer.entry
		if offer.has("slot"):
			equipment_views[offer.slot] = entry
			if offer.has("displaced") and offer_for(offer.displaced).is_empty():
				var old = offer.displaced
				views[0].entries.append(InventoryData.InventoryEntry.new(old.definition, offer.displaced_position, 1, old.contained_item_counts, old.metadata, old.stack_id))
			continue
		views[_target(offer)].entries.append(InventoryData.InventoryEntry.new(entry.definition, offer.position, offer.count, entry.contained_item_counts, entry.metadata, entry.stack_id))
