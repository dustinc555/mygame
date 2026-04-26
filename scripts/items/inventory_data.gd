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
var entries: Array[InventoryEntry] = []


func _init(inventory_columns: int = 10, inventory_rows: int = 6, inventory_max_weight: float = 60.0) -> void:
	columns = inventory_columns
	rows = inventory_rows
	max_weight = inventory_max_weight


func get_total_weight() -> float:
	var total := 0.0
	for entry in entries:
		total += entry.definition.unit_weight * entry.count
	return total


func can_add_item(definition) -> bool:
	if definition == null:
		return false
	if get_total_weight() + definition.unit_weight > max_weight:
		return false
	return find_first_space(definition) != Vector2i(-1, -1)


func add_item(definition) -> bool:
	if not can_add_item(definition):
		return false

	var slot := find_first_space(definition)
	if slot == Vector2i(-1, -1):
		return false

	entries.append(InventoryEntry.new(definition, slot, 1))
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
	if target_inventory.get_total_weight() + entry.definition.unit_weight * entry.count > target_inventory.max_weight:
		return false
	if not target_inventory.can_place_item(entry.definition, target_position):
		return false

	entries.erase(entry)
	target_inventory.entries.append(InventoryEntry.new(entry.definition, target_position, entry.count))
	changed.emit()
	target_inventory.changed.emit()
	return true


func find_first_space(definition) -> Vector2i:
	for y in range(rows - definition.grid_size.y + 1):
		for x in range(columns - definition.grid_size.x + 1):
			var cell := Vector2i(x, y)
			if can_place_item(definition, cell):
				return cell
	return Vector2i(-1, -1)


func can_place_item(definition, top_left: Vector2i) -> bool:
	if top_left.x < 0 or top_left.y < 0:
		return false
	if top_left.x + definition.grid_size.x > columns:
		return false
	if top_left.y + definition.grid_size.y > rows:
		return false

	for entry in entries:
		if _rects_overlap(top_left, definition.grid_size, entry.grid_position, entry.definition.grid_size):
			return false
	return true


func _rects_overlap(a_pos: Vector2i, a_size: Vector2i, b_pos: Vector2i, b_size: Vector2i) -> bool:
	return a_pos.x < b_pos.x + b_size.x and a_pos.x + a_size.x > b_pos.x and a_pos.y < b_pos.y + b_size.y and a_pos.y + a_size.y > b_pos.y


func _cell_in_entry(cell: Vector2i, entry) -> bool:
	return cell.x >= entry.grid_position.x and cell.y >= entry.grid_position.y and cell.x < entry.grid_position.x + entry.definition.grid_size.x and cell.y < entry.grid_position.y + entry.definition.grid_size.y
