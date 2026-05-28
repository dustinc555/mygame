extends Resource

class_name AiUtilityConsideration

@export var id: StringName = &""
@export var input_key: StringName = &""
@export_range(0.0, 16.0, 0.05) var weight := 1.0
@export var invert := false
@export var required := false
@export_range(0.0, 1.0, 0.01) var missing_value := 0.0
@export var curve: Curve
@export_multiline var explanation := ""


func score(context: AiUtilityContext) -> Dictionary:
	var missing := input_key == &"" or context == null or not context.has_fact(input_key)
	if missing and required:
		return {
			"id": str(id),
			"input_key": str(input_key),
			"raw": 0.0,
			"score": 0.0,
			"weight": weight,
			"required": required,
			"missing": true,
			"required_failed": true,
			"explanation": explanation,
		}
	var raw_value := missing_value if missing else context.get_fact(input_key, missing_value)
	if invert:
		raw_value = 1.0 - raw_value
	var consideration_score := curve.sample_baked(raw_value) if curve != null else raw_value
	consideration_score = clampf(consideration_score, 0.0, 1.0)
	return {
		"id": str(id),
		"input_key": str(input_key),
		"raw": raw_value,
		"score": consideration_score,
		"weight": maxf(weight, 0.0),
		"required": required,
		"missing": missing,
		"required_failed": required and consideration_score <= 0.0,
		"explanation": explanation,
	}
