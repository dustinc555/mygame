extends RefCounted

class_name AiPackage

var package_id := ""
var role_id := ""
var priority := 0
var clears_existing_jobs := false
var allowed_job_types: PackedInt32Array = PackedInt32Array()


func allows_job_type(job_type: int) -> bool:
	return allowed_job_types.is_empty() or allowed_job_types.has(job_type)
