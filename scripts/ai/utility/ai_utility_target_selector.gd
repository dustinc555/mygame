extends RefCounted

class_name AiUtilityTargetSelector


func select_target(goal: AiUtilityGoal, _entity_id: String, context: AiUtilityContext) -> Dictionary:
	if goal == null or context == null or goal.target_selector_id == &"":
		return {"found": false, "score": 0.0, "reason": "No target selector"}
	var candidates := context.get_targets(goal.target_selector_id)
	var best: Dictionary = {}
	var best_score := -1.0
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value if candidate_value is Dictionary else {"target": candidate_value}
		if bool(candidate.get("blocked", false)):
			continue
		var score := clampf(float(candidate.get("score", 1.0)), 0.0, 1.0)
		if score > best_score:
			best = candidate
			best_score = score
	if best_score < 0.0:
		return {"found": false, "score": 0.0, "reason": "No cached target candidates"}
	return {
		"found": true,
		"entity_id": str(best.get("entity_id", best.get("target_entity_id", ""))),
		"position": best.get("position", Vector3.ZERO),
		"has_position": best.has("position"),
		"target": best.get("target", null),
		"data": best.duplicate(false),
		"score": clampf(best_score, 0.0, 1.0),
		"reason": str(best.get("reason", "cached target")),
	}
