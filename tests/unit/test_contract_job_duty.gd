extends GutTest

class DutyJobs extends Node:
	var granted := false
	func can_execute_assignment_duty(_actor: Node) -> bool: return granted

class LawInteraction extends InteractionCapability:
	func has_direct_law_move() -> bool: return true

class Worker extends HumanoidCharacter:
	var order_type := InteractionCapability.ORDER_TYPE_NONE
	var fighting := false
	var seated := false
	var law_interaction: InteractionCapability
	var stops := 0
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func get_interaction() -> InteractionCapability: return law_interaction
	func is_sitting() -> bool: return seated
	func get_current_order_type() -> int: return order_type
	func is_in_combat() -> bool: return fighting
	func stop_movement() -> void:
		stops += 1
		order_type = InteractionCapability.ORDER_TYPE_NONE

# Runtime-only double; deliberately do not execute venue tooling in the editor.
@warning_ignore("missing_tool")
class ServiceArea extends BarServiceArea:
	var point: BarServicePoint
	var released_seats := 0
	func _ready() -> void: pass
	func get_waiter_service_points() -> Array: return [point]
	func claim_waiting_customer_seat(_worker: HumanoidCharacter): return null
	func release_waiter_customer_service(_seat) -> void: released_seats += 1

class Provider extends JobProvider:
	var area: ServiceArea
	var started := 0
	func _ready() -> void: pass
	func _resolve_bar_service_area() -> BarServiceArea: return area
	func _mark_contract_started(_contract_id: String) -> void: started += 1
	func _sync_gecs_state() -> void: pass

func _fixture() -> Dictionary:
	var host := Node3D.new()
	add_child_autofree(host)
	var worker := Worker.new()
	worker.stable_id = "contract.worker"
	var area := ServiceArea.new()
	var point := BarServicePoint.new()
	point.point_role = "waiter"
	var provider := Provider.new()
	var duty := DutyJobs.new()
	var definition := JobDefinition.new()
	definition.algorithm_id = "server_shift"
	definition.pay_interval_seconds = 1.0
	definition.pay_per_interval = 1
	provider.jobs.append(definition)
	provider.area = area
	provider._job_system_controller = duty
	area.point = point
	for node in [worker, area, point, provider, duty]: host.add_child(node)
	provider._initialize_slots()
	return {"worker": worker, "provider": provider, "duty": duty, "area": area, "point": point,
		"contract": {"contract_id": "contract.waiter", "job_index": 0, "display_name": "Waiter"}}

func test_denied_contract_start_and_candidate_do_not_mutate_worker_or_records() -> void:
	var f := _fixture()
	assert_false(f.provider.get_contract_work_status(f.worker, f.contract).actionable)
	assert_null(f.provider.start_contract_shift(f.worker, f.contract))
	assert_false(f.provider._claim_worker_slot(f.worker, 0).allowed)
	assert_false(f.provider._assign_worker_to_open_slot(f.worker, 0).allowed)
	assert_null(f.provider.create_assigned_work_ai_job(f.worker))
	assert_true(f.provider._worker_records.is_empty())
	assert_true(f.provider._find_worker_slot(f.worker).is_empty())
	assert_null(f.worker.get_active_job_provider())
	assert_eq(f.provider.started, 0)
	assert_eq(f.worker.stops, 0)

func test_live_npc_fails_closed_without_jobs_authority() -> void:
	var f := _fixture()
	f.provider._job_system_controller = null
	assert_null(f.provider.start_contract_shift(f.worker, f.contract))
	assert_true(f.provider._worker_records.is_empty())

func test_authorized_npc_waits_at_service_point_and_accrues_pay() -> void:
	var f := _fixture()
	f.duty.granted = true
	assert_true(f.provider.get_contract_work_status(f.worker, f.contract).actionable)
	assert_not_null(f.provider.start_contract_shift(f.worker, f.contract))
	f.provider.process_jobs(1.0, 1.0)
	assert_eq(f.point.get_assigned_worker(), f.worker)
	assert_eq(f.provider._get_worker_record(f.worker).owed_currency, 1)
	assert_true(f.provider.get_contract_work_status(f.worker, f.contract).actionable)
	assert_not_null(f.provider.create_assigned_work_ai_job(f.worker))

