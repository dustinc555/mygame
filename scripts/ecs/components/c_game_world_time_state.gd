extends "res://addons/gecs/ecs/component.gd"

class_name CGameWorldTimeState

@export var state_id := "world_time"
@export var total_world_minutes := 0.0
@export var speed_index := 1
@export var real_seconds_per_game_minute := 1.0
@export var server_authoritative_mode := false
@export var manual_paused := false
@export var last_emitted_absolute_minute := -1
@export var last_boundary_absolute_minute := -1

var state: Dictionary = {}


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	total_world_minutes = float(source.get("total_world_minutes", total_world_minutes))
	speed_index = int(source.get("speed_index", speed_index))
	real_seconds_per_game_minute = float(source.get("real_seconds_per_game_minute", real_seconds_per_game_minute))
	server_authoritative_mode = bool(source.get("server_authoritative_mode", server_authoritative_mode))
	manual_paused = bool(source.get("manual_paused", manual_paused))
	last_emitted_absolute_minute = int(source.get("last_emitted_absolute_minute", last_emitted_absolute_minute))
	last_boundary_absolute_minute = int(source.get("last_boundary_absolute_minute", last_boundary_absolute_minute))
	state = to_state()


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"total_world_minutes": total_world_minutes,
		"speed_index": speed_index,
		"real_seconds_per_game_minute": real_seconds_per_game_minute,
		"server_authoritative_mode": server_authoritative_mode,
		"manual_paused": manual_paused,
		"last_emitted_absolute_minute": last_emitted_absolute_minute,
		"last_boundary_absolute_minute": last_boundary_absolute_minute,
	}
