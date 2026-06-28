extends "res://addons/gecs/ecs/system.gd"

class_name GameVitalsSystem

## Authoritative actor vitals simulation over GECS components. Runs the same per-tick sequence the
## node VitalsCapability ran (bleeding -> dying -> recovery) via the shared VitalsStateMachine, so the
## ownership flip (see architecture/combat/VITALS_GECS_MIGRATION.md, S4) is a move of ownership, not of
## meaning. After the flip the node VitalsCapability becomes a read-only observer of these components.
##
## Scope: REALIZED HUMANOIDS only (death_profile == HUMANOID). Derealized actors are gone (their
## entity is removed at LOD — population_controller queue_free + unregister_actor), so off-screen
## bleeding is a separate step (S4b) that lives on the surviving ledger record, NOT here. Robots/quadbots
## keep their node-side death model until S5 and are skipped via the death_profile gate.
## (CGameActorVitals.vitals_sim_remaining is now vestigial — reserved for the S4b ledger window.)
##
## Registration: AFTER GameCombatResolutionSystem (which mutates the wound fields and calls
## VitalsStateMachine.recalculate at apply-time), BEFORE GameAiJobSystem.

const C_VITALS = preload("res://features/actors/sim/c_game_actor_vitals.gd")
const C_VITALS_INPUTS = preload("res://features/actors/sim/c_game_actor_vitals_inputs.gd")


func query() -> QueryBuilder:
	return q.with_all([C_VITALS, C_VITALS_INPUTS]).iterate([C_VITALS, C_VITALS_INPUTS])


func process(_entities: Array, components: Array, delta: float) -> void:
	var vitals: Array = components[0]
	var inputs: Array = components[1]
	var count := vitals.size()
	for index in range(count):
		var v := vitals[index] as CGameActorVitals
		var inp := inputs[index] as CGameActorVitalsInputs
		if v == null or inp == null:
			continue
		# Realized humanoids only. Robots/quadbots carry a CGameActorVitals entity too but keep their
		# node-side death model (robot_actor / quadbot drive _process_recovery directly) until S5, so the
		# sync stamps them ROBOT and this system leaves them alone — no double-sim.
		if v.death_profile != CGameActorVitals.DeathProfile.HUMANOID:
			continue
		v.held_externally_hold = inp.held_externally
		VitalsStateMachine.tick(v, inp.toughness, inp.healing_rate, delta)
