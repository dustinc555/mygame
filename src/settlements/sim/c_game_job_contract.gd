extends "res://addons/gecs/ecs/component.gd"

class_name CGameJobContract

@export var contract_id := ""
@export var actor_id := ""
@export var provider_id := ""
@export var provider_name := ""
@export var provider_path: NodePath
@export var provider_owner_actor_id := ""
@export var job_id := ""
@export var job_index := -1
@export var algorithm_id := ""
@export var display_name := "Job"
@export var priority_order := 0
@export var status := "active"
@export var hired_at := 0.0
@export var next_shift_time := 0.0
@export var report_deadline := 0.0
@export var shift_end_time := 0.0
@export var last_started_at := -1.0
@export var owed_currency := 0
@export var metadata: Dictionary = {}


func apply_data(data: Dictionary) -> void:
	contract_id = str(data.get("contract_id", contract_id))
	actor_id = str(data.get("actor_id", actor_id))
	provider_id = str(data.get("provider_id", provider_id))
	provider_name = str(data.get("provider_name", provider_name))
	provider_path = data.get("provider_path", provider_path)
	provider_owner_actor_id = str(data.get("provider_owner_actor_id", provider_owner_actor_id))
	job_id = str(data.get("job_id", job_id))
	job_index = int(data.get("job_index", job_index))
	algorithm_id = str(data.get("algorithm_id", algorithm_id))
	display_name = str(data.get("display_name", display_name))
	priority_order = int(data.get("priority_order", priority_order))
	status = str(data.get("status", status))
	hired_at = float(data.get("hired_at", hired_at))
	next_shift_time = float(data.get("next_shift_time", next_shift_time))
	report_deadline = float(data.get("report_deadline", report_deadline))
	shift_end_time = float(data.get("shift_end_time", shift_end_time))
	last_started_at = float(data.get("last_started_at", last_started_at))
	owed_currency = int(data.get("owed_currency", owed_currency))
	metadata = (data.get("metadata", metadata) as Dictionary).duplicate(true)


func to_dictionary() -> Dictionary:
	return {
		"contract_id": contract_id,
		"actor_id": actor_id,
		"provider_id": provider_id,
		"provider_name": provider_name,
		"provider_path": provider_path,
		"provider_owner_actor_id": provider_owner_actor_id,
		"job_id": job_id,
		"job_index": job_index,
		"algorithm_id": algorithm_id,
		"display_name": display_name,
		"priority_order": priority_order,
		"status": status,
		"hired_at": hired_at,
		"next_shift_time": next_shift_time,
		"report_deadline": report_deadline,
		"shift_end_time": shift_end_time,
		"last_started_at": last_started_at,
		"owed_currency": owed_currency,
		"metadata": metadata.duplicate(true),
	}
