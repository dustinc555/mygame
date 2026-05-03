extends RefCounted

class_name NpcRules

enum LifeState {
	ALIVE,
	ASLEEP,
	UNCONSCIOUS,
	DEAD,
}

enum CombatStance {
	AGGRESSIVE,
	DEFENSIVE,
	PASSIVE,
}

enum HungerStage {
	WELL_NOURISHED,
	HUNGRY,
	STARVING,
}

enum FatigueStage {
	WELL_RESTED,
	WINDED,
	EXHAUSTED,
}

const STANCE_LABELS := {
	CombatStance.AGGRESSIVE: "Aggressive",
	CombatStance.DEFENSIVE: "Defensive",
	CombatStance.PASSIVE: "Passive",
}

const LIFE_LABELS := {
	LifeState.ALIVE: "Alive",
	LifeState.ASLEEP: "Asleep",
	LifeState.UNCONSCIOUS: "Unconscious",
	LifeState.DEAD: "Dead",
}

const HUNGER_LABELS := {
	HungerStage.WELL_NOURISHED: "Well Nourished",
	HungerStage.HUNGRY: "Hungry",
	HungerStage.STARVING: "Starving",
}

const FATIGUE_LABELS := {
	FatigueStage.WELL_RESTED: "Well Rested",
	FatigueStage.WINDED: "Winded",
	FatigueStage.EXHAUSTED: "Exhausted",
}

const FATIGUE_RUN_LOCKOUT_THRESHOLD := 16.5

const DEATH_HP_FACTOR := 0.2
const BLEED_TO_BLOOD_RATE := 0.45
const BASE_HEAL_RATE := 0.1
const UNCONSCIOUS_HEAL_MULTIPLIER := 1.5

const FATIGUE_RUN_DRAIN := 6.5
const FATIGUE_COMBAT_DRAIN := 3.2
const FATIGUE_WORK_DRAIN := 2.4
const FATIGUE_IDLE_RECOVERY := 1.4
const WORLD_HUNGER_DRAIN_MULTIPLIER := 1.0

const NOURISHMENT_APPLY_RATE := 0.35
const RUN_SPEED_MULTIPLIER := 1.7
const MIN_EXHAUSTED_MOVE_MULTIPLIER := 0.2

const ASSIST_RANGE := 8.5
const AGGRO_RANGE := 8.5


static func get_stance_label(stance: int) -> String:
	return STANCE_LABELS.get(stance, "Unknown")


static func get_life_state_label(life_state: int) -> String:
	return LIFE_LABELS.get(life_state, "Unknown")


static func get_hunger_stage_label(stage: int) -> String:
	return HUNGER_LABELS.get(stage, "Unknown")


static func get_fatigue_stage_label(stage: int) -> String:
	return FATIGUE_LABELS.get(stage, "Unknown")


static func append_stage_modifiers(modifiers: Array, hunger_stage: int, fatigue_stage: int, open_cut_damage: float, max_hp: float) -> void:
	match hunger_stage:
		HungerStage.WELL_NOURISHED:
			modifiers.append({"stat": "attack_damage", "mul": 1.05})
			modifiers.append({"stat": "dodge_chance", "mul": 1.05})
			modifiers.append({"stat": "block_chance", "mul": 1.05})
			modifiers.append({"stat": "healing_rate", "mul": 1.2})
		HungerStage.HUNGRY:
			modifiers.append({"stat": "move_speed_multiplier", "mul": 0.9})
			modifiers.append({"stat": "attack_damage", "mul": 0.9})
			modifiers.append({"stat": "dodge_chance", "mul": 0.9})
			modifiers.append({"stat": "block_chance", "mul": 0.9})
		HungerStage.STARVING:
			modifiers.append({"stat": "move_speed_multiplier", "mul": 0.7})
			modifiers.append({"stat": "attack_damage", "mul": 0.7})
			modifiers.append({"stat": "dodge_chance", "mul": 0.7})
			modifiers.append({"stat": "block_chance", "mul": 0.7})
			modifiers.append({"stat": "healing_rate", "mul": 0.65})
			modifiers.append({"stat": "fatigue_recovery_rate", "mul": 0.55})

	match fatigue_stage:
		FatigueStage.WELL_RESTED:
			modifiers.append({"stat": "attack_damage", "mul": 1.03})
			modifiers.append({"stat": "dodge_chance", "mul": 1.03})
			modifiers.append({"stat": "block_chance", "mul": 1.03})
		FatigueStage.WINDED:
			modifiers.append({"stat": "attack_damage", "mul": 0.9})
			modifiers.append({"stat": "dodge_chance", "mul": 0.9})
			modifiers.append({"stat": "block_chance", "mul": 0.9})
			modifiers.append({"stat": "hunger_drain_rate", "mul": 1.2})
		FatigueStage.EXHAUSTED:
			modifiers.append({"stat": "move_speed_multiplier", "mul": MIN_EXHAUSTED_MOVE_MULTIPLIER})
			modifiers.append({"stat": "attack_damage", "mul": 0.65})
			modifiers.append({"stat": "dodge_chance", "mul": 0.65})
			modifiers.append({"stat": "block_chance", "mul": 0.65})
			modifiers.append({"stat": "hunger_drain_rate", "mul": 1.35})

	if max_hp > 0.0 and open_cut_damage > 0.0:
		var wound_ratio := clampf(open_cut_damage / max_hp, 0.0, 0.9)
		modifiers.append({"stat": "dodge_chance", "mul": maxf(0.35, 1.0 - wound_ratio)})
		modifiers.append({"stat": "block_chance", "mul": maxf(0.35, 1.0 - wound_ratio * 0.8)})
