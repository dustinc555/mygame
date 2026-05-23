extends Resource

class_name WorldSquadOperationProfile

@export var operation_id := ""
@export var display_name := "Squad Operation"
@export var start_phase_id := "travel"
@export var phases: Array[Resource] = []
@export var encamp_distance_from_border := 10.0
@export var conflict_event_radius := 35.0
@export var conflict_participation_seconds_required := 20.0


func get_phase(phase_id: String) -> Resource:
	for phase in phases:
		if phase != null and str(phase.get("phase_id")) == phase_id:
			return phase
	return null


func get_start_phase() -> Resource:
	return get_phase(start_phase_id)
