extends GutTest

const SLOT_SYSTEM = preload("res://features/combat/sim/game_combat_slot_system.gd")
const COMPONENTS := [
	preload("res://features/actors/sim/c_game_actor_identity.gd"),
	preload("res://features/actors/sim/c_game_actor_spatial.gd"),
	preload("res://features/actors/sim/c_game_actor_vitals.gd"),
	preload("res://features/combat/sim/c_game_combat_config.gd"),
	preload("res://features/combat/sim/c_game_combat_state.gd"),
	preload("res://features/combat/sim/c_game_combat_slot_state.gd"),
	preload("res://features/combat/sim/c_game_combat_action.gd"),
	preload("res://features/actors/bridge/c_game_actor_node.gd"),
]

# Only the physical query boundary is replaced. Assignment, reservations, state
# transitions and time run through the production system. Physics has its own tests.
class OpenGroundSlots extends SLOT_SYSTEM:
	func _resolve_position(_actor: Node3D, _target: Node3D, candidate: Vector3, _require_strike: bool) -> Vector3:
		return candidate

	func _can_strike(_actor: Node3D, _target: Node3D) -> bool:
		return true


func _fixture(positions: Array[Vector3]) -> Array:
	var columns: Array = []
	for script in COMPONENTS:
		var column: Array = []
		for index in positions.size():
			column.append(script.new())
		columns.append(column)
	for index in positions.size():
		columns[0][index].actor_id = "fighter_%d" % index
		columns[1][index].world_position = positions[index]
		var actor := Node3D.new()
		add_child_autofree(actor)
		actor.position = positions[index]
		columns[7][index].actor = actor
		if index > 0:
			columns[4][index].system_target_actor_id = "fighter_0"
	return columns


func test_rear_attacker_keeps_assigned_side_across_decision_ticks() -> void:
	var system = autofree(OpenGroundSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1.1, 0, 0)])
	system.process([], columns, 0.1)
	var front = columns[5][1]
	var rear = columns[5][2]
	assert_ne(front.slot_index, rear.slot_index, "The two attackers need separate assignments")
	var assigned_axis: Vector3 = rear.pair_axis
	for tick in range(4):
		system.process([], columns, 0.1)
	assert_eq(rear.pair_axis, assigned_axis, "Measuring current direction must not erase the assigned flank")
	assert_false(front.pair_axis.is_equal_approx(rear.pair_axis), "Separate slot IDs must remain separate destinations")


func test_approaching_attackers_reserve_sides_before_reaching_melee() -> void:
	var system = autofree(OpenGroundSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(3, 0, 0), Vector3(4, 0, 0)])
	for tick in range(4):
		system.process([], columns, 0.1)
	var front = columns[5][1]
	var rear = columns[5][2]
	assert_gte(front.slot_index, 0, "Approach needs an assigned position, not target-center chasing")
	assert_gte(rear.slot_index, 0)
	assert_gt(front.slot_position.distance_to(rear.slot_position), 0.9)
	assert_ne(front.slot_state, 3, "Being assigned is not being in position to fight")
	assert_ne(rear.slot_state, 3)


func test_rear_attacker_cannot_fight_before_reaching_its_side() -> void:
	var system = autofree(OpenGroundSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(1, 0, 0), Vector3(1.1, 0, 0)])
	for tick in range(4):
		system.process([], columns, 0.1)
	assert_eq(columns[5][1].slot_state, 3, "The well-positioned front fighter can stay engaged")
	assert_ne(columns[5][2].slot_state, 3, "The rear fighter must first reach a clear position")


func test_reposition_after_target_moves_does_not_repeat_old_flank_angle() -> void:
	var system = autofree(OpenGroundSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(3, 0, 0), Vector3(1, 0, 0)])
	# A stationary body forces a real side reservation, not an injected cursor.
	columns[4][2].system_target_actor_id = ""
	system.process([], columns, 0.1)
	var slot = columns[5][1]
	assert_true(slot.position_valid)
	assert_gt(absf(slot.slot_position.z), 0.5, "Occupied front requires a flank")
	columns[7][2].actor.queue_free()
	await get_tree().process_frame
	# Once the opponent moves, a fresh approach must prefer the now-open near
	# side. Reapplying the old angle to the NEW bearing drives reciprocal orbits.
	columns[1][0].world_position = Vector3(-1, 0, 0)
	system.process([], columns, 0.1)
	assert_almost_eq(slot.slot_position, Vector3.ZERO, Vector3.ONE * 0.001, "A completed flank is a world position, not a permanent circling preference")


