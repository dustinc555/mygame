extends SceneTree

class EcsPlaceholder:
	extends Node
	var debug := false

const DEMO_WORLD_SCENE_PATH := "res://scenes/worlds/demo_world/demo_world.tscn"

var _failures: Array[String] = []
var _ecs_placeholder: Node
var _registered_ecs_placeholder := false


func _initialize() -> void:
	_ensure_ecs_placeholder()
	var scene_resource := load(DEMO_WORLD_SCENE_PATH) as PackedScene
	if scene_resource == null:
		_failures.append("Demo world scene loads for selection validation")
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
	_expect(bootstrap != null, "GameBootstrap exists for selection validation")
	if bootstrap == null:
		_finish()
		return
	var gecs := bootstrap.get_node_or_null("GecsWorldController")
	var population_controller := bootstrap.get_node_or_null("PopulationController")
	var projection_controller := bootstrap.get_node_or_null("WorldActorProjectionController")
	var selection_controller := bootstrap.get_node_or_null("WorldSelectionController")
	var control_controller := bootstrap.get_node_or_null("WorldPlayerControlController")
	var details_panel := scene.get_node_or_null("GameHUD/HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel")
	_expect(gecs != null, "GecsWorldController exists")
	_expect(population_controller != null, "PopulationController exists")
	_expect(projection_controller != null, "WorldActorProjectionController exists")
	_expect(selection_controller != null, "WorldSelectionController exists")
	_expect(control_controller != null, "WorldPlayerControlController exists")
	_expect(details_panel != null and details_panel.has_method("get_debug_state"), "HumanoidDetailsPanel has GECS-backed renderer")
	if gecs == null or population_controller == null or projection_controller == null or selection_controller == null or control_controller == null or details_panel == null:
		_finish()
		return
	projection_controller.sync_projections()
	await process_frame

	_validate_player_selection(selection_controller, details_panel, projection_controller, "player.mira", "Mira", "steel_sword", "ranger_jerkin")
	_validate_skills_action(scene, gecs, selection_controller, control_controller, details_panel, "player.mira")
	_validate_skill_import_preserves_gecs_runtime_state(scene, population_controller, gecs)
	_validate_player_selection(selection_controller, details_panel, projection_controller, "player.tomas", "Tomas", "iron_axe", "peasant_tunic")
	_validate_other_projected_character(selection_controller, details_panel)
	_validate_gecs_update_refresh(gecs, selection_controller, details_panel)
	_finish()


