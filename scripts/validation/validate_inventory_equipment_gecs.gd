extends SceneTree

class EcsPlaceholder:
	extends Node
	var debug := false

const DEMO_WORLD_SCENE_PATH := "res://scenes/worlds/demo_world/demo_world.tscn"
const BANDAGE_PATH := "res://resources/items/consumables/bandage.tres"
const SILVER_PATH := "res://resources/items/currency/silver_coin.tres"
const STEEL_SWORD_PATH := "res://resources/items/equipment/weapons/swords/steel_sword.tres"
const BATTLE_SIM_SCRIPT := preload("res://scripts/sim/battle/battle_sim.gd")
const SILVER_ID := "silver_coin"
const STEEL_SWORD_ID := "steel_sword"

var _failures: Array[String] = []
var _ecs_placeholder: Node
var _registered_ecs_placeholder := false


func _initialize() -> void:
	_ensure_ecs_placeholder()
	var scene_resource := load(DEMO_WORLD_SCENE_PATH) as PackedScene
	if scene_resource == null:
		_failures.append("Demo world scene loads for inventory validation")
		_finish()
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	call_deferred("_run_validation", scene)


func _run_validation(scene: Node) -> void:
	for _index in range(18):
		await process_frame
	_promote_root_ecs_singleton()
	var bootstrap := scene.get_node_or_null("GameBootstrap")
	_expect(bootstrap != null, "GameBootstrap exists for inventory validation")
	if bootstrap == null:
		_finish()
		return
	var gecs := bootstrap.get_node_or_null("GecsWorldController")
	var inventory_controller := bootstrap.get_node_or_null("PartyInventoryController")
	var inventory_runner := bootstrap.get_node_or_null("WorldInventoryFixedTickRunner")
	var inventory_sim := bootstrap.get_node_or_null("WorldInventorySimController")
	var item_projection := bootstrap.get_node_or_null("WorldItemProjectionController")
	var selection_controller := bootstrap.get_node_or_null("WorldSelectionController")
	var player_control := bootstrap.get_node_or_null("WorldPlayerControlController")
	_expect(gecs != null and gecs.has_method("apply_inventory_command"), "GECS inventory command surface exists")
	_expect(inventory_controller != null and inventory_controller.has_method("open_inventory_for_actor_id"), "PartyInventoryController exists")
	_expect(inventory_runner != null and inventory_runner.has_method("queue_command"), "Inventory fixed tick runner exists")
	_expect(inventory_sim != null and inventory_sim.has_method("apply_sim_commands"), "WorldInventorySimController exists")
	_expect(item_projection != null and item_projection.has_method("sync_world_items"), "WorldItemProjectionController exists")
	_expect(selection_controller != null, "WorldSelectionController exists")
	_expect(player_control != null, "WorldPlayerControlController exists")
	if gecs == null or inventory_controller == null or inventory_runner == null or inventory_sim == null or item_projection == null or selection_controller == null or player_control == null:
		_finish()
		return

	_validate_item_definition_index()
	await _validate_inventory_window(gecs, inventory_controller, selection_controller, player_control)
	_validate_container_single_counts_and_layout(gecs, "player.mira.inventory", "Mira starting inventory")
	_validate_container_single_counts_and_layout(gecs, "player.tomas.inventory", "Tomas starting inventory")
	_validate_equipment_commands(gecs, inventory_runner)
	_validate_transfer_command(gecs, inventory_runner)
	_validate_drop_pickup_commands(gecs, inventory_runner, item_projection)
	_validate_no_stack_commands_and_import(gecs)
	_finish()


