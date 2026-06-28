extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_vitals_math.gd

const VM = preload("res://features/actors/sim/vitals_math.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	var checks := 0

	checks += _expect_float(failures, "total wound damage", VM.total_wound_damage(2.0, 3.0, 4.0), 9.0)
	checks += _expect_float(failures, "hp from wounds", VM.hp_from_wounds(100.0, 9.0), 91.0)
	checks += _expect_float(failures, "death point", VM.death_point(100.0), -100.0)
	checks += _expect_float(failures, "coma point", VM.coma_point(100.0, 10.0), -17.5)
	checks += _expect_float(failures, "blood death point", VM.blood_death_point(100.0), -100.0)
	checks += _expect_float(failures, "dying seconds", VM.dying_seconds(10.0), 28.0)

	checks += _expect(failures, "resolve healthy alive", VM.resolve_life_state(NpcRules.LifeState.ALIVE, 100.0, 100.0, 100.0, 100.0, 10.0) == NpcRules.LifeState.ALIVE)
	checks += _expect(failures, "resolve hp unconscious", VM.resolve_life_state(NpcRules.LifeState.ALIVE, 0.0, 100.0, 100.0, 100.0, 10.0) == NpcRules.LifeState.UNCONSCIOUS)
	checks += _expect(failures, "resolve hp coma", VM.resolve_life_state(NpcRules.LifeState.ALIVE, -17.5, 100.0, 100.0, 100.0, 10.0) == NpcRules.LifeState.RECOVERY_COMA)
	checks += _expect(failures, "resolve hp death dying", VM.resolve_life_state(NpcRules.LifeState.ALIVE, -100.0, 100.0, 100.0, 100.0, 10.0) == NpcRules.LifeState.DYING)
	checks += _expect(failures, "resolve blood death dying", VM.resolve_life_state(NpcRules.LifeState.ALIVE, 100.0, -100.0, 100.0, 100.0, 10.0) == NpcRules.LifeState.DYING)
	checks += _expect(failures, "resolve dead stays dead", VM.resolve_life_state(NpcRules.LifeState.DEAD, 100.0, 100.0, 100.0, 100.0, 10.0) == NpcRules.LifeState.DEAD)

	checks += _expect_float(failures, "bleed blood loss", VM.bleed_blood_loss(2.0, 3.0, 10.0), 9.0)
	checks += _expect_float(failures, "apply blood loss clamps", VM.apply_blood_loss(50.0, 200.0, 100.0), -100.0)

	var step := VM.recovery_step(10.0, 8.0, 6.0, 0.5, 2.0, 50.0, 100.0, 1.0, 2.0, 3.0)
	checks += _expect_float(failures, "recovery blunt damage", step["blunt_damage"], 4.0)
	checks += _expect_float(failures, "recovery open cut damage", step["open_cut_damage"], 5.9)
	checks += _expect_float(failures, "recovery bandaged cut damage", step["bandaged_cut_damage"], 1.2)
	checks += _expect_float(failures, "recovery bleed rate", step["bleed_rate"], 0.0)
	checks += _expect_float(failures, "recovery bleed burst rate", step["bleed_burst_rate"], 0.0)
	checks += _expect_float(failures, "recovery blood", step["blood"], 50.54)

	if failures.is_empty():
		print("PASS validate_vitals_math (%d checks)" % checks)
	else:
		for f in failures:
			push_error(f)
		print("FAIL validate_vitals_math: %d failures" % failures.size())

	quit(failures.size())


func _expect(failures: Array[String], label: String, cond: bool) -> int:
	if not cond:
		failures.append(label)
	return 1


func _expect_float(failures: Array[String], label: String, actual: float, expected: float) -> int:
	if not is_equal_approx(actual, expected):
		failures.append("%s expected %.6f got %.6f" % [label, expected, actual])
	return 1
