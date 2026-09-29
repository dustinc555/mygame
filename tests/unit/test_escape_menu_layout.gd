extends GutTest

class MenuStatus extends WorldStatusController:
	var debug_enabled := true

	func _debug_enabled() -> bool:
		return debug_enabled

var _viewport: SubViewport
var _status: MenuStatus

func before_each() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1152, 648)
	add_child_autofree(_viewport)
	var hud := CanvasLayer.new()
	_viewport.add_child(hud)
	var overlay := Control.new()
	hud.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status = MenuStatus.new()
	_viewport.add_child(_status)
	_status.hud_layer = hud
	_status.pause_overlay = overlay
	_status.debug_menu = DebugMenu.new()
	hud.add_child(_status.debug_menu)
	_status._show_escape_menu()
	await _settle_layout()

func test_growing_debug_list_stays_centered_and_inside_the_screen() -> void:
	for index in 60:
		var button := Button.new()
		button.text = "Debug - Extra %d" % index
		_status.escape_menu_debug_buttons.add_child(button)
	await _settle_layout()
	_assert_centered_and_contained()
	var scroll := _status.escape_menu_debug_buttons.get_parent() as ScrollContainer
	assert_not_null(scroll, "Debug entries need a scrolling viewport, not an unbounded column")
	if scroll != null:
		assert_true(scroll.get_v_scroll_bar().visible, "Overflow exposes a scrollbar")
		assert_gt(_status.escape_menu_debug_buttons.size.y, scroll.size.y)

func test_window_resize_keeps_the_open_menu_centered_and_contained() -> void:
	for dimensions in [Vector2i(800, 480), Vector2i(1920, 1080), Vector2i(500, 320)]:
		_viewport.size = dimensions
		await _settle_layout()
		_assert_centered_and_contained()
		assert_lte(_status.escape_menu_panel.size.y, 560.0, "A large display does not stretch the list indefinitely")

func test_debug_disabled_hides_the_empty_list_without_leaving_a_tall_blank_panel() -> void:
	_status._hide_escape_menu(false)
	_status.debug_enabled = false
	_status._show_escape_menu()
	await _settle_layout()
	assert_eq(_status.escape_menu_debug_buttons.get_child_count(), 0)
	assert_false(_status.escape_menu_debug_scroll.visible)
	assert_lt(_status.escape_menu_panel.size.y, 160.0, "Without debug entries the menu fits its title and Resume")
	_assert_centered_and_contained()
	_status._hide_escape_menu(false)
	_status.debug_enabled = true
	_status._show_escape_menu()
	await _settle_layout()
	assert_eq(_status.escape_menu_debug_buttons.get_child_count(), _status.debug_menu.get_window_titles().size() + 1)
	assert_true(_status.escape_menu_debug_scroll.visible)
	_assert_centered_and_contained()

func test_mouse_wheel_reaches_and_activates_the_last_debug_entry() -> void:
	_viewport.size = Vector2i(800, 480)
	await _settle_layout()
	var scroll := _status.escape_menu_debug_scroll
	var resume_bounds := _status.escape_menu_resume_button.get_global_rect()
	var last := _status.escape_menu_debug_buttons.get_child(-1) as Button
	assert_eq(last.text, "Debug - GECS Log")
	assert_false(scroll.get_global_rect().encloses(last.get_global_rect()), "This test starts with the final entry clipped")
	for tick in 20:
		_pointer_button(scroll.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	await _settle_layout()
	assert_gt(scroll.scroll_vertical, 0, "Real wheel input scrolls the list")
	assert_true(scroll.get_global_rect().encloses(last.get_global_rect()), "The last entry becomes clickable")
	assert_eq(_status.escape_menu_resume_button.get_global_rect(), resume_bounds, "Resume does not move with the list")
	_pointer_button(last.get_global_rect().get_center())
	assert_true(_status.is_brain_log_visible(), "Clicking the scrolled entry invokes the existing debug action")

func test_resume_releases_only_the_pause_requested_by_this_menu() -> void:
	_status._hide_escape_menu(false)
	var clock := WorldTimeController.new()
	_viewport.add_child(clock)
	_status.world_time = clock
	clock.request_manual_pause()
	_status._show_escape_menu()
	await _settle_layout()
	_pointer_button(_status.escape_menu_resume_button.get_global_rect().get_center())
	assert_false(_status.escape_menu_panel.visible)
	assert_true(clock.is_manual_paused(), "An existing manual pause is not owned by the menu")
	clock.release_manual_pause()
	_status._show_escape_menu()
	await _settle_layout()
	assert_true(clock.is_manual_paused())
	_pointer_button(_status.escape_menu_resume_button.get_global_rect().get_center())
	assert_false(_status.escape_menu_panel.visible)
	assert_false(clock.is_manual_paused(), "Resume releases the menu's own pause")

func test_escape_still_opens_and_closes_the_scrollable_menu() -> void:
	for expected_visible in [false, true, false]:
		for down in [true, false]:
			var event := InputEventKey.new()
			event.keycode = KEY_ESCAPE
			event.pressed = down
			_viewport.push_input(event, true)
		await _settle_layout()
		assert_eq(_status.escape_menu_panel.visible, expected_visible)

func _pointer_button(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	_viewport.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = button
		event.pressed = down
		_viewport.push_input(event, true)

func _assert_centered_and_contained() -> void:
	var bounds := _status.escape_menu_panel.get_global_rect()
	var screen := Vector2(_viewport.size)
	assert_almost_eq(bounds.get_center().x, screen.x * 0.5, 1.0, "Menu stays horizontally centered")
	assert_almost_eq(bounds.get_center().y, screen.y * 0.5, 1.0, "Actual menu height stays vertically centered")
	assert_gte(bounds.position.y, 16.0, "Menu leaves space above it")
	assert_lte(bounds.end.y, screen.y - 16.0, "Menu leaves space below it")
	assert_true(bounds.encloses(_status.escape_menu_resume_button.get_global_rect()), "Resume remains on the menu")

func _settle_layout() -> void:
	for frame in 4:
		await get_tree().process_frame
