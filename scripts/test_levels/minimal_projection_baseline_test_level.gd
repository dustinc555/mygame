extends Node3D

class_name MinimalProjectionBaselineTestLevel

const BOOTSTRAP_PATH := NodePath("GameBootstrap")
const PROJECTION_ROOT_NAME := "WorldActorProjections"
const BOOTSTRAP_WAIT_FRAMES := 180
const UI_REFRESH_SECONDS := 0.25
const PLAYER_SIDE_ID := "player_party"
const RAIDER_SIDE_ID := "attacking_raiders"
const PLAYER_FACTION_ID := "Player"
const RAIDER_FACTION_ID := "Raiders"
const PLAYER_PARTY_ID := "player_party"
const PLAYER_SQUAD_NAME := "PlayerParty"
const RAIDER_SQUAD_NAME := "AttackingRaiders"
const HELD_RESOLUTION_POLICY := "hold_engaged"
const HUMAN_RACE_PATH := "res://resources/character_races/human.tres"
const HUMAN_MALE_BODY_PATH := "res://resources/character_body_archetypes/human_male.tres"
const HUMAN_FEMALE_BODY_PATH := "res://resources/character_body_archetypes/human_female.tres"
const HAIR_SIMPLE_PARTED_PATH := "res://resources/character_appearance/hair_simple_parted.tres"
const HAIR_LONG_PATH := "res://resources/character_appearance/hair_long.tres"
const HAIR_BUZZED_PATH := "res://resources/character_appearance/hair_buzzed.tres"
const HAIR_BUZZED_FEMALE_PATH := "res://resources/character_appearance/hair_buzzed_female.tres"
const HAIR_BUNS_PATH := "res://resources/character_appearance/hair_buns.tres"
const EYEBROWS_REGULAR_PATH := "res://resources/character_appearance/eyebrows_regular.tres"
const EYEBROWS_FEMALE_PATH := "res://resources/character_appearance/eyebrows_female.tres"
const BEARD_FULL_PATH := "res://resources/character_appearance/beard_full.tres"

@export var scenario_id := "projection_baseline_1v1"
@export_range(1, 128, 1) var side_a_count := 1
@export_range(1, 128, 1) var side_b_count := 1
@export_range(1, 16, 1) var formation_columns := 8
@export var side_separation := 7.0
@export var actor_spacing := 1.55
@export var auto_start := true
@export var combat_locomotion_projection_enabled := true

var _bootstrap: Node
var _gecs: Node
var _combat: Node
var _projection: Node
var _runner: Node
var _camera_rig: Node
var _ready_for_benchmark := false
var _setup_complete := false
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
	add_to_group("minimal_projection_baseline_test_level")
	_build_ui()
	call_deferred("_prepare_benchmark")


func _process(delta: float) -> void:
	if not _ready_for_benchmark:
		return
	_record_frame_sample(delta)
	_ui_elapsed += delta
	if _ui_elapsed >= UI_REFRESH_SECONDS:
		_ui_elapsed = 0.0
		_render_ui()


func get_benchmark_state() -> Dictionary:
	var projection_metrics := _projection_metrics()
	var encounter_summary := _benchmark_encounter_summary()
	return {
		"ready": _ready_for_benchmark,
		"setup_complete": _setup_complete,
		"scenario_id": scenario_id,
		"scene_path": scene_file_path,
		"expected_actor_count": _expected_actor_count(),
		"projected_actor_count": int(projection_metrics.get("projected_actor_count", 0)),
		"visible_actor_count": int(projection_metrics.get("visible_actor_count", 0)),
		"projection_counts_by_kind": projection_metrics.get("projection_counts_by_kind", {}).duplicate(true) if projection_metrics.get("projection_counts_by_kind", {}) is Dictionary else {},
		"active_animation_count": _active_animation_count(),
		"average_fps": _average_fps(),
		"min_fps": _min_fps if _fps_frame_count > 0 else 0.0,
		"sample_frame_count": _fps_frame_count,
		"sample_elapsed_seconds": _fps_elapsed_seconds,
		"last_projection_sync_ms": _last_projection_sync_ms,
		"average_projection_sync_ms": _average_projection_sync_ms,
		"projection_sync_sample_count": _projection_sync_sample_count,
		"gecs_tick_ms": _gecs_tick_ms(),
		"battle_sim_included": bool(encounter_summary.get("has_battle_result", false)),
		"combat_locomotion_projection_enabled": combat_locomotion_projection_enabled,
		"combat_locomotion_metrics": _projection_locomotion_metrics(projection_metrics),
		"active_held_encounter_count": _active_held_encounter_count(),
		"combat_encounter": encounter_summary,
		"world_squad_summary": _world_squad_summary(),
	}


