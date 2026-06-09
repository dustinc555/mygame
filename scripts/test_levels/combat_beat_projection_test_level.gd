extends Node3D

class_name CombatBeatProjectionTestLevel

const BOOTSTRAP_PATH := NodePath("GameBootstrap")
const PROJECTION_ROOT_NAME := "WorldActorProjections"
const BOOTSTRAP_WAIT_FRAMES := 180
const UI_REFRESH_SECONDS := 0.2
const PLAYER_SIDE_ID := "side_a"
const RAIDER_SIDE_ID := "side_b"
const PLAYER_FACTION_ID := "combat_left"
const RAIDER_FACTION_ID := "combat_right"
const PLAYER_PARTY_ID := "player_party"
const HUMAN_RACE_PATH := "res://resources/character_races/human.tres"
const HUMAN_MALE_BODY_PATH := "res://resources/character_body_archetypes/human_male.tres"
const HUMAN_FEMALE_BODY_PATH := "res://resources/character_body_archetypes/human_female.tres"

@export var scenario_id := "combat_beat_5v5"
@export_range(1, 128, 1) var side_a_count := 5
@export_range(1, 128, 1) var side_b_count := 5
@export_range(1, 16, 1) var formation_columns := 5
@export var side_separation := 7.0
@export var actor_spacing := 1.45
@export var auto_start := true
@export_range(1, 256, 1) var battle_rounds := 32
@export_range(0, 256, 1) var detailed_beat_limit := 48
@export var resolve_to_completion_for_1v1 := true
@export_range(0, 256, 1) var projection_actor_cap := 0

var _bootstrap: Node
var _gecs: Node
var _combat: Node
var _projection: Node
var _runner: Node
var _camera_rig: Node
var _ready_for_review := false
var _setup_complete := false
var _active_encounter_id := ""
var _battle_result: Dictionary = {}
var _last_projection_sync_ms := 0.0
var _average_projection_sync_ms := 0.0
var _projection_sync_sample_count := 0
var _fps_sum := 0.0
var _min_fps := INF
var _fps_frame_count := 0
var _fps_elapsed_seconds := 0.0
var _ui_elapsed := 0.0

var _ui_layer: CanvasLayer
var _status_label: Label
var _metrics_label: Label


func _ready() -> void:
	add_to_group("combat_beat_projection_test_level")
	_build_ui()
	call_deferred("_prepare_review_scene")


func _process(delta: float) -> void:
	if not _ready_for_review:
		return
	_record_frame_sample(delta)
	if _battle_result.is_empty():
		_poll_for_resolved_fight()
	_ui_elapsed += delta
	if _ui_elapsed >= UI_REFRESH_SECONDS:
		_ui_elapsed = 0.0
		_render_ui()


func restart_fight() -> void:
	if not _ready_for_review and not _setup_complete:
		return
	_setup_complete = false
	_battle_result.clear()
	_active_encounter_id = ""
	_start_fight()


func restart_duel() -> void:
	restart_fight()


func get_review_state() -> Dictionary:
	var projection_metrics := _projection_metrics()
	return {
		"ready": _ready_for_review,
		"setup_complete": _setup_complete,
		"playback_active": projection_metrics.get("combat_projection_active", false) == true,
		"paused": false,
		"encounter_id": _active_encounter_id,
		"playback_time": float(projection_metrics.get("combat_projection_playback_time", 0.0)),
		"playback_duration": float(projection_metrics.get("combat_projection_duration", 0.0)),
		"battle_result": _battle_result.duplicate(true),
		"projection_metrics": projection_metrics,
		"combat_schedule_loop_enabled": _projection.get("combat_schedule_loop_enabled") == true if _projection != null else false,
	}


func get_benchmark_state() -> Dictionary:
	var projection_metrics := _projection_metrics()
	return {
		"ready": _ready_for_review,
		"setup_complete": _setup_complete,
		"scenario_id": scenario_id,
		"scene_path": scene_file_path,
		"expected_actor_count": _expected_actor_count(),
		"expected_projected_actor_count": _expected_projected_actor_count(),
		"projected_actor_count": int(projection_metrics.get("projected_actor_count", 0)),
		"visible_actor_count": int(projection_metrics.get("visible_actor_count", 0)),
		"active_animation_count": _active_animation_count(),
		"average_fps": _average_fps(),
		"min_fps": _min_fps if _fps_frame_count > 0 else 0.0,
		"sample_frame_count": _fps_frame_count,
		"sample_elapsed_seconds": _fps_elapsed_seconds,
		"last_projection_sync_ms": _last_projection_sync_ms,
		"average_projection_sync_ms": _average_projection_sync_ms,
		"projection_sync_sample_count": _projection_sync_sample_count,
		"gecs_tick_ms": _gecs_tick_ms(),
		"battle_sim_included": not _battle_result.is_empty(),
		"combat_projection": projection_metrics,
	}


