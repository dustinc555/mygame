extends GutTest

const INTERACTION = preload("res://features/actors/bridge/capabilities/interaction_capability.gd")

class Walker extends Node3D:
	signal state_changed
	signal inventory_changed
	var life_state := NpcRules.LifeState.ALIVE
	var moving := false
	var moves := 0
	var target := Vector3.ZERO
	var velocity := Vector3.ZERO
	var running := false
	func _set_actor_move_target(point: Vector3) -> void:
		moving = true
		target = point
		moves += 1
	func _clear_actor_move_target() -> void: moving = false
	func has_move_target() -> bool: return moving
	func requires_fire_to_die() -> bool: return false
	func begin_seated_visual(_point: Vector3, _rotation: Vector3) -> void: pass
	func _get_move_target_arrival_distance() -> float: return 0.2

class Seat extends Node3D:
	var searches := 0
	var blocked := false
	var sitter: Node
	func get_interaction_position(_actor: Node) -> Vector3: return global_position + Vector3.RIGHT
	func get_safe_stand_position(member: Node) -> Vector3:
		searches += 1
		return Vector3.INF if blocked else get_interaction_position(member)
	func claim_sitter(member: Node) -> bool:
		if is_instance_valid(sitter) and sitter != member: return false
		sitter = member
		return true
	func release_sitter(member: Node) -> void:
		if sitter == member: sitter = null
	func get_seat_position(_actor: Node) -> Vector3: return global_position
	func get_seat_rotation(_actor: Node) -> Vector3: return global_rotation

class MappedInteraction extends InteractionCapability:
	var test_map := RID()
	func _seat_navigation_map() -> RID: return test_map

func _fixture() -> Dictionary:
	var actor := Walker.new()
	var seat := Seat.new()
	add_child_autofree(actor)
	add_child_autofree(seat)
	seat.position = Vector3(10, 0, 0)
	var interaction = INTERACTION.new()
	interaction.setup(actor)
	seat.claim_sitter(actor)
	return {"actor": actor, "seat": seat, "interaction": interaction}

func test_unchanged_approach_solves_once_without_resetting_movement_or_order() -> void:
	var f := _fixture()
	watch_signals(f.interaction)
	for refresh in 20:
		f.interaction.assign_seat_target(f.seat, false)
	assert_eq(f.seat.searches, 1)
	assert_eq(f.actor.moves, 1)
	assert_signal_emit_count(f.interaction, "order_changed", 1)
	assert_eq(f.interaction.current_seat_stand_position, Vector3(11, 0, 0))
	assert_eq(f.actor.position, Vector3.ZERO, "Approach must not teleport the body")

func test_player_can_take_ownership_without_resolving_same_approach() -> void:
	var f := _fixture()
	f.interaction.assign_seat_target(f.seat, false)
	f.interaction.assign_seat_target(f.seat, true)
	f.interaction.assign_seat_target(f.seat, false)
	assert_true(f.interaction.order_was_player_issued)
	assert_eq(f.seat.searches, 1)

func test_moved_seat_revalidates_before_continuing() -> void:
	var f := _fixture()
	f.interaction.assign_seat_target(f.seat, false)
	f.seat.position.x += 3.0
	f.interaction.assign_seat_target(f.seat, false)
	assert_eq(f.seat.searches, 2)
	assert_eq(f.actor.target, Vector3(14, 0, 0))
	assert_eq(f.seat.sitter, f.actor, "Revalidation must preserve an existing reservation")

func test_failed_movement_revalidates_instead_of_reusing_stale_approach() -> void:
	var f := _fixture()
	f.interaction.assign_seat_target(f.seat, false)
	f.actor.moving = false
	f.seat.blocked = true
	f.interaction.assign_seat_target(f.seat, false)
	assert_eq(f.seat.searches, 2)
	assert_null(f.interaction.current_seat_target)
	assert_null(f.seat.sitter, "A refused route must release the home's preclaim")
	assert_false(f.actor.moving)

func test_changing_chairs_releases_old_claim_even_during_approach() -> void:
	var f := _fixture()
	f.interaction.assign_seat_target(f.seat, false)
	var second := Seat.new()
	add_child_autofree(second)
	second.position = Vector3(20, 0, 0)
	f.interaction.assign_seat_target(second, false)
	assert_null(f.seat.sitter)
	assert_eq(f.interaction.current_seat_target, second)

func test_combat_interrupt_clears_approach_and_reacquisition_solves_again() -> void:
	var f := _fixture()
	f.interaction.assign_seat_target(f.seat, false)
	f.interaction.begin_combat_order()
	assert_null(f.interaction.current_seat_target)
	assert_null(f.seat.sitter)
	assert_false(f.actor.moving)
	f.interaction.assign_seat_target(f.seat, false)
	assert_eq(f.seat.searches, 2)

