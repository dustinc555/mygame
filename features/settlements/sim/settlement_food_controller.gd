extends Node

class_name SettlementFoodController

const SERVICE_ID := &"settlement_food"
const PRESSURE_SUPPLIED := "supplied"
const PRESSURE_HUNGRY := "hungry"
const PRESSURE_STARVING := "starving"

signal food_status_changed(settlement_id: String, status: Dictionary)

var _world_time: WorldTimeController
var _stock: InventoryStockController
var _settlements: SettlementController
var _population: Node
var _gecs: GecsWorldController
var _statuses: Dictionary = {}
var _processing_day_settlement_ids: Dictionary = {}
var _queued_population_refresh_ids: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_world_time = context.require(WorldTimeController.SERVICE_ID) as WorldTimeController
	_stock = context.require(InventoryStockController.SERVICE_ID) as InventoryStockController
	_settlements = context.require(SettlementController.SERVICE_ID) as SettlementController
	_population = context.require(&"population")
	_gecs = context.require(GecsWorldController.SERVICE_ID) as GecsWorldController
	_world_time.hour_changed.connect(_on_hour_changed)
	_stock.stock_changed.connect(_on_stock_changed)
	if _population.has_signal("population_record_changed"):
		_population.connect("population_record_changed", _on_population_record_changed)
	_settlements.settlement_registered.connect(_on_settlement_registered)
	_gecs.world_reindexed.connect(_rebuild_from_gecs)
	_rebuild_from_gecs()


func get_status(settlement_id: String) -> Dictionary:
	return (_statuses.get(settlement_id, {}) as Dictionary).duplicate(true)


func get_all_statuses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for status in _statuses.values():
		result.append((status as Dictionary).duplicate(true))
	return result


func refresh_status(settlement_id: String) -> Dictionary:
	var definition := _settlements.get_settlement_definition(settlement_id) as SettlementDefinition
	if definition == null:
		return {}
	var previous := _statuses.get(settlement_id, {}) as Dictionary
	var stock := _stock.get_settlement_stock_snapshot(settlement_id)
	var demand := _daily_demand(settlement_id, definition)
	var production := _daily_production(definition, _settlements.get_settlement_state(settlement_id))
	var food_units := _sum_floats(stock.get("food_units", {}) as Dictionary)
	var reserve_days := 0.0
	var reserve_state := "finite"
	if demand <= 0.0:
		reserve_days = -1.0
		reserve_state = "zero_demand"
	elif production >= demand:
		reserve_days = -1.0
		reserve_state = "sustainable"
	else:
		reserve_days = food_units / maxf(demand - production, 0.001)
	var pressure := PRESSURE_SUPPLIED
	if float(previous.get("last_shortfall", 0.0)) > 0.0 or (demand > 0.0 and food_units <= 0.0):
		pressure = PRESSURE_STARVING
	elif reserve_state == "finite" and reserve_days < 3.0:
		pressure = PRESSURE_HUNGRY
	var status := {
		"settlement_id": settlement_id,
		"item_counts": (stock.get("items", {}) as Dictionary).duplicate(true),
		"food_type_counts": (stock.get("food_types", {}) as Dictionary).duplicate(true),
		"food_type_units": (stock.get("food_units", {}) as Dictionary).duplicate(true),
		"food_units": food_units,
		"demand_per_day": demand,
		"production_per_day": production,
		"net_per_day": production - demand,
		"reserve_days": reserve_days,
		"reserve_state": reserve_state,
		"pressure_state": pressure,
		"last_processed_day": int(previous.get("last_processed_day", -1)),
		"last_consumed": float(previous.get("last_consumed", 0.0)),
		"last_produced": float(previous.get("last_produced", 0.0)),
		"last_consumed_item_counts": (previous.get("last_consumed_item_counts", {}) as Dictionary).duplicate(true),
		"last_produced_item_counts": (previous.get("last_produced_item_counts", {}) as Dictionary).duplicate(true),
		"last_shortfall": float(previous.get("last_shortfall", 0.0)),
		"update_revision": int(previous.get("update_revision", 0)) + 1,
	}
	_store_status(settlement_id, status)
	var anchor := _settlements.get_settlement_anchor(settlement_id)
	if anchor != null and anchor.has_method("apply_settlement_food_status"):
		anchor.call("apply_settlement_food_status", status)
	return status.duplicate(true)


func transfer_food_units(source_settlement_id: String, target_settlement_id: String, requested_units: float) -> float:
	var transfer := _stock.transfer_food_units(source_settlement_id, target_settlement_id, requested_units)
	return float(transfer.get("food_units", 0.0))


func consume_food_units(settlement_id: String, requested_units: float) -> float:
	return float(_stock.consume_food_units(settlement_id, requested_units).get("food_units", 0.0))


func _bootstrap_registered_settlements() -> void:
	for settlement_id in _settlements.settlement_definitions.keys():
		_on_settlement_registered(str(settlement_id), _settlements.get_settlement_definition(str(settlement_id)))


func _on_settlement_registered(settlement_id: String, definition: Resource) -> void:
	call_deferred("_apply_settlement_registration", settlement_id, definition)


func _apply_settlement_registration(settlement_id: String, definition: Resource) -> void:
	var typed_definition := definition as SettlementDefinition
	if typed_definition == null:
		return
	for seed in Array(typed_definition.get("storage_seeds")):
		_stock.ensure_seeded_container(settlement_id, seed)
	var output_paths := PackedStringArray()
	for record in (_settlements.get_settlement_state(settlement_id).get("facilities", {}) as Dictionary).values():
		if not (record is Dictionary):
			continue
		for output in Array(record.get("food_outputs_per_day", [])):
			var path := str(output.get("item_definition_path", "")) if output is Dictionary else ""
			if not path.is_empty():
				output_paths.append(path)
	_stock.prime_item_definition_paths(output_paths)
	refresh_status(settlement_id)


