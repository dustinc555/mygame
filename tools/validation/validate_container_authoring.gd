extends SceneTree

## Container foundation contract: authored semantic types, exact one-time stock,
## indexed town lookup, plugin authoring, and reusable Sack furniture.
## Run: godot --headless --path . --script res://tools/validation/validate_container_authoring.gd

const CONTAINER_SCENE := "res://features/world/projection/containers/container.tscn"
const DOCK_SCRIPT := "res://addons/world_authoring/facility_dock.gd"
const FACILITY_TOOLS_SCRIPT := "res://addons/world_authoring/facility_tools.gd"
const PLUGIN_SCRIPT := "res://addons/world_authoring/plugin.gd"
const STOCK_CONTROLLER_SCRIPT := "res://features/inventory/sim/inventory_stock_controller.gd"
const SACK_SCENE := "res://features/world/projection/props/furniture/sack.tscn"
const SACK_2_SCENE := "res://features/world/projection/props/furniture/sack_2.tscn"
const SEED_SACK_SCENE := "res://features/world/projection/props/furniture/seed_sack.tscn"
const TOMATO_SEEDS := preload("res://features/inventory/resources/items/tomato_seeds.tres")
const HOE := preload("res://features/inventory/resources/items/hoe.tres")
const IRON_SWORD := preload("res://features/inventory/resources/items/iron_sword.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_semantic_type_and_exact_stock()
	await _validate_index_contract()
	_validate_plugin_contract()
	_validate_sack_family()
	_finish()


func _validate_semantic_type_and_exact_stock() -> void:
	var scene := load(CONTAINER_SCENE) as PackedScene
	_expect(scene != null, "Base container scene must load")
	if scene == null:
		return
	var container := scene.instantiate()
	if not _has_property(container, "container_type"):
		_fail("WorldContainer must expose a container_type property")
		container.free()
		return
	container.set("container_type", "seeds")
	var stock := InventoryStock.new()
	stock.item_definition = TOMATO_SEEDS
	stock.quantity = 12
	var stocks: Array[InventoryStock] = [stock]
	container.set("starting_items", stocks)
	root.add_child(container)
	await process_frame
	_expect(str(container.get("container_type")) == "seeds", "Container type must persist as Seeds")
	_expect(str(container.get("container_kind")) == "farm_seed", "Seeds type must map to farm_seed routing")
	container.display_name = "Sack"
	_expect(str(container.call("get_inventory_display_name")) == "Seed Sack", "Assigning Seeds to generic Sack furniture must make it read as Seed Sack")
	_expect(container.inventory.count_item(TOMATO_SEEDS) == 12, "Exact authored seed stock must seed once (count=%d starting=%d type=%s)" % [container.inventory.count_item(TOMATO_SEEDS), container.starting_items.size(), str(container.container_type)])
	_expect(container.inventory.can_add_item_count(TOMATO_SEEDS, 1), "Seeds container must accept seeds")
	_expect(not container.inventory.can_add_item_count(HOE, 1), "Seeds container must reject tools")
	container.set("container_type", "tools")
	_expect(not container.inventory.can_add_item_count(IRON_SWORD, 1), "Tools filtering must safely reject legacy items whose tool_tags resource value is null")
	_expect(IRON_SWORD.has_method("has_any_tool_tag") and not bool(IRON_SWORD.call("has_any_tool_tag")), "Legacy null tool_tags must be normalized through one Variant-safe item API")

	container.queue_free()
	await process_frame


func _validate_index_contract() -> void:
	var script := load(STOCK_CONTROLLER_SCRIPT) as Script
	var controller: Node = script.new() if script != null else null
	_expect(controller != null and controller.has_method("get_live_container_candidates"), "Inventory stock index must expose live candidates by settlement and container type")
	if controller != null:
		root.add_child(controller)
		var sack := (load(SEED_SACK_SCENE) as PackedScene).instantiate()
		sack.container_id = "town.seed_sack"
		sack.settlement_id = "town"
		root.add_child(sack)
		await process_frame
		controller.call("bind_world_container", sack)
		var town_seeds: Array = controller.call("get_live_container_candidates", "town", PackedStringArray(["seeds"]))
		_expect(town_seeds == [sack], "Indexed Seeds lookup must return only the town's live Seed Sack")
		_expect((controller.call("get_live_container_candidates", "other", PackedStringArray(["seeds"])) as Array).is_empty(), "Indexed lookup must not leak containers across towns")
		controller.call("detach_world_container", sack.container_id, sack)
		_expect((controller.call("get_live_container_candidates", "town", PackedStringArray(["seeds"])) as Array).is_empty(), "Detached containers must leave the index immediately")
		sack.queue_free()
		controller.queue_free()
		await process_frame


func _validate_plugin_contract() -> void:
	var script := load(DOCK_SCRIPT) as Script
	var dock := script.new() as Control if script != null else null
	_expect(dock != null, "Facility dock must compile")
	if dock == null:
		return
	dock.call("setup", RefCounted.new())
	var tabs := dock.get("_tabs") as TabContainer
	var names: Array[String] = []
	if tabs != null:
		for child in tabs.get_children():
			names.append(str(child.name))
	_expect(names == ["General", "Furniture", "Containers", "People"], "Facility workspace must expose a dedicated Containers tab")
	_expect(dock.has_method("set_container"), "Facility dock must edit a directly selected one-off container")
	var dock_source := FileAccess.get_file_as_string(DOCK_SCRIPT)
	var list_selection_source := dock_source.get_slice("_container_list.item_selected.connect", 1).get_slice("_container_list.item_activated.connect", 0)
	_expect(list_selection_source.contains("_select_container_from_list") and not list_selection_source.contains("select_container_from_dock"), "Single-click container switching must stay local and immediate")
	_expect(dock_source.contains("_container_list.item_activated.connect") and dock_source.contains("select_container_from_dock"), "Explicit double-click must remain available for scene-tree/viewport selection")
	_expect(dock_source.contains("func _select_container_from_list"), "Container switching needs one lightweight path that does not rebuild its list")
	_expect(dock_source.contains("str(candidate.name)") and dock_source.contains("get_inventory_display_name"), "Container rows must identify both the scene node and its semantic furniture name")
	var standalone := (load(SACK_SCENE) as PackedScene).instantiate()
	dock.call("set_container", standalone)
	dock.call("_rebuild")
	_expect(bool((dock.get("_content") as Control).visible) and not bool((dock.get("_placeholder") as Control).visible), "A standalone one-off container must open the same Containers workspace without a facility")
	standalone.free()
	dock.free()
	var tools_source := FileAccess.get_file_as_string(FACILITY_TOOLS_SCRIPT)
	_expect(tools_source.contains("node.set(\"owner_faction_name\"") and tools_source.contains("func _facility_owner_faction_id"), "Furnished containers must inherit their facility/town owner")
	_expect(tools_source.contains("object is WorldContainer") and tools_source.contains("node is WorldContainer"), "Facility tools must claim directly selected standalone containers")
	var dock_sync_source := tools_source.get_slice("func select_container_from_dock", 1).get_slice("## Reset to a plain rectangle", 0)
	_expect(dock_sync_source.contains("select_node_without_context_refresh") and not dock_sync_source.contains("_select_node(container)"), "Dock selection must bypass the expensive global editor refresh path")
	var plugin_source := FileAccess.get_file_as_string(PLUGIN_SCRIPT)
	_expect(plugin_source.contains("func select_node_without_context_refresh") and plugin_source.contains("_suppress_selection_refresh"), "The world-authoring router must suppress every context refresh during dock-driven selection")
	var mutation_source := tools_source.get_slice("func set_container_property", 1).get_slice("func set_container_starting_item_amount", 0)
	_expect(not mutation_source.contains("_refresh_ui()"), "Container property edits must never rebuild the full Facility dock")
	_expect(dock_source.contains("func refresh_container_property"), "Container edits must use one lightweight local refresh path")
	_expect(tools_source.contains("_container_tool_item_paths") and tools_source.contains("_resource_declares_tool_tags") and not tools_source.contains("item.tool_tags.is_empty()"), "Editor tools filtering must classify raw resource data without executing placeholder item scripts")


func _validate_sack_family() -> void:
	for path in [SACK_SCENE, SACK_2_SCENE, SEED_SACK_SCENE]:
		_expect(ResourceLoader.exists(path) and load(path) is PackedScene, "Missing reusable container scene: %s" % path)
	if ResourceLoader.exists(SEED_SACK_SCENE):
		var sack := (load(SEED_SACK_SCENE) as PackedScene).instantiate()
		_expect(_has_property(sack, "container_type") and str(sack.get("container_type")) == "seeds", "Seed Sack must be Sack furniture assigned the Seeds type")
		sack.free()


func _has_property(value: Object, property_name: String) -> bool:
	if value == null:
		return false
	for property in value.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("CONTAINER_AUTHORING_OK")
	else:
		print("CONTAINER_AUTHORING_FAILED count=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
