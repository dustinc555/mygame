extends Node

class_name PartyInventoryController

const SERVICE_ID := &"party_inventory"

const INVENTORY_WINDOW_SCENE = preload("res://features/ui/projection/inventory_window.tscn")
const WORLD_ITEM_SCENE = preload("res://features/world/projection/items/world_item.tscn")
const CURSOR_ITEM_DRAG_SOURCE_SCRIPT = preload("res://features/ui/projection/cursor_item_drag_source.gd")
const SILVER_ITEM = preload("res://features/inventory/resources/items/silver.tres")
const SILVER_POUCH_ITEM = preload("res://features/inventory/resources/items/silver_pouch.tres")
const WINDOW_EDGE_PADDING := 36.0
const WINDOW_TOP_PADDING := 160.0
const WINDOW_GAP := 24.0
const WORLD_ITEM_DROP_DISTANCE := 0.9
const WORLD_ITEM_STACK_RADIUS := 0.2
const WORLD_ITEM_GROUND_RAY_UP := 3.0
const WORLD_ITEM_GROUND_RAY_DOWN := 6.0
const WORLD_ITEM_GROUND_RAY_MAX_SKIPS := 12
const META_DURABLE_STACK_ID := "_durable_stack_id"

@export var inventory_toggle_key := KEY_I

var open_inventory_windows: Dictionary = {}
var primary_character_window: InventoryWindow
var secondary_inventory_window: InventoryWindow
var root_scene: Node
var _context: BootstrapContext
var hud_layer: CanvasLayer
var party_manager: PartyManager
var inventory_window_layer: Control
var floating_notice
var cursor_item_drag_source
var _initialized := false


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	hud_layer = context.hud_layer
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	add_to_group("party_inventory_controller")
	if root_scene != null:
		if hud_layer == null and root_scene != null:
			hud_layer = root_scene.get_node_or_null("GameHUD")
		_do_initialize()


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	party_manager = root_scene.get_node("PartyManager")
	if hud_layer == null:
		hud_layer = root_scene.get_node_or_null("GameHUD")
	inventory_window_layer = hud_layer.get_node("InventoryWindowLayer")
	floating_notice = hud_layer.get_node_or_null("FloatingNotice")
	_ensure_cursor_item_drag_source()
	_initialized = true


func _ensure_cursor_item_drag_source() -> void:
	if cursor_item_drag_source != null and is_instance_valid(cursor_item_drag_source):
		return
	cursor_item_drag_source = CURSOR_ITEM_DRAG_SOURCE_SCRIPT.new()
	cursor_item_drag_source.name = "CursorItemDragSource"
	inventory_window_layer.add_child(cursor_item_drag_source)
	cursor_item_drag_source.set_anchors_preset(Control.PRESET_FULL_RECT)
	cursor_item_drag_source.item_dropped_outside.connect(_on_cursor_item_dropped_outside)


func _unhandled_input(event: InputEvent) -> void:
	if not _initialized:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == inventory_toggle_key:
		open_selected_inventory()


func _process(_delta: float) -> void:
	_enforce_open_inventory_context()


func open_selected_inventory() -> void:
	if party_manager.selected_members.is_empty():
		return
	var selected_member = party_manager.selected_members[0]
	if _is_live_window(primary_character_window) and primary_character_window.inventory_owner == selected_member:
		_close_inventory_window(primary_character_window)
		_close_inventory_window(secondary_inventory_window)
		return
	_open_primary_inventory(selected_member, true)


func open_inventory_for_member(member: WorldActor) -> void:
	_open_primary_inventory(member, true)


func open_inventory_for_owner(inventory_owner) -> void:
	if inventory_owner == null:
		return
	if _owner_is_primary_character(inventory_owner):
		_open_primary_inventory(inventory_owner, true)
		return
	var focused_owner = _get_focused_character_owner()
	if focused_owner != null and focused_owner != inventory_owner:
		open_inventory_pair(focused_owner, inventory_owner)
		return
	_open_secondary_inventory(inventory_owner)


func open_inventory_pair(primary_owner, secondary_owner) -> void:
	if primary_owner == null:
		return
	if secondary_owner == null or secondary_owner == primary_owner:
		_open_primary_inventory(primary_owner, true)
		return
	if _open_primary_inventory(primary_owner, false) == null:
		return
	_open_secondary_inventory(secondary_owner)


func _open_primary_inventory(inventory_owner, close_secondary := true):
	if inventory_owner == null:
		return null
	if _is_live_window(secondary_inventory_window) and secondary_inventory_window.inventory_owner == inventory_owner:
		_close_inventory_window(secondary_inventory_window)
	if _is_live_window(primary_character_window) and primary_character_window.inventory_owner != inventory_owner:
		_close_inventory_window(primary_character_window)
	if close_secondary:
		_close_inventory_window(secondary_inventory_window)
	primary_character_window = _ensure_inventory_window(inventory_owner)
	_layout_inventory_windows()
	return primary_character_window


func _open_secondary_inventory(inventory_owner):
	if inventory_owner == null:
		return null
	if _is_live_window(primary_character_window) and primary_character_window.inventory_owner == inventory_owner:
		secondary_inventory_window = null
		_layout_inventory_windows()
		return primary_character_window
	if _is_live_window(secondary_inventory_window) and secondary_inventory_window.inventory_owner != inventory_owner:
		_close_inventory_window(secondary_inventory_window)
	secondary_inventory_window = _ensure_inventory_window(inventory_owner)
	_layout_inventory_windows()
	return secondary_inventory_window


func _ensure_inventory_window(inventory_owner):
	var existing = _get_window_for_owner(inventory_owner)
	if existing != null:
		existing.visible = true
		if existing.has_method("refresh"):
			existing.refresh()
		if existing.has_method("fit_to_content"):
			existing.fit_to_content()
		existing.grab_click_focus()
		inventory_window_layer.move_child(existing, inventory_window_layer.get_child_count() - 1)
		return existing

	var window = INVENTORY_WINDOW_SCENE.instantiate()
	open_inventory_windows[inventory_owner.get_instance_id()] = window
	inventory_window_layer.add_child(window)
	window.setup(inventory_owner)
	if window.has_method("fit_to_content"):
		window.fit_to_content()
	window.close_requested.connect(_on_inventory_window_close_requested)
	window.notice_requested.connect(_show_floating_notice)
	window.transfer_requested.connect(_on_inventory_transfer_requested)
	window.quick_transfer_requested.connect(_on_inventory_quick_transfer_requested)
	window.quick_equip_requested.connect(_on_inventory_quick_equip_requested)
	window.item_action_requested.connect(_on_inventory_item_action_requested)
	window.equip_requested.connect(_on_inventory_equip_requested)
	window.equipment_transfer_requested.connect(_on_equipment_transfer_requested)
	window.unequip_requested.connect(_on_inventory_unequip_requested)
	window.item_drop_requested.connect(_on_inventory_item_drop_requested)
	window.equipment_drop_requested.connect(_on_inventory_equipment_drop_requested)
	window.cursor_item_place_requested.connect(_on_cursor_item_place_requested)
	window.cursor_item_equip_requested.connect(_on_cursor_item_equip_requested)
	window.grab_click_focus()
	return window


func _on_inventory_window_close_requested(inventory_owner) -> void:
	if inventory_owner == null:
		return
	var window = _get_window_for_owner(inventory_owner)
	if window == null:
		return
	var closing_primary: bool = window == primary_character_window
	_close_inventory_window(window)
	if closing_primary:
		_close_inventory_window(secondary_inventory_window)
	_layout_inventory_windows()


func _close_inventory_window(window) -> void:
	if not _is_live_window(window):
		return
	var inventory_owner = window.inventory_owner
	if inventory_owner != null:
		open_inventory_windows.erase(inventory_owner.get_instance_id())
	if window == primary_character_window:
		primary_character_window = null
	if window == secondary_inventory_window:
		secondary_inventory_window = null
	window.queue_free()


func _close_all_inventory_windows() -> void:
	var windows := []
	for window in open_inventory_windows.values():
		if _is_live_window(window) and not windows.has(window):
			windows.append(window)
	if _is_live_window(primary_character_window) and not windows.has(primary_character_window):
		windows.append(primary_character_window)
	if _is_live_window(secondary_inventory_window) and not windows.has(secondary_inventory_window):
		windows.append(secondary_inventory_window)
	for window in windows:
		_close_inventory_window(window)
	open_inventory_windows.clear()
	primary_character_window = null
	secondary_inventory_window = null


