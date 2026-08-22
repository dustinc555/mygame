extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_bulk_take_all.gd

const PLATFORM_PATH := "res://features/world/projection/containers/bulk_storage_platform.tscn"
const WINDOW_PATH := "res://features/ui/projection/inventory_window.tscn"
const TOMATO := preload("res://features/inventory/resources/items/tomato.tres")

var failures: Array[String] = []
var _ecs_placeholder: Node


func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var platform := (load(PLATFORM_PATH) as PackedScene).instantiate()
	platform.container_id = "validation.bulk_take_all"
	root.add_child(platform)
	await process_frame
	platform.deposit_item_count(TOMATO, 30)
	var entry = platform.inventory.entries[0]
	_expect(platform.has_method("release_inventory_entry_count_with_metadata"), "bulk platform exposes a capacity-safe multi-item withdrawal transaction")
	if not platform.has_method("release_inventory_entry_count_with_metadata"):
		platform.free()
		_finish()
		return
	var actor_inventory := InventoryData.new(2, 2, 60.0, true)
	var stolen_metadata := {"stolen": true, "stolen_from_faction_id": "Market Ward"}
	var taken := int(platform.release_inventory_entry_count_with_metadata(entry, actor_inventory, entry.count, stolen_metadata))
	await process_frame
	_expect(taken == 4, "Take All takes exactly the four tomatoes that fit the actor grid")
	_expect(actor_inventory.count_item(TOMATO) == 4 and actor_inventory.entries.size() == 4, "taken tomatoes remain individual in actor inventory")
	_expect(platform.get_stored_item_count(TOMATO) == 26 and platform.inventory.entries.size() == 1 \
			and platform.get_displayed_visual_count() == 1, "overflow remains in the same authoritative one-stack one-crate platform entry")
	var all_stolen := true
	for actor_entry in actor_inventory.entries:
		all_stolen = all_stolen and bool(actor_entry.metadata.get("stolen", false))
	_expect(all_stolen and entry.metadata.is_empty(), "take metadata applies only to withdrawn units and never taints platform overflow")
	var weight_limited_inventory := InventoryData.new(10, 4, TOMATO.unit_weight * 2.0, true)
	var weight_taken := int(platform.release_inventory_entry_count_with_metadata(entry, weight_limited_inventory, entry.count, {}))
	_expect(weight_taken == 2 and weight_limited_inventory.count_item(TOMATO) == 2 \
			and platform.get_stored_item_count(TOMATO) == 24, "Take All stops at carry-weight capacity even when grid space remains")
	var stale_entry = platform.inventory.create_entry(TOMATO, Vector2i.ZERO, 1)
	_expect(not platform.can_release_inventory_entry_with_metadata(stale_entry, actor_inventory, {}), "stale stack references fail preflight before theft authorization")

	var window := (load(WINDOW_PATH) as PackedScene).instantiate() as InventoryWindow
	root.add_child(window)
	window.setup(platform)
	window.call("_on_inventory_item_right_clicked", entry, Vector2.ZERO, false)
	var popup := window.get_node("ItemMenu") as PopupMenu
	var labels: Array[String] = []
	for index in popup.item_count:
		labels.append(popup.get_item_text(index))
	_expect(labels.has("Take All"), "right-clicking a bulk-storage stack shows Take All")
	var emitted_actions: Array[String] = []
	window.item_action_requested.connect(func(_owner, _entry, action): emitted_actions.append(str(action)))
	window.call("_on_item_menu_id_pressed", 3)
	_expect(emitted_actions.has("take_all"), "Take All menu dispatches the canonical inventory action")

	root.remove_child(window)
	window.free()
	root.remove_child(platform)
	platform.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
	if failures.is_empty():
		print("BULK_TAKE_ALL_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BULK_TAKE_ALL_FAILED count=%d" % failures.size())
	quit(1)
