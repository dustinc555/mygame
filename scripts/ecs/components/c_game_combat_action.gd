extends "res://addons/gecs/ecs/component.gd"

class_name CGameCombatAction

# System-owned combat action/cooldown state (S2.3). Actor ids are stable GECS ids.
@export var cooldown_remaining := 0.0
@export var action_active := false
@export var action_target_actor_id := ""
@export var action_remaining := 0.0
@export var action_impact_remaining := 0.0
@export var action_has_impacted := false
@export var action_names: PackedStringArray = PackedStringArray()
@export var action_index := 0
@export var action_clip_remaining := 0.0
@export var action_attack_id := ""
@export var action_hit_reaction_names: PackedStringArray = PackedStringArray()
@export var action_blunt_damage := 0.0
@export var action_cut_damage := 0.0
@export var action_is_critical := false
@export var reaction_remaining := 0.0
@export var reaction_source_actor_id := ""
