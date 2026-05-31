extends SceneTree

const SNEAK_DEMO_SCENE := preload("res://scenes/test_levels/sneak_perception_demo.tscn")
const FACTION_HUMANOID_SCRIPT := preload("res://scripts/characters/faction_humanoid.gd")
const CROWD_OBSERVER_COUNT := 36

var _failures: Array[String] = []
var _scene: Node
var _player: HumanoidCharacter
var _noisy_player: HumanoidCharacter
var _invisible_player: HumanoidCharacter
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
	await _run_sustained_suspicion_case()
	await _run_sustained_moving_exposure_case()
	await _run_sneak_speed_case()
	await _run_sneak_training_pressure_cases()
	_run_sneak_training_rate_cases()
	await _run_camera_center_case()
	await _run_debug_toggle_case()
	await _run_stealing_cases()
	await _run_crowded_perception_case()
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
	_noisy_player = _scene.get_node_or_null("PartyMembers/Noisy") as HumanoidCharacter
	_invisible_player = _scene.get_node_or_null("PartyMembers/Invisible") as HumanoidCharacter
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
	if _noisy_player == null:
		_fail("Noisy was not found")
	if _invisible_player == null:
		_fail("Invisible was not found")
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
		if _player.get_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND) != 20:
			_fail("Expected Mira sleight of hand to start at 20")
	if _noisy_player != null and _noisy_player.get_skill_level(SkillRules.SUBTERFUGE_SNEAKING) != 1:
		_fail("Expected Noisy sneaking to start at 1")
	if _noisy_player != null and _noisy_player.get_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND) != 1:
		_fail("Expected Noisy sleight of hand to start at 1")
	if _invisible_player != null and _invisible_player.get_skill_level(SkillRules.SUBTERFUGE_SNEAKING) != 80:
		_fail("Expected Invisible sneaking to start at 80")
	if _invisible_player != null and _invisible_player.get_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND) != 80:
		_fail("Expected Invisible sleight of hand to start at 80")
	if _observer != null and _observer.get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION) != 1:
		_fail("Expected Watcher perception to start at 1")
	var party_manager := _scene.get_node_or_null("PartyManager") as PartyManager
	if party_manager != null and _player != null:
		party_manager.select_only(_player)
	await _wait_frames(2)
	var skills_button := _scene.get_node_or_null("GameHUD/HudLayout/BottomHud/InspectorSlot/HumanoidDetailsPanel/Margin/DetailsVBox/ActionRow/SecondaryActionButton") as Button
	if skills_button == null:
		_fail("Skills button was not added to selected party member details")
	elif skills_button.text != "Skills" or not skills_button.visible or skills_button.disabled:
		_fail("Skills button should be visible and enabled for selected party member")
	else:
		skills_button.pressed.emit()
		await _wait_frames(2)
		var skills_window := _scene.get_node_or_null("GameHUD/CharacterSkillsWindow") as Control
		if skills_window == null or not skills_window.visible:
			_fail("Skills window did not open from selected party member details")


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
	if _noisy_player != null and _world_time != null:
		_world_time.total_world_minutes = 18.0 * 60.0
		await _wait_frames(4)
		_noisy_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
		var novice_dusk_close := await _evaluate_subject_case(_noisy_player, "novice_dusk_close", Vector3(0.2, 0.6, -1.0))
		if not bool(novice_dusk_close.get("clearly_seen", false)):
			_fail("Expected level 1 sneaking to be clearly seen up close at dusk, got %s" % novice_dusk_close)
		_world_time.total_world_minutes = 16.0 * 60.0 + 30.0
		await _wait_frames(4)
		_noisy_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 20)
		var intermediate := await _evaluate_subject_case(_noisy_player, "intermediate_sneak_normal", Vector3(1.45, 0.6, -7.5))
		if bool(intermediate.get("clearly_seen", false)) or not bool(intermediate.get("partially_seen", false)):
			_fail("Expected level 20 sneaking to be intermediate/partially seen at normal range, got %s" % intermediate)
		_noisy_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 40)
		var skilled := await _evaluate_subject_case(_noisy_player, "skilled_sneak_normal", Vector3(1.45, 0.6, -7.5))
		if bool(skilled.get("clearly_seen", false)) or float(skilled.get("visibility_score", 1.0)) >= float(intermediate.get("visibility_score", 0.0)):
			_fail("Expected level 40 sneaking to improve beyond level 20 without becoming magic, got level20=%s level40=%s" % [intermediate, skilled])
	var legendary_normal := await _evaluate_subject_case(_invisible_player, "legendary_sneak_normal", Vector3(1.45, 0.6, -7.5))
	if bool(legendary_normal.get("clearly_seen", false)):
		_fail("Expected sneak 80 to avoid clear detection by perception 1 at normal range, got %s" % legendary_normal)
	var legendary_close := await _evaluate_subject_case(_invisible_player, "legendary_sneak_close", Vector3(0.2, 0.6, -1.0))
	if bool(legendary_close.get("clearly_seen", false)) or float(legendary_close.get("visibility_score", 1.0)) >= 0.14:
		_fail("Expected sneak 80 to avoid clear detection even at close range against perception 1, got %s" % legendary_close)


