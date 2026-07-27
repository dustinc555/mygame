extends SceneTree

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
	call_deferred("_run")


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
	var stayed_active := true
	for _cycle in range(8):
		realization.set("_mandatory_work_pending", 0)
		realization.call("_resync_settlement_assignments", anchors)
		realization.call("_update_loading_request")
		stayed_active = stayed_active and loading.requested
	if stayed_active:
		push_error("Nearby vacant staff slots kept realization loading active across every budget cycle")
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
	stayed_active = true
	for _cycle in range(8):
		realization.set("_mandatory_work_pending", 0)
		realization.call("_resync_settlement_assignments", anchors)
		realization.call("_update_loading_request")
		stayed_active = stayed_active and loading.requested
	if not stayed_active:
		push_error("Failed visible occupied staff realization released loading without bounded retries")
		quit(1)
		return
	var attempts_before_cap_check := settlement_controller.realization_attempts
	realization.set("_failed_assignment_realization_attempts", {"assignment:validation_settlement:employment:failed_occupied": 20})
	realization.set("_mandatory_work_pending", 0)
	realization.call("_resync_settlement_assignments", anchors)
	realization.call("_update_loading_request")
	if settlement_controller.realization_attempts != attempts_before_cap_check or loading.requested:
		push_error("Exhausted visible staff realization must stop retrying and release loading")
		quit(1)
		return
	print("VACANT_STAFF_REALIZATION_LOADING_OK")
	quit(0)
