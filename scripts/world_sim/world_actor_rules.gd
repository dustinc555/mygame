extends RefCounted

class_name WorldActorRules

const DEFAULT_MAX_HP := 100.0
const DEFAULT_MAX_BLOOD := 100.0
const DEFAULT_MOVE_SPEED := 3.2
const DEFAULT_BASE_ATTACK_DAMAGE := 18.0
const DEFAULT_ATTACK_RANGE := 1.15
const DEFAULT_ATTACK_COOLDOWN := 1.2
const DEFAULT_ATTACK_CUT_RATIO := 0.05
const DEFAULT_BLOCK_DAMAGE_MULTIPLIER := 0.4

const MOVEMENT_MODE_WALK := 0
const MOVEMENT_MODE_RUN := 1
const MOVEMENT_MODE_SNEAK := 2
const SNEAK_MOVE_SPEED_MIN_MULTIPLIER := 0.45
const SNEAK_MOVE_SPEED_MAX_MULTIPLIER := 1.45
const SNEAK_MOVE_SPEED_MASTER_LEVEL := 80.0
const SNEAK_MOVE_SPEED_CURVE := 0.75

const COMBAT_SCORE_CHANCE_DIVISOR := 220.0
const COMBAT_ATTRIBUTE_ASSIST_WEIGHT := 0.25
const COMBAT_DAMAGE_SKILL_WEIGHT := 0.20
const COMBAT_DAMAGE_ATTRIBUTE_WEIGHT := 0.25
const COMBAT_BODY_TOUGHNESS_BASE_WEIGHT := 0.025
const COMBAT_CRIT_SKILL_WEIGHT := 0.00303
const COMBAT_CRIT_DEXTERITY_WEIGHT := 0.00190
const TOUGHNESS_GRIT_RESISTANCE_WEIGHT := 0.0045
const TOUGHNESS_GRIT_RESISTANCE_CAP := 0.45
const TOUGHNESS_GRIT_SOAK_WEIGHT := 0.20
const COMA_BASE_FACTOR := 0.10
const COMA_TOUGHNESS_WEIGHT := 0.0075
const COMA_FACTOR_CAP := 0.85
const DYING_BASE_SECONDS := 20.0
const DYING_TOUGHNESS_SECONDS := 0.8

const COMBAT_ATTACK_SKILL_XP := 0.85
const TOUGHNESS_DAMAGE_XP_MULTIPLIER := 0.18

const VITAL_INPUT_FIELDS := {
	"life_state": true,
	"hp": true,
	"max_hp": true,
	"blood": true,
	"max_blood": true,
	"base_max_blood": true,
	"open_cut_damage": true,
	"bandaged_cut_damage": true,
	"blunt_damage": true,
	"bleed_rate": true,
	"base_attack_damage": true,
	"base_dodge_chance": true,
	"base_block_chance": true,
}


static func record_has_vital_inputs(record: Dictionary) -> bool:
	for key_value in record.keys():
		var key := str(key_value)
		if key == "skill_levels":
			var levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
			if levels.has(SkillRules.ATTRIBUTE_TOUGHNESS):
				return true
		elif VITAL_INPUT_FIELDS.has(key):
			return true
	return false


static func normalize_population_record(record: Dictionary, existing: Dictionary = {}) -> Dictionary:
	var result := existing.duplicate(true)
	for key_value in record.keys():
		result[key_value] = record[key_value]
	var raw_max_hp := float(result.get("max_hp", DEFAULT_MAX_HP))
	var max_hp_was_unset := raw_max_hp <= 0.0 and not record.has("max_hp")
	var max_hp := raw_max_hp
	if max_hp <= 0.0:
		max_hp = DEFAULT_MAX_HP
	result["max_hp"] = max_hp
	if not result.has("hp") or (max_hp_was_unset and not record.has("hp")):
		result["hp"] = max_hp
	var base_max_blood := get_base_max_blood(result)
	var raw_previous_max_blood := float(existing.get("max_blood", result.get("max_blood", base_max_blood)))
	var blood_was_unset := raw_previous_max_blood <= 0.0 and not record.has("blood")
	var previous_max_blood := raw_previous_max_blood if raw_previous_max_blood > 0.0 else base_max_blood
	var was_full := float(existing.get("blood", result.get("blood", previous_max_blood))) >= previous_max_blood - 0.05
	var max_blood := max_blood_for_skill_levels(base_max_blood, _skill_levels(result))
	result["base_max_blood"] = base_max_blood
	result["max_blood"] = max_blood
	if not result.has("blood") or blood_was_unset or (was_full and (existing.is_empty() or not record.has("blood"))):
		result["blood"] = max_blood
	else:
		result["blood"] = clampf(float(result.get("blood", max_blood)), -maxf(max_blood, 1.0) * NpcRules.BLOOD_LOSS_DEATH_FACTOR, max_blood)
	if _record_has_wounds(record) and not record.has("hp"):
		result["hp"] = max_hp - total_wound_damage(result)
	result["hp"] = clampf(float(result.get("hp", max_hp)), get_death_point(result), max_hp)
	_apply_life_state_from_vitals(result)
	return result


