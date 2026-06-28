extends "res://addons/gecs/ecs/component.gd"

class_name CGameCombatLoadout

# Per-actor combat SOURCE stats, authored by the node on an event (equip / skill change) and read
# only by GameCombatScoreSystem, which derives the packed scores in CGameCombatConfig via CombatMath.
# This is the one legitimate node -> component direction (Thrive: nodes may author component data).
# Systems never reflect into the node for these; the node pushes them here, typed, when they change.
#
# `dirty` is set true by the authoring side whenever any field changes; GameCombatScoreSystem
# recomputes only dirty loadouts and clears the flag, so derivation stays off the hot path.

@export var dirty := true

# Attributes / skills (levels, not yet turned into scores).
@export var weapon_skill_level := 0.0
@export var shields_skill_level := 0.0
@export var strength := 0.0
@export var dexterity := 0.0
@export var toughness := 0.0

# Active weapon damage profile (body-weapon or equipped weapon; see body_weapons.md / damage.md).
@export var blunt_base := 0.0
@export var cut_base := 0.0
@export var weapon_skill_id := ""
@export var weapon_parry_bonus := 0.0

# Shield, if equipped (see block.md).
@export var has_shield := false
@export var shield_block_bonus := 0.0
@export var block_damage_multiplier := 1.0