func _validate_player_selection(selection_controller: Node, details_panel: Node, projection_controller: Node, actor_id: String, expected_name: String, expected_weapon: String, expected_chest: String) -> void:
	_expect(bool(selection_controller.call("select_actor_id", actor_id)), "Can select %s" % actor_id)
	var snapshot: Dictionary = selection_controller.call("get_selected_details_snapshot")
	_expect(str(selection_controller.call("get_selected_actor_id")) == actor_id, "Selected actor id is %s" % actor_id)
	_expect(str(snapshot.get("member_name", "")) == expected_name, "%s selection shows name" % expected_name)
	_expect(str(snapshot.get("faction_id", "")) == "Player", "%s selection shows faction" % expected_name)
	_expect(str(snapshot.get("party_id", "")) == "player_party", "%s selection shows party" % expected_name)
	_expect(str(snapshot.get("projection_kind", "")) == "humanoid", "%s selection resolves humanoid projection" % expected_name)
	_expect(float(snapshot.get("hp", 0.0)) > 0.0 and float(snapshot.get("max_hp", 0.0)) > 0.0, "%s selection shows vitals" % expected_name)
	_expect(str(snapshot.get("stats_summary", "")) != "-", "%s selection shows stats" % expected_name)
	_expect(str(snapshot.get("skills_summary", "")) != "-", "%s selection shows skills" % expected_name)
	_expect(str(snapshot.get("wounds_summary", "")).begins_with("Wounds:"), "%s selection shows wound/life summary" % expected_name)
	_expect(str(snapshot.get("combat_summary", "")).contains("Stance:"), "%s selection shows combat state" % expected_name)
	_expect(float(snapshot.get("effective_attack_damage", 0.0)) > float(snapshot.get("base_attack_damage", 0.0)), "%s selection exposes equipped attack damage" % expected_name)
	_expect(snapshot.get("equipment_stat_modifiers", []) is Array and (snapshot.get("equipment_stat_modifiers", []) as Array).size() > 0, "%s selection exposes equipment modifiers" % expected_name)
	_expect(str(snapshot.get("objective_summary", "")).strip_edges() != "", "%s selection shows objective/activity" % expected_name)
	var equipment_slots: Dictionary = snapshot.get("equipment_slots", {}) if snapshot.get("equipment_slots", {}) is Dictionary else {}
	_expect(str(equipment_slots.get("weapon", "")) == expected_weapon, "%s selection shows weapon" % expected_name)
	_expect(str(equipment_slots.get("chest", "")) == expected_chest, "%s selection shows chest equipment" % expected_name)
	var projection := projection_controller.call("get_projection_for_actor", actor_id) as Node
	_expect(projection != null and projection.is_in_group("selected_actor"), "%s projection is marked selected" % expected_name)
	_expect(projection != null and projection.is_in_group("selected_party_member"), "%s projection is marked selected party member" % expected_name)
	_expect(projection != null and projection.get_node_or_null("SelectionHitArea") != null, "%s projection has selection hit area" % expected_name)
	var panel_state: Dictionary = details_panel.call("get_debug_state")
	_expect(str(panel_state.get("name", "")) == expected_name, "%s panel renders selected name" % expected_name)
	_expect(str(panel_state.get("faction", "")) == "Player", "%s panel renders main-style faction text" % expected_name)
	_expect(bool(panel_state.get("info_rows_visible", false)), "%s details show derived combat info rows" % expected_name)
	var info_labels: Array = panel_state.get("info_labels", []) if panel_state.get("info_labels", []) is Array else []
	_expect(info_labels.has("Combat"), "%s details panel shows combat row" % expected_name)
	_expect(info_labels.has("Defense"), "%s details panel shows defense row" % expected_name)
	var vital_labels: Array = panel_state.get("vital_labels", []) if panel_state.get("vital_labels", []) is Array else []
	_expect(vital_labels == ["Hunger", "Blood", "Health", "Fatigue"], "%s details rows use main humanoid vitals" % expected_name)
	_expect(str(panel_state.get("hunger", "")).contains("Well Nourished"), "%s hunger row shows main stage/value text" % expected_name)
	_expect(str(panel_state.get("fatigue", "")).contains("Well Rested"), "%s fatigue row shows main stage/value text" % expected_name)
	_expect(not _joined_details_text(panel_state).contains("Life"), "%s details panel does not show fake Life bar" % expected_name)
	_expect(_joined_details_text(panel_state).contains("Damage"), "%s details panel shows derived damage" % expected_name)
	_expect(not _joined_details_text(panel_state).contains("Modifiers"), "%s compact details panel omits raw modifier row" % expected_name)
	var action_texts := _visible_action_texts(panel_state)
	_expect(action_texts.has("Inventory"), "%s details actions include Inventory" % expected_name)
	_expect(action_texts.has("Skills"), "%s details actions include Skills" % expected_name)
	_expect(action_texts.has("Jobs"), "%s details actions include Jobs" % expected_name)
	_expect(not action_texts.has("Order"), "%s details actions do not show invalid Order" % expected_name)
	_expect(not action_texts.has("Action"), "%s details actions do not show stale placeholders" % expected_name)


func _validate_other_projected_character(selection_controller: Node, details_panel: Node) -> void:
	var other_actor_id := ""
	for node in get_nodes_in_group("projected_world_actor"):
		if not (node is Node):
			continue
		var actor_id := str((node as Node).get("actor_id"))
		if not actor_id.is_empty() and not actor_id.begins_with("player."):
			other_actor_id = actor_id
			break
	_expect(not other_actor_id.is_empty(), "At least one non-player projected character exists")
	if other_actor_id.is_empty():
		return
	_expect(bool(selection_controller.call("select_actor_id", other_actor_id)), "Can select non-player projected character")
	var snapshot: Dictionary = selection_controller.call("get_selected_details_snapshot")
	_expect(str(snapshot.get("actor_id", "")) == other_actor_id, "Non-player selection resolves GECS record")
	_expect(not str(snapshot.get("member_name", "")).is_empty(), "Non-player details show name")
	_expect(not str(snapshot.get("faction_id", "")).is_empty(), "Non-player details show faction")
	var panel_state: Dictionary = details_panel.call("get_debug_state")
	_expect(str(panel_state.get("name", "")).strip_edges() == str(snapshot.get("member_name", "")).strip_edges(), "Panel renders non-player selected name")