static func get_base_max_blood(record: Dictionary) -> float:
	var explicit_base := float(record.get("base_max_blood", 0.0))
	if explicit_base > 0.0:
		return explicit_base
	var max_blood := float(record.get("max_blood", DEFAULT_MAX_BLOOD))
	return max_blood if max_blood > 0.0 else DEFAULT_MAX_BLOOD


static func max_blood_for_skill_levels(base_max_blood: float, skill_levels: Dictionary) -> float:
	var toughness := float(skill_levels.get(SkillRules.ATTRIBUTE_TOUGHNESS, SkillRules.get_default_level(SkillRules.ATTRIBUTE_TOUGHNESS)))
	return SkillRules.get_max_blood_for_toughness(maxf(base_max_blood, 1.0), toughness)


static func total_wound_damage(record: Dictionary) -> float:
	return maxf(float(record.get("blunt_damage", 0.0)), 0.0) + maxf(float(record.get("open_cut_damage", 0.0)), 0.0) + maxf(float(record.get("bandaged_cut_damage", 0.0)), 0.0)


static func get_coma_point(record: Dictionary) -> float:
	var max_hp := maxf(float(record.get("max_hp", DEFAULT_MAX_HP)), 1.0)
	var coma_factor := clampf(COMA_BASE_FACTOR + get_stat_value(record, "toughness") * COMA_TOUGHNESS_WEIGHT, COMA_BASE_FACTOR, COMA_FACTOR_CAP)
	return -max_hp * coma_factor


static func get_death_point(record: Dictionary) -> float:
	return -maxf(float(record.get("max_hp", DEFAULT_MAX_HP)), 1.0)


static func get_blood_death_point(record: Dictionary) -> float:
	return -maxf(float(record.get("max_blood", DEFAULT_MAX_BLOOD)), 1.0)


static func get_dying_seconds(record: Dictionary) -> float:
	return DYING_BASE_SECONDS + get_stat_value(record, "toughness") * DYING_TOUGHNESS_SECONDS


static func is_life_state_downed(state: int) -> bool:
	return state == NpcRules.LifeState.UNCONSCIOUS or state == NpcRules.LifeState.RECOVERY_COMA or state == NpcRules.LifeState.DYING


static func can_participate(record: Dictionary) -> bool:
	if int(record.get("life_state", NpcRules.LifeState.ALIVE)) != NpcRules.LifeState.ALIVE:
		return false
	var max_hp := float(record.get("max_hp", 0.0))
	if max_hp > 0.0 and float(record.get("hp", max_hp)) <= 0.0:
		return false
	var max_blood := float(record.get("max_blood", 0.0))
	if max_blood > 0.0 and float(record.get("blood", max_blood)) <= 0.0:
		return false
	return true


static func condition_factor(record: Dictionary) -> float:
	var condition := 1.0
	var max_hp := float(record.get("max_hp", 0.0))
	if max_hp > 0.0:
		condition = minf(condition, clampf(float(record.get("hp", max_hp)) / max_hp, 0.0, 1.0))
	var max_blood := float(record.get("max_blood", 0.0))
	if max_blood > 0.0:
		condition = minf(condition, clampf(float(record.get("blood", max_blood)) / max_blood, 0.0, 1.0))
	return condition


