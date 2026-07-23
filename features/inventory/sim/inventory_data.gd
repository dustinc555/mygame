extends RefCounted

class_name InventoryData

const SILVER_ITEM := preload("res://features/inventory/resources/items/silver.tres")
const SILVER_POUCH_ITEM := preload("res://features/inventory/resources/items/silver_pouch.tres")
const ENTRY_BANDAGE_USES_KEY := "__bandage_uses"
const META_STOLEN := "stolen"
const META_STOLEN_FROM_FACTION_ID := "stolen_from_faction_id"
const META_STOLEN_FROM_SETTLEMENT_ID := "stolen_from_settlement_id"
const META_STOLEN_BY_ACTOR_ID := "stolen_by_actor_id"
const META_STOLEN_AT_MINUTE := "stolen_at_minute"
const META_STOLEN_EXPIRES_AT_MINUTE := "stolen_expires_at_minute"
const META_LAW_PRISONER_KEY := "law_prisoner_key"
const META_LAW_CASE_ID := "law_case_id"

signal changed


class InventoryEntry:
	var stack_id: String
	var definition
	var grid_position: Vector2i
	var count := 1
	var contained_item_counts: Dictionary = {}
	var metadata: Dictionary = {}

	func _init(item_definition, item_grid_position: Vector2i, item_count: int = 1, item_contained_item_counts: Dictionary = {}, item_metadata: Dictionary = {}, item_stack_id := "") -> void:
		stack_id = item_stack_id if not item_stack_id.is_empty() else InventoryData.create_stack_id()
		definition = item_definition
		grid_position = item_grid_position
		count = item_count
		contained_item_counts = item_contained_item_counts.duplicate(true)
		metadata = item_metadata.duplicate(true)


var columns := 10
var rows := 6
var max_weight := 60.0
var use_weight := true
var entries: Array[InventoryEntry] = []
var stack_id_prefix := ""
var next_stack_sequence := 1


static func create_stack_id() -> String:
	return "stack:%x" % ResourceUID.create_id()


func configure_stack_allocator(prefix: String, sequence := 1) -> void:
	stack_id_prefix = prefix.strip_edges()
	next_stack_sequence = maxi(1, sequence)
	for entry in entries:
		if entry != null:
			_observe_stack_id(entry.stack_id)


func create_entry(definition, grid_position: Vector2i, count := 1, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}, stack_id := "") -> InventoryEntry:
	var resolved_id := stack_id if not stack_id.is_empty() else _allocate_stack_id()
	_observe_stack_id(resolved_id)
	return InventoryEntry.new(definition, grid_position, count, contained_item_counts, metadata, resolved_id)


func _allocate_stack_id() -> String:
	if stack_id_prefix.is_empty():
		return create_stack_id()
	var stack_id := "%s.stack.%d" % [stack_id_prefix, next_stack_sequence]
	next_stack_sequence += 1
	return stack_id


func _observe_stack_id(stack_id: String) -> void:
	var prefix := "%s.stack." % stack_id_prefix
	if stack_id_prefix.is_empty() or not stack_id.begins_with(prefix):
		return
	next_stack_sequence = maxi(next_stack_sequence, int(stack_id.trim_prefix(prefix)) + 1)


func _init(inventory_columns: int = 10, inventory_rows: int = 6, inventory_max_weight: float = 60.0, inventory_use_weight: bool = true) -> void:
	columns = inventory_columns
	rows = inventory_rows
	max_weight = inventory_max_weight
	use_weight = inventory_use_weight


func get_total_weight() -> float:
	var total := 0.0
	for entry in entries:
		total += get_entry_weight(entry)
	return total


func can_add_item(definition) -> bool:
	return can_add_item_count(definition, 1)


func can_add_item_count(definition, amount: int) -> bool:
	if _is_silver_currency(definition):
		return _can_add_silver_count(amount)
	return _can_add_standard_item_count(definition, amount)


