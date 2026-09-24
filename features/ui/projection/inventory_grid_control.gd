extends Control

class_name InventoryGridControl

signal item_clicked(entry, shift_pressed)
signal item_right_clicked(entry, local_position, shift_pressed)
signal invalid_drop_attempted(message)
signal item_dropped_outside(source_owner, entry)

const ITEM_GEOMETRY = preload("res://features/ui/projection/inventory_item_geometry.gd")
const DEFAULT_CELL_SIZE := ITEM_GEOMETRY.DEFAULT_CELL_SIZE
const DEFAULT_CELL_GAP := ITEM_GEOMETRY.DEFAULT_CELL_GAP
const DEFAULT_ITEM_PADDING := ITEM_GEOMETRY.DEFAULT_ITEM_PADDING

@export var cell_size := DEFAULT_CELL_SIZE
@export var cell_gap := DEFAULT_CELL_GAP
@export var item_padding := DEFAULT_ITEM_PADDING

var inventory_data
var drop_validator: Callable
var drop_handler: Callable
var drop_error_provider: Callable
var entry_tooltip_provider: Callable
var entry_state_provider: Callable
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
			draw_rect(rect, Color(0.065, 0.06, 0.048), true)
			draw_rect(rect, Color(0.23, 0.205, 0.16), false, 1.0)

	for entry in inventory_data.entries:
		var item_rect := _item_rect(entry)
		draw_rect(item_rect, Color(0.16, 0.14, 0.095), true)
		draw_rect(item_rect, Color(0.49, 0.40, 0.24), false, 1.0)
		if entry.definition.icon != null:
			var content_rect := item_rect.grow(-item_padding)
			draw_texture_rect(entry.definition.icon, fit_icon_rect(entry.definition.icon, content_rect), false)
		else:
			draw_string(get_theme_default_font(), item_rect.position + Vector2(6, 20), entry.definition.display_name, HORIZONTAL_ALIGNMENT_LEFT, item_rect.size.x - 12, 16, Color(0.94, 0.94, 0.94, 1.0))
		var count_label := _entry_count_label(entry)
		if not count_label.is_empty():
			_draw_count_label(item_rect, count_label)
		_draw_bandage_uses_bar(entry, item_rect)
		if entry_state_provider.is_valid():
			var state: String = entry_state_provider.call(entry)
			if state == "incoming":
				draw_rect(item_rect, Color(1.0, 0.85, 0.35), false, 2.0)

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
	if entry_tooltip_provider.is_valid():
		return entry_tooltip_provider.call(entry)
	if inventory_data != null and inventory_data.has_method("is_entry_currency_container") and bool(inventory_data.call("is_entry_currency_container", entry)):
		var stored := _entry_silver_count(entry)
		var capacity := int(entry.definition.currency_container_capacity)
		return "%s\n%d/%d silver coins" % [entry.definition.display_name, stored, capacity]

	return entry.definition.display_name


func _get_drag_data(at_position: Vector2):
	var entry = _entry_at_local_position(at_position)
	if entry == null:
		return null

	var preview := preload("res://features/ui/projection/item_drag_preview.gd").create(entry.definition, _entry_count_label(entry), _item_rect(entry).size, item_padding)
	set_drag_preview(preview)
	_active_drag_data = {
		"entry": entry,
		"source_inventory": inventory_data,
		"source_owner": get_meta("source_owner", null),
	}
	return _active_drag_data


func _can_drop_data(at_position: Vector2, data) -> bool:
	var definition := _drag_definition(data)
	if drop_validator.is_null() or definition == null:
		_clear_preview()
		_last_invalid_drop_message = ""
		return false
	var target_cell := _drop_cell(at_position, definition)
	var is_valid: bool = drop_validator.call(data, target_cell)
	if is_valid:
		_preview_visible = true
		_preview_rect = _item_rect_from_definition(definition, target_cell)
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
	var definition := _drag_definition(data)
	if drop_handler.is_null() or definition == null:
		return
	drop_handler.call(data, _drop_cell(at_position, definition))


func _drag_definition(data) -> ItemDefinition:
	if not data is Dictionary:
		return null
	if data.get("entry") != null:
		return data["entry"].definition as ItemDefinition
	return data.get("item_definition") as ItemDefinition


func _drop_cell(at_position: Vector2, definition: ItemDefinition) -> Vector2i:
	# The ghost is centered on the pointer. Snap its top-left to the nearest
	# grid origin; validation, highlight and commit all use this same cell.
	var origin := at_position - item_pixel_size(definition, cell_size, cell_gap) * 0.5
	var stride := cell_size + Vector2.ONE * cell_gap
	return Vector2i(roundi(origin.x / stride.x), roundi(origin.y / stride.y))


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
	return _item_rect_from_definition(entry.definition, entry.grid_position)


static func item_pixel_size(definition: ItemDefinition, cells := DEFAULT_CELL_SIZE, gap := DEFAULT_CELL_GAP) -> Vector2:
	return ITEM_GEOMETRY.item_pixel_size(definition, cells, gap)


static func grid_pixel_size(dimensions: Vector2i, cells := DEFAULT_CELL_SIZE, gap := DEFAULT_CELL_GAP) -> Vector2:
	return ITEM_GEOMETRY.grid_pixel_size(dimensions, cells, gap)


static func fit_icon_rect(texture: Texture2D, content_rect: Rect2) -> Rect2:
	return ITEM_GEOMETRY.fit_icon_rect(texture, content_rect)


func _position_to_cell(local_position: Vector2) -> Vector2i:
	var stride := cell_size + Vector2.ONE * cell_gap
	return Vector2i(floori(local_position.x / stride.x), floori(local_position.y / stride.y))


func _entry_at_local_position(local_position: Vector2):
	if inventory_data == null:
		return null
	return inventory_data.get_entry_at_cell(_position_to_cell(local_position))


func _item_rect_from_data(entry, grid_position: Vector2i) -> Rect2:
	return _item_rect_from_definition(entry.definition, grid_position)


func _item_rect_from_definition(definition: ItemDefinition, grid_position: Vector2i) -> Rect2:
	var item_position := Vector2(grid_position.x, grid_position.y) * (cell_size + Vector2.ONE * cell_gap)
	return Rect2(item_position, item_pixel_size(definition, cell_size, cell_gap))


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


func _count_label_font_size(item_rect: Rect2, count_label: String) -> int:
	var font := get_theme_default_font()
	var font_size := 14
	while font_size > 1 and font.get_string_size(count_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > item_rect.size.x - 12.0:
		font_size -= 1
	return font_size


func _draw_count_label(item_rect: Rect2, count_label: String) -> void:
	var font := get_theme_default_font()
	var font_size := _count_label_font_size(item_rect, count_label)
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