static func get_stat_value(record: Dictionary, stat_name: String, include_secondary_modifiers := true) -> float:
	var value := _get_base_stat_value(record, stat_name)
	if include_secondary_modifiers:
		var additive := 0.0
		var multiplier := 1.0
		for modifier in _collect_stat_modifiers(record):
			if str(modifier.get("stat", "")) != stat_name:
				continue
			additive += float(modifier.get("add", 0.0))
			multiplier *= float(modifier.get("mul", 1.0))
		value = (value + additive) * multiplier
	match stat_name:
		"dodge_chance", "block_chance", "cut_ratio":
			return clampf(value, 0.0, 0.95)
		"block_damage_multiplier":
			return clampf(value, 0.0, 1.0)
		"attack_cooldown":
			return maxf(0.2, value)
		"move_speed", "move_speed_multiplier", "run_speed_multiplier", "attack_damage", "attack_range", "strength", "dexterity", "toughness", "perception", "stealth", "hunger_drain_rate", "fatigue_recovery_rate", "healing_rate", "blood_recovery_rate", "weapon_parry_bonus", "shield_block_bonus":
			return maxf(0.0, value)
	return value


static func move_speed_for_mode(record: Dictionary, movement_mode: int) -> float:
	return maxf(float(record.get("move_speed", DEFAULT_MOVE_SPEED)), 0.0) * move_speed_multiplier_for_mode(record, movement_mode)


static func move_speed_multiplier_for_mode(record: Dictionary, movement_mode: int) -> float:
	var base_multiplier := get_stat_value(record, "move_speed_multiplier")
	match movement_mode:
		MOVEMENT_MODE_RUN:
			return base_multiplier * get_stat_value(record, "run_speed_multiplier", false)
		MOVEMENT_MODE_SNEAK:
			return base_multiplier * _sneak_move_speed_multiplier(record)
	return base_multiplier


static func get_combat_weapon_skill_id(record: Dictionary) -> String:
	var weapon := _equipment_identifier(record, "weapon").to_lower()
	if weapon.is_empty():
		return SkillRules.COMBAT_UNARMED
	if weapon.contains("dagger"):
		return SkillRules.COMBAT_DAGGERS
	if weapon.contains("axe"):
		return SkillRules.COMBAT_AXES_ONE_HANDED
	if weapon.contains("sword"):
		return SkillRules.COMBAT_SWORDS_ONE_HANDED
	return SkillRules.COMBAT_SWORDS_ONE_HANDED


static func get_combat_weapon_skill_level(record: Dictionary) -> float:
	return float(skill_level(record, get_combat_weapon_skill_id(record)))


static func get_combat_hit_score(record: Dictionary) -> float:
	return get_combat_weapon_skill_level(record) + get_stat_value(record, "dexterity") * COMBAT_ATTRIBUTE_ASSIST_WEIGHT


static func get_combat_dodge_score(record: Dictionary) -> float:
	return get_stat_value(record, "dexterity")


static func get_combat_hit_chance(attacker: Dictionary, defender: Dictionary) -> float:
	return clampf(0.50 + (get_combat_hit_score(attacker) - get_combat_dodge_score(defender)) / COMBAT_SCORE_CHANCE_DIVISOR, 0.05, 0.95)


static func get_combat_crit_chance(record: Dictionary) -> float:
	var weapon_skill := get_combat_weapon_skill_level(record)
	var dexterity := get_stat_value(record, "dexterity")
	return clampf(0.05 + maxf(0.0, weapon_skill - 1.0) * COMBAT_CRIT_SKILL_WEIGHT + maxf(0.0, dexterity - 1.0) * COMBAT_CRIT_DEXTERITY_WEIGHT, 0.0, 1.0)


static func get_combat_block_score(record: Dictionary) -> float:
	var shield_score := float(skill_level(record, SkillRules.COMBAT_SHIELDS)) + get_stat_value(record, "strength") * COMBAT_ATTRIBUTE_ASSIST_WEIGHT
	var parry_score := get_combat_weapon_skill_level(record) + get_stat_value(record, "dexterity") * COMBAT_ATTRIBUTE_ASSIST_WEIGHT
	return maxf(shield_score if not _equipment_identifier(record, "offhand").is_empty() else 0.0, parry_score)


