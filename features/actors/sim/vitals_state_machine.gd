class_name VitalsStateMachine
extends RefCounted

const FIXED_TICK_SECONDS := 1.0 / 20.0
const MAX_CATCH_UP_FIXED_STEPS := 2400
const MAX_CATCH_UP_COARSE_STEPS := 120

## Shared, signal-free actor vitals state machine. Mutates a duck-typed vitals target (today the GECS
## CGameActorVitals component; the node VitalsCapability can be pointed here in cleanup) using
## VitalsMath for every formula. This is VitalsCapability.recalculate_vitals / process_bleeding /
## process_dying / process_recovery / _enter_* / _set_life_state ported MINUS the node-side signal
## emission, so BOTH the GECS GameVitalsSystem and the combat-resolution apply-path run the EXACT same
## transitions the node ran — orchestration parity is then by construction, not by test.
##
## The two entry points mirror the node's two paths:
##   * recalculate(v, toughness)  == the VitalsCapability setters (apply damage / blood / wounds, then
##     re-derive hp + life_state). The combat resolution system calls this right after it mutates the
##     wound fields, exactly as set_blunt_damage() used to call recalculate_vitals().
##   * tick(v, toughness, healing_rate, delta) == VitalsCapability.process() (bleeding -> dying ->
##     recovery). GameVitalsSystem calls this once per simulated tick.
##
## Death / life-state SIGNALS are intentionally NOT emitted here: recon found no consumer of
## WorldActor.died / life_state_changed, and death is detected by polling life_state == DEAD. After the
## ownership flip the node observer re-derives state_changed (the one real consumer: command-bar
## refresh) by diffing life_state. Keeping signals at the call site keeps this layer pure data.
##
## Faithful-port oracle: features/actors/bridge/capabilities/vitals_capability.gd.
## Parity gate: tools/validation/validate_vitals_system.gd.

# ---------------------------------------------------------------------------
# recalculate_vitals (the setter-equivalent: re-derive hp from wounds, then life_state)
# ---------------------------------------------------------------------------

static func recalculate(v, toughness: float) -> void:
	v.hp = VitalsMath.hp_from_wounds(v.max_hp, VitalsMath.total_wound_damage(v.blunt_damage, v.open_cut_damage, v.bandaged_cut_damage))
	if v.life_state == NpcRules.LifeState.DEAD:
		return
	var target := VitalsMath.resolve_life_state(v.life_state, v.hp, v.blood, v.max_hp, v.max_blood, toughness)
	if target == NpcRules.LifeState.DYING:
		enter_dying(v, toughness)
		return
	if target == NpcRules.LifeState.RECOVERY_COMA:
		v.life_state = NpcRules.LifeState.RECOVERY_COMA
		return
	if target == NpcRules.LifeState.UNCONSCIOUS:
		v.life_state = NpcRules.LifeState.UNCONSCIOUS
		return
	# Healthy branch: clear the dying timer, and only flip to ALIVE out of a recoverable downed state
	# (resolve_life_state returns the current state otherwise, so this is a no-op for the already-ALIVE).
	v.dying_timer_remaining = 0.0
	if target == NpcRules.LifeState.ALIVE:
		# Carried bodies stay down until put down or placed in a cell/bed —
		# main's recovery required _carried_by == null (see held_externally).
		if v.held_externally_hold and VitalsMath.is_recoverable_downed(v.life_state):
			return
		v.life_state = NpcRules.LifeState.ALIVE


static func enter_dying(v, toughness: float) -> void:
	# Arm the dying countdown ONLY on the edge into DYING (matches VitalsCapability._enter_dying_state),
	# so re-entering DYING on a later tick does not reset the clock.
	if v.life_state != NpcRules.LifeState.DYING:
		v.dying_timer_remaining = maxf(v.dying_timer_remaining, VitalsMath.dying_seconds(toughness))
	v.life_state = NpcRules.LifeState.DYING

# ---------------------------------------------------------------------------
# Per-tick simulation == VitalsCapability.process()  (bleeding -> dying -> recovery)
# ---------------------------------------------------------------------------

