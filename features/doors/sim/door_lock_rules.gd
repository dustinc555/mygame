extends RefCounted

class_name DoorLockRules

const LOCKPICKING_CHECK := preload("res://features/skills/resources/checks/lockpicking_check.tres")
const SKILL_CHECK_RULES := preload("res://features/skills/sim/skill_check_rules.gd")


static func can_attempt(lock_tier_id: String, lockpick_skill_level: float, has_required_lockpick: bool) -> bool:
	return has_required_lockpick and SKILL_CHECK_RULES.can_attempt(LOCKPICKING_CHECK, lock_tier_id, lockpick_skill_level)


static func get_success_chance(lock_tier_id: String, lockpick_skill_level: float, assisting_attribute_level: float) -> float:
	return SKILL_CHECK_RULES.get_success_chance(LOCKPICKING_CHECK, lock_tier_id, lockpick_skill_level, assisting_attribute_level)


static func get_attempt_duration_seconds() -> float:
	return float(LOCKPICKING_CHECK.get("attempt_duration_seconds"))


static func roll(command_id: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(command_id.hash())
	return rng.randf()


static func roll_tool_break(command_id: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = abs((command_id + ":break").hash())
	return rng.randf()