static func get_combat_block_chance(defender: Dictionary, incoming_hit_score: float) -> float:
	return clampf(0.15 + (get_combat_block_score(defender) - incoming_hit_score) / COMBAT_SCORE_CHANCE_DIVISOR, 0.02, 0.75)


static func calculate_combat_damage(blunt_base: float, cut_base: float, weapon_skill: float, strength: float, dexterity: float) -> Dictionary:
	var safe_blunt_base := maxf(0.0, blunt_base)
	var safe_cut_base := maxf(0.0, cut_base)
	var total_base := safe_blunt_base + safe_cut_base
	if total_base <= 0.0:
		return {"blunt_damage": 0.0, "cut_damage": 0.0}
	var blunt_share := safe_blunt_base / total_base
	var cut_share := safe_cut_base / total_base
	var skill_bonus := maxf(0.0, weapon_skill) * COMBAT_DAMAGE_SKILL_WEIGHT
	return {
		"blunt_damage": safe_blunt_base + blunt_share * skill_bonus + blunt_share * maxf(0.0, strength) * COMBAT_DAMAGE_ATTRIBUTE_WEIGHT,
		"cut_damage": safe_cut_base + cut_share * skill_bonus + cut_share * maxf(0.0, dexterity) * COMBAT_DAMAGE_ATTRIBUTE_WEIGHT,
	}


static func get_combat_damage(record: Dictionary) -> Dictionary:
	var total_base := maxf(get_stat_value(record, "attack_damage"), 0.0)
	if _equipment_identifier(record, "weapon").is_empty():
		var body_multiplier := 1.0 + get_stat_value(record, "toughness") * COMBAT_BODY_TOUGHNESS_BASE_WEIGHT
		total_base = maxf(2.5 * body_multiplier, total_base)
	var cut_ratio := clampf(get_stat_value(record, "cut_ratio"), 0.0, 1.0)
	return calculate_combat_damage(total_base * (1.0 - cut_ratio), total_base * cut_ratio, get_combat_weapon_skill_level(record), get_stat_value(record, "strength"), get_stat_value(record, "dexterity"))


