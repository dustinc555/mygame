extends "res://addons/gecs/ecs/component.gd"

class_name CGameActorVitals

# Durable actor vitals — the GECS truth target for the vitals ownership flip (see
# architecture/combat/VITALS_GECS_MIGRATION.md). Today (S2) this is still written as a one-way
# mirror of the node-side VitalsCapability; after the flip (S4) GameVitalsSystem owns these and the
# capability becomes a read-only observer. Field set + defaults mirror VitalsCapability exactly so
# the flip is a move of ownership, not of meaning.
#
# Death-rule profile selects which life-state model GameVitalsSystem applies (humanoid full model
# with dying/coma vs robot simple model). Populated per actor type; humanoids leave the default.

enum DeathProfile { HUMANOID = 0, ROBOT = 1 }

const DURABLE_FIELDS := [
	&"life_state",
	&"hp",
	&"max_hp",
	&"blood",
	&"max_blood",
	&"base_max_blood",
	&"blunt_damage",
	&"open_cut_damage",
	&"bandaged_cut_damage",
	&"bleed_rate",
	&"bleed_burst_rate",
	&"recovery_multiplier",
	&"dying_timer_remaining",
	&"death_profile",
]

# --- Life / health ----------------------------------------------------------
@export var life_state := 0
@export var hp := 100.0
@export var max_hp := 100.0

# --- Blood ------------------------------------------------------------------
@export var blood := 100.0
@export var max_blood := 100.0
@export var base_max_blood := 0.0

# --- Wounds (hp is derived: hp = max_hp - (blunt + open_cut + bandaged)) -----
@export var blunt_damage := 0.0
@export var open_cut_damage := 0.0
@export var bandaged_cut_damage := 0.0

# --- Bleeding ---------------------------------------------------------------
@export var bleed_rate := 0.0
@export var bleed_burst_rate := 0.0

# --- Recovery / dying -------------------------------------------------------
@export var recovery_multiplier := 1.0
@export var dying_timer_remaining := 0.0

# Runtime scratch (plain var — never serialized): mirrored from
# CGameActorVitalsInputs.held_externally by GameVitalsSystem each tick so the
# state machine can hold recovery while the body is being carried.
var held_externally_hold := false

# --- Which death model GameVitalsSystem runs for this actor ------------------
@export var death_profile := DeathProfile.HUMANOID

# --- Flip bookkeeping -------------------------------------------------------
# False until the sync has seeded this component from the live node once (post-realization the entity
# starts at C_VITALS.new() defaults). After seeding, the sync reverses: the component is the truth and
# flows component->node. Without this, a pre-wounded / non-default-max_hp / loaded actor would be
# clobbered to defaults on its first simulated tick.
@export var vitals_seeded := false


func copy_durable_state_to(target) -> void:
	if target == null:
		return
	for field in DURABLE_FIELDS:
		target.set(field, get(field))


func apply_durable_state(source: Dictionary) -> void:
	for field in DURABLE_FIELDS:
		if source.has(field):
			set(field, source[field])


func durable_state() -> Dictionary:
	var state := {}
	for field in DURABLE_FIELDS:
		state[field] = get(field)
	return state


func needs_active_simulation() -> bool:
	if life_state == NpcRules.LifeState.DEAD:
		return false
	if life_state == NpcRules.LifeState.UNCONSCIOUS or life_state == NpcRules.LifeState.RECOVERY_COMA or life_state == NpcRules.LifeState.DYING:
		return true
	return blunt_damage > 0.0 or open_cut_damage > 0.0 or bandaged_cut_damage > 0.0 \
		or bleed_rate > 0.0 or bleed_burst_rate > 0.0 or blood < max_blood
