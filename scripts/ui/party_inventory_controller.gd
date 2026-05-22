extends Node

class_name PartyInventoryController

const INVENTORY_WINDOW_SCENE = preload("res://scenes/ui/inventory_window.tscn")
const WORLD_ITEM_SCENE = preload("res://scenes/world/items/world_item.tscn")
const CURSOR_ITEM_DRAG_SOURCE_SCRIPT = preload("res://scripts/ui/cursor_item_drag_source.gd")
const SILVER_ITEM = preload("res://resources/items/silver.tres")
const WINDOW_EDGE_PADDING := 36.0
const WINDOW_TOP_PADDING := 160.0
const WINDOW_GAP := 24.0
const WORLD_ITEM_DROP_DISTANCE := 0.9
const WORLD_ITEM_STACK_RADIUS := 0.2
const WORLD_ITEM_GROUND_RAY_UP := 3.0
const WORLD_ITEM_GROUND_RAY_DOWN := 6.0
const WORLD_ITEM_GROUND_RAY_MAX_SKIPS := 12

@export var inventory_toggle_key := KEY_I

var open_inventory_windows: Dictionary = {}
var primary_character_window: InventoryWindow
var secondary_inventory_window: InventoryWindow
var root_scene: Node
var hud_layer: CanvasLayer
var party_manager: PartyManager
var inventory_window_layer: Control
var floating_notice
var cursor_item_drag_source
var _initialized := false


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
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


func open_selected_inventory() -> void:
	if party_manager.selected_members.is_empty():
		return
	_open_primary_inventory(party_manager.selected_members[0], true)


func open_inventory_for_member(member: HumanoidCharacter) -> void:
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


func _owner_is_primary_character(inventory_owner) -> bool:
	return inventory_owner is HumanoidCharacter and inventory_owner.is_player_party_member()


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
	if source_owner == target_owner:
		var source_inventory = _get_owner_inventory(source_owner)
		if source_inventory != null:
			source_inventory.move_entry(entry, target_cell)
		return
	if _try_handle_trade(source_owner, target_owner, entry, target_cell):
		return
	var source_inventory = _get_owner_inventory(source_owner)
	var target_inventory = _get_owner_inventory(target_owner)
	if source_inventory == null or target_inventory == null:
		return
	var target_window = _get_window_for_owner(target_owner)
	if _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return

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
	if target_cell == Vector2i(-1, -1):
		return
	if _try_handle_trade(source_owner, target_owner, entry, target_cell):
		return
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
	if action == "eat" and inventory_owner.has_method("eat_item"):
		inventory_owner.eat_item(entry.definition)


