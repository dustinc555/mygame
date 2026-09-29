extends GutTest

const BAR = preload("res://features/settlements/bridge/venues/bar_service_area.gd")
const JOBS = preload("res://features/settlements/sim/job_system_controller.gd")

class Clock extends Node:
	var hour := 20
	func get_hour() -> int: return hour

class Residents extends Node:
	var actor: Node
	func get_live_actor(_id: String) -> Node: return actor

class Settlements extends SettlementController:
	var residents: Node
	func _get_population_controller() -> Node: return residents

class VenueOwner extends Node:
	var venue: Node
	func get_bar_service_area() -> Node: return venue
	func release_settlement_assignment_duty(actor: Node) -> void:
		venue.release_staff_duty(actor)

# Runtime-only double; deliberately do not execute facility tooling in the editor.
@warning_ignore("missing_tool")
class Facility extends SettlementBar:
	func _ready() -> void: pass
	func _repair_authoring_tree() -> void: pass

class Seat extends Node3D:
	var sitter: Node
	func claim_sitter(actor: Node) -> bool:
		sitter = actor
		return true
	func release_sitter(actor: Node) -> void:
		if sitter == actor: sitter = null
	func get_sitter() -> Node: return sitter
	func get_seat_position(_actor: Node = null) -> Vector3: return global_position
	func is_occupied() -> bool: return sitter != null

class HomeOwner extends Node:
	var point: Node
	var released_before_home := false
	func refresh_settlement_assignment_actor(_actor: Node, _slot: Dictionary) -> void:
		released_before_home = point.worker == null

class Staff extends HumanoidCharacter:
	var moves := 0
	var seat_assignments := 0
	var seat_target: Node
	var fighting := false
	var player_order := false
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func set_move_target(_target: Vector3, _issued_by_player: bool = true, _continue_order: bool = false) -> void: moves += 1
	func is_in_combat() -> bool: return fighting
	func has_active_player_order() -> bool: return player_order
	func is_player_party_member() -> bool: return false
	func is_sitting() -> bool: return false
	func assign_seat_target(seat: Node, _issued_by_player: bool = true) -> void:
		seat_assignments += 1
		seat_target = seat
		get_interaction().current_seat_target = seat
		seat.claim_sitter(self)
	func get_current_seat_target() -> Node: return get_interaction().current_seat_target

@warning_ignore("missing_tool")
class Point extends FacilityGuardPost:
	var worker: WorldActor
	func get_pool_key(_owners: Dictionary) -> String: return "character:owner"
	func get_assigned_worker() -> WorldActor: return worker
	func is_worker_at_post(actor: WorldActor) -> bool: return actor.global_position.distance_to(get_work_position()) <= stand_radius
	func get_work_position() -> Vector3: return Vector3(10, 0, 0)
	func get_customer_position() -> Vector3: return Vector3.ZERO
	func is_available_for(actor: WorldActor) -> bool: return worker == null or worker == actor
	func claim_worker(actor: WorldActor) -> bool:
		worker = actor
		return true
	func release_worker(actor: WorldActor) -> void:
		if worker == actor: worker = null
	func is_point_role(role: String) -> bool: return role == "waiter"

var _previous_context: BootstrapContext

func before_each() -> void:
	_previous_context = BootstrapContext.active

func after_each() -> void:
	BootstrapContext.active = _previous_context

func _fixture() -> Dictionary:
	var host := Node3D.new()
	add_child_autofree(host)
	var clock := Clock.new()
	host.add_child(clock)
	var jobs := JOBS.new()
	autofree(jobs)
	var context := BootstrapContext.new(host)
	context.register(&"world_time", clock)
	context.register(&"job_system", jobs)
	BootstrapContext.active = context
	jobs._context = context
	var bar := BAR.new()
	bar.set_process(false)
	host.add_child(bar)
	bar.set_process(false)
	var actor := Staff.new()
	actor.name = "Waiter"
	actor.stable_id = "staff"
	bar.add_child(actor)
	bar.owner_character_path = NodePath("Waiter")
	bar.waiter_character_path = NodePath("Waiter")
	bar.guards_root_path = NodePath("Missing")
	bar.waiters_root_path = NodePath("Missing")
	var points := Node3D.new()
	points.name = "Points"
	bar.add_child(points)
	bar.service_points_root_path = NodePath("Points")
	bar.guard_posts_root_path = NodePath("Points")
	var point := Point.new()
	points.add_child(point)
	jobs.guard_duty.assignments["staff"] = "character:owner"
	jobs.guard_duty.register_post(point)
	bar._barkeeper_counter = point
	bar._barkeeper_counter_lookup_complete = true
	jobs._assignment_workers["staff"] = {"schedule_enabled": true, "work_schedule": {}, "duty_scope_id": "bar"}
	FacilityDutyContract.begin(actor, "bar")
	return {"bar": bar, "actor": actor, "point": point, "clock": clock, "jobs": jobs}

