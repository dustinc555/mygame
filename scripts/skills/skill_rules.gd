extends RefCounted

class_name SkillRules

const SKILL_CATALOG: SkillCatalog = preload("res://resources/skills/phase_1_skill_catalog.tres")

const DEFAULT_LEVEL := 1
const BASE_XP_TO_NEXT := 50.0
const LEVEL_XP_DECAY_CAP := 101.0
const MIN_LEVEL_XP_MULTIPLIER := 0.002

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
	return ceil(BASE_XP_TO_NEXT / get_level_xp_multiplier(level))


static func get_level_xp_multiplier(level: int) -> float:
	var safe_level := maxf(0.0, float(level))
	var remaining_ratio := clampf(1.0 - safe_level / LEVEL_XP_DECAY_CAP, 0.0, 1.0)
	return maxf(MIN_LEVEL_XP_MULTIPLIER, remaining_ratio * remaining_ratio)


static func get_diminishing_bonus(level: float, cap: float, curve: float = 35.0) -> float:
	if cap <= 0.0:
		return 0.0
	return cap * (1.0 - exp(-maxf(level, 0.0) / maxf(curve, 0.001)))


static func get_assisted_skill_score(primary_level: float, attribute_level: float, attribute_cap: float = 18.0, attribute_curve: float = 35.0) -> float:
	return maxf(primary_level, 0.0) + get_diminishing_bonus(attribute_level, attribute_cap, attribute_curve)
