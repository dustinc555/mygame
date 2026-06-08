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
		_failures.append("Demo world scene loads for party panel validation")
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
	_expect(bootstrap != null, "GameBootstrap exists for party panel validation")
	if bootstrap == null:
		_finish()
		return
	var gecs := bootstrap.get_node_or_null("GecsWorldController")
	var projection_controller := bootstrap.get_node_or_null("WorldActorProjectionController")
	var selection_controller := bootstrap.get_node_or_null("WorldSelectionController")
	var control_controller := bootstrap.get_node_or_null("WorldPlayerControlController")
	var movement_sim := bootstrap.get_node_or_null("WorldMovementOrderSimController")
	var party_panel := bootstrap.get_node_or_null("WorldPartyPanelController")
	var portrait_flow := scene.get_node_or_null("GameHUD/HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/PortraitScroll/PortraitFlow")
	_expect(gecs != null, "GecsWorldController exists")
	_expect(projection_controller != null, "WorldActorProjectionController exists")
	_expect(selection_controller != null, "WorldSelectionController exists")
	_expect(control_controller != null, "WorldPlayerControlController exists")
	_expect(movement_sim != null, "WorldMovementOrderSimController exists")
	_expect(party_panel != null, "WorldPartyPanelController exists")
	_expect(portrait_flow != null, "PortraitFlow exists in HUD")
	if gecs == null or projection_controller == null or selection_controller == null or control_controller == null or movement_sim == null or party_panel == null:
		_finish()
		return
	projection_controller.sync_projections()
	var records: Array = party_panel.call("refresh_party_panel")
	await _wait_for_portraits()

	_validate_party_records(records)
	_validate_party_cards(party_panel)
	_validate_card_selection_handoff(party_panel, selection_controller)
	_validate_card_double_click_follow(scene, party_panel, projection_controller, selection_controller)
	_validate_controlled_marker(party_panel, gecs, selection_controller, control_controller)
	await _validate_gecs_update_refresh(gecs, party_panel)
	_finish()


func _validate_party_records(records: Array) -> void:
	_expect(records.size() >= 2, "Party panel has at least Mira and Tomas records")
	var ids := _record_ids(records)
	_expect(ids.has("player.mira"), "Party panel includes Mira record")
	_expect(ids.has("player.tomas"), "Party panel includes Tomas record")
	for record in records:
		if not (record is Dictionary):
			continue
		var actor_id := str((record as Dictionary).get("actor_id", ""))
		if actor_id == "player.mira" or actor_id == "player.tomas":
			_expect(bool((record as Dictionary).get("player_party_member", false)), "%s is party-backed" % actor_id)
			_expect(bool((record as Dictionary).get("player_controllable", false)), "%s is controllable-backed" % actor_id)
			_expect(float((record as Dictionary).get("max_hp", 0.0)) > 0.0, "%s projects vitals into record snapshot" % actor_id)
			_expect(not str((record as Dictionary).get("equipment_summary", "")).is_empty(), "%s projects equipment summary into record snapshot" % actor_id)
			_expect(not str((record as Dictionary).get("objective_summary", "")).is_empty(), "%s projects objective summary into record snapshot" % actor_id)
			_expect(str((record as Dictionary).get("combat_summary", "")).contains("Stance:"), "%s projects combat summary into record snapshot" % actor_id)


