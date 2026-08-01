extends "res://addons/gecs/ecs/component.gd"

class_name CGamePopulationRecord

@export var actor_id := ""
@export var stable_id := ""
@export var settlement_id := ""
@export var generation_source := ""
@export var generation_index := 0
@export var member_name := ""
@export var birth_day_index := CharacterAgeRules.UNKNOWN_BIRTH_DAY
@export var actor_script_path := ""
@export var character_realizer_id := ""
@export var character_realizer_path := ""
@export var character_realizer_signature := ""
@export var character_type_id := ""
@export var character_type_path := ""
@export var character_type_signature := ""
@export var faction_id := ""
@export var party_id := ""
@export var squad_name := ""
@export var role_id := "resident"
@export var assignments: Dictionary = {}
@export var assignment_authority_scopes: Dictionary = {}
@export var assignment_exclusivity_groups: Dictionary = {}
@export var assignment_realized_once: Dictionary = {}
@export var hostile_faction_ids: PackedStringArray = PackedStringArray()
@export var combat_stance := 0
@export var auto_heal_enabled := false
@export var auto_burn_rustdead_enabled := false
@export var base_color := Color(0.62, 0.62, 0.62, 1.0)
@export var skill_levels: Dictionary = {}
@export var skill_xp: Dictionary = {}
@export var needs_state: Dictionary = {}
@export var movement_state: Dictionary = {}
@export var traits: Dictionary = {}
@export var personality: Dictionary = {}
@export var life_state := 0
## Durable physical disposition. Death creates a corpse; only explicit gameplay
## actions may transition it to buried, cremated, or consumed.
@export var body_state := "living"
@export var body_container_id := ""
@export var realization_state := "ledger"
@export var ledger_activity_state := "routine"
@export var ledger_minutes_elapsed := 0
@export var ledger_work_minutes := 0
@export var ledger_rest_minutes := 0
@export var ledger_activity_minutes: Dictionary = {}
@export var last_ledger_absolute_minute := -1
@export var last_world_position := Vector3.ZERO
@export var last_world_position_initialized := false
@export var last_world_transform := Transform3D.IDENTITY
@export var last_world_transform_initialized := false
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


func _set(property: StringName, value: Variant) -> bool:
	if property == &"assigned_slot_id":
		var legacy_slot_id := str(value)
		if not legacy_slot_id.is_empty():
			assignments["employment"] = legacy_slot_id
		return true
	if property == &"staff_assignment_realized_once":
		assignment_realized_once["employment"] = bool(value)
		return true
	return false