func _get_window_for_owner(inventory_owner):
	if inventory_owner == null:
		return null
	var key: int = inventory_owner.get_instance_id()
	var window = open_inventory_windows.get(key)
	if not _is_live_window(window):
		open_inventory_windows.erase(key)
		return null
	return window


func _is_live_window(window) -> bool:
	return window != null and is_instance_valid(window) and not window.is_queued_for_deletion()


func _has_live_inventory_windows() -> bool:
	if _is_live_window(primary_character_window) or _is_live_window(secondary_inventory_window):
		return true
	for window in open_inventory_windows.values():
		if _is_live_window(window):
			return true
	return false


func _enforce_open_inventory_context() -> void:
	if not _has_live_inventory_windows():
		return
	if _open_inventory_context_has_combat():
		_close_all_inventory_windows()
		return
	if _open_inventory_context_is_out_of_range():
		_close_all_inventory_windows()


func _open_inventory_context_is_out_of_range() -> bool:
	if _is_live_window(primary_character_window) and _is_live_window(secondary_inventory_window):
		return _owners_too_far(primary_character_window.inventory_owner, secondary_inventory_window.inventory_owner)
	if _is_live_window(secondary_inventory_window):
		var focused_owner = _get_focused_character_owner()
		return focused_owner != null and focused_owner != secondary_inventory_window.inventory_owner and _owners_too_far(focused_owner, secondary_inventory_window.inventory_owner)
	return false


func _open_inventory_context_has_combat() -> bool:
	for inventory_owner in _get_live_inventory_owners():
		if _inventory_owner_is_in_combat(inventory_owner):
			return true
	if party_manager != null:
		for member in party_manager.party_members:
			if _inventory_owner_is_in_combat(member):
				return true
	return false


func _get_live_inventory_owners() -> Array:
	var owners := []
	for window in open_inventory_windows.values():
		if _is_live_window(window) and window.inventory_owner != null and not owners.has(window.inventory_owner):
			owners.append(window.inventory_owner)
	if _is_live_window(primary_character_window) and primary_character_window.inventory_owner != null and not owners.has(primary_character_window.inventory_owner):
		owners.append(primary_character_window.inventory_owner)
	if _is_live_window(secondary_inventory_window) and secondary_inventory_window.inventory_owner != null and not owners.has(secondary_inventory_window.inventory_owner):
		owners.append(secondary_inventory_window.inventory_owner)
	return owners


func _inventory_owner_is_in_combat(inventory_owner) -> bool:
	if inventory_owner == null:
		return false
	if inventory_owner.has_method("is_in_combat") and bool(inventory_owner.is_in_combat()):
		return true
	var actor = _get_inventory_owner_actor(inventory_owner)
	return actor != inventory_owner and actor != null and actor.has_method("is_in_combat") and bool(actor.is_in_combat())


func _get_inventory_owner_actor(inventory_owner):
	if inventory_owner is WorldActor:
		return inventory_owner
	if inventory_owner != null and inventory_owner.has_method("get_owner_character"):
		var owner_character = inventory_owner.get_owner_character()
		if owner_character != null:
			return owner_character
	if inventory_owner != null and inventory_owner.has_method("get_explicit_owner_character"):
		var explicit_owner = inventory_owner.get_explicit_owner_character()
		if explicit_owner != null:
			return explicit_owner
	return null


func _owner_is_primary_character(inventory_owner) -> bool:
	return inventory_owner is WorldActor and inventory_owner.is_player_party_member()


func _get_focused_character_owner():
	if party_manager != null and not party_manager.selected_members.is_empty():
		return party_manager.selected_members[0]
	if _is_live_window(primary_character_window):
		return primary_character_window.inventory_owner
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


func _on_inventory_transfer_requested(source_owner, target_owner, entry, target_cell: Vector2i) -> void:
	if source_owner == null or target_owner == null or entry == null:
		return
	if source_owner != target_owner and not _can_transfer_between_owners(source_owner, target_owner):
		_show_floating_notice("Job inventory is locked")
		return
	if _try_deposit_entry_into_pouch(source_owner, target_owner, entry, target_cell):
		return
	if source_owner == target_owner:
		var same_owner_inventory = _get_owner_inventory(source_owner)
		if same_owner_inventory != null:
			same_owner_inventory.move_entry(entry, target_cell)
		return
	var source_inventory = _get_owner_inventory(source_owner)
	var target_inventory = _get_owner_inventory(target_owner)
	if source_inventory == null or target_inventory == null:
		return
	var target_window = _get_window_for_owner(target_owner)
	if _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return
	if _try_handle_trade(source_owner, target_owner, entry, target_cell):
		return
	if source_owner != target_owner and _entry_is_silver_pouch(source_inventory, entry):
		_show_floating_notice("Drop onto pouch")
		return
	if source_owner.has_method("can_release_inventory_entry") and source_owner.has_method("release_inventory_entry"):
		var transfer_metadata := _stolen_take_metadata(source_owner, target_owner, entry.metadata)
		var can_release := bool(source_owner.call("can_release_inventory_entry_with_metadata", entry, target_inventory, transfer_metadata)) \
				if source_owner.has_method("can_release_inventory_entry_with_metadata") else bool(source_owner.call("can_release_inventory_entry", entry, target_inventory))
		if not can_release:
			_show_floating_notice("Not enough room")
			return
		if not _authorize_container_take(source_owner, target_owner):
			return
		var released := bool(source_owner.call("release_inventory_entry_with_metadata", entry, target_inventory, transfer_metadata)) \
				if source_owner.has_method("release_inventory_entry_with_metadata") else bool(source_owner.call("release_inventory_entry", entry, target_inventory))
		if released:
			if target_window != null:
				target_window.clear_warning()
		return
	if target_owner.has_method("can_receive_inventory_entry") and target_owner.has_method("receive_inventory_entry"):
		var transfer_metadata := _stolen_take_metadata(source_owner, target_owner, entry.metadata)
		var can_receive := bool(target_owner.call("can_receive_inventory_entry_with_metadata", entry, transfer_metadata)) \
				if target_owner.has_method("can_receive_inventory_entry_with_metadata") else bool(target_owner.call("can_receive_inventory_entry", entry))
		if not can_receive:
			_show_floating_notice("Cannot store that here")
			return
		if not _authorize_container_take(source_owner, target_owner):
			return
		var received := bool(target_owner.call("receive_inventory_entry_with_metadata", source_inventory, entry, transfer_metadata)) \
				if target_owner.has_method("receive_inventory_entry_with_metadata") else bool(target_owner.call("receive_inventory_entry", source_inventory, entry))
		if received:
			if target_window != null:
				target_window.clear_warning()
		return
	# Roll the theft and mark the goods stolen only for a move that will
	# actually commit; a full or overweight target must not fire witnesses
	# or taint an item that stays in the source container.
	if not source_inventory.can_move_entry_to_inventory(entry, target_inventory, target_cell):
		return
	if not _authorize_container_take(source_owner, target_owner):
		return
	entry.metadata = _stolen_take_metadata(source_owner, target_owner, entry.metadata)

	if source_inventory.move_entry_to_inventory(entry, target_inventory, target_cell):
		if target_window != null:
			target_window.clear_warning()


