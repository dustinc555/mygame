extends GutTest

class QuietActor extends WorldActor:
	func _enter_tree() -> void:
		pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

var actor: QuietActor

func before_each() -> void:
	actor = QuietActor.new()
	add_child(actor)

func after_each() -> void:
	actor.free()

func test_sideways_shuffling_does_not_count_as_progress() -> void:
	actor._navigation_agent.set_move_target(Vector3(0, 0, 10))
	actor.position.x = 0.5
	assert_false(actor._navigation_agent._has_made_stuck_progress())
	actor.position.x = -0.5
	assert_false(actor._navigation_agent._has_made_stuck_progress())

func test_real_approach_counts_as_progress() -> void:
	actor._navigation_agent.set_move_target(Vector3(0, 0, 10))
	actor.position.z = 0.2
	assert_true(actor._navigation_agent._has_made_stuck_progress())

func test_combat_reposition_retains_displacement_progress() -> void:
	actor._navigation_agent.set_move_target(Vector3(0, 0, 10), WorldActor.COMBAT_ARRIVAL_DISTANCE, false)
	actor.position.x = 0.5
	assert_true(actor._navigation_agent._has_made_stuck_progress(), "Tactical circling is not a blocked travel order")

func test_combat_target_discards_passage_recovery_even_at_same_destination() -> void:
	var follower = actor._navigation_agent
	follower.set_move_target(Vector3(0, 0, 10))
	follower._recovery_path_index = 2
	follower.set_move_target(Vector3(0, 0, 10), WorldActor.COMBAT_ARRIVAL_DISTANCE, false)
	assert_eq(follower._recovery_path_index, -1)
	assert_false(follower._passage_recovery)

func test_recovery_advances_horizontal_waypoint_despite_path_height_offset() -> void:
	var follower = actor._navigation_agent
	follower.set_move_target(Vector3(0, 0, 10))
	follower._progress_path = PackedVector3Array([Vector3(0, 0.9, 0), Vector3(0, 0.9, 2)])
	follower._recovery_path_index = 0
	assert_eq(follower._get_recovery_move_direction(), Vector3.BACK)
	assert_eq(follower._recovery_path_index, 1)

func test_recovery_does_not_skip_corner_at_ordinary_waypoint_distance() -> void:
	var follower = actor._navigation_agent
	follower.set_move_target(Vector3(0, 0, 10))
	follower._progress_path = PackedVector3Array([Vector3(0.4, 0.9, 0), Vector3(0.4, 0.9, 2)])
	follower._recovery_path_index = 0
	assert_eq(follower._get_recovery_move_direction(), Vector3.RIGHT)
	assert_eq(follower._recovery_path_index, 0)

func test_progress_follows_detour_even_when_moving_away_from_destination() -> void:
	var follower = actor._navigation_agent
	follower.set_move_target(Vector3(0, 0, 10))
	follower._progress_path = PackedVector3Array([Vector3(0, 0, -2), Vector3(0, 0, 10)])
	follower._remaining_lengths = PackedFloat32Array([12.0, 0.0])
	follower._recovery_path_index = 0
	follower._target_synced = true
	follower._reset_stuck_tracking()
	actor.position.z = -0.2
	assert_true(follower._has_made_stuck_progress())

func test_new_destination_discards_precise_recovery_route() -> void:
	var follower = actor._navigation_agent
	follower.set_move_target(Vector3(0, 0, 10))
	follower._recovery_path_index = 2
	follower.set_move_target(Vector3(5, 0, 0))
	assert_eq(follower._recovery_path_index, -1)

func test_new_command_resets_previous_stall_but_continuing_goal_does_not() -> void:
	var follower = actor._navigation_agent
	follower.set_move_target(Vector3(0, 0, 10))
	follower.update_stuck_state(0.5, Vector3.BACK)
	follower._stuck_repath_attempts = 2
	follower._recovery_path_index = 1
	follower.set_move_target(Vector3(0, 0, 9), -1.0, true, true)
	assert_almost_eq(follower._stuck_seconds, 0.5, 0.001)
	assert_eq(follower._stuck_repath_attempts, 2)
	assert_eq(follower._recovery_path_index, 1)
	assert_false(follower._has_made_stuck_progress(), "The goal approaching a stationary body is not progress")
	follower.set_move_target(Vector3(5, 0, 0))
	assert_eq(follower._stuck_seconds, 0.0)
	assert_eq(follower._stuck_repath_attempts, 0)
	assert_eq(follower._recovery_path_index, -1)