func _run_lighting_cases() -> void:
	if _player == null or _observer == null or _perception_controller == null or _world_time == null:
		return
	_world_time.total_world_minutes = 23.0 * 60.0
	await _wait_frames(4)
	var dark := await _evaluate_case("night_dark", Vector3(1.45, 0.6, -7.5))
	var torch_lit := await _evaluate_case("night_torch_lit", Vector3(-5.8, 0.6, -5.45))
	if float(torch_lit.get("light_exposure", 0.0)) <= float(dark.get("light_exposure", 0.0)) + 0.18:
		_fail("Expected torch-lit exposure above dark exposure, dark=%s torch=%s" % [dark, torch_lit])


func _run_sustained_suspicion_case() -> void:
	if _scene == null or _noisy_player == null or _observer == null or _perception_controller == null or _world_time == null:
		return
	var party_manager := _scene.get_node_or_null("PartyManager") as PartyManager
	if party_manager == null:
		_fail("Cannot run sustained suspicion case without PartyManager")
		return
	_world_time.total_world_minutes = 23.0 * 60.0
	_observer.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 4)
	_noisy_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 2)
	_noisy_player.global_position = Vector3(1.45, 0.6, -8.5)
	_noisy_player.velocity = Vector3.ZERO
	_noisy_player.set_sneaking_enabled(true)
	_park_other_party_subjects(_noisy_player)
	party_manager.select_only(_noisy_player)
	_face_observer_to_subject(_noisy_player)
	await _wait_frames(8)
	var initial := _perception_controller.call("evaluate_observer", _observer, _noisy_player) as Dictionary
	_print_perception_case("novice_night_initial", initial)
	if bool(initial.get("clearly_seen", false)) or not bool(initial.get("partially_seen", false)):
		_fail("Expected level 2 night clear-LOS sneaking to start suspicious/yellow, got %s" % initial)
	await _wait_frames(100)
	var escalated := _perception_controller.call("get_latest_result", _observer, _noisy_player) as Dictionary
	_print_perception_case("novice_night_sustained", escalated)
	if not bool(escalated.get("clearly_seen", false)) or not bool(escalated.get("suspicion_escalated", false)):
		_fail("Expected sustained level 2 yellow suspicion to escalate to red, got %s" % escalated)
	_observer.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 1)
	party_manager.select_only(_player)