func test_closed_shift_does_not_reissue_counter_guard_or_waiter_movement() -> void:
	var f := _fixture()
	f.bar._process_owner_counter_duty()
	f.bar._process_guard_post_assignment(f.actor, 0.1)
	f.bar._return_waiter_to_service_point(f.actor)
	assert_eq(f.actor.moves, 0)
	assert_null(f.bar._find_waiter_for_service(null))
	assert_null(f.point.worker)

func test_shift_end_releases_counter_and_guard_claims() -> void:
	var f := _fixture()
	f.clock.hour = 19
	f.bar._process_guard_post_assignment(f.actor, 0.1)
	f.bar._counter_duty_owner = f.actor
	f.actor.begin_counter_duty(Vector3.ZERO)
	f.clock.hour = 20
	f.bar._process_owner_counter_duty()
	f.bar._process_guard_post_assignment(f.actor, 0.1)
	assert_null(f.point.worker)
	assert_false(f.actor.is_on_counter_duty())
	assert_true(f.jobs.guard_duty._claims.is_empty())
	assert_eq(f.actor.moves, 1, "Closing must not issue another move")

func test_authored_night_shift_reopens_legacy_waiter_execution() -> void:
	var f := _fixture()
	f.jobs._assignment_workers.staff.work_schedule = {"start_hour": 20, "end_hour": 6}
	assert_eq(f.bar._find_waiter_for_service(null), f.actor)
	f.bar._return_waiter_to_service_point(f.actor)
	assert_eq(f.actor.moves, 1)
	f.clock.hour = 6
	f.bar._return_waiter_to_service_point(f.actor)
	assert_eq(f.actor.moves, 1)
	assert_null(f.point.worker)

func test_player_order_and_combat_preempt_direct_staff_movement() -> void:
	var f := _fixture()
	f.clock.hour = 10
	for fighting in [false, true]:
		f.actor.player_order = not fighting
		f.actor.fighting = fighting
		f.bar._process_owner_counter_duty()
		f.bar._process_guard_post_assignment(f.actor, 0.1)
		f.bar._return_waiter_to_service_point(f.actor)
	assert_eq(f.actor.moves, 0)

func test_residence_handoff_releases_venue_before_home_projection() -> void:
	var f := _fixture()
	var settlements := Settlements.new()
	autofree(settlements)
	settlements._context = BootstrapContext.active
	var residents := Residents.new()
	autofree(residents)
	residents.actor = f.actor
	settlements.residents = residents
	BootstrapContext.active.register(&"population", residents)
	var venue_owner := VenueOwner.new()
	autofree(venue_owner)
	venue_owner.venue = f.bar
	var home := HomeOwner.new()
	autofree(home)
	home.point = f.point
	settlements._staff_role_owners_by_settlement["town"] = {"bar": venue_owner, "home": home}
	settlements.settlement_states["town"] = {"assignment_slots": {
		"employment:staff": {"assignment_domain": "employment", "slot_id": "staff", "occupant_actor_id": "staff", "owner_id": "bar"},
		"residence:resident": {"assignment_domain": "residence", "slot_id": "resident", "occupant_actor_id": "staff", "owner_id": "home"}}}
	f.point.claim_worker(f.actor)
	f.bar._pending_waiter_order = {"claimed_by": f.actor, "status": "claimed"}
	settlements.refresh_actor_residence_projection("town", "staff")
	assert_true(home.released_before_home)
	assert_null(f.bar._pending_waiter_order.claimed_by)
	assert_eq(f.bar._pending_waiter_order.status, "pending")

