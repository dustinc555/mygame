extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_bulk_storage_policy.gd

const PLATFORM_PATH := "res://features/world/projection/containers/bulk_storage_platform.tscn"
const ITEM_DIRECTORY := "res://features/inventory/resources/items"
const TOMATO := preload("res://features/inventory/resources/items/tomato.tres")
const COPPER_ORE := preload("res://features/inventory/resources/items/copper_ore.tres")

var failures: Array[String] = []
var _ecs_placeholder: Node


class ActorFixture:
	extends Node
	var faction_name := ""


func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	_validate_item_stack_rules()
	var scene := load(PLATFORM_PATH) as PackedScene
	_expect(scene != null, "bulk platform loads")
	if scene == null:
		_finish()
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var platform = scene.instantiate()
	platform.container_id = "validation.bulk_storage_policy"
	platform.owner_faction_name = "Player"
	holder.add_child(platform)
	await process_frame

	_expect(not platform.supports_locking and not platform.is_locked, "storage platform is permanently open and not lockable")
	var details: Dictionary = platform.get_details_panel_data_at(Vector3.ZERO)
	var rows: Array = details.get("info_rows", [])
	_expect(rows.size() == 1 and str(rows[0].get("label", "")) == "Ownership" and str(rows[0].get("value", "")) == "Player", "platform details expose ownership as the only info row")
	_expect(str(details.get("state", "")).is_empty(), "platform details expose no Cache, Openable, or lock status")

	var owner := ActorFixture.new()
	owner.faction_name = "Player"
	holder.add_child(owner)
	var foreign := ActorFixture.new()
	foreign.faction_name = "Market Ward"
	holder.add_child(foreign)
	var owner_actions: Array = platform.get_details_panel_actions_at(Vector3.ZERO, owner)
	var foreign_actions: Array = platform.get_details_panel_actions_at(Vector3.ZERO, foreign)
	_expect(owner_actions.size() == 1 and str(owner_actions[0].get("label", "")) == "Set Storage Type" and not bool(owner_actions[0].get("disabled", true)), "owner sees Set Storage Type as the only special action")
	_expect(foreign_actions.size() == 1 and bool(foreign_actions[0].get("disabled", false)), "foreign actor cannot edit storage policy")
	_expect(not _actions_include(owner_actions, "Open") and not _actions_include(owner_actions, "Lock"), "platform special actions never include Open, Lock, or Unlock")

	var player_inventory := InventoryData.new(10, 4, 0.0, false)
	_expect(player_inventory.add_item_count(TOMATO, 2) and player_inventory.entries.size() == 2, "two tomatoes occupy two ordinary player inventory entries")
	_expect(platform.deposit_item_count(TOMATO, 50), "platform accepts 50 tomatoes through its storage-only stack policy")
	await process_frame
	_expect(platform.inventory.entries.size() == 2 and platform.inventory.entries[0].count == 30 and platform.inventory.entries[1].count == 20, "50 tomatoes form exactly two platform stacks capped to one crate each")
	_expect(platform.get_displayed_visual_count() == platform.inventory.entries.size(), "every platform stack maps to exactly one visible crate")
	_expect(platform.deposit_item_count(TOMATO, 25), "platform accepts another 25 tomatoes")
	await process_frame
	_expect(platform.get_stored_item_count(TOMATO) == 75 and platform.inventory.entries.size() == 3 \
			and platform.get_displayed_visual_count() == 3, "75 tomatoes form three stacks and exactly three visible crates")
	_expect(platform.inventory.entries[0].count == 30 and platform.inventory.entries[1].count == 30 \
			and platform.inventory.entries[2].count == 15, "75 tomatoes pack as 30, 30, and 15 with no stack spanning multiple crates")
	platform.withdraw_item_count(TOMATO, 25)
	var saved_entry = platform.inventory.entries[0]
	var reloaded = scene.instantiate()
	reloaded.container_id = "validation.bulk_storage_policy.reloaded"
	reloaded.owner_faction_name = "Player"
	holder.add_child(reloaded)
	await process_frame
	reloaded.hydrate_storage_policy_from_gecs(false, false, {})
	reloaded.hydrate_inventory_from_gecs([{
		"definition": TOMATO,
		"item_definition_path": TOMATO.resource_path,
		"count": 50,
		"grid_position": Vector2i(4, 2),
		"contained_item_counts": {},
		"metadata": {},
		"stack_id": saved_entry.stack_id,
	}], 2)
	await process_frame
	_expect(reloaded.get_stored_item_count(TOMATO) == 50 and reloaded.inventory.entries.size() == 2, "authoritative saved stock hydrates into one stack per crate even when the current filter disallows new deposits")
	_expect(reloaded.inventory.entries[0].grid_position == Vector2i(4, 2), "world-container hydration preserves the persisted grid position")
	var actor_inventory := InventoryData.new(6, 5, 0.01, true)
	actor_inventory.hydrate_entry_with_contents(TOMATO, Vector2i(3, 1), 1, {}, {"owner": "saved"}, "saved.actor.tomato", false)
	_expect(actor_inventory.entries.size() == 1 and actor_inventory.entries[0].grid_position == Vector2i(3, 1) \
			and str(actor_inventory.entries[0].metadata.get("owner", "")) == "saved", "actor hydration primitive preserves position and metadata without applying current capacity limits")
	holder.remove_child(reloaded)
	reloaded.free()

	var filters: Array = platform.get_storage_filter_options()
	_expect(filters.size() == 2 and str(filters[0].get("label", "")) == "Food" and str(filters[1].get("label", "")) == "Materials", "filter popup has Food and Materials parent checkboxes")
	_expect(bool(filters[0].get("selected", false)) and not bool(filters[1].get("selected", true)), "default policy enables all food and disables materials")
	_expect(platform.set_storage_category_enabled("food", false, owner), "owner can disable the Food parent")
	_expect(not platform.is_storage_item_enabled(TOMATO), "disabling Food disables tomato")
	_expect(platform.set_storage_item_enabled(TOMATO.item_id, true, owner), "owner can enable a specific food leaf")
	filters = platform.get_storage_filter_options()
	_expect(bool(filters[0].get("indeterminate", false)), "specific food selection makes the Food parent indeterminate")
	_expect(not platform.set_storage_category_enabled("materials", true, foreign), "foreign actor cannot enable Materials")
	_expect(platform.set_storage_category_enabled("materials", true, owner), "owner can enable all Materials")
	_expect(platform.is_storage_item_enabled(COPPER_ORE), "enabling Materials enables copper ore")
	_expect(platform.withdraw_item_count(TOMATO, 50), "existing food can be cleared before changing commodity")
	_expect(platform.deposit_item_count(COPPER_ORE, 20), "enabled material can be stored through the same platform stack policy")
	await process_frame
	_expect(platform.inventory.entries.size() == 1 and platform.inventory.entries[0].definition == COPPER_ORE and platform.inventory.entries[0].count == 20, "material storage uses the ordinary Copper Ore item stack")
	_expect(platform.get_displayed_visual_count() == 1, "20 copper ore produces one bounded material crate visual")

	holder.free()
	_finish()


func _validate_item_stack_rules() -> void:
	var directory := DirAccess.open(ITEM_DIRECTORY)
	_expect(directory != null, "item resource directory opens")
	if directory == null:
		return
	for filename in directory.get_files():
		if not filename.ends_with(".tres"):
			continue
		var item := load("%s/%s" % [ITEM_DIRECTORY, filename]) as ItemDefinition
		if item == null:
			continue
		if filename.ends_with("_seeds.tres"):
			_expect(item.max_stack > 1, "%s remains stackable seed inventory" % item.display_name)
		else:
			_expect(item.max_stack == 1, "%s remains unstacked in ordinary inventory" % item.display_name)


func _actions_include(actions: Array, label: String) -> bool:
	for action in actions:
		if str(action.get("label", "")) == label:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
	if failures.is_empty():
		print("BULK_STORAGE_POLICY_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BULK_STORAGE_POLICY_FAILED count=%d" % failures.size())
	quit(1)