func can_add_loose_item_count(definition, amount: int) -> bool:
	return _can_add_standard_item_count(definition, amount)


func _can_add_standard_item_count(definition, amount: int) -> bool:
	if definition == null:
		return false
	if amount <= 0:
		return true
	if use_weight and get_total_weight() + get_item_weight(definition, amount) > max_weight:
		return false
	var remaining := amount
	if definition.max_stack > 1:
		for entry in entries:
			if _is_same_definition(entry.definition, definition) and entry.count < definition.max_stack and entry.contained_item_counts.is_empty() and entry.metadata.is_empty():
				remaining -= min(remaining, definition.max_stack - entry.count)
				if remaining <= 0:
					return true
	var reserved: Array = []
	while remaining > 0:
		var slot := _find_first_space_with_reserved_entries(definition, reserved)
		if slot == Vector2i(-1, -1):
			return false
		reserved.append({"definition": definition, "position": slot})
		remaining -= min(remaining, max(definition.max_stack, 1))
	return true


func add_item(definition) -> bool:
	return add_item_count(definition, 1)


func add_item_count(definition, amount: int) -> bool:
	if _is_silver_currency(definition):
		return _add_silver_count(amount)
	return _add_standard_item_count(definition, amount)


func add_loose_item_count(definition, amount: int) -> bool:
	return _add_standard_item_count(definition, amount)


func can_add_item_count_with_metadata(definition, amount: int, metadata: Dictionary) -> bool:
	if metadata.is_empty():
		return can_add_item_count(definition, amount)
	return _can_add_item_count_as_distinct_entries(definition, amount, {}, metadata)


func add_item_count_with_metadata(definition, amount: int, metadata: Dictionary) -> bool:
	if metadata.is_empty():
		return add_item_count(definition, amount)
	return _add_item_count_as_distinct_entries(definition, amount, {}, metadata)


func _add_standard_item_count(definition, amount: int, emit_changed := true) -> bool:
	if not _can_add_standard_item_count(definition, amount):
		return false
	var remaining := amount
	if definition.max_stack > 1:
		for entry in entries:
			if _is_same_definition(entry.definition, definition) and entry.count < definition.max_stack and entry.contained_item_counts.is_empty() and entry.metadata.is_empty():
				var added: int = min(remaining, definition.max_stack - entry.count)
				entry.count += added
				remaining -= added
				if remaining <= 0:
					if emit_changed:
						changed.emit()
					return true
	while remaining > 0:
		var slot: Vector2i = find_first_space(definition)
		if slot == Vector2i(-1, -1):
			return false
		var stack_count: int = min(remaining, max(definition.max_stack, 1))
		entries.append(create_entry(definition, slot, stack_count))
		remaining -= stack_count
	if emit_changed:
		changed.emit()
	return true


func can_add_entry_with_contents(definition, amount: int = 1, contained_item_counts: Dictionary = {}, _metadata: Dictionary = {}) -> bool:
	if definition == null or amount <= 0:
		return false
	if use_weight and get_total_weight() + get_item_weight(definition, amount, contained_item_counts) > max_weight:
		return false
	return find_first_space(definition) != Vector2i(-1, -1)


func add_entry_with_contents(definition, amount: int = 1, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}, stack_id := "") -> bool:
	if not can_add_entry_with_contents(definition, amount, contained_item_counts, metadata):
		return false
	var slot := find_first_space(definition)
	if slot == Vector2i(-1, -1):
		return false
	entries.append(create_entry(definition, slot, amount, contained_item_counts, metadata, stack_id))
	changed.emit()
	return true


func get_entry_at_cell(cell: Vector2i):
	for entry in entries:
		if _cell_in_entry(cell, entry):
			return entry
	return null


