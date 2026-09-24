extends GutTest

const DOCK = preload("res://addons/world_authoring/facility_dock.gd")

class Tools extends RefCounted:
	var placed_for: Node
	func begin_guard_post_placement(facility: Node) -> void:
		placed_for = facility

func test_private_spot_button_is_in_markers_not_furniture_and_targets_selected_facility() -> void:
	var tools := Tools.new()
	var dock := DOCK.new()
	dock.setup(tools)
	autofree(dock)
	var facility := Node3D.new()
	autofree(facility)
	dock._facility = facility
	var markers: Control
	var furniture: Control
	for index in dock._tabs.get_tab_count():
		var page := dock._tabs.get_tab_control(index)
		if page.name == "Markers": markers = page
		if page.name == "Furniture": furniture = page
	assert_not_null(markers, "Private marker placement must have a discoverable Markers tab")
	assert_not_null(furniture)
	for button in furniture.find_children("*", "Button", true, false):
		assert_false(button.text.contains("Guard Spot"), "Markers must not be hidden among furniture")
	if markers == null:
		return
	var placement: Button
	for button in markers.find_children("*", "Button", true, false):
		if button.text == "Add Mercenary Spot": placement = button
	assert_not_null(placement)
	if placement != null:
		placement.pressed.emit()
		assert_same(tools.placed_for, facility)
		var other := Node3D.new()
		autofree(other)
		dock._facility = other
		placement.pressed.emit()
		assert_same(tools.placed_for, other, "Button must use current selection, not its initial facility")
