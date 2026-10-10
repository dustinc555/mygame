extends Resource

## Shared lock-work tuning. Durations are seconds at normal game speed; pause
## stops work. Editing timing changes the remaining work, not the saved fraction.
@export_range(1, 20, 1) var successes_required := 3
@export_group("Attempt Timing")
@export_range(0.1, 120.0, 0.1) var novice_attempt_seconds := 20.0
@export_range(0.1, 120.0, 0.1) var expert_attempt_seconds := 2.0
@export_range(2.0, 100.0, 1.0) var expert_skill_level := 100.0
@export_range(0.1, 2.0, 0.05) var careful_speed := 1.0
@export_range(1.0, 3.0, 0.05) var rushed_speed := 1.5
@export_group("Failure and Wear")
@export_range(0.0, 100.0, 1.0) var setback_wear := 12.0
@export_range(0.0, 1.0, 0.05) var careful_risk := 0.55
@export_range(1.0, 3.0, 0.05) var rushed_risk := 1.4
@export_range(1.0, 3.0, 0.05) var rushed_wear := 1.5
@export_group("Interaction")
@export_range(0.05, 1.0, 0.01) var approach_tolerance := 0.12
@export_range(1.0, 120.0, 1.0) var approach_timeout_seconds := 35.0
## Sight is rechecked during work, independently of the pass/fail timer.
@export_range(0.05, 1.0, 0.05) var witness_check_interval_seconds := 0.25


func attempt_seconds(skill: float, rushed: bool) -> float:
	var mastery := clampf((skill - SkillRules.DEFAULT_LEVEL) / maxf(1.0, expert_skill_level - SkillRules.DEFAULT_LEVEL), 0.0, 1.0)
	var expert := maxf(0.1, expert_attempt_seconds)
	var novice := maxf(expert, novice_attempt_seconds)
	return lerpf(novice, expert, mastery) / maxf(0.1, rushed_speed if rushed else careful_speed)
