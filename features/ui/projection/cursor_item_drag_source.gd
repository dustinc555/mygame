extends Control

class_name CursorItemDragSource

signal item_dropped_outside(source_owner, definition, count, contained_item_counts, item_metadata)

var source_owner
var item_definition: ItemDefinition
var item_count := 1
var contained_item_counts: Dictionary = {}
var item_metadata: Dictionary = {}
var _active_drag_id := 0
var _has_item := false
var _keep_requested := false
var _pending_replacement: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func start_drag(drag_owner, definition: ItemDefinition, count := 1, item_contained_item_counts: Dictionary = {}, metadata: Dictionary = {}) -> void:
	if definition == null or count <= 0:
		return
	source_owner = drag_owner
	item_definition = definition
	item_count = count
	contained_item_counts = item_contained_item_counts.duplicate(true)
	item_metadata = metadata.duplicate(true)
	_has_item = true
	_keep_requested = false
	_pending_replacement.clear()
	_active_drag_id += 1
	call_deferred("_begin_drag", _active_drag_id)


func consume_drag(drag_id: int) -> void:
	if drag_id != _active_drag_id:
		return
	_clear_item()


func keep_drag(drag_id: int) -> void:
	if drag_id != _active_drag_id:
		return
	_keep_requested = true


func replace_drag_item(drag_id: int, drag_owner, definition: ItemDefinition, count := 1, item_contained_item_counts: Dictionary = {}, metadata: Dictionary = {}) -> void:
	if drag_id != _active_drag_id:
		return
	if definition == null or count <= 0:
		_clear_item()
		return
	_pending_replacement = {
		"owner": drag_owner,
		"definition": definition,
		"count": count,
		"contained_item_counts": item_contained_item_counts.duplicate(true),
		"metadata": metadata.duplicate(true),
	}
	_has_item = false
	_keep_requested = false


func _begin_drag(drag_id: int) -> void:
	if drag_id != _active_drag_id or not _has_item or item_definition == null:
		return
	force_drag(_make_drag_data(), _make_drag_preview())


func _make_drag_data() -> Dictionary:
	return {
		"cursor_item": true,
		"cursor_drag_id": _active_drag_id,
		"cursor_source": self,
		"source_owner": source_owner,
		"item_definition": item_definition,
		"count": item_count,
		"contained_item_counts": contained_item_counts.duplicate(true),
		"metadata": item_metadata.duplicate(true),
	}


func _make_drag_preview() -> Control:
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(96.0, 36.0)
	var label := Label.new()
	label.text = _drag_label()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	preview.add_child(label)
	return preview


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	if not _pending_replacement.is_empty():
		var replacement := _pending_replacement.duplicate()
		_pending_replacement.clear()
		start_drag(replacement["owner"], replacement["definition"], int(replacement["count"]), replacement.get("contained_item_counts", {}), replacement.get("metadata", {}))
		return
	if not _has_item:
		return
	if _keep_requested:
		_keep_requested = false
		call_deferred("_begin_drag", _active_drag_id)
		return
	if is_drag_successful():
		_clear_item()
		return
	if _mouse_is_over_inventory_window():
		call_deferred("_begin_drag", _active_drag_id)
		return
	item_dropped_outside.emit(source_owner, item_definition, item_count, contained_item_counts.duplicate(true), item_metadata.duplicate(true))
	_clear_item()


func _drag_label() -> String:
	if item_definition == null:
		return "Item"
	if item_definition.currency_container_capacity > 0:
		var silver_key := str(InventoryData.SILVER_ITEM.resource_path)
		var stored := int(contained_item_counts.get(silver_key, 0))
		return "%s %d/%d" % [item_definition.display_name, stored, int(item_definition.currency_container_capacity)]

	if item_count > 1:
		return "%s x%d" % [item_definition.display_name, item_count]
	return item_definition.display_name


func _mouse_is_over_inventory_window() -> bool:
	var parent_node := get_parent()
	if parent_node == null:
		return false
	var mouse_position := get_global_mouse_position()
	for child in parent_node.get_children():
		if child is InventoryWindow and child.visible and Rect2(child.global_position, child.size).has_point(mouse_position):
			return true
	return false


func _clear_item() -> void:
	_has_item = false
	source_owner = null
	item_definition = null
	item_count = 1
	contained_item_counts.clear()
	item_metadata.clear()
	_keep_requested = false
	_pending_replacement.clear()
