extends SceneTree

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")
const FLOAT_TOLERANCE := 0.02

var _failures: Array[String] = []
var _scene: Node
var _party_manager: PartyManager
var _interaction_controller: WorldInteractionController
var _camera: Camera3D
var _mira: HumanoidCharacter
var _tomas: HumanoidCharacter


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _load_scene()
	_run_fatigue_tests()
	await _run_close_group_click_test()
	if _failures.is_empty():
		print("FATIGUE_GROUP_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FATIGUE_GROUP_VALIDATION_FAILED count=%d" % _failures.size())
	quit(1)


func _load_scene() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_physics(80)
	_party_manager = _scene.get_node("PartyManager") as PartyManager
	_interaction_controller = _scene.get_node("GameBootstrap/WorldInteractionController") as WorldInteractionController
	_camera = _scene.get_node("CameraRig/CameraPivot/Camera3D") as Camera3D
	_mira = _scene.get_node("PartyMembers/Mira") as HumanoidCharacter
	_tomas = _scene.get_node("PartyMembers/Tomas") as HumanoidCharacter
	_camera.current = true


func _run_fatigue_tests() -> void:
	_test_stuck_running_recovers()
	_test_running_motion_drains()
	_test_walking_recovers_slower_than_idle()
	_test_sitting_and_sleep_recover_faster()
	_test_combat_idle_recovers()
	_test_attack_costs_fatigue()
	_test_dodge_costs_fatigue()
	_test_block_costs_fatigue()


func _test_stuck_running_recovers() -> void:
	_reset_actor_for_fatigue(_mira)
	_mira.running = true
	_mira.velocity = Vector3.ZERO
	_mira._set_actor_move_target(_mira.global_position + Vector3(12.0, 0.0, 0.0))
	var before := _mira.fatigue
	_mira._process_needs(1.0)
	if _mira.fatigue <= before:
		_failures.append("stuck_running_should_not_drain before=%.3f after=%.3f" % [before, _mira.fatigue])


func _test_running_motion_drains() -> void:
	_reset_actor_for_fatigue(_mira)
	_mira.running = true
	_mira.velocity = Vector3(_mira.move_speed, 0.0, 0.0)
	_mira._set_actor_move_target(_mira.global_position + Vector3(12.0, 0.0, 0.0))
	var before := _mira.fatigue
	_mira._process_needs(1.0)
	if _mira.fatigue >= before:
		_failures.append("running_motion_should_drain before=%.3f after=%.3f" % [before, _mira.fatigue])


func _test_walking_recovers_slower_than_idle() -> void:
	_reset_actor_for_fatigue(_mira)
	var before_idle := _mira.fatigue
	_mira.velocity = Vector3.ZERO
	_mira._process_needs(1.0)
	var idle_gain := _mira.fatigue - before_idle

	_reset_actor_for_fatigue(_mira)
	var before_walk := _mira.fatigue
	_mira.velocity = Vector3(_mira.move_speed * 0.5, 0.0, 0.0)
	_mira._process_needs(1.0)
	var walk_gain := _mira.fatigue - before_walk
	if walk_gain <= 0.0 or walk_gain >= idle_gain:
		_failures.append("walking_should_recover_slower_than_idle idle_gain=%.3f walk_gain=%.3f" % [idle_gain, walk_gain])


func _test_sitting_and_sleep_recover_faster() -> void:
	_reset_actor_for_fatigue(_mira)
	var before_idle := _mira.fatigue
	_mira._process_needs(1.0)
	var idle_gain := _mira.fatigue - before_idle

	_reset_actor_for_fatigue(_mira)
	_mira._is_sitting = true
	var before_sit := _mira.fatigue
	_mira._process_needs(1.0)
	var sit_gain := _mira.fatigue - before_sit

	_reset_actor_for_fatigue(_mira)
	_mira.life_state = NpcRules.LifeState.ASLEEP
	var before_sleep := _mira.fatigue
	_mira._process_needs(1.0)
	var sleep_gain := _mira.fatigue - before_sleep
	if sit_gain <= idle_gain or sleep_gain <= sit_gain:
		_failures.append("rest_recovery_order_expected idle=%.3f sit=%.3f sleep=%.3f" % [idle_gain, sit_gain, sleep_gain])


func _test_combat_idle_recovers() -> void:
	_reset_actor_for_fatigue(_mira)
	_reset_actor_for_fatigue(_tomas)
	_mira._current_order_type = HumanoidCharacter.OrderType.ATTACK
	_mira._current_attack_target = _tomas
	_mira.velocity = Vector3.ZERO
	var before := _mira.fatigue
	_mira._process_needs(1.0)
	if _mira.fatigue <= before:
		_failures.append("combat_idle_should_not_drain before=%.3f after=%.3f" % [before, _mira.fatigue])