func _on_inventory_quick_transfer_requested(source_owner, entry) -> void:
	if source_owner == null or entry == null:
		return
	var target_window = _first_other_inventory_window(source_owner)
	if target_window == null:
		return
	var target_owner = target_window.inventory_owner
	if target_owner == null:
		return
	if not _can_transfer_between_owners(source_owner, target_owner):
		_show_floating_notice("Job inventory is locked")
		return
	if _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return
	var source_inventory = _get_owner_inventory(source_owner)
	var target_inventory = _get_owner_inventory(target_owner)
	if source_inventory == null or target_inventory == null:
		return
	var target_cell: Vector2i = target_inventory.find_first_space(entry.definition)
	if target_cell != Vector2i(-1, -1) and _try_handle_trade(source_owner, target_owner, entry, target_cell):
		return
	if source_owner != target_owner and _entry_is_silver_pouch(source_inventory, entry):
		_show_floating_notice("Drop onto pouch")
		return
	if source_owner.has_method("can_release_inventory_entry") and source_owner.has_method("release_inventory_entry"):
		var transfer_metadata := _stolen_take_metadata(source_owner, target_owner, entry.metadata)
		var can_release := bool(source_owner.call("can_release_inventory_entry_with_metadata", entry, target_inventory, transfer_metadata)) \
				if source_owner.has_method("can_release_inventory_entry_with_metadata") else bool(source_owner.call("can_release_inventory_entry", entry, target_inventory))
		if not can_release:
			_show_floating_notice("Not enough room")
			return
		if not _authorize_container_take(source_owner, target_owner):
			return
		if source_owner.has_method("release_inventory_entry_with_metadata"):
			source_owner.call("release_inventory_entry_with_metadata", entry, target_inventory, transfer_metadata)
		else:
			source_owner.call("release_inventory_entry", entry, target_inventory)
		return
	if target_owner.has_method("can_receive_inventory_entry") and target_owner.has_method("receive_inventory_entry"):
		var transfer_metadata := _stolen_take_metadata(source_owner, target_owner, entry.metadata)
		var can_receive := bool(target_owner.call("can_receive_inventory_entry_with_metadata", entry, transfer_metadata)) \
				if target_owner.has_method("can_receive_inventory_entry_with_metadata") else bool(target_owner.call("can_receive_inventory_entry", entry))
		if not can_receive:
			_show_floating_notice("Cannot store that here")
			return
		if not _authorize_container_take(source_owner, target_owner):
			return
		if target_owner.has_method("receive_inventory_entry_with_metadata"):
			target_owner.call("receive_inventory_entry_with_metadata", source_inventory, entry, transfer_metadata)
		else:
			target_owner.call("receive_inventory_entry", source_inventory, entry)
		return
	if target_cell == Vector2i(-1, -1):
		return
	# Theft roll and stolen metadata only for a move that will commit.
	if not source_inventory.can_move_entry_to_inventory(entry, target_inventory, target_cell):
		return
	if not _authorize_container_take(source_owner, target_owner):
		return
	entry.metadata = _stolen_take_metadata(source_owner, target_owner, entry.metadata)
	source_inventory.move_entry_to_inventory(entry, target_inventory, target_cell)


func _first_other_inventory_window(source_owner):
	if _is_live_window(primary_character_window) and primary_character_window.inventory_owner != source_owner:
		return primary_character_window
	if _is_live_window(secondary_inventory_window) and secondary_inventory_window.inventory_owner != source_owner:
		return secondary_inventory_window
	for key in open_inventory_windows.keys():
		var window = open_inventory_windows[key]
		if _is_live_window(window) and window.inventory_owner != source_owner:
			return window
	return null


func _show_floating_notice(message: String) -> void:
	if floating_notice != null and floating_notice.has_method("show_message"):
		floating_notice.show_message(message)


func _owners_too_far(source_owner, target_owner) -> bool:
	if source_owner == null or target_owner == null:
		return false
	if source_owner.has_method("get_inventory_world_position") and target_owner.has_method("get_inventory_world_position"):
		return source_owner.get_inventory_world_position().distance_to(target_owner.get_inventory_world_position()) > 5.0
	return false


func _on_inventory_item_action_requested(inventory_owner, entry, action: String) -> void:
	if inventory_owner == null or entry == null:
		return
	if action == "take_all":
		_take_all_from_storage(inventory_owner, entry)
		return
	if action == "eat" and inventory_owner.has_method("eat_item"):
		inventory_owner.eat_item(entry.definition)
		return
	if action == "read":
		var read_controller := _context.get_optional(&"item_read")
		if read_controller != null:
			read_controller.read_inventory_item(_get_inventory_owner_actor(inventory_owner), entry)
		return
	if action.begins_with("take_silver_"):
		_take_silver_from_pouch(inventory_owner, entry, action)


func _take_all_from_storage(source_owner, entry) -> void:
	if source_owner == null or entry == null or not source_owner.has_method("release_inventory_entry_count_with_metadata"):
		return
	var target_window = _first_other_inventory_window(source_owner)
	var target_owner = target_window.inventory_owner if target_window != null else _get_focused_character_owner()
	if target_owner == null or target_owner == source_owner or not _can_transfer_between_owners(source_owner, target_owner) \
			or _owners_too_far(source_owner, target_owner):
		return
	var target_inventory = _get_owner_inventory(target_owner)
	if target_inventory == null:
		return
	var transfer_metadata := _stolen_take_metadata(source_owner, target_owner, entry.metadata)
	var can_take_one := bool(source_owner.call("can_release_inventory_entry_with_metadata", entry, target_inventory, transfer_metadata)) \
			if source_owner.has_method("can_release_inventory_entry_with_metadata") else false
	if not can_take_one or not _authorize_container_take(source_owner, target_owner):
		return
	var taken := int(source_owner.call(
		"release_inventory_entry_count_with_metadata",
		entry,
		target_inventory,
		int(entry.count),
		transfer_metadata
	))
	if taken > 0:
		_refresh_inventory_windows_for(source_owner, target_owner)


func _on_inventory_equip_requested(source_owner, entry, target_owner, slot_name: String) -> void:
	if source_owner == null or target_owner == null or entry == null:
		return
	var target_equipment := _get_owner_equipment(target_owner)
	if target_equipment == null or not target_equipment.can_equip_item_to_slot(entry.definition, slot_name):
		_show_floating_notice("Cannot equip")
		return
	if source_owner != target_owner:
		if not _can_transfer_between_owners(source_owner, target_owner):
			_show_floating_notice("Job inventory is locked")
			return
		if _owners_too_far(source_owner, target_owner):
			_show_floating_notice("Too far away")
			return
	var source_inventory = _get_owner_inventory(source_owner)
	var target_inventory = _get_owner_inventory(target_owner)
	if source_inventory == null or target_inventory == null or not source_inventory.entries.has(entry):
		return
	var replaced_item: ItemDefinition = target_equipment.get_equipped_item(slot_name)
	var replaced_stack_id := target_equipment.get_equipped_stack_id(slot_name)
	if source_owner == target_owner and replaced_item != null \
			and not _can_store_replaced_after_entry_removal(source_inventory, entry, replaced_item, replaced_stack_id):
		_show_floating_notice("No room for equipped item")
		return
	if not _try_pay_for_equipment_transfer(source_owner, target_owner, entry):
		return
	var replaced = target_equipment.equip_item_to_slot(entry.definition, slot_name, str(entry.stack_id))
	if not source_inventory.remove_entry(entry):
		target_equipment.unequip_item_from_slot(slot_name)
		if replaced != null:
			target_equipment.equip_item_to_slot(replaced, slot_name, replaced_stack_id)
		source_inventory.changed.emit()
		return
	if replaced != null and not _try_store_replaced_equipment(source_owner, target_owner, replaced, replaced_stack_id):
		var replaced_snapshot := _stack_snapshot(replaced_stack_id)
		_start_cursor_item_drag(target_owner, replaced, 1, replaced_snapshot.get("contained_item_counts", {}), replaced_snapshot.get("metadata", {}), replaced_stack_id)
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_inventory_quick_equip_requested(inventory_owner, entry) -> void:
	if inventory_owner == null or entry == null or entry.definition == null:
		return
	if _first_other_inventory_window(inventory_owner) != null:
		_on_inventory_quick_transfer_requested(inventory_owner, entry)
		return
	var equipment := _get_owner_equipment(inventory_owner)
	if equipment == null:
		return
	var slot_name := _preferred_compatible_equipment_slot(inventory_owner, equipment, entry.definition)
	if slot_name.is_empty():
		return
	_on_inventory_equip_requested(inventory_owner, entry, inventory_owner, slot_name)


