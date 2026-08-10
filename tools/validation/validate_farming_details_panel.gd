extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_details_panel.gd

const FARM_SIMULATION = preload("res://features/farming/sim/farm_simulation.gd")
const GAME_HUD_SCENE = preload("res://features/ui/projection/game_hud.tscn")
const PLOT_PROJECTION = preload("res://features/farming/projection/farm_plot_projection.gd")
const TOMATO = preload("res://features/farming/resources/crops/tomato.tres")
const WHEAT = preload("res://features/farming/resources/crops/wheat.tres")

class FakeFarm:
	extends Node
	var has_adjacent_field := false
	func can_actor_command_plot(actor: Node, _plot_id: String) -> bool:
		return actor != null
	func get_crop(crop_id: String):
		return TOMATO if crop_id == "tomato" else (WHEAT if crop_id == "wheat" else null)
	func get_crops() -> Array:
		return [TOMATO, WHEAT]
	func has_mergeable_adjacent_plot(_plot_id: String, _actor: Node = null) -> bool:
		return _actor != null and has_adjacent_field

var failures: Array[String] = []
var _ecs_placeholder: Node


func _init() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var farm := FakeFarm.new()
	root.add_child(farm)
	var party_manager_script = load("res://features/core/party/party_manager.gd")
	var party_manager = party_manager_script.new()
	party_manager.name = "PartyManager"
	root.add_child(party_manager)
	var owner_script = load("res://features/actors/projection/humanoid/humanoid_character.gd")
	var owner = owner_script.new()
	owner.name = "ValidationOwner"
	root.add_child(owner)
	await process_frame
	owner.set_player_party_member(true)
	party_manager.set_party_members([owner])
	party_manager.select_only(owner)
	var projection = PLOT_PROJECTION.new()
	root.add_child(projection)
	await process_frame
	projection.setup({
		"plot_id": "farm:details",
		"owner_faction_id": "Player",
		"cells": {
			"0:0": {"state": FARM_SIMULATION.STATE_TILLED, "crop_id": "", "world_position": Vector3(0.0, 0.0, 0.0), "growth": 0.0, "water": 0.0},
			"1:0": {"state": FARM_SIMULATION.STATE_GROWING, "crop_id": "tomato", "world_position": Vector3(1.25, 0.0, 0.0), "growth": 0.35, "water": 12.0, "stage_index": 2},
			"2:0": {"state": FARM_SIMULATION.STATE_RIPE, "crop_id": "tomato", "world_position": Vector3(2.5, 0.0, 0.0), "growth": 1.0, "water": 6.0, "stage_index": 6},
			"3:0": {"state": FARM_SIMULATION.STATE_WITHERED, "crop_id": "tomato", "world_position": Vector3(3.75, 0.0, 0.0), "growth": 0.7, "water": 0.0, "stage_index": 8},
			"4:0": {"state": FARM_SIMULATION.STATE_RIPE, "crop_id": "wheat", "world_position": Vector3(5.0, 0.0, 0.0), "growth": 1.0, "water": 6.0, "stage_index": 6},
		},
	}, farm)
	await process_frame

	_expect(projection.has_method("get_details_panel_data_at"), "farm plots expose authored player-facing details for the clicked cell")
	if projection.has_method("get_details_panel_data_at"):
		var empty: Dictionary = projection.call("get_details_panel_data_at", Vector3(0.05, 0.0, 0.0))
		_expect(str(empty.get("title", "")) == "Empty Tilled Soil", "tilled empty cell has the exact player-facing title")
		_expect(str(empty.get("state", "")) == "Empty", "tilled empty cell reports Empty state")
		_expect(not bool(empty.get("show_crop_bars", true)), "empty soil hides crop bars")

		var alive: Dictionary = projection.call("get_details_panel_data_at", Vector3(1.3, 0.0, 0.0))
		_expect(str(alive.get("title", "")) == "Tomato plant", "growing crop has a player-facing plant title")
		_expect(str(alive.get("state", "")) == "Alive", "growing crop reports Alive")
		_expect(is_equal_approx(float(alive.get("growth_ratio", -1.0)), 0.35), "crop details expose growth ratio")
		_expect(is_equal_approx(float(alive.get("hydration_ratio", -1.0)), 0.5), "crop details expose hydration ratio")

		var ripe: Dictionary = projection.call("get_details_panel_data_at", Vector3(2.55, 0.0, 0.0))
		_expect(str(ripe.get("state", "")) == "Ready for Harvest", "ripe crop reports Ready for Harvest")
		_expect(str(ripe.get("tool_requirement", "")).is_empty(), "ready tomato does not invent a harvest-tool requirement")
		var ready_wheat: Dictionary = projection.call("get_details_panel_data_at", Vector3(5.05, 0.0, 0.0))
		_expect(str(ready_wheat.get("state", "")) == "Ready for Harvest", "ready wheat reports Ready for Harvest")
		_expect(str(ready_wheat.get("tool_requirement", "")) == "Requires tool: Scythe", "ready wheat exposes its scythe requirement in authored player-facing text")
		_expect(TOMATO.get_stage_node_name(6) == "Crop_Tomato_Stage07", "Ready for Harvest resolves to the visually verified healthy tomato model")
		_expect(PLOT_PROJECTION.crop_visual_stage_index({"state": FARM_SIMULATION.STATE_RIPE, "stage_index": 8}) == 6, "old ripe saves cannot render the former corpse-stage index")
		var dead: Dictionary = projection.call("get_details_panel_data_at", Vector3(3.8, 0.0, 0.0))
		_expect(str(dead.get("state", "")) == "Dead", "withered crop reports Dead")
		_expect(TOMATO.get_stage_node_name(8) == "Crop_Tomato_Stage09", "Dead resolves to the visually verified corpse model")
		_expect(PLOT_PROJECTION.crop_visual_stage_index({"state": FARM_SIMULATION.STATE_WITHERED, "stage_index": 5}) == 8, "old withered saves normalize to the corpse model")

		var hud := GAME_HUD_SCENE.instantiate() as CanvasLayer
		root.add_child(hud)
		_expect(hud.get_node_or_null("BuildMenuButton") is Button, "HUD exposes a dedicated settlement build menu")
		var details_controller_script = load("res://features/ui/bridge/humanoid_details_controller.gd")
		var controller = details_controller_script.new()
		root.add_child(controller)
		controller.initialize(BootstrapContext.new(root, hud))
		await process_frame
		_expect(controller.has_method("inspect_target_at"), "details controller accepts the clicked world position")
		if controller.has_method("inspect_target_at"):
			controller.call("inspect_target_at", projection, Vector3(1.3, 0.0, 0.0))
			controller.call("_update_panel")
			var base := "HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/"
			var name_label := hud.get_node(base + "HeaderRow/Name") as Label
			var state_label := hud.get_node(base + "HeaderRow/State") as Label
			var faction_label := hud.get_node(base + "Faction") as Label
			var work_label := hud.get_node(base + "WorkStatus") as Label
			var info_rows := hud.get_node(base + "InfoRows") as Control
			var action_row := hud.get_node(base + "ActionRow") as Control
			var growth_row := hud.get_node_or_null(base + "FarmGrowthRow") as Control
			var hydration_row := hud.get_node_or_null(base + "FarmHydrationRow") as Control
			var tool_requirement_label := hud.get_node_or_null(base + "ToolRequirement") as Label
			_expect(name_label.text == "Tomato plant" and state_label.text == "ALIVE", "farm details render only the plant title and crop state in the header")
			_expect(not faction_label.visible and not work_label.visible, "farm details hide generic world-object subtitle and detail text")
			_expect(not info_rows.visible, "farm details hide generic Type, Action, and Status rows")
			_expect(action_row.visible and _visible_action_labels(action_row).has("Select Field"), "individual crop details expose Select Field without mixing in field controls")
			_expect(growth_row != null and growth_row.visible, "farm details show a crop progression bar")
			_expect(hydration_row != null and hydration_row.visible, "farm details show a hydration bar")
			controller.call("inspect_target_at", projection, Vector3(5.05, 0.0, 0.0))
			controller.call("_update_panel")
			_expect(state_label.text == "READY FOR HARVEST", "selected wheat shows Ready for Harvest")
			_expect(tool_requirement_label != null and tool_requirement_label.visible and tool_requirement_label.text == "Requires tool: Scythe", "selected ready wheat renders Requires tool: Scythe beneath its lifecycle state")
			if tool_requirement_label != null:
				_expect(tool_requirement_label.get_theme_font_size("font_size") < state_label.get_theme_font_size("font_size"), "wheat tool requirement text is smaller than the lifecycle state")
			projection.set("_field_details_mode", true)
			_expect((projection.call("get_details_panel_actions_at", Vector3(1.3, 0.0, 0.0), null) as Array).is_empty(), "field controls require an explicit acting character even for Player-owned fields")
			controller.call("_update_panel")
			_expect(_visible_action_labels(action_row) == ["Crop", "Till", "Expand", "Subtract", "Delete"], "selected field fits every currently valid action directly with no More button")
			farm.has_adjacent_field = true
			controller.call("_update_panel")
			_expect(_visible_action_labels(action_row) == ["Crop", "Till", "Expand", "Subtract", "Merge", "Delete"], "adjacent-field Merge and Delete both remain direct buttons without overflow")
			var routed_actions: Array[String] = []
			controller.inspector_action_requested.connect(func(_target, action_key: String): routed_actions.append(action_key))
			var delete_button: Button
			for action_button in controller.action_buttons:
				if action_button.visible and action_button.text == "Delete":
					delete_button = action_button
					break
			_expect(delete_button != null, "Delete Field is a directly clickable action")
			if delete_button != null:
				var delete_color := delete_button.get_theme_color("font_color")
				_expect(delete_color.r > delete_color.g * 1.5 and delete_color.r > delete_color.b * 1.5, "Delete Field text is visibly red")
				controller.call("_on_action_button_pressed", delete_button)
				_expect(not routed_actions.is_empty() and routed_actions[-1] == "world:farm_plot|delete", "Delete Field button routes the real delete action")
			var shifted_press := InputEventMouseButton.new()
			shifted_press.button_index = MOUSE_BUTTON_LEFT
			shifted_press.pressed = true
			shifted_press.shift_pressed = true
			var till_button: Button = controller.action_buttons[1]
			controller.call("_on_action_button_gui_input", shifted_press, till_button)
			controller.call("_on_action_button_pressed", till_button)
			_expect(not routed_actions.is_empty() and routed_actions[-1] == "world:farm_plot|till_all", "Shift is snapshotted on mouse press so release timing cannot downgrade whole-field Till")
		controller.queue_free()
		hud.queue_free()
	var details_source := FileAccess.get_file_as_string("res://features/ui/bridge/humanoid_details_controller.gd")
	var interaction_source := FileAccess.get_file_as_string("res://features/world/bridge/world_interaction_controller.gd")
	_expect(not details_source.contains("{\"key\": ACTION_FARM_PLAN, \"label\": \"Plan Field\"}"), "Plan Field is absent from permanent character actions")
	_expect(interaction_source.contains("add_submenu_item(\"Farming\"") and interaction_source.contains("add_item(\"Plan Field\""), "build menu nests Plan Field under Farming")
	_expect(interaction_source.contains("func _dispatch_world_context_action(target, action_key: String)") \
			and interaction_source.count("_dispatch_world_context_action(") >= 3, "details buttons and right-click actions converge on one world-action dispatcher")

	var physical_labels := projection.find_children("*", "Label3D", true, false)
	_expect(physical_labels.is_empty(), "crop visuals contain no physical percentage or loading-bar label")
	var wet := FARM_SIMULATION.complete_planting(FARM_SIMULATION.new_cell(Vector2i.ZERO, Vector3.ZERO), "tomato", TOMATO.water_per_growth_minute)
	var grown := FARM_SIMULATION.advance_cell(wet, TOMATO.to_sim_profile(), 1.0)
	var dry := FARM_SIMULATION.complete_planting(FARM_SIMULATION.new_cell(Vector2i.ZERO, Vector3.ZERO), "tomato", 0.0)
	var unchanged := FARM_SIMULATION.advance_cell(dry, TOMATO.to_sim_profile(), 1.0)
	_expect(float(grown.get("growth", 0.0)) > 0.0 and is_equal_approx(float(unchanged.get("growth", 0.0)), 0.0), "crops grow while hydration is positive and stop at zero")

	projection.queue_free()
	farm.queue_free()
	owner.queue_free()
	party_manager.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _visible_action_labels(row: Control) -> Array[String]:
	var labels: Array[String] = []
	for child in row.get_children():
		var button := child as Button
		if button != null and button.visible:
			labels.append(button.text)
	return labels


func _finish() -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
		_ecs_placeholder = null
	if failures.is_empty():
		print("FARMING_DETAILS_PANEL_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARMING_DETAILS_PANEL_FAILED count=%d" % failures.size())
	quit(1)
