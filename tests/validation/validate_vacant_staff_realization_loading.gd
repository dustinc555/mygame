extends "res://tests/validation/test_case.gd"

class FakeSettlement:
	extends Node

	func get_settlement_id() -> String:
		return "validation_settlement"


class FakeSettlementController:
	extends Node

	var slots: Array[Dictionary] = []
	var realization_attempts := 0

	func get_assignment_slots_for_realization(_settlement_id: String) -> Array[Dictionary]:
		return slots

	func is_assignment_slot_realized(_settlement_id: String, _assignment_domain: String, _slot_id: String) -> bool:
		return false

	func realize_assignment_slot(_settlement_id: String, _assignment_domain: String, _slot_id: String) -> bool:
		realization_attempts += 1
		return false

	func derealize_assignment_slot(_settlement_id: String, _assignment_domain: String, _slot_id: String) -> void:
		pass


class FakeLoadingOverlay:
	extends Node

	var requested := false

	func set_loading_request(_owner_id: String, active: bool) -> void:
		requested = active

	func is_loading_gate_active(_owner_id := "") -> bool:
		return requested


func _initialize() -> void:
	if OS.get_environment("MYGAME_VACANCY_RETRY_CHILD") == "1":
		call_deferred("_run")
	else:
		call_deferred("_assert_terminal_diagnostic")


func _assert_terminal_diagnostic() -> void:
	# The native logger cannot be removed, and disabling error printing also
	# disables custom Logger callbacks. Keep the exact production error in a
	# child log, asserted by this test's supervisor using the strict root scanner.
	# OS.execute (not execute_with_pipe) preserves root process-group cancellation.
	var evidence := OS.get_user_data_dir().path_join("vacancy_retry_%d" % OS.get_process_id())
	var output: Array = []
	var code := OS.execute("python3", [
		ProjectSettings.globalize_path("res://tests/validation/test_vacant_staff_diagnostic.py"),
		"--child", OS.get_executable_path(), ProjectSettings.globalize_path("res://"),
		evidence, str(PopulationRealizationController.MAX_ASSIGNMENT_REALIZATION_FAILURES),
	], output, true)
	for text in output:
		print(text)
	if code == 0:
		print("VACANT_STAFF_REALIZATION_LOADING_OK")
	else:
		push_error("Vacancy retry terminal expectation failed; raw child evidence: %s" % evidence)
	quit(0 if code == 0 else 1)


func _trace_retry(realization: Node, settlement_controller: Node, loading: Node, key: String) -> void:
	var failures: Dictionary = realization.get("_failed_assignment_realization_attempts")
	print("VACANCY_RETRY_STATE attempts=%d failures=%d loading=%s" % [
		settlement_controller.realization_attempts, int(failures.get(key, 0)),
		str(loading.requested),
	])


func _run() -> void:
	var scene_root := Node.new()
	root.add_child(scene_root)
	var settlement := FakeSettlement.new()
	settlement.add_to_group("settlement_town")
	scene_root.add_child(settlement)
	var settlement_controller := FakeSettlementController.new()
	scene_root.add_child(settlement_controller)
	for index in range(5):
		settlement_controller.slots.append({
			"slot_id": "vacant_%d" % index,
			"settlement_id": "validation_settlement",
			"assignment_domain": "employment",
			"filled": false,
			"occupant_actor_id": "",
			"world_position": Vector3.ZERO,
		})
	var loading := FakeLoadingOverlay.new()
	scene_root.add_child(loading)
	var context := BootstrapContext.new(scene_root)
	context.register(&"settlement", settlement_controller)
	context.register(&"navigation_loading_overlay", loading)
	var realization_script := load("res://features/world_sim/bridge/population_realization_controller.gd") as GDScript
	var realization: Node = realization_script.new()
	scene_root.add_child(realization)
	realization.initialize(context)
	realization.set_process(false)
	var anchors: Array[Vector3] = [Vector3.ZERO]
	var stayed_inactive := true
	for _cycle in range(8):
		realization.set("_mandatory_work_pending", 0)
		realization.call("_resync_settlement_assignments", anchors)
		realization.call("_update_loading_request")
		stayed_inactive = stayed_inactive and not loading.requested
	if not stayed_inactive or settlement_controller.realization_attempts != 0:
		push_error("Every vacant staff cycle must remain inactive without realization attempts")
		quit(1)
		return
	settlement_controller.slots = [{
		"slot_id": "occupied_home",
		"settlement_id": "validation_settlement",
		"assignment_domain": "residence",
		"filled": true,
		"occupant_actor_id": "validation.resident",
		"world_position": Vector3.ZERO,
	}]
	settlement_controller.realization_attempts = 0
	realization.set("_mandatory_work_pending", 0)
	realization.call("_resync_settlement_assignments", anchors)
	if settlement_controller.realization_attempts != 1:
		push_error("Occupied residence assignments must use the generic assignment realization path")
		quit(1)
		return
	settlement_controller.slots = [{
		"slot_id": "failed_occupied",
		"settlement_id": "validation_settlement",
		"assignment_domain": "employment",
		"filled": true,
		"occupant_actor_id": "validation.worker",
		"world_position": Vector3.ZERO,
	}]
	settlement_controller.realization_attempts = 0
	var limit: int = realization.MAX_ASSIGNMENT_REALIZATION_FAILURES
	var failure_key: String = realization.call("_assignment_retention_key", "validation_settlement", "employment", "failed_occupied")
	var failures: Dictionary = realization.get("_failed_assignment_realization_attempts")
	if failures.has(failure_key) or loading.requested:
		push_error("The occupied failure fixture must begin with no retries and an inactive loading owner")
		quit(1)
		return
	_trace_retry(realization, settlement_controller, loading, failure_key)
	for attempt in range(1, limit + 1):
		realization.set("_mandatory_work_pending", 0)
		realization.call("_resync_settlement_assignments", anchors)
		realization.call("_update_loading_request")
		_trace_retry(realization, settlement_controller, loading, failure_key)
		if settlement_controller.realization_attempts != attempt or loading.requested != (attempt < limit):
			push_error("Retry %d/%d must perform exactly one attempt and hold loading only before exhaustion" % [attempt, limit])
			quit(1)
			return
	for _cycle in range(3):
		realization.set("_mandatory_work_pending", 0)
		realization.call("_resync_settlement_assignments", anchors)
		realization.call("_update_loading_request")
		_trace_retry(realization, settlement_controller, loading, failure_key)
		if settlement_controller.realization_attempts != limit or loading.requested:
			push_error("Exhaustion must stop additional attempts and release the loading owner")
			quit(1)
			return
	scene_root.free()
	print("VACANT_STAFF_REALIZATION_LOADING_OK")
	quit(0)
