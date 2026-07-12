@tool
extends Resource

class_name SkillCheckDefinition

const SKILL_CHECK_TIER_SCRIPT := preload("res://features/skills/resources/skill_check_tier.gd")
@export var check_id := "skill_check"
@export var display_name := "Skill Check"
@export var primary_skill_id := ""
@export var assisting_attribute_id := ""
@export_range(0.0, 100.0, 0.01) var assisting_attribute_cap := 18.0
@export_range(0.01, 100.0, 0.01) var assisting_attribute_curve := 35.0
@export_range(0.0, 1.0, 0.01) var chance_at_equal_level := 0.5
@export_range(0.0, 0.25, 0.001) var chance_per_level_delta := 0.02
@export_range(0.0, 1.0, 0.01) var minimum_success_chance := 0.01
@export_range(0.0, 1.0, 0.01) var maximum_success_chance := 0.99
@export_range(0.0, 120.0, 0.1) var attempt_duration_seconds := 5.0
@export_range(0.0, 1.0, 0.01) var tool_break_chance_on_failure := 0.15
@export var tiers: Array[Resource] = []


func get_tier(tier_id: String) -> Resource:
	for entry in tiers:
		if entry != null and entry.get_script() == SKILL_CHECK_TIER_SCRIPT and str(entry.get("tier_id")) == tier_id:
			return entry
	return null


func get_valid_tiers() -> Array[Resource]:
	var result: Array[Resource] = []
	for entry in tiers:
		if entry != null and entry.get_script() == SKILL_CHECK_TIER_SCRIPT and entry.has_method("is_valid") and entry.call("is_valid"):
			result.append(entry)
	result.sort_custom(func(a: Resource, b: Resource) -> bool: return int(a.get("difficulty_level")) < int(b.get("difficulty_level")))
	return result