func _on_inventory_equip_requested(source_owner, entry, target_owner, slot_name: String) -> void:
	if source_owner == null or target_owner == null or entry == null:
		return
	if not target_owner.has_method("can_equip_item_to_slot") or not target_owner.can_equip_item_to_slot(entry.definition, slot_name):
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
	var previous = target_owner.get_equipped_item(slot_name) if target_owner.has_method("get_equipped_item") else null
	if not _try_pay_for_equipment_transfer(source_owner, target_owner, entry):
		return
	if not source_inventory.remove_entry(entry):
		return
	var replaced = target_owner.equip_item_to_slot(entry.definition, slot_name)
	if replaced != null and not _try_store_replaced_equipment(source_owner, target_owner, replaced):
		_start_cursor_item_drag(target_owner, replaced, 1)
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_equipment_transfer_requested(source_owner, source_slot_name: String, target_owner, target_slot_name: String) -> void:
	if source_owner == null or target_owner == null:
		return
	if source_owner != target_owner and _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return
	if not source_owner.has_method("get_equipped_item") or not source_owner.has_method("unequip_item_from_slot"):
		return
	if not target_owner.has_method("can_equip_item_to_slot") or not target_owner.has_method("equip_item_to_slot"):
		return
	var moving_item: ItemDefinition = source_owner.get_equipped_item(source_slot_name)
	if moving_item == null or not target_owner.can_equip_item_to_slot(moving_item, target_slot_name):
		_show_floating_notice("Cannot equip")
		return
	if source_owner == target_owner and source_slot_name == target_slot_name:
		return
	var target_previous: ItemDefinition = target_owner.get_equipped_item(target_slot_name)
	var can_swap_back: bool = target_previous != null and source_owner.has_method("can_equip_item_to_slot") and source_owner.has_method("equip_item_to_slot") and source_owner.can_equip_item_to_slot(target_previous, source_slot_name)
	var batched_owners := _begin_equipment_update_batch(source_owner, target_owner)
	source_owner.unequip_item_from_slot(source_slot_name)
	var replaced = target_owner.equip_item_to_slot(moving_item, target_slot_name)
	if replaced != null:
		if can_swap_back:
			source_owner.equip_item_to_slot(replaced, source_slot_name)
		else:
			_start_cursor_item_drag(target_owner, replaced, 1)
	_end_equipment_update_batch(batched_owners)
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
	if not source_owner.has_method("get_equipped_item") or not source_owner.has_method("unequip_item_from_slot"):
		return
	var item: ItemDefinition = source_owner.get_equipped_item(slot_name)
	var target_inventory = _get_owner_inventory(target_owner)
	if item == null or target_inventory == null:
		return
	if target_inventory.use_weight and target_inventory.get_total_weight() + item.unit_weight > target_inventory.max_weight:
		_show_floating_notice("Too heavy")
		return
	if not target_inventory.can_place_item(item, target_cell):
		_show_floating_notice("No room")
		return
	var removed: ItemDefinition = source_owner.unequip_item_from_slot(slot_name)
	if removed == null:
		return
	target_inventory.entries.append(InventoryData.InventoryEntry.new(removed, target_cell, 1))
	target_inventory.changed.emit()
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_inventory_item_drop_requested(source_owner, entry) -> void:
	if source_owner == null or entry == null:
		return
	var source_inventory = _get_owner_inventory(source_owner)
	if source_inventory == null or not source_inventory.entries.has(entry):
		return
	if not source_inventory.remove_entry(entry):
		return
	_spawn_world_item(source_owner, entry.definition, entry.count)


func _on_inventory_equipment_drop_requested(source_owner, slot_name: String) -> void:
	if source_owner == null or not source_owner.has_method("unequip_item_from_slot"):
		return
	var item: ItemDefinition = source_owner.unequip_item_from_slot(slot_name)
	if item == null:
		return
	_spawn_world_item(source_owner, item, 1)


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
	if target_role != null and source_role == null and source_owner != target_owner:
		if _try_sell_cursor_item(source_owner, target_owner, definition, count, target_cell, target_role):
			_consume_cursor_drag(data)
			_refresh_inventory_windows_for(source_owner, target_owner)
		else:
			_keep_cursor_drag(data)
		return
	if source_role != null and target_role == null and source_owner != target_owner:
		_show_floating_notice("Cannot trade")
		_keep_cursor_drag(data)
		return
	var target_inventory = _get_owner_inventory(target_owner)
	if target_inventory == null:
		_keep_cursor_drag(data)
		return
	if not _place_cursor_item_in_inventory(target_inventory, definition, count, target_cell):
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
	if not target_owner.has_method("can_equip_item_to_slot") or not target_owner.can_equip_item_to_slot(definition, slot_name):
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
	var replaced = target_owner.equip_item_to_slot(definition, slot_name)
	if replaced != null:
		_replace_cursor_drag(data, target_owner, replaced, 1)
	else:
		_consume_cursor_drag(data)
	_refresh_inventory_windows_for(source_owner, target_owner)


func _on_cursor_item_dropped_outside(source_owner, definition: ItemDefinition, count: int) -> void:
	_spawn_world_item(source_owner, definition, count)


func _get_owner_inventory(inventory_owner):
	if inventory_owner != null and inventory_owner.has_method("get_inventory_for_display"):
		return inventory_owner.get_inventory_for_display()
	if inventory_owner == null:
		return null
	return inventory_owner.inventory


func _refresh_inventory_windows_for(owner_a, owner_b = null) -> void:
	for owner in [owner_a, owner_b]:
		if owner == null:
			continue
		var window = open_inventory_windows.get(owner.get_instance_id())
		if _is_live_window(window) and window.has_method("refresh"):
			window.refresh()


