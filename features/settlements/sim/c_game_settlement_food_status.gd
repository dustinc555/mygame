extends "res://addons/gecs/ecs/component.gd"

class_name CGameSettlementFoodStatus

@export var settlement_id := ""
@export var item_counts: Dictionary = {}
@export var food_type_counts: Dictionary = {}
@export var food_type_units: Dictionary = {}
@export var food_units := 0.0
@export var demand_per_day := 0.0
@export var production_per_day := 0.0
@export var net_per_day := 0.0
@export var reserve_days := 0.0
@export var reserve_state := "zero_demand"
@export var pressure_state := "supplied"
@export var last_processed_day := -1
@export var last_consumed := 0.0
@export var last_produced := 0.0
@export var last_consumed_item_counts: Dictionary = {}
@export var last_produced_item_counts: Dictionary = {}
@export var last_shortfall := 0.0
@export var update_revision := 0


func apply_status(source: Dictionary) -> void:
	settlement_id = str(source.get("settlement_id", settlement_id))
	item_counts = (source.get("item_counts", item_counts) as Dictionary).duplicate(true)
	food_type_counts = (source.get("food_type_counts", food_type_counts) as Dictionary).duplicate(true)
	food_type_units = (source.get("food_type_units", food_type_units) as Dictionary).duplicate(true)
	food_units = float(source.get("food_units", food_units))
	demand_per_day = float(source.get("demand_per_day", demand_per_day))
	production_per_day = float(source.get("production_per_day", production_per_day))
	net_per_day = float(source.get("net_per_day", net_per_day))
	reserve_days = float(source.get("reserve_days", reserve_days))
	reserve_state = str(source.get("reserve_state", reserve_state))
	pressure_state = str(source.get("pressure_state", pressure_state))
	last_processed_day = int(source.get("last_processed_day", last_processed_day))
	last_consumed = float(source.get("last_consumed", last_consumed))
	last_produced = float(source.get("last_produced", last_produced))
	last_consumed_item_counts = (source.get("last_consumed_item_counts", last_consumed_item_counts) as Dictionary).duplicate(true)
	last_produced_item_counts = (source.get("last_produced_item_counts", last_produced_item_counts) as Dictionary).duplicate(true)
	last_shortfall = float(source.get("last_shortfall", last_shortfall))
	update_revision = int(source.get("update_revision", update_revision))


func to_status() -> Dictionary:
	return {
		"settlement_id": settlement_id,
		"item_counts": item_counts.duplicate(true),
		"food_type_counts": food_type_counts.duplicate(true),
		"food_type_units": food_type_units.duplicate(true),
		"food_units": food_units,
		"demand_per_day": demand_per_day,
		"production_per_day": production_per_day,
		"net_per_day": net_per_day,
		"reserve_days": reserve_days,
		"reserve_state": reserve_state,
		"pressure_state": pressure_state,
		"last_processed_day": last_processed_day,
		"last_consumed": last_consumed,
		"last_produced": last_produced,
		"last_consumed_item_counts": last_consumed_item_counts.duplicate(true),
		"last_produced_item_counts": last_produced_item_counts.duplicate(true),
		"last_shortfall": last_shortfall,
		"update_revision": update_revision,
	}