func _run_sustained_moving_exposure_case() -> void:
	if _scene == null or _invisible_player == null or _noisy_player == null or _observer == null or _perception_controller == null or _world_time == null:
		return
	var party_manager := _scene.get_node_or_null("PartyManager") as PartyManager
	if party_manager == null:
		_fail("Cannot run sustained moving exposure case without PartyManager")
		return
	_world_time.total_world_minutes = 12.0 * 60.0
	await _wait_frames(4)
	_observer.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 100)
	_invisible_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 80)
	_invisible_player.global_position = Vector3(1.45, 0.6, -7.5)
	_invisible_player.set_sneaking_enabled(true)
	_park_other_party_subjects(_invisible_player)
	_face_observer_to_subject(_invisible_player)
	party_manager.select_only(_invisible_player)
	_perception_controller.call("_clear_perception_state")
	var brief := _advance_sustained_exposure(_invisible_player, 0.6, true)
	_print_perception_case("elite_sneak80_brief_moving", brief)
	if bool(brief.get("clearly_seen", false)):
		_fail("Expected sneak 80 to survive a brief daylight crossing before red escalation, got %s" % brief)
	var sustained := _advance_sustained_exposure(_invisible_player, 3.6, true)
	_print_perception_case("elite_sneak80_sustained_moving", sustained)
	if float(sustained.get("sustained_moving_exposure", 0.0)) <= float(brief.get("sustained_moving_exposure", 0.0)) + 0.05:
		_fail("Expected moving in an elite guard cone to build sustained exposure, brief=%s sustained=%s" % [brief, sustained])
	if not bool(sustained.get("partially_seen", false)) and not bool(sustained.get("clearly_seen", false)):
		_fail("Expected sustained sneak 80 movement in broad daylight elite LOS to reach at least yellow, got %s" % sustained)
	_face_observer_away_from_subject(_invisible_player)
	var reset := _advance_sustained_exposure(_invisible_player, 0.2, true)
	_print_perception_case("elite_sneak80_left_cone", reset)
	if float(reset.get("sustained_moving_exposure", 1.0)) > 0.01:
		_fail("Expected leaving the observer cone to reset sustained exposure, got %s" % reset)
	_noisy_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 20)
	_noisy_player.global_position = Vector3(1.45, 0.6, -7.5)
	_noisy_player.set_sneaking_enabled(true)
	_park_other_party_subjects(_noisy_player)
	_face_observer_to_subject(_noisy_player)
	party_manager.select_only(_noisy_player)
	_perception_controller.call("_clear_perception_state")
	var low_skill := _advance_sustained_exposure(_noisy_player, 1.2, true)
	_print_perception_case("elite_sneak20_sustained_moving", low_skill)
	if not bool(low_skill.get("clearly_seen", false)) and float(low_skill.get("suspicion_progress", 0.0)) <= float(brief.get("suspicion_progress", 0.0)) + 0.25:
		_fail("Expected sneak 20 to escalate faster than sneak 80 under elite daylight exposure, low=%s high_brief=%s" % [low_skill, brief])
	_observer.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 1)
	_invisible_player.velocity = Vector3.ZERO
	_noisy_player.velocity = Vector3.ZERO
	party_manager.select_only(_player)


func _run_sneak_speed_case() -> void:
	if _noisy_player == null:
		return
	_noisy_player.set_sneaking_enabled(true)
	_noisy_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
	var novice_speed_multiplier := _noisy_player.get_stat_value("move_speed_multiplier")
	_noisy_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 80)
	var master_speed_multiplier := _noisy_player.get_stat_value("move_speed_multiplier")
	print("SNEAK_SPEED novice=%.2f master=%.2f run=%.2f" % [novice_speed_multiplier, master_speed_multiplier, NpcRules.RUN_SPEED_MULTIPLIER])
	if novice_speed_multiplier > 0.55:
		_fail("Expected novice sneaking to be a slow crawl, got %.3f" % novice_speed_multiplier)
	if master_speed_multiplier < 1.35 or master_speed_multiplier >= NpcRules.RUN_SPEED_MULTIPLIER:
		_fail("Expected master sneaking to approach but stay below running, got %.3f" % master_speed_multiplier)
	if master_speed_multiplier <= novice_speed_multiplier * 2.0:
		_fail("Expected sneak movement speed to scale strongly with skill, novice=%.3f master=%.3f" % [novice_speed_multiplier, master_speed_multiplier])


