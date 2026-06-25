extends "res://addons/gecs/ecs/component.gd"

class_name CGameLedgerSimulationState

@export var state_id := "ledger_simulation"
@export var last_processed_minute := -1
@export var last_batch_summary: Dictionary = {}


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	last_processed_minute = int(source.get("last_processed_minute", last_processed_minute))
	last_batch_summary = (source.get("last_batch_summary", last_batch_summary) as Dictionary).duplicate(true)


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"last_processed_minute": last_processed_minute,
		"last_batch_summary": last_batch_summary.duplicate(true),
	}