func _validate_inventory_window(gecs: Node, inventory_controller: Node, selection_controller: Node, player_control: Node) -> void:
	_expect(bool(selection_controller.call("select_actor_id", "player.mira")), "Can select Mira for inventory")
	inventory_controller.call("open_inventory_for_actor_id", "player.mira")
	await process_frame
	var window = inventory_controller.call("get_open_inventory_window", "player.mira")
	_expect(window != null, "Inventory action opens Mira inventory window")
	if window == null:
		return
	var model = window.get("inventory_owner")
	_expect(model != null and model.has_method("get_stack_snapshot"), "Inventory window uses GECS view model")
	if model == null:
		return
	var inventory: InventoryData = model.call("get_inventory_for_display")
	_expect(inventory != null and inventory.entries.size() > 0, "Inventory window displays GECS item entries")
	var title_bar := (window as Node).get_node_or_null("Margin/WindowVBox/TitleBar") as Control
	_expect(title_bar != null and title_bar.mouse_default_cursor_shape == Control.CURSOR_MOVE, "Inventory title bar uses move cursor")
	var moved_position := Vector2(148.0, 186.0)
	window.position = moved_position
	inventory_controller.call("_refresh_open_windows")
	await process_frame
	_expect(window.position == moved_position, "Inventory refresh preserves user-moved window position")
	var bandage_entry = _entry_for_item(inventory, BANDAGE_PATH)
	_expect(bandage_entry != null and not str(bandage_entry.stack_id).is_empty(), "Inventory entries carry stable stack IDs")
	_expect(bandage_entry != null and bandage_entry.definition.icon != null, "Inventory entries display item icons")
	_expect(model.call("get_equipment_slot_names").has("weapon"), "Inventory window exposes equipment slots")
	var weapon = model.call("get_equipped_item", "weapon")
	_expect(weapon != null and str(weapon.resource_path) == STEEL_SWORD_PATH, "Inventory window displays GECS equipped weapon")
	_expect(window.has_method("get_combat_stats_debug_state"), "Inventory window exposes Combat Stats debug state")
	var gear_state: Dictionary = window.call("get_combat_stats_debug_state") if window.has_method("get_combat_stats_debug_state") else {}
	var layout_state: Dictionary = window.call("get_inventory_layout_debug_state") if window.has_method("get_inventory_layout_debug_state") else {}
	var body_order: Array = layout_state.get("body_order", []) if layout_state.get("body_order", []) is Array else []
	var gear_effects: Dictionary = gear_state.get("effects", {}) if gear_state.get("effects", {}) is Dictionary else {}
	_expect(bool(layout_state.get("has_body", false)), "Inventory window uses horizontal body layout")
	_expect(body_order == ["InventoryGrid", "EquipmentSection", "CombatStatsSection"], "Inventory body orders grid, equipment, combat stats left-to-right")
	_expect(int(layout_state.get("equipment_columns", 0)) == 2, "Inventory equipment slots use two columns")
	_expect(int(layout_state.get("combat_stat_columns", 0)) == 2, "Inventory Combat Stats uses two columns")
	_expect(bool(gear_state.get("visible", false)), "Inventory window shows Combat Stats for character inventory")
	_expect(int(gear_state.get("columns", 0)) == 2, "Inventory Combat Stats debug state reports two columns")
	_expect(gear_effects.has("Damage"), "Inventory Combat Stats group modifiers by player-facing stat")
	_expect(gear_effects.has("Strength"), "Inventory Combat Stats show unmodified stats")
	var damage_effect: Dictionary = gear_effects.get("Damage", {}) if gear_effects.get("Damage", {}) is Dictionary else {}
	var strength_effect: Dictionary = gear_effects.get("Strength", {}) if gear_effects.get("Strength", {}) is Dictionary else {}
	var strength_sources: Array = strength_effect.get("sources", []) if strength_effect.get("sources", []) is Array else []
	_expect(str(damage_effect.get("summary", "")).begins_with("Damage "), "Inventory Combat Stat summary uses player-facing label")
	_expect(str(damage_effect.get("base", "")).begins_with("Base "), "Inventory Combat Stat shows base value")
	_expect(str(damage_effect.get("final", "")).begins_with("Final "), "Inventory Combat Stat shows final value")
	_expect(str(strength_effect.get("summary", "")).begins_with("Strength "), "Unmodified Combat Stat renders its value")
	_expect(strength_sources.is_empty(), "Unmodified Combat Stats render without source rows")
	var damage_sources: Array = damage_effect.get("sources", []) if damage_effect.get("sources", []) is Array else []
	var damage_source_tones: Array = damage_effect.get("source_tones", []) if damage_effect.get("source_tones", []) is Array else []
	_expect(_array_text_contains(damage_sources, "+9"), "Inventory Combat Stat shows signed contribution before item")
	_expect(_array_text_contains(damage_sources, "Steel Sword"), "Inventory Combat Stat source uses item display name")
	_expect(damage_source_tones.has("positive"), "Inventory positive Combat Stat modifier is marked green")
	_expect(not _gear_effect_text(gear_effects).contains("attack_damage"), "Inventory Combat Stats do not render raw stat IDs")
	_expect(not _gear_effect_text(gear_effects).contains("res://"), "Inventory Combat Stats do not render resource paths")
	_expect(not _gear_effect_text(gear_effects).contains("item_definition_path"), "Inventory Combat Stats do not render raw dictionaries")
	var record: Dictionary = gecs.call("get_population_record", "player.mira")
	var entries: Array = record.get("inventory_entries", []) if record.get("inventory_entries", []) is Array else []
	_expect(entries.size() > 0 and str(entries[0].get("stack_id", "")).strip_edges() != "", "Population inventory snapshots preserve stack IDs")
	_expect(entries.size() > 0 and not str(entries[0].get("item_id", "")).begins_with("res://"), "Population inventory snapshots expose stable item IDs")
	_expect(not bool(player_control.call("_ui_blocks_control")), "Open inventory window does not globally block world controls")
	var mira_position: Vector3 = record.get("last_world_position", Vector3.ZERO)
	var move_target := mira_position + Vector3(1.5, 0.0, 0.0)
	_expect(bool(player_control.call("issue_move_command_at_world_position", move_target, false)), "Move command works while inventory window is open")
	_expect(bool(selection_controller.call("select_actor_id", "player.tomas")), "Can select Tomas while inventory is open")
	await process_frame
	var tomas_window = inventory_controller.call("get_open_inventory_window", "player.tomas")
	var old_mira_window = inventory_controller.call("get_open_inventory_window", "player.mira")
	_expect(tomas_window != null, "Selecting another actor switches the primary inventory window")
	_expect(old_mira_window == null, "Selecting another actor closes the old primary inventory window")


