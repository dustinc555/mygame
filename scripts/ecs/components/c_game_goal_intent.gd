extends "res://addons/gecs/ecs/component.gd"

class_name CGameGoalIntent

@export var profile_id := "default_humanoid"
@export var goal_id := ""
@export var selected_score := 0.0
@export var selected_at := 0.0
@export var started_at := 0.0
@export var lock_until := 0.0
@export var current_goal_cooldown_seconds := 0.0
@export var target_entity_id := ""
@export var target_position := Vector3.ZERO
@export var has_target_position := false
@export var executor_key := ""
@export var source_id := "utility_ai"
@export var goal_cooldowns: Dictionary = {}
@export var last_runtime_summary: Dictionary = {}

var full_debug_breakdown: Dictionary = {}


func apply_decision(data: Dictionary) -> void:
	var next_goal_id := str(data.get("goal_id", data.get("selected_goal_id", "")))
	var now := float(data.get("selected_at", data.get("sim_time", selected_at)))
	var previous_goal_id := goal_id
	if not previous_goal_id.is_empty() and previous_goal_id != next_goal_id and current_goal_cooldown_seconds > 0.0:
		goal_cooldowns[previous_goal_id] = now + current_goal_cooldown_seconds
	profile_id = str(data.get("profile_id", profile_id))
	goal_id = next_goal_id
	selected_score = clampf(float(data.get("selected_score", data.get("score", selected_score))), 0.0, 1.0)
	selected_at = now
	if previous_goal_id != goal_id:
		started_at = now
		lock_until = now + maxf(float(data.get("lock_seconds", 0.0)), 0.0)
	current_goal_cooldown_seconds = maxf(float(data.get("cooldown_seconds", 0.0)), 0.0)
	target_entity_id = str(data.get("target_entity_id", target_entity_id))
	target_position = data.get("target_position", target_position)
	has_target_position = bool(data.get("has_target_position", has_target_position))
	executor_key = str(data.get("executor_key", executor_key))
	source_id = str(data.get("source_id", source_id))
	last_runtime_summary = (data.get("runtime_summary", {}) as Dictionary).duplicate(true)
	full_debug_breakdown = (data.get("debug_breakdown", {}) as Dictionary).duplicate(true)


func clear_intent() -> void:
	goal_id = ""
	selected_score = 0.0
	target_entity_id = ""
	target_position = Vector3.ZERO
	has_target_position = false
	executor_key = ""
	last_runtime_summary.clear()
	full_debug_breakdown.clear()


func to_dictionary(include_debug := false) -> Dictionary:
	var output := {
		"profile_id": profile_id,
		"goal_id": goal_id,
		"selected_score": selected_score,
		"selected_at": selected_at,
		"started_at": started_at,
		"lock_until": lock_until,
		"current_goal_cooldown_seconds": current_goal_cooldown_seconds,
		"target_entity_id": target_entity_id,
		"target_position": target_position,
		"has_target_position": has_target_position,
		"executor_key": executor_key,
		"source_id": source_id,
		"goal_cooldowns": goal_cooldowns.duplicate(true),
		"last_runtime_summary": last_runtime_summary.duplicate(true),
	}
	if include_debug:
		output["full_debug_breakdown"] = full_debug_breakdown.duplicate(true)
	return output
