extends SceneTree

const MAX_WAIT_FRAMES := 420
const SCENARIOS := [
	{"label": "10v10", "path": "res://scenes/test_levels/combat_beat_10v10_test.tscn", "actors": 20},
	{"label": "20v20", "path": "res://scenes/test_levels/combat_beat_20v20_test.tscn", "actors": 40},
	{"label": "30v30", "path": "res://scenes/test_levels/combat_beat_30v30_test.tscn", "actors": 60},
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	for scenario in SCENARIOS:
		await _validate_scenario(scenario)
	_finish()


func _validate_scenario(scenario: Dictionary) -> void:
	var scene_path := str(scenario.get("path", ""))
	var label := str(scenario.get("label", scene_path))
	var expected_actors := int(scenario.get("actors", 0))
	var scene_resource := load(scene_path) as PackedScene
	_expect(scene_resource != null, "%s scene loads" % label)
	if scene_resource == null:
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	await process_frame
	var state := await _wait_for_playback(scene, label)
	var battle_result: Dictionary = state.get("battle_result", {}) if state.get("battle_result", {}) is Dictionary else {}
	var projection_metrics: Dictionary = state.get("projection_metrics", {}) if state.get("projection_metrics", {}) is Dictionary else {}
	_expect(not battle_result.is_empty(), "%s resolves a BattleSim result" % label)
	_expect(bool(state.get("playback_active", false)), "%s activates projection playback" % label)
	_expect(not bool(state.get("combat_schedule_loop_enabled", true)), "%s disables projection replay loop" % label)
	_expect(not bool(projection_metrics.get("combat_projection_loop_enabled", true)), "%s metrics report replay loop disabled" % label)
	_expect(int(projection_metrics.get("projected_actor_count", 0)) == expected_actors, "%s projects all expected actors" % label)
	_expect(int(projection_metrics.get("combat_projection_scheduled_event_count", 0)) > 0, "%s has scheduled projection events" % label)
	_validate_terminal_result(label, battle_result)
	_validate_spatial_groups(label, battle_result)
	_validate_player_side_controllable(scene, label, int(expected_actors / 2))
	var terminal_state := await _wait_for_terminal_playback(scene, label, _member_casualty_count(battle_result) > 0)
	var terminal_metrics: Dictionary = terminal_state.get("projection_metrics", {}) if terminal_state.get("projection_metrics", {}) is Dictionary else {}
	_expect(bool(terminal_metrics.get("combat_projection_playback_complete", false)), "%s playback runs once to completion" % label)
	if _member_casualty_count(battle_result) > 0:
		_expect(int(terminal_metrics.get("combat_projection_active_ragdoll_downed_count", 0)) > 0, "%s activates ragdoll-backed downed bodies" % label)
	scene.queue_free()
	await process_frame


func _wait_for_playback(scene: Node, label: String) -> Dictionary:
	for _frame in range(MAX_WAIT_FRAMES):
		await process_frame
		if not scene.has_method("get_review_state"):
			continue
		var state = scene.call("get_review_state")
		if not (state is Dictionary):
			continue
		var battle_result: Dictionary = (state as Dictionary).get("battle_result", {}) if (state as Dictionary).get("battle_result", {}) is Dictionary else {}
		if bool((state as Dictionary).get("playback_active", false)) and not battle_result.is_empty():
			return (state as Dictionary).duplicate(true)
	_failures.append("%s starts projection playback within wait budget" % label)
	return {}


func _wait_for_terminal_playback(scene: Node, label: String, require_ragdoll: bool) -> Dictionary:
	var latest: Dictionary = {}
	for _frame in range(MAX_WAIT_FRAMES):
		await process_frame
		if not scene.has_method("get_review_state"):
			continue
		var state = scene.call("get_review_state")
		if not (state is Dictionary):
			continue
		latest = (state as Dictionary).duplicate(true)
		var projection_metrics: Dictionary = latest.get("projection_metrics", {}) if latest.get("projection_metrics", {}) is Dictionary else {}
		if not bool(projection_metrics.get("combat_projection_playback_complete", false)):
			continue
		if require_ragdoll and int(projection_metrics.get("combat_projection_active_ragdoll_downed_count", 0)) <= 0:
			continue
		return latest
	_failures.append("%s reaches terminal no-loop playback within wait budget" % label)
	return latest


func _validate_terminal_result(label: String, battle_result: Dictionary) -> void:
	_expect(str(battle_result.get("resolution_mode", "")) == "to_completion", "%s resolves to terminal completion" % label)
	var terminal_reason := str(battle_result.get("terminal_reason", ""))
	_expect(terminal_reason == "all_down" or terminal_reason == "flee", "%s terminal reason is K.O. or flee" % label)
	if terminal_reason == "all_down":
		_expect(_member_casualty_count(battle_result) > 0, "%s all-down terminal result has casualties" % label)
	else:
		_expect(not str(battle_result.get("fleeing_squad_id", "")).strip_edges().is_empty(), "%s flee terminal result records fleeing squad" % label)


func _validate_spatial_groups(label: String, battle_result: Dictionary) -> void:
	var grouping: Dictionary = battle_result.get("engagement_grouping", {}) if battle_result.get("engagement_grouping", {}) is Dictionary else {}
	_expect(str(grouping.get("strategy", "")) == "spatial_nearest_frontline", "%s uses spatial nearest engagement grouping" % label)
	var groups: Array = battle_result.get("engagement_groups", []) if battle_result.get("engagement_groups", []) is Array else []
	var paired_count := 0
	for group in groups:
		if not (group is Dictionary):
			continue
		var side_a: Array = (group as Dictionary).get("side_a_member_ids", []) if (group as Dictionary).get("side_a_member_ids", []) is Array else []
		var side_b: Array = (group as Dictionary).get("side_b_member_ids", []) if (group as Dictionary).get("side_b_member_ids", []) is Array else []
		if side_a.size() == 1 and side_b.size() == 1:
			paired_count += 1
	_expect(paired_count >= int(grouping.get("side_a_participant_count", 0)) * 0.8, "%s forms mostly 1v1 spatial pockets" % label)


func _validate_player_side_controllable(scene: Node, label: String, expected_player_count: int) -> void:
	var gecs := scene.get_node_or_null("GameBootstrap/GecsWorldController")
	if gecs == null or not gecs.has_method("get_population_records_core"):
		_failures.append("%s GECS population records are inspectable" % label)
		return
	var records = gecs.call("get_population_records_core")
	if not (records is Dictionary):
		_failures.append("%s GECS population records are a dictionary" % label)
		return
	var controllable_count := 0
	for actor_id_value in (records as Dictionary).keys():
		var actor_id := str(actor_id_value)
		if not actor_id.contains(".side_a."):
			continue
		var record: Dictionary = (records as Dictionary).get(actor_id, {}) if (records as Dictionary).get(actor_id, {}) is Dictionary else {}
		if bool(record.get("player_controllable", false)) and bool(record.get("player_party_member", false)) and str(record.get("party_id", "")) == "player_party":
			controllable_count += 1
	_expect(controllable_count == expected_player_count, "%s marks side A as controllable player party" % label)


func _member_casualty_count(battle_result: Dictionary) -> int:
	var count := 0
	var casualties = battle_result.get("member_casualties", {})
	if not (casualties is Dictionary):
		return count
	for squad_id in (casualties as Dictionary).keys():
		var entries = (casualties as Dictionary).get(squad_id, [])
		if entries is Array:
			count += (entries as Array).size()
	return count


func _finish() -> void:
	if _failures.is_empty():
		print("COMBAT_BEAT_EXTRA_PROJECTION_SCENES_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
