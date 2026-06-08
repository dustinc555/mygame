extends SceneTree

const TEST_SCENE_PATH := "res://scenes/test_levels/combat_beat_1v1_test.tscn"
const MAX_WAIT_FRAMES := 360

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var scene_resource := load(TEST_SCENE_PATH) as PackedScene
	_expect(scene_resource != null, "CombatBeat 1v1 test scene loads")
	if scene_resource == null:
		_finish()
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	await process_frame
	_validate_static_scene_contract(scene)
	await _wait_for_review_result(scene)
	_validate_review_state(scene)
	_finish()


func _validate_static_scene_contract(scene: Node) -> void:
	_expect(scene.get_node_or_null("GameBootstrap") != null, "CombatBeat 1v1 scene uses actual GameBootstrap")
	_expect(scene.get_node_or_null("WorldLoader") != null, "CombatBeat 1v1 scene has a world loader")
	_expect(scene.get_node_or_null("WorldMapSquadCommandPanel") == null, "CombatBeat 1v1 scene does not add world map squad command panel")
	var world_loader := scene.get_node_or_null("WorldLoader")
	var world_definition = world_loader.get("world_definition") if world_loader != null else null
	_expect(world_definition is Resource, "CombatBeat 1v1 scene uses its own world definition")
	if world_definition is Resource:
		_expect(str(world_definition.get("world_id")) == "combat_beat_1v1", "CombatBeat 1v1 world definition is standalone")
		var templates = world_definition.get("squad_templates")
		_expect(templates is Array and (templates as Array).size() == 2, "CombatBeat 1v1 world defines two squads")


func _wait_for_review_result(scene: Node) -> void:
	for _frame in range(MAX_WAIT_FRAMES):
		await process_frame
		if scene.has_method("get_review_state"):
			var state = scene.call("get_review_state")
			if state is Dictionary:
				var battle_result: Dictionary = (state as Dictionary).get("battle_result", {}) if (state as Dictionary).get("battle_result", {}) is Dictionary else {}
				if not battle_result.is_empty():
					return
	_failures.append("CombatBeat 1v1 scene resolves a review encounter within wait budget")


func _validate_review_state(scene: Node) -> void:
	_expect(scene.has_method("get_review_state"), "CombatBeat 1v1 scene exposes review state")
	if not scene.has_method("get_review_state"):
		return
	var state = scene.call("get_review_state")
	_expect(state is Dictionary, "CombatBeat 1v1 review state is a dictionary")
	if not (state is Dictionary):
		return
	var review_state: Dictionary = state
	_expect(bool(review_state.get("ready", false)), "CombatBeat 1v1 review scene is ready")
	var battle_result: Dictionary = review_state.get("battle_result", {}) if review_state.get("battle_result", {}) is Dictionary else {}
	_expect(not battle_result.is_empty(), "CombatBeat 1v1 review has a BattleSim result")
	var beats: Array = battle_result.get("beats", []) if battle_result.get("beats", []) is Array else []
	var groups: Array = battle_result.get("engagement_groups", []) if battle_result.get("engagement_groups", []) is Array else []
	var slots: Dictionary = battle_result.get("combat_slots", {}) if battle_result.get("combat_slots", {}) is Dictionary else {}
	var schedule: Dictionary = battle_result.get("combat_schedule", {}) if battle_result.get("combat_schedule", {}) is Dictionary else {}
	var continuity: Dictionary = battle_result.get("combat_continuity", {}) if battle_result.get("combat_continuity", {}) is Dictionary else {}
	_expect(beats.size() > 0, "CombatBeat 1v1 result emits CombatBeat records")
	_expect(str(battle_result.get("resolution_mode", "")) == "to_completion_1v1", "CombatBeat 1v1 uses completion resolution mode")
	_expect(beats.size() > 3, "CombatBeat 1v1 fight is not limited to the old three-beat default")
	_expect(_member_casualty_count(battle_result) >= 1, "CombatBeat 1v1 fight runs until a member is downed")
	_expect(_has_downed_beat(beats), "CombatBeat 1v1 emits a downed final beat")
	_expect(groups.size() == 1, "CombatBeat 1v1 result has one engagement group")
	_expect(slots.size() == 2, "CombatBeat 1v1 result has two combat slots")
	_expect(int(schedule.get("scheduled_event_count", 0)) > 0, "CombatBeat 1v1 result has playback schedule events")
	_expect(str(continuity.get("projection_state", "")) == "aftermath", "CombatBeat 1v1 result has aftermath continuity")
	var projection_metrics: Dictionary = review_state.get("projection_metrics", {}) if review_state.get("projection_metrics", {}) is Dictionary else {}
	_expect(int(projection_metrics.get("projected_actor_count", 0)) == 2, "CombatBeat 1v1 scene projects two fighters")
	var encounter_record := _resolved_encounter_record(scene, str(review_state.get("encounter_id", "")))
	_validate_start_request(encounter_record)
	_validate_no_live_truth_refs(battle_result, "battle_result")
	_validate_no_live_truth_refs(encounter_record, "encounter_record")


