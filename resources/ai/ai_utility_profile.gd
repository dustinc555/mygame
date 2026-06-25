extends Resource

class_name AiUtilityProfile

@export var profile_id := "default_humanoid"
@export var display_name := "Default Humanoid"
@export var fallback_goal_id: StringName = &"wander"
@export var goals: Array[Resource] = []


func get_goal(goal_id: StringName) -> AiUtilityGoal:
	for goal_resource in goals:
		var goal := goal_resource as AiUtilityGoal
		if goal != null and goal.id == goal_id:
			return goal
	return null


func get_fallback_goal() -> AiUtilityGoal:
	return get_goal(fallback_goal_id)
