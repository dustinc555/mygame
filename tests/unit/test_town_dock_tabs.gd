extends GutTest

const TOWN_DOCK := preload("res://addons/world_authoring/town_dock.gd")

class Town extends Node3D:
	var settlement_definition := SettlementDefinition.new()

class Tools extends RefCounted:
	var discoveries := 0
	var placements: Array[String] = []
	func get_town_facility_nodes(_town: Node) -> Array:
		discoveries += 1
		return []
	func begin_spawn_marker_placement(kind: String) -> void:
		placements.append(kind)
	func begin_guard_post_placement() -> void:
		placements.append("GuardSpot")

class Dock extends "res://addons/world_authoring/town_dock.gd":
	var saves := 0
	func _save_definition(_definition: Resource) -> void:
		saves += 1 # Never save a test fixture into the real author's resources.
	func _scan_resource_paths(_path: String) -> Array[String]:
		return []

func _field(page: Node, title: String) -> Control:
	for child in page.get_children():
		if child is HBoxContainer and child.get_child(0) is Label and child.get_child(0).text == title:
			return child.get_child(1)
		var nested := _field(child, title)
		if nested != null:
			return nested
	return null

func test_town_sections_use_full_width_pages_instead_of_columns() -> void:
	var dock := TOWN_DOCK.new()
	add_child_autofree(dock)
	dock.setup(RefCounted.new())
	var tabs := dock.get_child(1) as TabContainer
	assert_not_null(tabs, "Town sections must be tabs, not simultaneous columns")
	if tabs == null:
		return
	var titles: Array[String] = []
	for index in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(index))
	assert_eq(titles, ["General", "Population", "Economy", "Markers", "Facilities"])
	assert_false(tabs.use_hidden_tabs_for_min_size, "Hidden pages must not force the dock wider")
	for index in tabs.get_tab_count():
		var page := tabs.get_tab_control(index)
		assert_eq(page.custom_minimum_size.x, 0.0, "No fixed-width columns remain")
		if page is ScrollContainer:
			assert_eq(page.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)

func test_switching_tabs_preserves_widgets_scroll_and_does_not_scan_or_save() -> void:
	var tools := Tools.new()
	var town := Town.new()
	add_child_autofree(town)
	var dock := Dock.new()
	add_child_autofree(dock)
	dock.setup(tools)
	dock.size = Vector2(640, 260)
	dock.set_town(town)
	var tabs := dock.get_child(1) as TabContainer
	var name_edit := _field(tabs.get_tab_control(0), "Display Name") as LineEdit
	assert_not_null(name_edit)
	name_edit.text = "Unsubmitted edit"
	await wait_process_frames(3)
	var page := tabs.get_tab_control(0) as ScrollContainer
	page.scroll_vertical = 40
	var scroll_before := page.scroll_vertical
	var discoveries := tools.discoveries
	for index in [1, 2, 3, 4, 0]:
		tabs.current_tab = index
		await wait_process_frames(2)

	assert_same(_field(page, "Display Name"), name_edit, "Switching must retain existing controls")
	assert_eq(name_edit.text, "Unsubmitted edit")
	assert_eq(page.scroll_vertical, scroll_before)
	assert_eq(tools.discoveries, discoveries, "Tabs must not rescan town facilities")
	assert_eq(dock.saves, 0, "Tab navigation must not edit the definition")
	dock.refresh()
	assert_eq(tabs.current_tab, 0)
	tabs.current_tab = 3
	dock.refresh()
	assert_eq(tabs.current_tab, 3, "Explicit content refresh preserves the active page")

func test_moved_settings_and_marker_buttons_keep_their_original_actions() -> void:
	var tools := Tools.new()
	var town := Town.new()
	add_child_autofree(town)
	var dock := Dock.new()
	add_child_autofree(dock)
	dock.setup(tools)
	dock.set_town(town)
	var tabs := dock.get_child(1) as TabContainer
	var population := tabs.get_tab_control(1)
	var economy := tabs.get_tab_control(2)
	var guards := _field(population, "Guards") as SpinBox
	var growth := _field(population, "Growth / Day") as SpinBox
	var wealth := _field(economy, "Starting Wealth") as SpinBox
	assert_not_null(guards)
	assert_not_null(growth)
	assert_not_null(wealth)
	assert_null(_field(tabs.get_tab_control(0), "Guards"))
	assert_null(_field(population, "Starting Wealth"))
	guards.value = 7
	growth.value = 2.5
	wealth.value = 432.5
	assert_eq(town.settlement_definition.guard_count, 7)
	assert_eq(town.settlement_definition.population_growth_per_day, 2.5)
	assert_eq(town.settlement_definition.starting_wealth, 432.5)
	assert_eq(dock.saves, 3)
	for button in tabs.get_tab_control(3).find_children("*", "Button", true, false):
		button.pressed.emit()
	assert_eq(tools.placements, ["RoadSpawn", "DefenseSpawn", "GuardSpot"])
