extends GutTest

class QuietActor extends WorldActor:
	func _enter_tree() -> void:
		pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

const COMPONENTS := [
	preload("res://features/actors/bridge/c_game_actor_node.gd"),
	preload("res://features/actors/sim/c_game_actor_identity.gd"),
	preload("res://features/actors/sim/c_game_actor_spatial.gd"),
	preload("res://features/actors/sim/c_game_actor_vitals.gd"),
	preload("res://features/combat/sim/c_game_combat_config.gd"),
	preload("res://features/combat/sim/c_game_combat_action.gd"),
	preload("res://features/combat/sim/c_game_combat_slot_state.gd"),
	preload("res://features/actors/sim/c_game_movement_state.gd"),
]

func _fixture() -> Array:
	var data: Array = []
	for script in COMPONENTS:
		data.append([script.new(), script.new()])
	for i in range(2):
		var actor := QuietActor.new()
		add_child_autofree(actor)
		actor.position = Vector3(float(i) * 8.0, 0, 0)
		data[0][i].actor = actor
		data[1][i].actor_id = "fighter_%d" % i
		data[2][i].world_position = actor.position
	data[6][0].slot_target_actor_id = "fighter_1"
	data[6][0].slot_state = CGameCombatSlotState.FightState.MOVE_TO_TARGET
	return data

func test_missing_fight_position_does_not_stop_safe_pursuit() -> void:
	var data := _fixture()
	var system := GameCombatMovementSystem.new()
	add_child_autofree(system)
	system.process([], data, 0.05)
	var movement = data[7][0]
	assert_true(movement.system_movement_active)
	assert_false(movement.combat_settled, "Waiting for a strike position must not prevent travel toward the opponent")
	assert_eq(movement.move_target_position, Vector3(8, 0, 0))
	assert_false(data[6][0].position_valid, "A pursuit destination is not permission to strike")
	assert_ne(data[6][0].slot_state, CGameCombatSlotState.FightState.FIGHTING)
	assert_false(data[0][0].actor._system_move_settled)

func test_reserved_fight_position_stays_the_destination() -> void:
	var data := _fixture()
	data[6][0].position_valid = true
	data[6][0].slot_position = Vector3(7, 0, 1)
	var system := GameCombatMovementSystem.new()
	add_child_autofree(system)
	system.process([], data, 0.05)
	assert_eq(data[7][0].move_target_position, Vector3(7, 0, 1))
	assert_false(data[7][0].combat_settled)

func test_attack_animation_and_hit_reaction_still_stop_pursuit() -> void:
	var data := _fixture()
	var system := GameCombatMovementSystem.new()
	add_child_autofree(system)
	data[5][0].action_active = true
	system.process([], data, 0.05)
	assert_true(data[7][0].combat_settled)
	data[5][0].action_active = false
	data[5][0].reaction_remaining = 0.2
	system.process([], data, 0.05)
	assert_true(data[7][0].combat_settled)

func test_dead_target_releases_movement() -> void:
	var data := _fixture()
	data[3][1].life_state = NpcRules.LifeState.DEAD
	var system := GameCombatMovementSystem.new()
	add_child_autofree(system)
	system.process([], data, 0.05)
	assert_false(data[7][0].system_movement_active)
	assert_false(data[0][0].actor._system_move_active)
