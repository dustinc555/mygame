extends "res://addons/gecs/ecs/system.gd"

class_name GameVitalsSystem

## Authoritative actor vitals simulation over GECS components. Runs the same per-tick sequence the
## node VitalsCapability ran (bleeding -> dying -> recovery) via the shared VitalsStateMachine, so the
## ownership flip (see architecture/combat/VITALS_GECS_MIGRATION.md, S4) is a move of ownership, not of
## meaning. After the flip the node VitalsCapability becomes a read-only observer of these components.
##
## Scope: REALIZED HUMANOIDS only. Sparse ledger vitals use GamePopulationVitalsSystem.
##
## Registration: AFTER GameCombatResolutionSystem (which mutates the wound fields and calls
## VitalsStateMachine.recalculate at apply-time), BEFORE GameAiJobSystem.

const C_VITALS = preload("res://features/actors/sim/c_game_actor_vitals.gd")
const C_VITALS_INPUTS = preload("res://features/actors/sim/c_game_actor_vitals_inputs.gd")
const C_NODE = preload("res://features/actors/bridge/c_game_actor_node.gd")
const FIXED_VITALS_TICK_SECONDS := 1.0 / 20.0
const MAX_FIXED_STEPS_PER_FRAME := 8

var _fixed_accumulator := 0.0


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_VITALS, C_VITALS_INPUTS]).iterate([C_VITALS, C_VITALS_INPUTS])


func process(_entities: Array, components: Array, delta: float) -> void:
	var vitals: Array = components[0]
	var inputs: Array = components[1]
	var count := vitals.size()
	_fixed_accumulator = minf(_fixed_accumulator + maxf(delta, 0.0), FIXED_VITALS_TICK_SECONDS * float(MAX_FIXED_STEPS_PER_FRAME))
	while _fixed_accumulator >= FIXED_VITALS_TICK_SECONDS:
		_fixed_accumulator -= FIXED_VITALS_TICK_SECONDS
		for index in range(count):
			var v := vitals[index] as CGameActorVitals
			var inp := inputs[index] as CGameActorVitalsInputs
			if v == null or inp == null:
				continue
			# Robots and quadbots keep their separate death model until S5.
			if v.death_profile != CGameActorVitals.DeathProfile.HUMANOID:
				continue
			_apply_rest_request(v, inp)
			v.held_externally_hold = inp.held_externally
			VitalsStateMachine.tick(v, inp.toughness, inp.healing_rate, FIXED_VITALS_TICK_SECONDS)


func _apply_rest_request(v: CGameActorVitals, inp: CGameActorVitalsInputs) -> void:
	var requested_state := inp.pending_rest_state
	if requested_state < 0:
		return
	inp.pending_rest_state = -1
	if requested_state == NpcRules.LifeState.ASLEEP and v.life_state == NpcRules.LifeState.ALIVE:
		v.life_state = NpcRules.LifeState.ASLEEP
	elif requested_state == NpcRules.LifeState.ALIVE and v.life_state == NpcRules.LifeState.ASLEEP:
		v.life_state = NpcRules.LifeState.ALIVE


func catch_up_seconds(duration_seconds: float) -> void:
	if duration_seconds <= 0.0:
		return
	for entity in query().execute():
		var v := entity.get_component(C_VITALS) as CGameActorVitals
		var inp := entity.get_component(C_VITALS_INPUTS) as CGameActorVitalsInputs
		if v == null or inp == null or v.death_profile != CGameActorVitals.DeathProfile.HUMANOID or not v.needs_active_simulation():
			continue
		v.held_externally_hold = inp.held_externally
		VitalsStateMachine.catch_up(v, inp.toughness, inp.healing_rate, duration_seconds)