func _on_hour_changed(_absolute_hour: int, day_index: int, hour: int) -> void:
	for settlement_id_value in _settlements.settlement_definitions.keys():
		var settlement_id := str(settlement_id_value)
		var definition := _settlements.get_settlement_definition(settlement_id) as SettlementDefinition
		if definition == null:
			continue
		var profile := definition.get_behavior_profile() as SettlementBehaviorProfile
		if profile == null or hour != profile.daily_upkeep_hour:
			continue
		var status := _statuses.get(settlement_id, {}) as Dictionary
		if int(status.get("last_processed_day", -1)) == day_index:
			continue
		_process_day(settlement_id, definition, day_index)


func _process_day(settlement_id: String, definition: SettlementDefinition, day_index: int) -> void:
	_processing_day_settlement_ids[settlement_id] = true
	var outputs := _production_outputs(definition, _settlements.get_settlement_state(settlement_id))
	var production_result := _stock.add_production_outputs(settlement_id, outputs)
	var produced := float(production_result.get("food_units", 0.0))
	var demand := _daily_demand(settlement_id, definition)
	var consumption_result := _stock.consume_food_units(settlement_id, demand)
	var consumed := float(consumption_result.get("food_units", 0.0))
	var status := _statuses.get(settlement_id, {}) as Dictionary
	status["last_processed_day"] = day_index
	status["last_produced"] = produced
	status["last_consumed"] = consumed
	status["last_produced_item_counts"] = _stock.normalize_item_counts(production_result.get("items", {}) as Dictionary)
	status["last_consumed_item_counts"] = _stock.normalize_item_counts(consumption_result.get("items", {}) as Dictionary)
	status["last_shortfall"] = maxf(demand - consumed, 0.0)
	_statuses[settlement_id] = status
	_processing_day_settlement_ids.erase(settlement_id)
	refresh_status(settlement_id)


func _daily_demand(settlement_id: String, definition: SettlementDefinition) -> float:
	var profile := definition.get_behavior_profile() as SettlementBehaviorProfile
	if profile == null:
		return 0.0
	var population_count := int(_settlements.get_settlement_state(settlement_id).get("population", 0))
	if _population != null and _population.has_method("count_alive_records_for_settlement"):
		population_count = int(_population.call("count_alive_records_for_settlement", settlement_id))
	return maxf(float(population_count) * profile.food_units_per_person_per_day, 0.0)


func _daily_production(definition: SettlementDefinition, state: Dictionary) -> float:
	var total := 0.0
	for output in _production_outputs(definition, state):
		if output == null:
			continue
		var item := output.get("item") as ItemDefinition
		if item != null:
			total += item.settlement_food_units * int(output.get("count"))
		elif output is Dictionary:
			total += float(output.get("food_units_per_item", 0.0)) * int(output.get("count", 0))
	return total


func _production_outputs(definition: SettlementDefinition, state: Dictionary) -> Array:
	var outputs: Array = []
	var profile := definition.get_behavior_profile() as SettlementBehaviorProfile
	var settlement_id := str(state.get("settlement_id", definition.settlement_id))
	var physical_farming := _gecs != null and _gecs.has_method("has_active_farm_plot_for_settlement") \
			and bool(_gecs.call("has_active_farm_plot_for_settlement", settlement_id))
	if profile != null and not physical_farming:
		outputs.append_array(Array(profile.get("food_outputs_per_day")))
	for record in (state.get("facilities", {}) as Dictionary).values():
		if record is Dictionary and bool(record.get("enabled", true)):
			outputs.append_array(Array(record.get("food_outputs_per_day", [])))
	return outputs


func _on_stock_changed(settlement_id: String, _facility_id: String) -> void:
	if not _processing_day_settlement_ids.has(settlement_id) and _settlements.get_settlement_definition(settlement_id) != null:
		refresh_status(settlement_id)


func _on_population_record_changed(settlement_id: String, _actor_id: String) -> void:
	if settlement_id.is_empty() or _settlements.get_settlement_definition(settlement_id) == null:
		return
	var was_empty := _queued_population_refresh_ids.is_empty()
	_queued_population_refresh_ids[settlement_id] = true
	if was_empty:
		_flush_population_refreshes.call_deferred()


func _flush_population_refreshes() -> void:
	var settlement_ids := _queued_population_refresh_ids.keys()
	_queued_population_refresh_ids.clear()
	for settlement_id in settlement_ids:
		refresh_status(str(settlement_id))


func _store_status(settlement_id: String, status: Dictionary) -> void:
	_statuses[settlement_id] = status.duplicate(true)
	_gecs.upsert_settlement_food_status(settlement_id, status)
	food_status_changed.emit(settlement_id, status.duplicate(true))


func _rebuild_from_gecs() -> void:
	_statuses = _gecs.get_settlement_food_statuses() if _gecs != null else {}
	# Old saves predate physical stock records. Reapplying authored seeds is
	# idempotent and supplies the best-fit migration without duplicate stacks.
	call_deferred("_bootstrap_registered_settlements")


func _sum_floats(values: Dictionary) -> float:
	var total := 0.0
	for value in values.values():
		total += float(value)
	return total
