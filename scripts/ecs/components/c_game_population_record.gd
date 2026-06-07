extends "res://addons/gecs/ecs/component.gd"

class_name CGamePopulationRecord

@export var actor_id := ""
@export var stable_id := ""
@export var settlement_id := ""
@export var generation_source := ""
@export var generation_index := 0
@export var member_name := ""
@export var faction_id := ""
@export var squad_name := ""
@export var role_id := "resident"
@export var party_id := ""
@export var player_party_member := false
@export var player_controllable := false
@export var projection_kind := ""
@export var hostile_faction_ids: PackedStringArray = PackedStringArray()
@export var combat_stance := 0
@export var movement_mode := 0
@export var move_order: Dictionary = {}
@export var locomotion_state: Dictionary = {}
@export var world_facing_yaw := 0.0
@export var world_facing_yaw_initialized := false
@export var auto_heal_enabled := false
@export var auto_burn_rustdead_enabled := false
@export var base_color := Color(0.62, 0.62, 0.62, 1.0)
@export var skill_levels: Dictionary = {}
@export var skill_xp: Dictionary = {}
@export var traits: Dictionary = {}
@export var personality: Dictionary = {}
@export var life_state := 0
@export var hunger := 100.0
@export var hunger_stage := 0
@export var fatigue := 100.0
@export var fatigue_stage := 0
@export var hp := 0.0
@export var max_hp := 0.0
@export var blood := 0.0
@export var max_blood := 0.0
@export var open_cut_damage := 0.0
@export var bandaged_cut_damage := 0.0
@export var blunt_damage := 0.0
@export var bleed_rate := 0.0
@export var base_attack_damage := 0.0
@export var base_dodge_chance := 0.0
@export var base_block_chance := 0.0
@export var realization_state := "ledger"
@export var ledger_activity_state := "routine"
@export var ledger_minutes_elapsed := 0
@export var ledger_work_minutes := 0
@export var ledger_rest_minutes := 0
@export var ledger_activity_minutes: Dictionary = {}
@export var last_ledger_absolute_minute := -1
@export var last_world_position := Vector3.ZERO
@export var last_world_position_initialized := false
@export var control_intent: Dictionary = {}
@export var important := false
@export var appearance_character_race := ""
@export var appearance_body_archetype := ""
@export var appearance_visual_body_type := 0
@export var appearance_hair_style := ""
@export var appearance_beard_style := ""
@export var appearance_eyebrow_style := ""
@export var appearance_hair_color := Color.WHITE
@export var appearance_beard_color := Color.WHITE
@export var appearance_eyebrow_color := Color.WHITE
@export var appearance_skin_color_customized := false
@export var appearance_skin_color := Color.WHITE
@export var appearance_height_slider := 0.0
@export var appearance_shoulder_width_slider := 0.0
@export var appearance_arm_length_slider := 0.0
@export var appearance_neck_length_slider := 0.0

var record: Dictionary = {}


