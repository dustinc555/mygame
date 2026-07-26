extends SceneTree

const TWO_TOWNS_SCENE_PATH := "res://scenes/test_levels/two_towns_road_test.tscn"
const AI_UTILITY_ADAPTER_PATH := "res://features/ai/bridge/ai_utility_adapter.gd"
const COMBAT_COORDINATOR_PATH := "res://features/combat/bridge/combat_coordinator.gd"
const SKIN_TEXTURE_BUILDER_PATH := "res://features/actors/projection/appearance/skin_texture_builder.gd"

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = _instantiate_scene()
	if _scene == null:
		_fail("Two towns scene missing for staff realization validation")
		_finish()
		return
	var farmer_town := _scene.get_node_or_null("Settlements/FarmerCrossing")
	if farmer_town != null:
		farmer_town.set("actor_realization_policy", "important_plus_near")
	farmer_town = null
	root.add_child(_scene)
	await _wait_frames(180)
	_validate_staff_fills_under_non_full_policy()
	_validate_realization_lod_contract()
	_validate_exact_transform_restore()
	_validate_need_bar_smoothing()
	await _cleanup_scene()
	_finish()


func _instantiate_scene() -> Node:
	var scene_resource := load(TWO_TOWNS_SCENE_PATH) as PackedScene
	return scene_resource.instantiate() if scene_resource != null else null


