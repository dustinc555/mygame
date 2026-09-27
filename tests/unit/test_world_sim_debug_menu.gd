extends GutTest

const MENU_PATH := "res://features/world_sim/projection/world_sim_debug_menu.gd"

func test_world_sim_is_discoverable_in_the_existing_debug_menu() -> void:
	var debug := DebugMenu.new()
	add_child_autofree(debug)
	assert_has(debug.get_window_titles(), "World Sim")
	debug.toggle_window("World Sim")
	assert_true(debug.is_window_open("World Sim"))
	var panel := debug.find_child("CampAttack", true, false)
	assert_not_null(panel)
	if panel != null:
		assert_true(panel.is_visible_in_tree())
	debug.toggle_window("World Sim")
	assert_false(debug.is_window_open("World Sim"))

func test_action_browser_filters_categories_and_shows_only_the_selected_panel() -> void:
	if not ResourceLoader.exists(MENU_PATH):
		fail_test("World Sim needs an extensible action browser")
		return
	var menu = load(MENU_PATH).new()
	add_child_autofree(menu)
	var attack := VBoxContainer.new()
	var time := VBoxContainer.new()
	menu.add_action("attack", "Squads", "Spawn Attack", attack)
	menu.add_action("time", "Clock", "Advance Time", time)
	assert_true(attack.visible)
	assert_false(time.visible)
	var search: LineEdit = menu.find_child("ActionSearch", true, false)
	search.text = "clock"
	search.text_changed.emit(search.text)
	assert_false(attack.visible)
	assert_true(time.visible)
	var actions: Tree = menu.find_child("ActionList", true, false)
	assert_eq(actions.get_root().get_child_count(), 1)
	assert_eq(actions.get_root().get_first_child().get_text(0), "Clock")
	search.text = "nothing matches"
	search.text_changed.emit(search.text)
	assert_false(attack.visible)
	assert_false(time.visible)
	assert_eq(actions.get_root().get_child_count(), 0)
	search.clear()
	search.text_changed.emit(search.text)
	assert_eq(actions.get_root().get_child_count(), 2)
	assert_true(attack.visible)

func test_spawn_form_fits_the_default_window_without_hiding_the_result() -> void:
	var debug := DebugMenu.new()
	add_child_autofree(debug)
	debug.toggle_window("World Sim")
	for frame in 4:
		await get_tree().process_frame
	var panel: Control = debug.find_child("CampAttack", true, false)
	var scroll: ScrollContainer = debug.find_child("ActionScroll", true, false)
	var result: Label = panel.find_child("CommandStatus", true, false)
	assert_lte(panel.get_combined_minimum_size().y, scroll.size.y, "the complete form fits without scrolling")
	assert_true(scroll.get_global_rect().encloses(result.get_global_rect()), "command feedback stays visible")

func test_many_actions_scroll_without_expanding_the_browser() -> void:
	var menu = load(MENU_PATH).new()
	add_child_autofree(menu)
	menu.size = Vector2(660, 340)
	for index in 60:
		menu.add_action("action.%d" % index, "Category %d" % (index / 10), "Action %d" % index, VBoxContainer.new())
	for frame in 4:
		await get_tree().process_frame
	var actions: Tree = menu.find_child("ActionList", true, false)
	assert_lte(menu.size.y, 340.0)
	assert_eq(actions.get_root().get_child_count(), 6)
	var search: LineEdit = menu.find_child("ActionSearch", true, false)
	search.text = "Action 59"
	search.text_changed.emit(search.text)
	assert_eq(actions.get_root().get_child_count(), 1)
	assert_eq(actions.get_selected().get_metadata(0), "action.59")
