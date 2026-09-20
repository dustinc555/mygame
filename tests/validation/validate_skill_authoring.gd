extends SceneTree

var _failures: Array[String] = []

const LOCKPICKING_CHECK := preload("res://features/skills/resources/checks/lockpicking_check.tres")
const SKILL_CHECK_RULES := preload("res://features/skills/sim/skill_check_rules.gd")
const SKILL_PROGRESSION := preload("res://features/skills/resources/skill_progression.tres")


func _init() -> void:
	_validate_progression()
	_validate_lockpicking_curve()
	for failure in _failures:
		push_error(failure)
	print("SKILL_AUTHORING_OK" if _failures.is_empty() else "SKILL_AUTHORING_FAILED")
	quit(0 if _failures.is_empty() else 1)


func _validate_progression() -> void:
	_expect(int(SKILL_PROGRESSION.get("maximum_level")) == 100, "Skill progression must use the authored 1-100 scale.")


func _validate_lockpicking_curve() -> void:
	_expect(SKILL_CHECK_RULES.can_attempt(LOCKPICKING_CHECK, "medium", 1.0), "Level 1 must be allowed to attempt a medium lock.")
	_expect(not SKILL_CHECK_RULES.can_attempt(LOCKPICKING_CHECK, "very_hard", 49.0), "Very Hard must be unavailable below Lockpicking 50.")
	_expect(SKILL_CHECK_RULES.can_attempt(LOCKPICKING_CHECK, "very_hard", 50.0), "Very Hard must be available at Lockpicking 50.")
	_expect(is_equal_approx(SKILL_CHECK_RULES.get_success_chance(LOCKPICKING_CHECK, "medium", 1.0), 0.02), "Level 1 medium locks must have a 2% success chance.")
	_expect(is_equal_approx(SKILL_CHECK_RULES.get_success_chance(LOCKPICKING_CHECK, "very_hard", 50.0), 0.01), "Lockpicking 50 Very Hard locks must have a 1% success chance.")
	_expect(is_equal_approx(SKILL_CHECK_RULES.get_success_chance(LOCKPICKING_CHECK, "very_hard", 75.0), 0.5), "Equal Very Hard skill must have a 50% success chance.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
