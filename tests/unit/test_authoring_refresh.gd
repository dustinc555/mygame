extends GutTest

# Count actual scheduled work without requiring Godot's editor-only widgets.
class CountingDock extends "res://addons/world_authoring/facility_dock.gd":
	var rebuilds := 0
	func _rebuild() -> void:
		rebuilds += 1

func test_selecting_same_facility_does_not_repeat_work() -> void:
	var dock := CountingDock.new()
	add_child_autofree(dock)
	var facility := Node.new()
	add_child_autofree(facility)
	dock.set_facility(facility)
	dock.set_facility(facility)
	dock.set_facility(facility)
	await get_tree().process_frame
	assert_eq(dock.rebuilds, 1, "Repeated selection notifications must share one refresh")
	dock.set_facility(facility)
	await get_tree().process_frame
	assert_eq(dock.rebuilds, 1, "Selecting a sibling inside the same facility is not a content edit")

class Facility extends Node:
	func supports_furniture() -> bool: return true
	func supports_building_shell() -> bool: return true

class SectionDock extends "res://addons/world_authoring/facility_dock.gd":
	var people_builds := 0
	var furniture_builds := 0
	var general_builds := 0
	func _rebuild_identity() -> void: general_builds += 1
	func _rebuild_field_section() -> void: pass
	func _rebuild_shell_list() -> void: pass
	func _rebuild_containers() -> void: pass
	func _rebuild_people() -> void: people_builds += 1
	func _rebuild_furniture_browser() -> void: furniture_builds += 1
	func _rebuild_furniture_summary() -> void: pass

class ShopPanel extends VBoxContainer:
	func set_shop(_shop: Node) -> void: pass

func test_hidden_sections_do_no_work_until_opened() -> void:
	var dock := SectionDock.new()
	dock._placeholder = Label.new()
	dock.add_child(dock._placeholder)
	dock._content = VBoxContainer.new()
	dock.add_child(dock._content)
	dock._tabs = TabContainer.new()
	dock._content.add_child(dock._tabs)
	for title in ["General", "Furniture", "Containers", "People", "Shop"]:
		var tab := Control.new()
		tab.name = title
		dock._tabs.add_child(tab)
	dock._shop_panel = ShopPanel.new()
	dock.add_child(dock._shop_panel)
	add_child_autofree(dock)
	var facility := Facility.new()
	add_child_autofree(facility)
	dock.set_facility(facility)
	await get_tree().process_frame
	assert_eq(dock.general_builds, 1)
	assert_eq(dock.people_builds, 0, "Hidden People cannot scan the town")
	assert_eq(dock.furniture_builds, 0, "Hidden Furniture cannot rebuild its catalog")
	dock._tabs.current_tab = 1
	dock._rebuild()
	assert_eq(dock.furniture_builds, 1)
	assert_eq(dock.general_builds, 1, "Switching tabs does not rebuild General")
	dock._rebuild()
	assert_eq(dock.furniture_builds, 1, "An unchanged visible tab stays intact")
	dock.refresh()
	dock.refresh()
	await get_tree().process_frame
	assert_eq(dock.furniture_builds, 2, "A content-edit burst refreshes the visible section once")
	assert_eq(dock.people_builds, 0)


func test_snap_visuals_never_leak_into_runtime() -> void:
	var marker := ModularBuildingSnapMarker.new()
	marker.runtime_show_visual = true # Old authored flags cannot leak guides.
	add_child_autofree(marker)
	await get_tree().process_frame
	assert_null(marker.get_node_or_null(ModularBuildingSnapMarker.VISUAL_NAME))


func test_thumbnail_includes_authored_visual_without_running_container() -> void:
	var source: Node = load("res://features/world/projection/props/furniture/barrel.tscn").instantiate()
	var visuals := Node3D.new()
	preload("res://addons/world_authoring/scene_thumbnail.gd")._copy_meshes(source, Transform3D.IDENTITY, visuals)
	assert_gt(visuals.get_child_count(), 0, "The barrel's exported visual_scene must appear in its thumbnail")
	assert_false(source.is_inside_tree(), "Preview must not run container/gameplay startup")
	source.free()
	visuals.free()


class CapacityShop extends Node:
	var merchant_profile: Resource
	var starting_silver := 0
	var stock_columns := 4
	var stock_rows := 4
	var replenishment_days := 3
	var replenishment_hour := 8
	var stock_overrides := {}
	var synchronous_checks := 0
	func effective_stock() -> Dictionary: return stock_overrides
	func stock_capacity_warning() -> String:
		synchronous_checks += 1
		return ""

class CatalogTools extends RefCounted:
	signal item_catalog_changed
	var items: Array = []
	func container_item_options(_kind: String) -> Array: return items

