extends Control

class_name InventoryGridControl

signal item_clicked(entry, shift_pressed)
signal item_right_clicked(entry, local_position, shift_pressed)
signal invalid_drop_attempted(message)
signal item_dropped_outside(source_owner, entry)

@export var cell_size := Vector2(30.0, 30.0)
@export var cell_gap := 2.0
@export var item_padding := 4.0

var inventory_data
var drop_validator: Callable
var drop_handler: Callable
var drop_error_provider: Callable
var _preview_visible := false
var _preview_rect := Rect2()
var _last_invalid_drop_message := ""
var _active_drag_data: Dictionary = {}


func set_inventory_data(data) -> void:
	if inventory_data == data:
		return
	if inventory_data != null and inventory_data.changed.is_connected(queue_redraw):
		inventory_data.changed.disconnect(queue_redraw)
	inventory_data = data
	if inventory_data != null:
		inventory_data.changed.connect(queue_redraw)
		custom_minimum_size = _grid_pixel_size()
	queue_redraw()


func _draw() -> void:
	if inventory_data == null:
		return

	for y in range(inventory_data.rows):
		for x in range(inventory_data.columns):
			var rect := _cell_rect(Vector2i(x, y))
			draw_rect(rect, Color(0.12, 0.12, 0.14, 0.9), true)
			draw_rect(rect, Color(0.24, 0.24, 0.28, 1.0), false, 1.0)

	for entry in inventory_data.entries:
		var item_rect := _item_rect(entry)
		draw_rect(item_rect, Color(0.22, 0.18, 0.12, 0.96), true)
		draw_rect(item_rect, Color(0.92, 0.74, 0.32, 1.0), false, 2.0)
		if entry.definition.icon != null:
			var content_rect := item_rect.grow(-item_padding)
			var texture_size: Vector2 = entry.definition.icon.get_size()
			var scale_factor := minf(content_rect.size.x / texture_size.x, content_rect.size.y / texture_size.y)
			var draw_size: Vector2 = texture_size * scale_factor
			var draw_position: Vector2 = content_rect.position + (content_rect.size - draw_size) * 0.5
			draw_texture_rect(entry.definition.icon, Rect2(draw_position, draw_size), false)
		else:
			draw_string(get_theme_default_font(), item_rect.position + Vector2(6, 20), entry.definition.display_name, HORIZONTAL_ALIGNMENT_LEFT, item_rect.size.x - 12, 16, Color(0.94, 0.94, 0.94, 1.0))
		var count_label := _entry_count_label(entry)
		if not count_label.is_empty():
			_draw_count_label(item_rect, count_label)
		_draw_bandage_uses_bar(entry, item_rect)

	if _preview_visible:
		draw_rect(_preview_rect, Color(1.0, 0.85, 0.35, 0.22), true)
		draw_rect(_preview_rect, Color(1.0, 0.88, 0.45, 1.0), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var entry = _entry_at_local_position(event.position)
		if entry != null:
			item_clicked.emit(entry, event.shift_pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var right_clicked_entry = _entry_at_local_position(event.position)
		if right_clicked_entry != null:
			item_right_clicked.emit(right_clicked_entry, event.position, event.shift_pressed)


func _get_tooltip(at_position: Vector2) -> String:
	var entry = _entry_at_local_position(at_position)
	if entry == null or entry.definition == null:
		return ""
	if inventory_data != null and inventory_data.has_method("is_entry_currency_container") and bool(inventory_data.call("is_entry_currency_container", entry)):
		var stored := _entry_silver_count(entry)
		var capacity := int(entry.definition.currency_container_capacity)
		return "%s\n%d/%d silver coins" % [entry.definition.display_name, stored, capacity]

	return entry.definition.display_name


func _get_drag_data(at_position: Vector2):
	var entry = _entry_at_local_position(at_position)
	if entry == null:
		return null

	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(max(72.0, cell_size.x * entry.definition.grid_size.x), max(32.0, cell_size.y * entry.definition.grid_size.y))
	var label := Label.new()
	label.text = entry.definition.display_name if entry.definition.icon == null else entry.definition.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(label)
	set_drag_preview(preview)
	_active_drag_data = {
		"entry": entry,
		"source_inventory": inventory_data,
		"source_owner": get_meta("source_owner", null),
	}
	return _active_drag_data


func _can_drop_data(at_position: Vector2, data) -> bool:
	if drop_validator.is_null():
		_clear_preview()
		_last_invalid_drop_message = ""
		return false
	var target_cell := _position_to_cell(at_position)
	var is_valid: bool = drop_validator.call(data, target_cell)
	if is_valid and typeof(data) == TYPE_DICTIONARY and data.has("entry"):
		_preview_visible = true
		_preview_rect = _item_rect_from_data(data["entry"], target_cell)
		_last_invalid_drop_message = ""
		queue_redraw()
	elif is_valid and typeof(data) == TYPE_DICTIONARY and data.has("cursor_item") and data.has("item_definition"):
		_preview_visible = true
		_preview_rect = _item_rect_from_definition(data["item_definition"], target_cell)
		_last_invalid_drop_message = ""
		queue_redraw()
	else:
		if not drop_error_provider.is_null():
			_last_invalid_drop_message = str(drop_error_provider.call(data, target_cell))
		else:
			_last_invalid_drop_message = ""
		_clear_preview()
	return is_valid


func _drop_data(at_position: Vector2, data) -> void:
	_clear_preview()
	if drop_handler.is_null():
		return
	drop_handler.call(data, _position_to_cell(at_position))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if not _active_drag_data.is_empty() and not is_drag_successful():
			var local_mouse_for_drop := get_local_mouse_position()
			if not Rect2(Vector2.ZERO, size).has_point(local_mouse_for_drop):
				item_dropped_outside.emit(_active_drag_data.get("source_owner", null), _active_drag_data.get("entry", null))
		if not _preview_visible and _last_invalid_drop_message != "":
			var local_mouse := get_local_mouse_position()
			if Rect2(Vector2.ZERO, size).has_point(local_mouse):
				invalid_drop_attempted.emit(_last_invalid_drop_message)
		_last_invalid_drop_message = ""
		_active_drag_data.clear()
		_clear_preview()


func _grid_pixel_size() -> Vector2:
	if inventory_data == null:
		return Vector2.ZERO
	return Vector2(
		inventory_data.columns * cell_size.x + maxf(0.0, float(inventory_data.columns - 1)) * cell_gap,
		inventory_data.rows * cell_size.y + maxf(0.0, float(inventory_data.rows - 1)) * cell_gap
	)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(
		Vector2(cell.x, cell.y) * (cell_size + Vector2.ONE * cell_gap),
		cell_size
	)


func _item_rect(entry) -> Rect2:
	var item_position := Vector2(entry.grid_position.x, entry.grid_position.y) * (cell_size + Vector2.ONE * cell_gap)
	var grid_cells := Vector2(entry.definition.grid_size.x, entry.definition.grid_size.y)
	var item_size := grid_cells * cell_size
	item_size += Vector2.ONE * cell_gap * Vector2(maxi(entry.definition.grid_size.x - 1, 0), maxi(entry.definition.grid_size.y - 1, 0))
	return Rect2(item_position, item_size)


func _position_to_cell(local_position: Vector2) -> Vector2i:
	var stride := cell_size + Vector2.ONE * cell_gap
	return Vector2i(floori(local_position.x / stride.x), floori(local_position.y / stride.y))


func _entry_at_local_position(local_position: Vector2):
	if inventory_data == null:
		return null
	return inventory_data.get_entry_at_cell(_position_to_cell(local_position))


func _item_rect_from_data(entry, grid_position: Vector2i) -> Rect2:
	var item_position := Vector2(grid_position.x, grid_position.y) * (cell_size + Vector2.ONE * cell_gap)
	var grid_cells := Vector2(entry.definition.grid_size.x, entry.definition.grid_size.y)
	var item_size := grid_cells * cell_size
	item_size += Vector2.ONE * cell_gap * Vector2(maxi(entry.definition.grid_size.x - 1, 0), maxi(entry.definition.grid_size.y - 1, 0))
	return Rect2(item_position, item_size)


func _item_rect_from_definition(definition: ItemDefinition, grid_position: Vector2i) -> Rect2:
	var item_position := Vector2(grid_position.x, grid_position.y) * (cell_size + Vector2.ONE * cell_gap)
	var grid_cells := Vector2(definition.grid_size.x, definition.grid_size.y)
	var item_size := grid_cells * cell_size
	item_size += Vector2.ONE * cell_gap * Vector2(maxi(definition.grid_size.x - 1, 0), maxi(definition.grid_size.y - 1, 0))
	return Rect2(item_position, item_size)


func _clear_preview() -> void:
	if not _preview_visible:
		return
	_preview_visible = false
	_preview_rect = Rect2()
	queue_redraw()


func _entry_count_label(entry) -> String:
	if entry == null:
		return ""
	if inventory_data != null and inventory_data.has_method("is_entry_currency_container") and bool(inventory_data.call("is_entry_currency_container", entry)):
		var stored := _entry_silver_count(entry)
		var capacity := int(entry.definition.currency_container_capacity)
		return "%d/%d" % [stored, capacity]

	if entry.count > 1:
		return str(entry.count)
	return ""


func _entry_silver_count(entry) -> int:
	if inventory_data == null or entry == null or not inventory_data.has_method("get_entry_contained_item_count"):
		return 0
	return int(inventory_data.call("get_entry_contained_item_count", entry, InventoryData.SILVER_ITEM))


func _draw_count_label(item_rect: Rect2, count_label: String) -> void:
	var font := get_theme_default_font()
	var font_size := 14
	var text_size := font.get_string_size(count_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var backplate := Rect2(item_rect.position + Vector2(4.0, item_rect.size.y - text_size.y - 8.0), text_size + Vector2(8.0, 5.0))
	draw_rect(backplate, Color(0.02, 0.018, 0.012, 0.78), true)
	draw_rect(backplate, Color(1.0, 1.0, 1.0, 0.18), false, 1.0)
	var text_position := item_rect.position + Vector2(8.0, item_rect.size.y - 7.0)
	draw_string(font, text_position + Vector2(1.0, 1.0), count_label, HORIZONTAL_ALIGNMENT_LEFT, item_rect.size.x - 12.0, font_size, Color(0.0, 0.0, 0.0, 0.9))
	draw_string(font, text_position, count_label, HORIZONTAL_ALIGNMENT_LEFT, item_rect.size.x - 12.0, font_size, Color(1.0, 1.0, 1.0, 1.0))


func _draw_bandage_uses_bar(entry, item_rect: Rect2) -> void:
	if entry == null or entry.definition == null or int(entry.definition.bandage_max_uses) <= 0:
		return
	var max_uses := int(entry.definition.bandage_max_uses)
	var uses := max_uses
	if inventory_data != null and inventory_data.has_method("get_entry_bandage_uses"):
		uses = int(inventory_data.call("get_entry_bandage_uses", entry))
	var ratio := clampf(float(uses) / float(max_uses), 0.0, 1.0)
	var bar_rect := Rect2(item_rect.position + Vector2(6.0, item_rect.size.y - 8.0), Vector2(maxf(4.0, item_rect.size.x - 12.0), 4.0))
	draw_rect(bar_rect, Color(0.02, 0.018, 0.014, 0.62), true)
	if ratio > 0.0:
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * ratio, bar_rect.size.y)), Color(0.72, 0.88, 0.78, 0.92), true)
	draw_rect(bar_rect, Color(1.0, 1.0, 1.0, 0.16), false, 1.0)
