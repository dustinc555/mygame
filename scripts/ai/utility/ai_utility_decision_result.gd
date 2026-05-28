extends RefCounted

class_name AiUtilityDecisionResult

var selected_goal_id: StringName = &""
var selected_score := 0.0
var target_entity_id := ""
var target_position := Vector3.ZERO
var has_target_position := false
var target = null
var target_data: Dictionary = {}
var executor_key: StringName = &""
var all_goal_scores: Dictionary = {}
var consideration_breakdown: Dictionary = {}
var target_breakdown: Dictionary = {}
var reason_string := ""
var goal: AiUtilityGoal


func is_valid() -> bool:
	return selected_goal_id != &"" and selected_score > 0.0


func to_dictionary(include_breakdown := true) -> Dictionary:
	var output := {
		"selected_goal_id": str(selected_goal_id),
		"selected_score": selected_score,
		"target_entity_id": target_entity_id,
		"target_position": target_position,
		"has_target_position": has_target_position,
		"executor_key": str(executor_key),
		"reason": reason_string,
	}
	if include_breakdown:
		output["target_data"] = target_data.duplicate(true)
		output["all_goal_scores"] = all_goal_scores.duplicate(true)
		output["consideration_breakdown"] = consideration_breakdown.duplicate(true)
		output["target_breakdown"] = target_breakdown.duplicate(true)
	return output


func get_runtime_summary() -> Dictionary:
	return to_dictionary(false)