func get_population_position_snapshot() -> Dictionary:
	var result := {}
	if _gecs == null or not _gecs.has_method("get_population_records_core"):
		return result
	var records = _gecs.call("get_population_records_core")
	if not (records is Dictionary):
		return result
	for actor_id_value in (records as Dictionary).keys():
		var record = (records as Dictionary).get(actor_id_value)
		if not (record is Dictionary):
			continue
		var position = (record as Dictionary).get("last_world_position", null)
		if position is Vector3:
			result[str(actor_id_value)] = position
	return result


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


func _prepare_benchmark() -> void:
	_set_status("Waiting for projection baseline systems...")
	for _frame in range(BOOTSTRAP_WAIT_FRAMES):
		await get_tree().process_frame
		if _bind_systems():
			if auto_start:
				_start_benchmark()
			return
	_set_status("Timed out waiting for GameBootstrap projection systems.")


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


func _start_benchmark() -> void:
	if _setup_complete:
		return
	if _gecs.has_method("clear_population_records"):
		_gecs.call("clear_population_records")
	_seed_population_records()
	_seed_world_combat_encounter()
	if _projection != null:
		_projection.set("auto_project", true)
		_projection.set("max_projected_actor_count", 0)
		_projection.set("projection_update_interval_seconds", 0.05)
		_projection.set("combat_locomotion_projection_enabled", combat_locomotion_projection_enabled)
	measure_projection_sync(3)
	if _camera_rig != null and _camera_rig.has_method("focus_world_position"):
		_camera_rig.call("focus_world_position", Vector3.ZERO)
	_setup_complete = true
	_ready_for_benchmark = true
	_set_status("Projection baseline ready: %s actors" % _expected_actor_count())
	_render_ui()


func _seed_population_records() -> void:
	var side_a_offset := -side_separation * 0.5
	var side_b_offset := side_separation * 0.5
	for index in range(side_a_count):
		_upsert_actor_record(PLAYER_SIDE_ID, index, side_a_offset, PI)
	for index in range(side_b_count):
		_upsert_actor_record(RAIDER_SIDE_ID, index, side_b_offset, 0.0)


func _seed_world_combat_encounter() -> void:
	if _runner == null or not _runner.has_method("queue_command"):
		return
	_runner.call("queue_command", {
		"action": "replace_world_squads",
		"active_squads": _benchmark_squad_records(),
		"label": "Seed projection benchmark player-vs-raider squads",
	})
	_runner.call("queue_command", {
		"action": "start_combat_encounter",
		"start_request": _held_combat_start_request(),
		"label": "Start held projection benchmark combat encounter",
	})
	_flush_fixed_tick_commands()
	if _runner.has_method("stop"):
		_runner.call("stop")


func _flush_fixed_tick_commands() -> void:
	if _runner != null and _runner.has_method("advance_time") and _runner.has_method("get_fixed_delta"):
		_runner.call("advance_time", float(_runner.call("get_fixed_delta")))