func _validate_party_cards(party_panel: Node) -> void:
	var debug: Dictionary = party_panel.call("get_debug_state")
	var cards: Dictionary = debug.get("cards", {}) if debug.get("cards", {}) is Dictionary else {}
	_expect(cards.has("player.mira"), "Party panel has Mira card")
	_expect(cards.has("player.tomas"), "Party panel has Tomas card")
	var expected_names := {
		"player.mira": "Mira",
		"player.tomas": "Tomas",
	}
	for actor_id in expected_names.keys():
		if not cards.has(actor_id):
			continue
		var state: Dictionary = cards[actor_id]
		var card := party_panel.call("get_card_for_actor", actor_id) as Button
		_expect(card != null, "%s card node can be looked up" % actor_id)
		if card == null:
			continue
		var script := card.get_script() as Script
		_expect(script != null and script.resource_path == "res://scripts/ui/party_portrait_card.gd", "%s uses PartyPortraitCard script" % actor_id)
		var name_label := card.get_node_or_null("Margin/VBox/Name") as Label
		var portrait_image := card.get_node_or_null("Margin/VBox/PortraitImage") as TextureRect
		var portrait_root := card.get_node_or_null("Margin/VBox/PortraitViewportContainer/SubViewport/PortraitRoot") as Node3D
		_expect(name_label != null, "%s card has main-style name label" % actor_id)
		_expect(portrait_image != null, "%s card has main-style portrait image" % actor_id)
		_expect(portrait_root != null, "%s card has main-style portrait root" % actor_id)
		if name_label != null:
			_expect(name_label.text == str(expected_names[actor_id]), "%s card visible label is name-only" % actor_id)
		if portrait_image != null:
			_expect(portrait_image.texture != null, "%s card captures portrait texture" % actor_id)
		if portrait_root != null:
			_expect(_count_mesh_instances(portrait_root) > 0, "%s card duplicates projection visuals into portrait viewport" % actor_id)
		var source_child_names: Array = state.get("portrait_source_child_names", []) if state.get("portrait_source_child_names", []) is Array else []
		_expect(source_child_names.has("CharacterVisual"), "%s portrait source exposes main-style CharacterVisual" % actor_id)
		_expect(is_equal_approx(float(state.get("portrait_yaw_offset", -1.0)), PI), "%s portrait uses main-style portrait yaw offset" % actor_id)
		_expect(str(state.get("pose_animation", "")) == "Idle", "%s portrait samples main Idle pose" % actor_id)
		var visible_text := _visible_text_under(card)
		_expect(visible_text == str(expected_names[actor_id]), "%s visible card text is portrait name only" % actor_id)
		_expect(str(state.get("button_text", "")).is_empty(), "%s button text remains empty" % actor_id)
		_expect(not _contains_rejected_card_text(visible_text), "%s visible card omits status/equipment/objective lines" % actor_id)
	_expect(str(debug.get("squad_name", "")).begins_with("Party:"), "Party panel header shows projected party count")


func _validate_card_selection_handoff(party_panel: Node, selection_controller: Node) -> void:
	var card := party_panel.call("get_card_for_actor", "player.tomas") as Button
	_expect(card != null, "Tomas card can be looked up")
	if card == null:
		return
	if card.has_signal("portrait_pressed"):
		card.emit_signal("portrait_pressed", "player.tomas", false, false)
	else:
		card.emit_signal("pressed")
	party_panel.call("refresh_party_panel")
	_expect(str(selection_controller.call("get_selected_actor_id")) == "player.tomas", "Party card press selects Tomas through selection controller")
	var debug: Dictionary = party_panel.call("get_debug_state")
	var cards: Dictionary = debug.get("cards", {}) if debug.get("cards", {}) is Dictionary else {}
	var tomas: Dictionary = cards.get("player.tomas", {}) if cards.get("player.tomas", {}) is Dictionary else {}
	_expect(bool(tomas.get("pressed", false)), "Selected party card is marked pressed")
	_expect(bool(tomas.get("selected", false)), "Selected party card stores selected state")
	_expect(str(tomas.get("button_text", "")).is_empty(), "Selected party card does not add visible text marker")


func _validate_card_double_click_follow(scene: Node, party_panel: Node, projection_controller: Node, selection_controller: Node) -> void:
	var card := party_panel.call("get_card_for_actor", "player.mira") as Button
	var projection := projection_controller.call("get_projection_for_actor", "player.mira") as Node3D
	var rig := scene.find_child("CameraRig", true, false)
	_expect(card != null, "Mira card can be looked up for double-click follow")
	_expect(projection != null, "Mira projection exists for portrait follow")
	_expect(rig != null and rig.has_method("get_follow_target"), "Camera rig exposes follow target for portrait validation")
	if card == null or projection == null or rig == null:
		return
	if card.has_signal("portrait_pressed"):
		card.emit_signal("portrait_pressed", "player.mira", true, false)
	else:
		card.emit_signal("pressed")
	party_panel.call("refresh_party_panel")
	_expect(str(selection_controller.call("get_selected_actor_id")) == "player.mira", "Party card double-click selects Mira")
	_expect(rig.call("get_follow_target") == projection, "Party card double-click follows Mira projection")


