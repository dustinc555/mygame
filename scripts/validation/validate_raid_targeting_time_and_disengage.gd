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
	var faction_sim := _get_controller("faction_world_sim_controller")
	var encounter_controller := _get_controller("encounter_controller")
	var gecs := _get_controller("gecs_world_controller")
	var event_controller := _get_controller("world_event_choice_controller")
	var world_time := _scene.get_node_or_null("GameBootstrap/WorldTimeController")
	if settlement_controller == null or faction_controller == null or faction_sim == null or encounter_controller == null or gecs == null or event_controller == null or world_time == null:
		_fail("Controllers missing for raid targeting/time validation")
	else:
		_validate_clock_format(world_time)
		_validate_raid_limit(faction_sim, gecs)
		_validate_raid_target_selection(faction_sim, faction_controller)
		_validate_encounter_phase_flow(encounter_controller, gecs, event_controller)
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


func _validate_raid_limit(faction_sim: Node, gecs: Node) -> void:
	var squad_count_before := _world_sim_squad_count(gecs)
	var result := str(faction_sim.call("force_demand_tribute_raid"))
	if result.is_empty() or result.contains("not ready") or result.contains("No hostile target"):
		_fail("Forced world-sim raid failed: %s" % result)
		return
	var squad_count_after := _world_sim_squad_count(gecs)
	if squad_count_before == 0 and squad_count_after != 1:
		_fail("Forced world-sim raid should create one GECS squad")
	elif squad_count_before > 0 and squad_count_after != squad_count_before:
		_fail("Already-active world-sim raid count should stay stable")
	var blocked_result := str(faction_sim.call("force_demand_tribute_raid"))
	if not blocked_result.contains("already afield"):
		_fail("World-sim raids should be one-at-a-time")


func _validate_raid_target_selection(faction_sim: Node, faction_controller: Node) -> void:
	faction_controller.call("set_diplomatic_state", "Raiders", "Farmers", "war")
	var source := {"id": "raider_camp", "faction_id": "Raiders", "position": Vector3.ZERO}
	var farmer := {"id": "farmer_crossing", "faction_id": "Farmers", "position": Vector3(40.0, 0.0, 0.0)}
	var selected: Dictionary = faction_sim.call("_pick_target", faction_controller, "Raiders", source, [source, farmer])
	if str(selected.get("id", "")) != "farmer_crossing":
		_fail("Raider Camp should select Farmer Crossing in the base two-town setup")
	for blocked_state in ["alliance", "protectorate", "trade", "truce", "vassal", "tributary"]:
		faction_controller.call("set_diplomatic_state", "Raiders", "Farmers", blocked_state)
		selected = faction_sim.call("_pick_target", faction_controller, "Raiders", source, [source, farmer])
		if str(selected.get("id", "")) == "farmer_crossing":
			_fail("Raid target selection should block %s relations" % blocked_state)
	faction_controller.call("set_diplomatic_state", "Raiders", "Farmers", "war")
	faction_controller.call("set_diplomatic_state", "Raiders", "WeakTargets", "war")
	faction_controller.call("set_diplomatic_state", "Raiders", "StrongTargets", "war")
	var weak := {"id": "weak_raid_target", "faction_id": "WeakTargets", "position": Vector3(30.0, 0.0, 0.0)}
	var strong := {"id": "strong_raid_target", "faction_id": "StrongTargets", "position": Vector3(80.0, 0.0, 0.0)}
	var same_faction := {"id": "same_faction_target", "faction_id": "Raiders", "position": Vector3(10.0, 0.0, 0.0)}
	selected = faction_sim.call("_pick_target", faction_controller, "Raiders", source, [source, farmer, weak, strong, same_faction])
	if str(selected.get("id", "")) != "weak_raid_target":
		_fail("Raiders should prefer the nearby hostile target over same-faction or farther targets")
	faction_controller.call("set_diplomatic_state", "Raiders", "WeakTargets", "trade")
	selected = faction_sim.call("_pick_target", faction_controller, "Raiders", source, [source, farmer, weak, strong, same_faction])
	if str(selected.get("id", "")) == "weak_raid_target":
		_fail("Trade relations should remove the weak target from raid selection")
	faction_controller.call("set_diplomatic_state", "Raiders", "WeakTargets", "war")


func _validate_encounter_phase_flow(encounter_controller: Node, gecs: Node, event_controller: Node) -> void:
	var squad_id := _first_faction_squad_id(gecs)
	if squad_id.is_empty():
		_fail("Encounter phase validation could not find spawned squad")
		return
	var squad_state := _world_sim_squad_record(gecs, squad_id)
	squad_state["phase"] = "demand"
	squad_state["phase_timer"] = 0.0
	squad_state["decision"] = ""
	gecs.call("upsert_world_sim_squad", squad_state)
	encounter_controller.call("_tick", 0.5)
	squad_state = _world_sim_squad_record(gecs, squad_id)
	if str(squad_state.get("phase", "")) != "demand" or str(squad_state.get("decision", "")).is_empty():
		_fail("Raid should enter demand data phase")
	squad_state["decision"] = "refuse"
	squad_state["phase_timer"] = 0.1
	gecs.call("upsert_world_sim_squad", squad_state)
	encounter_controller.call("_tick", 0.5)
	squad_state = _world_sim_squad_record(gecs, squad_id)
	if str(squad_state.get("phase", "")) != "fight":
		_fail("Raid demand refusal should transition to fight data phase")
	squad_state["phase_timer"] = 0.1
	gecs.call("upsert_world_sim_squad", squad_state)
	encounter_controller.call("_tick", 0.5)
	squad_state = _world_sim_squad_record(gecs, squad_id)
	if str(squad_state.get("phase", "")) != "aftermath":
		_fail("Raid fight should transition to aftermath data phase")
	if bool(event_controller.call("is_prompt_visible")):
		_fail("World-sim encounter should not show old modal raid prompt")


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


func _world_sim_squad_count(gecs: Node) -> int:
	if gecs == null or not gecs.has_method("get_world_sim_squads"):
		return 0
	return int(gecs.call("get_world_sim_squads").size())


func _first_faction_squad_id(gecs: Node) -> String:
	if gecs == null or not gecs.has_method("get_world_sim_squads"):
		return ""
	for record in gecs.call("get_world_sim_squads"):
		if record is Dictionary and str(record.get("owner_kind", "")) == "faction":
			return str(record.get("squad_id", ""))
	return ""


func _world_sim_squad_record(gecs: Node, squad_id: String) -> Dictionary:
	if gecs == null or not gecs.has_method("get_world_sim_squads"):
		return {}
	for record in gecs.call("get_world_sim_squads"):
		if record is Dictionary and str(record.get("squad_id", "")) == squad_id:
			return (record as Dictionary).duplicate(true)
	return {}


func _fail(message: String) -> void:
	_failures.append(message)