func _upsert_actor_record(side_id: String, index: int, x_offset: float, facing_yaw: float) -> void:
	if _gecs == null:
		return
	var actor_id := _actor_id_for_side(side_id, index)
	var is_player := side_id == PLAYER_SIDE_ID
	var record := {
		"actor_id": actor_id,
		"stable_id": actor_id,
		"member_name": _member_name_for_actor(side_id, index),
		"faction_id": PLAYER_FACTION_ID if is_player else RAIDER_FACTION_ID,
		"squad_name": PLAYER_SQUAD_NAME if is_player else RAIDER_SQUAD_NAME,
		"role_id": "party_member" if is_player else "raider",
		"party_id": PLAYER_PARTY_ID if is_player else "",
		"player_party_member": is_player,
		"player_controllable": is_player,
		"projection_kind": "humanoid",
		"hostile_faction_ids": [RAIDER_FACTION_ID] if is_player else [PLAYER_FACTION_ID],
		"life_state": 0,
		"hp": 100.0,
		"max_hp": 100.0,
		"blood": 5.0,
		"max_blood": 5.0,
		"base_attack_damage": 20.0 if is_player else 14.0,
		"base_dodge_chance": 0.05 if is_player else 0.0,
		"base_block_chance": 0.05,
		"realization_state": "ledger",
		"ledger_activity_state": "projection_baseline",
		"last_world_position": _formation_position(index, x_offset),
		"last_world_position_initialized": true,
		"world_facing_yaw": facing_yaw,
		"world_facing_yaw_initialized": true,
		"locomotion_state": {"animation_state": "idle", "speed": 0.0, "horizontal_speed": 0.0},
		"projection_goal_position": _combat_goal_position(side_id, index, x_offset),
		"projection_locomotion_speed": 2.35,
		"projection_side_id": side_id,
		"projection_squad_id": _squad_id_for_side(side_id),
		"projection_locomotion_bounds": _projection_bounds_for_side(side_id),
		"traits": _traits_for_side(side_id),
		"appearance": _appearance_for_actor(side_id, index),
		"equipment_slots": _equipment_slots_for_actor(side_id, index),
		"skill_levels": _skill_levels_for_actor(side_id, index),
		"personality": _personality_for_actor(index),
		"important": true,
	}
	_upsert_population_record(record)


func _upsert_population_record(record: Dictionary) -> void:
	if _gecs == null:
		return
	if _gecs.has_method("upsert_population_record"):
		_gecs.call("upsert_population_record", record)
		return
	if _gecs.has_method("upsert_population_record_core"):
		_gecs.call("upsert_population_record_core", record)


func _benchmark_squad_records() -> Dictionary:
	var side_a_offset := -side_separation * 0.5
	var side_b_offset := side_separation * 0.5
	var records := {}
	records[_squad_id_for_side(PLAYER_SIDE_ID)] = _squad_record(PLAYER_SIDE_ID, side_a_count, side_a_offset)
	records[_squad_id_for_side(RAIDER_SIDE_ID)] = _squad_record(RAIDER_SIDE_ID, side_b_count, side_b_offset)
	return records


func _squad_record(side_id: String, member_count: int, x_offset: float) -> Dictionary:
	var is_player := side_id == PLAYER_SIDE_ID
	var location := Vector3(x_offset, 0.0, 0.0)
	var count := maxi(1, member_count)
	return {
		"squad_id": _squad_id_for_side(side_id),
		"faction_id": PLAYER_FACTION_ID if is_player else RAIDER_FACTION_ID,
		"party_id": PLAYER_PARTY_ID if is_player else "",
		"squad_name": PLAYER_SQUAD_NAME if is_player else RAIDER_SQUAD_NAME,
		"location": location,
		"objective_id": "defend_player_party" if is_player else "raid",
		"objective_state": "idle",
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
		"member_name_prefix": "Player Party" if is_player else "Attacking Raider",
		"strength": float(count) * (12.0 if is_player else 10.0),
		"base_strength": 0.0,
		"base_attack_damage": 12.0 if is_player else 10.0,
		"max_hp": 100.0,
		"combat_stance": 1,
		"hostile_faction_ids": [RAIDER_FACTION_ID] if is_player else [PLAYER_FACTION_ID],
		"base_color": Color(0.22, 0.52, 0.95, 1.0) if is_player else Color(0.82, 0.22, 0.18, 1.0),
		"morale": 1.0,
		"supplies": 10.0,
		"state": "idle",
		"role_markers": ["player_party"] if is_player else ["raider", "attacker", "hostile"],
	}