## True when move_entry_to_inventory would commit: the entry lives here, the
## target has the weight budget, and the cell fits. Lets callers gate side
## effects (theft rolls, stolen-item metadata) on a take that will happen.
func can_move_entry_to_inventory(entry, target_inventory, target_position: Vector2i) -> bool:
	if entry == null or target_inventory == null:
		return false
	if not entries.has(entry):
		return false
	if target_inventory == self:
		return true
	if target_inventory.use_weight and target_inventory.get_total_weight() + get_entry_weight(entry) > target_inventory.max_weight:
		return false
	return target_inventory.can_place_item(entry.definition, target_position)


func move_entry_to_inventory(entry, target_inventory, target_position: Vector2i) -> bool:
	if not can_move_entry_to_inventory(entry, target_inventory, target_position):
		return false
	if target_inventory == self:
		return move_entry(entry, target_position)

	entries.erase(entry)
	target_inventory.entries.append(InventoryEntry.new(entry.definition, target_position, entry.count, entry.contained_item_counts, entry.metadata, entry.stack_id))
	changed.emit()
	target_inventory.changed.emit()
	return true


func count_item(definition) -> int:
	var total := 0
	for entry in entries:
		if _is_same_definition(entry.definition, definition):
			total += entry.count
		elif _is_silver_currency(definition) and _is_silver_pouch_entry(entry):
			total += get_entry_contained_item_count(entry, SILVER_ITEM)
	return total


func remove_item_count(definition, amount: int) -> bool:
	if _is_silver_currency(definition):
		return _remove_silver_count(amount)
	return _remove_standard_item_count(definition, amount)


func _remove_standard_item_count(definition, amount: int) -> bool:
	if definition == null or amount <= 0:
		return false
	if count_item(definition) < amount:
		return false
	var remaining := amount
	for index in range(entries.size() - 1, -1, -1):
		var entry = entries[index]
		if not _is_same_definition(entry.definition, definition):
			continue
		var removed: int = min(remaining, entry.count)
		entry.count -= removed
		remaining -= removed
		if entry.count <= 0:
			entries.remove_at(index)
		if remaining <= 0:
			changed.emit()
			return true
	changed.emit()
	return true


func get_entry_weight(entry) -> float:
	if entry == null:
		return 0.0
	return get_item_weight(entry.definition, entry.count, entry.contained_item_counts)


func get_item_weight(definition, amount: int = 1, contained_item_counts: Dictionary = {}) -> float:
	if definition == null or amount <= 0:
		return 0.0
	var total: float = float(definition.unit_weight) * float(amount)
	var silver_count := int(contained_item_counts.get(_item_key(SILVER_ITEM), 0))
	if silver_count > 0:
		total += SILVER_ITEM.unit_weight * silver_count
	return total


func get_entry_contained_item_count(entry, definition) -> int:
	if entry == null or definition == null:
		return 0
	return max(0, int(entry.contained_item_counts.get(_item_key(definition), 0)))


func get_entry_bandage_max_uses(entry) -> int:
	if entry == null or entry.definition == null:
		return 0
	return max(0, int(entry.definition.bandage_max_uses))


func get_entry_bandage_uses(entry) -> int:
	var max_uses := get_entry_bandage_max_uses(entry)
	if max_uses <= 0:
		return 0
	var stored_uses := int(entry.contained_item_counts.get(ENTRY_BANDAGE_USES_KEY, max_uses))
	return clampi(stored_uses, 0, max_uses)


func set_entry_bandage_uses(entry, amount: int, emit_changed := true) -> bool:
	if entry == null or not entries.has(entry):
		return false
	var max_uses := get_entry_bandage_max_uses(entry)
	if max_uses <= 0:
		return false
	var clamped_amount := clampi(amount, 0, max_uses)
	if clamped_amount <= 0:
		entries.erase(entry)
	elif clamped_amount >= max_uses:
		entry.contained_item_counts.erase(ENTRY_BANDAGE_USES_KEY)
	else:
		entry.contained_item_counts[ENTRY_BANDAGE_USES_KEY] = clamped_amount
	if emit_changed:
		changed.emit()
	return true