static func roll_combat_attack_damage(record: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var damage := get_combat_damage(record)
	var blunt_damage := float(damage.get("blunt_damage", 0.0))
	var cut_damage := float(damage.get("cut_damage", 0.0))
	var critical := false
	var crit_multiplier := 1.0
	var roll := rng.randf() if rng != null else randf()
	if roll <= get_combat_crit_chance(record):
		critical = true
		crit_multiplier = rng.randf_range(2.0, 3.0) if rng != null else randf_range(2.0, 3.0)
		blunt_damage *= crit_multiplier
		cut_damage *= crit_multiplier
	return {
		"blunt_damage": blunt_damage,
		"cut_damage": cut_damage,
		"critical": critical,
		"crit_multiplier": crit_multiplier,
	}


static func apply_toughness_grit(record: Dictionary, blunt_damage: float, cut_damage: float) -> Dictionary:
	var safe_blunt := maxf(0.0, blunt_damage)
	var safe_cut := maxf(0.0, cut_damage)
	var post_armor_total := safe_blunt + safe_cut
	if post_armor_total <= 0.0:
		return {"blunt_damage": 0.0, "cut_damage": 0.0, "prevented_total": 0.0}
	var toughness := get_stat_value(record, "toughness")
	var damage_resistance := clampf(toughness * TOUGHNESS_GRIT_RESISTANCE_WEIGHT, 0.0, TOUGHNESS_GRIT_RESISTANCE_CAP)
	var grit_soak := toughness * TOUGHNESS_GRIT_SOAK_WEIGHT
	var prevented_total := minf(post_armor_total * damage_resistance, grit_soak)
	if prevented_total <= 0.0:
		return {"blunt_damage": safe_blunt, "cut_damage": safe_cut, "prevented_total": 0.0}
	var blunt_share := safe_blunt / post_armor_total
	var cut_share := safe_cut / post_armor_total
	return {
		"blunt_damage": maxf(0.0, safe_blunt - prevented_total * blunt_share),
		"cut_damage": maxf(0.0, safe_cut - prevented_total * cut_share),
		"prevented_total": prevented_total,
	}


static func apply_damage_to_record(target_record: Dictionary, blunt_damage: float, cut_damage: float, award_toughness_xp := true) -> Dictionary:
	var updated := normalize_population_record(target_record)
	var grit_damage := apply_toughness_grit(updated, blunt_damage, cut_damage)
	var final_blunt := float(grit_damage.get("blunt_damage", 0.0))
	var final_cut := float(grit_damage.get("cut_damage", 0.0))
	updated["blunt_damage"] = maxf(float(updated.get("blunt_damage", 0.0)), 0.0) + final_blunt
	updated["open_cut_damage"] = maxf(float(updated.get("open_cut_damage", 0.0)), 0.0) + final_cut
	_add_bleeding_from_cut(updated, final_blunt, final_cut)
	updated["hp"] = maxf(float(updated.get("max_hp", DEFAULT_MAX_HP)), 1.0) - total_wound_damage(updated)
	updated["hp"] = clampf(float(updated.get("hp", 0.0)), get_death_point(updated), float(updated.get("max_hp", DEFAULT_MAX_HP)))
	_apply_life_state_from_vitals(updated)
	var patch := _vitals_patch(updated)
	patch["damage_result"] = {
		"blunt_damage": final_blunt,
		"cut_damage": final_cut,
		"prevented_total": float(grit_damage.get("prevented_total", 0.0)),
		"life_state": int(updated.get("life_state", NpcRules.LifeState.ALIVE)),
	}
	if award_toughness_xp:
		add_skill_xp_to_patch(updated, patch, SkillRules.ATTRIBUTE_TOUGHNESS, (final_blunt + final_cut) * TOUGHNESS_DAMAGE_XP_MULTIPLIER)
	return patch


static func combat_attack_xp_patch(attacker_record: Dictionary) -> Dictionary:
	var patch := {"actor_id": str(attacker_record.get("actor_id", attacker_record.get("stable_id", ""))).strip_edges()}
	var skill_id := get_combat_weapon_skill_id(attacker_record)
	add_skill_xp_to_patch(attacker_record, patch, skill_id, COMBAT_ATTACK_SKILL_XP)
	add_skill_xp_to_patch(attacker_record, patch, SkillRules.ATTRIBUTE_DEXTERITY, COMBAT_ATTACK_SKILL_XP * 0.01)
	match skill_id:
		SkillRules.COMBAT_DAGGERS:
			add_skill_xp_to_patch(attacker_record, patch, SkillRules.ATTRIBUTE_DEXTERITY, COMBAT_ATTACK_SKILL_XP * 0.12)
		SkillRules.COMBAT_AXES_ONE_HANDED:
			add_skill_xp_to_patch(attacker_record, patch, SkillRules.ATTRIBUTE_STRENGTH, COMBAT_ATTACK_SKILL_XP * 0.08)
		SkillRules.COMBAT_UNARMED:
			add_skill_xp_to_patch(attacker_record, patch, SkillRules.ATTRIBUTE_STRENGTH, COMBAT_ATTACK_SKILL_XP * 0.04)
		_:
			add_skill_xp_to_patch(attacker_record, patch, SkillRules.ATTRIBUTE_DEXTERITY, COMBAT_ATTACK_SKILL_XP * 0.025)
	return patch


static func skill_level(record: Dictionary, skill_id: String) -> int:
	return int(_skill_levels(record).get(skill_id, SkillRules.get_default_level(skill_id)))


static func add_skill_xp_to_patch(record: Dictionary, patch: Dictionary, skill_id: String, amount: float) -> void:
	if skill_id.strip_edges().is_empty() or amount <= 0.0:
		return
	var skill_levels: Dictionary = (patch.get("skill_levels", record.get("skill_levels", {})) as Dictionary).duplicate(true)
	var skill_xp: Dictionary = (patch.get("skill_xp", record.get("skill_xp", {})) as Dictionary).duplicate(true)
	var level := int(skill_levels.get(skill_id, SkillRules.get_default_level(skill_id)))
	var xp := float(skill_xp.get(skill_id, 0.0)) + amount
	var xp_to_next := SkillRules.get_xp_to_next_level(level)
	while xp >= xp_to_next and xp_to_next > 0.0:
		xp -= xp_to_next
		level += 1
		xp_to_next = SkillRules.get_xp_to_next_level(level)
	skill_levels[skill_id] = level
	skill_xp[skill_id] = xp
	patch["skill_levels"] = skill_levels
	patch["skill_xp"] = skill_xp


static func _apply_life_state_from_vitals(record: Dictionary) -> void:
	if int(record.get("life_state", NpcRules.LifeState.ALIVE)) == NpcRules.LifeState.DEAD:
		return
	var hp := float(record.get("hp", record.get("max_hp", DEFAULT_MAX_HP)))
	var blood := float(record.get("blood", record.get("max_blood", DEFAULT_MAX_BLOOD)))
	if blood <= get_blood_death_point(record) or hp <= get_death_point(record):
		record["life_state"] = NpcRules.LifeState.DYING
		record["dying_timer_remaining"] = maxf(float(record.get("dying_timer_remaining", 0.0)), get_dying_seconds(record))
		return
	if hp <= get_coma_point(record):
		record["life_state"] = NpcRules.LifeState.RECOVERY_COMA
		return
	if blood <= 0.0 or hp <= 0.0:
		if int(record.get("life_state", NpcRules.LifeState.ALIVE)) != NpcRules.LifeState.RECOVERY_COMA:
			record["life_state"] = NpcRules.LifeState.UNCONSCIOUS
		return
	if not is_life_state_downed(int(record.get("life_state", NpcRules.LifeState.ALIVE))):
		record["life_state"] = NpcRules.LifeState.ALIVE


static func _vitals_patch(record: Dictionary) -> Dictionary:
	return {
		"life_state": int(record.get("life_state", NpcRules.LifeState.ALIVE)),
		"hp": float(record.get("hp", DEFAULT_MAX_HP)),
		"max_hp": float(record.get("max_hp", DEFAULT_MAX_HP)),
		"blood": float(record.get("blood", DEFAULT_MAX_BLOOD)),
		"max_blood": float(record.get("max_blood", DEFAULT_MAX_BLOOD)),
		"base_max_blood": float(record.get("base_max_blood", DEFAULT_MAX_BLOOD)),
		"open_cut_damage": float(record.get("open_cut_damage", 0.0)),
		"bandaged_cut_damage": float(record.get("bandaged_cut_damage", 0.0)),
		"blunt_damage": float(record.get("blunt_damage", 0.0)),
		"bleed_rate": float(record.get("bleed_rate", 0.0)),
	}


static func _add_bleeding_from_cut(record: Dictionary, final_blunt: float, final_cut: float) -> void:
	if final_cut <= 0.0:
		return
	var total_damage := maxf(final_blunt + final_cut, 0.001)
	var cut_ratio := clampf(final_cut / total_damage, 0.0, 1.0)
	var sharp_excess := maxf(0.0, cut_ratio - NpcRules.BLEED_SHARP_CUT_RATIO_THRESHOLD)
	var immediate_loss := final_cut * (NpcRules.BLEED_IMMEDIATE_BLOOD_LOSS_PER_CUT + sharp_excess * NpcRules.BLEED_IMMEDIATE_SHARPNESS_SCALE)
	var max_blood := maxf(float(record.get("max_blood", DEFAULT_MAX_BLOOD)), 1.0)
	record["blood"] = maxf(float(record.get("blood", max_blood)) - immediate_loss, -max_blood * NpcRules.BLOOD_LOSS_DEATH_FACTOR)
	record["bleed_rate"] = maxf(float(record.get("bleed_rate", 0.0)), 0.0) + final_cut * (NpcRules.BLEED_SUSTAINED_FROM_CUT_BASE + sharp_excess * NpcRules.BLEED_SUSTAINED_SHARPNESS_SCALE)


static func _get_base_stat_value(record: Dictionary, stat_name: String) -> float:
	match stat_name:
		"attack_damage":
			return float(record.get("base_attack_damage", DEFAULT_BASE_ATTACK_DAMAGE))
		"attack_range":
			return float(record.get("attack_range", DEFAULT_ATTACK_RANGE))
		"strength":
			return float(skill_level(record, SkillRules.ATTRIBUTE_STRENGTH))
		"dexterity":
			return float(skill_level(record, SkillRules.ATTRIBUTE_DEXTERITY))
		"toughness":
			return float(skill_level(record, SkillRules.ATTRIBUTE_TOUGHNESS))
		"perception":
			return float(skill_level(record, SkillRules.ATTRIBUTE_PERCEPTION))
		"stealth":
			return float(skill_level(record, SkillRules.SUBTERFUGE_SNEAKING))
		"attack_cooldown":
			return float(record.get("attack_cooldown_seconds", DEFAULT_ATTACK_COOLDOWN))
		"cut_ratio":
			return float(record.get("attack_cut_ratio", record.get("cut_ratio", DEFAULT_ATTACK_CUT_RATIO)))
		"dodge_chance":
			return float(record.get("base_dodge_chance", 0.08)) + SkillRules.get_diminishing_bonus(float(skill_level(record, SkillRules.ATTRIBUTE_DEXTERITY)), 0.18, 45.0)
		"block_chance":
			return float(record.get("base_block_chance", 0.06))
		"block_damage_multiplier":
			return float(record.get("block_damage_multiplier", DEFAULT_BLOCK_DAMAGE_MULTIPLIER))
		"move_speed":
			return float(record.get("move_speed", DEFAULT_MOVE_SPEED))
		"move_speed_multiplier":
			return 1.0
		"run_speed_multiplier":
			return NpcRules.RUN_SPEED_MULTIPLIER + SkillRules.get_diminishing_bonus(float(skill_level(record, SkillRules.MOVEMENT_RUNNING)), 0.42, 55.0)
		"hunger_drain_rate":
			var endurance_hunger_reduction := SkillRules.get_diminishing_bonus(float(skill_level(record, SkillRules.ATTRIBUTE_ENDURANCE)), 0.16, 65.0)
			return float(record.get("hunger_drain_rate", 0.08)) * (1.0 - endurance_hunger_reduction)
		"fatigue_recovery_rate":
			return NpcRules.FATIGUE_IDLE_RECOVERY + SkillRules.get_diminishing_bonus(float(skill_level(record, SkillRules.ATTRIBUTE_ENDURANCE)), 0.9, 60.0)
		"healing_rate":
			return NpcRules.BASE_HEAL_RATE
		"blood_recovery_rate":
			return NpcRules.BLOOD_RECOVERY_RATE
		"weapon_parry_bonus", "shield_block_bonus":
			return 0.0
	return 0.0


static func _collect_stat_modifiers(record: Dictionary) -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	NpcRules.append_stage_modifiers(modifiers, int(record.get("hunger_stage", NpcRules.HungerStage.WELL_NOURISHED)), int(record.get("fatigue_stage", NpcRules.FatigueStage.WELL_RESTED)), float(record.get("open_cut_damage", 0.0)), float(record.get("max_hp", DEFAULT_MAX_HP)))
	return modifiers


static func _sneak_move_speed_multiplier(record: Dictionary) -> float:
	var sneak_level := float(skill_level(record, SkillRules.SUBTERFUGE_SNEAKING))
	var ratio := clampf((sneak_level - float(SkillRules.DEFAULT_LEVEL)) / maxf(SNEAK_MOVE_SPEED_MASTER_LEVEL - float(SkillRules.DEFAULT_LEVEL), 0.001), 0.0, 1.0)
	var mastery := pow(ratio, SNEAK_MOVE_SPEED_CURVE)
	return lerpf(SNEAK_MOVE_SPEED_MIN_MULTIPLIER, SNEAK_MOVE_SPEED_MAX_MULTIPLIER, mastery)


static func _equipment_identifier(record: Dictionary, slot_name: String) -> String:
	var slot_paths: Dictionary = record.get("equipment_slot_paths", {}) if record.get("equipment_slot_paths", {}) is Dictionary else {}
	var from_paths := str(slot_paths.get(slot_name, "")).strip_edges()
	if not from_paths.is_empty():
		return from_paths
	var slots: Dictionary = record.get("equipment_slots", {}) if record.get("equipment_slots", {}) is Dictionary else {}
	return str(slots.get(slot_name, "")).strip_edges()


static func _skill_levels(record: Dictionary) -> Dictionary:
	return record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}


static func _record_has_wounds(record: Dictionary) -> bool:
	return record.has("blunt_damage") or record.has("open_cut_damage") or record.has("bandaged_cut_damage")