func _validate_controlled_marker(party_panel: Node, gecs: Node, selection_controller: Node, control_controller: Node) -> void:
	selection_controller.call("select_actor_id", "player.mira")
	var record: Dictionary = gecs.call("get_population_record", "player.mira")
	control_controller.call("issue_move_command_at_world_position", _record_position(record) + Vector3(2.0, 0.0, 0.0), false)
	party_panel.call("refresh_party_panel")
	var debug: Dictionary = party_panel.call("get_debug_state")
	var cards: Dictionary = debug.get("cards", {}) if debug.get("cards", {}) is Dictionary else {}
	var mira: Dictionary = cards.get("player.mira", {}) if cards.get("player.mira", {}) is Dictionary else {}
	_expect(bool(mira.get("controlled", false)), "Controlled party card stores control state")
	_expect(str(mira.get("button_text", "")).is_empty(), "Controlled party card does not add visible text marker")


func _validate_gecs_update_refresh(gecs: Node, party_panel: Node) -> void:
	var record: Dictionary = gecs.call("get_population_record", "player.tomas") if gecs.has_method("get_population_record") else {}
	_expect(not record.is_empty(), "Tomas GECS record exists before party panel update")
	if record.is_empty():
		return
	record["hp"] = 33.0
	record["blood"] = 2.0
	record["ledger_activity_state"] = "guarding_party"
	gecs.call("upsert_population_record", record)
	party_panel.call("refresh_party_panel")
	await _wait_for_portraits()
	var card := party_panel.call("get_card_for_actor", "player.tomas") as Button
	_expect(card != null, "Tomas card still exists after GECS update")
	if card == null:
		return
	var visible_text := _visible_text_under(card)
	_expect(visible_text == "Tomas", "Party card remains name-only after GECS update")
	_expect(not card.text.contains("HP 33"), "Party card does not expose GECS HP as visible text")
	_expect(not card.text.contains("Blood 2"), "Party card does not expose GECS blood as visible text")
	_expect(not visible_text.contains("Guarding Party"), "Party card does not expose GECS activity as visible text")
	var panel_record: Dictionary = card.get_meta("party_panel_record", {}) if card.get_meta("party_panel_record", {}) is Dictionary else {}
	_expect(is_equal_approx(float(panel_record.get("hp", 0.0)), 33.0), "Party card stores latest projected GECS snapshot")
	_expect(is_equal_approx(float(panel_record.get("blood", 0.0)), 2.0), "Party card stores latest projected GECS blood snapshot")
	_expect(str(panel_record.get("objective_summary", "")) == "Guarding Party", "Party card stores latest projected GECS activity snapshot")


func _record_ids(records: Array) -> Array[String]:
	var ids: Array[String] = []
	for record in records:
		if record is Dictionary:
			ids.append(str((record as Dictionary).get("actor_id", "")))
	return ids


func _record_position(record: Dictionary) -> Vector3:
	var position = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return position if position is Vector3 else Vector3.ZERO


func _wait_for_portraits() -> void:
	for _index in range(5):
		await process_frame


func _visible_text_under(node: Node) -> String:
	var parts: Array[String] = []
	_collect_visible_text(node, parts)
	return "\n".join(parts)


func _collect_visible_text(node: Node, parts: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Button:
		var button_text := (node as Button).text.strip_edges()
		if not button_text.is_empty():
			parts.append(button_text)
	elif node is Label:
		var label_text := (node as Label).text.strip_edges()
		if not label_text.is_empty():
			parts.append(label_text)
	for child in node.get_children():
		_collect_visible_text(child, parts)


func _contains_rejected_card_text(text: String) -> bool:
	for token in ["HP", "Blood", "Alive", "Dying", "Dead", "Weapon", "Chest", "Objective", "Guarding", "[SEL]", "[CTRL]"]:
		if text.contains(token):
			return true
	return false


func _count_mesh_instances(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count


func _finish() -> void:
	if _failures.is_empty():
		print("PARTY_PANEL_PROJECTION_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


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
