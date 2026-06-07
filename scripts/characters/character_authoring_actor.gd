extends CharacterBody3D

class_name CharacterAuthoringActor

@export var starting_equipment: Array[Resource] = []
@export var member_name := ""
@export var stable_id := ""
@export var faction_name := ""
@export var squad_name := ""
@export var hostile_factions: PackedStringArray = PackedStringArray()
@export_range(0, 8, 1) var combat_stance := 0
@export var base_attack_damage := 0.0
@export var base_color := Color(0.62, 0.62, 0.62, 1.0)
@export var starting_skill_levels: Dictionary = {}
@export var life_state := NpcRules.LifeState.ALIVE
@export var hp := 100.0
@export var max_hp := 100.0
@export var blood := 5.0
@export var max_blood := 5.0


func _ready() -> void:
	add_to_group("character_authoring_actor")


func get_authoring_record() -> Dictionary:
	return {
		"actor_id": stable_id,
		"stable_id": stable_id,
		"member_name": member_name if not member_name.is_empty() else str(name),
		"faction_id": faction_name,
		"squad_name": squad_name,
		"hostile_faction_ids": Array(hostile_factions),
		"combat_stance": combat_stance,
		"base_attack_damage": base_attack_damage,
		"base_color": base_color,
		"skill_levels": starting_skill_levels.duplicate(true),
		"life_state": life_state,
		"hp": hp,
		"max_hp": max_hp,
		"blood": blood,
		"max_blood": max_blood,
		"world_position": global_position,
	}