func measure_projection_sync(sample_count := 5) -> Dictionary:
	if _projection == null or not _projection.has_method("sync_projections"):
		return {"samples": 0, "average_ms": 0.0, "last_ms": 0.0}
	var safe_count := maxi(1, sample_count)
	var total_ms := 0.0
	for _index in range(safe_count):
		var started_usec := Time.get_ticks_usec()
		_projection.call("sync_projections")
		_last_projection_sync_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
		total_ms += _last_projection_sync_ms
	_average_projection_sync_ms = total_ms / float(safe_count)
	_projection_sync_sample_count = safe_count
	return {"samples": safe_count, "average_ms": _average_projection_sync_ms, "last_ms": _last_projection_sync_ms}


func _prepare_review_scene() -> void:
	_set_status("Waiting for CombatBeat projection systems...")
	for _frame in range(BOOTSTRAP_WAIT_FRAMES):
		await get_tree().process_frame
		if _bind_systems():
			_configure_projection()
			_ready_for_review = true
			if auto_start:
				_start_fight()
			return
	_set_status("Timed out waiting for GameBootstrap combat systems.")


func _bind_systems() -> bool:
	_bootstrap = get_node_or_null(BOOTSTRAP_PATH)
	if _bootstrap == null:
		return false
	_gecs = _bootstrap.get_node_or_null("GecsWorldController")
	_combat = _bootstrap.get_node_or_null("WorldMapCombatSimController")
	_projection = _bootstrap.get_node_or_null("WorldActorProjectionController")
	_runner = _bootstrap.get_node_or_null("WorldMapCombatFixedTickRunner")
	_camera_rig = get_node_or_null("CameraRig")
	return _gecs != null and _combat != null and _projection != null and _runner != null


func _configure_projection() -> void:
	if _projection == null:
		return
	_projection.set("auto_project", true)
	_projection.set("max_projected_actor_count", projection_actor_cap)
	_projection.set("projection_update_interval_seconds", 0.05)
	_projection.set("visible_combat_runtime_enabled", true)
	_projection.set("combat_schedule_projection_enabled", false)
	_projection.set("combat_schedule_loop_enabled", false)


func _start_fight() -> void:
	if _setup_complete:
		return
	if _gecs.has_method("clear_population_records"):
		_gecs.call("clear_population_records")
	_seed_population_records()
	_seed_world_combat_data()
	measure_projection_sync(3)
	if _camera_rig != null and _camera_rig.has_method("focus_world_position"):
		_camera_rig.call("focus_world_position", Vector3.ZERO)
	_setup_complete = true
	_set_status("Running live %dv%d visible combat." % [side_a_count, side_b_count])


func _seed_world_combat_data() -> void:
	if _runner == null or not _runner.has_method("queue_command"):
		return
	_active_encounter_id = "visible:%s:%d" % [scenario_id, Time.get_ticks_msec()]
	_runner.call("queue_command", {
		"action": "replace_world_squads",
		"active_squads": _squad_records(),
		"label": "Seed CombatBeat projection squads",
	})
	_flush_fixed_tick_commands(2)


func _flush_fixed_tick_commands(ticks: int) -> void:
	if _runner == null or not _runner.has_method("advance_time") or not _runner.has_method("get_fixed_delta"):
		return
	var fixed_delta := float(_runner.call("get_fixed_delta"))
	for _tick in range(maxi(1, ticks)):
		_runner.call("advance_time", fixed_delta)


func _poll_for_resolved_fight() -> void:
	var encounter := _resolved_encounter_record()
	if encounter.is_empty():
		return
	_battle_result = (encounter.get("battle_result", {}) as Dictionary).duplicate(true) if encounter.get("battle_result", {}) is Dictionary else {}
	_set_status("Playing resolved CombatBeat projection schedule.")


