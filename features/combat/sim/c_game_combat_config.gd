extends "res://addons/gecs/ecs/component.gd"

class_name CGameCombatConfig

# Per-actor combat decision config, synced from the node (S2.0). Read by the batched combat
# systems (S2.1 targeting, S2.3 resolution) so they never reflect into the node per candidate.
# These values rarely change at runtime.
@export var attack_range := 1.0
@export var aggro_scan_radius := 0.0
@export var assist_scan_radius := 0.0
@export var witness_radius := 0.0
@export var squad_assist_radius := 0.0
@export var move_target_vertical_tolerance := 0.75
@export var navigation_agent_radius := 0.4
@export var active_attack_slots := 3
@export var combat_stance := 0
@export var protected_from_combat := false
# Mirrored from the loadout by GameCombatScoreSystem; initiative rolls read it.
@export var dexterity := 0.0
# True while the player has an active order on this actor: targeting stops acquiring
# for them (they disengage) but they remain a valid target for enemies.
@export var player_order_active := false
@export var retarget_interval_seconds := 0.5
@export var retarget_jitter_seconds := 0.25
@export var attack_cooldown_seconds := 1.2
@export var blunt_damage := 0.0
@export var cut_damage := 0.0
@export var hit_score := 0.0
@export var dodge_score := 0.0
@export var block_score := 0.0
@export var block_damage_multiplier := 1.0
@export var crit_chance := 0.0
@export var toughness := 0.0
@export var has_shield := false
@export var weapon_skill_id := ""
@export var move_speed := 3.2
@export var movement_acceleration := 10.0