func _run_sneak_training_pressure_cases() -> void:
	if _noisy_player == null or _observer == null or _perception_controller == null:
		return
	_observer.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 4)
	_noisy_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
	var red_result := await _evaluate_subject_case(_noisy_player, "novice_training_red", Vector3(0.2, 0.6, -1.0))
	var red_pressure := float(_perception_controller.call("_get_sneaking_training_pressure", red_result))
	if red_pressure > 0.001:
		_fail("Expected clear red detection to award no sneak training pressure, got %.3f from %s" % [red_pressure, red_result])

	var relevant_low := {
		"clearly_seen": false,
		"line_of_sight_fraction": 1.0,
		"cone_fraction": 1.0,
		"visibility_score": 0.2,
		"subject_sneaking": 8.0,
		"observer_perception": 4.0,
	}
	var overmatched_low := relevant_low.duplicate()
	overmatched_low["subject_sneaking"] = 22.0
	var relevant_high := relevant_low.duplicate()
	relevant_high["subject_sneaking"] = 22.0
	relevant_high["observer_perception"] = 18.0
	var relevant_low_pressure := float(_perception_controller.call("_get_sneaking_training_pressure", relevant_low))
	var overmatched_low_pressure := float(_perception_controller.call("_get_sneaking_training_pressure", overmatched_low))
	var relevant_high_pressure := float(_perception_controller.call("_get_sneaking_training_pressure", relevant_high))
	print("SNEAK_TRAINING_PRESSURE low=%.3f overmatched=%.3f high=%.3f" % [relevant_low_pressure, overmatched_low_pressure, relevant_high_pressure])
	if relevant_low_pressure <= 0.01:
		_fail("Expected low perception observers to train low sneak basics")
	if overmatched_low_pressure > 0.001:
		_fail("Expected low perception observers to stop training high sneak, got %.3f" % overmatched_low_pressure)
	if relevant_high_pressure <= overmatched_low_pressure + 0.1:
		_fail("Expected higher perception observers to remain useful for higher sneak")

	_noisy_player.set_sneaking_enabled(true)
	_noisy_player.velocity = Vector3.ZERO
	var idle_multiplier := float(_perception_controller.call("_get_sneaking_activity_multiplier", _noisy_player))
	_noisy_player.velocity = Vector3(1.0, 0.0, 0.0)
	var moving_multiplier := float(_perception_controller.call("_get_sneaking_activity_multiplier", _noisy_player))
	_noisy_player.velocity = Vector3.ZERO
	if absf(idle_multiplier - 0.5) > 0.001 or absf(moving_multiplier - 1.0) > 0.001:
		_fail("Expected stationary hiding to train at half moving rate, idle=%.3f moving=%.3f" % [idle_multiplier, moving_multiplier])
	_observer.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 1)
	_noisy_player.set_sneaking_enabled(false)
	_noisy_player.global_position = Vector3(-12.0, 0.6, 12.0)
	_noisy_player.velocity = Vector3.ZERO


