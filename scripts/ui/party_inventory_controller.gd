extends Node

class_name PartyInventoryController

const INVENTORY_WINDOW_SCENE := preload("res://scenes/ui/inventory_window.tscn")
const GECS_INVENTORY_VIEW_MODEL_SCRIPT := preload("res://scripts/ui/gecs_inventory_view_model.gd")
const CURSOR_ITEM_DRAG_SOURCE_SCRIPT := preload("res://scripts/ui/cursor_item_drag_source.gd")
const WINDOW_EDGE_PADDING := 36.0
const WINDOW_TOP_PADDING := 160.0
const WINDOW_GAP := 24.0
const REFRESH_INTERVAL_SECONDS := 0.1

@export var inventory_toggle_key := KEY_I

var root_scene: Node
var hud_layer: CanvasLayer
var inventory_window_layer: Control
var floating_notice
var cursor_item_drag_source
var primary_character_window: InventoryWindow
var secondary_inventory_window: InventoryWindow

var _windows_by_container_id: Dictionary = {}
var _models_by_container_id: Dictionary = {}
var _initialized := false
var _refresh_elapsed := 0.0
var _refresh_pending := false
var _selection_controller_node: Node


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	add_to_group("party_inventory_controller")
	_do_initialize()


func _process(delta: float) -> void:
	_bind_selection_controller()
	if not _initialized or _windows_by_container_id.is_empty():
		return
	_refresh_elapsed += delta
	if not _refresh_pending and _refresh_elapsed < REFRESH_INTERVAL_SECONDS:
		return
	_refresh_elapsed = 0.0
	_refresh_pending = false
	_refresh_open_windows()


func _unhandled_input(event: InputEvent) -> void:
	if not _initialized:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo or key_event.keycode != inventory_toggle_key:
		return
	open_selected_inventory()
	get_viewport().set_input_as_handled()


func open_selected_inventory() -> void:
	var selected_ids := _selected_actor_ids()
	if selected_ids.is_empty():
		return
	var primary_actor_id := selected_ids[0]
	if _is_live_window(primary_character_window) and _window_actor_id(primary_character_window) == primary_actor_id:
		_close_all_inventory_windows()
		return
	_open_primary_inventory(primary_actor_id, selected_ids.size() < 2)
	if selected_ids.size() >= 2:
		_open_secondary_inventory(selected_ids[1])
	_layout_inventory_windows()


func open_inventory_for_actor_id(actor_id: String) -> void:
	var normalized_id := actor_id.strip_edges()
	if normalized_id.is_empty():
		return
	_open_primary_inventory(normalized_id, true)
	_layout_inventory_windows()


func open_inventory_pair(primary_actor_id: String, secondary_actor_id: String) -> void:
	if primary_actor_id.strip_edges().is_empty():
		return
	_open_primary_inventory(primary_actor_id.strip_edges(), secondary_actor_id.strip_edges().is_empty())
	if not secondary_actor_id.strip_edges().is_empty() and secondary_actor_id.strip_edges() != primary_actor_id.strip_edges():
		_open_secondary_inventory(secondary_actor_id.strip_edges())
	_layout_inventory_windows()


func get_open_inventory_window(actor_id: String) -> InventoryWindow:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_actor_inventory_container_id"):
		return null
	var container_id := str(bridge.call("get_actor_inventory_container_id", actor_id.strip_edges()))
	var window = _windows_by_container_id.get(container_id)
	return window as InventoryWindow if _is_live_window(window) else null


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	if hud_layer == null:
		hud_layer = root_scene.get_node_or_null("GameHUD")
	if hud_layer == null:
		return
	inventory_window_layer = hud_layer.get_node_or_null("InventoryWindowLayer") as Control
	floating_notice = hud_layer.get_node_or_null("FloatingNotice")
	if inventory_window_layer == null:
		return
	_ensure_cursor_item_drag_source()
	_bind_selection_controller()
	_initialized = true


func _open_primary_inventory(actor_id: String, close_secondary := true) -> InventoryWindow:
	var model = _view_model_for_actor(actor_id)
	if model == null:
		return null
	if _is_live_window(primary_character_window) and _window_actor_id(primary_character_window) != actor_id:
		_close_inventory_window(primary_character_window)
	if close_secondary:
		_close_inventory_window(secondary_inventory_window)
	primary_character_window = _ensure_inventory_window(model)
	return primary_character_window


