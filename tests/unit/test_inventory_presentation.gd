extends GutTest

const WINDOW = preload("res://features/ui/projection/inventory_window.tscn")
const STOCK = preload("res://features/ui/projection/merchant_stock_list.gd")
const SEEDS = preload("res://features/inventory/resources/items/eggplant_seeds.tres")

class EquippedOwner extends Node:
	var item: ItemDefinition
	func get_equipped_item(_slot: String):
		return item

class BagOwner extends Node:
	var inventory := InventoryData.new()
	func shows_inventory_equipment() -> bool:
		return false

func test_sort_aligns_to_drawn_cells_not_expanded_window() -> void:
	for columns in [6, 10]:
		var owner := BagOwner.new()
		owner.inventory.columns = columns
		add_child_autofree(owner)
		var window = WINDOW.instantiate()
		add_child_autofree(window)
		window.setup(owner)
		await get_tree().process_frame
		await get_tree().process_frame
		window.size.x = 700
		await get_tree().process_frame
		await get_tree().process_frame
		var grid: Control = window.inventory_grid
		var button: Button = window.auto_sort_button
		# Drawn grid is 30-pixel cells with 2-pixel gaps, independent of panel fill.
		var right: float = grid.global_position.x + columns * 32 - 2
		assert_almost_eq(button.get_global_rect().end.x, right, 0.01)
		assert_almost_eq(button.global_position.x, right - 62, 0.01)
		assert_eq(button.size, Vector2(62, 30), "Sort occupies two cell widths and one cell height")
		assert_almost_eq(window.weight_label.global_position.x, grid.global_position.x, 0.01)
		assert_almost_eq(grid.global_position.y - button.get_global_rect().end.y, 8.0, 0.01)

func test_equipped_art_preserves_bag_scale_when_slot_size_changes() -> void:
	var owner := EquippedOwner.new()
	add_child_autofree(owner)
	owner.item = load("res://features/inventory/resources/items/steel_sword.tres")
	var slot := EquipmentSlotControl.new()
	add_child_autofree(slot)
	slot.setup(owner, "weapon", "Weapon")
	await get_tree().process_frame
	await get_tree().process_frame
	var icon: TextureRect = slot.find_child("EquipmentIcon", true, false)
	# The existing 1x4 bag footprint is 30x126 with four pixels of padding.
	# Its square source art therefore draws at 22x22, not at the slot's width.
	assert_eq(icon.size, Vector2(22, 22))
	slot.size = Vector2(180, 180)
	await get_tree().process_frame
	assert_eq(icon.size, Vector2(22, 22), "A larger equipment target must not enlarge the item")
	assert_eq(owner.item.grid_size, Vector2i(1, 4), "Presentation must not mutate the item footprint")

func test_equipment_slot_does_not_expand_for_oversized_saved_gear() -> void:
	var owner := EquippedOwner.new()
	add_child_autofree(owner)
	var slot := EquipmentSlotControl.new()
	add_child_autofree(slot)
	slot.setup(owner, "legs", "Legs")
	var empty_size := slot.custom_minimum_size
	owner.item = ItemDefinition.new()
	owner.item.grid_size = Vector2i(4, 5)
	owner.item.equip_slot = "legs"
	slot.refresh()
	assert_eq(slot.custom_minimum_size, empty_size, "Saved oversized gear must not enlarge its slot")
	assert_eq(slot.size, empty_size)
	assert_true(slot.clip_contents, "Old oversized art cannot cover neighboring drop targets")
	assert_eq(owner.item.grid_size, Vector2i(4, 5), "Never shrink the item to bypass capacity")
	owner.item = null
	slot.refresh()
	assert_eq(slot.custom_minimum_size, empty_size)


func test_equipped_sword_occupies_its_original_cells_without_clipping() -> void:
	var owner := EquippedOwner.new()
	add_child_autofree(owner)
	owner.item = load("res://features/inventory/resources/items/steel_sword.tres")
	var slot := EquipmentSlotControl.new()
	add_child_autofree(slot)
	slot.setup(owner, "weapon", "Weapon")
	assert_gte(slot.custom_minimum_size.y, 126.0, "Four bag cells must fit without shrinking or clipping")
	assert_true(slot.has_method("get_equipped_item_rect"))
	if slot.has_method("get_equipped_item_rect"):
		assert_eq(slot.get_equipped_item_rect(), Rect2(0, 0, 30, 126))
		slot.size = Vector2(180, 180)
		assert_eq(slot.get_equipped_item_rect(), Rect2(0, 0, 30, 126), "Extra target space is not item space")