func _run_sneak_training_rate_cases() -> void:
	if _perception_controller == null:
		return
	var minimum_valid_pressure_case := {
		"clearly_seen": false,
		"line_of_sight_fraction": 1.0,
		"cone_fraction": 1.0,
		"visibility_score": 0.03,
		"subject_sneaking": 1.0,
		"observer_perception": 4.0,
	}
	var minimum_pressure := float(_perception_controller.call("_get_sneaking_training_pressure", minimum_valid_pressure_case))
	var level_1_xp_to_next := SkillRules.get_xp_to_next_level(1)
	var ten_second_xp := float(_perception_controller.call("_get_sneaking_risk_xp", 10.0, minimum_pressure, 1.0))
	var thirty_second_xp := float(_perception_controller.call("_get_sneaking_risk_xp", 30.0, minimum_pressure, 1.0))
	var fast_forward_xp := float(_perception_controller.call("_get_sneaking_risk_xp", 80.0, minimum_pressure, 1.0))
	print("SNEAK_TRAINING_RATE pressure=%.3f xp10=%.2f xp30=%.2f xp80=%.2f next=%.2f" % [minimum_pressure, ten_second_xp, thirty_second_xp, fast_forward_xp, level_1_xp_to_next])
	if minimum_pressure < 0.44:
		_fail("Expected level-1 valid hiding pressure floor to prevent microscopic XP, got %.3f" % minimum_pressure)
	if ten_second_xp >= level_1_xp_to_next:
		_fail("Expected level 1 sneak not to level in only 10 seconds of minimum-risk hiding")
	if thirty_second_xp < level_1_xp_to_next:
		_fail("Expected level 1 sneak to level within about 30 seconds of valid risky movement, got %.2f / %.2f" % [thirty_second_xp, level_1_xp_to_next])
	if fast_forward_xp < thirty_second_xp * 2.4:
		_fail("Expected fast-forward-scaled delta to materially increase sneak XP, normal=%.2f fast=%.2f" % [thirty_second_xp, fast_forward_xp])


func _run_stealing_cases() -> void:
	if _player == null or _observer == null or _perception_controller == null or _ownership_controller == null or _owned_sword == null or _owned_vase == null:
		return
	_world_time.total_world_minutes = 16.0 * 60.0 + 30.0
	_player.set_sneaking_enabled(true)
	_park_other_party_subjects(_player)
	await _wait_frames(4)
	var steal_label := str(_ownership_controller.get_take_item_label(_player, _owned_sword))
	var steal_color := _ownership_controller.get_take_item_color(_player, _owned_sword)
	if steal_label != "Steal" or steal_color.a <= 0.0:
		_fail("Expected owned sword to show soft-red Steal action, label=%s color=%s" % [steal_label, steal_color])
	_owned_vase.global_position = Vector3(0.0, 0.08, 1.65)
	_player.global_position = Vector3(0.0, 0.6, 1.85)
	_player.velocity = Vector3.ZERO
	_player.set_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND, 0)
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
	_player.set_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND, 100)
	_face_observer_away_from_player()
	await _wait_frames(4)
	var skilled_pickup := bool(_owned_vase.try_pickup(_player))
	if not skilled_pickup:
		_fail("Expected high-skill close vase steal to beat theft noise suspicion")
	await _wait_frames(2)
	if is_instance_valid(_owned_vase):
		_fail("Expected high-skill stolen vase to leave the world")
	_player.set_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND, 20)
	_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
	_player.set_sneaking_enabled(true)
	_player.global_position = Vector3(0.2, 0.6, -1.0)
	_player.velocity = Vector3.ZERO
	_face_observer_to_player()
	await _wait_frames(8)
	var seen_result := _perception_controller.call("evaluate_observer", _observer, _player) as Dictionary
	if not bool(seen_result.get("clearly_seen", false)):
		_fail("Expected sword steal setup to be clearly witnessed, got %s" % seen_result)
	var seen_pickup := bool(_owned_sword.try_pickup(_player))
	if not seen_pickup:
		_fail("Expected clearly witnessed sword steal to resolve as a grab-and-run pickup")
	await _wait_frames(2)
	if is_instance_valid(_owned_sword):
		_fail("Expected witnessed stolen sword to leave the world")


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


