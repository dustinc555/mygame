extends GutTest

class QuietActor extends WorldActor:
	func _enter_tree() -> void:
		pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		navigation_path_height_offset = 0.0
		_navigation_agent.configure()

class QuietInteraction extends WorldInteractionController:
	func _ready() -> void:
		set_process(false)

class HeldBatch extends "res://features/core/navigation/navigation_query_jobs.gd".Batch:
	var gate: Semaphore
	func run() -> void:
		gate.wait()
		super.run()

class HeldQueries extends "res://features/core/navigation/navigation_query_jobs.gd":
	var gate := Semaphore.new()
	func _new_batch() -> Batch:
		var batch := HeldBatch.new()
		batch.gate = gate
		return batch

var _viewport: SubViewport
var _root: Node3D
var _navigation: WorldNavigationController
var _actor: QuietActor
var _region: NavigationRegion3D

func before_each() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	add_child(_viewport)
	_root = Node3D.new()
	_viewport.add_child(_root)
	_navigation = WorldNavigationController.new()
	_navigation.settings = WorldNavigationSettings.new()
	_root.add_child(_navigation)
	_navigation.set_process(false)
	_region = NavigationRegion3D.new()
	NavigationServer3D.region_set_use_async_iterations(_region.get_rid(), false)
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-10, 0, -10), Vector3(-10, 0, 10), Vector3(10, 0, 10), Vector3(10, 0, -10)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	_region.navigation_mesh = mesh
	_root.add_child(_region)
	var map := _root.get_world_3d().navigation_map
	NavigationServer3D.map_set_use_async_iterations(map, false)
	NavigationServer3D.map_force_update(map)
	_actor = QuietActor.new()
	_actor.position = Vector3(-4, 0, 0)
	_root.add_child(_actor)

func after_each() -> void:
	_viewport.queue_free()
	await get_tree().process_frame

func _wait_direction() -> Vector3:
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		var direction: Vector3 = _actor._navigation_agent.get_move_direction(0.016)
		if not direction.is_zero_approx() or not _actor.has_move_target():
			return direction
		await get_tree().process_frame
	fail_test("Async route did not complete")
	return Vector3.ZERO

func test_live_follower_defers_path_query_instead_of_blocking_order_frame() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	var follower = _actor._navigation_agent
	assert_eq(follower.get_move_direction(0.016), Vector3.ZERO, "First call queues work; it must not synchronously find a path")
	assert_true(_actor.has_move_target(), "Waiting for a worker is not an unreachable destination")
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	assert_eq(follower.get_navigation_map(), _root.get_world_3d().navigation_map, "Threaded queries do not clone and force-rebuild navigation maps")

func test_combat_follower_uses_movement_lane_without_claiming_player_priority() -> void:
	_actor.set_system_movement_bridge(1, true, Vector3(4, 0, 0), Vector3.ZERO, Vector3(4, 0, 0), false, 42)
	_actor._prepare_combat_navigation(0.05)
	var follower = _actor._navigation_agent
	follower.get_move_direction(0.016)
	var queued: Dictionary = _navigation.query_jobs._pending.get(str(follower.get_instance_id()), {})
	assert_false(queued.is_empty())
	assert_true(queued.get("request", {}).get("movement_route", false), "Actual pursuit must not queue as a tactical position search")
	assert_false(queued.get("request", {}).get("player_order", true), "NPC movement must leave player priority intact")
	assert_eq(await _wait_direction(), Vector3.RIGHT)

func test_retarget_and_removal_discard_inflight_route() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	_actor._navigation_agent.get_move_direction(0.016)
	_actor.set_move_target(Vector3(-4, 0, 6))
	assert_almost_eq(await _wait_direction(), Vector3.BACK, Vector3.ONE * 0.001)
	_root.remove_child(_actor)
	_root.add_child(_actor)
	assert_almost_eq(await _wait_direction(), Vector3.BACK, Vector3.ONE * 0.001, "Reentry reacquires the retained destination")

func test_removed_provider_falls_back_to_native_with_current_destination() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_navigation.free()
	_actor.set_move_target(Vector3(-4, 0, 6))
	assert_almost_eq(await _wait_direction(), Vector3.BACK, Vector3.ONE * 0.001, "Native fallback must resynchronize, not reuse an obsolete target")