func _finish() -> void:
	if _failures.is_empty():
		print("POPULATION_STAFF_REALIZATION_POLICY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("POPULATION_STAFF_REALIZATION_POLICY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_staff_fills_under_non_full_policy() -> void:
	var settlement_controller := _get_controller("settlement_controller")
	if settlement_controller == null or not settlement_controller.has_method("get_settlement_state"):
		_fail("SettlementController missing for staff realization validation")
		return
	var state: Dictionary = settlement_controller.call("get_settlement_state", "farmer_crossing")
	var required_staff := int(state.get("population_required_staff", 0))
	var assigned_staff := int(state.get("population_assigned", 0))
	var vacancies: Dictionary = state.get("staff_vacancies", {})
	var staff_slots: Dictionary = state.get("staff_slots", {})
	if required_staff <= 0:
		_fail("Farmer Crossing should expose required staff slots")
	if assigned_staff < required_staff:
		_fail("Non-full realization policy should still realize enough residents to fill staff; required=%d assigned=%d" % [required_staff, assigned_staff])
	if not vacancies.is_empty():
		_fail("Staff vacancies should not deadlock under important_plus_near policy; vacancies=%d" % vacancies.size())
	for slot_value in staff_slots.values():
		if not ((slot_value as Dictionary).get("world_position", null) is Vector3):
			_fail("Staff slots need stable world positions for per-slot LOD")
			break
	var population := _get_controller("population_controller")
	if population == null or not population.has_method("get_records_for_settlement"):
		_fail("PopulationController missing for staff record validation")
		return
	var staff_record_count := 0
	for record in population.call("get_records_for_settlement", "farmer_crossing"):
		if not (record is Dictionary):
			continue
		if ["barkeeper", "waiter", "guard", "barber", "warden", "ruler"].has(str(record.get("role_id", ""))):
			staff_record_count += 1
	if staff_record_count < required_staff:
		_fail("Claimed staff should update generated population records to staff roles; records=%d required=%d" % [staff_record_count, required_staff])
	_validate_new_staff_assignment_clears_movement(population)


func _validate_new_staff_assignment_clears_movement(population: Node) -> void:
	var candidate_id := ""
	var assigned_slot_id := ""
	for record_value in population.call("get_records_for_settlement", "farmer_crossing"):
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		if str(record.get("role_id", "resident")) == "resident" and str(record.get("assigned_slot_id", "")).is_empty():
			var actor_id := str(record.get("actor_id", ""))
			if not assigned_slot_id.is_empty() or candidate_id.is_empty() or actor_id < candidate_id:
				candidate_id = actor_id
				assigned_slot_id = ""
		elif candidate_id.is_empty() and not str(record.get("assigned_slot_id", "")).is_empty():
			candidate_id = str(record.get("actor_id", ""))
			assigned_slot_id = str(record.get("assigned_slot_id", ""))
	if candidate_id.is_empty():
		_fail("Staff assignment validation needs one population record")
		return
	if not assigned_slot_id.is_empty():
		population.call("release_slot_assignment", "farmer_crossing", assigned_slot_id)
	population.call("update_actor_record", candidate_id, {
		"movement_state": {
			"has_move_target": true,
			"move_target": Vector3(999.0, 0.0, 999.0),
			"issued_by_player": true,
		},
	})
	var claimed: Dictionary = population.call("claim_unassigned_record_for_slot", "farmer_crossing", "validation.staff.slot", "guard")
	if str(claimed.get("actor_id", "")) != candidate_id or not (claimed.get("movement_state", {}) as Dictionary).is_empty() or bool(claimed.get("staff_assignment_realized_once", true)):
		_fail("New staff assignment must clear unrelated resident movement intent")


func _validate_realization_lod_contract() -> void:
	var realization := _get_controller("population_realization_controller")
	var party_manager := _get_controller("party_manager")
	if realization == null or party_manager == null:
		_fail("LOD contract validation needs realization and party controllers")
		return
	var members = party_manager.get("party_members")
	if not (members is Array) or members.is_empty() or not (members[0] is Node3D):
		_fail("LOD contract validation needs a living party member")
		return
	var member := members[0] as Node3D
	var original_position := member.global_position
	var primary: Vector3 = realization.call("get_primary_realization_anchor")
	member.global_position = primary + Vector3(500.0, 0.0, 0.0)
	var anchors: Array = realization.call("get_realization_anchor_positions")
	if anchors.size() != 1:
		_fail("Population realization should use only the camera as its detail anchor")
	var visible_radius := float(realization.call("get_visible_radius"))
	var entry_radius := float(realization.call("get_entry_radius"))
	var remote_party_position := member.global_position
	var remote_party_record := {
		"actor_id": "validation.secondary",
		"last_world_position": remote_party_position,
		"last_world_position_initialized": true,
		"realization_state": "ledger",
	}
	if bool(realization.call("should_realize_actor", null, remote_party_record, "near_player")):
		_fail("A remote party member must not keep nearby town projections realized")
	var preload_position := primary + Vector3((visible_radius + entry_radius) * 0.5, 0.0, 0.0)
	var preload_record := remote_party_record.duplicate()
	preload_record["actor_id"] = "validation.preload"
	preload_record["last_world_position"] = preload_position
	if bool(realization.call("is_position_within_realization_range", preload_position)):
		_fail("Preload test position should remain outside the visible LOD radius")
	if not bool(realization.call("should_realize_actor", null, preload_record, "near_player")):
		_fail("Population realization should prepare initialized records before they enter visible LOD")
	var uninitialized_record := remote_party_record.duplicate()
	uninitialized_record["actor_id"] = "validation.uninitialized"
	uninitialized_record["last_world_position_initialized"] = false
	if bool(realization.call("should_realize_actor", null, uninitialized_record, "near_player")):
		_fail("Uninitialized ledger positions must not realize at an accidental world position")
	if str(realization.call("_staff_retention_key", "town_a", "guard.0")) == str(realization.call("_staff_retention_key", "town_b", "guard.0")):
		_fail("Staff retention keys must include settlement identity")
	member.global_position = original_position


func _validate_exact_transform_restore() -> void:
	var realizer_script := load("res://features/settlements/bridge/population_character_realizer.gd") as GDScript
	var realizer: Node = realizer_script.new()
	var actor := Node3D.new()
	_scene.add_child(realizer)
	_scene.add_child(actor)
	var expected := Transform3D(Basis.from_euler(Vector3(0.11, 1.37, -0.06)), Vector3(18.25, 4.75, -31.5))
	realizer.call("restore_record_transform", actor, {
		"last_world_transform": expected,
		"last_world_transform_initialized": true,
	})
	if not actor.global_transform.is_equal_approx(expected):
		_fail("Character realization should restore exact world position, height, and facing")


func _validate_need_bar_smoothing() -> void:
	var details := _get_controller("humanoid_details_controller")
	if details == null or not details.has_method("_smooth_need_ratio"):
		_fail("Humanoid details controller should expose need-bar presentation smoothing")
		return
	details.set("_ui_delta", 1.0 / 60.0)
	var first_step := float(details.call("_smooth_need_ratio", 1.0, 0.98, 0, 0))
	if first_step <= 0.98 or first_step >= 1.0:
		_fail("Need bars should move toward a new value instead of jumping in one frame")
	var at_30_fps := _converged_need_ratio(details, 30)
	var at_60_fps := _converged_need_ratio(details, 60)
	if absf(at_30_fps - at_60_fps) > 0.001:
		_fail("Need-bar smoothing should look the same across frame rates")
	details.set("_ui_delta", 1.0 / 60.0)
	var stage_snap := float(details.call("_smooth_need_ratio", 0.02, 1.0, 0, 1))
	if not is_equal_approx(stage_snap, 1.0):
		_fail("Need bars should snap when the hunger or fatigue stage changes")


func _converged_need_ratio(details: Node, fps: int) -> float:
	details.set("_ui_delta", 1.0 / float(fps))
	var displayed := 1.0
	for _frame in range(fps):
		displayed = float(details.call("_smooth_need_ratio", displayed, 0.5, 0, 0))
	return displayed


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] as Node if not nodes.is_empty() else null


func _fail(message: String) -> void:
	_failures.append(message)


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _cleanup_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
	_scene = null
	await process_frame
	await physics_frame
	_cleanup_runtime_state()
	await _wait_frames(20)


func _cleanup_runtime_state() -> void:
	var combat_coordinator = load(COMBAT_COORDINATOR_PATH)
	if combat_coordinator != null and combat_coordinator.has_method("reset_all_state"):
		combat_coordinator.reset_all_state()
	var ai_utility_adapter = load(AI_UTILITY_ADAPTER_PATH)
	if ai_utility_adapter != null and ai_utility_adapter.has_method("clear_runtime_caches"):
		ai_utility_adapter.clear_runtime_caches()
	var skin_texture_builder = load(SKIN_TEXTURE_BUILDER_PATH)
	if skin_texture_builder != null and skin_texture_builder.has_method("clear_runtime_caches"):
		skin_texture_builder.clear_runtime_caches()