func test_unequipped_slot_can_resize_before_its_icon_refreshes() -> void:
	var owner := EquippedOwner.new()
	add_child_autofree(owner)
	var sword: ItemDefinition = load("res://features/inventory/resources/items/steel_sword.tres")
	owner.item = sword
	var slot := EquipmentSlotControl.new()
	add_child_autofree(slot)
	slot.setup(owner, "weapon", "Weapon")
	await get_tree().process_frame
	assert_same(slot._icon.texture, sword.icon)
	assert_eq(slot.get_equipped_item_rect().size, Vector2(30, 126))
	owner.item = null
	# InventoryWindow refreshes an existing slot with setup(). Its size change
	# emits resized synchronously, before refresh() has cleared the old texture.
	slot.setup(owner, "weapon", "Weapon")
	assert_null(slot._icon.texture)
	assert_eq(slot.get_equipped_item_rect(), Rect2())
	assert_eq(slot._label.text, "Weapon")
	owner.item = sword
	slot.setup(owner, "weapon", "Weapon")
	assert_same(slot._icon.texture, sword.icon)
	assert_eq(slot._icon.size, Vector2(22, 22))

func test_resize_clears_stale_equipment_art_after_owner_is_freed() -> void:
	var owner := EquippedOwner.new()
	add_child(owner)
	owner.item = load("res://features/inventory/resources/items/steel_sword.tres")
	var slot := EquipmentSlotControl.new()
	add_child_autofree(slot)
	slot.setup(owner, "weapon", "Weapon")
	assert_not_null(slot._icon.texture)
	owner.free()
	slot.size += Vector2(10, 10)
	assert_null(slot._icon.texture, "Resize must discard art whose equipped owner no longer exists")

func test_split_drag_keeps_the_inventory_footprint_scale() -> void:
	var source := CursorItemDragSource.new()
	add_child_autofree(source)
	source.item_definition = load("res://features/inventory/resources/items/steel_sword.tres")
	var preview := source._make_drag_preview()
	autofree(preview)
	var icon: TextureRect = preview.find_child("ItemIcon", true, false)
	assert_eq(icon.size, Vector2(22, 22), "Split/cursor drag must use the same art scale as bag and equipment")

func test_inventory_panel_is_opaque() -> void:
	var window = WINDOW.instantiate()
	add_child_autofree(window)
	var style = window.get_theme_stylebox("panel")
	assert_true(style is StyleBoxFlat)
	if style is StyleBoxFlat:
		assert_eq(style.bg_color.a, 1.0, "World must not bleed through inventory")

func test_inventory_header_has_a_distinct_solid_grab_bar() -> void:
	var window = WINDOW.instantiate()
	add_child_autofree(window)
	var style = window.title_bar.get_theme_stylebox("panel")
	assert_true(style is StyleBoxFlat, "The draggable header needs a visible surface")
	if style is StyleBoxFlat:
		assert_eq(style.bg_color.a, 1.0)
		assert_ne(style.bg_color, window.get_theme_stylebox("panel").bg_color)
		assert_gt(style.border_width_bottom, 0, "Separate the grab bar from the equipment")
	var grip = window.title_bar.find_child("Grip", true, false)
	assert_null(grip, "Do not display a decorative pseudo-menu in the drag bar")

