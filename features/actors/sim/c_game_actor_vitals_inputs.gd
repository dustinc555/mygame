extends "res://addons/gecs/ecs/component.gd"

class_name CGameActorVitalsInputs

# Per-actor vitals INPUTS authored by the node (from StatsCapability) on an event (skill change),
# read only by GameVitalsSystem. This is the one legitimate node->component direction (same pattern
# as CGameCombatLoadout): the node pushes these typed, the system never reflects into the node.
#
# Crucially these are cached IN the component so the vitals sim keeps running after derealization —
# a wounded actor that leaves LOD keeps bleeding/healing for a bounded window with no live node,
# because the system reads toughness/healing_rate from here, not from the (gone) StatsCapability.
#
# `dirty` is set true by the authoring side whenever an input changes; the node re-authors and clears
# it, so derivation that depends on these (e.g. toughness -> max_blood) stays off the hot path.

@export var dirty := true

# Drives coma/dying thresholds and the toughness->max_blood curve (SkillRules.get_max_blood_for_toughness).
@export var toughness := 0.0

# Drives recovery/healing speed (StatsCapability "healing_rate"; NpcRules.BASE_HEAL_RATE fallback).
# Default matches VitalsCapability._get_healing_rate()'s null-stats fallback so an entity that is
# simulated before its inputs are ever authored heals at the same rate the node would have used.
@export var healing_rate := NpcRules.BASE_HEAL_RATE

# True while another actor is physically holding this body (carry). Downed
# recovery must hold while carried — main's invariant (_carried_by == null):
# waking mid-haul deadlocks arrests and stomps the carry pose.
@export var held_externally := false