func _validate_gecs_update_refresh(gecs: Node, selection_controller: Node, details_panel: Node) -> void:
	var record: Dictionary = gecs.call("get_population_record", "player.tomas") if gecs.has_method("get_population_record") else {}
	_expect(not record.is_empty(), "Tomas GECS record exists before update")
	if record.is_empty():
		return
	record["hp"] = 42.0
	record["blood"] = 3.0
	record["ledger_activity_state"] = "medical_recovery"
	gecs.call("upsert_population_record", record)
	selection_controller.call("select_actor_id", "player.tomas")
	var snapshot: Dictionary = selection_controller.call("refresh_selection_details")
	_expect(is_equal_approx(float(snapshot.get("hp", 0.0)), 42.0), "Selection details refresh after GECS HP update")
	_expect(is_equal_approx(float(snapshot.get("blood", 0.0)), 3.0), "Selection details refresh after GECS blood update")
	_expect(str(snapshot.get("objective_summary", "")).contains("Medical Recovery"), "Selection details refresh GECS activity update")
	var panel_state: Dictionary = details_panel.call("get_debug_state")
	_expect(str(panel_state.get("hp", "")).contains("42"), "Panel health text updates from GECS")
	_expect(str(panel_state.get("blood", "")).contains("3"), "Panel blood text updates from GECS")