func test_provider_removal_without_new_order_resynchronizes_native_target() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_navigation.free()
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	assert_almost_eq(_actor._navigation_agent.get_final_position(), Vector3(4, 0, 0), Vector3.ONE * 0.001)

func test_map_change_invalidates_completed_path_and_rejects_disconnected_target() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_region.enabled = false
	NavigationServer3D.map_force_update(_root.get_world_3d().navigation_map)
	assert_eq(await _wait_direction(), Vector3.ZERO)
	assert_false(_actor.has_move_target())

func test_changing_layers_cannot_reuse_old_path() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor._navigation_agent.navigation_layers = 2
	assert_eq(await _wait_direction(), Vector3.ZERO)
	assert_false(_actor.has_move_target())

func test_same_destination_does_not_queue_repeated_worker_queries() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	var serial: int = _navigation.query_jobs._serial
	for tick in range(20):
		_actor.set_move_target(Vector3(4, 0, 0))
		assert_eq(_actor._navigation_agent.get_move_direction(0.016), Vector3.RIGHT)
	assert_eq(_navigation.query_jobs._serial, serial)

func test_changed_orders_keep_following_valid_route_while_replacement_is_pending() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	# Do not yield: replacement work cannot have been pumped or published yet.
	# Moving the held cursor must change the order without stopping the actor.
	for step in range(6):
		_actor.set_move_target(Vector3(4, 0, 1 + step))
		assert_eq(_actor._navigation_agent.get_move_direction(0.016), Vector3.RIGHT,
			"Keep the accepted route while calculating the new destination")
	assert_eq(_actor.get_move_target(), Vector3(4, 0, 6))

func test_changing_held_input_consumes_completed_turn_before_requesting_next() -> void:
	var party := PartyManager.new()
	_root.add_child(party)
	party.selected_members = [_actor]
	var dispatcher := QuietInteraction.new()
	dispatcher.party_manager = party
	_root.add_child(dispatcher)
	dispatcher.issue_move_command_at_world(Vector3(4, 0, 0), false)
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	dispatcher.issue_move_command_at_world(Vector3(-4, 0, 6), false)
	var follower = _actor._navigation_agent
	follower.get_move_direction(0.016)
	for step in range(8):
		await _wait_query_ready()
		var latest := Vector3(-4.0 + (step + 1) * 0.1, 0, 6)
		dispatcher.issue_move_command_at_world(latest, false, Vector3.UP, true)
		var direction: Vector3 = follower.get_move_direction(0.016)
		assert_gt(direction.z, 0.9, "Turn while the held cursor is still changing, not only after release")
		assert_eq(_actor.get_move_target(), latest, "A useful earlier route must not replace the newest destination")
	var queued: Dictionary = _navigation.query_jobs._pending.get(str(follower.get_instance_id()), {})
	assert_false(queued.is_empty(), "The latest held correction is queued after accepting the earlier turn")
	assert_true(queued.get("request", {}).get("player_order", false), "Direct orders use the player's reserved query capacity")

func test_held_updates_do_not_cancel_a_useful_unfinished_worker() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_navigation.query_jobs.close()
	var jobs := HeldQueries.new()
	_navigation.query_jobs = jobs
	_actor._navigation_agent._query_jobs = jobs
	_actor.set_move_target(Vector3(-4, 0, 6))
	var follower = _actor._navigation_agent
	follower.get_move_direction(0.016)
	jobs.pump()
	var ticket: int = follower._query_ticket
	for step in range(8):
		_actor.set_move_target(Vector3(-4.0 + (step + 1) * 0.1, 0, 6), true, true)
		follower.get_move_direction(0.016)
		assert_eq(follower._query_ticket, ticket, "Held steering must not continually restart unfinished work")
	for index in range(16):
		jobs.gate.post()
	await _wait_query_ready()
	assert_gt(follower.get_move_direction(0.016).z, 0.9)
	assert_eq(_actor.get_move_target(), Vector3(-3.2, 0, 6))