func _held_combat_start_request() -> Dictionary:
	return {
		"encounter_id": _encounter_id(),
		"initial_intent": "raid",
		"resolution_policy": HELD_RESOLUTION_POLICY,
		"source_type": "projection_locomotion_benchmark",
		"encounter_center": Vector3.ZERO,
		"projection_importance": "important",
		"visibility_flags": {"force_visible": true},
		"projection_flags": {"important": true},
		"raid_context": {"attacker_side_id": RAIDER_SIDE_ID, "defender_side_id": PLAYER_SIDE_ID},
		"sides": [
			_encounter_side_record(PLAYER_SIDE_ID, side_a_count, -side_separation * 0.5),
			_encounter_side_record(RAIDER_SIDE_ID, side_b_count, side_separation * 0.5),
		],
	}


func _encounter_side_record(side_id: String, member_count: int, x_offset: float) -> Dictionary:
	var is_player := side_id == PLAYER_SIDE_ID
	return {
		"side_id": side_id,
		"faction_id": PLAYER_FACTION_ID if is_player else RAIDER_FACTION_ID,
		"party_id": PLAYER_PARTY_ID if is_player else "",
		"squad_id": _squad_id_for_side(side_id),
		"player_owned": is_player,
		"role_markers": ["player_party"] if is_player else ["raider", "attacker", "hostile"],
		"member_refs": _encounter_member_refs(side_id, member_count),
		"starting_position": Vector3(x_offset, 0.0, 0.0),
		"projection_importance": "important",
	}