func consume_bandage_entry_use(entry, emit_changed := true) -> bool:
	if entry == null or not entries.has(entry):
		return false
	var remaining_uses := get_entry_bandage_uses(entry)
	if remaining_uses <= 0:
		return false
	remaining_uses -= 1
	if remaining_uses <= 0:
		entries.erase(entry)
	else:
		set_entry_bandage_uses(entry, remaining_uses, false)
	if emit_changed:
		changed.emit()
	return true


func set_entry_contained_item_count(entry, definition, amount: int, emit_changed := true) -> bool:
	if entry == null or definition == null or not entries.has(entry):
		return false
	var key: String = _item_key(definition)
	var clamped_amount: int = max(0, amount)
	if clamped_amount <= 0:
		entry.contained_item_counts.erase(key)
	else:
		entry.contained_item_counts[key] = clamped_amount
	if emit_changed:
		changed.emit()
	return true


func adjust_entry_contained_item_count(entry, definition, amount_delta: int, emit_changed := true) -> int:
	if entry == null or definition == null or not entries.has(entry):
		return 0
	var previous := get_entry_contained_item_count(entry, definition)
	var next: int = max(0, previous + amount_delta)
	set_entry_contained_item_count(entry, definition, next, emit_changed)
	return next - previous


func get_entry_remaining_currency_capacity(entry, definition) -> int:
	if entry == null or definition == null or not _entry_can_store_currency(entry, definition):
		return 0
	var capacity := int(entry.definition.currency_container_capacity)
	return max(0, capacity - get_entry_contained_item_count(entry, definition))


func is_entry_currency_container(entry, definition = null) -> bool:
	if entry == null or entry.definition == null:
		return false
	if definition != null:
		return _entry_can_store_currency(entry, definition)
	return not str(entry.definition.currency_id).is_empty() and int(entry.definition.currency_container_capacity) > 0


func can_take_contained_item_as_loose(entry, definition, amount: int) -> bool:
	if entry == null or definition == null or amount <= 0:
		return false
	var available := get_entry_contained_item_count(entry, definition)
	return available >= amount and can_add_loose_item_count(definition, amount)


func take_contained_item_as_loose(entry, definition, amount: int) -> int:
	if entry == null or definition == null or amount <= 0:
		return 0
	var available := get_entry_contained_item_count(entry, definition)
	var taken: int = min(amount, available)
	if taken <= 0 or not can_add_loose_item_count(definition, taken):
		return 0
	set_entry_contained_item_count(entry, definition, available - taken, false)
	_add_standard_item_count(definition, taken, false)
	changed.emit()
	return taken


func remove_entry(entry) -> bool:
	if entry == null or not entries.has(entry):
		return false
	entries.erase(entry)
	changed.emit()
	return true


func get_entry_metadata(entry) -> Dictionary:
	return entry.metadata.duplicate(true) if entry != null else {}


func set_entry_metadata(entry, metadata: Dictionary, emit_changed := true) -> bool:
	if entry == null or not entries.has(entry):
		return false
	entry.metadata = metadata.duplicate(true)
	if emit_changed:
		changed.emit()
	return true


func is_entry_stolen(entry) -> bool:
	return entry != null and bool(entry.metadata.get(META_STOLEN, false))


func mark_entry_stolen(entry, faction_id: String, settlement_id: String, actor_id: String, stolen_at_minute: int, expires_at_minute: int, emit_changed := true) -> bool:
	if entry == null or not entries.has(entry):
		return false
	var metadata: Dictionary = entry.metadata.duplicate(true)
	metadata[META_STOLEN] = true
	metadata[META_STOLEN_FROM_FACTION_ID] = faction_id
	metadata[META_STOLEN_FROM_SETTLEMENT_ID] = settlement_id
	metadata[META_STOLEN_BY_ACTOR_ID] = actor_id
	metadata[META_STOLEN_AT_MINUTE] = stolen_at_minute
	metadata[META_STOLEN_EXPIRES_AT_MINUTE] = expires_at_minute
	entry.metadata = metadata
	if emit_changed:
		changed.emit()
	return true