func _preferred_compatible_equipment_slot(inventory_owner, equipment, definition: ItemDefinition) -> String:
	if definition == null or equipment == null:
		return ""
	var candidates: Array[String] = []
	if not definition.equip_slot.is_empty():
		candidates.append(definition.equip_slot)
	for slot_value in definition.alternate_equip_slots:
		var alternate_slot := str(slot_value)
		if not alternate_slot.is_empty() and not candidates.has(alternate_slot):
			candidates.append(alternate_slot)
	if inventory_owner != null and inventory_owner.has_method("get_equipment_slot_names"):
		for slot_value in inventory_owner.get_equipment_slot_names():
			var actor_slot := str(slot_value)
			if not candidates.has(actor_slot):
				candidates.append(actor_slot)
	for candidate in candidates:
		if equipment.can_equip_item_to_slot(definition, candidate):
			return candidate
	return ""


func _can_store_replaced_after_entry_removal(inventory, incoming_entry, replaced: ItemDefinition, replaced_stack_id: String) -> bool:
	if inventory == null or incoming_entry == null or replaced == null:
		return false
	var snapshot := _stack_snapshot(replaced_stack_id)
	var replaced_count := int(snapshot.get("count", 1))
	var replaced_contents: Dictionary = snapshot.get("contained_item_counts", {})
	if inventory.use_weight:
		var incoming_weight: float = inventory.get_item_weight(incoming_entry.definition, int(incoming_entry.count), incoming_entry.contained_item_counts)
		var replaced_weight: float = inventory.get_item_weight(replaced, replaced_count, replaced_contents)
		if inventory.get_total_weight() - incoming_weight + replaced_weight > inventory.max_weight:
			return false
	for y in range(inventory.rows - replaced.grid_size.y + 1):
		for x in range(inventory.columns - replaced.grid_size.x + 1):
			if inventory.can_place_item(replaced, Vector2i(x, y), incoming_entry):
				return true
	return false


func _on_equipment_transfer_requested(source_owner, source_slot_name: String, target_owner, target_slot_name: String) -> void:
	if source_owner == null or target_owner == null:
		return
	if source_owner != target_owner and _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return
	var source_equipment := _get_owner_equipment(source_owner)
	var target_equipment := _get_owner_equipment(target_owner)
	if source_equipment == null or target_equipment == null:
		return
	var moving_item: ItemDefinition = source_equipment.get_equipped_item(source_slot_name)
	if moving_item == null or not target_equipment.can_equip_item_to_slot(moving_item, target_slot_name):
		_show_floating_notice("Cannot equip")
		return
	if source_owner == target_owner and source_slot_name == target_slot_name:
		return
	var target_previous: ItemDefinition = target_equipment.get_equipped_item(target_slot_name)
	var moving_stack_id := source_equipment.get_equipped_stack_id(source_slot_name)
	var target_previous_stack_id := target_equipment.get_equipped_stack_id(target_slot_name)
	var can_swap_back: bool = target_previous != null and source_equipment.can_equip_item_to_slot(target_previous, source_slot_name)
	var batched_equipment := _begin_equipment_update_batch(source_equipment, target_equipment)
	source_equipment.unequip_item_from_slot(source_slot_name)
	var replaced = target_equipment.equip_item_to_slot(moving_item, target_slot_name, moving_stack_id)
	if replaced != null:
		if can_swap_back:
			source_equipment.equip_item_to_slot(replaced, source_slot_name, target_previous_stack_id)
		else:
			var replaced_snapshot := _stack_snapshot(target_previous_stack_id)
			_start_cursor_item_drag(target_owner, replaced, 1, replaced_snapshot.get("contained_item_counts", {}), replaced_snapshot.get("metadata", {}), target_previous_stack_id)
	_end_equipment_update_batch(batched_equipment)
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_inventory_unequip_requested(source_owner, slot_name: String, target_owner, target_cell: Vector2i) -> void:
	if source_owner == null or target_owner == null:
		return
	if source_owner != target_owner:
		if not _can_transfer_between_owners(source_owner, target_owner):
			_show_floating_notice("Job inventory is locked")
			return
		if _owners_too_far(source_owner, target_owner):
			_show_floating_notice("Too far away")
			return
	var source_equipment := _get_owner_equipment(source_owner)
	if source_equipment == null:
		return
	var item: ItemDefinition = source_equipment.get_equipped_item(slot_name)
	var target_inventory = _get_owner_inventory(target_owner)
	if item == null or target_inventory == null:
		return
	var stack_id := source_equipment.get_equipped_stack_id(slot_name)
	var snapshot := _stack_snapshot(stack_id)
	var item_count := int(snapshot.get("count", 1))
	if target_inventory.has_method("accepts_item_count") and not bool(target_inventory.call("accepts_item_count", item, item_count)):
		_show_floating_notice("Cannot store that here")
		return
	if target_inventory.use_weight and target_inventory.get_total_weight() + item.unit_weight > target_inventory.max_weight:
		_show_floating_notice("Too heavy")
		return
	if not target_inventory.can_place_item(item, target_cell):
		_show_floating_notice("No room")
		return
	var removed: ItemDefinition = source_equipment.unequip_item_from_slot(slot_name)
	if removed == null:
		return
	target_inventory.entries.append(target_inventory.create_entry(
		removed,
		target_cell,
		int(snapshot.get("count", 1)),
		(snapshot.get("contained_item_counts", {}) as Dictionary).duplicate(true),
		(snapshot.get("metadata", {}) as Dictionary).duplicate(true),
		stack_id
	))
	target_inventory.changed.emit()
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_inventory_item_drop_requested(source_owner, entry) -> void:
	if source_owner == null or entry == null:
		return
	var source_inventory = _get_owner_inventory(source_owner)
	if source_inventory == null or not source_inventory.entries.has(entry):
		return
	# Dropping a container's item on the floor is still taking it out.
	if not _authorize_container_take(source_owner, null):
		return
	var contained_item_counts: Dictionary = entry.contained_item_counts.duplicate(true)
	var metadata: Dictionary = _stolen_take_metadata(source_owner, null, entry.metadata.duplicate(true))
	if not source_inventory.remove_entry(entry):
		return
	_spawn_world_item(source_owner, entry.definition, entry.count, contained_item_counts, metadata, entry.stack_id)


func _on_inventory_equipment_drop_requested(source_owner, slot_name: String) -> void:
	var source_equipment := _get_owner_equipment(source_owner)
	if source_equipment == null:
		return
	var stack_id := source_equipment.get_equipped_stack_id(slot_name)
	var snapshot := _stack_snapshot(stack_id)
	var item: ItemDefinition = source_equipment.unequip_item_from_slot(slot_name)
	if item == null:
		return
	_spawn_world_item(source_owner, item, int(snapshot.get("count", 1)), snapshot.get("contained_item_counts", {}), snapshot.get("metadata", {}), stack_id)


