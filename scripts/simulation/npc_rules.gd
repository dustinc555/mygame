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
const BLOOD_LOSS_DEATH_FACTOR := 1.0
const BLEED_TO_BLOOD_RATE := 0.18
const BLEED_IMMEDIATE_BLOOD_LOSS_PER_CUT := 0.18
const BLEED_IMMEDIATE_SHARPNESS_SCALE := 0.08
const BLEED_BURST_FROM_CUT_BASE := 1.5
const BLEED_BURST_SHARPNESS_SCALE := 0.8
const BLEED_SUSTAINED_FROM_CUT_BASE := 0.035
const BLEED_SUSTAINED_SHARPNESS_SCALE := 0.18
const BLEED_SHARP_CUT_RATIO_THRESHOLD := 0.6
const BLEED_BURST_CLOT_FRACTION_PER_SECOND := 0.26
const BLEED_BURST_MIN_CLOT_RATE := 0.75
const BLEED_CLOT_RATE := 0.035
const BLEED_HEALING_CLOT_MULTIPLIER := 0.1
const BLEED_HEALING_BURST_CLOT_MULTIPLIER := 0.4
const BLOOD_RECOVERY_RATE := 0.09
const BLOOD_RECOVERY_SLEEP_MULTIPLIER := 2.0
const BASE_HEAL_RATE := 0.1
const UNCONSCIOUS_HEAL_MULTIPLIER := 1.5

const FATIGUE_RUN_DRAIN := 6.5
const FATIGUE_WORK_DRAIN := 2.4
const FATIGUE_IDLE_RECOVERY := 1.4
const FATIGUE_WALK_RECOVERY_MULTIPLIER := 0.35
const FATIGUE_SIT_RECOVERY_MULTIPLIER := 2.0
const FATIGUE_SLEEP_RECOVERY_MULTIPLIER := 4.0
const FATIGUE_ATTACK_COST := 1.6
const FATIGUE_BLOCK_COST := 0.45
const FATIGUE_DODGE_COST := 0.55
const WORLD_HUNGER_DRAIN_MULTIPLIER := 1.0

const NOURISHMENT_APPLY_RATE := 0.35
const RUN_SPEED_MULTIPLIER := 1.7
const MIN_EXHAUSTED_MOVE_MULTIPLIER := 0.2

const ASSIST_RANGE := 8.5
const AGGRO_RANGE := 8.5
const COMBAT_WITNESS_RANGE := 16.0
const RAID_ALARM_APPROACH_RANGE := 8.0


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
