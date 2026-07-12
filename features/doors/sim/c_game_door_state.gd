extends "res://addons/gecs/ecs/component.gd"

class_name CGameDoorState

@export var door_id := ""
@export var building_id := ""
@export var is_open := false
@export var is_locked := false
@export var lock_tier_id := "easy"
@export var exit_policy := "free_exit"
@export var relock_on_close := false
@export var authorized_actor_ids := PackedStringArray()
@export var authorized_faction_ids := PackedStringArray()
@export var authorized_key_ids := PackedStringArray()
@export var close_behavior := "stay_open"
@export var auto_close_delay_seconds := 0.0
@export var scheduled_actor_id := ""
@export var scheduled_open_hour := -1
@export var scheduled_close_hour := -1
## During business hours this door is supposed to stand open (bar/shop front
## doors); the keeper is sent to fix drift.
@export var kept_open := false
# Runtime scratch: a keeper-reconcile timer is already armed for this door.
var keeper_reconcile_armed := false
@export var interaction_side_a := Vector3.ZERO
@export var interaction_side_b := Vector3.ZERO
@export var interaction_radius := 1.5
@export var is_realized := false
@export var active_command_id := ""
@export var next_command_sequence := 1
@export var state_revision := 0