func _on_cursor_item_place_requested(data: Dictionary, target_owner, target_cell: Vector2i) -> void:
	var definition: ItemDefinition = data.get("item_definition") as ItemDefinition
	var source_owner = data.get("source_owner", null)
	var count := int(data.get("count", 1))
	if definition == null or target_owner == null or count <= 0:
		_keep_cursor_drag(data)
		return
	if source_owner != null and source_owner != target_owner:
		if not _can_transfer_between_owners(source_owner, target_owner):
			_show_floating_notice("Job inventory is locked")
			_keep_cursor_drag(data)
			return
		if _owners_too_far(source_owner, target_owner):
			_show_floating_notice("Too far away")
			_keep_cursor_drag(data)
			return
	var target_role = _get_merchant_role(target_owner)
	var source_role = _get_merchant_role(source_owner)
	if _try_deposit_cursor_into_pouch(data, target_owner, target_cell):
		_refresh_inventory_windows_for(source_owner, target_owner)
		return
	if target_role != null and source_role == null and source_owner != target_owner:
		if _try_sell_cursor_item(source_owner, target_owner, definition, count, target_cell, target_role, data.get("metadata", {})):
			_consume_cursor_drag(data)
			_refresh_inventory_windows_for(source_owner, target_owner)
		else:
			_keep_cursor_drag(data)
		return
	if source_role != null and target_role == null and source_owner != target_owner:
		_show_floating_notice("Cannot trade")
		_keep_cursor_drag(data)
		return
	if source_owner != null and source_owner != target_owner and _definition_is_silver_pouch(definition):
		_show_floating_notice("Drop onto pouch")
		_keep_cursor_drag(data)
		return
	var target_inventory = _get_owner_inventory(target_owner)
	if target_inventory == null:
		_keep_cursor_drag(data)
		return
	if target_owner.has_method("receive_cursor_item"):
		var transfer_metadata: Dictionary = data.get("metadata", {}).duplicate(true)
		if source_owner != null and source_owner != target_owner:
			transfer_metadata = _stolen_take_metadata(source_owner, target_owner, transfer_metadata)
		if target_owner.has_method("can_receive_cursor_item") and not bool(target_owner.call(
				"can_receive_cursor_item", definition, count, data.get("contained_item_counts", {}), transfer_metadata
		)):
			_show_floating_notice("Cannot store that here")
			_keep_cursor_drag(data)
			return
		if source_owner != null and source_owner != target_owner and not _authorize_container_take(source_owner, target_owner):
			_keep_cursor_drag(data)
			return
		if bool(target_owner.call("receive_cursor_item", definition, count, data.get("contained_item_counts", {}), transfer_metadata)):
			_consume_cursor_drag(data)
			_refresh_inventory_windows_for(source_owner, target_owner)
		else:
			_show_floating_notice("Cannot store that here")
			_keep_cursor_drag(data)
		return
	# Theft roll and stolen metadata only for a placement that will commit;
	# a full or overweight target must not fire witnesses or taint the item.
	if not _can_place_cursor_item_in_inventory(target_inventory, definition, count, target_cell, data.get("contained_item_counts", {})):
		_keep_cursor_drag(data)
		return
	if source_owner != null and source_owner != target_owner:
		if not _authorize_container_take(source_owner, target_owner):
			_keep_cursor_drag(data)
			return
		data["metadata"] = _stolen_take_metadata(source_owner, target_owner, data.get("metadata", {}))
	if not _place_cursor_item_in_inventory(target_inventory, definition, count, target_cell, data.get("contained_item_counts", {}), data.get("metadata", {})):
		_keep_cursor_drag(data)
		return
	_consume_cursor_drag(data)
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_cursor_item_equip_requested(data: Dictionary, target_owner, slot_name: String) -> void:
	var definition: ItemDefinition = data.get("item_definition") as ItemDefinition
	var source_owner = data.get("source_owner", null)
	if definition == null or target_owner == null:
		_keep_cursor_drag(data)
		return
	var target_equipment := _get_owner_equipment(target_owner)
	if target_equipment == null or not target_equipment.can_equip_item_to_slot(definition, slot_name):
		_show_floating_notice("Cannot equip")
		_keep_cursor_drag(data)
		return
	if source_owner != null and source_owner != target_owner:
		if not _can_transfer_between_owners(source_owner, target_owner):
			_show_floating_notice("Job inventory is locked")
			_keep_cursor_drag(data)
			return
		if _owners_too_far(source_owner, target_owner):
			_show_floating_notice("Too far away")
			_keep_cursor_drag(data)
			return
	var incoming_metadata := (data.get("metadata", {}) as Dictionary).duplicate(true)
	var incoming_stack_id := str(incoming_metadata.get(META_DURABLE_STACK_ID, ""))
	var replaced_stack_id := target_equipment.get_equipped_stack_id(slot_name)
	var replaced = target_equipment.equip_item_to_slot(definition, slot_name, incoming_stack_id)
	if replaced != null:
		var replaced_snapshot := _stack_snapshot(replaced_stack_id)
		_replace_cursor_drag(data, target_owner, replaced, 1, replaced_snapshot.get("contained_item_counts", {}), replaced_snapshot.get("metadata", {}), replaced_stack_id)
	else:
		_consume_cursor_drag(data)
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_cursor_item_dropped_outside(source_owner, definition: ItemDefinition, count: int, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}) -> void:
	# The item already left its inventory when the cursor drag began, so a
	# blocked roll cannot put it back — run the roll for its consequences
	# (witnesses, law report) and spawn the item regardless, marked stolen.
	_authorize_container_take(source_owner, null)
	metadata = _stolen_take_metadata(source_owner, null, metadata)
	var stack_id := str(metadata.get(META_DURABLE_STACK_ID, ""))
	metadata.erase(META_DURABLE_STACK_ID)
	_spawn_world_item(source_owner, definition, count, contained_item_counts, metadata, stack_id)


func _get_owner_inventory(inventory_owner):
	if inventory_owner != null and inventory_owner.has_method("get_inventory_for_display"):
		return inventory_owner.get_inventory_for_display()
	if inventory_owner == null:
		return null
	return inventory_owner.inventory


func _get_owner_equipment(inventory_owner) -> EquipmentCapability:
	if inventory_owner == null or not inventory_owner.has_method("get_equipment"):
		return null
	return inventory_owner.get_equipment() as EquipmentCapability


func _refresh_inventory_windows_for(owner_a, owner_b = null) -> void:
	for inventory_owner in [owner_a, owner_b]:
		if inventory_owner == null:
			continue
		var window = open_inventory_windows.get(inventory_owner.get_instance_id())
		if _is_live_window(window) and window.has_method("refresh"):
			window.refresh()


