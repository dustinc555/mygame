extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_combat_math.gd
## Prior baseline: new file (pure math).

const CM = preload("res://features/combat/sim/combat_math.gd")


func _initialize() -> void:
	var failures: Array[String] = []

	var base := CM.base_damage(2.5, 0.0, 5.0, 10.0, 8.0)
	_expect(failures, "base blunt damage", is_equal_approx(base["blunt_damage"], 6.0))
	_expect(failures, "base cut damage", is_equal_approx(base["cut_damage"], 0.0))
	_expect(failures, "base blunt share", is_equal_approx(base["blunt_share"], 1.0))
	_expect(failures, "base cut share", is_equal_approx(base["cut_share"], 0.0))

	var zero_base := CM.base_damage(0.0, 0.0, 5.0, 10.0, 8.0)
	_expect(failures, "zero blunt damage", is_equal_approx(zero_base["blunt_damage"], 0.0))
	_expect(failures, "zero cut damage", is_equal_approx(zero_base["cut_damage"], 0.0))
	_expect(failures, "zero blunt share", is_equal_approx(zero_base["blunt_share"], 0.0))
	_expect(failures, "zero cut share", is_equal_approx(zero_base["cut_share"], 0.0))

	var grit := CM.apply_toughness_grit(6.0, 0.0, 10.0)
	_expect(failures, "grit blunt damage", is_equal_approx(grit["blunt_damage"], 5.73))
	_expect(failures, "grit cut damage", is_equal_approx(grit["cut_damage"], 0.0))

	_expect(failures, "crit chance", is_equal_approx(CM.crit_chance(5.0, 8.0), 0.07542))

	var crit := CM.apply_crit(2.0, 3.0, 2.5)
	_expect(failures, "crit blunt damage", is_equal_approx(crit["blunt_damage"], 5.0))
	_expect(failures, "crit cut damage", is_equal_approx(crit["cut_damage"], 7.5))

	_expect(failures, "hit score", is_equal_approx(CM.hit_score(5.0, 8.0), 7.0))
	_expect(failures, "hit chance", is_equal_approx(CM.hit_chance(7.0, 8.0), 0.4954545))
	_expect(failures, "dodge score", is_equal_approx(CM.dodge_score(8.0), 8.0))

	_expect(failures, "parry score", is_equal_approx(CM.parry_score(5.0, 8.0, 0.0), 7.0))
	_expect(failures, "defense chance", is_equal_approx(CM.defense_chance(7.0, 7.0), 0.15))
	_expect(failures, "shield block score", is_equal_approx(CM.shield_block_score(5.0, 8.0, 1.0), 8.0))

	var block := CM.apply_block_mitigation(10.0, 4.0, 0.5)
	_expect(failures, "block blunt damage", is_equal_approx(block["blunt_damage"], 5.0))
	_expect(failures, "block cut damage", is_equal_approx(block["cut_damage"], 2.0))

	var body_weapon := CM.condition_body_weapon(2.5, 0.0, 10.0)
	_expect(failures, "body weapon blunt base", is_equal_approx(body_weapon["blunt_base"], 3.125))
	_expect(failures, "body weapon cut base", is_equal_approx(body_weapon["cut_base"], 0.0))

	_expect(failures, "initiative with credit", is_equal_approx(CM.initiative_weight(8.0, 2.0), 10.0))
	_expect(failures, "initiative floor", is_equal_approx(CM.initiative_weight(0.0, 0.0), 1.0))

	_expect(failures, "hit chance high clamp", is_equal_approx(CM.hit_chance(999.0, 0.0), 0.95))
	_expect(failures, "hit chance low clamp", is_equal_approx(CM.hit_chance(0.0, 999.0), 0.05))
	_expect(failures, "defense chance high clamp", is_equal_approx(CM.defense_chance(999.0, 0.0), 0.75))
	_expect(failures, "defense chance low clamp", is_equal_approx(CM.defense_chance(0.0, 999.0), 0.02))

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 1
	var roll_a: float = CM.roll_crit_multiplier(rng_a)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 1
	var roll_b: float = CM.roll_crit_multiplier(rng_b)
	_expect(failures, "crit roll lower bound", roll_a >= 2.0)
	_expect(failures, "crit roll upper bound", roll_a <= 3.0)
	_expect(failures, "crit roll deterministic", is_equal_approx(roll_a, roll_b))

	if failures.is_empty():
		print("PASS validate_combat_math")
	else:
		for f in failures:
			push_error(f)
		print("FAIL validate_combat_math: %d failures" % failures.size())

	quit(failures.size())


func _expect(failures: Array[String], label: String, cond: bool) -> void:
	if not cond:
		failures.append(label)
