extends GutTest

class DutyJobs extends JobSystemController:
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	var granted := false
	var checked_actor: Node
	func can_execute_assignment_duty(actor: Node) -> bool:
		checked_actor = actor
		return granted

class Staff extends HumanoidCharacter:
	var moves := 0
	var clears := 0
	var target := Vector3.INF
	var fighting := false
	var player_order := false
	var carrying := false
	var interaction := InteractionCapability.new()
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func get_interaction() -> InteractionCapability: return interaction
	func set_move_target(destination: Vector3, _issued_by_player: bool = true) -> void:
		moves += 1
		target = destination
	func has_move_target() -> bool: return target.is_finite()
	func get_move_target() -> Vector3: return target
	func _clear_actor_move_target() -> void:
		clears += 1
		target = Vector3.INF
	func is_in_combat() -> bool: return fighting
	func has_active_player_order() -> bool: return player_order
	func is_carrying_someone() -> bool: return carrying
	func is_law_prisoner() -> bool: return true

# Runtime-only double; deliberately do not execute facility tooling in the editor.
@warning_ignore("missing_tool")
class Jail extends SettlementJail:
	var warden: Node
	var sentence_active := false
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func get_warden_actor() -> Node: return warden
	func _is_warden_sentence_delivery_active(_warden: HumanoidCharacter) -> bool:
		return sentence_active
	func _has_pending_sentence_notification(_actor: HumanoidCharacter) -> bool: return true
	func _ensure_sentence_route(entry: Dictionary, _actor: WorldActor, _warden: HumanoidCharacter) -> Dictionary:
		return entry
	func _open_sentence_conversation(_warden: HumanoidCharacter, _actor: WorldActor, _message: String) -> bool: return true
	func _notify_sentence_delivered(_actor: WorldActor) -> bool: return true

@warning_ignore("missing_tool")
class Point extends FacilityGuardPost:
	var worker: WorldActor
	func get_pool_key(_owners: Dictionary) -> String: return "town:test"
	func get_assigned_worker() -> WorldActor: return worker
	func is_worker_at_post(actor: WorldActor) -> bool: return actor.global_position.distance_to(get_work_position()) <= stand_radius
	var work_position := Vector3(10, 0, 0)
	func get_work_position() -> Vector3: return work_position
	func get_customer_position() -> Vector3: return Vector3(11, 0, 0)
	func is_available_for(actor: WorldActor) -> bool: return worker == null or worker == actor
	func claim_worker(actor: WorldActor) -> bool:
		if not is_available_for(actor): return false
		worker = actor
		return true
	func release_worker(actor: WorldActor) -> void:
		if worker == actor: worker = null

var _previous_context: BootstrapContext

func before_each() -> void:
	_previous_context = BootstrapContext.active

func after_each() -> void:
	BootstrapContext.active = _previous_context

func _fixture() -> Dictionary:
	var host := Node3D.new()
	add_child_autofree(host)
	var jobs := DutyJobs.new()
	host.add_child(jobs)
	var context := BootstrapContext.new(host)
	context.register(&"job_system", jobs)
	BootstrapContext.active = context
	jobs._context = context
	var jail := Jail.new()
	host.add_child(jail)
	var actor := Staff.new()
	actor.stable_id = "guard"
	host.add_child(actor)
	var point := Point.new()
	jail.add_child(point)
	jobs.guard_duty.assignments["guard"] = "town:test"
	jobs.guard_duty.register_post(point)
	jail.warden = actor
	jail._cached_warden_post = point
	jail._cached_guard_posts.append(point)
	return {"jail": jail, "actor": actor, "jobs": jobs, "point": point}

func test_denied_duty_cannot_start_desk_or_guard_movement_or_claims() -> void:
	var f := _fixture()
	f.jail._process_warden_home_return()
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	assert_eq(f.jobs.checked_actor, f.actor)
	assert_eq(f.actor.moves, 0)
	assert_null(f.point.worker)
	assert_false(f.actor.is_on_counter_duty())

func test_denied_duty_cannot_begin_counter_pose_even_at_desk() -> void:
	var f := _fixture()
	f.actor.position = f.point.work_position
	f.jail._process_warden_home_return()
	assert_false(f.actor.is_on_counter_duty())
	assert_null(f.point.worker)

func test_granted_desk_return_is_routine_not_law_custody() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.jail._process_warden_home_return()
	assert_eq(f.actor.moves, 1)
	assert_eq(f.actor.target, f.point.work_position)
	assert_false(f.actor.interaction.is_law_custody_returning())
	f.actor.position = f.point.work_position
	f.jail._process_warden_home_return()
	assert_true(f.actor.is_on_counter_duty())
	assert_eq(f.point.worker, f.actor)

func test_granted_guard_claims_post_and_moves() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	assert_eq(f.actor.moves, 1)
	assert_eq(f.point.worker, f.actor)