func _spawn_world_item(source_owner, definition: ItemDefinition, count: int, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}, stack_id := "") -> void:
	if root_scene == null or definition == null or count <= 0:
		return
	var drop_position_value = _get_world_drop_position(source_owner)
	if not (drop_position_value is Vector3):
		return
	var requested_drop_position: Vector3 = drop_position_value
	var stack := _get_world_item_stack(requested_drop_position)
	var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	if world_item == null:
		return
	world_item.setup(definition, count, contained_item_counts, stack_id)
	world_item.item_metadata = metadata.duplicate(true)
	root_scene.add_child(world_item)
	world_item.place_bottom_at(stack["position"], float(stack["next_bottom_y"]))
	var lifecycle := _context.get_optional(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
	if lifecycle == null:
		world_item.queue_free()
		return
	var result := lifecycle.submit_world_stack({
		"stack_id": world_item.stack_id,
		"container_id": "world",
		"owner_actor_id": "",
		"item_definition_path": definition.resource_path,
		"count": count,
		"grid_position": Vector2i.ZERO,
		"contained_item_counts": contained_item_counts.duplicate(true),
		"metadata": metadata.duplicate(true),
		"location_kind": "world_loose",
		"world_transform": world_item.global_transform,
		"placement_host_id": "",
		"placement_slot_id": "",
		"location_settlement_id": "",
	})
	if not bool(result.get("accepted", false)):
		world_item.queue_free()


func _get_world_drop_position(source_owner) -> Variant:
	var drop_owner = source_owner if source_owner != null else _get_focused_character_owner()
	if drop_owner == null:
		return null
	var origin := Vector3.ZERO
	if drop_owner.has_method("get_inventory_world_position"):
		origin = drop_owner.get_inventory_world_position()
	elif drop_owner is Node3D:
		origin = (drop_owner as Node3D).global_position
	else:
		return null
	var forward := Vector3.FORWARD
	if drop_owner is Node3D:
		forward = -(drop_owner as Node3D).global_transform.basis.z.normalized()
		if forward.length_squared() <= 0.001:
			forward = Vector3.FORWARD
	var drop_position := origin + forward * WORLD_ITEM_DROP_DISTANCE
	drop_position.y = _get_drop_ground_y(drop_owner, origin, drop_position)
	return drop_position


func _get_drop_ground_y(drop_owner, origin: Vector3, drop_position: Vector3) -> float:
	var world_3d := _get_drop_world_3d(drop_owner)
	if world_3d != null:
		var start := Vector3(drop_position.x, maxf(origin.y, drop_position.y) + WORLD_ITEM_GROUND_RAY_UP, drop_position.z)
		var end := Vector3(drop_position.x, minf(origin.y, drop_position.y) - WORLD_ITEM_GROUND_RAY_DOWN, drop_position.z)
		var excludes := _get_drop_ground_ray_excludes(drop_owner)
		for _attempt in range(WORLD_ITEM_GROUND_RAY_MAX_SKIPS):
			var query := PhysicsRayQueryParameters3D.create(start, end)
			query.exclude = excludes
			var hit := world_3d.direct_space_state.intersect_ray(query)
			if hit.is_empty() or not hit.has("position"):
				break
			var collider: Object = hit.get("collider")
			if not _drop_ground_hit_should_be_skipped(collider):
				return (hit["position"] as Vector3).y
			if collider is CollisionObject3D:
				var rid := (collider as CollisionObject3D).get_rid()
				if not excludes.has(rid):
					excludes.append(rid)
			else:
				break
	if drop_owner != null and drop_owner.has_method("get_collision_bottom_local_y"):
		return origin.y + float(drop_owner.get_collision_bottom_local_y())
	return origin.y


func _get_drop_world_3d(drop_owner) -> World3D:
	if root_scene is Node3D and root_scene.is_inside_tree():
		return (root_scene as Node3D).get_world_3d()
	if drop_owner is Node3D and (drop_owner as Node3D).is_inside_tree():
		return (drop_owner as Node3D).get_world_3d()
	return null


func _get_drop_ground_ray_excludes(drop_owner) -> Array[RID]:
	var excludes: Array[RID] = []
	if drop_owner is CollisionObject3D:
		excludes.append((drop_owner as CollisionObject3D).get_rid())
	if root_scene != null and root_scene.is_inside_tree():
		for group_name in ["world_item", "humanoid_character", "party_member", "npc_character"]:
			for node in root_scene.get_tree().get_nodes_in_group(group_name):
				if node is CollisionObject3D:
					var rid := (node as CollisionObject3D).get_rid()
					if not excludes.has(rid):
						excludes.append(rid)
	return excludes


func _drop_ground_hit_should_be_skipped(collider: Object) -> bool:
	return _node_or_parent_is_in_group(collider, "world_item") \
		or _node_or_parent_is_in_group(collider, "humanoid_character") \
		or _node_or_parent_is_in_group(collider, "party_member") \
		or _node_or_parent_is_in_group(collider, "npc_character")


func _node_or_parent_is_in_group(value: Object, group_name: String) -> bool:
	if not (value is Node):
		return false
	var current := value as Node
	while current != null:
		if current.is_in_group(group_name):
			return true
		current = current.get_parent()
	return false


func _get_world_item_stack(drop_position: Vector3) -> Dictionary:
	var stack_position := drop_position
	var next_bottom_y := drop_position.y + WorldItem.GROUND_CLEARANCE
	if root_scene == null or not root_scene.is_inside_tree():
		return {"position": stack_position, "next_bottom_y": next_bottom_y}
	var drop_xz := Vector2(drop_position.x, drop_position.z)
	var found_stack := false
	for node in root_scene.get_tree().get_nodes_in_group("world_item"):
		var world_item := node as WorldItem
		if world_item == null or world_item.is_queued_for_deletion():
			continue
		var item_xz := Vector2(world_item.global_position.x, world_item.global_position.z)
		if item_xz.distance_to(drop_xz) > WORLD_ITEM_STACK_RADIUS:
			continue
		var item_top_y := world_item.get_visual_top_y()
		if found_stack and item_top_y <= next_bottom_y:
			continue
		found_stack = true
		next_bottom_y = item_top_y
		stack_position.x = world_item.global_position.x
		stack_position.z = world_item.global_position.z
	return {"position": stack_position, "next_bottom_y": next_bottom_y}


func _start_cursor_item_drag(drag_owner, definition: ItemDefinition, count: int, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}, stack_id := "") -> void:
	if definition == null or count <= 0:
		return
	_ensure_cursor_item_drag_source()
	var drag_metadata := metadata.duplicate(true)
	if not stack_id.is_empty():
		drag_metadata[META_DURABLE_STACK_ID] = stack_id
	cursor_item_drag_source.start_drag(drag_owner, definition, count, contained_item_counts, drag_metadata)


func _begin_equipment_update_batch(equipment_a, equipment_b = null) -> Array:
	var capabilities := []
	for equipment in [equipment_a, equipment_b]:
		if equipment == null or capabilities.has(equipment):
			continue
		equipment.begin_equipment_update_batch()
		capabilities.append(equipment)
	return capabilities


func _end_equipment_update_batch(capabilities: Array) -> void:
	for equipment in capabilities:
		if equipment != null:
			equipment.end_equipment_update_batch()


func _consume_cursor_drag(data: Dictionary) -> void:
	var source = data.get("cursor_source", null)
	if source != null and source.has_method("consume_drag"):
		source.consume_drag(int(data.get("cursor_drag_id", 0)))


func _keep_cursor_drag(data: Dictionary) -> void:
	var source = data.get("cursor_source", null)
	if source != null and source.has_method("keep_drag"):
		source.keep_drag(int(data.get("cursor_drag_id", 0)))


func _replace_cursor_drag(data: Dictionary, drag_owner, definition: ItemDefinition, count: int, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}, stack_id := "") -> void:
	var source = data.get("cursor_source", null)
	if source != null and source.has_method("replace_drag_item"):
		var drag_metadata := metadata.duplicate(true)
		if not stack_id.is_empty():
			drag_metadata[META_DURABLE_STACK_ID] = stack_id
		source.replace_drag_item(int(data.get("cursor_drag_id", 0)), drag_owner, definition, count, contained_item_counts, drag_metadata)


func _try_store_replaced_equipment(source_owner, target_owner, definition: ItemDefinition, stack_id := "") -> bool:
	if definition == null:
		return true
	var snapshot := _stack_snapshot(stack_id)
	var source_inventory = _get_owner_inventory(source_owner)
	if source_inventory != null and _get_merchant_role(source_owner) == null and source_inventory.can_add_item(definition):
		return source_inventory.add_entry_with_contents(definition, int(snapshot.get("count", 1)), snapshot.get("contained_item_counts", {}), snapshot.get("metadata", {}), stack_id)
	var target_inventory = _get_owner_inventory(target_owner)
	if target_inventory != null and target_inventory != source_inventory and target_inventory.can_add_item(definition):
		return target_inventory.add_entry_with_contents(definition, int(snapshot.get("count", 1)), snapshot.get("contained_item_counts", {}), snapshot.get("metadata", {}), stack_id)
	return false


func _stack_snapshot(stack_id: String) -> Dictionary:
	if stack_id.is_empty() or _context == null:
		return {}
	var gecs := _context.get_optional(GecsWorldController.SERVICE_ID)
	return gecs.call("get_item_stack", stack_id) if gecs != null and gecs.has_method("get_item_stack") else {}


## Feasibility half of _place_cursor_item_in_inventory (shows the same
## notices), so callers can gate theft side effects on a placement that
## will actually commit.
func _can_place_cursor_item_in_inventory(target_inventory, definition: ItemDefinition, count: int, target_cell: Vector2i, contained_item_counts: Dictionary = {}) -> bool:
	if target_inventory == null or definition == null or count <= 0:
		return false
	if target_inventory.has_method("accepts_item_count") and not bool(target_inventory.call("accepts_item_count", definition, count)):
		_show_floating_notice("Cannot store that here")
		return false
	if target_inventory.use_weight and target_inventory.get_total_weight() + target_inventory.get_item_weight(definition, count, contained_item_counts) > target_inventory.max_weight:
		_show_floating_notice("Too heavy")
		return false
	if not target_inventory.can_place_item(definition, target_cell):
		_show_floating_notice("No room")
		return false
	return true


func _place_cursor_item_in_inventory(target_inventory, definition: ItemDefinition, count: int, target_cell: Vector2i, contained_item_counts: Dictionary = {}, metadata: Dictionary = {}) -> bool:
	if not _can_place_cursor_item_in_inventory(target_inventory, definition, count, target_cell, contained_item_counts):
		return false
	var item_metadata := metadata.duplicate(true)
	var stack_id := str(item_metadata.get(META_DURABLE_STACK_ID, ""))
	item_metadata.erase(META_DURABLE_STACK_ID)
	target_inventory.entries.append(target_inventory.create_entry(definition, target_cell, count, contained_item_counts, item_metadata, stack_id))
	target_inventory.changed.emit()
	return true