func test_held_reversal_discards_a_completed_opposing_turn() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(-4, 0, 6), true, true)
	_actor._navigation_agent.get_move_direction(0.016)
	await _wait_query_ready()
	_actor.set_move_target(Vector3(-4, 0, -6), true, true)
	assert_eq(_actor._navigation_agent.get_move_direction(0.016), Vector3.RIGHT)
	assert_almost_eq(await _wait_replacement_direction(), Vector3.FORWARD, Vector3.ONE * 0.001)

func test_unreachable_earlier_held_goal_does_not_fail_latest_reachable_goal() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(30, 0, 0))
	_actor._navigation_agent.get_move_direction(0.016)
	await _wait_query_ready()
	_actor.set_move_target(Vector3(6, 0, 6), true, true)
	_actor._navigation_agent.get_move_direction(0.016)
	assert_true(_actor.has_move_target())
	assert_gt((await _wait_replacement_direction()).z, 0.4)

func test_recovery_progress_uses_advanced_worker_waypoint() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	var follower = _actor._navigation_agent
	follower._handle_stuck()
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.position.x = -2.0
	assert_true(follower._has_made_stuck_progress(), "Recovery must measure distance to the next waypoint, not the abandoned start")

func test_retained_route_end_does_not_steer_to_unqueried_destination() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	var follower = _actor._navigation_agent
	_actor.set_move_target(Vector3(4, 0, 6))
	assert_eq(follower.get_move_direction(0.016), Vector3.RIGHT)
	_actor.position = Vector3(4, 0, 0)
	assert_eq(follower.get_move_direction(0.016), Vector3.ZERO,
		"The old route proves no access beyond its endpoint")
	assert_true(_actor.has_move_target(), "Waiting at the old endpoint must not finish the new order")

func test_combat_pursuit_consumes_ready_path_while_same_opponent_keeps_moving() -> void:
	_actor.set_system_movement_bridge(1, true, Vector3(4, 0, 0), Vector3.ZERO, Vector3(4, 0, 0), false, 42)
	_actor._prepare_combat_navigation(0.05)
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_system_movement_bridge(2, true, Vector3(4, 0, 5), Vector3.ZERO, Vector3(4, 0, 5), false, 42)
	_actor._prepare_combat_navigation(0.05)
	var follower = _actor._navigation_agent
	follower.get_move_direction(0.016)
	await _wait_query_ready()
	var ticket: int = follower._query_ticket
	_actor.set_system_movement_bridge(3, true, Vector3(4, 0, 6), Vector3.ZERO, Vector3(4, 0, 6), false, 42)
	_actor._prepare_combat_navigation(0.05)
	assert_eq(follower._query_ticket, ticket, "A moving opponent must not cancel useful pursuit work")
	assert_gt(follower.get_move_direction(0.016).z, 0.4, "The pursuer must turn before the opponent stops")

func test_replacing_combat_opponent_discards_old_pending_route() -> void:
	_actor.set_system_movement_bridge(1, true, Vector3(4, 0, 5), Vector3.ZERO, Vector3(4, 0, 5), false, 42)
	_actor._prepare_combat_navigation(0.05)
	_actor._navigation_agent.get_move_direction(0.016)
	await _wait_query_ready()
	_actor.set_system_movement_bridge(2, true, Vector3(4, 0, 6), Vector3.ZERO, Vector3(4, 0, 6), false, 43)
	_actor._prepare_combat_navigation(0.05)
	assert_eq(_actor._navigation_agent._query_ticket, 0, "Another opponent is a new command, not a continuation")

func test_moving_opponent_cannot_postpone_blocked_pursuer_recovery() -> void:
	_actor.stuck_check_seconds = 0.5
	_actor.stuck_repath_attempt_limit = 1
	var follower = _actor._navigation_agent
	for step in range(8):
		var target := Vector3(4, 0, 1.0 + step * 0.1)
		_actor.set_system_movement_bridge(step + 1, true, target, Vector3.ZERO, target, false, 42)
		_actor._prepare_combat_navigation(0.25)
		var direction := await _wait_replacement_direction()
		# Paths finish normally, but a physical obstruction prevents this body
		# from advancing. Only the opponent moves; this is not actor progress.
		follower.update_stuck_state(0.25, direction)
		if _actor.has_combat_navigation_failed():
			break
	assert_true(_actor.has_combat_navigation_failed(), "Report the blocked approach after bounded retries even while the same opponent moves")