func test_closing_cancels_active_service_without_return_move() -> void:
	var f := _fixture()
	f.bar._active_service_waiter = f.actor
	f.bar._active_service_seat = f.point
	f.point.claim_worker(f.actor)
	f.bar._continue_waiter_service(f.actor)
	assert_null(f.bar._active_service_waiter)
	assert_null(f.point.worker)
	assert_eq(f.actor.moves, 0)

func test_24_hour_staff_waits_for_jobs_grant_before_executing() -> void:
	var f := _fixture()
	f.jobs._assignment_workers.staff.work_schedule = {"start_hour": 0, "end_hour": 0}
	FacilityDutyContract.end(f.actor, "bar")
	f.bar._process_owner_counter_duty()
	f.bar._process_guard_post_assignment(f.actor, 0.1)
	f.bar._return_waiter_to_service_point(f.actor)
	assert_eq(f.actor.moves, 0, "An open shift is not a Jobs grant")
	assert_null(f.bar._find_waiter_for_service(null))
	FacilityDutyContract.begin(f.actor, "bar")
	f.bar._return_waiter_to_service_point(f.actor)
	assert_eq(f.actor.moves, 1)
	assert_eq(f.bar._find_waiter_for_service(null), f.actor)

func test_on_shift_fallback_does_not_restart_venue_duty() -> void:
	var f := _fixture()
	f.clock.hour = 10
	f.bar._process_guard_post_assignment(f.actor, 0.1)
	FacilityDutyContract.end(f.actor, "bar")
	f.bar.release_staff_duty(f.actor)
	f.bar._process_guard_post_assignment(f.actor, 0.1)
	f.bar._return_waiter_to_service_point(f.actor)
	assert_eq(f.actor.moves, 1)
	assert_null(f.point.worker)

func test_barber_does_not_restart_seating_off_duty() -> void:
	var f := _fixture()
	var facility := Facility.new()
	add_child_autofree(facility)
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	facility.add_child(furniture)
	var seat := Seat.new()
	furniture.add_child(seat)
	f.clock.hour = 10
	facility._send_barber_to_seat(f.actor)
	assert_eq(f.actor.seat_assignments, 1)
	facility._send_barber_to_seat(f.actor)
	assert_eq(f.actor.seat_assignments, 1, "Routine refresh must not restart the same seat journey")
	f.clock.hour = 20
	facility.release_settlement_assignment_duty(f.actor)
	facility._send_barber_to_seat(f.actor)
	assert_eq(f.actor.seat_assignments, 1)
	assert_null(seat.sitter)

func test_initial_staff_service_move_requires_jobs_grant() -> void:
	var f := _fixture()
	var facility := Facility.new()
	add_child_autofree(facility)
	facility.bar_service_area_path = facility.get_path_to(f.bar)
	f.clock.hour = 10
	FacilityDutyContract.end(f.actor, "bar")
	facility._send_actor_to_service_point(f.actor, "barkeeper")
	assert_eq(f.actor.moves, 0)
	FacilityDutyContract.begin(f.actor, "bar")
	facility._send_actor_to_service_point(f.actor, "barkeeper")
	assert_eq(f.actor.moves, 1)

func test_barber_release_preserves_a_player_owned_seat() -> void:
	var f := _fixture()
	var facility := Facility.new()
	add_child_autofree(facility)
	var seat := Seat.new()
	facility.add_child(seat)
	seat.claim_sitter(f.actor)
	facility._barber_seat_by_actor_id[f.actor.get_instance_id()] = seat
	f.actor.seat_target = seat
	f.actor.player_order = true
	facility.release_settlement_assignment_duty(f.actor)
	assert_eq(seat.sitter, f.actor)
	assert_eq(f.actor.seat_target, seat)
	assert_true(facility._barber_seat_by_actor_id.is_empty())

func test_barber_release_does_not_release_an_unowned_residence_seat() -> void:
	var f := _fixture()
	var facility := Facility.new()
	add_child_autofree(facility)
	var seat := Seat.new()
	facility.add_child(seat)
	seat.claim_sitter(f.actor)
	f.actor.seat_target = seat
	facility.release_settlement_assignment_duty(f.actor)
	assert_eq(seat.sitter, f.actor)
	assert_eq(f.actor.seat_target, seat)
