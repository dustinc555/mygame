extends RefCounted

class_name AiUtilityContext

var entity_id := ""
var actor: Node
var profile_id := "default_humanoid"
var position := Vector3.ZERO
var lod_tier := 1
var sim_time := 0.0
var current_goal_id: StringName = &""
var current_goal_started_at := 0.0
var current_goal_lock_until := 0.0
var current_target_entity_id := ""
var goal_cooldowns: Dictionary = {}
var facts: Dictionary = {}
var targets: Dictionary = {}


func set_fact(key: StringName, value: float) -> void:
	facts[key] = clampf(value, 0.0, 1.0)


func get_fact(key: StringName, default_value := 0.0) -> float:
	if facts.has(key):
		return clampf(float(facts[key]), 0.0, 1.0)
	return clampf(default_value, 0.0, 1.0)


func has_fact(key: StringName) -> bool:
	return facts.has(key)


func set_targets(selector_id: StringName, candidates: Array) -> void:
	targets[selector_id] = candidates


func get_targets(selector_id: StringName) -> Array:
	return targets.get(selector_id, [])


func get_goal_cooldown_until(goal_id: StringName) -> float:
	return float(goal_cooldowns.get(goal_id, goal_cooldowns.get(str(goal_id), 0.0)))


func to_debug_dictionary() -> Dictionary:
	return {
		"entity_id": entity_id,
		"profile_id": profile_id,
		"position": position,
		"lod_tier": lod_tier,
		"sim_time": sim_time,
		"current_goal_id": str(current_goal_id),
		"current_goal_started_at": current_goal_started_at,
		"current_goal_lock_until": current_goal_lock_until,
		"current_target_entity_id": current_target_entity_id,
		"facts": facts.duplicate(true),
	}