static func tick(v, toughness: float, healing_rate: float, delta: float) -> void:
	process_bleeding(v, toughness, delta)
	process_dying(v, delta)
	process_recovery(v, toughness, healing_rate, delta)


## Deterministic bounded fast-forward for explicit world-time jumps. Normal play remains exact 20 Hz.
## Typical wounds resolve during the exact window; pathological long spans use a fixed coarse budget.
static func catch_up(v, toughness: float, healing_rate: float, duration_seconds: float) -> void:
	var remaining := maxf(duration_seconds, 0.0)
	var exact_steps := mini(int(floor(remaining / FIXED_TICK_SECONDS)), MAX_CATCH_UP_FIXED_STEPS)
	for _step in range(exact_steps):
		tick(v, toughness, healing_rate, FIXED_TICK_SECONDS)
		remaining -= FIXED_TICK_SECONDS
		if not v.needs_active_simulation():
			return
	if remaining <= 0.000001:
		return
	var coarse_steps := mini(MAX_CATCH_UP_COARSE_STEPS, maxi(1, int(ceil(remaining / FIXED_TICK_SECONDS))))
	var coarse_delta := remaining / float(coarse_steps)
	for _step in range(coarse_steps):
		tick(v, toughness, healing_rate, coarse_delta)
		if not v.needs_active_simulation():
			return


static func process_bleeding(v, toughness: float, delta: float) -> void:
	if v.life_state == NpcRules.LifeState.DEAD:
		return
	if v.bleed_rate + v.bleed_burst_rate <= 0.0:
		return
	var amount := VitalsMath.bleed_blood_loss(v.bleed_rate, v.bleed_burst_rate, delta)
	if amount <= 0.0:
		return
	v.blood = VitalsMath.apply_blood_loss(v.blood, amount, v.max_blood)
	recalculate(v, toughness)


static func process_dying(v, delta: float) -> void:
	if v.life_state != NpcRules.LifeState.DYING:
		return
	if not VitalsMath.has_lethal_dying_vitals(v.hp, v.blood, v.max_hp, v.max_blood):
		# Pulled back from the brink (e.g. blood restored) -> stabilise into coma, not death.
		v.life_state = NpcRules.LifeState.RECOVERY_COMA
		return
	v.dying_timer_remaining = maxf(0.0, v.dying_timer_remaining - delta)
	if v.dying_timer_remaining <= 0.0:
		v.dying_timer_remaining = 0.0
		v.life_state = NpcRules.LifeState.DEAD


static func process_recovery(v, toughness: float, healing_rate: float, delta: float) -> void:
	if v.life_state == NpcRules.LifeState.DEAD:
		return
	# Nothing to recover and not downed -> skip (matches VitalsCapability.process_recovery guard).
	if v.blunt_damage <= 0.0 and v.bandaged_cut_damage <= 0.0 and v.open_cut_damage <= 0.0 \
			and v.bleed_burst_rate <= 0.0 and v.bleed_rate <= 0.0 and v.blood >= v.max_blood \
			and not VitalsMath.is_recoverable_downed(v.life_state):
		return
	# No healing this tick -> skip the wound update AND the recalculate, exactly as the node does
	# (recovery_step is pure; falling through to recalculate could otherwise transition a downed actor).
	if healing_rate * v.recovery_multiplier * delta <= 0.0:
		return
	var step := VitalsMath.recovery_step(v.blunt_damage, v.open_cut_damage, v.bandaged_cut_damage, v.bleed_rate, v.bleed_burst_rate, v.blood, v.max_blood, healing_rate, v.recovery_multiplier, delta)
	v.blunt_damage = step["blunt_damage"]
	v.open_cut_damage = step["open_cut_damage"]
	v.bandaged_cut_damage = step["bandaged_cut_damage"]
	v.bleed_rate = step["bleed_rate"]
	v.bleed_burst_rate = step["bleed_burst_rate"]
	v.blood = step["blood"]
	recalculate(v, toughness)
