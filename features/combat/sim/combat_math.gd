class_name CombatMath
extends RefCounted

## damage.md.
static func base_damage(blunt_base: float, cut_base: float, weapon_skill: float, strength: float, dexterity: float) -> Dictionary:
	var total_base := blunt_base + cut_base
	if is_equal_approx(total_base, 0.0):
		return {
			"blunt_damage": 0.0,
			"cut_damage": 0.0,
			"blunt_share": 0.0,
			"cut_share": 0.0,
		}

	var blunt_share := blunt_base / total_base
	var cut_share := cut_base / total_base
	var skill_bonus := weapon_skill * 0.20
	return {
		"blunt_damage": blunt_base + blunt_share * skill_bonus + blunt_share * strength * 0.25,
		"cut_damage": cut_base + cut_share * skill_bonus + cut_share * dexterity * 0.25,
		"blunt_share": blunt_share,
		"cut_share": cut_share,
	}


## damage.md grit.
static func apply_toughness_grit(blunt_damage: float, cut_damage: float, toughness: float) -> Dictionary:
	var post_armor_total := blunt_damage + cut_damage
	var blunt_share := 0.0
	var cut_share := 0.0
	if not is_equal_approx(post_armor_total, 0.0):
		blunt_share = blunt_damage / post_armor_total
		cut_share = cut_damage / post_armor_total

	var damage_resistance := clampf(toughness * 0.0045, 0.0, 0.45)
	var grit_soak := toughness * 0.20
	var prevented_total := minf(post_armor_total * damage_resistance, grit_soak)
	return {
		"blunt_damage": blunt_damage - prevented_total * blunt_share,
		"cut_damage": cut_damage - prevented_total * cut_share,
	}


## body_weapons.md.
static func condition_body_weapon(blunt_base: float, cut_base: float, toughness: float) -> Dictionary:
	var m := 1.0 + toughness * 0.025
	return {
		"blunt_base": blunt_base * m,
		"cut_base": cut_base * m,
	}


## crit.md.
static func crit_chance(weapon_skill: float, dexterity: float) -> float:
	return clampf(0.05 + maxf(0.0, weapon_skill - 1.0) * 0.00303 + maxf(0.0, dexterity - 1.0) * 0.00190, 0.0, 1.0)


## crit.md.
static func roll_crit_multiplier(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(2.0, 3.0)


## crit.md.
static func apply_crit(blunt_damage: float, cut_damage: float, crit_multiplier: float) -> Dictionary:
	return {
		"blunt_damage": blunt_damage * crit_multiplier,
		"cut_damage": cut_damage * crit_multiplier,
	}


## hit.md.
static func hit_score(weapon_skill: float, dexterity: float) -> float:
	return weapon_skill + dexterity * 0.25


## hit.md.
static func hit_chance(attacker_hit_score: float, defender_dodge_score: float) -> float:
	return clampf(0.50 + (attacker_hit_score - defender_dodge_score) / 220.0, 0.05, 0.95)


## dodge.md.
static func dodge_score(dexterity: float) -> float:
	return dexterity


## block.md.
static func parry_score(weapon_skill: float, dexterity: float, weapon_parry_bonus: float) -> float:
	return weapon_skill + dexterity * 0.25 + weapon_parry_bonus


## block.md.
static func shield_block_score(shields_skill: float, strength: float, shield_block_bonus: float) -> float:
	return shields_skill + strength * 0.25 + shield_block_bonus


## block.md.
static func defense_chance(defense_score: float, hit_score: float) -> float:
	return clampf(0.15 + (defense_score - hit_score) / 220.0, 0.02, 0.75)


## block.md.
static func apply_block_mitigation(blunt_damage: float, cut_damage: float, block_damage_multiplier: float) -> Dictionary:
	return {
		"blunt_damage": blunt_damage * block_damage_multiplier,
		"cut_damage": cut_damage * block_damage_multiplier,
	}


## initiative.md.
static func initiative_weight(dexterity: float, initiative_credit: float) -> float:
	return maxf(1.0, dexterity) + initiative_credit
