class_name VitalsMath
extends RefCounted

## Pure vitals arithmetic — the single owner of the actor vitals/wounds/death formulas, extracted
## from VitalsCapability so BOTH the node capability (today) and GameVitalsSystem (after the GECS
## ownership flip) call the exact same math. Parity between them is then exact by construction.
##
## Every function here is static and side-effect free: it takes scalars and returns scalars / a new
## Dictionary. It NEVER mutates a node, emits a signal, or arms a timer — those side effects stay at
## the call site (VitalsCapability._set_life_state / _enter_* keep owning signals + the dying timer).
##
## Faithful port of features/actors/bridge/capabilities/vitals_capability.gd. Oracle for the repoint:
## tools/validation/validate_vitals_capability.gd (must stay green) + tools/validation/validate_vitals_math.gd.

# Coma / dying tuning (was VitalsCapability.COMA_* / DYING_*). Rates that depend on world rules
# (bleed/clot/recovery/blood) are read from NpcRules so there is one source of truth.
const COMA_BASE_FACTOR := 0.10
const COMA_TOUGHNESS_WEIGHT := 0.0075
const COMA_FACTOR_CAP := 0.85
const DYING_BASE_SECONDS := 20.0
const DYING_TOUGHNESS_SECONDS := 0.8

# ---------------------------------------------------------------------------
# Wounds → hp
# ---------------------------------------------------------------------------

static func total_wound_damage(blunt_damage: float, open_cut_damage: float, bandaged_cut_damage: float) -> float:
	return blunt_damage + open_cut_damage + bandaged_cut_damage


static func hp_from_wounds(max_hp: float, total_wounds: float) -> float:
	return max_hp - total_wounds

# ---------------------------------------------------------------------------
# Thresholds (match VitalsCapability.get_coma_point/get_death_point/get_blood_death_point/get_dying_seconds)
# ---------------------------------------------------------------------------

static func coma_point(max_hp: float, toughness: float) -> float:
	var safe_max := maxf(max_hp, 1.0)
	var coma_factor := clampf(COMA_BASE_FACTOR + toughness * COMA_TOUGHNESS_WEIGHT, COMA_BASE_FACTOR, COMA_FACTOR_CAP)
	return -safe_max * coma_factor


static func death_point(max_hp: float) -> float:
	return -maxf(max_hp, 1.0)


static func blood_death_point(max_blood: float) -> float:
	return -maxf(max_blood, 1.0) * NpcRules.BLOOD_LOSS_DEATH_FACTOR


static func dying_seconds(toughness: float) -> float:
	return DYING_BASE_SECONDS + toughness * DYING_TOUGHNESS_SECONDS

# ---------------------------------------------------------------------------
# Life-state predicates (match VitalsCapability.is_life_state_*)
# ---------------------------------------------------------------------------

static func is_recoverable_downed(state: int) -> bool:
	return state == NpcRules.LifeState.UNCONSCIOUS \
		or state == NpcRules.LifeState.RECOVERY_COMA \
		or state == NpcRules.LifeState.DYING


static func has_lethal_dying_vitals(hp: float, blood: float, max_hp: float, max_blood: float) -> bool:
	return blood <= blood_death_point(max_blood) or hp <= death_point(max_hp)

# ---------------------------------------------------------------------------
# Life-state precedence (the recalculate_vitals decision, made pure)
# ---------------------------------------------------------------------------

## Returns the TARGET life_state given current vitals. Mirrors VitalsCapability.recalculate_vitals
## exactly: DEAD is terminal; then blood/hp death -> DYING; then coma; then unconscious; otherwise the
## healthy branch returns ALIVE only when currently in a recoverable downed state, else keeps current.
## The caller applies the result via its _enter_* / _set_life_state path (which own the dying timer +
## signal emission) and clears the dying timer in the healthy branch, just as the original did.
static func resolve_life_state(current_state: int, hp: float, blood: float, max_hp: float, max_blood: float, toughness: float) -> int:
	if current_state == NpcRules.LifeState.DEAD:
		return NpcRules.LifeState.DEAD
	if blood <= blood_death_point(max_blood) or hp <= death_point(max_hp):
		return NpcRules.LifeState.DYING
	if hp <= coma_point(max_hp, toughness):
		return NpcRules.LifeState.RECOVERY_COMA
	if blood <= 0.0 or hp <= 0.0:
		return NpcRules.LifeState.UNCONSCIOUS
	if is_recoverable_downed(current_state):
		return NpcRules.LifeState.ALIVE
	return current_state