func test_queued_seat_is_not_a_valid_new_target() -> void:
	var f := _fixture()
	f.seat.queue_free()
	f.interaction.assign_seat_target(f.seat, false)
	assert_eq(f.seat.searches, 0)
	assert_null(f.interaction.current_seat_target)

func test_teardown_releases_preclaim_and_cached_approach() -> void:
	var f := _fixture()
	f.interaction.assign_seat_target(f.seat, false)
	f.interaction.teardown()
	assert_null(f.seat.sitter)
	assert_null(f.interaction.current_seat_target)

func test_approach_tick_revalidates_moved_chair_without_waiting_for_home_refresh() -> void:
	var f := _fixture()
	f.interaction.assign_seat_target(f.seat, false)
	f.seat.position.z = 4.0
	f.interaction.process_seat_interaction()
	assert_eq(f.seat.searches, 2)
	assert_eq(f.actor.target, Vector3(11, 0, 4))
	assert_false(f.interaction.is_sitting)

func test_freed_chair_clears_order_and_replacement_gets_new_search() -> void:
	var f := _fixture()
	f.interaction.assign_seat_target(f.seat, false)
	f.seat.free()
	f.interaction.process_seat_interaction()
	assert_null(f.interaction.current_seat_target)
	assert_false(f.actor.moving)
	var replacement := Seat.new()
	add_child_autofree(replacement)
	f.interaction.assign_seat_target(replacement, false)
	assert_eq(replacement.searches, 1)

func test_replaced_navigation_map_invalidates_approach() -> void:
	var f := _fixture()
	var interaction := MappedInteraction.new()
	interaction.setup(f.actor)
	interaction.assign_seat_target(f.seat, false)
	var navigation_map := NavigationServer3D.map_create()
	interaction.test_map = navigation_map
	interaction.assign_seat_target(f.seat, false)
	assert_eq(f.seat.searches, 2)
	interaction.stop_seat_assignment()
	NavigationServer3D.free_rid(navigation_map)

func test_navigation_map_rebuild_invalidates_approach_on_next_tick() -> void:
	var f := _fixture()
	var interaction := MappedInteraction.new()
	interaction.setup(f.actor)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-5, 0, -5), Vector3(5, 0, -5), Vector3(5, 0, 5), Vector3(-5, 0, 5)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	viewport.add_child(region)
	var navigation_map := region.get_world_3d().navigation_map
	NavigationServer3D.map_set_active(navigation_map, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(navigation_map)
	await get_tree().process_frame
	interaction.test_map = navigation_map
	interaction.assign_seat_target(f.seat, false)
	var prior_iteration := NavigationServer3D.map_get_iteration_id(navigation_map)
	region.position.x = 2.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(navigation_map)
	await get_tree().process_frame
	assert_ne(NavigationServer3D.map_get_iteration_id(navigation_map), prior_iteration)
	interaction.process_seat_interaction()
	assert_eq(f.seat.searches, 2)
	interaction.stop_seat_assignment()

func test_seated_refresh_never_searches_or_moves_body() -> void:
	var f := _fixture()
	f.interaction.assign_seat_target(f.seat, false)
	f.actor.position = f.actor.target
	f.interaction.process_seat_interaction()
	assert_true(f.interaction.is_sitting)
	var seated_position: Vector3 = f.actor.position
	f.interaction.assign_seat_target(f.seat, false)
	assert_eq(f.seat.searches, 1)
	assert_eq(f.actor.position, seated_position)

func test_upstairs_seat_requires_vertical_arrival_before_sitting() -> void:
	var f := _fixture()
	f.seat.position = Vector3(0, 3, 0)
	f.actor.position = Vector3(1, 0, 0)
	f.interaction.assign_seat_target(f.seat, false)
	f.interaction.process_seat_interaction()
	assert_false(f.interaction.is_sitting, "An upstairs chair cannot be reached through its floor")
	assert_true(f.actor.moving, "Keep the stair route active")
	f.actor.position.y = 3.0
	f.interaction.process_seat_interaction()
	assert_true(f.interaction.is_sitting, "The same approach completes on the correct floor")

func test_stopped_upstairs_approach_can_retry_despite_matching_horizontal_position() -> void:
	var f := _fixture()
	f.seat.position = Vector3(0, 3, 0)
	f.actor.position = Vector3(1, 0, 0)
	f.interaction.assign_seat_target(f.seat, false)
	f.actor.moving = false
	f.interaction.assign_seat_target(f.seat, false)
	assert_eq(f.seat.searches, 2)
	assert_true(f.actor.moving)
