extends GutTest

const STEP = preload("res://features/camps/bridge/camp_routine_step.gd")

class Actor extends Node3D:
	var life_state := NpcRules.LifeState.ALIVE
	var movement_calls := 0
	var seat_calls := 0
	var moving := false
	var is_sitting := false
	var current_seat_target: Node
	func wake_up_from_rest(_player: bool) -> void:
		is_sitting = false
		current_seat_target = null
	func set_move_target(_target: Vector3, _player: bool) -> void:
		movement_calls += 1
		moving = true
	func has_move_target() -> bool:
		return moving
	func stop_movement() -> void:
		moving = false
	func assign_seat_target(seat: Node, _player: bool) -> void:
		seat_calls += 1
		current_seat_target = seat
	func get_interaction():
		return self

class Seat extends Node:
	var sitter: Node
	func claim_sitter(actor: Node) -> bool:
		if is_instance_valid(sitter) and sitter != actor:
			return false
		sitter = actor
		return true
	func release_sitter(actor: Node) -> void:
		if sitter == actor:
			sitter = null

class Source extends Node:
	var seat: Node
	func get_camp_seat(_job, _actor: Node = null) -> Node:
		return seat
	func get_camp_post(_job) -> FacilityGuardPost:
		return null
	func get_patrol_destination(_actor, job) -> Vector3:
		return job.data.destination

func _job(source: Node, routine: String) -> AiJob:
	var job := AiJob.new()
	job.source = source
	job.data = {"routine": routine, "destination": Vector3(10, 0, 0), "camp_center": Vector3.ZERO, "camp_radius": 20.0}
	return job

func test_unchanged_guard_destination_does_not_restart_travel() -> void:
	var actor := Actor.new()
	var source := Source.new()
	add_child_autofree(actor)
	add_child_autofree(source)
	var job := _job(source, "guard")
	var step = STEP.new()
	step.start(actor, job)
	for index in 8:
		step.tick(actor, job, 0.5)
	assert_eq(actor.movement_calls, 1, "one movement order, not a reset every half second")
	actor.position = job.data.destination
	step.tick(actor, job, 0.5)
	for index in 8:
		step.tick(actor, job, 0.5)
	assert_eq(actor.movement_calls, 1, "holding position never restarts navigation")

func test_seat_is_reserved_before_approach_and_released_on_cancel() -> void:
	var actor := Actor.new()
	var source := Source.new()
	var seat := Seat.new()
	add_child_autofree(actor)
	add_child_autofree(source)
	add_child_autofree(seat)
	source.seat = seat
	var job := _job(source, "sit")
	var step = STEP.new()
	step.start(actor, job)
	assert_eq(seat.sitter, actor)
	assert_eq(actor.seat_calls, 1, "use shared safe seat approach immediately")
	actor.is_sitting = true
	for index in 12:
		step.tick(actor, job, 0.5)
	assert_eq(actor.seat_calls, 1)
	assert_eq(actor.movement_calls, 0, "never path into stool collider")
	step.cancel(actor, job)
	assert_null(seat.sitter)

func test_occupied_seat_falls_back_to_standing_without_retries() -> void:
	var actor := Actor.new()
	var occupant := Actor.new()
	var source := Source.new()
	var seat := Seat.new()
	for node in [actor, occupant, source, seat]:
		add_child_autofree(node)
	source.seat = seat
	seat.sitter = occupant
	actor.moving = true
	var job := _job(source, "sit")
	var step = STEP.new()
	step.start(actor, job)
	for index in 12:
		step.tick(actor, job, 0.5)
	assert_eq(seat.sitter, occupant)
	assert_false(actor.moving, "standing fallback clears an earlier movement target")
	assert_eq(actor.seat_calls, 0)
	assert_eq(actor.movement_calls, 0)

func test_cancel_before_start_never_claims_a_seat() -> void:
	var actor := Actor.new()
	var source := Source.new()
	var seat := Seat.new()
	for node in [actor, source, seat]:
		add_child_autofree(node)
	source.seat = seat
	var step = STEP.new()
	step.cancel(actor, _job(source, "sit"))
	assert_null(seat.sitter)
	assert_eq(actor.seat_calls, 0)

func test_removed_seat_releases_pose_and_falls_back_to_quiet_standing() -> void:
	var actor := Actor.new()
	var source := Source.new()
	add_child_autofree(actor)
	add_child_autofree(source)
	var seat := Seat.new()
	source.seat = seat
	var step = STEP.new()
	var job := _job(source, "sit")
	step.start(actor, job)
	actor.is_sitting = true
	step.tick(actor, job, 0.5)
	seat.free()
	for index in 12:
		assert_eq(step.tick(actor, job, 0.5), AiTaskStep.StepStatus.RUNNING)
	assert_false(actor.is_sitting)
	assert_eq(actor.seat_calls, 1)
	assert_eq(actor.movement_calls, 0)

func test_patrol_keeps_travel_but_retries_a_failed_path_only_after_cooldown() -> void:
	var actor := Actor.new()
	var source := Source.new()
	add_child_autofree(actor)
	add_child_autofree(source)
	var job := _job(source, "patrol")
	var step = STEP.new()
	step.start(actor, job)
	step.tick(actor, job, 0.5)
	actor.moving = false
	for index in 8:
		step.tick(actor, job, 0.5)
	assert_eq(actor.movement_calls, 1)
	for index in 4:
		step.tick(actor, job, 0.5)
	assert_eq(actor.movement_calls, 2)
	for index in 20:
		step.tick(actor, job, 0.5)
	assert_eq(actor.movement_calls, 2, "an active path is never restarted")
