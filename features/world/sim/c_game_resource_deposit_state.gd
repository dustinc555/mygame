class_name CGameResourceDepositState
extends "res://addons/gecs/ecs/component.gd"
## Durable independent stock. No live nodes or Resource references are saved.
@export var deposit_id := ""
@export var deposit_type_id := ""
@export var definition_path := ""
@export var stock := 0
@export var refill_at_minute := -1.0
@export var revision := 0

func to_state() -> Dictionary:
	return {"deposit_id": deposit_id, "deposit_type_id": deposit_type_id,
		"definition_path": definition_path, "stock": stock,
		"refill_at_minute": refill_at_minute, "revision": revision}

func apply_state(state: Dictionary) -> void:
	deposit_id = str(state.get("deposit_id", deposit_id))
	deposit_type_id = str(state.get("deposit_type_id", deposit_type_id))
	definition_path = str(state.get("definition_path", definition_path))
	stock = maxi(0, int(state.get("stock", stock)))
	refill_at_minute = float(state.get("refill_at_minute", refill_at_minute))
	if stock > 0 or not is_finite(refill_at_minute):
		refill_at_minute = -1.0
	revision = maxi(0, int(state.get("revision", revision)))
