extends SceneTree

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(120)
	var settlement_controller := _get_controller("settlement_controller")
	var faction_controller := _get_controller("faction_controller")
	var world_squad_controller := _get_controller("world_squad_controller")
	var event_controller := _get_controller("world_event_choice_controller")
	var world_time := _scene.get_node_or_null("GameBootstrap/WorldTimeController")
	if settlement_controller == null or faction_controller == null or world_squad_controller == null or event_controller == null or world_time == null:
		_fail("Controllers missing for raid targeting/time validation")
	else:
		_validate_clock_format(world_time)
		await _validate_raids_are_manual(settlement_controller, faction_controller, world_squad_controller, world_time)
		_validate_raid_target_selection(settlement_controller, faction_controller)
		await _validate_planning_phase_uses_world_clock(settlement_controller, world_squad_controller, event_controller, world_time)
		_validate_combat_disengage_helpers()
	if _failures.is_empty():
		print("RAID_TARGETING_TIME_DISENGAGE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RAID_TARGETING_TIME_DISENGAGE_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_clock_format(world_time: Node) -> void:
	world_time.set("total_world_minutes", 0.0)
	if str(world_time.call("format_time")) != "Mon 12:00 AM":
		_fail("Clock should format midnight as 12:00 AM")
	world_time.set("total_world_minutes", 12.0 * 60.0)
	if str(world_time.call("format_time")) != "Mon 12:00 PM":
		_fail("Clock should format noon as 12:00 PM")
	world_time.set("total_world_minutes", 16.0 * 60.0 + 30.0)
	if str(world_time.call("format_time")) != "Mon 04:30 PM":
		_fail("Clock should format afternoon time with PM suffix")


func _validate_raids_are_manual(settlement_controller: Node, faction_controller: Node, world_squad_controller: Node, world_time: Node) -> void:
	faction_controller.call("set_diplomatic_state", "Raiders", "Farmers", "war")
	settlement_controller.call("set_food", "raider_camp", 0.0, "validation_no_auto_raid")
	var squad_count_before := int(world_squad_controller.call("serialize_state").size())
	var absolute_hour := int(world_time.call("get_absolute_hour")) + 24
	settlement_controller.call("_evaluate_settlement_strategy", "raider_camp", absolute_hour, int(world_time.call("get_day_index")), int(world_time.call("get_hour")))
	await _wait_frames(2)
	var squad_count_after := int(world_squad_controller.call("serialize_state").size())
	if squad_count_after != squad_count_before:
		_fail("Raider raids should not auto-launch from food pressure; use the request/force raid action instead")


func _validate_raid_target_selection(settlement_controller: Node, faction_controller: Node) -> void:
	faction_controller.call("set_diplomatic_state", "Raiders", "Farmers", "war")
	if str(settlement_controller.call("select_food_raid_target", "raider_camp")) != "farmer_crossing":
		_fail("Raider Camp should select Farmer Crossing in the base two-town setup")
	for blocked_state in ["alliance", "protectorate", "trade", "truce", "vassal", "tributary"]:
		faction_controller.call("set_diplomatic_state", "Raiders", "Farmers", blocked_state)
		if str(settlement_controller.call("select_food_raid_target", "raider_camp")) == "farmer_crossing":
			_fail("Raid target selection should block %s relations" % blocked_state)
	faction_controller.call("set_diplomatic_state", "Raiders", "Farmers", "war")
	_register_test_settlement(settlement_controller, "weak_raid_target", "WeakTargets", Vector3(45.0, 0.0, 0.0), 6, 80.0, 120.0)
	_register_test_settlement(settlement_controller, "strong_raid_target", "StrongTargets", Vector3(52.0, 0.0, 0.0), 120, 80.0, 120.0)
	_register_test_settlement(settlement_controller, "same_faction_target", "Raiders", Vector3(56.0, 0.0, 0.0), 1, 300.0, 300.0)
	faction_controller.call("set_diplomatic_state", "Raiders", "WeakTargets", "neutral")
	faction_controller.call("set_diplomatic_state", "Raiders", "StrongTargets", "neutral")
	var selected := str(settlement_controller.call("select_food_raid_target", "raider_camp"))
	if selected != "weak_raid_target":
		_fail("Raiders should prefer the nearby weaker target over same-faction or stronger targets; selected=%s" % selected)
	faction_controller.call("set_diplomatic_state", "Raiders", "WeakTargets", "trade")
	selected = str(settlement_controller.call("select_food_raid_target", "raider_camp"))
	if selected == "weak_raid_target":
		_fail("Trade relations should remove the weak target from raid selection")
	faction_controller.call("set_diplomatic_state", "Raiders", "WeakTargets", "neutral")


func _register_test_settlement(settlement_controller: Node, settlement_id: String, faction_id: String, position: Vector3, population: int, food: float, max_food: float) -> void:
	var faction := FactionDefinition.new()
	faction.faction_id = faction_id
	faction.display_name = faction_id
	var definition := SettlementDefinition.new()
	definition.settlement_id = settlement_id
	definition.display_name = settlement_id.capitalize()
	definition.faction_definition = faction
	definition.world_position = position
	definition.starting_food = food
	definition.max_food = max_food
	settlement_controller.call("_register_settlement_definition", definition, null)
	var states: Dictionary = settlement_controller.get("settlement_states")
	var state: Dictionary = states.get(settlement_id, {})
	state["population"] = population
	state["max_occupancy"] = max(population, 1)
	state["food"] = food
	state["max_food"] = maxf(max_food, 1.0)
	state["food_ratio"] = clampf(food / maxf(max_food, 1.0), 0.0, 1.0)
	state["world_position"] = position
	states[settlement_id] = state


func _validate_planning_phase_uses_world_clock(settlement_controller: Node, world_squad_controller: Node, event_controller: Node, world_time: Node) -> void:
	var farmer_anchor: Node3D = settlement_controller.call("get_settlement_anchor", "farmer_crossing") as Node3D
	var player := _scene.get_node_or_null("PartyMembers/Mira") as Node3D
	if farmer_anchor == null or player == null:
		_fail("Could not position player for planning phase validation")
		return
	var prompt_position: Vector3 = farmer_anchor.call("get_spawn_position", "defense") if farmer_anchor.has_method("get_spawn_position") else farmer_anchor.global_position
	player.global_position = prompt_position
	var event_count_before := int(event_controller.call("get_event_count"))
	var event_id := "raider_camp:farmer_crossing:%d" % int(world_time.call("get_absolute_hour"))
	if not bool(settlement_controller.call("force_food_raid", "raider_camp", "farmer_crossing")):
		_fail("Forced raid failed for planning phase validation")
		return
	await _wait_frames(2)
	var squad_id := _first_squad_id(world_squad_controller)
	if squad_id.is_empty():
		_fail("Planning phase validation could not find spawned squad")
		return
	world_squad_controller.call("debug_force_phase", squad_id, "planning")
	world_time.call("advance_minutes", 59.0)
	world_squad_controller.call("_process_active_squads")
	var squad_state: Dictionary = world_squad_controller.call("get_squad_state", squad_id)
	if str(squad_state.get("phase_id", "")) != "planning":
		_fail("Raid planning should still be active before 60 world minutes")
	if float(squad_state.get("phase_elapsed", 0.0)) < 58.9:
		_fail("Raid planning elapsed time should follow world minutes")
	world_time.call("advance_minutes", 1.0)
	world_squad_controller.call("_process_active_squads")
	squad_state = world_squad_controller.call("get_squad_state", squad_id)
	if str(squad_state.get("phase_id", "")) != "battle":
		_fail("Raid planning should transition to battle after 60 world minutes")
	if int(event_controller.call("get_event_count")) <= event_count_before:
		_fail("Battle transition should create a local conflict event")
	if event_controller.call("get_event", event_id) == null:
		_fail("Battle transition created no event with the raid action id")
	if not bool(event_controller.call("is_prompt_visible")):
		_fail("Battle transition should show the local choice prompt")
	if not bool(world_time.call("is_world_paused")):
		_fail("Battle prompt should pause world time")
	if event_controller.has_method("debug_ignore_event"):
		event_controller.call("debug_ignore_event", event_id)


func _validate_combat_disengage_helpers() -> void:
	var raider := _first_resident_at("Settlements/RaiderCamp/Residents")
	var farmer := _first_resident_at("Settlements/FarmerCrossing/Residents")
	if raider == null or farmer == null:
		_fail("Could not find actors for combat disengage validation")
		return
	var raider_position := raider.global_position
	var farmer_position := farmer.global_position
	raider.call("cancel_ai_job")
	farmer.call("cancel_ai_job")
	raider.call("stop_attack_assignment")
	farmer.call("stop_attack_assignment")
	farmer.call("set_move_target", farmer.global_position + Vector3(5.0, 0.0, 0.0), true)
	if not bool(farmer.call("_is_player_order_to_avoid_combat")):
		_fail("Player-issued movement should suppress automatic combat re-engagement")
	raider.global_position = Vector3.ZERO
	farmer.global_position = Vector3(4.0, 0.0, 0.0)
	raider.set("combat_chase_leash_distance", 10.0)
	raider.set("attack_range", 1.15)
	raider.call("assign_attack_target", farmer, false, false, false)
	raider.call("cancel_ai_job")
	farmer.global_position = Vector3(35.0, 0.0, 0.0)
	if not bool(raider.call("_should_abandon_attack_chase")):
		_fail("NPC attack orders should abandon targets beyond the chase leash")
	raider.call("stop_attack_assignment")
	raider.global_position = Vector3.ZERO
	farmer.global_position = Vector3(4.0, 0.0, 0.0)
	raider.call("assign_attack_target", farmer, true, false, false)
	farmer.global_position = Vector3(35.0, 0.0, 0.0)
	if bool(raider.call("_should_abandon_attack_chase")):
		_fail("Player-issued attack orders should not be cancelled by the NPC chase leash")
	raider.call("stop_attack_assignment")
	farmer.call("stop_attack_assignment")
	raider.global_position = raider_position
	farmer.global_position = farmer_position


func _first_resident_at(path: String) -> HumanoidCharacter:
	var root_node := _scene.get_node_or_null(path)
	if root_node == null:
		return null
	for child in root_node.get_children():
		if child is HumanoidCharacter:
			return child as HumanoidCharacter
	return null


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] if not nodes.is_empty() else null


func _first_squad_id(world_squad_controller: Node) -> String:
	if world_squad_controller == null or not world_squad_controller.has_method("serialize_state"):
		return ""
	var squads: Dictionary = world_squad_controller.call("serialize_state")
	for squad_id in squads.keys():
		return str(squad_id)
	return ""


func _fail(message: String) -> void:
	_failures.append(message)