func apply_record(source: Dictionary) -> void:
	actor_id = str(source.get("actor_id", source.get("stable_id", actor_id))).strip_edges()
	stable_id = str(source.get("stable_id", actor_id)).strip_edges()
	settlement_id = str(source.get("settlement_id", settlement_id))
	generation_source = str(source.get("generation_source", generation_source))
	generation_index = int(source.get("generation_index", generation_index))
	member_name = str(source.get("member_name", member_name))
	birth_day_index = int(source.get("birth_day_index", birth_day_index))
	actor_script_path = str(source.get("actor_script_path", actor_script_path))
	character_realizer_id = str(source.get("character_realizer_id", character_realizer_id))
	character_realizer_path = str(source.get("character_realizer_path", character_realizer_path))
	character_realizer_signature = str(source.get("character_realizer_signature", character_realizer_signature))
	character_type_id = str(source.get("character_type_id", character_type_id))
	character_type_path = str(source.get("character_type_path", character_type_path))
	character_type_signature = str(source.get("character_type_signature", character_type_signature))
	faction_id = str(source.get("faction_id", faction_id))
	party_id = str(source.get("party_id", party_id))
	squad_name = str(source.get("squad_name", squad_name))
	role_id = str(source.get("role_id", role_id))
	assignments = (source.get("assignments", assignments) as Dictionary).duplicate(true)
	assignment_authority_scopes = (source.get("assignment_authority_scopes", assignment_authority_scopes) as Dictionary).duplicate(true)
	assignment_exclusivity_groups = (source.get("assignment_exclusivity_groups", assignment_exclusivity_groups) as Dictionary).duplicate(true)
	assignment_realized_once = (source.get("assignment_realized_once", assignment_realized_once) as Dictionary).duplicate(true)
	hostile_faction_ids = PackedStringArray(source.get("hostile_faction_ids", hostile_faction_ids))
	combat_stance = int(source.get("combat_stance", combat_stance))
	auto_heal_enabled = bool(source.get("auto_heal_enabled", auto_heal_enabled))
	auto_burn_rustdead_enabled = bool(source.get("auto_burn_rustdead_enabled", auto_burn_rustdead_enabled))
	base_color = source.get("base_color", base_color)
	skill_levels = (source.get("skill_levels", skill_levels) as Dictionary).duplicate(true)
	skill_xp = (source.get("skill_xp", skill_xp) as Dictionary).duplicate(true)
	needs_state = (source.get("needs_state", needs_state) as Dictionary).duplicate(true)
	movement_state = (source.get("movement_state", movement_state) as Dictionary).duplicate(true)
	traits = (source.get("traits", traits) as Dictionary).duplicate(true)
	personality = (source.get("personality", personality) as Dictionary).duplicate(true)
	life_state = int(source.get("life_state", life_state))
	body_state = str(source.get("body_state", "corpse" if life_state == NpcRules.LifeState.DEAD else body_state))
	body_container_id = str(source.get("body_container_id", body_container_id))
	realization_state = str(source.get("realization_state", realization_state))
	ledger_activity_state = str(source.get("ledger_activity_state", ledger_activity_state))
	ledger_minutes_elapsed = int(source.get("ledger_minutes_elapsed", ledger_minutes_elapsed))
	ledger_work_minutes = int(source.get("ledger_work_minutes", ledger_work_minutes))
	ledger_rest_minutes = int(source.get("ledger_rest_minutes", ledger_rest_minutes))
	ledger_activity_minutes = (source.get("ledger_activity_minutes", ledger_activity_minutes) as Dictionary).duplicate(true)
	last_ledger_absolute_minute = int(source.get("last_ledger_absolute_minute", last_ledger_absolute_minute))
	last_world_position = source.get("last_world_position", last_world_position)
	last_world_position_initialized = bool(source.get("last_world_position_initialized", last_world_position_initialized))
	last_world_transform = source.get("last_world_transform", last_world_transform)
	last_world_transform_initialized = bool(source.get("last_world_transform_initialized", last_world_transform_initialized))
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
		"birth_day_index": birth_day_index,
		"actor_script_path": actor_script_path,
		"character_realizer_id": character_realizer_id,
		"character_realizer_path": character_realizer_path,
		"character_realizer_signature": character_realizer_signature,
		"character_type_id": character_type_id,
		"character_type_path": character_type_path,
		"character_type_signature": character_type_signature,
		"faction_id": faction_id,
		"party_id": party_id,
		"squad_name": squad_name,
		"role_id": role_id,
		"assignments": assignments.duplicate(true),
		"assignment_authority_scopes": assignment_authority_scopes.duplicate(true),
		"assignment_exclusivity_groups": assignment_exclusivity_groups.duplicate(true),
		"assignment_realized_once": assignment_realized_once.duplicate(true),
		"hostile_faction_ids": Array(hostile_faction_ids),
		"combat_stance": combat_stance,
		"auto_heal_enabled": auto_heal_enabled,
		"auto_burn_rustdead_enabled": auto_burn_rustdead_enabled,
		"base_color": base_color,
		"skill_levels": skill_levels.duplicate(true),
		"skill_xp": skill_xp.duplicate(true),
		"needs_state": needs_state.duplicate(true),
		"movement_state": movement_state.duplicate(true),
		"traits": traits.duplicate(true),
		"personality": personality.duplicate(true),
		"life_state": life_state,
		"body_state": body_state,
		"body_container_id": body_container_id,
		"realization_state": realization_state,
		"ledger_activity_state": ledger_activity_state,
		"ledger_minutes_elapsed": ledger_minutes_elapsed,
		"ledger_work_minutes": ledger_work_minutes,
		"ledger_rest_minutes": ledger_rest_minutes,
		"ledger_activity_minutes": ledger_activity_minutes.duplicate(true),
		"last_ledger_absolute_minute": last_ledger_absolute_minute,
		"last_world_position": last_world_position,
		"last_world_position_initialized": last_world_position_initialized,
		"last_world_transform": last_world_transform,
		"last_world_transform_initialized": last_world_transform_initialized,
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