func _try_sell_cursor_item(source_owner, merchant_owner, definition: ItemDefinition, count: int, target_cell: Vector2i, merchant_role, metadata: Dictionary = {}) -> bool:
	if source_owner == null or merchant_owner == null or definition == null or count <= 0:
		return false
	if not _can_sell_metadata_to_merchant(source_owner, merchant_owner, metadata):
		_show_floating_notice("Stolen goods")
		return false
	if not _item_is_sellable(definition):
		_show_floating_notice("Cannot trade")
		return false
	var price: int = merchant_role.get_buy_price(definition)
	if price < 0:
		_show_floating_notice("Cannot trade")
		return false
	price *= count
	var merchant_inventory = _get_owner_inventory(merchant_owner)
	if merchant_inventory == null or not merchant_inventory.can_place_item(definition, target_cell):
		_show_floating_notice("Merchant does not have space")
		return false
	if merchant_inventory.count_item(SILVER_ITEM) < price:
		_show_floating_notice("Cannot afford")
		return false
	if not source_owner.inventory.can_add_item_count(SILVER_ITEM, price):
		_show_floating_notice("Not enough space")
		return false
	merchant_inventory.remove_item_count(SILVER_ITEM, price)
	source_owner.inventory.add_item_count(SILVER_ITEM, price)
	var item_metadata := metadata.duplicate(true)
	var stack_id := str(item_metadata.get(META_DURABLE_STACK_ID, ""))
	item_metadata.erase(META_DURABLE_STACK_ID)
	merchant_inventory.entries.append(merchant_inventory.create_entry(definition, target_cell, count, {}, item_metadata, stack_id))
	merchant_inventory.changed.emit()
	return true


func _try_pay_for_equipment_transfer(source_owner, target_owner, entry) -> bool:
	if source_owner == target_owner:
		return true
	var source_role = _get_merchant_role(source_owner)
	var target_role = _get_merchant_role(target_owner)
	if source_role == null and target_role == null:
		return true
	if source_role != null and target_role == null:
		if not _item_is_sellable(entry.definition):
			_show_floating_notice("Cannot trade")
			return false
		var price: int = source_role.get_sell_price(entry.definition) * entry.count
		var source_inventory = _get_owner_inventory(source_owner)
		if price < 0 or target_owner.inventory.count_item(SILVER_ITEM) < price:
			_show_floating_notice("Cannot afford")
			return false
		if source_inventory == null or not source_inventory.can_add_item_count(SILVER_ITEM, price):
			_show_floating_notice("Merchant does not have space")
			return false
		target_owner.inventory.remove_item_count(SILVER_ITEM, price)
		source_inventory.add_item_count(SILVER_ITEM, price)
		return true
	_show_floating_notice("Cannot trade")
	return false


func _can_transfer_between_owners(source_owner, target_owner) -> bool:
	if source_owner != null and source_owner.has_method("can_transfer_display_inventory_to"):
		if not source_owner.can_transfer_display_inventory_to(target_owner):
			return false
	if target_owner != null and target_owner.has_method("can_receive_inventory_transfer_from"):
		if not target_owner.can_receive_inventory_transfer_from(source_owner):
			return false
	return true


func _try_handle_trade(source_owner, target_owner, entry, target_cell: Vector2i) -> bool:
	var source_role = _get_merchant_role(source_owner)
	var target_role = _get_merchant_role(target_owner)
	if source_role == null and target_role == null:
		return false
	if source_role != null and target_role != null:
		return false
	if source_role != null:
		return _buy_from_merchant(source_owner, target_owner, entry, target_cell, source_role)
	return _sell_to_merchant(source_owner, target_owner, entry, target_cell, target_role)


func _buy_from_merchant(merchant_owner, buyer_owner, entry, target_cell: Vector2i, merchant_role) -> bool:
	if not _item_is_sellable(entry.definition):
		_show_floating_notice("Cannot trade")
		return true
	var price: int = merchant_role.get_sell_price(entry.definition)
	if price < 0:
		_show_floating_notice("Cannot afford")
		return true
	price *= entry.count
	var merchant_inventory = _get_owner_inventory(merchant_owner)
	if merchant_inventory == null:
		_show_floating_notice("Cannot trade")
		return true
	if buyer_owner.inventory.count_item(SILVER_ITEM) < price:
		_show_floating_notice("Cannot afford")
		return true
	if not buyer_owner.inventory.can_place_item(entry.definition, target_cell):
		_show_floating_notice("Not enough space")
		return true
	if not merchant_inventory.can_add_item_count(SILVER_ITEM, price):
		_show_floating_notice("Merchant does not have space")
		return true
	if not buyer_owner.inventory.remove_item_count(SILVER_ITEM, price):
		_show_floating_notice("Cannot afford")
		return true
	merchant_inventory.add_item_count(SILVER_ITEM, price)
	merchant_inventory.move_entry_to_inventory(entry, buyer_owner.inventory, target_cell)
	return true


func _sell_to_merchant(seller_owner, merchant_owner, entry, target_cell: Vector2i, merchant_role) -> bool:
	if not _item_is_sellable(entry.definition):
		_show_floating_notice("Cannot trade")
		return true
	if not _can_sell_metadata_to_merchant(seller_owner, merchant_owner, entry.metadata):
		_show_floating_notice("Stolen goods")
		return true
	var price: int = merchant_role.get_buy_price(entry.definition)
	if price < 0:
		_show_floating_notice("Cannot trade")
		return true
	price *= entry.count
	var merchant_inventory = _get_owner_inventory(merchant_owner)
	var seller_inventory = _get_owner_inventory(seller_owner)
	if merchant_inventory == null or seller_inventory == null:
		_show_floating_notice("Cannot trade")
		return true
	if not merchant_inventory.can_place_item(entry.definition, target_cell):
		_show_floating_notice("Merchant does not have space")
		return true
	if merchant_inventory.count_item(SILVER_ITEM) < price:
		_show_floating_notice("Cannot afford")
		return true
	if not seller_owner.inventory.can_add_item_count(SILVER_ITEM, price):
		_show_floating_notice("Not enough space")
		return true
	merchant_inventory.remove_item_count(SILVER_ITEM, price)
	seller_owner.inventory.add_item_count(SILVER_ITEM, price)
	seller_inventory.move_entry_to_inventory(entry, merchant_inventory, target_cell)
	return true


func _can_sell_metadata_to_merchant(seller_owner, merchant_owner, metadata: Dictionary) -> bool:
	if metadata.is_empty() or not bool(metadata.get(InventoryData.META_STOLEN, false)):
		return true
	var law_controller := _get_law_order_controller()
	if law_controller == null or not law_controller.has_method("can_sell_entry_to_merchant"):
		return true
	var stub := InventoryData.InventoryEntry.new(null, Vector2i.ZERO, 1, {}, metadata)
	return bool(law_controller.call("can_sell_entry_to_merchant", seller_owner, merchant_owner, stub))


func _try_deposit_entry_into_pouch(source_owner, target_owner, entry, target_cell: Vector2i) -> bool:
	var source_inventory = _get_owner_inventory(source_owner)
	var target_inventory = _get_owner_inventory(target_owner)
	if source_inventory == null or target_inventory == null or entry == null or not source_inventory.entries.has(entry):
		return false
	var target_entry = target_inventory.get_entry_at_cell(target_cell)
	if not _entry_is_silver_pouch(target_inventory, target_entry):
		return false
	if target_entry == entry:
		_show_floating_notice("Same pouch")
		return true
	if not _entry_is_silver_coin(entry) and not _entry_is_silver_pouch(source_inventory, entry):
		return false
	if source_owner != target_owner:
		if _owners_too_far(source_owner, target_owner):
			_show_floating_notice("Too far away")
			return true
		if _get_merchant_role(source_owner) != null or _get_merchant_role(target_owner) != null:
			_show_floating_notice("Cannot trade")
			return true
	var capacity := int(target_inventory.get_entry_remaining_currency_capacity(target_entry, SILVER_ITEM))
	if capacity <= 0:
		_show_floating_notice("Pouch full")
		return true
	if _entry_is_silver_coin(entry):
		_deposit_coin_entry_into_pouch(source_inventory, target_inventory, entry, target_entry, capacity)
		_refresh_inventory_windows_for(source_owner, target_owner)
		return true
	_deposit_pouch_entry_into_pouch(source_owner, source_inventory, target_inventory, entry, target_entry, capacity)
	_refresh_inventory_windows_for(source_owner, target_owner)
	return true