func test_inventory_header_uses_hand_art_and_separate_button_targets() -> void:
	var window = WINDOW.instantiate()
	add_child_autofree(window)
	var grab = window.title_bar.find_child("GrabArea", true, false)
	assert_not_null(grab, "Only the name/grip surface owns the hand cursor")
	if grab == null:
		return
	assert_eq(grab.mouse_default_cursor_shape, Control.CURSOR_MOVE)
	assert_not_null(window.get("GRAB_OPEN"))
	assert_not_null(window.get("GRAB_CLOSED"))
	assert_eq(window.title_label.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(window.close_button.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(window.auto_sort_button.mouse_filter, Control.MOUSE_FILTER_STOP)

func test_inventory_header_drag_moves_window_and_stops_on_release() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1400, 1000)
	add_child_autofree(viewport)
	var window = WINDOW.instantiate()
	viewport.add_child(window)
	await get_tree().process_frame
	await get_tree().process_frame
	window.position = Vector2(40, 40)
	var start: Vector2 = window.title_label.get_global_rect().get_center()
	_header_pointer_motion(viewport, start)
	assert_eq(window.get_global_mouse_position(), start)
	_header_pointer_button(viewport, start, true)
	assert_true(window._dragging, "Pressing the name must reach the grab bar")
	var grab = window.title_bar.find_child("GrabArea", true, false)
	assert_not_null(grab)
	if grab != null:
		assert_eq(grab.mouse_default_cursor_shape, Control.CURSOR_DRAG, "Held hand must close")
	_header_pointer_motion(viewport, start + Vector2(120, 60), MOUSE_BUTTON_MASK_LEFT)
	assert_eq(window.position, Vector2(160, 100))
	_header_pointer_button(viewport, start + Vector2(120, 60), false)
	assert_false(window._dragging)
	if grab != null:
		assert_eq(grab.mouse_default_cursor_shape, Control.CURSOR_MOVE, "Released hand opens again")
	_header_pointer_motion(viewport, start + Vector2(200, 100))
	assert_eq(window.position, Vector2(160, 100), "Release must end window movement")
	var close_at: Vector2 = window.close_button.get_global_rect().get_center()
	watch_signals(window)
	_header_pointer_motion(viewport, close_at)
	_header_pointer_button(viewport, close_at, true)
	assert_false(window._dragging, "Close is a button, not part of the drag target")
	_header_pointer_button(viewport, close_at, false)
	assert_signal_emit_count(window, "close_requested", 1)

func test_hiding_or_losing_focus_cancels_header_grab() -> void:
	var window = WINDOW.instantiate()
	add_child_autofree(window)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	window._on_title_bar_gui_input(press)
	assert_true(window._dragging)
	window.hide()
	assert_false(window._dragging, "A hidden window must not retain a grab")
	window.show()
	window._on_title_bar_gui_input(press)
	window.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(window._dragging, "Alt-tab must release the closed-hand cursor")

func test_header_layout_is_compact_and_buttons_do_not_look_like_drag_handles() -> void:
	var window = WINDOW.instantiate()
	add_child_autofree(window)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lte(window.title_bar.size.y, 34.0)
	assert_eq(window.auto_sort_button.text, "Sort", "The bag action names what it does")
	assert_false(window.title_bar.is_ancestor_of(window.auto_sort_button))
	assert_lt(window.auto_sort_button.get_global_rect().end.y, window.inventory_grid.get_global_rect().position.y)
	assert_almost_eq(window.auto_sort_button.get_global_rect().end.x, window.inventory_grid.get_global_rect().end.x, 1.0)
	assert_gte(window.close_button.size.x, 28.0)
	assert_gte(window.auto_sort_button.size.x, 28.0)

func _header_pointer_motion(viewport: SubViewport, at: Vector2, buttons := 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = buttons
	viewport.push_input(event, true)

func _header_pointer_button(viewport: SubViewport, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	viewport.push_input(event, true)

func test_all_drag_sources_preview_and_land_under_the_ghost_center() -> void:
	var grid := InventoryGridControl.new()
	add_child_autofree(grid)
	var inventory := InventoryData.new()
	var sword: ItemDefinition = load("res://features/inventory/resources/items/steel_sword.tres")
	assert_true(inventory.add_item_count(sword, 1))
	grid.set_inventory_data(inventory)
	var received: Array[Vector2i] = []
	grid.drop_validator = func(_data, cell): return inventory.can_place_item(sword, cell, inventory.entries[0])
	grid.drop_handler = func(_data, cell): received.append(cell)
	var payloads := [
		{"entry": inventory.entries[0], "source_inventory": inventory},
		{"equipment_owner": self, "equip_slot": "weapon", "item_definition": sword},
		{"cursor_item": true, "item_definition": sword},
	]
	for data in payloads:
		# Center of a 30x126 item starting at column 2, row 0.
		assert_true(grid._can_drop_data(Vector2(79, 63), data))
		assert_true(grid._preview_visible, "Every supported source has a landing preview")
		assert_eq(grid._preview_rect, Rect2(64, 0, 30, 126))
		grid._drop_data(Vector2(79, 63), data)
		assert_eq(received.back(), Vector2i(2, 0), "Commit must match the highlighted cells")
		assert_false(grid._preview_visible)
		assert_false(grid._can_drop_data(Vector2(79, 15), data), "Centered item crossing the top edge is invalid, not silently relocated")
		assert_false(grid._preview_visible)

func test_stock_has_no_search_sort_or_instructional_prose() -> void:
	var panel = STOCK.new()
	add_child_autofree(panel)
	assert_eq(panel.find_children("*", "LineEdit", true, false).size(), 1, "Only the quantity field remains")
	assert_eq(panel.find_children("*", "OptionButton", true, false).size(), 0)
	assert_eq(panel.find_children("*", "Tree", true, false).size(), 0, "Stock is visual goods, not a spreadsheet")
	for label in panel.find_children("*", "Label", true, false):
		assert_false(label.text.contains("Select goods"))
		assert_false(label.text.contains("To sell:"))

func test_equipment_targets_are_large_and_icon_based() -> void:
	var slot := EquipmentSlotControl.new()
	add_child_autofree(slot)
	assert_gte(slot.custom_minimum_size.y, 52.0)
	assert_eq(slot.find_children("*", "TextureRect", true, false).size(), 1)

func test_cursor_drag_uses_item_art_not_a_text_panel() -> void:
	var source := CursorItemDragSource.new()
	add_child_autofree(source)
	source.item_definition = SEEDS
	source.item_count = 3
	var preview := source._make_drag_preview()
	autofree(preview)
	var icons := preview.find_children("*", "TextureRect", true, false)
	assert_eq(icons.size(), 1)
	if not icons.is_empty():
		assert_same(icons[0].texture, SEEDS.icon)
		assert_eq(icons[0].mouse_filter, Control.MOUSE_FILTER_IGNORE)

func test_equipment_layout_keeps_body_order_and_nonoverlapping_drop_targets() -> void:
	var layout = preload("res://features/ui/projection/equipment_layout.gd").new()
	add_child_autofree(layout)
	var slots: Dictionary = {}
	for slot_name in ["head", "chest", "legs", "feet", "weapon", "offhand", "hands", "undershirt", "backpack", "tail"]:
		var slot := EquipmentSlotControl.new()
		layout.add_child(slot)
		slot.setup(null, slot_name, slot_name)
		slots[slot_name] = slot
	layout.arrange()
	assert_lt(slots.head.position.y, slots.chest.position.y)
	assert_lt(slots.chest.position.y, slots.legs.position.y)
	assert_lt(slots.legs.position.y, slots.feet.position.y)
	assert_lt(slots.hands.position.y, slots.legs.position.y, "Handwear belongs beside the torso, not the feet")
	assert_gte(layout.custom_minimum_size.y, slots.tail.get_rect().end.y)
	for a in slots:
		for b in slots:
			if a != b:
				assert_false(slots[a].get_rect().intersects(slots[b].get_rect()), "%s overlaps %s" % [a, b])

func test_equipment_uses_race_authored_square_cells() -> void:
	var race := CharacterRaceDefinition.new()
	race.equipment_slot_grid_sizes = {"chest": Vector2i(3, 2)}
	var actor := HumanoidCharacter.new()
	autofree(actor)
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.character_race = race
	var slot := EquipmentSlotControl.new()
	add_child_autofree(slot)
	slot.setup(actor, "chest", "Chest")
	assert_eq(slot.grid_dimensions, Vector2i(3, 2))
	assert_eq(slot.custom_minimum_size, Vector2(94, 62), "Equipment uses the bag's 30-pixel cells and 2-pixel gaps")
	var style := slot.get_theme_stylebox("panel")
	assert_true(style is StyleBoxFlat, "Empty and filled targets need a visible backing, not an invisible hitbox")
	if style is StyleBoxFlat:
		assert_eq(style.bg_color.a, 1.0)

func test_race_slot_sizes_fallback_and_invalid_values() -> void:
	var race := CharacterRaceDefinition.new()
	race.equipment_slot_grid_sizes = {"chest": Vector2i(4, 3), "head": Vector2i(0, -1)}
	assert_eq(race.get_slot_grid_size("chest"), Vector2i(4, 3))
	assert_eq(race.get_slot_grid_size("head"), Vector2i.ONE)
	assert_eq(race.get_slot_grid_size("tail"), Vector2i(2, 2))
	assert_eq(CharacterRaceDefinition.new().get_slot_grid_size("chest"), Vector2i(2, 3), "Race edits must not leak into other races")

func test_large_race_equipment_areas_do_not_overlap() -> void:
	var race := CharacterRaceDefinition.new()
	race.equipment_slot_grid_sizes = {"head": Vector2i(4, 3), "chest": Vector2i(5, 4), "hands": Vector2i(3, 3), "backpack": Vector2i(4, 5)}
	var actor := HumanoidCharacter.new()
	autofree(actor)
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.character_race = race
	var layout = preload("res://features/ui/projection/equipment_layout.gd").new()
	add_child_autofree(layout)
	for slot_name in ["head", "chest", "legs", "feet", "weapon", "offhand", "hands", "undershirt", "backpack", "tail", "horns"]:
		var slot := EquipmentSlotControl.new()
		layout.add_child(slot)
		slot.setup(actor, slot_name, slot_name)
	layout.arrange()
	for a in layout.get_children():
		assert_lte(a.get_rect().end.x, layout.custom_minimum_size.x)
		assert_lte(a.get_rect().end.y, layout.custom_minimum_size.y)
		for b in layout.get_children():
			if a != b:
				assert_false(a.get_rect().intersects(b.get_rect()))