func _validate_skills_action(scene: Node, gecs: Node, selection_controller: Node, control_controller: Node, details_panel: Node, actor_id: String) -> void:
	var record: Dictionary = gecs.call("get_population_record", actor_id) if gecs != null and gecs.has_method("get_population_record") else {}
	_expect(not record.is_empty(), "Skills validation has GECS population record")
	if not record.is_empty():
		var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
		if not skill_levels.has("attribute.strength"):
			skill_levels["attribute.strength"] = SkillRules.DEFAULT_LEVEL
		record["skill_levels"] = skill_levels.duplicate(true)
		record["skill_xp"] = {"attribute.strength": 25.0}
		gecs.call("upsert_population_record", record)
	selection_controller.call("select_actor_id", actor_id)
	var button := _visible_action_button(details_panel, "Skills")
	_expect(button != null, "Skills action button is visible")
	if button == null:
		return
	button.emit_signal("pressed")
	var window := scene.get_node_or_null("GameHUD/InventoryWindowLayer/CharacterSkillsWindow")
	_expect(window != null and window.has_method("get_debug_state"), "Skills action opens GECS-backed skills window")
	if window == null or not window.has_method("get_debug_state"):
		return
	var state: Dictionary = window.call("get_debug_state")
	var rows: Dictionary = state.get("rows", {}) if state.get("rows", {}) is Dictionary else {}
	var sections: Dictionary = state.get("sections", {}) if state.get("sections", {}) is Dictionary else {}
	_expect(bool(state.get("visible", false)), "Skills window is visible after action")
	_expect(str(state.get("actor_id", "")) == actor_id, "Skills window tracks selected actor id")
	_expect(not bool(state.get("depends_on_live_actor", true)), "Skills window does not depend on live actor")
	_expect(control_controller.has_method("_ui_blocks_control") and not bool(control_controller.call("_ui_blocks_control")), "Skills window open does not block world movement controls")
	var window_size: Vector2 = state.get("window_size", Vector2.ZERO)
	_expect(window_size.is_equal_approx(Vector2(760.0, 520.0)), "Skills window uses main size")
	_expect(bool(state.get("has_scroll_container", false)), "Skills window body is scrollable")
	_expect(int(state.get("column_count", 0)) == 2, "Skills window uses main two-column layout")
	_expect(_section_title(sections, "attributes") == "Core Attributes", "Skills window has Core Attributes section")
	_expect(not sections.has("gear_effects"), "Skills window does not contain Gear Effects")
	_expect(_section_title(sections, "combat") == "Combat", "Skills window has Combat section")
	_expect(_section_title(sections, "subterfuge") == "Subterfuge", "Skills window has Subterfuge section")
	_expect(_section_title(sections, "movement") == "Movement", "Skills window has Movement section")
	_expect(_section_title(sections, "labor") == "Labor", "Skills window has Labor section")
	_expect(_section_title(sections, "craft") == "Crafting", "Skills window has Crafting section")
	_expect(_section_title(sections, "knowledge_tech") == "Knowledge / Tech", "Skills window groups knowledge and tech")
	_expect(rows.has("attribute.strength"), "Skills window includes Strength from catalog")
	_expect(rows.has("labor.mining"), "Skills window includes Mining from catalog")
	_expect(rows.has("tech.robotics"), "Skills window includes Robotics from catalog")
	var strength_row: Dictionary = rows.get("attribute.strength", {}) if rows.get("attribute.strength", {}) is Dictionary else {}
	_expect(bool(strength_row.get("has_progress", false)), "Skills row includes progress control")
	var updated_record: Dictionary = gecs.call("get_population_record", actor_id) if gecs != null and gecs.has_method("get_population_record") else {}
	var updated_levels: Dictionary = updated_record.get("skill_levels", {}) if updated_record.get("skill_levels", {}) is Dictionary else {}
	var strength_level := int(updated_levels.get("attribute.strength", SkillRules.DEFAULT_LEVEL))
	var expected_xp_to_next := SkillRules.get_xp_to_next_level(strength_level)
	_expect(str(strength_row.get("level", "")) == "Lv %d" % strength_level, "Skills row renders GECS skill level")
	_expect(str(strength_row.get("xp", "")) == "%d / %d" % [25, int(ceil(expected_xp_to_next))], "Skills row renders GECS skill XP")
	_expect(is_equal_approx(float(strength_row.get("progress_value", 0.0)), 25.0), "Skills progress value uses GECS XP")
	_expect(is_equal_approx(float(strength_row.get("progress_max", 0.0)), expected_xp_to_next), "Skills progress max uses level display denominator")
	var fallback_record := updated_record.duplicate(true)
	fallback_record.erase("skill_xp")
	window.call("show_for_actor_id", actor_id, fallback_record)
	var fallback_state: Dictionary = window.call("get_debug_state")
	var fallback_rows: Dictionary = fallback_state.get("rows", {}) if fallback_state.get("rows", {}) is Dictionary else {}
	var fallback_strength: Dictionary = fallback_rows.get("attribute.strength", {}) if fallback_rows.get("attribute.strength", {}) is Dictionary else {}
	_expect(is_equal_approx(float(fallback_strength.get("progress_value", -1.0)), 0.0), "Skills window missing skill_xp falls back to empty progress")
	_expect(bool(fallback_strength.get("has_progress_background", false)) and bool(fallback_strength.get("has_progress_fill", false)), "Skills window empty progress bar remains visibly styled")
	var post_fallback_record: Dictionary = gecs.call("get_population_record", actor_id) if gecs != null and gecs.has_method("get_population_record") else {}
	var post_fallback_xp: Dictionary = post_fallback_record.get("skill_xp", {}) if post_fallback_record.get("skill_xp", {}) is Dictionary else {}
	_expect(is_equal_approx(float(post_fallback_xp.get("attribute.strength", 0.0)), 25.0), "Skills window does not mutate GECS records on fallback display")


