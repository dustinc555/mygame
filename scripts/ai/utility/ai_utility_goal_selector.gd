extends RefCounted

class_name AiUtilityGoalSelector

const SAFE_SCORE_FLOOR := 0.001


func decide(context: AiUtilityContext, profile: AiUtilityProfile, target_selector: AiUtilityTargetSelector = null) -> AiUtilityDecisionResult:
	var result := AiUtilityDecisionResult.new()
	if context == null or profile == null:
		result.reason_string = "Missing context or profile"
		return result
	var selector := target_selector if target_selector != null else AiUtilityTargetSelector.new()
	var scored: Array[Dictionary] = []
	var current_entry: Dictionary = {}
	for goal_resource in profile.goals:
		var goal := goal_resource as AiUtilityGoal
		if goal == null or goal.id == &"":
			continue
		if _is_goal_on_cooldown(goal, context) and goal.id != context.current_goal_id:
			result.all_goal_scores[str(goal.id)] = 0.0
			result.consideration_breakdown[str(goal.id)] = [{"cooldown_until": context.get_goal_cooldown_until(goal.id)}]
			continue
		var score_data := score_goal(goal, context)
		var score := float(score_data.get("score", 0.0))
		var target_data := {"found": false, "score": 1.0, "reason": "No target required"}
		if goal.requires_target:
			target_data = selector.select_target(goal, context.entity_id, context)
			if not bool(target_data.get("found", false)):
				score = 0.0
			else:
				score *= clampf(float(target_data.get("score", 1.0)), 0.0, 1.0)
		score = clampf(score, 0.0, 1.0)
		var entry := {
			"goal": goal,
			"score": score,
			"target": target_data,
		}
		scored.append(entry)
		result.all_goal_scores[str(goal.id)] = score
		result.consideration_breakdown[str(goal.id)] = score_data.get("breakdown", [])
		result.target_breakdown[str(goal.id)] = target_data
		if goal.id == context.current_goal_id:
			current_entry = entry
	var selected_entry := _choose_goal(context, profile, scored, current_entry)
	_apply_entry_to_result(result, selected_entry)
	return result


func score_goal(goal: AiUtilityGoal, context: AiUtilityContext) -> Dictionary:
	if goal == null or context == null:
		return {"score": 0.0, "breakdown": []}
	var product := 1.0
	var total_weight := 0.0
	var breakdown: Array = []
	for consideration_resource in goal.considerations:
		var consideration := consideration_resource as AiUtilityConsideration
		if consideration == null:
			continue
		var data := consideration.score(context)
		breakdown.append(data)
		if bool(data.get("required_failed", false)):
			return {"score": 0.0, "breakdown": breakdown}
		var weight := maxf(float(data.get("weight", 0.0)), 0.0)
		if weight <= 0.0:
			continue
		var safe_score := maxf(float(data.get("score", 0.0)), SAFE_SCORE_FLOOR)
		product *= pow(safe_score, weight)
		total_weight += weight
	if total_weight <= 0.0:
		return {"score": 0.0, "breakdown": breakdown}
	var score := pow(product, 1.0 / total_weight)
	if goal.id == context.current_goal_id:
		score += goal.inertia_bonus
	score = clampf(score, 0.0, 1.0)
	if score < goal.min_score:
		score = 0.0
	return {"score": score, "breakdown": breakdown}


func _choose_goal(context: AiUtilityContext, profile: AiUtilityProfile, scored: Array[Dictionary], current_entry: Dictionary) -> Dictionary:
	var best := _highest_scored_entry(scored)
	var emergency := _highest_emergency_entry(scored)
	if context.current_goal_id != &"" and context.current_goal_lock_until > context.sim_time and emergency.is_empty():
		if not current_entry.is_empty():
			return current_entry
		var current_goal := profile.get_goal(context.current_goal_id)
		if current_goal != null:
			return {"goal": current_goal, "score": 0.0, "target": {"found": false, "score": 0.0, "reason": "Locked current goal"}}
	if not emergency.is_empty() and float(emergency.get("score", 0.0)) > 0.0:
		return emergency
	if best.is_empty() or float(best.get("score", 0.0)) <= 0.0:
		var fallback := profile.get_fallback_goal()
		if fallback != null:
			return {"goal": fallback, "score": maxf(fallback.min_score, 0.01), "target": {"found": false, "score": 1.0, "reason": "Fallback"}}
		return {}
	if context.current_goal_id != &"" and not current_entry.is_empty():
		var current_goal := current_entry.get("goal") as AiUtilityGoal
		var best_goal := best.get("goal") as AiUtilityGoal
		if current_goal != null and best_goal != null and best_goal.id != current_goal.id:
			var current_score := float(current_entry.get("score", 0.0))
			if float(best.get("score", 0.0)) < current_score + current_goal.switch_threshold:
				return current_entry
	return best


func _highest_scored_entry(scored: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1.0
	for entry in scored:
		var score := float(entry.get("score", 0.0))
		if score > best_score:
			best = entry
			best_score = score
	return best


func _highest_emergency_entry(scored: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0.0
	for entry in scored:
		var goal := entry.get("goal") as AiUtilityGoal
		var score := float(entry.get("score", 0.0))
		if goal != null and goal.emergency and score > best_score:
			best = entry
			best_score = score
	return best


func _is_goal_on_cooldown(goal: AiUtilityGoal, context: AiUtilityContext) -> bool:
	return goal != null and context != null and context.get_goal_cooldown_until(goal.id) > context.sim_time


func _apply_entry_to_result(result: AiUtilityDecisionResult, entry: Dictionary) -> void:
	if result == null or entry.is_empty():
		return
	var goal := entry.get("goal") as AiUtilityGoal
	if goal == null:
		return
	var target: Dictionary = entry.get("target", {})
	result.goal = goal
	result.selected_goal_id = goal.id
	result.selected_score = clampf(float(entry.get("score", 0.0)), 0.0, 1.0)
	result.executor_key = goal.executor_key
	result.target_entity_id = str(target.get("entity_id", ""))
	result.target_position = target.get("position", Vector3.ZERO)
	result.has_target_position = bool(target.get("has_position", false))
	result.target = target.get("target", null)
	result.target_data = (target.get("data", {}) as Dictionary).duplicate(false)
	result.reason_string = "%s score=%.3f" % [goal.get_debug_label(), result.selected_score]