func clear_expired_stolen_metadata(absolute_minute: int) -> int:
	var cleared := 0
	for entry in entries:
		if entry == null or not bool(entry.metadata.get(META_STOLEN, false)):
			continue
		var expires_at := int(entry.metadata.get(META_STOLEN_EXPIRES_AT_MINUTE, -1))
		if expires_at < 0 or absolute_minute < expires_at:
			continue
		entry.metadata.erase(META_STOLEN)
		entry.metadata.erase(META_STOLEN_FROM_FACTION_ID)
		entry.metadata.erase(META_STOLEN_FROM_SETTLEMENT_ID)
		entry.metadata.erase(META_STOLEN_BY_ACTOR_ID)
		entry.metadata.erase(META_STOLEN_AT_MINUTE)
		entry.metadata.erase(META_STOLEN_EXPIRES_AT_MINUTE)
		cleared += 1
	if cleared > 0:
		changed.emit()
	return cleared


func move_entry(entry, target_position: Vector2i) -> bool:
	if entry == null:
		return false
	if not entries.has(entry):
		return false
	if not can_place_item(entry.definition, target_position, entry):
		return false
	entry.grid_position = target_position
	changed.emit()
	return true


func auto_sort() -> bool:
	if entries.is_empty():
		return true
	var existing_entries := entries.duplicate()
	existing_entries.sort_custom(_sort_entries_for_packing)
	entries.clear()
	for entry in existing_entries:
		var slot := find_first_space(entry.definition)
		if slot == Vector2i(-1, -1):
			entries = existing_entries
			changed.emit()
			return false
		entry.grid_position = slot
		entries.append(entry)
	changed.emit()
	return true


func _can_add_item_count_as_distinct_entries(definition, amount: int, contained_item_counts: Dictionary = {}, _metadata: Dictionary = {}) -> bool:
	if definition == null or amount <= 0:
		return false
	if use_weight and get_total_weight() + get_item_weight(definition, amount, contained_item_counts) > max_weight:
		return false
	var remaining := amount
	var reserved: Array = []
	while remaining > 0:
		var slot := _find_first_space_with_reserved_entries(definition, reserved)
		if slot == Vector2i(-1, -1):
			return false
		reserved.append({"definition": definition, "position": slot})
		remaining -= min(remaining, max(definition.max_stack, 1))
	return true


func _add_item_count_as_distinct_entries(definition, amount: int, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}, emit_changed := true) -> bool:
	if not _can_add_item_count_as_distinct_entries(definition, amount, contained_item_counts, metadata):
		return false
	var remaining := amount
	while remaining > 0:
		var slot := find_first_space(definition)
		if slot == Vector2i(-1, -1):
			return false
		var stack_count: int = min(remaining, max(definition.max_stack, 1))
		entries.append(create_entry(definition, slot, stack_count, contained_item_counts if remaining == amount else {}, metadata))
		remaining -= stack_count
	if emit_changed:
		changed.emit()
	return true


func find_first_space(definition) -> Vector2i:
	for y in range(rows - definition.grid_size.y + 1):
		for x in range(columns - definition.grid_size.x + 1):
			var cell := Vector2i(x, y)
			if can_place_item(definition, cell):
				return cell
	return Vector2i(-1, -1)


func can_place_item(definition, top_left: Vector2i, ignored_entry = null) -> bool:
	if top_left.x < 0 or top_left.y < 0:
		return false
	if top_left.x + definition.grid_size.x > columns:
		return false
	if top_left.y + definition.grid_size.y > rows:
		return false

	for entry in entries:
		if entry == ignored_entry:
			continue
		if _rects_overlap(top_left, definition.grid_size, entry.grid_position, entry.definition.grid_size):
			return false
	return true