func _validate_skill_import_preserves_gecs_runtime_state(scene: Node, population_controller: Node, gecs: Node) -> void:
	var actor_id := "validation.skill_import"
	var actor := CharacterAuthoringActor.new()
	actor.name = "SkillImportValidationActor"
	actor.stable_id = actor_id
	actor.member_name = "Skill Import Validation"
	actor.starting_skill_levels = {"movement.running": 4}
	actor.starting_skill_xp = {"movement.running": 5.0}
	scene.add_child(actor)
	var imported: Dictionary = population_controller.call("_new_record_from_actor", actor, actor_id, "validation", {})
	var imported_levels: Dictionary = imported.get("skill_levels", {}) if imported.get("skill_levels", {}) is Dictionary else {}
	var imported_xp: Dictionary = imported.get("skill_xp", {}) if imported.get("skill_xp", {}) is Dictionary else {}
	_expect(int(imported_levels.get("movement.running", 0)) == 4, "Authored actor skill levels seed new GECS record")
	_expect(is_equal_approx(float(imported_xp.get("movement.running", 0.0)), 5.0), "Authored actor skill XP seeds new GECS record")

	gecs.call("upsert_population_record", imported)
	var gecs_record: Dictionary = gecs.call("get_population_record", actor_id) if gecs.has_method("get_population_record") else {}
	gecs_record["skill_levels"] = {"movement.running": 4}
	gecs_record["skill_xp"] = {"movement.running": 37.0}
	gecs.call("upsert_population_record", gecs_record)
	actor.starting_skill_levels = {"movement.running": 99}
	actor.starting_skill_xp = {"movement.running": 999.0}
	var latest: Dictionary = population_controller.call("_get_actor_record_mutable", actor_id)
	var preserved: Dictionary = population_controller.call("_merge_actor_state_into_record", latest, actor, "validation", {})
	var preserved_levels: Dictionary = preserved.get("skill_levels", {}) if preserved.get("skill_levels", {}) is Dictionary else {}
	var preserved_xp: Dictionary = preserved.get("skill_xp", {}) if preserved.get("skill_xp", {}) is Dictionary else {}
	_expect(int(preserved_levels.get("movement.running", 0)) == 4, "Runtime actor sync preserves GECS skill levels")
	_expect(is_equal_approx(float(preserved_xp.get("movement.running", 0.0)), 37.0), "Runtime actor sync preserves GECS skill XP")
	if population_controller.has_method("remove_actor_record"):
		population_controller.call("remove_actor_record", actor_id, false)
	if actor.is_inside_tree():
		actor.queue_free()


func _section_title(sections: Dictionary, section_id: String) -> String:
	var data: Dictionary = sections.get(section_id, {}) if sections.get(section_id, {}) is Dictionary else {}
	return str(data.get("title", ""))


func _finish() -> void:
	if _failures.is_empty():
		print("CHARACTER_SELECTION_DETAILS_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _visible_action_texts(panel_state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var actions: Array = panel_state.get("actions", []) if panel_state.get("actions", []) is Array else []
	for action in actions:
		if not (action is Dictionary):
			continue
		if bool((action as Dictionary).get("visible", false)):
			result.append(str((action as Dictionary).get("text", "")))
	return result


func _visible_action_button(details_panel: Node, label: String) -> Button:
	var action_row := details_panel.get_node_or_null("Margin/DetailsVBox/ActionRow")
	if action_row == null:
		return null
	for child in action_row.get_children():
		var button := child as Button
		if button != null and button.visible and button.text == label:
			return button
	return null


func _joined_details_text(panel_state: Dictionary) -> String:
	var labels: Array = panel_state.get("info_labels", []) if panel_state.get("info_labels", []) is Array else []
	var vital_labels: Array = panel_state.get("vital_labels", []) if panel_state.get("vital_labels", []) is Array else []
	var values: Array = panel_state.get("info_values", []) if panel_state.get("info_values", []) is Array else []
	var parts: Array[String] = []
	for value in labels:
		parts.append(str(value))
	for value in vital_labels:
		parts.append(str(value))
	for value in values:
		parts.append(str(value))
	for key in ["hunger", "blood", "hp", "fatigue"]:
		parts.append(str(panel_state.get(key, "")))
	return "\n".join(parts)


func _ensure_ecs_placeholder() -> void:
	if Engine.has_singleton("ECS"):
		return
	_ecs_placeholder = EcsPlaceholder.new()
	_ecs_placeholder.name = "ECSPlaceholder"
	Engine.register_singleton("ECS", _ecs_placeholder)
	_registered_ecs_placeholder = true


func _promote_root_ecs_singleton() -> void:
	if not _registered_ecs_placeholder:
		return
	var ecs_node := root.get_node_or_null("ECS")
	if ecs_node == null:
		return
	Engine.unregister_singleton("ECS")
	if _ecs_placeholder != null:
		_ecs_placeholder.free()
		_ecs_placeholder = null
	Engine.register_singleton("ECS", ecs_node)
	_registered_ecs_placeholder = false