func apply_record(source: Dictionary) -> void:
	actor_id = str(source.get("actor_id", source.get("stable_id", actor_id))).strip_edges()
	stable_id = str(source.get("stable_id", actor_id)).strip_edges()
	settlement_id = str(source.get("settlement_id", settlement_id))
	generation_source = str(source.get("generation_source", generation_source))
	generation_index = int(source.get("generation_index", generation_index))
	member_name = str(source.get("member_name", member_name))
	faction_id = str(source.get("faction_id", faction_id))
	squad_name = str(source.get("squad_name", squad_name))
	role_id = str(source.get("role_id", role_id))
	party_id = str(source.get("party_id", party_id))
	player_party_member = bool(source.get("player_party_member", player_party_member))
	player_controllable = bool(source.get("player_controllable", player_controllable))
	projection_kind = str(source.get("projection_kind", projection_kind))
	hostile_faction_ids = PackedStringArray(source.get("hostile_faction_ids", hostile_faction_ids))
	combat_stance = int(source.get("combat_stance", combat_stance))
	movement_mode = int(source.get("movement_mode", movement_mode))
	move_order = (source.get("move_order", move_order) as Dictionary).duplicate(true)
	locomotion_state = (source.get("locomotion_state", locomotion_state) as Dictionary).duplicate(true)
	world_facing_yaw = float(source.get("world_facing_yaw", world_facing_yaw))
	world_facing_yaw_initialized = bool(source.get("world_facing_yaw_initialized", world_facing_yaw_initialized))
	auto_heal_enabled = bool(source.get("auto_heal_enabled", auto_heal_enabled))
	auto_burn_rustdead_enabled = bool(source.get("auto_burn_rustdead_enabled", auto_burn_rustdead_enabled))
	base_color = source.get("base_color", base_color)
	skill_levels = (source.get("skill_levels", skill_levels) as Dictionary).duplicate(true)
	skill_xp = (source.get("skill_xp", skill_xp) as Dictionary).duplicate(true)
	traits = (source.get("traits", traits) as Dictionary).duplicate(true)
	personality = (source.get("personality", personality) as Dictionary).duplicate(true)
	life_state = int(source.get("life_state", life_state))
	hunger = float(source.get("hunger", hunger))
	hunger_stage = int(source.get("hunger_stage", hunger_stage))
	fatigue = float(source.get("fatigue", fatigue))
	fatigue_stage = int(source.get("fatigue_stage", fatigue_stage))
	hp = float(source.get("hp", hp))
	max_hp = float(source.get("max_hp", max_hp))
	blood = float(source.get("blood", blood))
	max_blood = float(source.get("max_blood", max_blood))
	open_cut_damage = float(source.get("open_cut_damage", open_cut_damage))
	bandaged_cut_damage = float(source.get("bandaged_cut_damage", bandaged_cut_damage))
	blunt_damage = float(source.get("blunt_damage", blunt_damage))
	bleed_rate = float(source.get("bleed_rate", bleed_rate))
	base_attack_damage = float(source.get("base_attack_damage", base_attack_damage))
	base_dodge_chance = float(source.get("base_dodge_chance", base_dodge_chance))
	base_block_chance = float(source.get("base_block_chance", base_block_chance))
	realization_state = str(source.get("realization_state", realization_state))
	ledger_activity_state = str(source.get("ledger_activity_state", ledger_activity_state))
	ledger_minutes_elapsed = int(source.get("ledger_minutes_elapsed", ledger_minutes_elapsed))
	ledger_work_minutes = int(source.get("ledger_work_minutes", ledger_work_minutes))
	ledger_rest_minutes = int(source.get("ledger_rest_minutes", ledger_rest_minutes))
	ledger_activity_minutes = (source.get("ledger_activity_minutes", ledger_activity_minutes) as Dictionary).duplicate(true)
	last_ledger_absolute_minute = int(source.get("last_ledger_absolute_minute", last_ledger_absolute_minute))
	last_world_position = source.get("last_world_position", last_world_position)
	last_world_position_initialized = bool(source.get("last_world_position_initialized", last_world_position_initialized))
	control_intent = (source.get("control_intent", control_intent) as Dictionary).duplicate(true)
	important = bool(source.get("important", important))
	var appearance: Dictionary = source.get("appearance", {})
	appearance_character_race = str(appearance.get("character_race", appearance_character_race))
	appearance_body_archetype = str(appearance.get("body_archetype", appearance_body_archetype))
	appearance_visual_body_type = int(appearance.get("visual_body_type", appearance_visual_body_type))
	appearance_hair_style = str(appearance.get("hair_style", appearance_hair_style))
	appearance_beard_style = str(appearance.get("beard_style", appearance_beard_style))
	appearance_eyebrow_style = str(appearance.get("eyebrow_style", appearance_eyebrow_style))
	appearance_hair_color = appearance.get("hair_color", appearance_hair_color)
	appearance_beard_color = appearance.get("beard_color", appearance_beard_color)
	appearance_eyebrow_color = appearance.get("eyebrow_color", appearance_eyebrow_color)
	appearance_skin_color_customized = bool(appearance.get("skin_color_customized", appearance_skin_color_customized))
	appearance_skin_color = appearance.get("skin_color", appearance_skin_color)
	appearance_height_slider = float(appearance.get("height_slider", appearance_height_slider))
	appearance_shoulder_width_slider = float(appearance.get("shoulder_width_slider", appearance_shoulder_width_slider))
	appearance_arm_length_slider = float(appearance.get("arm_length_slider", appearance_arm_length_slider))
	appearance_neck_length_slider = float(appearance.get("neck_length_slider", appearance_neck_length_slider))
	record = to_record()


