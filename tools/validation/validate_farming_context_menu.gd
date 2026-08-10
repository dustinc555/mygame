extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_context_menu.gd

const PLOT_PROJECTION = preload("res://features/farming/projection/farm_plot_projection.gd")
const TOMATO = preload("res://features/farming/resources/crops/tomato.tres")
const BELL_PEPPER = preload("res://features/farming/resources/crops/bell_pepper.tres")
const WHEAT = preload("res://features/farming/resources/crops/wheat.tres")
const SCYTHE = preload("res://features/inventory/resources/items/scythe.tres")

class FakeFarm:
	extends Node
	var requests: Array[Dictionary] = []
	var prepared_plot_till := false
	var prepared_operations: Array[Dictionary] = []
	var has_adjacent_field := false
	func can_actor_command_plot(actor: Node, _plot_id: String) -> bool:
		return actor == null or str(actor.get("faction_name")) == "Player"
	func get_crops() -> Array:
		return [TOMATO, BELL_PEPPER, WHEAT]
	func get_crop(crop_id: String):
		return TOMATO if crop_id == "tomato" else (BELL_PEPPER if crop_id == "bell_pepper" else (WHEAT if crop_id == "wheat" else null))
	func request_cell_operation(plot_id: String, cell_key: String, operation: String, crop_id := "", allowed_actor_ids := PackedStringArray()) -> Dictionary:
		requests.append({"plot_id": plot_id, "cell_key": cell_key, "operation": operation, "crop_id": crop_id, "allowed_actor_ids": allowed_actor_ids.duplicate()})
		return {"plot_id": plot_id, "cell_key": cell_key}
	func prepare_plot_till(_plot_id: String, _actor: Node, _allowed_actor_ids := PackedStringArray()) -> Dictionary:
		prepared_plot_till = true
		return {"targets": [{"plot_id": "farm:test", "cell_key": "0:0", "request_revision": 2}]}
	func prepare_plot_operation(plot_id: String, operation: String, crop_id: String, allowed_actor_ids: PackedStringArray, preferred_cell_key: String, _actor: Node = null) -> Dictionary:
		prepared_operations.append({"plot_id": plot_id, "operation": operation, "crop_id": crop_id, "allowed_actor_ids": allowed_actor_ids.duplicate(), "preferred_cell_key": preferred_cell_key})
		return {"targets": [
			{"plot_id": plot_id, "cell_key": preferred_cell_key, "request_revision": 3},
			{"plot_id": plot_id, "cell_key": "5:0", "request_revision": 4},
		]}
	func has_mergeable_adjacent_plot(_plot_id: String, _actor: Node = null) -> bool:
		return has_adjacent_field

class FakeWorkBridge:
	extends Node
	var assignments: Array[Dictionary] = []
	var sequences: Array[Dictionary] = []
	func assign_cell(plot_id: String, cell_key: String, actors: Array) -> String:
		assignments.append({"plot_id": plot_id, "cell_key": cell_key, "actors": actors.duplicate()})
		return "1 worker assigned"
	func assign_cell_sequence(targets: Array, actor: Node, manual := false) -> String:
		sequences.append({"targets": targets.duplicate(true), "actor": actor, "manual": manual})
		return "1 cell queued"

class FakePlacement:
	extends Node
	var edit_requests: Array[Dictionary] = []
	func begin_field_edit(plot_id: String, mode: String, actor: Node) -> String:
		edit_requests.append({"plot_id": plot_id, "mode": mode, "actor": actor})
		return "%s field" % mode.capitalize()

class FakeEquipment:
	extends RefCounted
	func get_equipped_item(_slot_name: String):
		return null
	func can_equip_item_to_slot(definition, slot_name: String) -> bool:
		return definition != null and definition.can_equip_to_slot(slot_name)

