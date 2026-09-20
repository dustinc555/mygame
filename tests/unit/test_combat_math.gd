extends GutTest
## Production rules used by the GECS score/resolution systems, not random attacks.

const COMBAT = preload("res://features/combat/sim/combat_math.gd")


func test_mixed_weapon_damage_uses_strength_for_blunt_and_dexterity_for_cut() -> void:
	var damage := COMBAT.base_damage(2.0, 6.0, 10.0, 8.0, 12.0)
	assert_almost_eq(damage.blunt_damage, 3.0, 0.000001)
	assert_almost_eq(damage.cut_damage, 9.75, 0.000001)
	assert_eq(damage.blunt_share, 0.25)
	assert_eq(damage.cut_share, 0.75)
	assert_eq_deep(COMBAT.base_damage(0.0, 0.0, 100.0, 100.0, 100.0), {
		"blunt_damage": 0.0, "cut_damage": 0.0, "blunt_share": 0.0, "cut_share": 0.0,
	})


func test_hit_chance_tracks_advantage_but_never_guarantees_hit_or_miss() -> void:
	assert_eq(COMBAT.hit_chance(50.0, 50.0), 0.5)
	assert_gt(COMBAT.hit_chance(60.0, 50.0), 0.5)
	assert_lt(COMBAT.hit_chance(50.0, 60.0), 0.5)
	assert_eq(COMBAT.hit_chance(999.0, 0.0), 0.95)
	assert_eq(COMBAT.hit_chance(0.0, 999.0), 0.05)