func _try_deposit_cursor_into_pouch(data: Dictionary, target_owner, target_cell: Vector2i) -> bool:
	var target_inventory = _get_owner_inventory(target_owner)
	if target_inventory == null:
		return false
	var target_entry = target_inventory.get_entry_at_cell(target_cell)
	if not _entry_is_silver_pouch(target_inventory, target_entry):
		return false
	var source_owner = data.get("source_owner", null)
	var definition: ItemDefinition = data.get("item_definition") as ItemDefinition
	if definition == null or not _definition_is_silver_currency(definition):
		return false
	if source_owner != null and source_owner != target_owner:
		if _owners_too_far(source_owner, target_owner):
			_show_floating_notice("Too far away")
			_keep_cursor_drag(data)
			return true
		if _get_merchant_role(source_owner) != null or _get_merchant_role(target_owner) != null:
			_show_floating_notice("Cannot trade")
			_keep_cursor_drag(data)
			return true
	var capacity := int(target_inventory.get_entry_remaining_currency_capacity(target_entry, SILVER_ITEM))
	if capacity <= 0:
		_show_floating_notice("Pouch full")
		_keep_cursor_drag(data)
		return true
	if _definition_is_silver_pouch(definition):
		var stored := _contained_silver_count(data.get("contained_item_counts", {}))
		if stored <= 0:
			_show_floating_notice("No silver")
			_keep_cursor_drag(data)
			return true
		var moved: int = min(capacity, stored)
		target_inventory.adjust_entry_contained_item_count(target_entry, SILVER_ITEM, moved)
		var remaining_pouch_silver := stored - moved
		if remaining_pouch_silver > 0:
			_replace_cursor_drag(data, source_owner, SILVER_POUCH_ITEM, 1, _silver_contents(remaining_pouch_silver))
		else:
			_consume_cursor_drag(data)
		return true
	var count := int(data.get("count", 1))
	if count <= 0:
		_show_floating_notice("No silver")
		_keep_cursor_drag(data)
		return true
	var moved_coins: int = min(capacity, count)
	target_inventory.adjust_entry_contained_item_count(target_entry, SILVER_ITEM, moved_coins)
	var remaining := count - moved_coins
	if remaining > 0:
		_replace_cursor_drag(data, source_owner, SILVER_ITEM, remaining)
	else:
		_consume_cursor_drag(data)
	return true


func _deposit_coin_entry_into_pouch(source_inventory, target_inventory, entry, target_entry, capacity: int) -> void:
	var moved: int = min(capacity, int(entry.count))
	if moved <= 0:
		return
	target_inventory.adjust_entry_contained_item_count(target_entry, SILVER_ITEM, moved, false)
	entry.count -= moved
	if entry.count <= 0:
		source_inventory.entries.erase(entry)
	_emit_inventory_changes(source_inventory, target_inventory)


func _deposit_pouch_entry_into_pouch(source_owner, source_inventory, target_inventory, entry, target_entry, capacity: int) -> void:
	var stored := int(source_inventory.get_entry_contained_item_count(entry, SILVER_ITEM))
	if stored <= 0:
		_show_floating_notice("No silver")
		return
	var moved: int = min(capacity, stored)
	target_inventory.adjust_entry_contained_item_count(target_entry, SILVER_ITEM, moved, false)
	source_inventory.entries.erase(entry)
	_emit_inventory_changes(source_inventory, target_inventory)
	var remaining_pouch_silver := stored - moved
	if remaining_pouch_silver > 0:
		_start_cursor_item_drag(source_owner, SILVER_POUCH_ITEM, 1, _silver_contents(remaining_pouch_silver))


func _emit_inventory_changes(inventory_a, inventory_b = null) -> void:
	if inventory_a != null:
		inventory_a.changed.emit()
	if inventory_b != null and inventory_b != inventory_a:
		inventory_b.changed.emit()


func _entry_is_silver_coin(entry) -> bool:
	return entry != null and _definition_is_silver_coin(entry.definition)


func _entry_is_silver_pouch(inventory, entry) -> bool:
	return inventory != null and entry != null and inventory.has_method("is_entry_currency_container") and bool(inventory.call("is_entry_currency_container", entry, SILVER_ITEM))


func _definition_is_silver_currency(definition: ItemDefinition) -> bool:
	return definition != null and str(definition.currency_id) == str(SILVER_ITEM.currency_id)


func _definition_is_silver_coin(definition: ItemDefinition) -> bool:
	return _definition_is_silver_currency(definition) and int(definition.currency_container_capacity) <= 0


func _definition_is_silver_pouch(definition: ItemDefinition) -> bool:
	return _definition_is_silver_currency(definition) and int(definition.currency_container_capacity) > 0


func _contained_silver_count(contained_item_counts: Dictionary) -> int:
	return max(0, int(contained_item_counts.get(_silver_key(), 0)))


func _silver_contents(amount: int) -> Dictionary:
	return {_silver_key(): max(0, amount)}


func _silver_key() -> String:
	return str(SILVER_ITEM.resource_path)


func _item_is_sellable(definition: ItemDefinition) -> bool:
	return definition != null and bool(definition.sellable)


func _get_merchant_role(inventory_owner):
	if inventory_owner != null and inventory_owner.has_method("get_merchant_role"):
		return inventory_owner.get_merchant_role()
	return null


func _get_law_order_controller() -> Node:
	return _context.get_optional(LawOrderController.SERVICE_ID) if _context != null else null


## --- Container burglary -------------------------------------------------------
## Opening someone else's container is legal; taking anything OUT of it (into
## any inventory or onto the floor) is burglary. The standard theft roll runs
## against the container: witnesses, sneak-adjusted stealing skill, XP both
## ways, stolen metadata, law report. Putting items IN stays legal.


## Returns false when a suspicious witness blocks the attempt before it
## happens (the item stays where it is).
func _authorize_container_take(source_owner, acting_owner) -> bool:
	if not _owner_is_owned_container(source_owner):
		return true
	var ownership := _get_ownership_controller()
	var actor := _burglary_actor(acting_owner)
	if ownership == null or actor == null or not ownership.has_method("request_take_item"):
		return false
	return bool(ownership.call("request_take_item", actor, source_owner))


func _stolen_take_metadata(source_owner, acting_owner, current_metadata: Dictionary) -> Dictionary:
	if not _owner_is_owned_container(source_owner):
		return current_metadata
	var ownership := _get_ownership_controller()
	var actor := _burglary_actor(acting_owner)
	if ownership == null or actor == null or not ownership.has_method("get_take_item_metadata"):
		return current_metadata
	return ownership.call("get_take_item_metadata", actor, source_owner, current_metadata) as Dictionary


func _owner_is_owned_container(inventory_owner) -> bool:
	if not (inventory_owner is Node) or not (inventory_owner as Node).is_in_group("world_container"):
		return false
	return OwnershipUtils.is_owned(inventory_owner)


## The burglar is the character receiving the goods when that is a character;
## container-to-container moves and floor drops fall back to the focused
## party member doing the dragging.
func _burglary_actor(acting_owner) -> HumanoidCharacter:
	if acting_owner is HumanoidCharacter:
		return acting_owner
	var focused = _get_focused_character_owner()
	return focused if focused is HumanoidCharacter else null


func _get_ownership_controller() -> Node:
	return _context.get_optional(OwnershipController.SERVICE_ID) if _context != null else null


func _take_silver_from_pouch(inventory_owner, entry, action: String) -> void:
	if inventory_owner == null or entry == null:
		return
	if not inventory_owner.has_method("is_player_party_member") or not bool(inventory_owner.call("is_player_party_member")):
		return
	var inventory = _get_owner_inventory(inventory_owner)
	if inventory == null or not inventory.has_method("is_entry_currency_container") or not bool(inventory.call("is_entry_currency_container", entry, SILVER_ITEM)):
		return
	var available := int(inventory.call("get_entry_contained_item_count", entry, SILVER_ITEM))
	var amount := _silver_take_amount(action, available)
	if amount <= 0:
		return
	if not inventory.can_add_loose_item_count(SILVER_ITEM, amount):
		_show_floating_notice("No room")
		return
	var taken := int(inventory.call("take_contained_item_as_loose", entry, SILVER_ITEM, amount))
	if taken <= 0:
		_show_floating_notice("No room")
		return
	_refresh_inventory_windows_for(inventory_owner)


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
