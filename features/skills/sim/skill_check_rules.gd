@tool
extends RefCounted

class_name SkillCheckRules


static func can_attempt(check: Resource, tier_id: String, primary_skill_level: float) -> bool:
	var tier: Resource = check.get_tier(tier_id) if check != null else null
	return tier != null and primary_skill_level >= float(tier.get("minimum_attempt_level"))


static func get_assisted_score(check: Resource, primary_skill_level: float, attribute_level: float) -> float:
	if check == null:
		return 0.0
	return SkillRules.get_assisted_skill_score(
		primary_skill_level,
		attribute_level,
		float(check.get("assisting_attribute_cap")),
		float(check.get("assisting_attribute_curve")),
	)


static func get_success_chance(check: Resource, tier_id: String, primary_skill_level: float, attribute_level := 0.0) -> float:
	var tier: Resource = check.get_tier(tier_id) if check != null else null
	if tier == null or not can_attempt(check, tier_id, primary_skill_level):
		return 0.0
	var score := get_assisted_score(check, primary_skill_level, attribute_level)
	var chance := float(check.get("chance_at_equal_level")) + (score - float(tier.get("difficulty_level"))) * float(check.get("chance_per_level_delta"))
	return clampf(chance, float(check.get("minimum_success_chance")), float(check.get("maximum_success_chance")))
