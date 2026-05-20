extends SceneTree

const SNEAK_DEMO_SCENE := preload("res://scenes/test_levels/sneak_perception_demo.tscn")

var _failures: Array[String] = []
var _scene: Node
var _player: HumanoidCharacter
var _observer: HumanoidCharacter
var _perception_controller: Node
var _interaction_controller: WorldInteractionController
var _world_time: WorldTimeController
var _camera: Camera3D


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _load_scene()
	await _run_visibility_cases()
	await _run_lighting_cases()
	await _run_camera_center_case()
	await _run_debug_toggle_case()
	if _failures.is_empty():
		print("SNEAK_PERCEPTION_DEMO_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SNEAK_PERCEPTION_DEMO_FAILED count=%d" % _failures.size())
	quit(1)


func _load_scene() -> void:
	_scene = SNEAK_DEMO_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(50)
	_player = _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	_observer = _scene.get_node_or_null("PartyMembers/Watcher") as HumanoidCharacter
	_perception_controller = _scene.get_node_or_null("GameBootstrap/PerceptionController")
	_interaction_controller = _scene.get_node_or_null("GameBootstrap/WorldInteractionController") as WorldInteractionController
	_world_time = _scene.get_node_or_null("GameBootstrap/WorldTimeController") as WorldTimeController
	_camera = _scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
	if _player == null:
		_fail("Mira was not found")
	if _observer == null:
		_fail("Watcher was not found")
	if _perception_controller == null:
		_fail("PerceptionController was not found")
	if _interaction_controller == null:
		_fail("WorldInteractionController was not found")
	if _camera == null:
		_fail("Camera3D was not found")
	if _scene != null:
		_scene.set("observer_rotation_enabled", false)
	if _player != null:
		_player.set_sneaking_enabled(true)
	var party_manager := _scene.get_node_or_null("PartyManager") as PartyManager
	if party_manager != null and _player != null:
		party_manager.select_only(_player)


func _run_visibility_cases() -> void:
	if _player == null or _observer == null or _perception_controller == null:
		return
	var visible := await _evaluate_case("clear_visible", Vector3(1.45, 0.6, -7.5))
	if float(visible.get("line_of_sight_fraction", 0.0)) < 0.66 or not bool(visible.get("clearly_seen", false)):
		_fail("Expected clear visible case, got %s" % visible)
	var hidden := await _evaluate_case("pillar_hidden", Vector3(0.0, 0.6, -7.5))
	if float(hidden.get("line_of_sight_fraction", 1.0)) > 0.05 or float(hidden.get("visibility_score", 1.0)) > 0.05:
		_fail("Expected pillar-hidden case, got %s" % hidden)
	var partial := await _evaluate_case("pillar_partial", Vector3(1.08, 0.6, -7.5))
	var partial_los := float(partial.get("line_of_sight_fraction", 0.0))
	if partial_los <= 0.05 or partial_los >= 0.95:
		_fail("Expected partial pillar visibility, got %s" % partial)


func _run_lighting_cases() -> void:
	if _player == null or _observer == null or _perception_controller == null or _world_time == null:
		return
	_world_time.total_world_minutes = 23.0 * 60.0
	await _wait_frames(4)
	var dark := await _evaluate_case("night_dark", Vector3(1.45, 0.6, -7.5))
	var torch_lit := await _evaluate_case("night_torch_lit", Vector3(-5.8, 0.6, -5.45))
	if float(torch_lit.get("light_exposure", 0.0)) <= float(dark.get("light_exposure", 0.0)) + 0.18:
		_fail("Expected torch-lit exposure above dark exposure, dark=%s torch=%s" % [dark, torch_lit])


func _run_camera_center_case() -> void:
	if _player == null or _interaction_controller == null or _camera == null:
		return
	_player.global_position = Vector3(0.0, 0.6, -7.5)
	_interaction_controller._set_follow_target(_player)
	await _wait_frames(4)
	var anchor := _player.get_follow_anchor_position() + Vector3(0.0, 1.35, 0.0)
	var screen_position := _camera.unproject_position(anchor)
	var center := Vector2(float(root.size.x), float(root.size.y)) * 0.5
	var error := screen_position.distance_to(center)
	print("SNEAK_CAMERA_CENTER error=%.2f screen=%s center=%s" % [error, screen_position, center])
	if error > 10.0:
		_fail("Followed Mira anchor is not screen-centered: error=%.2f screen=%s center=%s" % [error, screen_position, center])


func _run_debug_toggle_case() -> void:
	if _perception_controller == null:
		return
	_perception_controller.set("debug_show_los_rays", true)
	await _evaluate_case("debug_los_rays", Vector3(1.45, 0.6, -7.5))
	_perception_controller.set("debug_show_los_rays", false)
	if _scene != null:
		var message := str(_scene.call("perform_sneak_demo_action", "toggle_vision_cone", [])) if _scene.has_method("perform_sneak_demo_action") else ""
		if message.is_empty():
			_fail("Sneak demo action button target did not respond")


func _evaluate_case(label: String, player_position: Vector3) -> Dictionary:
	_player.global_position = player_position
	_player.velocity = Vector3.ZERO
	_face_observer_to_player()
	await _wait_frames(8)
	var result := _perception_controller.call("evaluate_observer", _observer, _player) as Dictionary
	print("SNEAK_PERCEPTION_CASE %s los=%.2f score=%.2f light=%.2f clear=%s partial=%s" % [
		label,
		float(result.get("line_of_sight_fraction", 0.0)),
		float(result.get("visibility_score", 0.0)),
		float(result.get("light_exposure", 0.0)),
		bool(result.get("clearly_seen", false)),
		bool(result.get("partially_seen", false)),
	])
	return result


func _face_observer_to_player() -> void:
	var target := Vector3(_player.global_position.x, _observer.global_position.y, _player.global_position.z)
	if _observer.global_position.distance_squared_to(target) <= 0.001:
		return
	_observer.look_at(target, Vector3.UP)
	_observer.rotation.x = 0.0
	_observer.rotation.z = 0.0


func _wait_frames(frames: int) -> void:
	for _index in range(frames):
		await process_frame
		await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