func _open_secondary_inventory(actor_id: String) -> InventoryWindow:
	var model = _view_model_for_actor(actor_id)
	if model == null:
		return null
	if _is_live_window(primary_character_window) and _window_actor_id(primary_character_window) == actor_id:
		secondary_inventory_window = null
		return primary_character_window
	if _is_live_window(secondary_inventory_window) and _window_actor_id(secondary_inventory_window) != actor_id:
		_close_inventory_window(secondary_inventory_window)
	secondary_inventory_window = _ensure_inventory_window(model)
	return secondary_inventory_window


func _ensure_inventory_window(model) -> InventoryWindow:
	var existing = _windows_by_container_id.get(model.container_id)
	if _is_live_window(existing):
		var existing_window := existing as InventoryWindow
		model.refresh()
		existing_window.visible = true
		existing_window.refresh()
		existing_window.grab_click_focus()
		inventory_window_layer.move_child(existing_window, inventory_window_layer.get_child_count() - 1)
		return existing_window
	var window := INVENTORY_WINDOW_SCENE.instantiate() as InventoryWindow
	_windows_by_container_id[model.container_id] = window
	inventory_window_layer.add_child(window)
	window.setup(model)
	window.close_requested.connect(_on_inventory_window_close_requested)
	window.notice_requested.connect(_show_floating_notice)
	window.transfer_requested.connect(_on_inventory_transfer_requested)
	window.quick_transfer_requested.connect(_on_inventory_quick_transfer_requested)
	window.item_action_requested.connect(_on_inventory_item_action_requested)
	window.equip_requested.connect(_on_inventory_equip_requested)
	window.equipment_transfer_requested.connect(_on_equipment_transfer_requested)
	window.unequip_requested.connect(_on_inventory_unequip_requested)
	window.item_drop_requested.connect(_on_inventory_item_drop_requested)
	window.equipment_drop_requested.connect(_on_inventory_equipment_drop_requested)
	window.cursor_item_place_requested.connect(_on_cursor_item_place_requested)
	window.cursor_item_equip_requested.connect(_on_cursor_item_equip_requested)
	window.sort_requested.connect(_on_inventory_sort_requested)
	window.grab_click_focus()
	return window


func _view_model_for_actor(actor_id: String):
	var bridge := _get_gecs_world()
	if bridge == null:
		return null
	var container_id := "%s.inventory" % actor_id
	if bridge.has_method("get_actor_inventory_container_id"):
		container_id = str(bridge.call("get_actor_inventory_container_id", actor_id))
	var existing = _models_by_container_id.get(container_id)
	if _is_inventory_model(existing):
		existing.refresh()
		return existing
	var model = GECS_INVENTORY_VIEW_MODEL_SCRIPT.new()
	model.setup(bridge, actor_id, container_id)
	_models_by_container_id[container_id] = model
	return model


func _on_inventory_window_close_requested(inventory_owner) -> void:
	var model = _inventory_model(inventory_owner)
	if model == null:
		return
	var window = _windows_by_container_id.get(model.container_id)
	var closing_primary: bool = window == primary_character_window
	_close_inventory_window(window)
	if closing_primary:
		_close_inventory_window(secondary_inventory_window)
	_layout_inventory_windows()


func _close_inventory_window(window) -> void:
	if not _is_live_window(window):
		return
	var inventory_owner = window.inventory_owner
	if _is_inventory_model(inventory_owner):
		_windows_by_container_id.erase(inventory_owner.container_id)
	if window == primary_character_window:
		primary_character_window = null
	if window == secondary_inventory_window:
		secondary_inventory_window = null
	(window as Node).queue_free()


func _close_all_inventory_windows() -> void:
	var windows := []
	for window in _windows_by_container_id.values():
		if _is_live_window(window) and not windows.has(window):
			windows.append(window)
	for window in windows:
		_close_inventory_window(window)
	_windows_by_container_id.clear()
	primary_character_window = null
	secondary_inventory_window = null


func _has_live_inventory_windows() -> bool:
	if _is_live_window(primary_character_window) or _is_live_window(secondary_inventory_window):
		return true
	for window in _windows_by_container_id.values():
		if _is_live_window(window):
			return true
	return false