func _validate_equipment_commands(gecs: Node, inventory_runner: Node) -> void:
	var base_record: Dictionary = gecs.call("get_population_record", "player.mira")
	var base_damage := float(base_record.get("base_attack_damage", 0.0))
	var equipped_profile: Dictionary = gecs.call("get_actor_stat_profile", "player.mira", base_record)
	var equipped_stats: Dictionary = equipped_profile.get("effective_stats", {}) if equipped_profile.get("effective_stats", {}) is Dictionary else {}
	_expect(float(equipped_stats.get("attack_damage", 0.0)) > base_damage, "Equipped sword increases derived attack damage")
	var battle_record: Dictionary = gecs.call("get_actor_battle_member_record", "player.mira", base_record)
	_expect(float(battle_record.get("effective_attack_damage", 0.0)) > base_damage, "Battle member record exposes equipped attack damage")
	var base_profile: Dictionary = BATTLE_SIM_SCRIPT._combat_profile({"squad_id": "validation.base", "member_records": [base_record]})
	var derived_profile: Dictionary = BATTLE_SIM_SCRIPT._combat_profile({"squad_id": "validation.derived", "member_records": [battle_record]})
	_expect(float(derived_profile.get("base_power", 0.0)) > float(base_profile.get("base_power", 0.0)), "BattleSim uses derived equipment combat stats")
	_expect(is_equal_approx(float(gecs.call("get_population_record", "player.mira").get("base_attack_damage", 0.0)), base_damage), "Derived stat profile does not mutate stored base damage")
	var sword := load(STEEL_SWORD_PATH) as ItemDefinition
	var target_cell := _first_space_for_item(gecs, "player.mira.inventory", sword)
	_expect(target_cell != Vector2i(-1, -1), "Mira inventory has room to unequip weapon")
	_queue_and_advance(inventory_runner, {"action": "unequip_slot", "actor_id": "player.mira", "slot_name": "weapon", "target_container_id": "player.mira.inventory", "target_cell": target_cell})
	var slots := _equipment_dict(gecs, "player.mira")
	_expect(not slots.has("weapon"), "Unequip command removes GECS weapon slot")
	var unequipped_profile: Dictionary = gecs.call("get_actor_stat_profile", "player.mira", gecs.call("get_population_record", "player.mira"))
	var unequipped_stats: Dictionary = unequipped_profile.get("effective_stats", {}) if unequipped_profile.get("effective_stats", {}) is Dictionary else {}
	_expect(is_equal_approx(float(unequipped_stats.get("attack_damage", -1.0)), base_damage), "Unequipping removes weapon attack modifier")
	var sword_stack := _stack_for_item(gecs, "player.mira.inventory", STEEL_SWORD_PATH)
	_expect(not sword_stack.is_empty(), "Unequip command creates inventory stack")
	_queue_and_advance(inventory_runner, {"action": "equip_stack", "source_stack_id": str(sword_stack.get("stack_id", "")), "target_actor_id": "player.mira", "slot_name": "weapon"})
	slots = _equipment_dict(gecs, "player.mira")
	_expect(str(slots.get("weapon", "")) == STEEL_SWORD_PATH, "Equip command restores GECS weapon slot")
	_expect(_stack_for_item(gecs, "player.mira.inventory", STEEL_SWORD_PATH).is_empty(), "Equip command removes equipped inventory stack")
	var restored_profile: Dictionary = gecs.call("get_actor_stat_profile", "player.mira", gecs.call("get_population_record", "player.mira"))
	var restored_stats: Dictionary = restored_profile.get("effective_stats", {}) if restored_profile.get("effective_stats", {}) is Dictionary else {}
	_expect(float(restored_stats.get("attack_damage", 0.0)) > base_damage, "Re-equipping restores weapon attack modifier")


