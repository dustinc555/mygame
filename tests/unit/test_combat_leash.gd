extends GutTest

class QuietActor extends WorldActor:
	func _enter_tree() -> void:
		pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

var _world: World
var _system: GameCombatTargetingSystem
var _data: Array

func before_each() -> void:
	_world = World.new()
	add_child_autofree(_world)
	_system = GameCombatTargetingSystem.new()
	_world.add_system(_system)
	_data = []
	for script in [CGameActorNode, CGameActorIdentity, CGameActorSpatial, CGameActorVitals, CGameActorFaction, CGameCombatConfig, CGameCombatState, CGameCombatSlotState]:
		_data.append([script.new(), script.new()])
	for i in range(2):
		var actor := QuietActor.new()
		add_child_autofree(actor)
		_data[0][i].actor = actor
		_data[1][i].actor_id = "leash_%d" % i
		_data[4][i].faction_id = "side_%d" % i
		_data[5][i].combat_stance = NpcRules.CombatStance.AGGRESSIVE if i == 0 else NpcRules.CombatStance.PASSIVE
		_data[5][i].aggro_scan_radius = 8.5
		_data[5][i].retarget_jitter_seconds = 0.0
	_data[4][0].hostile_faction_ids = PackedStringArray(["side_1"])
	_move_target(8.0)

func _step() -> void:
	_system.process([null, null], _data, 1.0)

func _move_target(distance: float) -> void:
	_data[2][1].world_position = _data[2][0].world_position + Vector3(distance, 0, 0)

func test_committed_pursuit_survives_leaving_acquisition_range_without_a_slot() -> void:
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1")
	_move_target(75.0)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1", "Choosing to fight commits pursuit, not just standing in an approved melee slot")

func test_pursuit_uses_fighter_to_target_distance_not_spawn_or_camp() -> void:
	_step()
	_data[2][0].world_position = Vector3(500, 0, 500)
	_move_target(90.0)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1")

func test_committed_grudge_does_not_expire_mid_chase() -> void:
	_data[4][0].hostile_faction_ids.clear()
	_data[6][0].personal_hostile_actor_ids = PackedStringArray(["leash_1"])
	_step()
	_data[6][0].personal_hostile_actor_ids.clear()
	_move_target(30.0)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1")

func test_leash_boundary_releases_even_an_old_fighting_slot() -> void:
	_step()
	_data[7][0].slot_target_actor_id = "leash_1"
	_data[7][0].slot_state = CGameCombatSlotState.FightState.FIGHTING
	_move_target(100.0)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1")
	_move_target(100.01)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "")
	assert_eq(_data[0][0].actor._system_target_id, 0)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "", "Old slot must not re-acquire a released opponent")

func test_leash_is_not_a_larger_fresh_enemy_scan() -> void:
	_move_target(75.0)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "")

func test_defend_and_player_move_still_release_pursuit() -> void:
	_step()
	_data[5][0].combat_stance = NpcRules.CombatStance.DEFENSIVE
	_data[5][1].player_order_active = true
	_data[6][0].personal_hostile_actor_ids = PackedStringArray(["leash_1"])
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "")
	_data[5][0].combat_stance = NpcRules.CombatStance.AGGRESSIVE
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1")
	_data[4][0].player_order_active = true
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "")

func test_invalid_or_protected_target_releases_committed_pursuit() -> void:
	_step()
	_data[5][1].protected_from_combat = true
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "")
	_data[5][1].protected_from_combat = false
	_step()
	_data[3][1].life_state = NpcRules.LifeState.DEAD
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "")

func test_player_explicit_attack_retains_exact_command_outside_auto_leash() -> void:
	_data[4][0].player_party_member = true
	_data[6][0].commanded_target_actor_id = "leash_1"
	_move_target(120.0)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1")

func test_npc_exact_attack_releases_outside_pursuit_leash() -> void:
	_data[6][0].commanded_target_actor_id = "leash_1"
	_move_target(90.0)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1")
	_move_target(101.0)
	_step()
	assert_eq(_data[6][0].commanded_target_actor_id, "")
	assert_eq(_data[6][0].system_target_actor_id, "")

func test_runtime_debug_control_changes_existing_pursuit_on_next_target_check() -> void:
	_step()
	_move_target(75.0)
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1")
	var panel = preload("res://features/combat/projection/combat_debug_panel.gd").new()
	add_child_autofree(panel)
	var distance := panel.get_node("PursuitLeashDistance") as SpinBox
	var original := distance.value
	distance.value = 60.0
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "", "Human control must change targeting, not just the displayed value")
	assert_eq(_data[0][0].actor._system_target_id, 0)
	distance.value = original
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "", "Restoring the leash does not enlarge fresh acquisition range")

func test_queued_target_is_not_retained_by_committed_pursuit() -> void:
	_step()
	_data[0][1].actor.queue_free()
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "")
	assert_eq(_data[0][0].actor._system_target_id, 0)

func test_runtime_leash_control_caps_fresh_acquisition() -> void:
	var panel = preload("res://features/combat/projection/combat_debug_panel.gd").new()
	add_child_autofree(panel)
	var distance := panel.get_node("PursuitLeashDistance") as SpinBox
	var original := distance.value
	distance.value = 5.0
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "", "Fresh scans cannot reacquire opponents outside the configured leash")
	distance.value = original
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "leash_1", "Restoring the leash permits ordinary nearby acquisition")

func test_passive_stance_releases_committed_pursuit() -> void:
	_step()
	_data[5][0].combat_stance = NpcRules.CombatStance.PASSIVE
	_step()
	assert_eq(_data[6][0].system_target_actor_id, "")
	assert_eq(_data[0][0].actor._system_target_id, 0)
