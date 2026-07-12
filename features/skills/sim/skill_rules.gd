@tool
extends RefCounted

class_name SkillRules

const SKILL_CATALOG: SkillCatalog = preload("res://features/skills/resources/phase_1_skill_catalog.tres")
const SKILL_PROGRESSION: Resource = preload("res://features/skills/resources/skill_progression.tres")

const DEFAULT_LEVEL := 1
const BASE_XP_TO_NEXT := 50.0
const LEVEL_XP_DECAY_CAP := 101.0
const MIN_LEVEL_XP_MULTIPLIER := 0.002
const CHECK_CHANCE_VERY_LOW_MAX := 0.2
const CHECK_CHANCE_LOW_MAX := 0.4
const CHECK_CHANCE_EVEN_MAX := 0.65
const CHECK_CHANCE_HIGH_MAX := 0.9
const TOUGHNESS_MAX_BLOOD_BONUS_CAP := 0.5
const TOUGHNESS_MAX_BLOOD_BONUS_CURVE := 45.0

const ATTRIBUTE_STRENGTH := "attribute.strength"
const ATTRIBUTE_PERCEPTION := "attribute.perception"
const ATTRIBUTE_DEXTERITY := "attribute.dexterity"
const ATTRIBUTE_TOUGHNESS := "attribute.toughness"
const ATTRIBUTE_ENDURANCE := "attribute.endurance"
const ATTRIBUTE_CHARISMA := "attribute.charisma"

const COMBAT_SWORDS_ONE_HANDED := "combat.swords_one_handed"
const COMBAT_AXES_ONE_HANDED := "combat.axes_one_handed"
const COMBAT_DAGGERS := "combat.daggers"
const COMBAT_UNARMED := "combat.unarmed"
const COMBAT_SHIELDS := "combat.shields"

const MOVEMENT_RUNNING := "movement.running"

const LABOR_MINING := "labor.mining"
const LABOR_SCAVENGING := "labor.scavenging"
const LABOR_FARMING := "labor.farming"
const LABOR_FISHING := "labor.fishing"
const LABOR_CONSTRUCTION := "labor.construction"

const CRAFT_BLACKSMITHING := "craft.blacksmithing"
const CRAFT_WEAVING := "craft.weaving"
const CRAFT_LEATHERWORKING := "craft.leatherworking"

const SUBTERFUGE_SNEAKING := "subterfuge.sneaking"
const SUBTERFUGE_SLEIGHT_OF_HAND := "subterfuge.sleight_of_hand"
const SUBTERFUGE_LOCKPICKING := "subterfuge.lockpicking"

const KNOWLEDGE_MEDICINE := "knowledge.medicine"
const TECH_ROBOTICS := "tech.robotics"
const KNOWLEDGE_ARCHEOLOGY := "knowledge.archeology"


static func get_all_definitions() -> Array[SkillDefinition]:
	return SKILL_CATALOG.get_definitions() if SKILL_CATALOG != null else []


static func get_definition(skill_id: String) -> SkillDefinition:
	return SKILL_CATALOG.get_definition(skill_id) if SKILL_CATALOG != null else null


static func get_default_level(skill_id: String) -> int:
	var definition := get_definition(skill_id)
	return maxi(0, definition.default_level) if definition != null else DEFAULT_LEVEL


static func get_xp_to_next_level(level: int) -> float:
	return ceil(SKILL_PROGRESSION.base_xp_to_next / get_level_xp_multiplier(level))


static func get_level_xp_multiplier(level: int) -> float:
	var safe_level := maxf(0.0, float(level))
	var remaining_ratio := clampf(1.0 - safe_level / SKILL_PROGRESSION.level_xp_decay_cap, 0.0, 1.0)
	return maxf(SKILL_PROGRESSION.minimum_level_xp_multiplier, remaining_ratio * remaining_ratio)


static func get_diminishing_bonus(level: float, cap: float, curve: float = 35.0) -> float:
	if cap <= 0.0:
		return 0.0
	return cap * (1.0 - exp(-maxf(level, 0.0) / maxf(curve, 0.001)))


static func get_toughness_max_blood_bonus(level: float) -> float:
	return get_diminishing_bonus(level, TOUGHNESS_MAX_BLOOD_BONUS_CAP, TOUGHNESS_MAX_BLOOD_BONUS_CURVE)


static func get_max_blood_for_toughness(base_max_blood: float, toughness_level: float) -> float:
	return maxf(base_max_blood, 1.0) * (1.0 + get_toughness_max_blood_bonus(toughness_level))


static func get_assisted_skill_score(primary_level: float, attribute_level: float, attribute_cap: float = 18.0, attribute_curve: float = 35.0) -> float:
	return maxf(primary_level, 0.0) + get_diminishing_bonus(attribute_level, attribute_cap, attribute_curve)


static func get_chance_check_xp(chance: float, passed: bool, scale := 1.0) -> float:
	var bounded_chance := clampf(chance, 0.0, 1.0)
	var base_xp := 0.0
	if bounded_chance < SKILL_PROGRESSION.chance_very_low_max:
		base_xp = SKILL_PROGRESSION.very_low_success_xp if passed else SKILL_PROGRESSION.very_low_failure_xp
	elif bounded_chance < SKILL_PROGRESSION.chance_low_max:
		base_xp = SKILL_PROGRESSION.low_success_xp if passed else SKILL_PROGRESSION.low_failure_xp
	elif bounded_chance < SKILL_PROGRESSION.chance_even_max:
		base_xp = SKILL_PROGRESSION.even_success_xp if passed else SKILL_PROGRESSION.even_failure_xp
	elif bounded_chance < SKILL_PROGRESSION.chance_high_max:
		base_xp = SKILL_PROGRESSION.high_success_xp if passed else SKILL_PROGRESSION.high_failure_xp
	else:
		base_xp = SKILL_PROGRESSION.trivial_success_xp if passed else SKILL_PROGRESSION.trivial_failure_xp
	return base_xp * maxf(scale, 0.0)
