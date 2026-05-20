extends SceneTree

const SNEAK_DEMO_SCENE := preload("res://scenes/test_levels/sneak_perception_demo.tscn")

var _failures: Array[String] = []
var _scene: Node
var _player: HumanoidCharacter
var _observer: HumanoidCharacter
var _perception_controller: Node
var _ownership_controller: OwnershipController
var _interaction_controller: WorldInteractionController
var _world_time: WorldTimeController
var _camera: Camera3D
var _owned_sword: WorldItem
var _owned_vase: WorldItem


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _load_scene()
	await _run_visibility_cases()
	await _run_lighting_cases()
	await _run_camera_center_case()
	await _run_debug_toggle_case()
	await _run_stealing_cases()
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
	_ownership_controller = _scene.get_node_or_null("GameBootstrap/OwnershipController") as OwnershipController
	_interaction_controller = _scene.get_node_or_null("GameBootstrap/WorldInteractionController") as WorldInteractionController
	_world_time = _scene.get_node_or_null("GameBootstrap/WorldTimeController") as WorldTimeController
	_camera = _scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
	_owned_sword = _scene.get_node_or_null("OwnedSword") as WorldItem
	_owned_vase = _scene.get_node_or_null("OwnedVase") as WorldItem
	if _player == null:
		_fail("Mira was not found")
	if _observer == null:
		_fail("Watcher was not found")
	if _perception_controller == null:
		_fail("PerceptionController was not found")
	if _ownership_controller == null:
		_fail("OwnershipController was not found")
	if _interaction_controller == null:
		_fail("WorldInteractionController was not found")
	if _world_time == null:
		_fail("WorldTimeController was not found")
	if _camera == null:
		_fail("Camera3D was not found")
	if _owned_sword == null:
		_fail("OwnedSword was not found")
	if _owned_vase == null:
		_fail("OwnedVase was not found")
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


func _run_stealing_cases() -> void:
	if _player == null or _observer == null or _perception_controller == null or _ownership_controller == null or _owned_sword == null or _owned_vase == null:
		return
	_world_time.total_world_minutes = 16.0 * 60.0 + 30.0
	_player.set_sneaking_enabled(true)
	await _wait_frames(4)
	var steal_label := str(_ownership_controller.get_take_item_label(_player, _owned_sword))
	var steal_color := _ownership_controller.get_take_item_color(_player, _owned_sword)
	if steal_label != "Steal" or steal_color.a <= 0.0:
		_fail("Expected owned sword to show soft-red Steal action, label=%s color=%s" % [steal_label, steal_color])
	_owned_vase.global_position = Vector3(0.0, 0.08, 1.65)
	_player.global_position = Vector3(0.0, 0.6, 1.85)
	_player.velocity = Vector3.ZERO
	_player.sleight_of_hand = 0
	_face_observer_away_from_player()
	await _wait_frames(8)
	var hidden_result := _perception_controller.call("evaluate_observer", _observer, _player) as Dictionary
	if bool(hidden_result.get("clearly_seen", false)):
		_fail("Expected behind-watcher vase steal setup to stay visually hidden, got %s" % hidden_result)
	var noisy_pickup := bool(_owned_vase.try_pickup(_player))
	if noisy_pickup:
		_fail("Expected low-skill close vase steal to be blocked by theft noise suspicion")
	await _wait_frames(2)
	if not is_instance_valid(_owned_vase):
		_fail("Expected blocked noisy vase steal to remain in the world")
	_player.sleight_of_hand = 100
	_face_observer_away_from_player()
	await _wait_frames(4)
	var skilled_pickup := bool(_owned_vase.try_pickup(_player))
	if not skilled_pickup:
		_fail("Expected high-skill close vase steal to beat theft noise suspicion")
	await _wait_frames(2)
	if is_instance_valid(_owned_vase):
		_fail("Expected high-skill stolen vase to leave the world")
	_player.sleight_of_hand = 0
	_player.global_position = Vector3(1.45, 0.6, -7.5)
	_player.velocity = Vector3.ZERO
	_face_observer_to_player()
	await _wait_frames(8)
	var first_seen_pickup := bool(_owned_sword.try_pickup(_player))
	if first_seen_pickup:
		_fail("Expected first witnessed sword steal attempt to be blocked")
	if not is_instance_valid(_owned_sword):
		_fail("Expected blocked witnessed sword steal to remain in the world")
	var second_seen_pickup := bool(_owned_sword.try_pickup(_player))
	if second_seen_pickup:
		_fail("Expected second witnessed sword steal attempt to be blocked before escalation")
	var escalated_pickup := bool(_owned_sword.try_pickup(_player))
	if not escalated_pickup:
		_fail("Expected repeated witnessed sword steal to escalate and allow grab-and-run pickup")
	if not _observer.has_hostility_with(_player):
		_fail("Expected repeated witnessed stealing to make observer hostile")
	if _player.sneaking:
		_fail("Expected combat escalation to break player sneaking")
	await _wait_frames(2)
	if is_instance_valid(_owned_sword):
		_fail("Expected escalated stolen sword to leave the world")


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
		var noise_message := str(_scene.call("perform_sneak_demo_action", "toggle_theft_noise_radius", [])) if _scene.has_method("perform_sneak_demo_action") else ""
		if noise_message.is_empty() or not bool(_scene.get("show_theft_noise_radius")):
			_fail("Sneak demo theft-noise radius toggle did not respond")
		var noise_visual_root := _scene.get_node_or_null("TheftNoiseRadiusVisuals")
		var visible_noise_visuals := 0
		if noise_visual_root != null:
			for child in noise_visual_root.get_children():
				if child is MeshInstance3D and child.visible:
					visible_noise_visuals += 1
		if visible_noise_visuals < 2:
			_fail("Expected theft-noise radius visuals for owned sword and vase, got %d" % visible_noise_visuals)


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


func _face_observer_away_from_player() -> void:
	var target := _observer.global_position * 2.0 - _player.global_position
	target.y = _observer.global_position.y
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
