@tool
extends Resource

class_name SkillCheckTier

@export var tier_id := "tier"
@export var display_name := "Tier"
@export_range(1, 100, 1) var difficulty_level := 1
@export_range(1, 100, 1) var minimum_attempt_level := 1


func is_valid() -> bool:
	return not tier_id.is_empty() and difficulty_level >= 1 and minimum_attempt_level >= 1