func test_clear_fighting_position_can_settle_without_finishing_obsolete_flank() -> void:
	var system = autofree(OpenGroundSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(3, 0, 0), Vector3(1, 0, 0)])
	columns[4][2].system_target_actor_id = ""
	system.process([], columns, 0.1)
	assert_gt(absf(columns[5][1].slot_position.z), 0.5)
	columns[7][2].actor.queue_free()
	await get_tree().process_frame
	# A moving exchange has already brought this fighter to an unobstructed,
	# correctly spaced strike position. Do not keep chasing the old flank.
	columns[1][1].world_position = Vector3(1, 0, 0)
	system.process([], columns, 0.1)
	assert_almost_eq(columns[5][1].slot_position, Vector3(1, 0, 0), Vector3.ONE * 0.001)
	assert_eq(columns[5][1].slot_state, 3)


func test_target_destruction_releases_live_position_immediately() -> void:
	var system = autofree(OpenGroundSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(1, 0, 0)])
	system.process([], columns, 0.1)
	assert_true(columns[5][1].position_valid)
	columns[7][0].actor.queue_free()
	await get_tree().process_frame
	system.process([], columns, 0.1)
	assert_false(columns[5][1].position_valid, "LOD removal must release the reservation")
	assert_eq(columns[5][1].slot_state, 0)


func test_five_attackers_keep_three_attack_reservations_and_separate_waiting_space() -> void:
	var system = autofree(OpenGroundSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(3, 0, 0), Vector3(4, 0, 0), Vector3(5, 0, 0), Vector3(6, 0, 0), Vector3(7, 0, 0)])
	for tick in range(12):
		system.process([], columns, 0.1)
	var active := 0
	var waiting := 0
	for index in range(1, 6):
		var slot = columns[5][index]
		assert_true(slot.position_valid)
		active += int(slot.slot_index >= 0)
		waiting += int(slot.slot_state == 4)
		for other in range(1, index):
			assert_gte(slot.slot_position.distance_to(columns[5][other].slot_position), 0.9)
	assert_eq(active, 3)
	assert_eq(waiting, 2)


func test_unrealized_alive_record_does_not_occupy_combat_space() -> void:
	var system = autofree(OpenGroundSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(3, 0, 0), Vector3(1, 0, 0)])
	columns[4][2].system_target_actor_id = ""
	columns[7][2].actor.queue_free()
	await get_tree().process_frame
	system.process([], columns, 0.1)
	assert_almost_eq(columns[5][1].slot_position, Vector3(1, 0, 0), Vector3.ONE * 0.001, "Durable records without bodies must not evict a valid front position")


func test_small_target_drift_leaves_arrival_margin_inside_strike_range() -> void:
	var system = autofree(OpenGroundSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(3, 0, 0)])
	system.process([], columns, 0.1)
	columns[1][0].world_position = Vector3(-0.1, 0, 0)
	for tick in range(8):
		system.process([], columns, 0.1)
	var slot = columns[5][1]
	assert_true(slot.position_valid)
	assert_lte(slot.slot_position.distance_to(columns[1][0].world_position) + WorldActor.COMBAT_ARRIVAL_DISTANCE, 1.12, "Even a sub-repath target movement cannot leave a stopped fighter outside attack range")


class BlockedSlots extends OpenGroundSlots:
	var query_count := 0
	func _resolve_position(_actor: Node3D, _target: Node3D, _candidate: Vector3, _require_strike: bool) -> Vector3:
		query_count += 1
		return Vector3.INF


func test_unreachable_positions_stop_and_bound_queries_instead_of_direct_chasing() -> void:
	var system = autofree(BlockedSlots.new())
	var columns := _fixture([Vector3.ZERO, Vector3(3, 0, 0), Vector3(4, 0, 0), Vector3(5, 0, 0)])
	system.process([], columns, 0.3)
	assert_lte(system.query_count, SLOT_SYSTEM.MAX_POSITION_QUERIES_PER_FRAME)
	for index in range(1, 4):
		assert_false(columns[5][index].position_valid)
		assert_ne(columns[5][index].slot_state, 3)
