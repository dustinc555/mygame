extends SceneTree

const MINING_SCENE_PATH := "res://scenes/test_levels/mining_test.tscn"
const FOOD_PATH := "res://resources/items/consumables/food.tres"
const COPPER_ORE_PATH := "res://resources/items/materials/copper_ore.tres"

var _failures: Array[String] = []


func _initialize() -> void:
	var scene_resource := load(MINING_SCENE_PATH) as PackedScene
	if scene_resource == null:
		_failures.append("Mining scene loads")
		_finish()
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	call_deferred("_run_validation", scene)


func _run_validation(scene: Node) -> void:
	for _index in range(30):
		await process_frame
	var bootstrap := scene.get_node_or_null("GameBootstrap")
	_expect(bootstrap != null, "GameBootstrap exists")
	if bootstrap == null:
		_finish()
		return
	var gecs := bootstrap.get_node_or_null("GecsWorldController")
	var selection := bootstrap.get_node_or_null("WorldSelectionController")
	var player_control := bootstrap.get_node_or_null("WorldPlayerControlController")
	var movement_runner := bootstrap.get_node_or_null("WorldMovementOrderFixedTickRunner")
	var conversation := bootstrap.get_node_or_null("ConversationController")
	var inventory := bootstrap.get_node_or_null("PartyInventoryController")
	var projection := bootstrap.get_node_or_null("WorldActorProjectionController")
	_expect(gecs != null, "GECS controller exists")
	_expect(selection != null, "Selection controller exists")
	_expect(player_control != null, "Player control controller exists")
	_expect(movement_runner != null, "Movement fixed tick runner exists")
	_expect(conversation != null, "Conversation controller exists")
	_expect(inventory != null, "Inventory controller exists")
	_expect(projection != null, "Projection controller exists")
	if gecs == null or selection == null or player_control == null or movement_runner == null or conversation == null or inventory == null or projection == null:
		_finish()
		return

	_validate_population(gecs, projection)
	_validate_mining_resource(scene, gecs)
	await _validate_trade_inventory(inventory)
	await _validate_conversation_job_offer(gecs, conversation, scene)
	await _validate_mine_and_haul_job(gecs, movement_runner)
	await _validate_pickup_arrival(gecs, selection, player_control, movement_runner)
	await _validate_mining_completion(gecs, selection, player_control, movement_runner, projection, scene)
	_finish()


func _validate_population(gecs: Node, projection: Node) -> void:
	for actor_id in ["player.mira", "player.tomas", "npc.mining_test.jim"]:
		var record: Dictionary = gecs.call("get_population_record", actor_id)
		_expect(not record.is_empty(), "%s GECS population record exists" % actor_id)
		_expect(projection.call("get_projection_for_actor", actor_id) != null, "%s projection exists" % actor_id)
	var jim: Dictionary = gecs.call("get_population_record", "npc.mining_test.jim")
	var traits: Dictionary = jim.get("traits", {}) if jim.get("traits", {}) is Dictionary else {}
	_expect(bool(traits.get("merchant", false)), "Jim is marked as merchant")
	_expect(not str(traits.get("conversation_definition_path", "")).is_empty(), "Jim has conversation definition path")
	_expect(traits.get("job_offers", []) is Array and not (traits.get("job_offers", []) as Array).is_empty(), "Jim has mining job offer metadata")


func _validate_mining_resource(scene: Node, gecs: Node) -> void:
	var copper := scene.get_node_or_null("CopperNode")
	_expect(copper != null and copper.is_in_group("mining_resource"), "Copper node is mining resource")
	_expect(copper != null and copper.has_method("get_mining_action_for_actor"), "Copper node exposes mining action payload")
	if copper == null:
		return
	var action: Dictionary = copper.call("get_mining_action_for_actor", "player.mira", gecs.call("get_population_record", "player.mira"))
	_expect(str(action.get("type", "")) == "mine_resource", "Copper mining action type is stable")
	_expect(str(action.get("item_definition_path", "")) == COPPER_ORE_PATH, "Copper mining action grants copper ore")