func _validate_transfer_command(gecs: Node, inventory_runner: Node) -> void:
	var bandage_stack := _stack_for_item(gecs, "player.mira.inventory", BANDAGE_PATH)
	_expect(not bandage_stack.is_empty(), "Mira has bandage stack before transfer")
	if bandage_stack.is_empty():
		return
	var bandage := load(BANDAGE_PATH) as ItemDefinition
	var target_cell := _first_space_for_item(gecs, "player.tomas.inventory", bandage)
	_expect(target_cell != Vector2i(-1, -1), "Tomas inventory has room for transferred bandage")
	_queue_and_advance(inventory_runner, {"action": "move_stack", "source_stack_id": str(bandage_stack.get("stack_id", "")), "target_container_id": "player.tomas.inventory", "target_cell": target_cell})
	var moved_stack := _stack_by_id(gecs, str(bandage_stack.get("stack_id", "")))
	_expect(str(moved_stack.get("container_id", "")) == "player.tomas.inventory", "Transfer command moves stack by stable ID")


func _validate_drop_pickup_commands(gecs: Node, inventory_runner: Node, item_projection: Node) -> void:
	var bandage_stack := _stack_for_item(gecs, "player.tomas.inventory", BANDAGE_PATH)
	_expect(not bandage_stack.is_empty(), "Tomas has bandage stack before drop")
	if bandage_stack.is_empty():
		return
	var stack_id := str(bandage_stack.get("stack_id", ""))
	_queue_and_advance(inventory_runner, {"action": "drop_stack", "stack_id": stack_id, "world_position": Vector3(10.0, 0.0, 10.0)})
	var dropped_stack := _stack_by_id(gecs, stack_id)
	_expect(str(dropped_stack.get("container_id", "")) == "world", "Drop command moves stack to GECS world container")
	item_projection.call("sync_world_items")
	_expect(item_projection.call("get_projection_for_stack", stack_id) != null, "World item projection renders dropped stack")
	_queue_and_advance(inventory_runner, {"action": "pickup_stack", "actor_id": "player.mira", "stack_id": stack_id})
	var picked_stack := _stack_by_id(gecs, stack_id)
	_expect(str(picked_stack.get("container_id", "")) == "player.mira.inventory", "Pickup command moves world stack into actor inventory")
	item_projection.call("sync_world_items")
	_expect(item_projection.call("get_projection_for_stack", stack_id) == null, "World item projection removes picked-up stack")