func _rects_overlap(a_pos: Vector2i, a_size: Vector2i, b_pos: Vector2i, b_size: Vector2i) -> bool:
	return a_pos.x < b_pos.x + b_size.x and a_pos.x + a_size.x > b_pos.x and a_pos.y < b_pos.y + b_size.y and a_pos.y + a_size.y > b_pos.y


func _cell_in_entry(cell: Vector2i, entry) -> bool:
	return cell.x >= entry.grid_position.x and cell.y >= entry.grid_position.y and cell.x < entry.grid_position.x + entry.definition.grid_size.x and cell.y < entry.grid_position.y + entry.definition.grid_size.y


func _sort_entries_for_packing(a, b) -> bool:
	var a_area: int = a.definition.grid_size.x * a.definition.grid_size.y
	var b_area: int = b.definition.grid_size.x * b.definition.grid_size.y
	if a_area == b_area:
		return a.definition.display_name < b.definition.display_name
	return a_area > b_area


func _can_add_silver_count(amount: int) -> bool:
	if amount <= 0:
		return true
	var remaining := amount
	var added_weight := 0.0
	for entry in entries:
		if not _is_silver_pouch_entry(entry):
			continue
		var pouch_space := get_entry_remaining_currency_capacity(entry, SILVER_ITEM)
		if pouch_space <= 0:
			continue
		var added_to_existing: int = min(remaining, pouch_space)
		remaining -= added_to_existing
		added_weight += SILVER_ITEM.unit_weight * added_to_existing
		if remaining <= 0:
			return not use_weight or get_total_weight() + added_weight <= max_weight

	var reserved: Array = []
	var pouch_capacity := _silver_pouch_capacity()
	while remaining > 0 and pouch_capacity > 0:
		var pouch_slot := _find_first_space_with_reserved_entries(SILVER_POUCH_ITEM, reserved)
		if pouch_slot == Vector2i(-1, -1):
			break
		var stored_in_new_pouch: int = min(remaining, pouch_capacity)
		reserved.append({"definition": SILVER_POUCH_ITEM, "position": pouch_slot})
		remaining -= stored_in_new_pouch
		added_weight += get_item_weight(SILVER_POUCH_ITEM, 1, {_item_key(SILVER_ITEM): stored_in_new_pouch})

	if remaining > 0 and SILVER_ITEM.max_stack > 1:
		for entry in entries:
			if not _is_same_definition(entry.definition, SILVER_ITEM) or not entry.contained_item_counts.is_empty() or entry.count >= SILVER_ITEM.max_stack:
				continue
			var added_to_stack: int = min(remaining, SILVER_ITEM.max_stack - entry.count)
			remaining -= added_to_stack
			added_weight += SILVER_ITEM.unit_weight * added_to_stack
			if remaining <= 0:
				return not use_weight or get_total_weight() + added_weight <= max_weight

	while remaining > 0:
		var coin_slot := _find_first_space_with_reserved_entries(SILVER_ITEM, reserved)
		if coin_slot == Vector2i(-1, -1):
			return false
		var loose_count: int = min(remaining, max(SILVER_ITEM.max_stack, 1))
		reserved.append({"definition": SILVER_ITEM, "position": coin_slot})
		remaining -= loose_count
		added_weight += SILVER_ITEM.unit_weight * loose_count
	return not use_weight or get_total_weight() + added_weight <= max_weight


func _add_silver_count(amount: int) -> bool:
	if amount <= 0:
		return true
	if not _can_add_silver_count(amount):
		return false
	var remaining := amount
	var did_change := false
	for entry in entries:
		if not _is_silver_pouch_entry(entry):
			continue
		var pouch_space := get_entry_remaining_currency_capacity(entry, SILVER_ITEM)
		if pouch_space <= 0:
			continue
		var added_to_existing: int = min(remaining, pouch_space)
		set_entry_contained_item_count(entry, SILVER_ITEM, get_entry_contained_item_count(entry, SILVER_ITEM) + added_to_existing, false)
		remaining -= added_to_existing
		did_change = true
		if remaining <= 0:
			changed.emit()
			return true

	var pouch_capacity := _silver_pouch_capacity()
	while remaining > 0 and pouch_capacity > 0:
		var pouch_slot := find_first_space(SILVER_POUCH_ITEM)
		if pouch_slot == Vector2i(-1, -1):
			break
		var stored_in_new_pouch: int = min(remaining, pouch_capacity)
		entries.append(create_entry(SILVER_POUCH_ITEM, pouch_slot, 1, {_item_key(SILVER_ITEM): stored_in_new_pouch}))
		remaining -= stored_in_new_pouch
		did_change = true

	if remaining > 0:
		if not _add_standard_item_count(SILVER_ITEM, remaining, false):
			return false
		did_change = true
	if did_change:
		changed.emit()
	return true