func _validate_trade_inventory(inventory: Node) -> void:
	inventory.call("open_inventory_pair", "player.mira", "npc.mining_test.jim")
	await process_frame
	_expect(inventory.call("get_open_inventory_window", "player.mira") != null, "Trade opens Mira inventory")
	_expect(inventory.call("get_open_inventory_window", "npc.mining_test.jim") != null, "Trade opens Jim inventory")


func _validate_conversation_job_offer(gecs: Node, conversation: Node, scene: Node) -> void:
	conversation.call("begin_conversation", "player.mira", "npc.mining_test.jim")
	await process_frame
	var window := scene.get_node_or_null("GameHUD/ConversationWindow") as Control
	_expect(window != null and window.visible, "Talk opens conversation window")
	var actions: Array = conversation.get("displayed_actions")
	var offer: Dictionary = {}
	for action in actions:
		if action is Dictionary and str((action as Dictionary).get("type", "")) == "job_offer":
			offer = (action as Dictionary).get("offer", {})
			break
	_expect(not offer.is_empty(), "Conversation exposes Jim mining job offer")
	if not offer.is_empty():
		conversation.call("_handle_job_offer", offer)
		await process_frame
		var contracts: Array = gecs.call("get_actor_job_contracts", "player.mira")
		var found := false
		for contract in contracts:
			if contract is Dictionary and str((contract as Dictionary).get("job_id", "")) == "jim_mining":
				found = true
		_expect(found, "Accepting Jim job offer writes GECS job contract")
	if window != null and window.has_method("hide_conversation"):
		window.call("hide_conversation")


func _validate_mine_and_haul_job(gecs: Node, movement_runner: Node) -> void:
	var before_count := _container_item_count(gecs, "mining_test.barrel", COPPER_ORE_PATH)
	var after_count := before_count
	for _cycle in range(80):
		await process_frame
		_advance_runner(movement_runner, 30)
		after_count = _container_item_count(gecs, "mining_test.barrel", COPPER_ORE_PATH)
		if after_count > before_count:
			break
	_expect(after_count > before_count, "Mine-and-haul job transfers copper ore to output barrel")


func _validate_pickup_arrival(gecs: Node, selection: Node, player_control: Node, movement_runner: Node) -> void:
	_expect(selection.call("select_actor_id", "player.mira"), "Can select Mira for pickup")
	var grant_result: Dictionary = gecs.call("apply_inventory_command", {"action": "grant_item", "actor_id": "player.mira", "item_definition_path": FOOD_PATH, "count": 1})
	_expect(bool(grant_result.get("ok", false)), "Can grant pickup test item")
	var stack_id := str((grant_result.get("stack_ids", []) as Array)[0]) if grant_result.get("stack_ids", []) is Array and not (grant_result.get("stack_ids", []) as Array).is_empty() else ""
	var mira_record: Dictionary = gecs.call("get_population_record", "player.mira")
	var position: Vector3 = mira_record.get("last_world_position", Vector3.ZERO)
	var drop_result: Dictionary = gecs.call("apply_inventory_command", {"action": "drop_stack", "stack_id": stack_id, "world_position": position})
	_expect(bool(drop_result.get("ok", false)), "Can drop pickup test item to world")
	player_control.call("_issue_actor_interaction_move", "player.mira", position, {"type": "pickup_stack", "stack_id": stack_id}, false)
	_advance_runner(movement_runner, 12)
	await process_frame
	var picked_stack := _stack_snapshot(gecs, stack_id)
	_expect(str(picked_stack.get("container_id", "")) == "player.mira.inventory", "Pickup arrival moves world stack into Mira inventory")


