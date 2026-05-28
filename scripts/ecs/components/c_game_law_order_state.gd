extends "res://addons/gecs/ecs/component.gd"

class_name CGameLawOrderState

@export var state_id := "law_order"
@export var warrants: Dictionary = {}
@export var prisoner_records: Dictionary = {}


func apply_state(source: Dictionary) -> void:
	state_id = str(source.get("state_id", state_id))
	warrants = (source.get("warrants", warrants) as Dictionary).duplicate(true)
	prisoner_records = (source.get("prisoner_records", prisoner_records) as Dictionary).duplicate(true)


func to_state() -> Dictionary:
	return {
		"state_id": state_id,
		"warrants": warrants.duplicate(true),
		"prisoner_records": prisoner_records.duplicate(true),
	}