func _bind_selection_controller() -> void:
	if not _initialized and root_scene == null:
		return
	if _selection_controller_node != null and is_instance_valid(_selection_controller_node):
		return
	var selection := _selection_controller()
	if selection == null:
		return
	_selection_controller_node = selection
	var selection_callable := Callable(self, "_on_selection_changed")
	if selection.has_signal("selection_changed") and not selection.is_connected("selection_changed", selection_callable):
		selection.connect("selection_changed", selection_callable)


func _on_selection_changed(actor_id: String, _details_snapshot: Dictionary) -> void:
	if not _initialized or not _has_live_inventory_windows():
		return
	var normalized_id := actor_id.strip_edges()
	if normalized_id.is_empty():
		_close_all_inventory_windows()
		return
	if _is_live_window(primary_character_window) and _window_actor_id(primary_character_window) == normalized_id:
		return
	_open_primary_inventory(normalized_id, true)
	_layout_inventory_windows()


func _on_inventory_sort_requested(inventory_owner) -> void:
	var model = _inventory_model(inventory_owner)
	if model == null:
		return
	_queue_inventory_command({"action": "sort_container", "container_id": model.container_id})


func _on_inventory_transfer_requested(source_owner, target_owner, entry, target_cell: Vector2i) -> void:
	var source = _inventory_model(source_owner)
	var target = _inventory_model(target_owner)
	if source == null or target == null or entry == null:
		return
	if _owners_too_far(source, target):
		_show_floating_notice("Too far away")
		return
	if _try_deposit_entry_into_pouch(source, target, entry, target_cell):
		return
	_queue_inventory_command({
		"action": "move_stack",
		"source_stack_id": str(entry.stack_id),
		"target_container_id": target.container_id,
		"target_cell": target_cell,
	})


func _on_inventory_quick_transfer_requested(source_owner, entry) -> void:
	var source = _inventory_model(source_owner)
	if source == null or entry == null:
		return
	var target_window := _first_other_inventory_window(source)
	if target_window == null:
		return
	var target = _inventory_model(target_window.inventory_owner)
	if target == null or _owners_too_far(source, target):
		_show_floating_notice("Too far away")
		return
	var target_cell: Vector2i = target.inventory.find_first_space(entry.definition)
	if target_cell == Vector2i(-1, -1):
		_show_floating_notice("No room")
		return
	_queue_inventory_command({
		"action": "move_stack",
		"source_stack_id": str(entry.stack_id),
		"target_container_id": target.container_id,
		"target_cell": target_cell,
	})


func _on_inventory_item_action_requested(inventory_owner, entry, action: String) -> void:
	var model = _inventory_model(inventory_owner)
	if model == null or entry == null:
		return
	if action == "eat":
		_queue_inventory_command({"action": "consume_stack_item", "stack_id": str(entry.stack_id), "actor_id": model.actor_id, "item_action": "eat"})
		return
	if action.begins_with("take_silver_"):
		_queue_inventory_command({"action": "take_silver_from_pouch", "stack_id": str(entry.stack_id), "amount": _silver_take_amount(action, model.inventory.get_entry_contained_item_count(entry, InventoryData.SILVER_ITEM))})


func _on_inventory_equip_requested(source_owner, entry, target_owner, slot_name: String) -> void:
	var target = _inventory_model(target_owner)
	if target == null or entry == null:
		return
	var source = _inventory_model(source_owner)
	if source != null and _owners_too_far(source, target):
		_show_floating_notice("Too far away")
		return
	_queue_inventory_command({"action": "equip_stack", "source_stack_id": str(entry.stack_id), "target_actor_id": target.actor_id, "slot_name": slot_name})


func _on_equipment_transfer_requested(source_owner, source_slot_name: String, target_owner, target_slot_name: String) -> void:
	var source = _inventory_model(source_owner)
	var target = _inventory_model(target_owner)
	if source == null or target == null:
		return
	if source != target and _owners_too_far(source, target):
		_show_floating_notice("Too far away")
		return
	_queue_inventory_command({"action": "transfer_equipment", "source_actor_id": source.actor_id, "source_slot_name": source_slot_name, "target_actor_id": target.actor_id, "target_slot_name": target_slot_name})


