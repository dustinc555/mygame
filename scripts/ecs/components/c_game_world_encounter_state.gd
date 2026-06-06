extends "res://addons/gecs/ecs/component.gd"

class_name CGameWorldEncounterState

@export var state_id := "world_encounters"
@export var encounters_by_id: Dictionary = {}
@export var active_pair_keys: Dictionary = {}
@export var next_encounter_id := 1
@export var encounter_range := 30.0
@export var spatial_bin_size := 60.0
@export var hostile_threshold := -50
@export var encounter_log: Array[Dictionary] = []


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	encounters_by_id = (source.get("encounters_by_id", encounters_by_id) as Dictionary).duplicate(true)
	active_pair_keys = (source.get("active_pair_keys", active_pair_keys) as Dictionary).duplicate(true)
	next_encounter_id = int(source.get("next_encounter_id", next_encounter_id))
	encounter_range = float(source.get("encounter_range", encounter_range))
	spatial_bin_size = float(source.get("spatial_bin_size", spatial_bin_size))
	hostile_threshold = int(source.get("hostile_threshold", hostile_threshold))
	encounter_log = _dictionary_array(source.get("encounter_log", encounter_log))


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"encounters_by_id": encounters_by_id.duplicate(true),
		"active_pair_keys": active_pair_keys.duplicate(true),
		"next_encounter_id": next_encounter_id,
		"encounter_range": encounter_range,
		"spatial_bin_size": spatial_bin_size,
		"hostile_threshold": hostile_threshold,
		"encounter_log": encounter_log.duplicate(true),
	}


func _dictionary_array(value) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for entry in value:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result