func test_native_pursuit_keeps_recovery_deadline_when_opponent_approaches() -> void:
	_navigation.free()
	_actor.stuck_check_seconds = 0.5
	_actor.stuck_repath_attempt_limit = 1
	for step in range(8):
		var target := Vector3(4.0 - step * 0.2, 0, 1)
		_actor.set_system_movement_bridge(step + 1, true, target, Vector3.ZERO, target, false, 42)
		_actor._prepare_combat_navigation(0.25)
		var direction := await _wait_replacement_direction()
		_actor._navigation_agent.update_stuck_state(0.25, direction)
		if _actor.has_combat_navigation_failed():
			break
	assert_true(_actor.has_combat_navigation_failed(), "A new native route or an approaching opponent cannot masquerade as body progress")

func test_continually_replaced_pursuit_routes_do_not_bypass_retry_limit() -> void:
	_actor.stuck_check_seconds = 0.5
	_actor.stuck_repath_attempt_limit = 1
	var follower = _actor._navigation_agent
	for step in range(8):
		var target := Vector3(4, 0, 1.0 + step * 0.2)
		_actor.set_system_movement_bridge(step * 2 + 1, true, target, Vector3.ZERO, target, false, 42)
		_actor._prepare_combat_navigation(0.25)
		follower.get_move_direction(0.016)
		await _wait_query_ready()
		# The opponent steps again before the ready path is consumed. Every
		# accepted path is useful, but trails the newest goal during pursuit.
		target.z += 0.1
		_actor.set_system_movement_bridge(step * 2 + 2, true, target, Vector3.ZERO, target, false, 42)
		_actor._prepare_combat_navigation(0.0)
		var direction: Vector3 = follower.get_move_direction(0.016)
		follower.update_stuck_state(0.25, direction)
		if _actor.has_combat_navigation_failed():
			break
	assert_true(_actor.has_combat_navigation_failed(), "Pending corrections must not give a blocked pursuit unlimited retries")

func test_held_destination_updates_keep_blocked_order_recovery_bounded() -> void:
	_actor.stuck_check_seconds = 0.5
	_actor.stuck_repath_attempt_limit = 1
	for step in range(8):
		_actor.set_move_target(Vector3(4, 0, 1.0 + step * 0.1), true, true)
		var direction := await _wait_replacement_direction()
		_actor._navigation_agent.update_stuck_state(0.25, direction)
		if not _actor.has_move_target():
			break
	assert_false(_actor.has_move_target(), "Repeated held destinations must not indefinitely reset blocked-order recovery")

func test_clear_command_discards_pending_result() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(-4, 0, 6))
	assert_eq(_actor._navigation_agent.get_move_direction(0.016), Vector3.RIGHT)
	var jobs = _navigation.query_jobs
	_actor.stop_movement()
	for tick in range(4):
		await get_tree().process_frame
	assert_false(_actor.has_move_target())
	assert_true(_actor._navigation_agent._async_path.is_empty())
	assert_true(jobs._tickets.is_empty())
	assert_true(jobs._ready.is_empty())

func _wait_replacement_direction() -> Vector3:
	var follower = _actor._navigation_agent
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		var direction: Vector3 = follower.get_move_direction(0.016)
		if (follower._query_ticket == 0 and follower._target_synced) or not _actor.has_move_target():
			return direction
		await get_tree().process_frame
	fail_test("Replacement route did not complete")
	return Vector3.ZERO

func test_replacement_starts_from_current_progress_not_old_query_start() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(8, 0, 0))
	_actor._navigation_agent.get_move_direction(0.016)
	# Simulate travel during the worker request, before it can be published.
	_actor.position.x = -2.0
	assert_eq(await _wait_replacement_direction(), Vector3.RIGHT,
		"A completed route must not send the moving actor back to its old start")