func _on_inventory_unequip_requested(source_owner, slot_name: String, target_owner, target_cell: Vector2i) -> void:
	var source = _inventory_model(source_owner)
	var target = _inventory_model(target_owner)
	if source == null or target == null:
		return
	if source != target and _owners_too_far(source, target):
		_show_floating_notice("Too far away")
		return
	_queue_inventory_command({"action": "unequip_slot", "actor_id": source.actor_id, "slot_name": slot_name, "target_container_id": target.container_id, "target_cell": target_cell})


func _on_inventory_item_drop_requested(source_owner, entry) -> void:
	var source = _inventory_model(source_owner)
	if source == null or entry == null:
		return
	_queue_inventory_command({"action": "drop_stack", "stack_id": str(entry.stack_id), "world_position": source.get_inventory_world_position()})


func _on_inventory_equipment_drop_requested(source_owner, slot_name: String) -> void:
	var source = _inventory_model(source_owner)
	if source == null:
		return
	_queue_inventory_command({"action": "drop_equipment", "actor_id": source.actor_id, "slot_name": slot_name, "world_position": source.get_inventory_world_position()})


func _on_cursor_item_place_requested(data: Dictionary, _target_owner, _target_cell: Vector2i) -> void:
	_keep_cursor_drag(data)


func _on_cursor_item_equip_requested(data: Dictionary, _target_owner, _slot_name: String) -> void:
	_keep_cursor_drag(data)


func _on_cursor_item_dropped_outside(_source_owner, _definition: ItemDefinition, _count: int, _contained_item_counts: Dictionary = {}, _metadata: Dictionary = {}) -> void:
	_show_floating_notice("Cannot drop cursor item")


func _try_deposit_entry_into_pouch(_source, target, entry, target_cell: Vector2i) -> bool:
	var target_entry = target.inventory.get_entry_at_cell(target_cell)
	if target_entry == null or not target.inventory.is_entry_currency_container(target_entry, InventoryData.SILVER_ITEM):
		return false
	_queue_inventory_command({"action": "deposit_silver_into_pouch", "source_stack_id": str(entry.stack_id), "target_stack_id": str(target_entry.stack_id)})
	return true


func _queue_inventory_command(command: Dictionary) -> void:
	var runner := _inventory_runner()
	if runner != null and runner.has_method("queue_command"):
		runner.call("queue_command", command)
	else:
		var sim := _inventory_sim_controller()
		if sim != null and sim.has_method("apply_sim_commands"):
			sim.call("apply_sim_commands", [command])
	_refresh_pending = true


func _refresh_open_windows() -> void:
	var stale_keys: Array[String] = []
	for container_id_value in _windows_by_container_id.keys():
		var container_id := str(container_id_value)
		var window = _windows_by_container_id[container_id_value]
		if not _is_live_window(window):
			stale_keys.append(container_id)
			continue
		var model = _inventory_model((window as InventoryWindow).inventory_owner)
		if model != null:
			model.refresh()
			(window as InventoryWindow).refresh()
	for key in stale_keys:
		_windows_by_container_id.erase(key)


func _first_other_inventory_window(source) -> InventoryWindow:
	for window in [primary_character_window, secondary_inventory_window]:
		if _is_live_window(window) and (window as InventoryWindow).inventory_owner != source:
			return window as InventoryWindow
	for window in _windows_by_container_id.values():
		if _is_live_window(window) and (window as InventoryWindow).inventory_owner != source:
			return window as InventoryWindow
	return null


func _layout_inventory_windows() -> void:
	var primary_window = primary_character_window if _is_live_window(primary_character_window) else null
	var secondary_window = secondary_inventory_window if _is_live_window(secondary_inventory_window) else null
	if primary_window == null and secondary_window == null:
		return
	_fit_inventory_window(primary_window)
	_fit_inventory_window(secondary_window)
	var viewport_size := inventory_window_layer.get_viewport_rect().size
	if primary_window != null:
		primary_window.position = _clamp_window_position(primary_window, Vector2(WINDOW_EDGE_PADDING, WINDOW_TOP_PADDING), viewport_size)
	if secondary_window != null:
		var secondary_position := _secondary_window_position(primary_window, secondary_window, viewport_size)
		secondary_window.position = _clamp_window_position(secondary_window, secondary_position, viewport_size)


func _fit_inventory_window(window) -> void:
	if _is_live_window(window) and window.has_method("fit_to_content"):
		window.fit_to_content()


