extends "res://addons/gecs/ecs/component.gd"

class_name CGameJobProviderMemory

@export var memory_id := ""
@export var provider_id := ""
@export var actor_id := ""
@export var job_id := ""
@export var reason := ""
@export var recorded_at := 0.0
@export var note := ""


func apply_data(data: Dictionary) -> void:
	memory_id = str(data.get("memory_id", memory_id))
	provider_id = str(data.get("provider_id", provider_id))
	actor_id = str(data.get("actor_id", actor_id))
	job_id = str(data.get("job_id", job_id))
	reason = str(data.get("reason", reason))
	recorded_at = float(data.get("recorded_at", recorded_at))
	note = str(data.get("note", note))


func to_dictionary() -> Dictionary:
	return {
		"memory_id": memory_id,
		"provider_id": provider_id,
		"actor_id": actor_id,
		"job_id": job_id,
		"reason": reason,
		"recorded_at": recorded_at,
		"note": note,
	}
