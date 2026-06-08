extends CharacterBody3D

class_name CharacterAuthoringActor

@export var starting_equipment_ids: PackedStringArray = PackedStringArray()
@export var member_name := ""
@export var stable_id := ""
@export var projection_kind := "humanoid"
@export var faction_name := ""
@export var squad_name := ""
@export var hostile_factions: PackedStringArray = PackedStringArray()
@export_range(0, 8, 1) var combat_stance := 0
@export var base_attack_damage := 0.0
@export var base_color := Color(0.62, 0.62, 0.62, 1.0)
@export var starting_skill_levels: Dictionary = {}
@export var starting_skill_xp: Dictionary = {}
@export var life_state := NpcRules.LifeState.ALIVE
@export var hunger := 100.0
@export var hunger_stage := NpcRules.HungerStage.WELL_NOURISHED
@export var fatigue := 100.0
@export var fatigue_stage := NpcRules.FatigueStage.WELL_RESTED
@export var hp := 100.0
@export var max_hp := 100.0
@export var blood := 5.0
@export var max_blood := 5.0
@export var open_cut_damage := 0.0
@export var bandaged_cut_damage := 0.0
@export var blunt_damage := 0.0
@export var bleed_rate := 0.0


func _ready() -> void:
	add_to_group("character_authoring_actor")


func get_authoring_record() -> Dictionary:
	return {
		"actor_id": stable_id,
		"stable_id": stable_id,
		"projection_kind": projection_kind,
		"member_name": member_name if not member_name.is_empty() else str(name),
		"faction_id": faction_name,
		"squad_name": squad_name,
		"hostile_faction_ids": Array(hostile_factions),
		"combat_stance": combat_stance,
		"base_attack_damage": base_attack_damage,
		"base_color": base_color,
		"starting_equipment_ids": Array(starting_equipment_ids),
		"skill_levels": starting_skill_levels.duplicate(true),
		"skill_xp": starting_skill_xp.duplicate(true),
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
		"world_position": global_position,
	}