func _secondary_window_position(primary_window, secondary_window, viewport_size: Vector2) -> Vector2:
	if primary_window == null:
		return Vector2(maxf(WINDOW_EDGE_PADDING, viewport_size.x - secondary_window.size.x - WINDOW_EDGE_PADDING), WINDOW_TOP_PADDING)
	var candidates: Array[Vector2] = [
		Vector2(primary_window.position.x + primary_window.size.x + WINDOW_GAP, primary_window.position.y),
		Vector2(maxf(WINDOW_EDGE_PADDING, viewport_size.x - secondary_window.size.x - WINDOW_EDGE_PADDING), primary_window.position.y),
		Vector2(primary_window.position.x, primary_window.position.y + primary_window.size.y + WINDOW_GAP),
		Vector2(primary_window.position.x, primary_window.position.y - secondary_window.size.y - WINDOW_GAP),
	]
	var primary_rect := Rect2(primary_window.position, primary_window.size)
	for candidate in candidates:
		var clamped := _clamp_window_position(secondary_window, candidate, viewport_size)
		if not primary_rect.intersects(Rect2(clamped, secondary_window.size)):
			return clamped
	return candidates[0]


func _clamp_window_position(window, target_position: Vector2, viewport_size: Vector2) -> Vector2:
	var max_x := maxf(0.0, viewport_size.x - window.size.x)
	var max_y := maxf(0.0, viewport_size.y - window.size.y)
	return Vector2(clampf(target_position.x, 0.0, max_x), clampf(target_position.y, 0.0, max_y))


func _ensure_cursor_item_drag_source() -> void:
	if cursor_item_drag_source != null and is_instance_valid(cursor_item_drag_source):
		return
	cursor_item_drag_source = CURSOR_ITEM_DRAG_SOURCE_SCRIPT.new()
	cursor_item_drag_source.name = "CursorItemDragSource"
	inventory_window_layer.add_child(cursor_item_drag_source)
	cursor_item_drag_source.set_anchors_preset(Control.PRESET_FULL_RECT)
	cursor_item_drag_source.item_dropped_outside.connect(_on_cursor_item_dropped_outside)


func _keep_cursor_drag(data: Dictionary) -> void:
	var source = data.get("cursor_source", null)
	if source != null and source.has_method("keep_drag"):
		source.keep_drag(int(data.get("cursor_drag_id", 0)))


func _owners_too_far(source, target) -> bool:
	return source != null and target != null and source.get_inventory_world_position().distance_to(target.get_inventory_world_position()) > 5.0


func _silver_take_amount(action: String, available: int) -> int:
	if available <= 0:
		return 0
	match action:
		"take_silver_1":
			return min(1, available)
		"take_silver_5":
			return min(5, available)
		"take_silver_10":
			return min(10, available)
		"take_silver_half":
			return min(available, max(1, int(floor(float(available) * 0.5))))
		"take_silver_quarter":
			return min(available, max(1, int(floor(float(available) * 0.25))))
		_:
			return 0


func _show_floating_notice(message: String) -> void:
	if floating_notice != null and floating_notice.has_method("show_message"):
		floating_notice.show_message(message)


func _selected_actor_ids() -> Array[String]:
	var selection := _selection_controller()
	if selection != null and selection.has_method("get_selected_actor_ids"):
		return selection.call("get_selected_actor_ids")
	if selection != null and selection.has_method("get_selected_actor_id"):
		var selected_id := str(selection.call("get_selected_actor_id"))
		return [selected_id] if not selected_id.is_empty() else []
	return []


func _selection_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldSelectionController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_selection_controller") if is_inside_tree() else null


func _get_gecs_world() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null


func _inventory_runner() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldInventoryFixedTickRunner")
		if local != null:
			return local
	return null


func _inventory_sim_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldInventorySimController")
		if local != null:
			return local
	return null


func _is_live_window(window) -> bool:
	return window != null and is_instance_valid(window) and not (window as Node).is_queued_for_deletion()


func _window_actor_id(window) -> String:
	if not _is_live_window(window):
		return ""
	var model = _inventory_model((window as InventoryWindow).inventory_owner)
	return model.actor_id if model != null else ""


func _inventory_model(value):
	if value != null and value.has_method("get_inventory_for_display") and value.has_method("get_stack_snapshot"):
		return value
	return null


func _is_inventory_model(value) -> bool:
	return _inventory_model(value) != null