func _encounter_member_refs(side_id: String, member_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var is_player := side_id == PLAYER_SIDE_ID
	for index in range(maxi(1, member_count)):
		var actor_id := _actor_id_for_side(side_id, index)
		result.append({
			"member_id": actor_id,
			"actor_id": actor_id,
			"squad_id": _squad_id_for_side(side_id),
			"party_id": PLAYER_PARTY_ID if is_player else "",
			"role_markers": ["player_party"] if is_player else ["raider", "attacker", "hostile"],
		})
	return result


func _side_member_ids(side_id: String, member_count: int) -> Array[String]:
	var result: Array[String] = []
	for index in range(maxi(1, member_count)):
		result.append(_actor_id_for_side(side_id, index))
	return result


func _actor_id_for_side(side_id: String, index: int) -> String:
	return "projection_baseline.%s.%s.%03d" % [scenario_id, side_id, index + 1]


func _squad_id_for_side(side_id: String) -> String:
	return "projection_baseline.%s.%s" % [scenario_id, side_id]


func _encounter_id() -> String:
	return "encounter:%s:held_raid" % scenario_id


func _traits_for_side(side_id: String) -> Dictionary:
	if side_id == PLAYER_SIDE_ID:
		return {"projection_baseline_actor": true, "player_party_member": true}
	return {"projection_baseline_actor": true, "raider": true, "attacker": true, "hostile": true}


func _projection_bounds_for_side(side_id: String) -> Dictionary:
	if side_id == PLAYER_SIDE_ID:
		return {"max_x": -0.35}
	return {"min_x": 0.35}


func _member_name_for_actor(side_id: String, index: int) -> String:
	if side_id == PLAYER_SIDE_ID:
		var player_names := ["Mira", "Tomas", "Ren", "Kiva", "Sable", "Orin", "Dara", "Voss", "Nia", "Cal"]
		return "%s %02d" % [player_names[index % player_names.size()], int(index / player_names.size()) + 1]
	var raider_names := ["Dustknife", "Scrapjack", "Razor", "Ash", "Grub", "Cinder", "Brack", "Wretch", "Hook", "Maw"]
	return "%s Raider %02d" % [raider_names[index % raider_names.size()], int(index / raider_names.size()) + 1]


func _appearance_for_actor(side_id: String, index: int) -> Dictionary:
	var female := index % 3 == 0 if side_id == PLAYER_SIDE_ID else index % 4 == 1
	var skin_colors := [
		Color(0.88, 0.68, 0.54, 1.0),
		Color(0.66, 0.43, 0.30, 1.0),
		Color(0.52, 0.34, 0.24, 1.0),
		Color(0.74, 0.56, 0.43, 1.0),
	]
	var hair_colors := [
		Color(0.16, 0.11, 0.07, 1.0),
		Color(0.12, 0.075, 0.045, 1.0),
		Color(0.32, 0.22, 0.13, 1.0),
		Color(0.08, 0.075, 0.065, 1.0),
	]
	var hair_style := _hair_style_for_actor(female, index)
	var eyebrow_style := EYEBROWS_FEMALE_PATH if female else EYEBROWS_REGULAR_PATH
	var hair_color: Color = hair_colors[index % hair_colors.size()]
	return {
		"beard_color": hair_color,
		"beard_style": "" if female or index % 2 == 0 else BEARD_FULL_PATH,
		"body_archetype": HUMAN_FEMALE_BODY_PATH if female else HUMAN_MALE_BODY_PATH,
		"character_race": HUMAN_RACE_PATH,
		"eyebrow_color": hair_color,
		"eyebrow_style": eyebrow_style,
		"hair_color": hair_color,
		"hair_style": hair_style,
		"height_slider": -0.05 + float(index % 7) * 0.025,
		"skin_color": skin_colors[index % skin_colors.size()],
		"skin_color_customized": true,
		"visual_body_type": 3 if female else 2,
	}


func _hair_style_for_actor(female: bool, index: int) -> String:
	if female:
		var female_hair := [HAIR_LONG_PATH, HAIR_BUNS_PATH, HAIR_BUZZED_FEMALE_PATH]
		return female_hair[index % female_hair.size()]
	var male_hair := [HAIR_SIMPLE_PARTED_PATH, HAIR_BUZZED_PATH]
	return male_hair[index % male_hair.size()]


func _equipment_slots_for_actor(side_id: String, index: int) -> Dictionary:
	if side_id == PLAYER_SIDE_ID:
		return _player_equipment_slots(index)
	return _raider_equipment_slots(index)


func _player_equipment_slots(index: int) -> Dictionary:
	match index % 4:
		0:
			return {
				"head": "res://resources/items/equipment/armor/head/ranger_hood.tres",
				"chest": "res://resources/items/equipment/armor/chest/ranger_jerkin.tres",
				"legs": "res://resources/items/equipment/armor/legs/ranger_leggings.tres",
				"feet": "res://resources/items/equipment/armor/feet/ranger_boots.tres",
				"weapon": "res://resources/items/equipment/weapons/swords/steel_sword.tres",
				"offhand": "res://resources/items/equipment/offhand/shields/round_shield.tres",
			}
		1:
			return {
				"chest": "res://resources/items/equipment/clothing/peasant_tunic.tres",
				"legs": "res://resources/items/equipment/clothing/peasant_trousers.tres",
				"feet": "res://resources/items/equipment/clothing/peasant_shoes.tres",
				"weapon": "res://resources/items/equipment/weapons/axes/iron_axe.tres",
			}
		2:
			return {
				"head": "res://resources/items/equipment/armor/head/knight_armet.tres",
				"chest": "res://resources/items/equipment/armor/chest/knight_cuirass.tres",
				"legs": "res://resources/items/equipment/armor/legs/knight_greaves.tres",
				"feet": "res://resources/items/equipment/armor/feet/knight_sabatons.tres",
				"hands": "res://resources/items/equipment/armor/hands/knight_gauntlets.tres",
				"weapon": "res://resources/items/equipment/weapons/hammers/war_hammer.tres",
				"offhand": "res://resources/items/equipment/offhand/shields/heater_shield.tres",
			}
		_:
			return {
				"chest": "res://resources/items/equipment/clothing/noble_doublet.tres",
				"legs": "res://resources/items/equipment/clothing/noble_trousers.tres",
				"feet": "res://resources/items/equipment/clothing/noble_shoes.tres",
				"weapon": "res://resources/items/equipment/weapons/daggers/steel_dagger.tres",
			}


func _raider_equipment_slots(index: int) -> Dictionary:
	match index % 4:
		0:
			return {
				"chest": "res://resources/items/equipment/clothing/peasant_tunic.tres",
				"legs": "res://resources/items/equipment/clothing/peasant_trousers.tres",
				"feet": "res://resources/items/equipment/clothing/peasant_shoes.tres",
				"weapon": "res://resources/items/equipment/weapons/axes/hatchet.tres",
			}
		1:
			return {
				"head": "res://resources/items/equipment/armor/head/ranger_hood.tres",
				"chest": "res://resources/items/equipment/armor/chest/ranger_jerkin.tres",
				"legs": "res://resources/items/equipment/armor/legs/ranger_leggings.tres",
				"feet": "res://resources/items/equipment/armor/feet/ranger_boots.tres",
				"weapon": "res://resources/items/equipment/weapons/daggers/iron_dagger.tres",
			}
		2:
			return {
				"chest": "res://resources/items/equipment/armor/chest/knight_gambeson.tres",
				"legs": "res://resources/items/equipment/clothing/peasant_trousers.tres",
				"feet": "res://resources/items/equipment/clothing/peasant_shoes.tres",
				"weapon": "res://resources/items/equipment/weapons/polearms/spear.tres",
			}
		_:
			return {
				"chest": "res://resources/items/equipment/clothing/noble_doublet.tres",
				"legs": "res://resources/items/equipment/clothing/noble_trousers.tres",
				"feet": "res://resources/items/equipment/clothing/noble_shoes.tres",
				"weapon": "res://resources/items/equipment/weapons/swords/iron_sword.tres",
				"offhand": "res://resources/items/equipment/offhand/shields/painted_round_shield.tres",
			}


func _skill_levels_for_actor(side_id: String, index: int) -> Dictionary:
	var base := 45 + (index % 6) * 3
	if side_id == RAIDER_SIDE_ID:
		base = 34 + (index % 5) * 3
	return {
		"attribute.strength": base,
		"attribute.perception": base - 4,
		"attribute.dexterity": base + 2,
		"attribute.toughness": base,
		"attribute.endurance": base,
		"combat.swords_one_handed": base,
		"combat.axes_one_handed": base - 2,
		"combat.daggers": base - 6,
		"combat.shields": base - 4,
	}


func _personality_for_actor(index: int) -> Dictionary:
	return {
		"discipline": 0.45 + float(index % 6) * 0.06,
		"nerve": 0.50 + float(index % 5) * 0.07,
	}


func _formation_position(index: int, x_offset: float) -> Vector3:
	var side_count := _side_count_for_x(x_offset)
	var columns := maxi(1, mini(formation_columns, side_count))
	var row := int(index / columns)
	var column := index % columns
	var centered_column := float(column) - float(columns - 1) * 0.5
	var side_direction := -1.0 if x_offset < 0.0 else 1.0
	return Vector3(x_offset + side_direction * float(row) * actor_spacing, 0.0, centered_column * actor_spacing)


func _combat_goal_position(side_id: String, index: int, x_offset: float) -> Vector3:
	var start := _formation_position(index, x_offset)
	var side_count := _side_count_for_x(x_offset)
	var columns := maxi(1, mini(formation_columns, side_count))
	var row := int(index / columns)
	var side_direction := -1.0 if side_id == PLAYER_SIDE_ID else 1.0
	var front_x := -0.9 if side_id == PLAYER_SIDE_ID else 0.9
	return Vector3(front_x + side_direction * float(row) * 1.05, start.y, start.z)


func _side_count_for_x(x_offset: float) -> int:
	return side_a_count if x_offset < 0.0 else side_b_count


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


func _projection_locomotion_metrics(projection_metrics: Dictionary) -> Dictionary:
	return {
		"enabled": bool(projection_metrics.get("combat_locomotion_enabled", false)),
		"actor_count": int(projection_metrics.get("combat_locomotion_actor_count", 0)),
		"pair_check_count": int(projection_metrics.get("combat_locomotion_pair_checks", 0)),
		"max_allowed_pair_checks": int(projection_metrics.get("combat_locomotion_max_pair_checks", 0)),
		"overlap_violations": int(projection_metrics.get("combat_locomotion_overlap_violations", 0)),
		"pass_through_violations": int(projection_metrics.get("combat_locomotion_pass_through_violations", 0)),
	}


func _benchmark_encounter_summary() -> Dictionary:
	if _combat == null or not _combat.has_method("get_world_encounter_state"):
		return {}
	var state = _combat.call("get_world_encounter_state")
	if not (state is Dictionary):
		return {}
	var encounters = (state as Dictionary).get("encounters_by_id", {})
	if not (encounters is Dictionary):
		return {}
	var encounter = (encounters as Dictionary).get(_encounter_id(), {})
	if not (encounter is Dictionary):
		return {}
	var record: Dictionary = encounter
	var start_request: Dictionary = record.get("start_request", {}) if record.get("start_request", {}) is Dictionary else {}
	return {
		"encounter_id": str(record.get("encounter_id", "")),
		"status": str(record.get("status", "")),
		"initial_intent": str(record.get("initial_intent", record.get("reason", ""))),
		"resolution_policy": str(record.get("resolution_policy", "")),
		"squad_ids": _string_array(record.get("squad_ids", [])),
		"side_ids": _string_array(record.get("side_ids", [])),
		"faction_ids": _string_array(record.get("faction_ids", [])),
		"party_ids": _string_array(record.get("party_ids", [])),
		"player_owned_side_id": str(record.get("player_owned_side_id", "")),
		"has_battle_result": record.has("battle_result"),
		"start_request_side_count": (start_request.get("sides", []) as Array).size() if start_request.get("sides", []) is Array else 0,
	}


func _active_held_encounter_count() -> int:
	if _combat == null or not _combat.has_method("get_world_encounter_state"):
		return 0
	var state = _combat.call("get_world_encounter_state")
	if not (state is Dictionary):
		return 0
	var encounters = (state as Dictionary).get("encounters_by_id", {})
	if not (encounters is Dictionary):
		return 0
	var count := 0
	for encounter_id in (encounters as Dictionary).keys():
		var encounter = (encounters as Dictionary).get(encounter_id)
		if encounter is Dictionary and str((encounter as Dictionary).get("status", "")) == "engaged" and str((encounter as Dictionary).get("resolution_policy", "")) == HELD_RESOLUTION_POLICY:
			count += 1
	return count


func _world_squad_summary() -> Dictionary:
	var result := {}
	if _combat == null or not _combat.has_method("get_world_squad_state"):
		return result
	var state = _combat.call("get_world_squad_state")
	if not (state is Dictionary):
		return result
	var active_squads = (state as Dictionary).get("active_squads", {})
	if not (active_squads is Dictionary):
		return result
	for squad_id in [_squad_id_for_side(PLAYER_SIDE_ID), _squad_id_for_side(RAIDER_SIDE_ID)]:
		var squad = (active_squads as Dictionary).get(squad_id, {})
		if not (squad is Dictionary):
			continue
		var record: Dictionary = squad
		result[squad_id] = {
			"squad_id": str(record.get("squad_id", "")),
			"faction_id": str(record.get("faction_id", "")),
			"party_id": str(record.get("party_id", "")),
			"squad_name": str(record.get("squad_name", "")),
			"state": str(record.get("state", "")),
			"active_encounter_id": str(record.get("active_encounter_id", "")),
			"member_count": int(record.get("member_count", 0)),
			"member_ids": _string_array(record.get("member_ids", [])),
			"hostile_faction_ids": _string_array(record.get("hostile_faction_ids", [])),
		}
	return result


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for entry in value:
		var text := str(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


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


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "ProjectionBaselineUILayer"
	add_child(_ui_layer)
	var panel := PanelContainer.new()
	panel.name = "ProjectionBaselinePanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(420.0, 86.0)
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
	_status_label.text = "Projection baseline starting..."
	_metrics_label.text = "Metrics pending"
	column.add_child(_status_label)
	column.add_child(_metrics_label)


func _render_ui() -> void:
	if _metrics_label == null:
		return
	var state := get_benchmark_state()
	_metrics_label.text = "FPS avg %.1f min %.1f | actors %d/%d visible %d | anim %d | sync %.3f ms | tick %.3f ms" % [
		float(state.get("average_fps", 0.0)),
		float(state.get("min_fps", 0.0)),
		int(state.get("projected_actor_count", 0)),
		int(state.get("expected_actor_count", 0)),
		int(state.get("visible_actor_count", 0)),
		int(state.get("active_animation_count", 0)),
		float(state.get("average_projection_sync_ms", 0.0)),
		float(state.get("gecs_tick_ms", 0.0)),
	]


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text
