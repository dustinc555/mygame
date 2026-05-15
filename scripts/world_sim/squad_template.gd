extends Resource

class_name SquadTemplate

@export var template_id := ""
@export var display_name := "Squad"
@export var faction_definition: Resource
@export var member_name_prefix := "Squad Member"
@export_range(1, 24, 1) var member_count := 3
@export var base_strength := 20.0
@export var food_capacity := 30.0
@export var base_color := Color(0.62, 0.62, 0.62, 1.0)
@export var max_hp := 100.0
@export var base_attack_damage := 18.0
@export_range(0, 2, 1) var combat_stance := NpcRules.CombatStance.DEFENSIVE
@export var hostile_faction_ids: PackedStringArray = PackedStringArray()
@export var starting_equipment: Array[Resource] = []


func get_id() -> String:
	return template_id if not template_id.is_empty() else display_name


func get_faction_id() -> String:
	return str(faction_definition.call("get_id")) if faction_definition != null and faction_definition.has_method("get_id") else ""