func _run_crowded_perception_case() -> void:
	if _scene == null or _noisy_player == null or _perception_controller == null:
		return
	var party_root := _scene.get_node_or_null("PartyMembers") as Node3D
	var party_manager := _scene.get_node_or_null("PartyManager") as PartyManager
	if party_root == null or party_manager == null:
		_fail("Cannot run crowded perception case; party root or manager missing")
		return
	_perception_controller.set_process(false)
	_world_time.total_world_minutes = 23.0 * 60.0
	_noisy_player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
	_noisy_player.global_position = Vector3(0.0, 0.6, 0.0)
	_noisy_player.velocity = Vector3.ZERO
	_noisy_player.set_sneaking_enabled(true)
	_spawn_crowd_observers(party_root, _noisy_player)
	party_manager.select_only(_noisy_player)
	await _wait_frames(2)
	var idle_xp_gain := _measure_crowd_training_xp(_noisy_player, 4, false)
	var moving_xp_gain := _measure_crowd_training_xp(_noisy_player, 4, true)
	var results := _perception_controller.call("get_latest_results_for_subject", _noisy_player) as Array
	print("SNEAK_CROWD_RESULTS count=%d idle_xp=%.3f moving_xp=%.3f" % [results.size(), idle_xp_gain, moving_xp_gain])
	if results.size() < CROWD_OBSERVER_COUNT:
		_fail("Crowded perception case evaluated too few observers: expected at least %d got %d" % [CROWD_OBSERVER_COUNT, results.size()])
	if moving_xp_gain <= 0.02:
		_fail("Level-1 crowded moving sneak XP gain was too low: %.3f" % moving_xp_gain)
	if moving_xp_gain < 0.6:
		_fail("Level-1 crowded moving sneak XP should have a fast start, got %.3f" % moving_xp_gain)
	if moving_xp_gain > 1.25:
		_fail("Crowded moving sneak XP should be bounded by one observer, got %.3f" % moving_xp_gain)
	if idle_xp_gain <= 0.0 or idle_xp_gain >= moving_xp_gain:
		_fail("Stationary risky hiding should train slower than moving, idle=%.3f moving=%.3f" % [idle_xp_gain, moving_xp_gain])
	if absf(idle_xp_gain / maxf(moving_xp_gain, 0.001) - 0.5) > 0.2:
		_fail("Stationary risky hiding should be roughly half moving XP, idle=%.3f moving=%.3f" % [idle_xp_gain, moving_xp_gain])
	if float(_perception_controller.get("perception_tick_seconds")) <= 0.0:
		_fail("Perception controller should use a positive fixed tick interval")


func _measure_crowd_training_xp(subject: HumanoidCharacter, ticks: int, moving: bool) -> float:
	if subject == null or _perception_controller == null:
		return 0.0
	_park_other_party_subjects(subject)
	subject.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
	subject.set_sneaking_enabled(true)
	subject.global_position = Vector3(0.0, 0.6, 0.0)
	_perception_controller.call("_clear_perception_state")
	var tick_seconds := float(_perception_controller.get("perception_tick_seconds"))
	var active_subjects: Array[HumanoidCharacter] = [subject]
	var xp_before := subject.get_skill_xp(SkillRules.SUBTERFUGE_SNEAKING)
	for _index in range(ticks):
		subject.velocity = Vector3(1.0, 0.0, 0.0) if moving else Vector3.ZERO
		_perception_controller.call("_update_perception", tick_seconds, active_subjects)
	subject.velocity = Vector3.ZERO
	return subject.get_skill_xp(SkillRules.SUBTERFUGE_SNEAKING) - xp_before


func _advance_sustained_exposure(subject: HumanoidCharacter, seconds: float, moving: bool) -> Dictionary:
	if subject == null or _perception_controller == null:
		return {}
	_park_other_party_subjects(subject)
	var tick_seconds := float(_perception_controller.get("perception_tick_seconds"))
	var ticks := maxi(1, int(ceil(seconds / maxf(tick_seconds, 0.001))))
	var active_subjects: Array[HumanoidCharacter] = [subject]
	for _index in range(ticks):
		subject.velocity = Vector3(1.0, 0.0, 0.0) if moving else Vector3.ZERO
		_perception_controller.call("_update_perception", tick_seconds, active_subjects)
	subject.velocity = Vector3.ZERO
	return _perception_controller.call("get_latest_result", _observer, subject) as Dictionary