# ---------------------------------------------------------------------------
# Per-tick steps (match process_bleeding / process_recovery / process_dying math)
# ---------------------------------------------------------------------------

## Blood lost this step from active bleeding (rate + burst), before clamping. Matches
## process_bleeding: total_bleed_rate * NpcRules.BLEED_TO_BLOOD_RATE * delta.
static func bleed_blood_loss(bleed_rate: float, bleed_burst_rate: float, delta: float) -> float:
	var total_bleed_rate := bleed_rate + bleed_burst_rate
	if total_bleed_rate <= 0.0:
		return 0.0
	return total_bleed_rate * NpcRules.BLEED_TO_BLOOD_RATE * delta


## Applies a blood loss amount with the same clamp as VitalsCapability.apply_blood_loss.
static func apply_blood_loss(blood: float, amount: float, max_blood: float) -> float:
	if amount <= 0.0:
		return blood
	return clampf(blood - amount, blood_death_point(max_blood), max_blood)


## One recovery tick. Returns the updated wound/bleed/blood values. Pure: the caller decides (from
## life_state) whether to run recovery at all and calls recalculate afterward, exactly as the original
## process_recovery does. Assumes healing_step has already been gated > 0 by the caller is NOT required
## — a healing_step <= 0 simply leaves wounds unchanged (still clots/recovers nothing), matching the
## original early-out.
static func recovery_step(blunt_damage: float, open_cut_damage: float, bandaged_cut_damage: float, bleed_rate: float, bleed_burst_rate: float, blood: float, max_blood: float, healing_rate: float, recovery_multiplier: float, delta: float) -> Dictionary:
	var result := {
		"blunt_damage": blunt_damage,
		"open_cut_damage": open_cut_damage,
		"bandaged_cut_damage": bandaged_cut_damage,
		"bleed_rate": bleed_rate,
		"bleed_burst_rate": bleed_burst_rate,
		"blood": blood,
	}
	var healing_step := healing_rate * recovery_multiplier * delta
	if healing_step <= 0.0:
		return result
	var new_blunt := maxf(0.0, blunt_damage - healing_step)
	var new_bandaged := maxf(0.0, bandaged_cut_damage - healing_step * 0.8)
	var new_open_cut := maxf(0.0, open_cut_damage - healing_step * 0.35)
	var new_burst := bleed_burst_rate
	if bleed_burst_rate > 0.0:
		var burst_clot_step := maxf(NpcRules.BLEED_BURST_MIN_CLOT_RATE, bleed_burst_rate * NpcRules.BLEED_BURST_CLOT_FRACTION_PER_SECOND) * delta + healing_step * NpcRules.BLEED_HEALING_BURST_CLOT_MULTIPLIER
		new_burst = maxf(0.0, bleed_burst_rate - burst_clot_step)
	var new_rate := bleed_rate
	if bleed_rate > 0.0:
		var clot_step := NpcRules.BLEED_CLOT_RATE * delta + healing_step * NpcRules.BLEED_HEALING_CLOT_MULTIPLIER
		new_rate = maxf(0.0, bleed_rate - clot_step)
	var new_blood := blood
	if new_rate + new_burst <= 0.0 and blood < max_blood:
		new_blood = minf(max_blood, blood + NpcRules.BLOOD_RECOVERY_RATE * recovery_multiplier * delta)
	result["blunt_damage"] = new_blunt
	result["open_cut_damage"] = new_open_cut
	result["bandaged_cut_damage"] = new_bandaged
	result["bleed_rate"] = new_rate
	result["bleed_burst_rate"] = new_burst
	result["blood"] = new_blood
	return result