func _resolved_encounter_record(scene: Node, encounter_id: String) -> Dictionary:
	var combat := scene.get_node_or_null("GameBootstrap/WorldMapCombatSimController")
	if combat == null or not combat.has_method("get_world_encounter_state"):
		return {}
	var state = combat.call("get_world_encounter_state")
	if not (state is Dictionary):
		return {}
	var encounters = (state as Dictionary).get("encounters_by_id", {})
	if not (encounters is Dictionary):
		return {}
	var encounter = (encounters as Dictionary).get(encounter_id, {})
	return encounter.duplicate(true) if encounter is Dictionary else {}


func _validate_start_request(encounter_record: Dictionary) -> void:
	_expect(not encounter_record.is_empty(), "CombatBeat 1v1 resolved encounter record is inspectable")
	var start_request: Dictionary = encounter_record.get("start_request", {}) if encounter_record.get("start_request", {}) is Dictionary else {}
	_expect(not start_request.is_empty(), "CombatBeat 1v1 encounter stores the shared start request")
	_expect(str(encounter_record.get("initial_intent", "")) == "debug", "CombatBeat 1v1 encounter maps initial_intent")
	_expect(str(start_request.get("initial_intent", "")) == "debug", "CombatBeat 1v1 start request uses debug intent")
	_expect(str(start_request.get("source_type", "")) == "debug_1v1", "CombatBeat 1v1 start request records source_type")
	var sides: Array = start_request.get("sides", []) if start_request.get("sides", []) is Array else []
	_expect(sides.size() == 2, "CombatBeat 1v1 start request has two sides")
	for side in sides:
		if side is Dictionary:
			_expect(not str((side as Dictionary).get("squad_id", "")).strip_edges().is_empty(), "CombatBeat 1v1 side has squad_id")
			var members: Array = (side as Dictionary).get("member_refs", []) if (side as Dictionary).get("member_refs", []) is Array else []
			_expect(not members.is_empty(), "CombatBeat 1v1 side has stable member refs")


func _member_casualty_count(battle_result: Dictionary) -> int:
	var count := 0
	var casualties = battle_result.get("member_casualties", {})
	if not (casualties is Dictionary):
		return count
	for squad_id in (casualties as Dictionary).keys():
		var entries = casualties[squad_id]
		if entries is Array:
			count += (entries as Array).size()
	return count


func _has_downed_beat(beats: Array) -> bool:
	for beat in beats:
		if beat is Dictionary and str((beat as Dictionary).get("result", "")) == "downed":
			return true
	return false


func _validate_no_live_truth_refs(value, path: String) -> void:
	if value is Node:
		_failures.append("CombatBeat 1v1 stores live Node in %s" % path)
		return
	if value is NodePath:
		_failures.append("CombatBeat 1v1 stores NodePath in %s" % path)
		return
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			_validate_no_live_truth_refs((value as Dictionary).get(key), "%s.%s" % [path, str(key)])
	elif value is Array:
		for index in range((value as Array).size()):
			_validate_no_live_truth_refs((value as Array)[index], "%s[%d]" % [path, index])


func _finish() -> void:
	if _failures.is_empty():
		print("COMBAT_BEAT_1V1_TEST_LEVEL_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
