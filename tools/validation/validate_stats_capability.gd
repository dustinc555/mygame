extends SceneTree

## Focused sanity check for StatsCapability resolution.
## Run: godot --headless --path . --script res://tools/validation/validate_stats_capability.gd
##
## Verifies: skill set wiring, base stat resolution, attribute-derived stats,
## per-stat clamps, and that the equipment layer degrades safely when absent.

const STATS = preload("res://features/actors/bridge/capabilities/stats_capability.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var stats: StatsCapability = STATS.new()
	# No actor/equipment wired — equipment layer must degrade to empty.
	stats.set_skill_set(null)

	# Default attribute level resolves through the skill set.
	var str_default := stats.get_stat_value("strength")
	_expect(failures, "strength default >= 0", str_default >= 0.0)

	# Setting an attribute level flows into the derived stat.
	stats.set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, 10)
	_expect(failures, "strength reflects level 10", is_equal_approx(stats.get_stat_value("strength"), 10.0))

	# Derived stat reads a different attribute (dexterity -> dodge_chance bonus).
	stats.set_skill_level(SkillRules.ATTRIBUTE_DEXTERITY, 20)
	var dodge := stats.get_stat_value("dodge_chance")
	_expect(failures, "dodge_chance above base after dexterity", dodge > stats.base_dodge_chance)
	_expect(failures, "dodge_chance clamped <= 0.95", dodge <= 0.95)

	# attack_cooldown floor clamp.
	stats.configure_base_stats({"attack_cooldown_seconds": 0.05})
	_expect(failures, "attack_cooldown floored at 0.2", is_equal_approx(stats.get_stat_value("attack_cooldown"), 0.2))

	# base attack damage passes through.
	stats.configure_base_stats({"base_attack_damage": 25.0})
	_expect(failures, "attack_damage passes base through", is_equal_approx(stats.get_stat_value("attack_damage"), 25.0))

	# XP mutates immediately but batches signal fanout once per skill.
	var emitted := {"level": 0, "progress": 0}
	stats.skill_level_changed.connect(func(_id): emitted.level += 1)
	stats.skill_progress_changed.connect(func(_id): emitted.progress += 1)
	var running_xp_before := stats.get_skill_xp(SkillRules.MOVEMENT_RUNNING)
	stats.add_skill_xp(SkillRules.MOVEMENT_RUNNING, 0.25)
	stats.add_skill_xp(SkillRules.MOVEMENT_RUNNING, 0.75)
	_expect(failures, "xp enables only its bounded flush tick", stats.physics_process_enabled)
	_expect(failures, "xp mutates authoritative progress immediately", is_equal_approx(stats.get_skill_xp(SkillRules.MOVEMENT_RUNNING) - running_xp_before, 1.0))
	_expect(failures, "xp signal waits for batch flush", emitted.progress == 0)
	stats.flush_pending_xp()
	_expect(failures, "idle stats stop physics processing", not stats.physics_process_enabled)
	_expect(failures, "non-level xp emits one progress signal on flush", emitted.progress == 1 and emitted.level == 0)
	emitted.level = 0
	emitted.progress = 0
	stats.add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, 100000.0)
	stats.add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, 1.0)
	_expect(failures, "level mutation is immediate", stats.get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS) > SkillRules.DEFAULT_LEVEL)
	_expect(failures, "level signal waits for batch flush", emitted.progress == 0)
	stats.flush_pending_xp()
	_expect(failures, "toughness remains leveled after signal flush", stats.get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS) > SkillRules.DEFAULT_LEVEL)
	_expect(failures, "skill_level_changed emitted once", emitted.level == 1)
	_expect(failures, "skill_progress_changed emitted once", emitted.progress == 1)

	# Unknown stat is safe.
	_expect(failures, "unknown stat returns 0", is_equal_approx(stats.get_stat_value("nonsense"), 0.0))

	if failures.is_empty():
		print("PASS: StatsCapability resolution and XP batching sane")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)