func _resolved_encounter_record() -> Dictionary:
	if _combat == null or not _combat.has_method("get_world_encounter_state") or _active_encounter_id.is_empty():
		return {}
	var state = _combat.call("get_world_encounter_state")
	if not (state is Dictionary):
		return {}
	var encounters = (state as Dictionary).get("encounters_by_id", {})
	if not (encounters is Dictionary):
		return {}
	var encounter = (encounters as Dictionary).get(_active_encounter_id, {})
	if encounter is Dictionary and str((encounter as Dictionary).get("status", "")) == "resolved":
		return (encounter as Dictionary).duplicate(true)
	return {}


func _seed_population_records() -> void:
	for index in range(side_a_count):
		_upsert_actor_record(PLAYER_SIDE_ID, index, -side_separation * 0.5, PI)
	for index in range(side_b_count):
		_upsert_actor_record(RAIDER_SIDE_ID, index, side_separation * 0.5, 0.0)


func _upsert_actor_record(side_id: String, index: int, x_offset: float, facing_yaw: float) -> void:
	if _gecs == null or not _gecs.has_method("upsert_population_record_core"):
		return
	var actor_id := _actor_id_for_side(side_id, index)
	var is_left := side_id == PLAYER_SIDE_ID
	_gecs.call("upsert_population_record_core", {
		"actor_id": actor_id,
		"stable_id": actor_id,
		"member_id": actor_id,
		"member_name": _member_name_for_actor(side_id, index),
		"faction_id": PLAYER_FACTION_ID if is_left else RAIDER_FACTION_ID,
		"squad_name": "Left Combatants" if is_left else "Right Combatants",
		"party_id": PLAYER_PARTY_ID if is_left else "",
		"player_party_member": is_left,
		"player_controllable": is_left,
		"role_id": "combat_projection_actor",
		"projection_kind": "humanoid",
		"life_state": 0,
		"hp": 100.0,
		"max_hp": 100.0,
		"blood": 5.0,
		"max_blood": 5.0,
		"base_attack_damage": 18.0 if is_left else 16.0,
		"base_dodge_chance": 0.08 if is_left else 0.05,
		"base_block_chance": 0.08,
		"combat_stance": 1 if is_left else 0,
		"movement_mode": 0,
		"realization_state": "ledger",
		"ledger_activity_state": "defensive_hold" if is_left else "raiding_seek_target",
		"control_intent": _initial_visible_combat_intent(is_left),
		"last_world_position": _formation_position(side_id, index, x_offset),
		"last_world_position_initialized": true,
		"world_facing_yaw": facing_yaw,
		"world_facing_yaw_initialized": true,
		"locomotion_state": {"animation_state": "idle", "speed": 0.0, "horizontal_speed": 0.0},
		"projection_sort_key": "%03d:%s" % [index, side_id],
		"appearance": _appearance_for_actor(side_id, index),
		"skill_levels": _skill_levels_for_actor(index),
		"important": true,
	})


func _initial_visible_combat_intent(is_player_party: bool) -> Dictionary:
	return {
		"source": "defensive_hold" if is_player_party else "ai_raiding",
		"mode": "hold_until_attacked" if is_player_party else "seek_visible_target",
	}


func _squad_records() -> Dictionary:
	return {
		_squad_id_for_side(PLAYER_SIDE_ID): _squad_record(PLAYER_SIDE_ID, side_a_count, -side_separation * 0.5),
		_squad_id_for_side(RAIDER_SIDE_ID): _squad_record(RAIDER_SIDE_ID, side_b_count, side_separation * 0.5),
	}


func _squad_record(side_id: String, member_count: int, x_offset: float) -> Dictionary:
	var is_left := side_id == PLAYER_SIDE_ID
	var location := Vector3(x_offset, 0.0, 0.0)
	var count := maxi(1, member_count)
	return {
		"squad_id": _squad_id_for_side(side_id),
		"faction_id": PLAYER_FACTION_ID if is_left else RAIDER_FACTION_ID,
		"party_id": PLAYER_PARTY_ID if is_left else "",
		"player_owned": is_left,
		"squad_name": "Left Combatants" if is_left else "Right Combatants",
		"location": location,
		"objective_id": "defend_player_party" if is_left else "raid",
		"objective_state": "defensive_hold" if is_left else "raiding",
		"target_location": Vector3.ZERO,
		"route": [location, Vector3.ZERO],
		"speed": 0.0,
		"arrival_threshold": 0.0,
		"arrival_state": "idle",
		"home_location": location,
		"active_encounter_id": "",
		"last_encounter_id": "",
		"member_count": count,
		"member_ids": _side_member_ids(side_id, count),
		"member_name_prefix": "Left" if is_left else "Right",
		"strength": float(count) * (18.0 if is_left else 16.0),
		"base_strength": 0.0,
		"base_attack_damage": 18.0 if is_left else 16.0,
		"max_hp": 100.0,
		"combat_stance": 1 if is_left else 0,
		"hostile_faction_ids": [RAIDER_FACTION_ID] if is_left else [PLAYER_FACTION_ID],
		"morale": 1.0,
		"supplies": 40.0,
		"state": "defensive" if is_left else "raiding",
		"visible_runtime_combat": true,
	}


