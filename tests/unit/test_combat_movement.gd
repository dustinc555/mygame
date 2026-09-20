extends GutTest

const ACTOR = preload("res://features/actors/bridge/world_actor.gd")

func _actor() -> WorldActor:
	var actor := ACTOR.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = CapsuleShape3D.new()
	actor.add_child(collision)
	add_child_autofree(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.gravity = 0.0
	return actor


func test_combat_submits_destination_to_existing_navigation_not_supplied_velocity() -> void:
	var actor := _actor()
	var destination := Vector3(4, 0, 0)
	actor.set_system_movement_bridge(0, true, destination, Vector3(0, 0, 9), destination, false, 0)
	actor.process_world_actor_movement(0.016)
	assert_true(actor.has_move_target(), "Combat must use the actor's ordinary navigation target")
	assert_eq(actor.get_move_target(), destination)
	assert_almost_eq(actor.velocity.z, 0.0, 0.001, "No raw combat velocity may bypass an unavailable path")
	assert_false(actor.has_active_player_order(), "Combat travel must not suppress its own targeting")


func test_player_move_keeps_priority_over_combat_destination() -> void:
	var actor := _actor()
	actor.set_move_target(Vector3(5, 0, 0), true)
	actor.set_system_movement_bridge(0, true, Vector3(-5, 0, 0), Vector3(-4, 0, 0), Vector3(-5, 0, 0), false, 0)
	actor.process_world_actor_movement(0.016)
	assert_eq(actor.get_move_target(), Vector3(5, 0, 0))
	assert_true(actor.has_active_player_order())


func test_persistence_does_not_restore_transient_combat_navigation() -> void:
	var actor := _actor()
	actor.set_system_movement_bridge(0, true, Vector3(5, 0, 0), Vector3.ZERO, Vector3(6, 0, 0), false, 0)
	actor.process_world_actor_movement(0.016)
	var saved := actor.get_persistent_movement_state()
	assert_true(actor.has_move_target(), "Doors and movement still see the live combat route")
	assert_false(saved.has_move_target, "Combat positions cannot become standalone orders after LOD/load")
	var restored := _actor()
	restored.apply_population_runtime_state({}, saved)
	assert_false(restored.has_move_target())
	actor.set_move_target(Vector3(8, 0, 0), true)
	var player_saved := actor.get_persistent_movement_state()
	restored.apply_population_runtime_state({}, player_saved)
	assert_true(restored.has_move_target())
	assert_true(restored.has_active_player_order())
	assert_eq(restored.get_move_target(), Vector3(8, 0, 0))


func test_movement_intent_uses_reserved_destination_and_moves_waiting_fighters() -> void:
	var actor := _actor()
	var target := _actor()
	target.position = Vector3(4, 0, 0)
	var system = autofree(load("res://features/combat/sim/game_combat_movement_system.gd").new())
	var scripts := [
		"res://features/actors/bridge/c_game_actor_node.gd",
		"res://features/actors/sim/c_game_actor_identity.gd",
		"res://features/actors/sim/c_game_actor_spatial.gd",
		"res://features/actors/sim/c_game_actor_vitals.gd",
		"res://features/combat/sim/c_game_combat_config.gd",
		"res://features/combat/sim/c_game_combat_action.gd",
		"res://features/combat/sim/c_game_combat_slot_state.gd",
		"res://features/actors/sim/c_game_movement_state.gd",
	]
	var columns: Array = []
	for path in scripts:
		columns.append([load(path).new(), load(path).new()])
	columns[0][0].actor = actor
	columns[0][1].actor = target
	columns[1][0].actor_id = "attacker"
	columns[1][1].actor_id = "target"
	columns[2][1].world_position = target.position
	var slot = columns[6][0]
	slot.slot_target_actor_id = "target"
	slot.slot_state = 4
	slot.position_valid = true
	slot.slot_position = Vector3(4, 0, 2)
	system.process([], columns, 0.05)
	assert_eq(columns[7][0].move_target_position, slot.slot_position)
	assert_false(columns[7][0].combat_settled, "Waiting fighters must first travel to their waiting position")
	assert_eq(columns[7][0].desired_velocity, Vector3.ZERO, "Combat supplies intent, never an alternate velocity")