func _validate_no_stack_commands_and_import(gecs: Node) -> void:
	var validation_record := {
		"actor_id": "validation.inventory",
		"stable_id": "validation.inventory",
		"member_name": "Inventory Validation",
		"player_party_member": true,
		"projection_kind": "humanoid",
		"life_state": 0,
		"inventory_entries": [{"stack_id": "validation.silver.stack", "item_id": SILVER_ID, "count": 2, "grid_position": Vector2i.ZERO}],
		"equipment_slots": {},
	}
	gecs.call("upsert_population_record", validation_record)
	var stacks: Array = gecs.call("get_inventory_stacks", "validation.inventory.inventory")
	_expect(stacks.size() == 2, "Imported count expands into individual stacks")
	for stack in stacks:
		if stack is Dictionary:
			_expect(int((stack as Dictionary).get("count", 0)) == 1, "Imported stack count is one")
			_expect(str((stack as Dictionary).get("item_id", "")) == SILVER_ID, "Imported stack keeps stable item ID")
	_validate_container_single_counts_and_layout(gecs, "validation.inventory.inventory", "Validation expanded inventory")
	var split_result: Dictionary = gecs.call("apply_inventory_command", {"action": "split_stack", "stack_id": "validation.silver.stack", "amount": 1, "target_cell": Vector2i(2, 0)})
	_expect(not bool(split_result.get("ok", true)), "Split command is disabled")
	var new_stack_id := ""
	for stack in stacks:
		if stack is Dictionary and str((stack as Dictionary).get("stack_id", "")) != "validation.silver.stack":
			new_stack_id = str((stack as Dictionary).get("stack_id", ""))
	if new_stack_id.is_empty():
		return
	var merge_result: Dictionary = gecs.call("apply_inventory_command", {"action": "merge_stacks", "source_stack_id": new_stack_id, "target_stack_id": "validation.silver.stack"})
	_expect(not bool(merge_result.get("ok", true)), "Merge command is disabled")
	_expect(int(_stack_by_id(gecs, "validation.silver.stack").get("count", 0)) == 1, "Disabled merge leaves target stack count at one")
	_expect(not _stack_by_id(gecs, new_stack_id).is_empty(), "Disabled merge leaves source stack intact")


func _validate_container_single_counts_and_layout(gecs: Node, container_id: String, label: String) -> void:
	var container: Dictionary = gecs.call("get_inventory_container", container_id)
	var inventory := InventoryData.new(int(container.get("columns", 10)), int(container.get("rows", 6)), float(container.get("max_weight", 60.0)), false)
	for stack in gecs.call("get_inventory_stacks", container_id):
		if not (stack is Dictionary):
			continue
		var stack_id := str((stack as Dictionary).get("stack_id", ""))
		var item_path := str((stack as Dictionary).get("item_definition_path", ""))
		var item := load(item_path) as ItemDefinition if not item_path.is_empty() else null
		_expect(int((stack as Dictionary).get("count", 0)) == 1, "%s stack %s count is one" % [label, stack_id])
		if item == null:
			_failures.append("%s stack %s item loads" % [label, stack_id])
			continue
		var grid_position: Vector2i = (stack as Dictionary).get("grid_position", Vector2i.ZERO)
		_expect(inventory.can_place_item(item, grid_position), "%s stack %s does not overlap" % [label, stack_id])
		inventory.entries.append(InventoryData.InventoryEntry.new(item, grid_position, 1, ((stack as Dictionary).get("contained_item_counts", {}) as Dictionary), ((stack as Dictionary).get("metadata", {}) as Dictionary), stack_id))


func _validate_item_definition_index() -> void:
	ItemDefinitionIndex.reset()
	var item_paths := ItemDefinitionIndex.all_item_paths()
	_expect(item_paths.size() > 0, "Item definition index scans structured item folders")
	_expect(ItemDefinitionIndex.resource_path_for(STEEL_SWORD_ID) == STEEL_SWORD_PATH, "Item index resolves steel sword ID")
	_expect(ItemDefinitionIndex.resource_path_for("silver") == SILVER_PATH, "Item index resolves legacy silver alias")
	var root_dir := DirAccess.open("res://resources/items")
	if root_dir != null:
		root_dir.list_dir_begin()
		while true:
			var name := root_dir.get_next()
			if name.is_empty():
				break
			_expect(not name.ends_with(".tres"), "No item definitions remain at resources/items root")
		root_dir.list_dir_end()
	for item_path in item_paths:
		var definition := ItemDefinitionIndex.load_definition(item_path)
		_expect(definition != null, "Indexed item definition loads: %s" % item_path)
		if definition == null:
			continue
		var item_id := ItemDefinitionIndex.item_id_for_definition(definition)
		_expect(not item_id.is_empty() and not item_id.begins_with("res://"), "Indexed item has stable item ID: %s" % item_path)