func to_record() -> Dictionary:
	return {
		"actor_id": actor_id,
		"stable_id": stable_id if not stable_id.is_empty() else actor_id,
		"settlement_id": settlement_id,
		"generation_source": generation_source,
		"generation_index": generation_index,
		"member_name": member_name,
		"faction_id": faction_id,
		"squad_name": squad_name,
		"role_id": role_id,
		"party_id": party_id,
		"player_party_member": player_party_member,
		"player_controllable": player_controllable,
		"projection_kind": projection_kind,
		"hostile_faction_ids": Array(hostile_faction_ids),
		"combat_stance": combat_stance,
		"movement_mode": movement_mode,
		"move_order": move_order.duplicate(true),
		"locomotion_state": locomotion_state.duplicate(true),
		"world_facing_yaw": world_facing_yaw,
		"world_facing_yaw_initialized": world_facing_yaw_initialized,
		"auto_heal_enabled": auto_heal_enabled,
		"auto_burn_rustdead_enabled": auto_burn_rustdead_enabled,
		"base_color": base_color,
		"skill_levels": skill_levels.duplicate(true),
		"skill_xp": skill_xp.duplicate(true),
		"traits": traits.duplicate(true),
		"personality": personality.duplicate(true),
		"life_state": life_state,
		"hunger": hunger,
		"hunger_stage": hunger_stage,
		"fatigue": fatigue,
		"fatigue_stage": fatigue_stage,
		"hp": hp,
		"max_hp": max_hp,
		"blood": blood,
		"max_blood": max_blood,
		"open_cut_damage": open_cut_damage,
		"bandaged_cut_damage": bandaged_cut_damage,
		"blunt_damage": blunt_damage,
		"bleed_rate": bleed_rate,
		"base_attack_damage": base_attack_damage,
		"base_dodge_chance": base_dodge_chance,
		"base_block_chance": base_block_chance,
		"realization_state": realization_state,
		"ledger_activity_state": ledger_activity_state,
		"ledger_minutes_elapsed": ledger_minutes_elapsed,
		"ledger_work_minutes": ledger_work_minutes,
		"ledger_rest_minutes": ledger_rest_minutes,
		"ledger_activity_minutes": ledger_activity_minutes.duplicate(true),
		"last_ledger_absolute_minute": last_ledger_absolute_minute,
		"last_world_position": last_world_position,
		"last_world_position_initialized": last_world_position_initialized,
		"control_intent": control_intent.duplicate(true),
		"important": important,
		"appearance": {
			"character_race": appearance_character_race,
			"body_archetype": appearance_body_archetype,
			"visual_body_type": appearance_visual_body_type,
			"hair_style": appearance_hair_style,
			"beard_style": appearance_beard_style,
			"eyebrow_style": appearance_eyebrow_style,
			"hair_color": appearance_hair_color,
			"beard_color": appearance_beard_color,
			"eyebrow_color": appearance_eyebrow_color,
			"skin_color_customized": appearance_skin_color_customized,
			"skin_color": appearance_skin_color,
			"height_slider": appearance_height_slider,
			"shoulder_width_slider": appearance_shoulder_width_slider,
			"arm_length_slider": appearance_arm_length_slider,
			"neck_length_slider": appearance_neck_length_slider,
		},
	}
