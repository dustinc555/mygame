extends RefCounted

class_name InventoryData

signal changed


class InventoryEntry:
	var definition
	var grid_position: Vector2i
	var count := 1

	func _init(item_definition, item_grid_position: Vector2i, item_count: int = 1) -> void:
		definition = item_definition
		grid_position = item_grid_position
		count = item_count


var columns := 10
var rows := 6
var max_weight := 60.0
var use_weight := true
var entries: Array[InventoryEntry] = []


func _init(inventory_columns: int = 10, inventory_rows: int = 6, inventory_max_weight: float = 60.0, inventory_use_weight: bool = true) -> void:
	columns = inventory_columns
	rows = inventory_rows
	max_weight = inventory_max_weight
	use_weight = inventory_use_weight


func get_total_weight() -> float:
	var total := 0.0
	for entry in entries:
		total += entry.definition.unit_weight * entry.count
	return total


func can_add_item(definition) -> bool:
	return can_add_item_count(definition, 1)


func can_add_item_count(definition, amount: int) -> bool:
	if definition == null:
		return false
	if amount <= 0:
		return true
	if use_weight and get_total_weight() + definition.unit_weight * amount > max_weight:
		return false
	var remaining := amount
	if definition.max_stack > 1:
		for entry in entries:
			if entry.definition == definition and entry.count < definition.max_stack:
				remaining -= min(remaining, definition.max_stack - entry.count)
				if remaining <= 0:
					return true
	var reserved: Array[Vector2i] = []
	while remaining > 0:
		var slot := _find_first_space_with_reserved(definition, reserved)
		if slot == Vector2i(-1, -1):
			return false
		reserved.append(slot)
		remaining -= min(remaining, max(definition.max_stack, 1))
	return true


func add_item(definition) -> bool:
	return add_item_count(definition, 1)


func add_item_count(definition, amount: int) -> bool:
	if not can_add_item_count(definition, amount):
		return false
	var remaining := amount
	if definition.max_stack > 1:
		for entry in entries:
			if entry.definition == definition and entry.count < definition.max_stack:
				var added: int = min(remaining, definition.max_stack - entry.count)
				entry.count += added
				remaining -= added
				if remaining <= 0:
					changed.emit()
					return true
	while remaining > 0:
		var slot: Vector2i = find_first_space(definition)
		if slot == Vector2i(-1, -1):
			return false
		var stack_count: int = min(remaining, max(definition.max_stack, 1))
		entries.append(InventoryEntry.new(definition, slot, stack_count))
		remaining -= stack_count
	changed.emit()
	return true


func get_entry_at_cell(cell: Vector2i):
	for entry in entries:
		if _cell_in_entry(cell, entry):
			return entry
	return null


func move_entry_to_inventory(entry, target_inventory, target_position: Vector2i) -> bool:
	if entry == null or target_inventory == null:
		return false
	if not entries.has(entry):
		return false
	if target_inventory == self:
		return move_entry(entry, target_position)
	if target_inventory.use_weight and target_inventory.get_total_weight() + entry.definition.unit_weight * entry.count > target_inventory.max_weight:
		return false
	if not target_inventory.can_place_item(entry.definition, target_position):
		return false

	entries.erase(entry)
	target_inventory.entries.append(InventoryEntry.new(entry.definition, target_position, entry.count))
	changed.emit()
	target_inventory.changed.emit()
	return true


func count_item(definition) -> int:
	var total := 0
	for entry in entries:
		if entry.definition == definition:
			total += entry.count
	return total


func remove_item_count(definition, amount: int) -> bool:
	if definition == null or amount <= 0:
		return false
	if count_item(definition) < amount:
		return false
	var remaining := amount
	for index in range(entries.size() - 1, -1, -1):
		var entry = entries[index]
		if entry.definition != definition:
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


func _find_first_space_with_reserved(definition, reserved: Array[Vector2i]) -> Vector2i:
	for y in range(rows - definition.grid_size.y + 1):
		for x in range(columns - definition.grid_size.x + 1):
			var cell := Vector2i(x, y)
			if not can_place_item(definition, cell):
				continue
			var overlaps_reserved := false
			for reserved_cell in reserved:
				if _rects_overlap(cell, definition.grid_size, reserved_cell, definition.grid_size):
					overlaps_reserved = true
					break
			if not overlaps_reserved:
				return cell
	return Vector2i(-1, -1)