func _remove_silver_count(amount: int) -> bool:
	if amount <= 0:
		return false
	if count_item(SILVER_ITEM) < amount:
		return false
	var remaining := amount
	var did_change := false
	for index in range(entries.size() - 1, -1, -1):
		var entry = entries[index]
		if not _is_same_definition(entry.definition, SILVER_ITEM):
			continue
		var removed: int = min(remaining, entry.count)
		entry.count -= removed
		remaining -= removed
		did_change = true
		if entry.count <= 0:
			entries.remove_at(index)
		if remaining <= 0:
			changed.emit()
			return true
	for index in range(entries.size() - 1, -1, -1):
		var entry = entries[index]
		if not _is_silver_pouch_entry(entry):
			continue
		var pouch_count := get_entry_contained_item_count(entry, SILVER_ITEM)
		if pouch_count <= 0:
			continue
		var removed_from_pouch: int = min(remaining, pouch_count)
		set_entry_contained_item_count(entry, SILVER_ITEM, pouch_count - removed_from_pouch, false)
		remaining -= removed_from_pouch
		did_change = true
		if remaining <= 0:
			changed.emit()
			return true
	if did_change:
		changed.emit()
	return remaining <= 0


func _silver_pouch_capacity() -> int:
	return max(0, int(SILVER_POUCH_ITEM.currency_container_capacity))


func _is_silver_currency(definition) -> bool:
	if definition == null:
		return false
	if _is_same_definition(definition, SILVER_ITEM):
		return true
	return str(definition.currency_id) == str(SILVER_ITEM.currency_id) and int(definition.currency_container_capacity) <= 0


func _is_silver_pouch_entry(entry) -> bool:
	return entry != null and _entry_can_store_currency(entry, SILVER_ITEM)


func _entry_can_store_currency(entry, definition) -> bool:
	if entry == null or entry.definition == null or definition == null:
		return false
	return str(entry.definition.currency_id) == str(definition.currency_id) and int(entry.definition.currency_container_capacity) > 0


func _is_same_definition(left, right) -> bool:
	if left == right:
		return true
	if left == null or right == null:
		return false
	var left_path := str(left.resource_path)
	var right_path := str(right.resource_path)
	return not left_path.is_empty() and left_path == right_path


func _item_key(definition) -> String:
	if definition == null:
		return ""
	var resource_path := str(definition.resource_path)
	return resource_path if not resource_path.is_empty() else str(definition.display_name)


func _find_first_space_with_reserved_entries(definition, reserved: Array) -> Vector2i:
	for y in range(rows - definition.grid_size.y + 1):
		for x in range(columns - definition.grid_size.x + 1):
			var cell := Vector2i(x, y)
			if not can_place_item(definition, cell):
				continue
			var overlaps_reserved := false
			for reserved_entry in reserved:
				var reserved_definition = reserved_entry.get("definition", null)
				var reserved_position: Vector2i = reserved_entry.get("position", Vector2i(-1, -1))
				if reserved_definition == null:
					continue
				if _rects_overlap(cell, definition.grid_size, reserved_position, reserved_definition.grid_size):
					overlaps_reserved = true
					break
			if not overlaps_reserved:
				return cell
	return Vector2i(-1, -1)
