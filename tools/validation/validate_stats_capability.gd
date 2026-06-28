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

	# XP raises level and emits.
	var emitted := {"hit": false}
	stats.skill_level_changed.connect(func(_id): emitted.hit = true)
	stats.add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, 100000.0)
	_expect(failures, "toughness leveled from xp", stats.get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS) > SkillRules.DEFAULT_LEVEL)
	_expect(failures, "skill_level_changed emitted", emitted.hit)

	# Unknown stat is safe.
	_expect(failures, "unknown stat returns 0", is_equal_approx(stats.get_stat_value("nonsense"), 0.0))

	if failures.is_empty():
		print("PASS: StatsCapability resolution sane (8 checks)")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)