func _spawn_crowd_observers(parent: Node3D, training_subject: HumanoidCharacter) -> void:
	for index in range(CROWD_OBSERVER_COUNT):
		var node_name := "CrowdWatcher%d" % index
		if parent.get_node_or_null(node_name) != null:
			continue
		var angle := TAU * float(index) / float(CROWD_OBSERVER_COUNT)
		var radius := 5.0 + float(index % 4) * 2.0
		var position := Vector3(sin(angle) * radius, 0.6, -cos(angle) * radius)
		var color := Color(0.48 + float(index % 5) * 0.04, 0.52, 0.56, 1.0)
		var observer := _scene.call("_make_humanoid", node_name, FACTION_HUMANOID_SCRIPT, position, color, "Townsfolk", false) as HumanoidCharacter
		if observer == null:
			_fail("Could not create crowded perception observer %d" % index)
			continue
		observer.member_name = node_name
		observer.stable_id = "town.sneak_demo.crowd.%d" % index
		observer.combat_stance = NpcRules.CombatStance.PASSIVE
		observer.fatigue_enabled = false
		observer.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 4)
		parent.add_child(observer)
		observer.look_at(Vector3(training_subject.global_position.x, observer.global_position.y, training_subject.global_position.z), Vector3.UP)


func _park_other_party_subjects(active_subject: HumanoidCharacter) -> void:
	var subjects: Array[HumanoidCharacter] = [_player, _noisy_player, _invisible_player]
	for index in range(subjects.size()):
		var subject := subjects[index]
		if subject == null or subject == active_subject:
			continue
		subject.velocity = Vector3.ZERO
		subject.global_position = Vector3(28.0 + float(index) * 2.0, 0.6, 18.0)


func _evaluate_case(label: String, player_position: Vector3) -> Dictionary:
	_park_other_party_subjects(_player)
	_player.global_position = player_position
	_player.velocity = Vector3.ZERO
	_face_observer_to_player()
	await _wait_frames(8)
	var result := _perception_controller.call("evaluate_observer", _observer, _player) as Dictionary
	_print_perception_case(label, result)
	return result


func _evaluate_subject_case(subject: HumanoidCharacter, label: String, subject_position: Vector3) -> Dictionary:
	if subject == null:
		return {}
	_park_other_party_subjects(subject)
	subject.global_position = subject_position
	subject.velocity = Vector3.ZERO
	subject.set_sneaking_enabled(true)
	_face_observer_to_subject(subject)
	await _wait_frames(8)
	var result := _perception_controller.call("evaluate_observer", _observer, subject) as Dictionary
	_print_perception_case(label, result)
	return result


func _print_perception_case(label: String, result: Dictionary) -> void:
	print("SNEAK_PERCEPTION_CASE %s los=%.2f score=%.2f light=%.2f clear=%s partial=%s" % [
		label,
		float(result.get("line_of_sight_fraction", 0.0)),
		float(result.get("visibility_score", 0.0)),
		float(result.get("light_exposure", 0.0)),
		bool(result.get("clearly_seen", false)),
		bool(result.get("partially_seen", false)),
	])


func _face_observer_to_player() -> void:
	_face_observer_to_subject(_player)


func _face_observer_to_subject(subject: HumanoidCharacter) -> void:
	if subject == null:
		return
	var target := Vector3(subject.global_position.x, _observer.global_position.y, subject.global_position.z)
	if _observer.global_position.distance_squared_to(target) <= 0.001:
		return
	_observer.look_at(target, Vector3.UP)
	_observer.rotation.x = 0.0
	_observer.rotation.z = 0.0

func _face_observer_away_from_player() -> void:
	_face_observer_away_from_subject(_player)


func _face_observer_away_from_subject(subject: HumanoidCharacter) -> void:
	if subject == null:
		return
	var target := _observer.global_position * 2.0 - subject.global_position
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
