extends GutTest
## Fast boundary protection for the rules used by VitalsStateMachine.

const VITALS = preload("res://features/actors/sim/vitals_math.gd")


func test_life_state_boundaries_prioritize_lethal_damage_and_keep_death_terminal() -> void:
	var cases := [
		[NpcRules.LifeState.ALIVE, 0.01, 100.0, NpcRules.LifeState.ALIVE],
		[NpcRules.LifeState.ALIVE, 0.0, 100.0, NpcRules.LifeState.UNCONSCIOUS],
		[NpcRules.LifeState.ALIVE, -17.49, 100.0, NpcRules.LifeState.UNCONSCIOUS],
		[NpcRules.LifeState.ALIVE, -17.5, 100.0, NpcRules.LifeState.RECOVERY_COMA],
		[NpcRules.LifeState.ALIVE, -99.99, 100.0, NpcRules.LifeState.RECOVERY_COMA],
		[NpcRules.LifeState.ALIVE, -100.0, 100.0, NpcRules.LifeState.DYING],
		[NpcRules.LifeState.ALIVE, 100.0, 0.0, NpcRules.LifeState.UNCONSCIOUS],
		[NpcRules.LifeState.ALIVE, -17.5, -100.0, NpcRules.LifeState.DYING],
		[NpcRules.LifeState.UNCONSCIOUS, 100.0, 100.0, NpcRules.LifeState.ALIVE],
		[NpcRules.LifeState.DEAD, 100.0, 100.0, NpcRules.LifeState.DEAD],
	]
	for row in cases:
		assert_eq(VITALS.resolve_life_state(row[0], row[1], row[2], 100.0, 100.0, 10.0), row[3],
			"current=%s hp=%s blood=%s" % [row[0], row[1], row[2]])


func test_recovery_stops_at_healthy_limits_and_zero_time_changes_nothing() -> void:
	var healed := VITALS.recovery_step(2.0, 3.0, 4.0, 0.5, 1.0, 99.9, 100.0, 100.0, 1.0, 10.0)
	assert_eq_deep(healed, {
		"blunt_damage": 0.0, "open_cut_damage": 0.0, "bandaged_cut_damage": 0.0,
		"bleed_rate": 0.0, "bleed_burst_rate": 0.0, "blood": 100.0,
	})
	var unchanged := VITALS.recovery_step(2.0, 3.0, 4.0, 0.5, 1.0, 99.9, 100.0, 100.0, 1.0, 0.0)
	assert_eq_deep(unchanged, {
		"blunt_damage": 2.0, "open_cut_damage": 3.0, "bandaged_cut_damage": 4.0,
		"bleed_rate": 0.5, "bleed_burst_rate": 1.0, "blood": 99.9,
	})