func test_revoked_continuation_releases_claims_without_pay_or_priority_order_reset() -> void:
	var f := _fixture()
	f.duty.granted = true
	assert_not_null(f.provider.start_contract_shift(f.worker, f.contract))
	f.provider.process_jobs(1.0, 1.0)
	var slot: Dictionary = f.provider._find_worker_slot(f.worker).slot_state
	slot.target_service_seat = f.point
	f.worker.order_type = InteractionCapability.ORDER_TYPE_HEAL
	f.duty.granted = false
	var result: Dictionary = f.provider.tick_worker_job_from_ai(f.worker, 10.0)
	assert_true(result.ended)
	assert_null(f.point.get_assigned_worker())
	assert_eq(f.area.released_seats, 1)
	assert_null(f.worker.get_active_job_provider())
	assert_eq(f.worker.order_type, InteractionCapability.ORDER_TYPE_HEAL)
	assert_eq(f.worker.stops, 0)
	assert_eq(f.provider._get_worker_record(f.worker).owed_currency, 1)

func test_revocation_in_process_jobs_preserves_player_and_combat_movement() -> void:
	for player_order in [true, false]:
		var f := _fixture()
		f.duty.granted = true
		assert_not_null(f.provider.start_contract_shift(f.worker, f.contract))
		f.worker._active_player_order = player_order
		f.worker.fighting = not player_order
		f.worker.order_type = InteractionCapability.ORDER_TYPE_MOVE
		f.duty.granted = false
		f.provider.process_jobs(2.0, 2.0)
		assert_null(f.worker.get_active_job_provider())
		assert_eq(f.worker.stops, 0)
		assert_eq(f.worker.order_type, InteractionCapability.ORDER_TYPE_MOVE)

func test_party_voluntary_contract_start_does_not_require_npc_duty() -> void:
	var f := _fixture()
	f.worker.player_party_member = true
	assert_not_null(f.provider.start_contract_shift(f.worker, f.contract))
	assert_eq(f.worker.get_active_job_provider(), f.provider)
	assert_eq(f.provider.started, 1)

func test_revocation_preserves_direct_law_move() -> void:
	var f := _fixture()
	f.duty.granted = true
	assert_not_null(f.provider.start_contract_shift(f.worker, f.contract))
	f.worker.law_interaction = LawInteraction.new()
	f.worker.order_type = InteractionCapability.ORDER_TYPE_MOVE
	f.duty.granted = false
	f.provider.process_jobs(1.0, 1.0)
	assert_null(f.worker.get_active_job_provider())
	assert_eq(f.worker.stops, 0)
	assert_eq(f.worker.order_type, InteractionCapability.ORDER_TYPE_MOVE)
	assert_true(f.worker.get_interaction().has_direct_law_move())

func test_authorized_order_preparation_continues_service() -> void:
	var f := _fixture()
	f.duty.granted = true
	assert_not_null(f.provider.start_contract_shift(f.worker, f.contract))
	var slot: Dictionary = f.provider._find_worker_slot(f.worker).slot_state
	slot.target_service_customer = f.worker
	slot.target_service_seat = f.point
	slot.server_state = JobProvider.SERVER_STATE_WAITING_AT_BAR
	f.worker.seated = true
	f.provider.process_jobs(1.0, 1.0)
	assert_eq(slot.server_state_elapsed, 1.0)
	assert_eq(slot.server_state, JobProvider.SERVER_STATE_WAITING_AT_BAR)
	assert_eq(f.provider._get_worker_record(f.worker).owed_currency, 1)

func test_detached_provider_also_requires_npc_authorization() -> void:
	var provider := JobProvider.new()
	var worker := Worker.new()
	autofree(provider)
	autofree(worker)
	var definition := JobDefinition.new()
	definition.algorithm_id = "server_shift"
	provider.jobs.append(definition)
	assert_false(provider._claim_worker_slot(worker, 0, false).allowed)
	assert_true(provider._worker_records.is_empty())