func _validate_mining_completion(gecs: Node, selection: Node, player_control: Node, movement_runner: Node, projection_controller: Node, scene: Node) -> void:
	_expect(selection.call("select_actor_id", "player.mira"), "Can select Mira for mining")
	var before_count := _actor_item_count(gecs, "player.mira", COPPER_ORE_PATH)
	var mira_record: Dictionary = gecs.call("get_population_record", "player.mira")
	var position: Vector3 = mira_record.get("last_world_position", Vector3.ZERO)
	var copper := scene.get_node_or_null("CopperNode")
	var action: Dictionary = copper.call("get_mining_action_for_actor", "player.mira", mira_record) if copper != null else {}
	action["duration_seconds"] = 2.0
	var mining_position: Vector3 = action.get("mining_position", position)
	player_control.call("_issue_actor_interaction_move", "player.mira", mining_position, action, false)
	var saw_mining_animation_ready := false
	var saw_mining_animation := false
	var saw_progress_indicator := false
	var saw_progress_advance := false
	for _cycle in range(240):
		_advance_runner(movement_runner, 3)
		if projection_controller != null and projection_controller.has_method("sync_projections"):
			projection_controller.call("sync_projections")
		await process_frame
		var projection = projection_controller.call("get_projection_for_actor", "player.mira") if projection_controller != null and projection_controller.has_method("get_projection_for_actor") else null
		var debug_state: Dictionary = projection.call("get_projection_debug_state") if projection != null and projection.has_method("get_projection_debug_state") else {}
		var body_state: Dictionary = debug_state.get("body_state", {}) if debug_state.get("body_state", {}) is Dictionary else {}
		var body_projection = projection.call("get_body_projection") if projection != null and projection.has_method("get_body_projection") else null
		var mining_presentation_state: Dictionary = body_projection.call("get_mining_presentation_debug_state") if body_projection != null and body_projection.has_method("get_mining_presentation_debug_state") else {}
		var work_indicator_state: Dictionary = projection.call("get_work_indicator_debug_state") if projection != null and projection.has_method("get_work_indicator_debug_state") else {}
		saw_mining_animation_ready = saw_mining_animation_ready or bool(mining_presentation_state.get("world_mining_animation_ready", false))
		saw_mining_animation = saw_mining_animation or str(mining_presentation_state.get("world_animation", body_state.get("world_animation", ""))) == "Mining"
		saw_progress_indicator = saw_progress_indicator or bool(work_indicator_state.get("visible", false))
		saw_progress_advance = saw_progress_advance or float(work_indicator_state.get("progress", 0.0)) > 0.01
		if _actor_item_count(gecs, "player.mira", COPPER_ORE_PATH) >= before_count + 1 and saw_mining_animation and saw_progress_advance:
			break
	var after_count := _actor_item_count(gecs, "player.mira", COPPER_ORE_PATH)
	_expect(saw_mining_animation_ready, "Humanoid projection imports mining animation")
	_expect(saw_mining_animation, "Mira plays mining animation while mining")
	_expect(saw_progress_indicator, "Mining shows an in-world progress bar")
	_expect(saw_progress_advance, "Mining progress bar advances from GECS work progress")
	_expect(after_count >= before_count + 1, "Mining completion grants copper ore to Mira inventory")


func _advance_runner(runner: Node, ticks: int) -> void:
	for _index in range(ticks):
		runner.call("advance_time", 1.0 / 30.0)


func _actor_item_count(gecs: Node, actor_id: String, item_path: String) -> int:
	var container_id := str(gecs.call("get_actor_inventory_container_id", actor_id))
	return _container_item_count(gecs, container_id, item_path)


func _container_item_count(gecs: Node, container_id: String, item_path: String) -> int:
	var total := 0
	for stack in gecs.call("get_inventory_stacks", container_id):
		if stack is Dictionary and str((stack as Dictionary).get("item_definition_path", "")) == item_path:
			total += int((stack as Dictionary).get("count", 1))
	return total


func _stack_snapshot(gecs: Node, stack_id: String) -> Dictionary:
	for stack in gecs.call("get_inventory_stacks", ""):
		if stack is Dictionary and str((stack as Dictionary).get("stack_id", "")) == stack_id:
			return (stack as Dictionary).duplicate(true)
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MINING_CONTEXT_INTERACTIONS_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error("MINING_CONTEXT_INTERACTIONS_VALIDATION_FAILED: %s" % failure)
	quit(1)
