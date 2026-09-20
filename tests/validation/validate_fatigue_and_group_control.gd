extends "res://tests/validation/test_case.gd"

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
		await _cleanup_scene()
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FATIGUE_GROUP_VALIDATION_FAILED count=%d" % _failures.size())
	await _cleanup_scene()
	quit(1)


func _load_scene() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_physics(80)
	_party_manager = _scene.get_node("PartyManager") as PartyManager
	_interaction_controller = _scene.find_child("WorldInteractionController", true, false) as WorldInteractionController
	_camera = _scene.get_node("CameraRig/CameraPivot/Camera3D") as Camera3D
	_mira = _scene.get_node("PartyMembers/Mira") as HumanoidCharacter
	_tomas = _scene.get_node("PartyMembers/Tomas") as HumanoidCharacter
	_camera.current = true


func _cleanup_scene() -> void:
	_party_manager = null
	_interaction_controller = null
	_camera = null
	_mira = null
	_tomas = null
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
		_scene = null
	await process_frame


func _run_fatigue_tests() -> void:
	_test_attack_costs_fatigue()
	_test_dodge_costs_fatigue()
	_test_block_costs_fatigue()


func _test_attack_costs_fatigue() -> void:
	_reset_actor_for_fatigue(_mira)
	_reset_actor_for_fatigue(_tomas)
	_place_duelists()
	var before := _mira.fatigue
	_mira.on_system_combat_attack_started(_tomas, PackedStringArray())
	if _mira.fatigue >= before - FLOAT_TOLERANCE:
		_failures.append("attack_should_cost_fatigue before=%.3f after=%.3f" % [before, _mira.fatigue])


func _test_dodge_costs_fatigue() -> void:
	_reset_actor_for_fatigue(_tomas)
	var before := _tomas.fatigue
	_tomas.play_system_combat_hit_reaction(_mira, "dodged", "test", PackedStringArray(), false, false, true, 0.0)
	if _tomas.fatigue >= before - FLOAT_TOLERANCE:
		_failures.append("Resolved dodge must spend fatigue")


func _test_block_costs_fatigue() -> void:
	_reset_actor_for_fatigue(_tomas)
	var before := _tomas.fatigue
	_tomas.play_system_combat_hit_reaction(_mira, "blocked", "test", PackedStringArray(), false, false, true, 0.0)
	if _tomas.fatigue >= before - FLOAT_TOLERANCE:
		_failures.append("Resolved block must spend fatigue")


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
	var target_spacing := _horizontal_distance(_mira.get_move_target(), _tomas.get_move_target())
	if target_spacing > _interaction_controller.close_move_command_spacing * 1.25:
		_failures.append("close_group_click spacing too wide spacing=%.3f expected<=%.3f mira=%s tomas=%s" % [target_spacing, _interaction_controller.close_move_command_spacing * 1.25, _mira.get_move_target(), _tomas.get_move_target()])
	if target_spacing < _interaction_controller.close_move_command_spacing * 0.35:
		_failures.append("close_group_click spacing too tight spacing=%.3f mira=%s tomas=%s" % [target_spacing, _mira.get_move_target(), _tomas.get_move_target()])


func _reset_actor_for_fatigue(actor: HumanoidCharacter) -> void:
	actor.stop_movement()
	actor.life_state = NpcRules.LifeState.ALIVE
	actor.fatigue_enabled = true
	actor.get_needs().fatigue_stage = NpcRules.FatigueStage.WELL_RESTED
	actor.fatigue = 50.0
	actor.running = false
	actor.sneaking = false
	actor.velocity = Vector3.ZERO


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