func test_shop_refresh_does_not_pack_inventory_in_the_click_handler() -> void:
	var panel := preload("res://addons/world_authoring/shop_panel.gd").new()
	add_child_autofree(panel)
	panel.setup(CatalogTools.new())
	var shop := CapacityShop.new()
	add_child_autofree(shop)
	panel.set_shop(shop)
	assert_eq(shop.synchronous_checks, 0, "Capacity validation must yield, not stall the editor click")
	await wait_process_frames(3)
	assert_eq(panel._capacity_warning.text, "")


func test_snap_context_is_only_the_standalone_shell() -> void:
	var town := Node3D.new()
	var shell := WorldBuilding.new()
	var marker := ModularBuildingSnapMarker.new()
	town.add_child(shell)
	shell.add_child(marker)
	assert_false(marker.is_shell_authoring_context(town))
	assert_true(marker.is_shell_authoring_context(shell))
	assert_false(marker.is_shell_authoring_context(null))
	town.free()


func test_capacity_feedback_cancels_stale_stock_edits() -> void:
	var panel := preload("res://addons/world_authoring/shop_panel.gd").new()
	add_child_autofree(panel)
	panel.setup(CatalogTools.new())
	var shop := CapacityShop.new()
	add_child_autofree(shop)
	shop.stock_overrides = {"res://features/inventory/resources/items/iron_sword.tres": {"quantity": 100}}
	panel.set_shop(shop)
	shop.stock_overrides = {}
	panel.refresh()
	await wait_process_frames(4)
	assert_eq(panel._capacity_warning.text, "", "The old over-capacity result cannot replace the new empty stock result")
	assert_false(panel._capacity_warning.visible)


class PlacementReceiver extends RefCounted:
	var calls: Array
	func _init(log: Array) -> void: calls = log
	func canceled() -> void: calls.append("cancel")
	func committed(_transform: Transform3D) -> void: calls.append("commit")

func _bind_placement_receiver(ghost: RefCounted, calls: Array) -> WeakRef:
	var receiver := PlacementReceiver.new(calls)
	ghost._on_commit = func(transform: Transform3D) -> void: receiver.committed(transform)
	ghost._on_cancel = func() -> void: receiver.canceled()
	return weakref(receiver)

func test_shop_catalog_arrival_and_invalidation_update_rows() -> void:
	var tools := CatalogTools.new()
	var panel := preload("res://addons/world_authoring/shop_panel.gd").new()
	add_child_autofree(panel)
	panel.setup(tools)
	var shop := CapacityShop.new()
	add_child_autofree(shop)
	panel.set_shop(shop)
	await wait_process_frames(3)
	assert_eq(panel._controls.size(), 0)
	var item := load("res://features/inventory/resources/items/iron_sword.tres") as ItemDefinition
	tools.items = [item]
	tools.item_catalog_changed.emit()
	await wait_process_frames(3)
	assert_true(panel._controls.has(item.resource_path), "The async catalog must populate the open shop")
	tools.items = []
	tools.item_catalog_changed.emit()
	await wait_process_frames(3)
	assert_eq(panel._controls.size(), 0, "Removed catalog entries cannot leave stale rows")

func test_finished_placement_releases_callback_owners() -> void:
	for commit in [false, true]:
		var ghost := preload("res://addons/world_authoring/placement_ghost.gd").new(null)
		var preview := Node3D.new()
		add_child(preview)
		ghost._preview = preview
		var calls: Array = []
		var reference := _bind_placement_receiver(ghost, calls)
		if commit: ghost._commit()
		else: ghost.cancel()
		assert_eq(calls, ["commit" if commit else "cancel"])
		assert_null(reference.get_ref(), "Completed previews must not retain tools and their catalogs")
		ghost.cancel()
		assert_eq(calls.size(), 1, "Cleanup cannot replay the callback")


func test_shop_background_work_survives_dock_unmount_and_remount() -> void:
	var tools := CatalogTools.new()
	var panel := preload("res://addons/world_authoring/shop_panel.gd").new()
	add_child(panel)
	panel.setup(tools)
	var shop := CapacityShop.new()
	add_child_autofree(shop)
	shop.stock_overrides = {"res://features/inventory/resources/items/iron_sword.tres": {"quantity": 100}}
	panel.set_shop(shop)
	remove_child(panel)
	tools.item_catalog_changed.emit()
	await wait_process_frames(3)
	shop.stock_overrides = {}
	add_child(panel)
	await wait_process_frames(4)
	assert_eq(panel._capacity_warning.text, "", "Remount resumes validation against current stock")
	panel.free()