class FakeActor:
	extends Node
	var faction_name := "Player"
	var inventory := InventoryData.new()
	var equipment = FakeEquipment.new()
	func get_equipment():
		return equipment

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var projection = PLOT_PROJECTION.new()
	var farm := FakeFarm.new()
	var work := FakeWorkBridge.new()
	var placement := FakePlacement.new()
	var owner := FakeActor.new()
	var other_owner := FakeActor.new()
	var no_equipment_owner := FakeActor.new()
	var outsider := FakeActor.new()
	no_equipment_owner.equipment = null
	no_equipment_owner.inventory.add_item_count(SCYTHE, 1)
	outsider.faction_name = "Raiders"
	owner.inventory.add_item_count(TOMATO.seed_item, 3)
	other_owner.inventory.add_item_count(BELL_PEPPER.seed_item, 2)
	root.add_child(farm)
	root.add_child(work)
	root.add_child(placement)
	root.add_child(owner)
	root.add_child(other_owner)
	root.add_child(no_equipment_owner)
	root.add_child(outsider)
	root.add_child(projection)
	await process_frame
	var context := BootstrapContext.new(root)
	context.register(&"farm_work", work)
	context.register(&"farm_placement", placement)
	BootstrapContext.active = context
	projection._farm = farm
	projection.plot_id = "farm:test"
	projection._state = {
		"plot_id": "farm:test",
		"owner_faction_id": "Player",
		"cells": {
			"0:0": {"state": "untilled", "world_position": Vector3(0.0, 0.0, 0.0)},
			"1:0": {"state": "tilled", "world_position": Vector3(1.25, 0.0, 0.0)},
			"2:0": {"state": "growing", "crop_id": "tomato", "world_position": Vector3(2.5, 0.0, 0.0), "water": 0.0},
			"3:0": {"state": "ripe", "crop_id": "tomato", "world_position": Vector3(3.75, 0.0, 0.0)},
			"4:0": {"state": "ripe", "crop_id": "wheat", "world_position": Vector3(5.0, 0.0, 0.0)},
		},
	}
	projection.call("_sync_visuals")
	for _frame in 3:
		await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(0.0, 5.0, 0.0), Vector3(0.0, -5.0, 0.0))
	query.collide_with_areas = true
	var hit := projection.get_world_3d().direct_space_state.intersect_ray(query)
	_expect(
		_context_target_from_collider(hit.get("collider")) == projection,
		"right-click physics ray hits the field interaction surface: hit=%s shape_owners=%s children=%d" % [
			str(hit),
			str(projection._collision_root.get_shape_owners()),
			projection._collision_root.get_child_count(),
		]
	)

	_expect(projection.has_method("get_world_context_actions_at"), "plot projection exposes hit-position cell actions")
	if projection.has_method("get_world_context_actions_at"):
		var owned_actions: Array = projection.call("get_world_context_actions_at", owner, Vector3(0.1, 0.0, 0.0))
		_expect(_labels(owned_actions) == ["Till"], "single-cell right-click exposes only the exact cell action")
		farm.has_adjacent_field = true
		_expect(_labels(projection.call("get_world_context_actions_at", owner, Vector3(0.1, 0.0, 0.0))) == ["Till"], "adjacency never leaks field-wide actions into a single-cell menu")
		farm.has_adjacent_field = false
		_expect(_labels(projection.call("get_world_context_actions_at", outsider, Vector3(0.1, 0.0, 0.0))) == ["Owned by Player"], "foreign field right-click exposes no work or edit commands")
		var request_count_before_foreign := farm.requests.size()
		projection.perform_world_context_action(str(owned_actions[0].get("key", "")), [outsider])
		_expect(farm.requests.size() == request_count_before_foreign, "foreign actors cannot publish durable crop-cell work through a captured action key")
		var till_actions: Array = projection.call("get_world_context_actions_at", null, Vector3(0.1, 0.0, 0.0))
		_expect(_labels(till_actions) == ["Till"], "untilled cell shows only Till")
		_expect(_has_no_plot_wide_actions(till_actions), "untilled cell has no plot-wide or Change Crop Type action")
		if not till_actions.is_empty():
			var no_worker_result := projection.perform_world_context_action(str(till_actions[0].get("key", "")), [])
			_expect(no_worker_result == "Select a worker first" and farm.requests.is_empty(), "manual cell action cannot publish unrestricted work without a selected actor")
			projection.perform_world_context_action(str(till_actions[0].get("key", "")), [owner])
			var till_request: Dictionary = farm.requests[-1] if not farm.requests.is_empty() else {}
			_expect(str(till_request.get("plot_id", "")) == "farm:test" and str(till_request.get("cell_key", "")) == "0:0" and str(till_request.get("operation", "")) == "till", "Till requests only clicked cell")
			_expect(PackedStringArray(till_request.get("allowed_actor_ids", PackedStringArray())).size() == 1, "manual Till remains restricted to selected actors")
			_expect(not work.assignments.is_empty() and str(work.assignments[-1].get("cell_key", "")) == "0:0", "Till assigns selected actors only to clicked cell")

		var plant_actions: Array = projection.call("get_world_context_actions_at", owner, Vector3(1.3, 0.0, 0.0))
		_expect(_labels(plant_actions) == ["Plant Tomato"], "tilled cell lists only crops whose seed item is in the acting character's pocket")
		_expect(_has_no_plot_wide_actions(plant_actions), "plant menu has no All or Change Crop Type action")
		_expect(_labels(projection.call("get_world_context_actions_at", other_owner, Vector3(1.3, 0.0, 0.0))) == ["Plant Bell Pepper"], "plant choices follow the acting character instead of another party member")
		_expect(_labels(projection.call("get_world_context_actions_at", null, Vector3(1.3, 0.0, 0.0))).is_empty(), "tilled cell exposes no Plant action without an acting character")
		owner.inventory.remove_item_count(TOMATO.seed_item, 3)
		_expect(_labels(projection.call("get_world_context_actions_at", owner, Vector3(1.3, 0.0, 0.0))).is_empty(), "Plant action disappears after its seed stack leaves the acting character's pocket")
		owner.inventory.add_item_count(TOMATO.seed_item, 3)
		var tomato_action := _action_with_label(plant_actions, "Plant Tomato")
		if not tomato_action.is_empty():
			projection.perform_world_context_action(str(tomato_action.get("key", "")), [owner])
			_expect(str(farm.requests[-1].get("cell_key", "")) == "1:0" and str(farm.requests[-1].get("crop_id", "")) == "tomato", "Plant Tomato targets clicked cell and selected crop")
			projection.perform_world_context_action("farm_field|plant|1:0|tomato", [owner])
			var field_operation: Dictionary = farm.prepared_operations[-1] if not farm.prepared_operations.is_empty() else {}
			_expect(str(field_operation.get("operation", "")) == "plant" and str(field_operation.get("crop_id", "")) == "tomato" and str(field_operation.get("preferred_cell_key", "")) == "1:0", "Shift-click Plant Tomato expands the clicked action across its field")
			_expect(PackedStringArray(field_operation.get("allowed_actor_ids", PackedStringArray())).size() == 1, "Shift-click field work remains a command for the selected actor")
			_expect(not work.sequences.is_empty() and (work.sequences[-1].get("targets", []) as Array).size() == 2, "Shift-click sends every valid field cell through the actor command sequence")

		_expect(_labels(projection.call("get_world_context_actions_at", null, Vector3(2.55, 0.0, 0.0))) == ["Water"], "dry growing cell shows Water")
		_expect(_labels(projection.call("get_world_context_actions_at", null, Vector3(3.8, 0.0, 0.0))) == ["Harvest"], "ripe cell shows Harvest")
		_expect(_labels(projection.call("get_world_context_actions_at", owner, Vector3(5.0, 0.0, 0.0))).is_empty(), "wheat never exposes a Harvest command to a worker with no scythe")
		owner.inventory.add_item_count(SCYTHE, 1)
		var wheat_actions: Array = projection.call("get_world_context_actions_at", owner, Vector3(5.0, 0.0, 0.0))
		_expect(_labels(wheat_actions) == ["Harvest"], "wheat exposes Harvest when the worker carries a scythe that farming can equip")
		_expect(_labels(projection.call("get_world_context_actions_at", no_equipment_owner, Vector3(5.0, 0.0, 0.0))).is_empty(), "wheat hides Harvest when a carried scythe cannot actually be equipped")
		if not wheat_actions.is_empty():
			projection.perform_world_context_action(str(wheat_actions[0].get("key", "")), [owner])
			_expect(str(farm.requests[-1].get("cell_key", "")) == "4:0" and str(farm.requests[-1].get("operation", "")) == "harvest", "wheat Harvest reaches the same exact-cell request path as other crops")

	_expect(projection.has_method("begin_inspection_at") and projection.has_method("get_details_panel_actions_at"), "crop inspection can drill into its logical field")
	if projection.has_method("begin_inspection_at") and projection.has_method("get_details_panel_actions_at"):
		projection.call("begin_inspection_at", Vector3(2.55, 0.0, 0.0))
		projection.call("set_inspected", true)
		_expect(_labels(projection.call("get_details_panel_actions_at", Vector3(2.55, 0.0, 0.0))) == ["Water", "Select Field"], "individual crop details include Select Field without mixing field controls into the crop panel")
		_expect(not projection._selection_root.visible, "clicking a crop does not select or outline the whole field")
		projection.perform_world_context_action("farm_select_field", [owner])
		var field_data: Dictionary = projection.get_details_panel_data_at(Vector3(2.55, 0.0, 0.0))
		_expect(str(field_data.get("state", "")) == "No Crop" and projection._selection_root.visible, "Select Field switches scope and reveals the green field overlay")
		_expect((projection.call("get_details_panel_actions_at", Vector3(2.55, 0.0, 0.0), null) as Array).is_empty(), "Player-owned field controls stay hidden without an explicit acting character")
		_expect(_labels(projection.call("get_details_panel_actions_at", Vector3(2.55, 0.0, 0.0), owner)) == ["Crop", "Till", "Expand", "Subtract", "Delete"], "owned selected field hides Merge without an adjacent field and keeps Delete direct")
		farm.has_adjacent_field = true
		_expect(_labels(projection.call("get_details_panel_actions_at", Vector3(2.55, 0.0, 0.0), owner)) == ["Crop", "Till", "Expand", "Subtract", "Merge", "Delete"], "owned selected field exposes Merge only while an adjacent field exists")
		farm.has_adjacent_field = false
		projection.perform_world_context_action("farm_plot|till_all", [owner])
		_expect(farm.prepared_plot_till and not work.sequences.is_empty(), "field-wide Till assigns the complete field command to the selected actor")
		_expect((projection.call("get_details_panel_actions_at", Vector3(2.55, 0.0, 0.0), outsider) as Array).is_empty(), "field management controls are hidden from non-owners")
		_expect(_labels_from_crop_options(projection.call("get_field_crop_options")) == ["No Crop", "Tomato", "Bell Pepper", "Wheat"], "crop picker keeps the full crop list out of the action row")
		var deleted_state: Dictionary = (projection.get("_state") as Dictionary).duplicate(true)
		deleted_state["field_deleted"] = true
		projection.update_state(deleted_state)
		projection.call("begin_inspection_at", Vector3(2.55, 0.0, 0.0))
		_expect(_labels(projection.call("get_details_panel_actions_at", Vector3(2.55, 0.0, 0.0))) == ["Water"], "deleted field remnants preserve physical crop actions without logical field actions")
		_expect(_labels(projection.call("get_world_context_actions_at", owner, Vector3(2.55, 0.0, 0.0))) == ["Water"], "deleted remnants expose no field-wide context actions")
		_expect(not projection._selection_root.visible, "deleted field remnants have no logical field boundary")
		deleted_state["field_deleted"] = false
		projection.update_state(deleted_state)
		projection.call("begin_inspection_at", Vector3(1.3, 0.0, 0.0))
		_expect(projection._selection_root.visible, "clicking empty field soil selects the field directly")
		projection.call("set_inspected", false)
		_expect(not projection._selection_root.visible, "field overlay disappears when field inspection ends")

	var interaction_source := FileAccess.get_file_as_string("res://features/world/bridge/world_interaction_controller.gd")
	_expect(interaction_source.contains("get_world_context_actions_at") and interaction_source.contains("result[\"position\"]"), "right-click forwards the ray-hit position to cell context actions")
	_expect(interaction_source.contains("_cancel_selected_settlement_work"), "manual world-context orders cancel selected actors' current settlement work first")
	_expect(interaction_source.contains("func _with_shift_field_scope") and interaction_source.contains("Input.is_key_pressed(KEY_SHIFT)"), "holding Shift while choosing a crop-cell action changes only that action to field scope")
	_expect(interaction_source.contains("_action_preserves_field_work") and interaction_source.contains("\"farm_plot|delete\""), "both field-management routes reach retirement and edit guards without pre-cancelling active physical work")
	_expect(interaction_source.contains("func _dispatch_world_context_action(target, action_key: String)") \
			and interaction_source.count("is_in_group(\"farm_plot\")") == 1, "shared details/right-click dispatcher suppresses farming world and center status text once")
	var right_click_leaf := interaction_source.get_slice("func _perform_world_context_action(action_index: int) -> void:", 1) \
			.get_slice("func _assign_pickup_to_selection", 0)
	_expect(not right_click_leaf.contains("context_world_action_target.has_method"), "right-click leaf delegates stale-target validation without dereferencing the target first")
	var interaction_script = load("res://features/world/bridge/world_interaction_controller.gd")
	var interaction = interaction_script.new()
	root.add_child(interaction)
	_expect(str(interaction.call("_with_shift_field_scope", "farm_cell|water|2:0|", true)) == "farm_field|water|2:0|", "Shift converts an exact crop-cell action to field scope")
	_expect(str(interaction.call("_with_shift_field_scope", "farm_cell|water|2:0|", false)) == "farm_cell|water|2:0|" \
			and str(interaction.call("_with_shift_field_scope", "farm_plot|delete", true)) == "farm_plot|delete", "Shift leaves unmodified clicks and non-cell field controls unchanged")
	var stale_target := Node3D.new()
	root.add_child(stale_target)
	interaction.context_world_action_target = stale_target
	interaction.context_world_actions = [{"key": "farm_cell|harvest|0:0|", "label": "Harvest"}]
	stale_target.free()
	interaction.call("_perform_world_context_action", 0)
	_expect(true, "right-click dispatcher safely ignores a target freed while its menu is open")
	interaction.queue_free()

	BootstrapContext.active = null
	projection.queue_free()
	farm.queue_free()
	work.queue_free()
	placement.queue_free()
	owner.queue_free()
	other_owner.queue_free()
	outsider.queue_free()
	_finish()


func _context_target_from_collider(collider) -> Node:
	var node := collider as Node
	while node != null:
		if node.has_method("get_world_context_actions"):
			return node
		node = node.get_parent()
	return null


func _labels(actions: Array) -> Array[String]:
	var result: Array[String] = []
	for action in actions:
		result.append(str((action as Dictionary).get("label", "")))
	return result


func _labels_from_crop_options(options: Array) -> Array[String]:
	var result: Array[String] = []
	for option in options:
		result.append(str((option as Dictionary).get("label", "")))
	return result


func _action_with_label(actions: Array, label: String) -> Dictionary:
	for action in actions:
		if str((action as Dictionary).get("label", "")) == label:
			return action
	return {}


func _has_no_plot_wide_actions(actions: Array) -> bool:
	for action in actions:
		var label := str((action as Dictionary).get("label", ""))
		if label.contains("All") or label == "Change Crop Type":
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FARMING_CONTEXT_MENU_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARMING_CONTEXT_MENU_FAILED count=%d" % failures.size())
	quit(1)