func _wait_query_ready() -> void:
	var key := str(_actor._navigation_agent.get_instance_id())
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		_navigation.query_jobs.pump()
		if _navigation.query_jobs._ready.has(key):
			return
		await get_tree().process_frame
	fail_test("Worker result was not published")

func test_route_from_abandoned_start_is_requeried_without_backtracking() -> void:
	_actor.set_move_target(Vector3(8, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(-4, 0, 6))
	_actor._navigation_agent.get_move_direction(0.016)
	_actor.position.x = -1.0
	await _wait_query_ready()
	assert_eq(_actor._navigation_agent.get_move_direction(0.016), Vector3.ZERO,
		"Brake rather than backtrack, cut a corner or outrun every replacement")
	assert_almost_eq(await _wait_replacement_direction(), Vector3(-3, 0, 6).normalized(), Vector3.ONE * 0.001,
		"Requery from the current position without following the abandoned route")

func test_blocked_retained_route_does_not_cancel_pending_new_order() -> void:
	_actor.stuck_repath_attempt_limit = 0
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(-4, 0, 6))
	var follower = _actor._navigation_agent
	follower.get_move_direction(0.016)
	follower._handle_stuck()
	assert_true(_actor.has_move_target(), "A blocked old route does not prove a fresh command unreachable, even with retries disabled")
	assert_eq(follower.get_move_direction(0.016), Vector3.ZERO, "Stop using the blocked old route")
	assert_almost_eq(await _wait_replacement_direction(), Vector3.BACK, Vector3.ONE * 0.001)

func test_late_route_cannot_keep_the_actor_running_away_from_every_replacement() -> void:
	_actor.set_move_target(Vector3(8, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(-4, 0, 6))
	var follower = _actor._navigation_agent
	var turned := false
	for completion in range(4):
		var direction: Vector3 = follower.get_move_direction(0.016)
		# Advance only along the actual requested direction while the worker runs.
		_actor.position += direction * 1.28
		await _wait_query_ready()
		direction = follower.get_move_direction(0.016)
		if direction.z > 0.5:
			turned = true
			break
	assert_true(turned, "A late path must not create endless old-route/requery motion")

func test_ready_replacement_cannot_override_a_newer_order() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(-4, 0, 6))
	_actor._navigation_agent.get_move_direction(0.016)
	await _wait_query_ready()
	_actor.set_move_target(Vector3(-4, 0, -6))
	assert_eq(_actor._navigation_agent.get_move_direction(0.016), Vector3.RIGHT,
		"Discard the completed but superseded turn; retain the accepted route")
	assert_almost_eq(await _wait_replacement_direction(), Vector3.FORWARD, Vector3.ONE * 0.001)

func test_map_invalidation_discards_retained_route_during_replacement() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(-4, 0, 6))
	_actor._navigation_agent.get_move_direction(0.016)
	_region.enabled = false
	NavigationServer3D.map_force_update(_root.get_world_3d().navigation_map)
	assert_eq(await _wait_replacement_direction(), Vector3.ZERO)
	assert_false(_actor.has_move_target())

func test_layer_change_discards_retained_route_during_replacement() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(-4, 0, 6))
	_actor._navigation_agent.get_move_direction(0.016)
	_actor._navigation_agent.navigation_layers = 2
	assert_eq(await _wait_replacement_direction(), Vector3.ZERO)
	assert_false(_actor.has_move_target())

func test_provider_removal_during_replacement_uses_latest_native_target() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(-4, 0, 6))
	_actor._navigation_agent.get_move_direction(0.016)
	_navigation.free()
	assert_almost_eq(await _wait_direction(), Vector3.BACK, Vector3.ONE * 0.001)
	assert_true(_actor._navigation_agent._async_path.is_empty())

func test_unreachable_replacement_finishes_without_reusing_old_endpoint() -> void:
	_actor.set_move_target(Vector3(4, 0, 0))
	assert_eq(await _wait_direction(), Vector3.RIGHT)
	_actor.set_move_target(Vector3(30, 0, 0))
	assert_eq(_actor._navigation_agent.get_move_direction(0.016), Vector3.RIGHT)
	assert_eq(await _wait_replacement_direction(), Vector3.ZERO)
	assert_false(_actor.has_move_target())