func test_small_physical_steps_accumulate_across_continuing_combat_goals() -> void:
	var follower = actor._navigation_agent
	follower.set_move_target(Vector3(0, 0, 10), -1.0, false)
	for step in range(4):
		actor.position.x += actor.stuck_min_progress * 0.3
		follower.set_move_target(Vector3(0, 0, 10.0 + step * 0.2), -1.0, false, true)
		follower.update_stuck_state(0.1, Vector3.RIGHT)
	assert_eq(follower._stuck_seconds, 0.0, "Real circling progress still resets recovery even when each step is below the threshold")

func test_yield_does_not_replace_order_and_new_command_wins() -> void:
	assert_true(actor.begin_navigation_yield(Vector3(2, 0, 0)))
	assert_false(actor.get_persistent_movement_state()["has_move_target"], "A sidestep is not a saved order")
	actor.set_move_target(Vector3(0, 0, 5), true)
	actor.end_navigation_yield()
	assert_eq(actor.get_move_target(), Vector3(0, 0, 5), "Yield cleanup cannot erase a newer command")

func test_busy_actor_refuses_yield() -> void:
	actor.set_move_target(Vector3(0, 0, 5), true)
	assert_false(actor.begin_navigation_yield(Vector3(2, 0, 0)))
	assert_eq(actor.get_move_target(), Vector3(0, 0, 5))

func test_stop_cancels_return_trip() -> void:
	assert_true(actor.begin_navigation_yield(Vector3(2, 0, 0)))
	actor.stop_movement()
	actor.end_navigation_yield()
	assert_false(actor.has_move_target())
	assert_false(actor.is_navigation_yielding())

func test_duty_target_waits_for_passage_then_resumes() -> void:
	assert_true(actor.begin_navigation_yield(Vector3(2, 0, 0)))
	actor.set_move_target(Vector3(0, 0, 3), false)
	assert_eq(actor.get_move_target(), Vector3(2, 0, 0))
	actor.end_navigation_yield()
	assert_eq(actor.get_move_target(), Vector3(0, 0, 3))
	assert_false(actor.has_active_player_order())

func test_combat_interrupt_cannot_restore_old_post() -> void:
	assert_true(actor.begin_navigation_yield(Vector3(2, 0, 0)))
	actor._system_move_active = true
	actor._system_move_settled = false
	actor._system_move_target = Vector3(0, 0, 8)
	actor._prepare_combat_navigation(0.0)
	actor.end_navigation_yield()
	assert_eq(actor.get_move_target(), Vector3(0, 0, 8))
	assert_false(actor.is_navigation_yielding())

func test_tree_removal_discards_transient_yield() -> void:
	assert_true(actor.begin_navigation_yield(Vector3(2, 0, 0)))
	remove_child(actor)
	add_child(actor)
	assert_false(actor.is_navigation_yielding())
	assert_false(actor.has_move_target())

func test_timeout_releases_actor_and_sleeps_controller() -> void:
	var recovery = load("res://features/actors/bridge/navigation/navigation_recovery_controller.gd").new()
	add_child(recovery)
	var requester := QuietActor.new()
	add_child(requester)
	requester.set_move_target(Vector3(0, 0, 5))
	assert_true(actor.begin_navigation_yield(Vector3(2, 0, 0)))
	recovery._active.append({"requester": weakref(requester), "blocker": weakref(actor), "origin": Vector3.ZERO, "remaining": 0.1})
	recovery._physics_process(0.2)
	assert_false(actor.is_navigation_yielding())
	assert_eq(actor.get_move_target(), Vector3.ZERO)
	assert_true(recovery._active.is_empty())
	assert_false(recovery.is_physics_processing())
	requester.free()
	recovery.free()

func test_freed_requester_releases_yield_safely() -> void:
	var recovery = load("res://features/actors/bridge/navigation/navigation_recovery_controller.gd").new()
	add_child(recovery)
	var requester := Node3D.new()
	add_child(requester)
	assert_true(actor.begin_navigation_yield(Vector3(2, 0, 0)))
	recovery._active.append({"requester": weakref(requester), "blocker": weakref(actor), "origin": Vector3.ZERO, "remaining": 6.0})
	requester.free()
	recovery._physics_process(0.1)
	assert_false(actor.is_navigation_yielding())
	assert_false(recovery.is_physics_processing())
	recovery.free()