func _combat_start_request() -> Dictionary:
	var resolve_to_completion := true
	return {
		"encounter_id": _active_encounter_id,
		"initial_intent": "raid",
		"source_type": "visible_combat_beat_projection_test",
		"encounter_center": Vector3.ZERO,
		"projection_importance": "important",
		"visibility_flags": {"force_visible": true},
		"projection_flags": {"important": true},
		"battle_sim_config": {
			"rounds": battle_rounds,
			"detailed_beat_limit": detailed_beat_limit,
			"resolve_to_completion": resolve_to_completion,
			"max_completion_beats": maxi(maxi(battle_rounds, 96), _expected_actor_count() * 12),
		},
		"sides": [
			_encounter_side_record(PLAYER_SIDE_ID, side_a_count, -side_separation * 0.5),
			_encounter_side_record(RAIDER_SIDE_ID, side_b_count, side_separation * 0.5),
		],
	}


func _encounter_side_record(side_id: String, member_count: int, x_offset: float) -> Dictionary:
	var is_left := side_id == PLAYER_SIDE_ID
	return {
		"side_id": side_id,
		"faction_id": PLAYER_FACTION_ID if is_left else RAIDER_FACTION_ID,
		"squad_id": _squad_id_for_side(side_id),
		"party_id": PLAYER_PARTY_ID if is_left else "",
		"player_owned": is_left,
		"role_markers": ["player_party"] if is_left else ["raider_party"],
		"member_refs": _encounter_member_refs(side_id, member_count),
		"starting_position": Vector3(x_offset, 0.0, 0.0),
		"projection_importance": "important",
	}


