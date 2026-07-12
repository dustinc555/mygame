@tool
extends Resource

class_name DoorDefinition

@export_range(-180.0, 180.0, 1.0) var open_angle_degrees := -90.0
@export_range(0.0, 5.0, 0.05) var animation_duration_seconds := 0.35
@export_enum("stay_open", "auto_close") var close_behavior := "stay_open"
@export_range(0.0, 120.0, 0.5) var auto_close_delay_seconds := 8.0
@export var default_open := false
@export var default_locked := false
@export var lock_tier_id := "easy"
## free_exit: a lock binds from the outside only — anyone inside can always
## leave, and the door re-locks behind them. symmetric: the lock binds both
## directions (jail cells, vaults). authorized_exit: leaving requires door
## authorization even when unlocked (lockdown flow control, not imprisonment).
@export_enum("free_exit", "symmetric", "authorized_exit") var exit_policy := "free_exit"
@export_range(0.1, 5.0, 0.1) var interaction_radius := 1.5