func test_release_clears_guard_claim_and_owned_movement() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	f.jail.release_settlement_assignment_duty(f.actor)
	assert_null(f.point.worker)
	assert_true(f.jobs.guard_duty._claims.is_empty())
	assert_true(f.jobs.guard_duty._moves.is_empty())
	assert_false(f.actor.has_move_target())
	assert_eq(f.actor.clears, 1)

func test_grant_loss_releases_counter_pose_and_claim() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.actor.position = f.point.work_position
	f.jail._process_warden_home_return()
	f.jobs.granted = false
	f.jail._process_warden_home_return()
	assert_null(f.point.worker)
	assert_false(f.actor.is_on_counter_duty())

func test_grant_loss_stops_routine_desk_commute_without_law_state() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.jail._process_warden_home_return()
	f.jobs.granted = false
	f.jail._process_warden_home_return()
	assert_eq(f.actor.moves, 1)
	assert_false(f.actor.has_move_target())
	assert_false(f.actor.interaction.is_law_custody_returning())
	assert_true(f.jail._routine_duty_target_by_actor_id.is_empty())

func test_grant_loss_releases_guard_without_reissuing_move() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	f.jobs.granted = false
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	assert_eq(f.actor.moves, 1)
	assert_false(f.actor.has_move_target())
	assert_null(f.point.worker)
	assert_true(f.jobs.guard_duty._claims.is_empty())

func test_release_preserves_replacement_home_movement() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.jail._process_warden_home_return()
	var home := Vector3(20, 0, 0)
	f.actor.set_move_target(home, false)
	f.jail.release_settlement_assignment_duty(f.actor)
	assert_eq(f.actor.target, home)
	assert_eq(f.actor.clears, 0)

func test_real_custody_return_is_not_replaced_or_cleared_by_duty() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	f.actor.interaction._law_custody_return_active = true
	f.jail._process_warden_home_return()
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	f.jail.release_settlement_assignment_duty(f.actor)
	assert_eq(f.actor.moves, 1)
	assert_eq(f.actor.clears, 0)
	assert_true(f.actor.interaction.is_law_custody_returning())
	assert_null(f.point.worker)

func test_sentence_move_survives_denied_duty_and_release() -> void:
	var f := _fixture()
	f.actor.interaction._law_sentence_move_active = true
	f.actor.target = Vector3(3, 0, 0)
	f.jail._process_warden_home_return()
	f.jail.release_settlement_assignment_duty(f.actor)
	assert_eq(f.actor.target, Vector3(3, 0, 0))
	assert_true(f.actor.interaction.is_law_sentence_moving())
	assert_eq(f.actor.moves, 0)
	assert_eq(f.actor.clears, 0)

func test_active_sentence_delivery_preempts_granted_desk_return() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.jail.sentence_active = true
	f.jail._process_warden_home_return()
	assert_eq(f.actor.moves, 0)
	assert_null(f.point.worker)

func test_custody_hauling_preempts_even_a_granted_duty() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.actor.interaction.current_order_type = InteractionCapability.ORDER_TYPE_PLACE_IN_CELL
	f.jail._process_warden_home_return()
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	f.jail.release_settlement_assignment_duty(f.actor)
	assert_eq(f.actor.moves, 0)
	assert_eq(f.actor.clears, 0)
	assert_eq(f.actor.interaction.current_order_type, InteractionCapability.ORDER_TYPE_PLACE_IN_CELL)

func test_release_does_not_cancel_player_or_combat_movement() -> void:
	var f := _fixture()
	f.jobs.granted = true
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	f.actor.player_order = true
	f.jail.release_settlement_assignment_duty(f.actor)
	assert_eq(f.actor.clears, 0)
	assert_null(f.point.worker)
	f.actor.player_order = false
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	f.actor.fighting = true
	f.jail.release_settlement_assignment_duty(f.actor)
	assert_eq(f.actor.clears, 0)
	assert_null(f.point.worker)

func test_missing_jobs_service_fails_closed() -> void:
	var f := _fixture()
	BootstrapContext.active = BootstrapContext.new()
	f.jail._process_warden_home_return()
	f.jail._process_guard_post_assignment(f.actor, 0.1)
	assert_eq(f.actor.moves, 0)
	assert_null(f.point.worker)

func test_sentence_completion_releases_interaction_law_state_before_routine_duty() -> void:
	var f := _fixture()
	f.actor.interaction._law_sentence_move_active = true
	f.jail._pending_sentence_announcements.append({"actor": f.actor, "route": [Vector3.ZERO], "route_index": 0})
	f.jail._process_sentence_announcements(0.1)
	assert_true(f.jail._pending_sentence_announcements.is_empty())
	assert_false(f.actor.interaction.is_law_sentence_moving(), "Completion must clear the capability, not a nonexistent actor method")
	f.jobs.granted = true
	f.jail._process_warden_home_return()
	assert_eq(f.actor.moves, 1, "Completed sentencing must allow routine desk return")