func _queue_and_advance(runner: Node, command: Dictionary) -> void:
	runner.call("queue_command", command)
	runner.call("advance_time", runner.call("get_fixed_delta"))


func _equipment_dict(gecs: Node, actor_id: String) -> Dictionary:
	var result := {}
	for slot in gecs.call("get_equipment_slots", actor_id):
		if slot is Dictionary:
			result[str((slot as Dictionary).get("slot_name", ""))] = str((slot as Dictionary).get("item_definition_path", ""))
	return result


func _stack_for_item(gecs: Node, container_id: String, item_path: String) -> Dictionary:
	for stack in gecs.call("get_inventory_stacks", container_id):
		if stack is Dictionary and str((stack as Dictionary).get("item_definition_path", "")) == item_path:
			return (stack as Dictionary).duplicate(true)
	return {}


func _stack_by_id(gecs: Node, stack_id: String) -> Dictionary:
	for stack in gecs.call("get_inventory_stacks"):
		if stack is Dictionary and str((stack as Dictionary).get("stack_id", "")) == stack_id:
			return (stack as Dictionary).duplicate(true)
	return {}


func _first_space_for_item(gecs: Node, container_id: String, definition: ItemDefinition) -> Vector2i:
	if definition == null:
		return Vector2i(-1, -1)
	var container: Dictionary = gecs.call("get_inventory_container", container_id)
	var inventory := InventoryData.new(int(container.get("columns", 10)), int(container.get("rows", 6)), float(container.get("max_weight", 60.0)), true)
	for stack in gecs.call("get_inventory_stacks", container_id):
		if not (stack is Dictionary):
			continue
		var item_path := str((stack as Dictionary).get("item_definition_path", ""))
		var item := load(item_path) as ItemDefinition if not item_path.is_empty() else null
		if item == null:
			continue
		inventory.entries.append(InventoryData.InventoryEntry.new(item, (stack as Dictionary).get("grid_position", Vector2i.ZERO), int((stack as Dictionary).get("count", 1)), ((stack as Dictionary).get("contained_item_counts", {}) as Dictionary), ((stack as Dictionary).get("metadata", {}) as Dictionary), str((stack as Dictionary).get("stack_id", ""))))
	return inventory.find_first_space(definition)


func _entry_for_item(inventory: InventoryData, item_path: String):
	if inventory == null:
		return null
	for entry in inventory.entries:
		if entry != null and entry.definition != null and str(entry.definition.resource_path) == item_path:
			return entry
	return null


func _array_text_contains(values: Array, needle: String) -> bool:
	for value in values:
		if str(value).contains(needle):
			return true
	return false


func _gear_effect_text(gear_effects: Dictionary) -> String:
	var parts: Array[String] = []
	for effect in gear_effects.values():
		if not (effect is Dictionary):
			continue
		parts.append(str((effect as Dictionary).get("summary", "")))
		parts.append(str((effect as Dictionary).get("base", "")))
		parts.append(str((effect as Dictionary).get("final", "")))
		var sources: Array = (effect as Dictionary).get("sources", []) if (effect as Dictionary).get("sources", []) is Array else []
		for source in sources:
			parts.append(str(source))
	return "\n".join(parts)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _registered_ecs_placeholder:
		Engine.unregister_singleton("ECS")
		_registered_ecs_placeholder = false
	if _ecs_placeholder != null and is_instance_valid(_ecs_placeholder):
		_ecs_placeholder.queue_free()
	if _failures.is_empty():
		print("INVENTORY_EQUIPMENT_GECS_VALIDATION_OK")
	else:
		for failure in _failures:
			push_error(failure)
	quit(_failures.size())


func _ensure_ecs_placeholder() -> void:
	if Engine.has_singleton("ECS"):
		return
	_ecs_placeholder = EcsPlaceholder.new()
	_ecs_placeholder.name = "ECS"
	Engine.register_singleton("ECS", _ecs_placeholder)
	_registered_ecs_placeholder = true


func _promote_root_ecs_singleton() -> void:
	var root_ecs := root.get_node_or_null("ECS")
	if root_ecs == null or root_ecs == _ecs_placeholder:
		return
	if _registered_ecs_placeholder:
		Engine.unregister_singleton("ECS")
		_registered_ecs_placeholder = false
	Engine.register_singleton("ECS", root_ecs)