func _test_attack_costs_fatigue() -> void:
	_reset_actor_for_fatigue(_mira)
	_reset_actor_for_fatigue(_tomas)
	_place_duelists()
	var before := _mira.fatigue
	_mira._start_combat_attack(_tomas)
	if _mira.fatigue >= before - FLOAT_TOLERANCE:
		_failures.append("attack_should_cost_fatigue before=%.3f after=%.3f" % [before, _mira.fatigue])
	_mira.COMBAT_COORDINATOR.release_character(_mira)
	_mira.COMBAT_COORDINATOR.release_character(_tomas)


func _test_dodge_costs_fatigue() -> void:
	_reset_actor_for_fatigue(_mira)
	_reset_actor_for_fatigue(_tomas)
	_tomas.base_dodge_chance = 100.0
	_tomas.base_block_chance = 0.0
	var before := _tomas.fatigue
	var did_dodge := false
	for _attempt in range(40):
		if _tomas.receive_attack(_mira, 0.0, 0.0) == "dodged":
			did_dodge = true
			break
	if not did_dodge or _tomas.fatigue >= before - FLOAT_TOLERANCE:
		_failures.append("dodge_should_cost_fatigue dodged=%s before=%.3f after=%.3f" % [did_dodge, before, _tomas.fatigue])


func _test_block_costs_fatigue() -> void:
	_reset_actor_for_fatigue(_mira)
	_reset_actor_for_fatigue(_tomas)
	_tomas.base_dodge_chance = 0.0
	_tomas.base_block_chance = 100.0
	var before := _tomas.fatigue
	var did_block := false
	for _attempt in range(40):
		if _tomas.receive_attack(_mira, 0.0, 0.0) == "blocked":
			did_block = true
			break
	if not did_block or _tomas.fatigue >= before - FLOAT_TOLERANCE:
		_failures.append("block_should_cost_fatigue blocked=%s before=%.3f after=%.3f" % [did_block, before, _tomas.fatigue])


func _run_close_group_click_test() -> void:
	_reset_actor_for_fatigue(_mira)
	_reset_actor_for_fatigue(_tomas)
	var click_target := Vector3(-5.0, 0.0, 15.0)
	_place_actor(_mira, click_target + Vector3(-1.0, 0.6, 0.0))
	_place_actor(_tomas, click_target + Vector3(1.0, 0.6, 0.0))
	_party_manager.set_selection([_mira, _tomas])
	await _wait_physics(10)
	_set_camera_for_click(click_target, Vector3(0.0, 10.0, 10.0))
	await _wait_physics(3)
	var issued := _interaction_controller.issue_move_command(_camera.unproject_position(click_target), false)
	if not issued:
		_failures.append("close_group_click did not issue move command")
		return
	var target_spacing := _horizontal_distance(_mira._move_target, _tomas._move_target)
	if target_spacing > _interaction_controller.close_move_command_spacing * 1.25:
		_failures.append("close_group_click spacing too wide spacing=%.3f expected<=%.3f mira=%s tomas=%s" % [target_spacing, _interaction_controller.close_move_command_spacing * 1.25, _mira._move_target, _tomas._move_target])
	if target_spacing < _interaction_controller.close_move_command_spacing * 0.35:
		_failures.append("close_group_click spacing too tight spacing=%.3f mira=%s tomas=%s" % [target_spacing, _mira._move_target, _tomas._move_target])


func _reset_actor_for_fatigue(actor: HumanoidCharacter) -> void:
	actor._clear_all_active_orders()
	actor.COMBAT_COORDINATOR.release_character(actor)
	actor.life_state = NpcRules.LifeState.ALIVE
	actor.fatigue_enabled = true
	actor.fatigue_stage = NpcRules.FatigueStage.WELL_RESTED
	actor.fatigue = 50.0
	actor.running = false
	actor.sneaking = false
	actor.velocity = Vector3.ZERO
	actor._is_sitting = false
	actor.base_dodge_chance = 0.08
	actor.base_block_chance = 0.06
	actor._combat_cooldown_remaining = 0.0
	actor._clear_combat_action()


func _place_duelists() -> void:
	_place_actor(_mira, Vector3(-8.0, 0.6, 12.0))
	_place_actor(_tomas, Vector3(-7.1, 0.6, 12.0))


func _place_actor(actor: HumanoidCharacter, position: Vector3) -> void:
	actor.global_position = position
	actor.velocity = Vector3.ZERO
	actor._clear_actor_move_target()


func _set_camera_for_click(target_position: Vector3, offset: Vector3) -> void:
	_camera.global_position = target_position + offset
	_camera.look_at(target_position, Vector3.UP)


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _wait_physics(frames: int) -> void:
	for _index in range(frames):
		await physics_frame
