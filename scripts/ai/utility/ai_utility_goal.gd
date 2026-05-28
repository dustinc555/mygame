extends Resource

class_name AiUtilityGoal

const AI_JOB_SCRIPT := preload("res://scripts/ai/ai_job.gd")

@export var id: StringName = &""
@export var display_name := ""
@export_range(0.0, 1.0, 0.01) var min_score := 0.0
@export_range(0.0, 120.0, 0.05) var cooldown_seconds := 0.0
@export_range(0.0, 120.0, 0.05) var lock_seconds := 0.0
@export_range(0.0, 1.0, 0.01) var inertia_bonus := 0.0
@export_range(0.0, 1.0, 0.01) var switch_threshold := 0.0
@export var emergency := false
@export var executor_key: StringName = &""
@export var allowed_lod_tiers: PackedInt32Array = PackedInt32Array()
@export var target_selector_id: StringName = &""
@export var requires_target := false
@export var considerations: Array[Resource] = []
@export var job_type: int = AI_JOB_SCRIPT.JobType.NONE
@export var job_priority := -1
@export var source_id := "utility_ai"
@export var package_id := ""
@export var debug_label := ""


func is_allowed_for_lod(lod_tier: int) -> bool:
	return allowed_lod_tiers.is_empty() or allowed_lod_tiers.has(lod_tier)


func get_priority() -> int:
	if job_priority >= 0:
		return job_priority
	return AI_JOB_SCRIPT.priority_for_type(job_type)


func get_debug_label() -> String:
	if not debug_label.is_empty():
		return debug_label
	if not display_name.is_empty():
		return display_name
	return str(id)


func get_package_id() -> String:
	return package_id if not package_id.is_empty() else "utility:%s" % str(id)
