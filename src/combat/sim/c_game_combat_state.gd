extends "res://addons/gecs/ecs/component.gd"

class_name CGameCombatState

# Per-actor dynamic combat state, synced from the node (S2.0).
# Runtime ints are frame-local caches only. Exported *_actor_id strings are durable truth.
var current_target_id := 0
@export var current_target_actor_id := ""
var last_direct_attacker_id := 0
@export var last_direct_attacker_actor_id := ""
@export var sneaking := false
var personal_hostile_ids: PackedInt64Array = PackedInt64Array()
@export var personal_hostile_actor_ids: PackedStringArray = PackedStringArray()

# Written by the batched targeting system (S2.1). Runtime id is a bridge cache only.
var system_target_id := 0
@export var system_target_actor_id := ""
var system_target_retarget_remaining := 0.0