func _encounter_member_refs(side_id: String, member_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(maxi(1, member_count)):
		var actor_id := _actor_id_for_side(side_id, index)
		result.append({
			"member_id": actor_id,
			"actor_id": actor_id,
			"squad_id": _squad_id_for_side(side_id),
			"party_id": PLAYER_PARTY_ID if side_id == PLAYER_SIDE_ID else "",
			"role_markers": ["player_party"] if side_id == PLAYER_SIDE_ID else ["raider_party"],
		})
	return result


func _side_member_ids(side_id: String, member_count: int) -> Array[String]:
	var result: Array[String] = []
	for index in range(maxi(1, member_count)):
		result.append(_actor_id_for_side(side_id, index))
	return result


func _actor_id_for_side(side_id: String, index: int) -> String:
	return "combat_beat.%s.%s.%03d" % [scenario_id, side_id, index + 1]


func _squad_id_for_side(side_id: String) -> String:
	return "combat_beat.%s.%s" % [scenario_id, side_id]


func _formation_position(side_id: String, index: int, x_offset: float) -> Vector3:
	var side_count := side_a_count if side_id == PLAYER_SIDE_ID else side_b_count
	var columns := maxi(1, mini(formation_columns, side_count))
	var row := int(index / columns)
	var column := index % columns
	var centered_column := float(column) - float(columns - 1) * 0.5
	var side_direction := -1.0 if x_offset < 0.0 else 1.0
	return Vector3(x_offset + side_direction * float(row) * actor_spacing, 0.0, centered_column * actor_spacing)


func _member_name_for_actor(side_id: String, index: int) -> String:
	var left_names := ["Mira", "Tomas", "Ren", "Kiva", "Sable", "Orin", "Dara", "Voss", "Nia", "Cal"]
	var right_names := ["Dustknife", "Scrapjack", "Razor", "Ash", "Grub", "Cinder", "Brack", "Wretch", "Hook", "Maw"]
	var names := left_names if side_id == PLAYER_SIDE_ID else right_names
	return "%s %02d" % [names[index % names.size()], int(index / names.size()) + 1]


func _appearance_for_actor(side_id: String, index: int) -> Dictionary:
	var female := index % 3 == 0 if side_id == PLAYER_SIDE_ID else index % 4 == 1
	return {
		"body_archetype": HUMAN_FEMALE_BODY_PATH if female else HUMAN_MALE_BODY_PATH,
		"character_race": HUMAN_RACE_PATH,
		"visual_body_type": 3 if female else 2,
		"skin_color": Color(0.78 - float(index % 4) * 0.06, 0.58 - float(index % 3) * 0.04, 0.43 - float(index % 2) * 0.03, 1.0),
		"skin_color_customized": true,
	}


func _skill_levels_for_actor(index: int) -> Dictionary:
	return {
		"attribute.strength": 4.0 + float(index % 3),
		"attribute.dexterity": 4.0 + float(index % 2),
		"attribute.toughness": 4.0,
		"attribute.endurance": 4.0,
		"combat.unarmed": 5.0,
		"combat.swords_one_handed": 3.0,
		"combat.shields": 2.0,
	}


func _record_frame_sample(delta: float) -> void:
	if delta <= 0.0:
		return
	var fps := 1.0 / delta
	_fps_sum += fps
	_min_fps = minf(_min_fps, fps)
	_fps_frame_count += 1
	_fps_elapsed_seconds += delta


func _average_fps() -> float:
	return _fps_sum / maxf(float(_fps_frame_count), 1.0)


func _projection_metrics() -> Dictionary:
	if _projection != null and _projection.has_method("get_projection_performance_metrics"):
		var metrics = _projection.call("get_projection_performance_metrics")
		return metrics if metrics is Dictionary else {}
	return {}


func _active_animation_count() -> int:
	var projection_root := get_node_or_null(PROJECTION_ROOT_NAME)
	if projection_root == null:
		return 0
	var count := 0
	for child in projection_root.get_children():
		if child == null or not child.has_method("get_projection_debug_state"):
			continue
		var debug_value = child.call("get_projection_debug_state")
		var debug_state: Dictionary = debug_value if debug_value is Dictionary else {}
		var body_state: Dictionary = debug_state.get("body_state", {}) if debug_state.get("body_state", {}) is Dictionary else {}
		if not str(body_state.get("world_animation", "")).strip_edges().is_empty():
			count += 1
	return count


func _gecs_tick_ms() -> float:
	if _runner != null and _runner.has_method("get_average_tick_time_ms"):
		return float(_runner.call("get_average_tick_time_ms"))
	return 0.0


func _expected_actor_count() -> int:
	return maxi(0, side_a_count) + maxi(0, side_b_count)


func _expected_projected_actor_count() -> int:
	var expected := _expected_actor_count()
	return mini(expected, projection_actor_cap) if projection_actor_cap > 0 else expected


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "CombatBeatProjectionUILayer"
	_ui_layer.layer = 40
	add_child(_ui_layer)
	var panel := PanelContainer.new()
	panel.name = "CombatBeatProjectionPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(520.0, 92.0)
	_ui_layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_status_label = Label.new()
	_metrics_label = Label.new()
	_status_label.text = "CombatBeat projection starting..."
	_metrics_label.text = "Metrics pending"
	column.add_child(_status_label)
	column.add_child(_metrics_label)


func _render_ui() -> void:
	if _metrics_label == null:
		return
	var state := get_benchmark_state()
	var projection: Dictionary = state.get("combat_projection", {}) if state.get("combat_projection", {}) is Dictionary else {}
	_metrics_label.text = "FPS %.1f | actors %d/%d | events %d active %d | anim %d | groups %d | skipped %d | update %.3f ms" % [
		float(state.get("average_fps", 0.0)),
		int(state.get("projected_actor_count", 0)),
		int(state.get("expected_actor_count", 0)),
		int(projection.get("combat_projection_scheduled_event_count", 0)),
		int(projection.get("combat_projection_active_event_count", 0)),
		int(state.get("active_animation_count", 0)),
		int(projection.get("combat_projection_engagement_group_count", 0)),
		int(projection.get("combat_projection_skipped_beat_count", 0)),
		float(projection.get("combat_projection_update_ms", 0.0)),
	]


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