func _spawn_world_item(source_owner, definition: ItemDefinition, count: int) -> void:
	if root_scene == null or definition == null or count <= 0:
		return
	var drop_position_value = _get_world_drop_position(source_owner)
	if not (drop_position_value is Vector3):
		return
	var requested_drop_position: Vector3 = drop_position_value
	var stack := _get_world_item_stack(requested_drop_position)
	var drop_position: Vector3 = stack["position"]
	var next_bottom_y: float = stack["next_bottom_y"]
	for _index in range(count):
		var world_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
		if world_item == null:
			return
		root_scene.add_child(world_item)
		world_item.setup(definition, 1)
		var item_height := world_item.place_bottom_at(drop_position, next_bottom_y)
		next_bottom_y += maxf(item_height, 0.05)


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


func _start_cursor_item_drag(owner, definition: ItemDefinition, count: int) -> void:
	if definition == null or count <= 0:
		return
	_ensure_cursor_item_drag_source()
	cursor_item_drag_source.start_drag(owner, definition, count)


func _begin_equipment_update_batch(owner_a, owner_b = null) -> Array:
	var owners := []
	for owner in [owner_a, owner_b]:
		if owner == null or owners.has(owner) or not owner.has_method("begin_equipment_update_batch"):
			continue
		owner.begin_equipment_update_batch()
		owners.append(owner)
	return owners


func _end_equipment_update_batch(owners: Array) -> void:
	for owner in owners:
		if owner != null and owner.has_method("end_equipment_update_batch"):
			owner.end_equipment_update_batch()


func _consume_cursor_drag(data: Dictionary) -> void:
	var source = data.get("cursor_source", null)
	if source != null and source.has_method("consume_drag"):
		source.consume_drag(int(data.get("cursor_drag_id", 0)))


func _keep_cursor_drag(data: Dictionary) -> void:
	var source = data.get("cursor_source", null)
	if source != null and source.has_method("keep_drag"):
		source.keep_drag(int(data.get("cursor_drag_id", 0)))


func _replace_cursor_drag(data: Dictionary, owner, definition: ItemDefinition, count: int) -> void:
	var source = data.get("cursor_source", null)
	if source != null and source.has_method("replace_drag_item"):
		source.replace_drag_item(int(data.get("cursor_drag_id", 0)), owner, definition, count)


func _try_store_replaced_equipment(source_owner, target_owner, definition: ItemDefinition) -> bool:
	if definition == null:
		return true
	var source_inventory = _get_owner_inventory(source_owner)
	if source_inventory != null and _get_merchant_role(source_owner) == null and source_inventory.can_add_item(definition):
		return source_inventory.add_item(definition)
	var target_inventory = _get_owner_inventory(target_owner)
	if target_inventory != null and target_inventory != source_inventory and target_inventory.can_add_item(definition):
		return target_inventory.add_item(definition)
	return false


func _place_cursor_item_in_inventory(target_inventory, definition: ItemDefinition, count: int, target_cell: Vector2i) -> bool:
	if target_inventory == null or definition == null or count <= 0:
		return false
	if target_inventory.use_weight and target_inventory.get_total_weight() + definition.unit_weight * count > target_inventory.max_weight:
		_show_floating_notice("Too heavy")
		return false
	if not target_inventory.can_place_item(definition, target_cell):
		_show_floating_notice("No room")
		return false
	target_inventory.entries.append(InventoryData.InventoryEntry.new(definition, target_cell, count))
	target_inventory.changed.emit()
	return true


func _try_sell_cursor_item(source_owner, merchant_owner, definition: ItemDefinition, count: int, target_cell: Vector2i, merchant_role) -> bool:
	if source_owner == null or merchant_owner == null or definition == null or count <= 0:
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
	merchant_inventory.entries.append(InventoryData.InventoryEntry.new(definition, target_cell, count))
	merchant_inventory.changed.emit()
	return true


func _try_pay_for_equipment_transfer(source_owner, target_owner, entry) -> bool:
	var source_role = _get_merchant_role(source_owner)
	var target_role = _get_merchant_role(target_owner)
	if source_role == null and target_role == null:
		return true
	if source_role != null and target_role == null:
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


func _get_merchant_role(inventory_owner):
	if inventory_owner != null and inventory_owner.has_method("get_merchant_role"):
		return inventory_owner.get_merchant_role()
	return null
